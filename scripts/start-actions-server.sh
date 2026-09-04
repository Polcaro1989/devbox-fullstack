#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SSH_PASSWORD:-}" ]]; then
  echo 'SSH_PASSWORD is required' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
RUNTIME_DIR="${RUNNER_TEMP:-/tmp}/actions-server"
mkdir -p "$RUNTIME_DIR"

sudo apt-get update
sudo apt-get install -y --no-install-recommends openssh-server
sudo rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 may automatically start the distro SSH service/socket when
# openssh-server is installed or upgraded. Stop that public/default listener
# before starting our dedicated sshd, which binds only to the Tailscale IP.
sudo systemctl stop ssh.service ssh.socket 2>/dev/null || true
sudo pkill -x sshd 2>/dev/null || true

sudo install -d -m 0755 /run/sshd
sudo ssh-keygen -A
printf 'runner:%s\n' "$SSH_PASSWORD" | sudo chpasswd

if [[ "${ACTIONS_SERVER_SMOKE:-0}" == '1' ]]; then
  TAILSCALE_IP="${TAILSCALE_IP:-127.0.0.1}"
  SSH_PORT="${SSH_PORT:-2222}"
else
  if ! command -v tailscale >/dev/null 2>&1; then
    echo 'tailscale is required before starting the SSH server' >&2
    exit 1
  fi
  TAILSCALE_IP="${TAILSCALE_IP:-$(tailscale ip -4 | head -n 1)}"
  SSH_PORT="${SSH_PORT:-22}"
fi

if [[ -z "$TAILSCALE_IP" ]]; then
  echo 'Tailscale did not provide an IPv4 address' >&2
  exit 1
fi

SSHD_CONFIG="$RUNTIME_DIR/sshd_config"
SSHD_LOG="$RUNTIME_DIR/sshd.log"
SSHD_PID="$RUNTIME_DIR/sshd.pid"

cat > "$SSHD_CONFIG" <<EOF
Port $SSH_PORT
ListenAddress $TAILSCALE_IP
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_rsa_key
PidFile $SSHD_PID
UsePAM yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers runner
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts no
ClientAliveInterval 60
ClientAliveCountMax 3
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

sudo /usr/sbin/sshd -t -f "$SSHD_CONFIG"
sudo /usr/sbin/sshd -D -e -f "$SSHD_CONFIG" >"$SSHD_LOG" 2>&1 &
sshd_process=$!
echo "$sshd_process" > "$RUNTIME_DIR/sshd-process.pid"

for _ in $(seq 1 20); do
  if kill -0 "$sshd_process" 2>/dev/null \
    && timeout 1 bash -c "exec 3<>/dev/tcp/${TAILSCALE_IP}/${SSH_PORT}; exec 3>&-" 2>/dev/null; then
    break
  fi
  sleep 1
done

if ! kill -0 "$sshd_process" 2>/dev/null; then
  echo 'SSH server process failed to start' >&2
  tail -n 120 "$SSHD_LOG" >&2 || true
  exit 1
fi

if ! timeout 2 bash -c "exec 3<>/dev/tcp/${TAILSCALE_IP}/${SSH_PORT}; exec 3>&-" 2>/dev/null; then
  echo "SSH server is not listening on ${TAILSCALE_IP}:${SSH_PORT}" >&2
  tail -n 120 "$SSHD_LOG" >&2 || true
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'SSH_HOST=%s\nSSH_PORT=%s\n' "$TAILSCALE_IP" "$SSH_PORT" >> "$GITHUB_ENV"
fi

if [[ "${ACTIONS_SERVER_SMOKE:-0}" == '1' ]]; then
  echo 'PASS: local Actions Server SSH stack is healthy'
  exit 0
fi

{
  echo '## Actions Server ready'
  echo
  echo "- SSH: \`ssh -p $SSH_PORT runner@$TAILSCALE_IP\`"
  echo '- Username: `runner`'
  echo '- Password: repository secret `DESKTOP_PASSWORD` (not printed)'
  echo '- Network: private Tailscale address only'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "Actions Server ready: ssh -p $SSH_PORT runner@$TAILSCALE_IP"
echo 'Username: runner'
echo 'Password: use the repository secret DESKTOP_PASSWORD (not printed)'
