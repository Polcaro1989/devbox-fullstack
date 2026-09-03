#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl git unzip zip xz-utils jq \
  build-essential pkg-config \
  php-cli php-curl php-mbstring php-xml php-zip php-bcmath php-intl php-sqlite3 \
  composer \
  python3 python3-pip python3-venv
sudo rm -rf /var/lib/apt/lists/*

export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
nvm use --lts

DOTNET_DIR="$HOME/.dotnet-actions"
mkdir -p "$DOTNET_DIR"
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
for channel in 8.0 9.0 10.0; do
  /tmp/dotnet-install.sh --channel "$channel" --install-dir "$DOTNET_DIR" --no-path
 done
rm -f /tmp/dotnet-install.sh

export DOTNET_ROOT="$DOTNET_DIR"
export PATH="$DOTNET_DIR:$(dirname "$(command -v node)"):$PATH"

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$DOTNET_DIR" "$(dirname "$(command -v node)")" >> "$GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DOTNET_ROOT=%s\n' "$DOTNET_DIR" >> "$GITHUB_ENV"
  printf 'NVM_DIR=%s\n' "$NVM_DIR" >> "$GITHUB_ENV"
fi

php --version | head -n 1
composer --version
python3 --version
pip3 --version
node --version
npm --version
dotnet --list-sdks

df -h /
