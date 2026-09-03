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
  .github/workflows/actions-desktop.yml .github/workflows/ci.yml \
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

SETUP=scripts/setup-actions-toolchain.sh
require_literal "$SETUP" 'for channel in 8.0 9.0 10.0'
require_literal "$SETUP" '--channel "$channel"'
require_literal "$SETUP" 'nvm install --lts'

nvm_disable_line=$(grep -nF 'set +u' "$SETUP" | head -n1 | cut -d: -f1 || true)
nvm_source_line=$(grep -nF 'source "$NVM_DIR/nvm.sh"' "$SETUP" | head -n1 | cut -d: -f1 || true)
nvm_use_line=$(grep -nF 'nvm use --lts' "$SETUP" | head -n1 | cut -d: -f1 || true)
nvm_restore_line=$(grep -nF 'set -u' "$SETUP" | tail -n1 | cut -d: -f1 || true)
if [[ -z "$nvm_disable_line" || -z "$nvm_source_line" || -z "$nvm_use_line" || -z "$nvm_restore_line" ]]; then
  fail 'setup script must guard NVM calls from bash nounset'
fi
if ! (( nvm_disable_line < nvm_source_line && nvm_source_line < nvm_use_line && nvm_use_line < nvm_restore_line )); then
  fail 'setup script must disable nounset before sourcing/using NVM and restore it afterward'
fi

DESKTOP_SCRIPT=scripts/start-actions-desktop.sh
for text in 'Xvfb' 'fluxbox' 'x11vnc' 'websockify' 'ttyd' 'nginx' 'htpasswd' 'cloudflared' '127.0.0.1' 'DESKTOP_PASSWORD' 'trycloudflare.com' 'ACTIONS_DESKTOP_SMOKE'; do
  require_literal "$DESKTOP_SCRIPT" "$text"
done
require_literal "$DESKTOP_SCRIPT" 'auth_basic'
require_literal "$DESKTOP_SCRIPT" '/terminal/'

CI=.github/workflows/ci.yml
require_literal "$CI" 'desktop-smoke:'
require_literal "$CI" 'ACTIONS_DESKTOP_SMOKE: 1'
require_literal "$CI" 'DESKTOP_PASSWORD: ci-smoke-only-not-a-real-secret'
require_literal "$CI" 'bash scripts/start-actions-desktop.sh'

if grep -R --exclude='.env.example' --exclude='test-config.sh' -E 'DEVBOX_SSH_PASSWORD=[^$<{[:space:]][^[:space:]]{8,}' . >/dev/null 2>&1; then
  fail 'a concrete DEVBOX_SSH_PASSWORD appears to be committed'
fi

if grep -R --exclude='test-config.sh' -E 'DESKTOP_PASSWORD=[A-Za-z0-9][^$<{[:space:]]{7,}' . >/dev/null 2>&1; then
  fail 'a concrete DESKTOP_PASSWORD appears to be committed'
fi

echo 'PASS: Actions Desktop configuration contract satisfied'
