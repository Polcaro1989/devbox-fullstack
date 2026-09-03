#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo 'Arquivo .env nao encontrado. Copie .env.example para .env e defina DEVBOX_SSH_PASSWORD.' >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo 'Docker nao encontrado no host.' >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now docker
fi

docker compose config >/dev/null
docker compose up -d --build

echo 'Devbox iniciada com restart: unless-stopped.'
