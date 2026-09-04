# Git-backed Persistent Devbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist useful `/home/runner` state across manually started GitHub-hosted Actions Server sessions by storing one encrypted, verified snapshot in the private Git repository `Polcaro1989/Repository-`.

**Architecture:** The runner remains ephemeral. Bash scripts archive `/home/runner`, exclude rebuildable/runtime-heavy data, compress with zstd, encrypt with GnuPG, split into sub-100 MB chunks, and publish a single orphan commit to a `devbox-state` branch. The next run restores that state before SSH starts. A 15-minute checkpoint loop plus a final save runs well before the 355-minute job timeout.

**Tech Stack:** GitHub Actions, Bash, Git, GNU tar, zstd, GnuPG, Tailscale, OpenSSH.

**Spec:** `docs/superpowers/specs/2026-09-04-git-persistent-devbox-design.md`

## Global Constraints

- `devbox-fullstack` stays public; state data and credentials never enter it.
- `Polcaro1989/Repository-` is the private state repository.
- Production requires `DEVBOX_STATE_TOKEN` and `DEVBOX_STATE_PASSWORD` Actions secrets.
- The state branch must contain one reachable orphan commit after every successful save.
- Never replace the previous remote state until the new encrypted archive passes checksum/decrypt/tar verification.
- Preserve `.git`, staged/unstaged/untracked changes, modes, timestamps, and symlinks.
- Exclude GitHub Actions `work/` and rebuildable tool/cache trees.
- No scheduled trigger, self-dispatch, workflow chaining, or automatic runner replacement.

---

### Task 1: Define persistence contract and local Git-state behavior test

**Files:**
- Create: `scripts/state-excludes.txt`
- Create: `tests/test-git-state.sh`
- Modify: `tests/test-config.sh`

**Interfaces:**
- Tests require the new save/restore/session scripts and workflow wiring.
- `tests/test-git-state.sh` uses `DEVBOX_STATE_REMOTE_URL` pointing to a local bare repository.

- [ ] Add required-file and workflow-order assertions to `tests/test-config.sh`.
- [ ] Add exclusions that preserve `.git` but remove `work/`, SDK copies, package caches, and common generated outputs.
- [ ] Build a local behavior test fixture containing a nested Git repository with staged, unstaged, and untracked changes, an executable, and a symlink.
- [ ] Verify the test fails before implementation exists.

### Task 2: Implement Git state common/auth helpers and safe restore

**Files:**
- Create: `scripts/state-common.sh`
- Create: `scripts/restore-git-state.sh`

**Interfaces:**
- Production consumes `DEVBOX_STATE_REPO`, `DEVBOX_STATE_TOKEN`, `DEVBOX_STATE_PASSWORD`, optional `DEVBOX_STATE_BRANCH`.
- Tests consume `DEVBOX_STATE_REMOTE_URL` and `DEVBOX_STATE_PASSWORD` without a token.
- `state_git` runs authenticated Git without embedding the token in remote URLs.

- [ ] Validate environment without printing secrets.
- [ ] Create a temporary `GIT_ASKPASS` helper when a token is needed.
- [ ] Probe/fetch `devbox-state`; treat a missing branch as first boot and authentication/fetch errors as fatal.
- [ ] Reassemble chunks, verify SHA-256, decrypt with GnuPG, reject unsafe tar paths, and restore metadata into the persistent root.
- [ ] Run shell syntax/static tests.

### Task 3: Implement verified save and one-commit replacement

**Files:**
- Create: `scripts/save-git-state.sh`

**Interfaces:**
- Consumes `PERSIST_ROOT` (default `/home/runner`), exclusions file, state repo settings, encryption password, chunk/max-size settings.
- Produces an orphan commit on `devbox-state` containing `state.part-*`, `manifest.sha256`, and `metadata.txt`.

- [ ] Acquire `flock`.
- [ ] tar + zstd the persistent root using the exclusions file.
- [ ] Encrypt with GnuPG AES-256 using a temporary mode-0600 passphrase file.
- [ ] Verify checksum and decrypt/list round trip before publication.
- [ ] Enforce 1.5 GB encrypted-size guard.
- [ ] Split into 90 MiB chunks.
- [ ] Create a brand-new orphan commit with no parent and force-push only after verification.
- [ ] Run behavior test twice and assert the branch has one reachable commit and restores only newest state.

### Task 4: Add periodic checkpoint session loop

**Files:**
- Create: `scripts/state-session-loop.sh`

**Interfaces:**
- `DEVBOX_CHECKPOINT_SECONDS` default `900`.
- `DEVBOX_SESSION_SECONDS` default `19200`.
- Calls `save-git-state.sh` serially and attempts a final save on normal exit/TERM/INT.

- [ ] Implement 15-minute checkpoint loop with bounded total duration.
- [ ] Fail a checkpoint visibly but keep the SSH session alive when an older valid remote state still exists.
- [ ] Attempt final save on normal loop completion and catchable termination.

### Task 5: Wire persistence into Actions Server and CI

**Files:**
- Modify: `.github/workflows/actions-desktop.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `tests/test-config.sh`

**Interfaces:**
- Workflow env includes `DEVBOX_STATE_REPO=Polcaro1989/Repository-`, `DEVBOX_STATE_TOKEN`, `DEVBOX_STATE_PASSWORD`, `DEVBOX_STATE_BRANCH=devbox-state`.
- Restore happens after base toolchain verification and before Tailscale/SSH.
- Long-running session uses `state-session-loop.sh` instead of a raw `sleep`.
- Final `if: always()` save provides a redundant normal/cancel cleanup attempt.

- [ ] Set `actions/checkout` `persist-credentials: false`.
- [ ] Validate/mask state secrets.
- [ ] Install state dependencies, restore before SSH, run checkpoint loop, and add final save.
- [ ] Add local behavior test to CI and validate all shell scripts with `bash -n`.
- [ ] Confirm static tests forbid R2/B2 dependencies and still forbid schedule/self-dispatch chaining.

### Task 6: Verify and ship through PR

**Files:** all changed files above.

- [ ] Run CI-equivalent static/behavior/syntax checks through GitHub Actions.
- [ ] Review PR diff for secret leakage and unsafe state scope.
- [ ] Confirm existing SSH/Tailscale smoke test remains green.
- [ ] Merge only after checks pass.
- [ ] User creates `DEVBOX_STATE_TOKEN` and `DEVBOX_STATE_PASSWORD` secrets before starting the new Actions Server.
