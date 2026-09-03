#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: $1"
}

require_literal() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing required text: $text"
}

for file in \
  Dockerfile docker-compose.yml entrypoint.sh \
  scripts/verify-toolchain.sh scripts/install-host.sh \
  scripts/setup-actions-toolchain.sh scripts/start-actions-desktop.sh \
  .github/workflows/actions-desktop.yml \
  .env.example .gitignore .dockerignore; do
  require_file "$file"
done

if [[ -e .devcontainer/devcontainer.json ]]; then
  fail 'Codespaces configuration must not exist in the final Actions Desktop implementation'
fi

require_literal docker-compose.yml 'restart: unless-stopped'
require_literal docker-compose.yml '${DEVBOX_SSH_PASSWORD:?'
require_literal docker-compose.yml '${SSH_PORT:-2222}:22'
require_literal docker-compose.yml '${WORKSPACE_PATH:-./workspace}:/workspace'
require_literal docker-compose.yml '/var/lib/devbox-ssh'

require_literal .gitignore '.env'
require_literal Dockerfile 'openssh-server'
require_literal Dockerfile 'PasswordAuthentication yes'
require_literal Dockerfile 'PermitRootLogin no'
require_literal Dockerfile 'AllowUsers dev'
require_literal Dockerfile '--channel 8.0'
require_literal Dockerfile '--channel 9.0'
require_literal Dockerfile '--channel 10.0'
require_literal Dockerfile 'nvm install --lts'

if grep -Fq -- '--channel 7.0' Dockerfile; then
  fail 'Dockerfile must not install .NET 7'
fi

require_literal entrypoint.sh 'DEVBOX_SSH_PASSWORD'
require_literal entrypoint.sh 'chpasswd'
require_literal entrypoint.sh 'ssh_host_ed25519_key'
require_literal entrypoint.sh 'sshd -D -e'

require_literal scripts/install-host.sh 'systemctl enable --now docker'
require_literal scripts/install-host.sh 'docker compose up -d --build'

WORKFLOW=.github/workflows/actions-desktop.yml
require_literal "$WORKFLOW" 'name: Actions Desktop'
require_literal "$WORKFLOW" 'workflow_dispatch:'
require_literal "$WORKFLOW" 'runs-on: ubuntu-latest'
require_literal "$WORKFLOW" 'timeout-minutes: 355'
require_literal "$WORKFLOW" 'DESKTOP_PASSWORD: ${{ secrets.DESKTOP_PASSWORD }}'
require_literal "$WORKFLOW" 'bash scripts/setup-actions-toolchain.sh'
require_literal "$WORKFLOW" 'bash scripts/start-actions-desktop.sh'

if grep -Eq '^[[:space:]]*schedule:' "$WORKFLOW"; then
  fail 'Actions Desktop must not have a scheduled trigger'
fi
if grep -Eq 'repository_dispatch|workflow_run|gh workflow run|actions/workflows/.*/dispatches' "$WORKFLOW"; then
  fail 'Actions Desktop must not self-dispatch or chain new runs'
fi

require_literal scripts/setup-actions-toolchain.sh 'for channel in 8.0 9.0 10.0'
require_literal scripts/setup-actions-toolchain.sh '--channel "$channel"'
require_literal scripts/setup-actions-toolchain.sh 'nvm install --lts'

DESKTOP_SCRIPT=scripts/start-actions-desktop.sh
for text in 'Xvfb' 'fluxbox' 'x11vnc' 'websockify' 'ttyd' 'nginx' 'htpasswd' 'cloudflared' '127.0.0.1' 'DESKTOP_PASSWORD' 'trycloudflare.com'; do
  require_literal "$DESKTOP_SCRIPT" "$text"
done
require_literal "$DESKTOP_SCRIPT" 'auth_basic'
require_literal "$DESKTOP_SCRIPT" '/terminal/'

if grep -R --exclude='.env.example' --exclude='test-config.sh' -E 'DEVBOX_SSH_PASSWORD=[^$<{[:space:]][^[:space:]]{8,}' . >/dev/null 2>&1; then
  fail 'a concrete DEVBOX_SSH_PASSWORD appears to be committed'
fi

if grep -R --exclude='test-config.sh' -E 'DESKTOP_PASSWORD=[A-Za-z0-9][^$<{[:space:]]{7,}' . >/dev/null 2>&1; then
  fail 'a concrete DESKTOP_PASSWORD appears to be committed'
fi

echo 'PASS: Actions Desktop configuration contract satisfied'
