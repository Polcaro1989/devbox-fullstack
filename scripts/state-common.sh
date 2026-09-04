#!/usr/bin/env bash
set -euo pipefail

STATE_BRANCH="${DEVBOX_STATE_BRANCH:-devbox-state}"
STATE_REPO="${DEVBOX_STATE_REPO:-}"
STATE_REMOTE_OVERRIDE="${DEVBOX_STATE_REMOTE_URL:-}"
STATE_TOKEN="${DEVBOX_STATE_TOKEN:-}"
STATE_PASSWORD="${DEVBOX_STATE_PASSWORD:-}"

state_require_env() {
  [[ -n "$STATE_PASSWORD" ]] || { echo 'DEVBOX_STATE_PASSWORD is required.' >&2; return 1; }

  if [[ -z "$STATE_REMOTE_OVERRIDE" ]]; then
    [[ -n "$STATE_REPO" ]] || { echo 'DEVBOX_STATE_REPO is required.' >&2; return 1; }
    [[ -n "$STATE_TOKEN" ]] || { echo 'DEVBOX_STATE_TOKEN is required.' >&2; return 1; }
  fi

  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    [[ -z "$STATE_TOKEN" ]] || echo "::add-mask::$STATE_TOKEN"
    echo "::add-mask::$STATE_PASSWORD"
  fi
}

state_remote_url() {
  if [[ -n "$STATE_REMOTE_OVERRIDE" ]]; then
    printf '%s\n' "$STATE_REMOTE_OVERRIDE"
  else
    printf 'https://github.com/%s.git\n' "$STATE_REPO"
  fi
}

state_prepare_git_auth() {
  local dir="$1"
  export GIT_TERMINAL_PROMPT=0

  if [[ -z "$STATE_TOKEN" ]]; then
    return 0
  fi

  local askpass="$dir/git-askpass.sh"
  cat > "$askpass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "${DEVBOX_STATE_TOKEN:?DEVBOX_STATE_TOKEN is required}" ;;
  *) printf '\n' ;;
esac
EOF
  chmod 700 "$askpass"
  export GIT_ASKPASS="$askpass"
}

state_require_commands() {
  local missing=0
  local command_name
  for command_name in git tar zstd gpg sha256sum split flock; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "Missing required command: $command_name" >&2
      missing=1
    fi
  done
  (( missing == 0 ))
}

state_probe_branch() {
  local repo_dir="$1"
  local output status

  set +e
  output="$(git -C "$repo_dir" ls-remote --exit-code --heads origin "refs/heads/$STATE_BRANCH" 2>&1)"
  status=$?
  set -e

  case "$status" in
    0) return 0 ;;
    2) return 2 ;;
    *)
      echo 'Unable to access the persistent state repository.' >&2
      [[ -z "$output" ]] || printf '%s\n' "$output" >&2
      return "$status"
      ;;
  esac
}

state_write_passphrase_file() {
  local file="$1"
  umask 077
  printf '%s' "$STATE_PASSWORD" > "$file"
  chmod 600 "$file"
}
