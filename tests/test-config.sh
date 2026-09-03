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

for file in Dockerfile docker-compose.yml entrypoint.sh scripts/verify-toolchain.sh scripts/install-host.sh .env.example .gitignore .dockerignore .devcontainer/devcontainer.json; do
  require_file "$file"
done

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

require_literal .devcontainer/devcontainer.json '"target": "toolchain"'
require_literal .devcontainer/devcontainer.json 'ghcr.io/devcontainers/features/desktop-lite:1'
require_literal .devcontainer/devcontainer.json '"password": "noPassword"'
require_literal .devcontainer/devcontainer.json '"forwardPorts": [6080]'
require_literal .devcontainer/devcontainer.json '"label": "Desktop (noVNC)"'
require_literal .devcontainer/devcontainer.json '"visibility": "private"'
require_literal .devcontainer/devcontainer.json '"remoteUser": "dev"'
require_literal .devcontainer/devcontainer.json '"--shm-size=1g"'

if grep -Fq -- 'DEVBOX_SSH_PASSWORD' .devcontainer/devcontainer.json; then
  fail 'Codespaces configuration must not require DEVBOX_SSH_PASSWORD'
fi

if grep -R --exclude='.env.example' --exclude='test-config.sh' -E 'DEVBOX_SSH_PASSWORD=[^$<{[:space:]][^[:space:]]{8,}' . >/dev/null 2>&1; then
  fail 'a concrete DEVBOX_SSH_PASSWORD appears to be committed'
fi

echo 'PASS: devbox configuration contract satisfied'
