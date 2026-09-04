#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=state-common.sh
source "$SCRIPT_DIR/state-common.sh"

PERSIST_ROOT="${PERSIST_ROOT:-/home/runner}"

state_require_env
state_require_commands

work_dir="$(mktemp -d /tmp/devbox-state-restore.XXXXXX)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

export GNUPGHOME="$work_dir/gnupg"
mkdir -m 700 "$GNUPGHOME"
state_prepare_git_auth "$work_dir"
remote_url="$(state_remote_url)"
repo_dir="$work_dir/repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" remote add origin "$remote_url"

if state_probe_branch "$repo_dir"; then
  :
else
  status=$?
  if [[ "$status" -eq 2 ]]; then
    echo 'No persistent state branch found; starting with a fresh user state.'
    exit 0
  fi
  exit "$status"
fi

git -C "$repo_dir" fetch -q --depth=1 origin "refs/heads/$STATE_BRANCH"
git -C "$repo_dir" checkout -q --detach FETCH_HEAD

[[ -f "$repo_dir/manifest.sha256" ]] || { echo 'Persistent state manifest is missing.' >&2; exit 1; }
compgen -G "$repo_dir/state.part-*" >/dev/null || { echo 'Persistent state chunks are missing.' >&2; exit 1; }

encrypted="$work_dir/snapshot.tar.zst.gpg"
archive="$work_dir/snapshot.tar.zst"
passfile="$work_dir/passphrase"

cat "$repo_dir"/state.part-* > "$encrypted"
(
  cd "$work_dir"
  sha256sum -c "$repo_dir/manifest.sha256"
)

state_write_passphrase_file "$passfile"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase-file "$passfile" \
  --output "$archive" \
  --decrypt "$encrypted" >/dev/null 2>&1

# Reject absolute paths and parent traversal before extraction.
if tar --zstd -tf "$archive" | awk '
  /^\// { bad=1 }
  /(^|\/)\.\.(\/|$)/ { bad=1 }
  END { exit bad ? 1 : 0 }
'; then
  :
else
  echo 'Persistent state archive contains unsafe paths.' >&2
  exit 1
fi

mkdir -p "$PERSIST_ROOT"
tar --zstd -xpf "$archive" -C "$PERSIST_ROOT"

if [[ "$PERSIST_ROOT" == "/home/runner" ]]; then
  chmod u+rwx /home/runner
fi

echo 'Persistent Git-backed user state restored successfully.'
