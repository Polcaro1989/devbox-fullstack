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

for file in Dockerfile docker-compose.yml entrypoint.sh scripts/verify-toolchain.sh scripts/install-host.sh scripts/start-actions-desktop.sh .env.example .gitignore .dockerignore .github/workflows/actions-desktop.yml; do
  require_file "$file"
done

if [[ -e .devcontainer/devcontainer.json ]]; then
  fail 'Codespaces configuration must not remain in the final Actions Desktop mode'
fi

require_literal docker-compose.yml 'restart: unless-stopped'
require_literal docker-compose.yml '${DEVBOX_SSH_PASSWORD:?'
require_literal docker-compose.yml '${SSH_PORT:-2222}:22'
require_literal docker-compose.yml '${WORKSPACE_PATH:-./workspace}:/workspace'
require_literal docker-compose.yml '/var/lib/devbox-ssh'
require_literal docker-compose.yml 'target: ssh-runtime'

require_literal .gitignore '.env'
require_literal Dockerfile 'AS toolchain'
require_literal Dockerfile 'AS ssh-runtime'
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
SESSION=scripts/start-actions-desktop.sh

require_literal "$WORKFLOW" 'workflow_dispatch:'
require_literal "$WORKFLOW" 'runs-on: ubuntu-latest'
require_literal "$WORKFLOW" 'timeout-minutes: 350'
require_literal "$WORKFLOW" 'DESKTOP_PASSWORD: ${{ secrets.DESKTOP_PASSWORD }}'
require_literal "$WORKFLOW" 'permissions:'
require_literal "$WORKFLOW" 'contents: read'
require_literal "$WORKFLOW" 'bash scripts/start-actions-desktop.sh'

if grep -Eq 'schedule:|cron:|workflow_run:' "$WORKFLOW"; then
  fail 'Actions Desktop must be manual only and must not chain or schedule replacement runs'
fi

require_literal "$SESSION" 'DESKTOP_PASSWORD'
require_literal "$SESSION" 'Xvfb :99'
require_literal "$SESSION" 'fluxbox'
require_literal "$SESSION" 'x11vnc'
require_literal "$SESSION" '127.0.0.1:5900'
require_literal "$SESSION" 'websockify'
require_literal "$SESSION" '127.0.0.1:6080'
require_literal "$SESSION" 'auth_basic'
require_literal "$SESSION" 'htpasswd'
require_literal "$SESSION" 'ttyd'
require_literal "$SESSION" '127.0.0.1:7681'
require_literal "$SESSION" 'cloudflared tunnel'
require_literal "$SESSION" 'trycloudflare.com'
require_literal "$SESSION" 'verify-toolchain'

if grep -R --exclude='.env.example' --exclude='test-config.sh' -E 'DEVBOX_SSH_PASSWORD=[^$<{[:space:]][^[:space:]]{8,}' . >/dev/null 2>&1; then
  fail 'a concrete DEVBOX_SSH_PASSWORD appears to be committed'
fi

if grep -R --exclude='test-config.sh' -E 'DESKTOP_PASSWORD=[A-Za-z0-9][^$<{[:space:]]{7,}' . >/dev/null 2>&1; then
  fail 'a concrete DESKTOP_PASSWORD appears to be committed'
fi

echo 'PASS: devbox configuration contract satisfied'
