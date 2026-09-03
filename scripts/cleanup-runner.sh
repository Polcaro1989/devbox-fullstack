#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

before_bytes="$(df --output=avail -B1 / | tail -n1 | tr -d ' ')"

echo '== Disk before cleanup =='
df -h /

# Remove large preinstalled toolchains that this devbox does not use.
# Keep the hosted Node/Python caches and core runner dependencies intact.
paths=(
  /usr/local/lib/android
  /usr/share/swift
  /opt/ghc
  /usr/local/.ghcup
  /opt/hostedtoolcache/CodeQL
  /usr/local/share/boost
  /usr/share/dotnet
)

for path in "${paths[@]}"; do
  if [[ -e "$path" ]]; then
    echo "Removing $path ($(sudo du -sh "$path" 2>/dev/null | awk '{print $1}' || echo unknown))"
    sudo rm -rf -- "$path"
  fi
done

if command -v docker >/dev/null 2>&1; then
  docker system prune -af || true
fi

sudo apt-get clean
sudo rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

after_bytes="$(df --output=avail -B1 / | tail -n1 | tr -d ' ')"
reclaimed_bytes=$((after_bytes - before_bytes))

printf 'Reclaimed: %s\n' "$(numfmt --to=iec-i --suffix=B "$reclaimed_bytes")"
echo '== Disk after cleanup =='
df -h /
