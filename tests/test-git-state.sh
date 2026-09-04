#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for command_name in git tar zstd gpg sha256sum split flock; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing test dependency: $command_name"
done

tmp="$(mktemp -d /tmp/devbox-state-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

bare_repo="$tmp/state.git"
fixture="$tmp/home"
restored="$tmp/restored"
wrong_restore="$tmp/wrong-restore"
git init -q --bare "$bare_repo"
mkdir -p "$fixture/projects/demo"

git -C "$fixture/projects/demo" init -q
git -C "$fixture/projects/demo" config user.email ci@example.invalid
git -C "$fixture/projects/demo" config user.name CI
printf 'base\n' > "$fixture/projects/demo/tracked.txt"
git -C "$fixture/projects/demo" add tracked.txt
git -C "$fixture/projects/demo" commit -q -m base

printf 'staged\n' > "$fixture/projects/demo/staged.txt"
git -C "$fixture/projects/demo" add staged.txt
printf 'modified\n' >> "$fixture/projects/demo/tracked.txt"
printf 'untracked\n' > "$fixture/projects/demo/untracked.txt"
ln -s tracked.txt "$fixture/projects/demo/tracked-link"
printf '#!/usr/bin/env bash\necho ok\n' > "$fixture/projects/demo/run.sh"
chmod 755 "$fixture/projects/demo/run.sh"
printf 'remove me\n' > "$fixture/obsolete.txt"
mkdir -p "$fixture/.config/devbox"
printf 'setting=true\n' > "$fixture/.config/devbox/settings.conf"

export DEVBOX_STATE_REMOTE_URL="$bare_repo"
export DEVBOX_STATE_PASSWORD='ci-only-state-password-not-a-real-secret'
export DEVBOX_STATE_BRANCH='devbox-state'
export DEVBOX_STATE_CHUNK_BYTES='16K'
export DEVBOX_STATE_MAX_BYTES='100000000'
export PERSIST_EXCLUDES_FILE="$ROOT_DIR/scripts/state-excludes.txt"
export PERSIST_LOCK_FILE="$tmp/state.lock"
export PERSIST_ROOT="$fixture"

bash scripts/save-git-state.sh
[[ -f "$fixture/obsolete.txt" ]] || fail 'test setup lost obsolete file before second snapshot'

rm "$fixture/obsolete.txt"
printf 'latest\n' > "$fixture/latest-only.txt"
bash scripts/save-git-state.sh

commit_count="$(git --git-dir="$bare_repo" rev-list --count refs/heads/devbox-state)"
[[ "$commit_count" == '1' ]] || fail "state branch must have exactly one reachable commit, got $commit_count"
if git --git-dir="$bare_repo" cat-file -p refs/heads/devbox-state | grep -q '^parent '; then
  fail 'latest state commit must be orphaned and have no parent'
fi

mapfile -t state_files < <(git --git-dir="$bare_repo" ls-tree -r --name-only refs/heads/devbox-state)
(( ${#state_files[@]} >= 4 )) || fail 'state branch contains too few files'
for state_file in "${state_files[@]}"; do
  case "$state_file" in
    content.sha256|manifest.sha256|metadata.txt|state.part-*) ;;
    *) fail "unexpected plaintext or unrelated file in state branch: $state_file" ;;
  esac
done

export PERSIST_ROOT="$restored"
bash scripts/restore-git-state.sh

[[ -f "$restored/latest-only.txt" ]] || fail 'latest-only file was not restored'
[[ ! -e "$restored/obsolete.txt" ]] || fail 'file deleted before newest save returned after restore'
[[ -x "$restored/projects/demo/run.sh" ]] || fail 'executable permission was not preserved'
[[ -L "$restored/projects/demo/tracked-link" ]] || fail 'symlink was not preserved'
[[ "$(readlink "$restored/projects/demo/tracked-link")" == 'tracked.txt' ]] || fail 'symlink target changed'
[[ -f "$restored/.config/devbox/settings.conf" ]] || fail 'user configuration was not restored'

status="$(git -C "$restored/projects/demo" status --porcelain)"
printf '%s\n' "$status" | grep -Fq 'A  staged.txt' || fail 'staged Git state was not preserved'
printf '%s\n' "$status" | grep -Fq ' M tracked.txt' || fail 'unstaged Git change was not preserved'
printf '%s\n' "$status" | grep -Fq '?? untracked.txt' || fail 'untracked Git file was not preserved'

export PERSIST_ROOT="$wrong_restore"
export DEVBOX_STATE_PASSWORD='wrong-password-for-negative-test'
if bash scripts/restore-git-state.sh >/dev/null 2>&1; then
  fail 'restore unexpectedly succeeded with the wrong encryption password'
fi

echo 'PASS: Git-backed persistent state preserves working-tree state and keeps one reachable snapshot'
