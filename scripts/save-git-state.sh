#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=state-common.sh
source "$SCRIPT_DIR/state-common.sh"

PERSIST_ROOT="${PERSIST_ROOT:-/home/runner}"
EXCLUDES_FILE="${PERSIST_EXCLUDES_FILE:-$SCRIPT_DIR/state-excludes.txt}"
LOCK_FILE="${PERSIST_LOCK_FILE:-/tmp/devbox-git-state.lock}"
CHUNK_BYTES="${DEVBOX_STATE_CHUNK_BYTES:-90M}"
MAX_BYTES="${DEVBOX_STATE_MAX_BYTES:-1500000000}"

state_require_env
state_require_commands
[[ -d "$PERSIST_ROOT" ]] || { echo "Persistent root does not exist: $PERSIST_ROOT" >&2; exit 1; }
[[ -f "$EXCLUDES_FILE" ]] || { echo "State exclusions file does not exist: $EXCLUDES_FILE" >&2; exit 1; }

exec 9>"$LOCK_FILE"
if ! flock -w 300 9; then
  echo 'Timed out waiting for another state save to finish.' >&2
  exit 1
fi

work_dir="$(mktemp -d /tmp/devbox-state-save.XXXXXX)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

export GNUPGHOME="$work_dir/gnupg"
mkdir -m 700 "$GNUPGHOME"
state_prepare_git_auth "$work_dir"
remote_url="$(state_remote_url)"

archive="$work_dir/snapshot.tar.zst"
encrypted="$work_dir/snapshot.tar.zst.gpg"
verify_archive="$work_dir/verify.tar.zst"
passfile="$work_dir/passphrase"
publish_dir="$work_dir/publish"
mkdir -p "$publish_dir"

echo "Creating persistent-state archive from $PERSIST_ROOT ..."
tar --zstd -cpf "$archive" \
  --exclude-from="$EXCLUDES_FILE" \
  -C "$PERSIST_ROOT" .

content_hash="$(sha256sum "$archive" | awk '{print $1}')"
printf '%s  snapshot.tar.zst\n' "$content_hash" > "$publish_dir/content.sha256"

state_write_passphrase_file "$passfile"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase-file "$passfile" \
  --symmetric --cipher-algo AES256 --compress-algo none \
  --output "$encrypted" "$archive" >/dev/null 2>&1

encrypted_hash="$(sha256sum "$encrypted" | awk '{print $1}')"
printf '%s  snapshot.tar.zst.gpg\n' "$encrypted_hash" > "$publish_dir/manifest.sha256"

# Verify both integrity and decryptability before touching the remote branch.
(
  cd "$work_dir"
  sha256sum -c "$publish_dir/manifest.sha256"
)
gpg --batch --yes --pinentry-mode loopback \
  --passphrase-file "$passfile" \
  --output "$verify_archive" \
  --decrypt "$encrypted" >/dev/null 2>&1
[[ "$(sha256sum "$verify_archive" | awk '{print $1}')" == "$content_hash" ]] || {
  echo 'Decrypted archive verification failed.' >&2
  exit 1
}
tar --zstd -tf "$verify_archive" >/dev/null

encrypted_size="$(stat -c '%s' "$encrypted")"
if (( encrypted_size > MAX_BYTES )); then
  echo "Persistent state is too large for the configured Git safety limit: ${encrypted_size} bytes > ${MAX_BYTES} bytes." >&2
  du -sh "$PERSIST_ROOT" >&2 || true
  exit 1
fi

# If the plaintext archive is byte-identical to the current state, avoid a pointless force-push.
probe_repo="$work_dir/probe"
mkdir -p "$probe_repo"
git -C "$probe_repo" init -q
git -C "$probe_repo" remote add origin "$remote_url"
if state_probe_branch "$probe_repo"; then
  git -C "$probe_repo" fetch -q --depth=1 origin "refs/heads/$STATE_BRANCH"
  current_content_hash="$(git -C "$probe_repo" show FETCH_HEAD:content.sha256 2>/dev/null | awk 'NR==1 {print $1}' || true)"
  if [[ -n "$current_content_hash" && "$current_content_hash" == "$content_hash" ]]; then
    echo 'Persistent state is unchanged; existing state commit kept.'
    exit 0
  fi
else
  status=$?
  if [[ "$status" -ne 2 ]]; then
    exit "$status"
  fi
fi

split -b "$CHUNK_BYTES" -d -a 4 "$encrypted" "$publish_dir/state.part-"
chunk_count="$(find "$publish_dir" -maxdepth 1 -type f -name 'state.part-*' | wc -l | tr -d ' ')"
[[ "$chunk_count" -gt 0 ]] || { echo 'Snapshot splitting produced no chunks.' >&2; exit 1; }

cat > "$publish_dir/metadata.txt" <<EOF
format=devbox-git-state-v1
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source_repository=${GITHUB_REPOSITORY:-local}
source_run_id=${GITHUB_RUN_ID:-local}
encrypted_bytes=$encrypted_size
chunks=$chunk_count
EOF

publish_repo="$work_dir/publish-repo"
mkdir -p "$publish_repo"
git -C "$publish_repo" init -q
git -C "$publish_repo" config user.name 'devbox-state-bot'
git -C "$publish_repo" config user.email 'devbox-state-bot@users.noreply.github.com'
git -C "$publish_repo" config core.compression 0
git -C "$publish_repo" config pack.compression 0
git -C "$publish_repo" checkout -q --orphan "$STATE_BRANCH"
cp -a "$publish_dir"/. "$publish_repo"/
git -C "$publish_repo" add -A
git -C "$publish_repo" commit -q -m "devbox state $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -C "$publish_repo" remote add origin "$remote_url"

# The remote ref changes only here, after the new state has been fully verified.
git -C "$publish_repo" push -q --force origin "HEAD:refs/heads/$STATE_BRANCH"

echo "Persistent state saved successfully: $encrypted_size encrypted bytes in $chunk_count chunk(s)."
