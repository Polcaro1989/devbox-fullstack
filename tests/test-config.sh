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
  scripts/setup-actions-toolchain.sh scripts/cleanup-runner.sh scripts/start-actions-server.sh \
  scripts/state-common.sh scripts/save-git-state.sh scripts/restore-git-state.sh \
  scripts/state-session-loop.sh scripts/state-excludes.txt \
  tests/test-git-state.sh \
  .github/workflows/actions-desktop.yml .github/workflows/ci.yml \
  .env.example .gitignore .dockerignore; do
  require_file "$file"
done

if [[ -e scripts/start-actions-desktop.sh ]]; then
  fail 'graphical Actions Desktop launcher must be removed in SSH-only server mode'
fi
if [[ -e .devcontainer/devcontainer.json ]]; then
  fail 'Codespaces configuration must not exist in the final Actions Server implementation'
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
require_literal "$WORKFLOW" 'name: Actions Server'
require_literal "$WORKFLOW" 'workflow_dispatch:'
require_literal "$WORKFLOW" 'runs-on: ubuntu-latest'
require_literal "$WORKFLOW" 'timeout-minutes: 355'
require_literal "$WORKFLOW" 'SSH_PASSWORD: ${{ secrets.DESKTOP_PASSWORD }}'
require_literal "$WORKFLOW" 'TAILSCALE_AUTHKEY: ${{ secrets.TAILSCALE_AUTHKEY }}'
require_literal "$WORKFLOW" 'DEVBOX_STATE_REPO: Polcaro1989/Repository-'
require_literal "$WORKFLOW" 'DEVBOX_STATE_TOKEN: ${{ secrets.DEVBOX_STATE_TOKEN }}'
require_literal "$WORKFLOW" 'DEVBOX_STATE_PASSWORD: ${{ secrets.DEVBOX_STATE_PASSWORD }}'
require_literal "$WORKFLOW" 'DEVBOX_STATE_BRANCH: devbox-state'
require_literal "$WORKFLOW" 'persist-credentials: false'
require_literal "$WORKFLOW" 'uses: tailscale/github-action@v4'
require_literal "$WORKFLOW" 'authkey: ${{ secrets.TAILSCALE_AUTHKEY }}'
require_literal "$WORKFLOW" 'bash scripts/cleanup-runner.sh'
require_literal "$WORKFLOW" 'bash scripts/setup-actions-toolchain.sh'
require_literal "$WORKFLOW" 'bash scripts/restore-git-state.sh'
require_literal "$WORKFLOW" 'bash scripts/start-actions-server.sh'
require_literal "$WORKFLOW" 'bash scripts/state-session-loop.sh'
require_literal "$WORKFLOW" 'bash scripts/save-git-state.sh'
require_literal "$WORKFLOW" '/tmp/devbox-session-ready'

cleanup_line=$(grep -nF 'bash scripts/cleanup-runner.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
setup_line=$(grep -nF 'bash scripts/setup-actions-toolchain.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
restore_line=$(grep -nF 'bash scripts/restore-git-state.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
tailscale_line=$(grep -nF 'uses: tailscale/github-action@v4' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
server_line=$(grep -nF 'bash scripts/start-actions-server.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
loop_line=$(grep -nF 'bash scripts/state-session-loop.sh' "$WORKFLOW" | head -n1 | cut -d: -f1 || true)
if [[ -z "$cleanup_line" || -z "$setup_line" ]] || ! (( cleanup_line < setup_line )); then
  fail 'runner cleanup must happen before development toolchain setup'
fi
if [[ -z "$setup_line" || -z "$restore_line" ]] || ! (( setup_line < restore_line )); then
  fail 'persistent state must restore after base toolchain setup'
fi
if [[ -z "$restore_line" || -z "$tailscale_line" || -z "$server_line" || -z "$loop_line" ]] || ! (( restore_line < tailscale_line && tailscale_line < server_line && server_line < loop_line )); then
  fail 'restore, Tailscale, SSH, and checkpoint session loop are in the wrong order'
fi

if grep -Eq '^[[:space:]]*schedule:' "$WORKFLOW"; then
  fail 'Actions Server must not have a scheduled trigger'
fi
if grep -Eq 'repository_dispatch|workflow_run|gh workflow run|actions/workflows/.*/dispatches' "$WORKFLOW"; then
  fail 'Actions Server must not self-dispatch or chain new runs'
fi
if grep -Eq 'start-actions-desktop|noVNC|cloudflared|graphical desktop|DESKTOP_URL' "$WORKFLOW"; then
  fail 'Actions Server workflow must not start the old graphical desktop stack'
fi
if grep -Eiq 'R2_|cloudflarestorage|Backblaze|B2_' "$WORKFLOW"; then
  fail 'Actions Server persistence must use the private Git state repository, not R2/B2'
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

CLEANUP=scripts/cleanup-runner.sh
for text in 'df -h /' '/usr/local/lib/android' '/opt/ghc' '/usr/local/.ghcup' '/opt/hostedtoolcache/CodeQL' 'docker system prune -af' 'apt-get clean'; do
  require_literal "$CLEANUP" "$text"
done
if grep -Fq '/opt/hostedtoolcache/node' "$CLEANUP" || grep -Fq '/opt/hostedtoolcache/Python' "$CLEANUP"; then
  fail 'cleanup must preserve hosted Node and Python tool caches for runner compatibility'
fi

SERVER_SCRIPT=scripts/start-actions-server.sh
for text in 'openssh-server' 'SSH_PASSWORD' 'tailscale ip -4' 'chpasswd' 'PasswordAuthentication yes' 'PermitRootLogin no' 'AllowUsers runner' 'ListenAddress $TAILSCALE_IP' 'sshd -D -e' 'ACTIONS_SERVER_SMOKE' 'systemctl stop ssh.service ssh.socket' 'pkill -x sshd'; do
  require_literal "$SERVER_SCRIPT" "$text"
done
for forbidden in Xvfb xfce4 noVNC novnc x11vnc websockify ttyd nginx cloudflared fluxbox; do
  if grep -Fiq "$forbidden" "$SERVER_SCRIPT"; then
    fail "SSH-only server script must not contain graphical/web desktop dependency: $forbidden"
  fi
done

STATE_COMMON=scripts/state-common.sh
for text in 'DEVBOX_STATE_TOKEN' 'DEVBOX_STATE_PASSWORD' 'GIT_ASKPASS' 'x-access-token' 'DEVBOX_STATE_REMOTE_URL' 'ls-remote --exit-code'; do
  require_literal "$STATE_COMMON" "$text"
done
if grep -Fq 'https://x-access-token:' "$STATE_COMMON"; then
  fail 'Git state token must not be embedded in a remote URL'
fi

STATE_SAVE=scripts/save-git-state.sh
for text in 'flock -w 300' 'tar --zstd' 'gpg --batch' 'sha256sum' 'split -b' 'checkout -q --orphan' 'push -q --force' 'manifest.sha256' 'content.sha256' '1500000000'; do
  require_literal "$STATE_SAVE" "$text"
done
verify_line=$(grep -nF -- '--decrypt "$encrypted"' "$STATE_SAVE" | head -n1 | cut -d: -f1 || true)
push_line=$(grep -nF 'push -q --force' "$STATE_SAVE" | head -n1 | cut -d: -f1 || true)
if [[ -z "$verify_line" || -z "$push_line" ]] || ! (( verify_line < push_line )); then
  fail 'new state must be decrypted/verified before force-pushing over the previous state'
fi

STATE_RESTORE=scripts/restore-git-state.sh
for text in 'manifest.sha256' 'sha256sum -c' 'gpg --batch' 'tar --zstd -tf' 'tar --zstd -xpf' 'No persistent state branch found'; do
  require_literal "$STATE_RESTORE" "$text"
done

STATE_LOOP=scripts/state-session-loop.sh
for text in 'DEVBOX_CHECKPOINT_SECONDS:-900' 'DEVBOX_SESSION_SECONDS:-19200' "save_checkpoint 'periodic'" "save_checkpoint 'final'" 'trap on_signal INT TERM'; do
  require_literal "$STATE_LOOP" "$text"
done

EXCLUDES=scripts/state-excludes.txt
for text in 'work' '.cache' '.nvm' '.dotnet-actions' 'node_modules'; do
  require_literal "$EXCLUDES" "$text"
done
if grep -Eq '(^|/)\.git($|/)' "$EXCLUDES"; then
  fail '.git directories must not be excluded from persistent state'
fi

CI=.github/workflows/ci.yml
require_literal "$CI" 'server-smoke:'
require_literal "$CI" 'ACTIONS_SERVER_SMOKE: 1'
require_literal "$CI" 'SSH_PASSWORD: ci-smoke-only-not-a-real-secret'
require_literal "$CI" 'TAILSCALE_IP: 127.0.0.1'
require_literal "$CI" 'SSH_PORT: 2222'
require_literal "$CI" 'bash scripts/start-actions-server.sh'
require_literal "$CI" 'bash tests/test-git-state.sh'
if grep -Fq 'desktop-smoke:' "$CI"; then
  fail 'CI must use the SSH server smoke test instead of the old desktop smoke test'
fi

if grep -R --exclude='.env.example' --exclude='test-config.sh' -E 'DEVBOX_SSH_PASSWORD=[^$<{[:space:]][^[:space:]]{8,}' . >/dev/null 2>&1; then
  fail 'a concrete DEVBOX_SSH_PASSWORD appears to be committed'
fi
if grep -R --exclude='test-config.sh' -E 'tskey-auth-[A-Za-z0-9_-]+' . >/dev/null 2>&1; then
  fail 'a concrete Tailscale auth key appears to be committed'
fi
if grep -R --exclude='test-config.sh' -E '(github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,})' . >/dev/null 2>&1; then
  fail 'a concrete GitHub token appears to be committed'
fi

echo 'PASS: Actions Server SSH and Git-backed persistence configuration contract satisfied'
