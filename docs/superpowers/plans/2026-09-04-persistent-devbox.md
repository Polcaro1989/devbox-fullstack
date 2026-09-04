# Persistent Devbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each manually started Actions Server session restore the prior user's working state, including Git changes that were never committed, user configuration, permissions, symlinks, and selected tool state, while keeping only the newest verified encrypted Restic snapshot in Cloudflare R2.

**Architecture:** GitHub-hosted `ubuntu-latest` remains disposable. The workflow reconstructs the base development toolchain, initializes or opens an encrypted Restic repository on R2, restores persistent user state before SSH starts, runs periodic checkpoint saves while SSH is active, and performs a final save attempt on normal shutdown. Every save creates and verifies a new snapshot before `forget --keep-last 1 --prune` is allowed to remove prior snapshots.

**Tech Stack:** GitHub Actions, Bash, Restic, Cloudflare R2 S3 API, Tailscale, OpenSSH, existing shell-based CI.

**Spec:** `docs/superpowers/specs/2026-09-04-persistent-devbox-design.md`

## Global Constraints

- The repository is public; no R2, Restic, SSH, Tailscale, GitHub, or other secret value may be committed or printed.
- Keep exactly one verified Restic snapshot after a successful save.
- Never delete the previous known-good snapshot before the new snapshot is created and verified.
- A failed backup or verification must leave the previous snapshot untouched.
- Preserve user project `.git` directories, staged state, unstaged changes, untracked files, permissions, timestamps, and symlinks.
- Do not blindly restore the whole root filesystem or `/etc`.
- Existing Tailscale private networking and SSH behavior must continue to work.
- Do not add scheduled workflow runs, self-dispatch, workflow chaining, or automatic replacement of expired GitHub-hosted runners.
- GitHub Actions runtime internals and transient secret-bearing files under the workflow's own `_work`, `_actions`, and `_temp` areas are not persistent user state and must be excluded from snapshots.
- User development projects should live under `/home/runner/projects` or other normal user-owned home directories, not under GitHub Actions' internal runner work directories.

---

### Task 1: Define and test the persistence contract

**Files:**
- Modify: `tests/test-config.sh`
- Create: `scripts/persistence-excludes.txt`

**Interfaces:**
- Consumes: existing `require_file`, `require_literal`, and workflow-order checks in `tests/test-config.sh`.
- Produces: a static contract requiring persistence scripts, required workflow secrets, safe ordering, retention safety, and explicit exclusions.

- [ ] **Step 1: Write failing static-contract tests**

Extend the required-file list with:

```bash
scripts/setup-persistence.sh \
scripts/restore-persistence.sh \
scripts/save-persistence.sh \
scripts/persistence-excludes.txt
```

Add workflow requirements:

```bash
require_literal "$WORKFLOW" 'R2_ACCOUNT_ID: ${{ secrets.R2_ACCOUNT_ID }}'
require_literal "$WORKFLOW" 'AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}'
require_literal "$WORKFLOW" 'AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}'
require_literal "$WORKFLOW" 'RESTIC_PASSWORD: ${{ secrets.RESTIC_PASSWORD }}'
require_literal "$WORKFLOW" 'bash scripts/setup-persistence.sh'
require_literal "$WORKFLOW" 'bash scripts/restore-persistence.sh'
require_literal "$WORKFLOW" 'bash scripts/save-persistence.sh'
```

Require restore before SSH:

```bash
restore_line=$(grep -nF 'bash scripts/restore-persistence.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
server_line=$(grep -nF 'bash scripts/start-actions-server.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
[[ -n "$restore_line" && -n "$server_line" ]] || fail 'persistence restore and SSH server steps must exist'
(( restore_line < server_line )) || fail 'persistent state must restore before SSH starts'
```

Require save-script safety ordering:

```bash
SAVE=scripts/save-persistence.sh
for text in 'restic backup' 'restic snapshots' 'forget --keep-last 1 --prune' 'flock'; do
  require_literal "$SAVE" "$text"
done

backup_line=$(grep -nF 'restic backup' "$SAVE" | head -n1 | cut -d: -f1 || true)
verify_line=$(grep -nF 'restic snapshots' "$SAVE" | head -n1 | cut -d: -f1 || true)
forget_line=$(grep -nF 'forget --keep-last 1 --prune' "$SAVE" | head -n1 | cut -d: -f1 || true)
(( backup_line < verify_line && verify_line < forget_line )) || fail 'backup must be created and verified before old snapshots are pruned'
```

Require exclusions for GitHub runner internals and secret-prone files:

```bash
EXCLUDES=scripts/persistence-excludes.txt
for text in '/home/runner/work/_actions' '/home/runner/work/_temp' '.restic-cache' '.aws/credentials'; do
  require_literal "$EXCLUDES" "$text"
done
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
bash tests/test-config.sh
```

Expected: FAIL because the persistence files and workflow wiring do not exist yet.

- [ ] **Step 3: Add the initial exclusion file**

Create `scripts/persistence-excludes.txt` with:

```text
/home/runner/work/_actions
/home/runner/work/_temp
/home/runner/.cache/restic
/home/runner/.restic-cache
/home/runner/.aws/credentials
/home/runner/.config/rclone/rclone.conf
/home/runner/.local/share/Trash
/home/runner/.cache
**/.DS_Store
**/node_modules
**/bin
**/obj
```

Do not exclude `.git`, `.git/index`, user project configuration, or ordinary files under `/home/runner/projects`.

- [ ] **Step 4: Run the contract test again**

Run:

```bash
bash tests/test-config.sh
```

Expected: still FAIL, now specifically on missing scripts/workflow wiring.

- [ ] **Step 5: Commit the contract**

```bash
git add tests/test-config.sh scripts/persistence-excludes.txt
git commit -m "test: define persistent devbox contract"
```

---

### Task 2: Implement Restic/R2 setup and safe restore

**Files:**
- Create: `scripts/setup-persistence.sh`
- Create: `scripts/restore-persistence.sh`
- Modify: `tests/test-config.sh`

**Interfaces:**
- Consumes environment variables `R2_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`.
- Produces environment `RESTIC_REPOSITORY=s3:https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/devbox-fullstack` and a ready Restic repository.
- `restore-persistence.sh` restores latest state to `/home/runner` and exits non-zero on corrupt/unreadable existing state.

- [ ] **Step 1: Add failing tests for setup/restore behavior**

Add to `tests/test-config.sh`:

```bash
SETUP_PERSISTENCE=scripts/setup-persistence.sh
for text in 'set -euo pipefail' 'restic' 'RESTIC_REPOSITORY' 'r2.cloudflarestorage.com' 'restic init' 'restic snapshots'; do
  require_literal "$SETUP_PERSISTENCE" "$text"
done

RESTORE_PERSISTENCE=scripts/restore-persistence.sh
for text in 'set -euo pipefail' 'restic snapshots' 'restic restore latest' '/home/runner'; do
  require_literal "$RESTORE_PERSISTENCE" "$text"
done
```

- [ ] **Step 2: Run the contract test and verify it fails**

```bash
bash tests/test-config.sh
```

Expected: FAIL because setup/restore scripts are absent.

- [ ] **Step 3: Implement `scripts/setup-persistence.sh`**

Use strict mode, validate non-empty variables without printing them, install Restic from apt when absent, mask secrets when running in GitHub Actions, export the R2 repository endpoint through `$GITHUB_ENV`, check whether the repository exists, and initialize it only when there is no existing repository.

Core behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is required}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"

RESTIC_REPOSITORY="s3:https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/devbox-fullstack"
export RESTIC_REPOSITORY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::add-mask::$AWS_ACCESS_KEY_ID"
  echo "::add-mask::$AWS_SECRET_ACCESS_KEY"
  echo "::add-mask::$RESTIC_PASSWORD"
  echo "RESTIC_REPOSITORY=$RESTIC_REPOSITORY" >> "$GITHUB_ENV"
fi

if ! command -v restic >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y restic
fi

if ! restic snapshots >/dev/null 2>&1; then
  restic init
fi
```

Implementation must distinguish a truly absent repository from authentication/network/corruption failures; do not run `restic init` over an unreadable existing repository. Use the Restic command's error output/status to detect an absent config object, otherwise fail visibly.

- [ ] **Step 4: Implement `scripts/restore-persistence.sh`**

Core behavior:

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! restic snapshots --json | grep -q '"id"'; then
  echo 'No persistent snapshot found; starting with a fresh user state.'
  exit 0
fi

sudo -E restic restore latest --target /
sudo chown runner:runner /home/runner

echo 'Persistent user state restored.'
```

Keep ownership/mode metadata from Restic where possible. Do not recursively `chown -R` the entire home after restore because that would destroy intentionally preserved ownership metadata; only correct the home directory itself and explicit paths whose owner is known to be `runner`.

- [ ] **Step 5: Validate shell syntax and static contract**

```bash
bash -n scripts/setup-persistence.sh scripts/restore-persistence.sh
bash tests/test-config.sh
```

Expected: persistence setup/restore checks PASS; save/workflow checks may still fail until later tasks.

- [ ] **Step 6: Commit setup/restore**

```bash
git add scripts/setup-persistence.sh scripts/restore-persistence.sh tests/test-config.sh
git commit -m "feat: add encrypted R2 persistence restore"
```

---

### Task 3: Implement atomic save, verification, and keep-last-one retention

**Files:**
- Create: `scripts/save-persistence.sh`
- Create: `tests/test-persistence.sh`
- Modify: `tests/test-config.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes active Restic/R2 environment from Task 2.
- Produces one new snapshot tagged `devbox` when backup succeeds.
- Guarantees retention runs only after the new snapshot is observed.
- Uses `/tmp/devbox-restic.lock` with `flock` so periodic/manual/final saves cannot overlap.

- [ ] **Step 1: Write a failing behavior test with a local Restic repository**

Create `tests/test-persistence.sh` that uses a temporary directory and local Restic repository, creates a miniature `/home/runner`-like fixture containing executable files, symlinks, and a Git repository with staged, unstaged, and untracked changes, then invokes the save logic through environment overrides.

The fixture must include:

```bash
git init "$fixture/projects/demo"
git -C "$fixture/projects/demo" config user.email ci@example.invalid
git -C "$fixture/projects/demo" config user.name CI
echo base > "$fixture/projects/demo/tracked.txt"
git -C "$fixture/projects/demo" add tracked.txt
git -C "$fixture/projects/demo" commit -m base

echo staged > "$fixture/projects/demo/staged.txt"
git -C "$fixture/projects/demo" add staged.txt
echo modified >> "$fixture/projects/demo/tracked.txt"
echo untracked > "$fixture/projects/demo/untracked.txt"
ln -s tracked.txt "$fixture/projects/demo/tracked-link"
printf '#!/bin/sh\necho ok\n' > "$fixture/projects/demo/run.sh"
chmod 755 "$fixture/projects/demo/run.sh"
```

After two successful saves, assert:

```bash
snapshot_count=$(restic snapshots --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
[[ "$snapshot_count" == 1 ]]
```

Restore and assert:

```bash
[[ -x "$restored/projects/demo/run.sh" ]]
[[ -L "$restored/projects/demo/tracked-link" ]]
git -C "$restored/projects/demo" status --porcelain | grep -F 'A  staged.txt'
git -C "$restored/projects/demo" status --porcelain | grep -F ' M tracked.txt'
git -C "$restored/projects/demo" status --porcelain | grep -F '?? untracked.txt'
```

- [ ] **Step 2: Run the persistence test and verify it fails**

```bash
bash tests/test-persistence.sh
```

Expected: FAIL because `save-persistence.sh` does not exist yet.

- [ ] **Step 3: Implement `scripts/save-persistence.sh`**

Required sequence:

```bash
#!/usr/bin/env bash
set -euo pipefail

PERSIST_ROOT="${PERSIST_ROOT:-/home/runner}"
EXCLUDES_FILE="${PERSIST_EXCLUDES_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/persistence-excludes.txt}"
LOCK_FILE="${PERSIST_LOCK_FILE:-/tmp/devbox-restic.lock}"

exec 9>"$LOCK_FILE"
flock -w 300 9

before_ids="$(restic snapshots --json --tag devbox)"
restic backup "$PERSIST_ROOT" --tag devbox --exclude-file "$EXCLUDES_FILE"
after_json="$(restic snapshots --json --tag devbox)"

newest_id="$(printf '%s' "$after_json" | python3 -c 'import json,sys; x=json.load(sys.stdin); print(x[-1]["short_id"] if x else "")')"
[[ -n "$newest_id" ]] || { echo 'New snapshot verification failed.' >&2; exit 1; }

restic forget --keep-last 1 --tag devbox --prune
```

Strengthen verification by comparing pre-save and post-save snapshot IDs/timestamps, so an old existing snapshot cannot falsely satisfy the verification step after a failed/no-op backup.

If `restic backup` or verification fails, exit before `forget` executes.

- [ ] **Step 4: Run behavior and syntax tests**

```bash
bash -n scripts/save-persistence.sh tests/test-persistence.sh
bash tests/test-persistence.sh
bash tests/test-config.sh
```

Expected: PASS.

- [ ] **Step 5: Wire persistence behavior test into CI**

Add to `build-and-verify` in `.github/workflows/ci.yml` after the static contract:

```yaml
      - name: Persistence behavior
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y restic
          bash tests/test-persistence.sh
```

Extend Bash syntax validation:

```yaml
      - name: Validate Bash syntax
        run: bash -n entrypoint.sh scripts/*.sh tests/*.sh
```

- [ ] **Step 6: Run the CI-equivalent local checks**

```bash
bash tests/test-config.sh
bash tests/test-persistence.sh
bash -n entrypoint.sh scripts/*.sh tests/*.sh
```

Expected: PASS.

- [ ] **Step 7: Commit save/retention behavior**

```bash
git add scripts/save-persistence.sh tests/test-persistence.sh tests/test-config.sh .github/workflows/ci.yml
git commit -m "feat: retain only latest verified devbox snapshot"
```

---

### Task 4: Wire restore and periodic checkpoints into Actions Server

**Files:**
- Modify: `.github/workflows/actions-desktop.yml`
- Create: `scripts/persistence-loop.sh`
- Modify: `tests/test-config.sh`

**Interfaces:**
- Consumes scripts from Tasks 2-3 and repository secrets `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `RESTIC_PASSWORD`.
- Produces automatic restore before SSH and periodic checkpoint saves during the manually started session.
- Does not create or dispatch another GitHub Actions run.

- [ ] **Step 1: Add failing workflow-order and loop tests**

Require workflow order:

```bash
setup_persist_line=$(grep -nF 'bash scripts/setup-persistence.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
restore_line=$(grep -nF 'bash scripts/restore-persistence.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
server_line=$(grep -nF 'bash scripts/start-actions-server.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
(( setup_persist_line < restore_line && restore_line < server_line )) || fail 'persistence must initialize and restore before SSH starts'
```

Require the loop script to call only local save logic:

```bash
LOOP=scripts/persistence-loop.sh
require_literal "$LOOP" 'bash "$SCRIPT_DIR/save-persistence.sh"'
if grep -Eq 'workflow_dispatch|gh workflow run|dispatches|repository_dispatch' "$LOOP"; then
  fail 'persistence loop must not start replacement Actions runs'
fi
```

- [ ] **Step 2: Run static tests and verify they fail**

```bash
bash tests/test-config.sh
```

Expected: FAIL on missing workflow wiring/loop.

- [ ] **Step 3: Implement the periodic save loop**

Create `scripts/persistence-loop.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL_SECONDS="${PERSIST_INTERVAL_SECONDS:-600}"

while sleep "$INTERVAL_SECONDS"; do
  if ! bash "$SCRIPT_DIR/save-persistence.sh"; then
    echo '::warning::Persistent checkpoint failed; previous verified snapshot was retained.'
  fi
done
```

Default interval: 10 minutes. This limits possible lost work if the hosted runner is terminated without a usable final cleanup window.

- [ ] **Step 4: Add persistence secrets and restore steps to the workflow**

Add job environment:

```yaml
      R2_ACCOUNT_ID: ${{ secrets.R2_ACCOUNT_ID }}
      AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
      RESTIC_PASSWORD: ${{ secrets.RESTIC_PASSWORD }}
```

Extend secret validation without printing values and mask each secret.

After toolchain verification and before Tailscale/SSH, add:

```yaml
      - name: Setup persistent storage
        run: bash scripts/setup-persistence.sh

      - name: Restore persistent user state
        run: bash scripts/restore-persistence.sh
```

After SSH startup, start checkpointing:

```yaml
      - name: Start persistence checkpoints
        run: |
          nohup bash scripts/persistence-loop.sh > /tmp/devbox-persistence.log 2>&1 &
          echo $! > /tmp/devbox-persistence.pid
```

- [ ] **Step 5: Replace the simple keep-alive with a trap-backed session script**

Do not rely on a later Actions step for final save because `sleep 19800` blocks that step and cancellation may skip following steps. Put the keep-alive and best-effort final save in the same shell process:

```yaml
      - name: Keep session alive
        shell: bash
        run: |
          set -euo pipefail
          final_save() {
            echo 'Attempting final persistent checkpoint...'
            bash scripts/save-persistence.sh || echo '::warning::Final checkpoint failed; previous verified snapshot remains.'
          }
          trap final_save EXIT INT TERM
          echo 'Actions Server session is active. Cancel this workflow when you are finished.'
          sleep 19800
```

The periodic checkpoints remain the durability mechanism; the trap is only best effort.

- [ ] **Step 6: Run static and syntax tests**

```bash
bash tests/test-config.sh
bash -n scripts/persistence-loop.sh scripts/*.sh tests/*.sh
```

Expected: PASS.

- [ ] **Step 7: Commit workflow wiring**

```bash
git add .github/workflows/actions-desktop.yml scripts/persistence-loop.sh tests/test-config.sh
git commit -m "feat: restore and checkpoint Actions Server state"
```

---

### Task 5: Add user-facing manual checkpoint and verify end-to-end behavior

**Files:**
- Create: `scripts/devbox-save`
- Modify: `scripts/setup-persistence.sh`
- Modify: `tests/test-config.sh`
- Modify: `.github/workflows/ci.yml` only if needed for the new executable test.

**Interfaces:**
- Consumes `scripts/save-persistence.sh`.
- Produces a simple `devbox-save` command available in the SSH session for explicit checkpoints before risky work or before canceling the workflow.

- [ ] **Step 1: Add failing command-availability test**

In `tests/test-config.sh`:

```bash
require_file scripts/devbox-save
require_literal scripts/devbox-save 'save-persistence.sh'
require_literal scripts/setup-persistence.sh '/usr/local/bin/devbox-save'
```

- [ ] **Step 2: Run static test and verify it fails**

```bash
bash tests/test-config.sh
```

Expected: FAIL because manual checkpoint command is absent.

- [ ] **Step 3: Implement `scripts/devbox-save`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="${DEVBOX_PERSISTENCE_SCRIPT_DIR:-/opt/devbox-persistence}"
exec bash "$SCRIPT_DIR/save-persistence.sh"
```

During setup, install the persistence scripts into a stable runtime directory and expose the wrapper:

```bash
sudo install -d -m 0755 /opt/devbox-persistence
sudo install -m 0755 scripts/save-persistence.sh /opt/devbox-persistence/save-persistence.sh
sudo install -m 0644 scripts/persistence-excludes.txt /opt/devbox-persistence/persistence-excludes.txt
sudo install -m 0755 scripts/devbox-save /usr/local/bin/devbox-save
```

Adjust runtime path handling so the installed save script uses `/opt/devbox-persistence/persistence-excludes.txt` when invoked via `devbox-save`.

- [ ] **Step 4: Run the complete local verification suite**

```bash
bash tests/test-config.sh
bash tests/test-persistence.sh
bash -n entrypoint.sh scripts/*.sh tests/*.sh
```

Expected: PASS.

- [ ] **Step 5: Run existing project build/smoke checks**

```bash
docker compose config >/dev/null
docker build -t devbox-fullstack:test .
docker run --rm --entrypoint /usr/local/bin/verify-toolchain devbox-fullstack:test
ACTIONS_SERVER_SMOKE=1 SSH_PASSWORD=ci-smoke-only-not-a-real-secret TAILSCALE_IP=127.0.0.1 SSH_PORT=2222 bash scripts/start-actions-server.sh
```

Expected: existing Docker/toolchain and SSH-only server behavior remains green.

- [ ] **Step 6: Commit manual checkpoint support**

```bash
git add scripts/devbox-save scripts/setup-persistence.sh tests/test-config.sh .github/workflows/ci.yml
git commit -m "feat: add manual devbox persistence checkpoint"
```

---

### Task 6: Live R2 smoke test without leaking credentials

**Files:**
- No new committed files required unless a defect is discovered.

**Interfaces:**
- Consumes repository secrets configured by the user in GitHub Actions.
- Produces evidence that one manually started Actions Server can save state and a later manually started Actions Server can restore it.

- [ ] **Step 1: Configure repository secrets through GitHub Settings**

Required secret names:

```text
R2_ACCOUNT_ID
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
RESTIC_PASSWORD
```

Use a dedicated Cloudflare R2 bucket/API token scoped to this devbox. Do not paste secret values into chat, workflow logs, repository files, or issue/PR comments.

- [ ] **Step 2: Start one Actions Server run manually and create a persistence fixture over SSH**

```bash
mkdir -p ~/projects/persistence-smoke
cd ~/projects/persistence-smoke
git init
git config user.email smoke@example.invalid
git config user.name Smoke
echo base > tracked.txt
git add tracked.txt
git commit -m base
echo staged > staged.txt
git add staged.txt
echo changed >> tracked.txt
echo untracked > untracked.txt
printf '#!/bin/sh\necho persisted\n' > executable.sh
chmod 755 executable.sh
ln -s tracked.txt tracked-link
devbox-save
git status --porcelain
```

Expected Git status includes staged, unstaged, and untracked state.

- [ ] **Step 3: Verify retention on the live repository**

Run without revealing secrets:

```bash
restic snapshots --tag devbox
```

Expected: exactly one retained snapshot after a completed checkpoint/prune cycle.

- [ ] **Step 4: End the first workflow manually and start a second Actions Server workflow manually**

Do not add workflow chaining or auto-restart logic.

- [ ] **Step 5: Verify the restored state in the new VM**

```bash
cd ~/projects/persistence-smoke
git status --porcelain
test -x executable.sh
test -L tracked-link
cat tracked.txt
cat untracked.txt
```

Expected: staged/unstaged/untracked Git state, executable permission, symlink, and file contents match the previous session.

- [ ] **Step 6: Verify newest-only retention after another manual save**

```bash
devbox-save
restic snapshots --tag devbox
```

Expected: one snapshot remains. If the save or verification fails, the previous known-good snapshot remains instead of being deleted.

- [ ] **Step 7: Final review before merge/completion**

Check that CI is green, inspect workflow logs for accidental secret output, confirm no `schedule`, `workflow_run`, `repository_dispatch`, or workflow-dispatch API chaining was introduced, and confirm the existing Tailscale + OpenSSH path still works.
