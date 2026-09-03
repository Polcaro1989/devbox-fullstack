#!/usr/bin/env bash
set -euo pipefail

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
else
  echo 'NVM not found' >&2
  exit 1
fi

if [[ -d "$HOME/.dotnet-actions" ]]; then
  export DOTNET_ROOT="$HOME/.dotnet-actions"
  export PATH="$DOTNET_ROOT:$PATH"
fi

php --version
composer --version
python3 --version
pip3 --version
nvm --version
node --version
npm --version

dotnet --list-sdks
for major in 8 9 10; do
  dotnet --list-sdks | grep -Eq "^${major}\." || {
    echo ".NET SDK ${major}.x not found" >&2
    exit 1
  }
done

if dotnet --list-sdks | grep -Eq '^7\.'; then
  echo '.NET SDK 7.x should not be installed' >&2
  exit 1
fi

echo 'PASS: toolchain verified (.NET 8/9/10, PHP, Python, NVM/Node)'
