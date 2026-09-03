#!/usr/bin/env bash
set -euo pipefail

: "${DEVBOX_SSH_PASSWORD:?DEVBOX_SSH_PASSWORD must be set}"

echo "dev:${DEVBOX_SSH_PASSWORD}" | chpasswd

KEY_DIR=/var/lib/devbox-ssh
mkdir -p "$KEY_DIR" /run/sshd
chmod 700 "$KEY_DIR"

if [[ ! -f "$KEY_DIR/ssh_host_ed25519_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$KEY_DIR/ssh_host_ed25519_key"
fi

if [[ ! -f "$KEY_DIR/ssh_host_rsa_key" ]]; then
  ssh-keygen -q -t rsa -b 4096 -N '' -f "$KEY_DIR/ssh_host_rsa_key"
fi

ln -sf "$KEY_DIR/ssh_host_ed25519_key" /etc/ssh/ssh_host_ed25519_key
ln -sf "$KEY_DIR/ssh_host_ed25519_key.pub" /etc/ssh/ssh_host_ed25519_key.pub
ln -sf "$KEY_DIR/ssh_host_rsa_key" /etc/ssh/ssh_host_rsa_key
ln -sf "$KEY_DIR/ssh_host_rsa_key.pub" /etc/ssh/ssh_host_rsa_key.pub

exec /usr/sbin/sshd -D -e
