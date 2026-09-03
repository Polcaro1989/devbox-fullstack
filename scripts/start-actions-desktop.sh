#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DESKTOP_PASSWORD:-}" ]]; then
  echo 'DESKTOP_PASSWORD is required' >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export DISPLAY=:1
RUNTIME_DIR="${RUNNER_TEMP:-/tmp}/actions-desktop"
mkdir -p "$RUNTIME_DIR"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  xvfb fluxbox x11vnc novnc websockify xterm pcmanfm \
  nginx apache2-utils dbus-x11
sudo rm -rf /var/lib/apt/lists/*

sudo curl -fsSL \
  https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
  -o /usr/local/bin/ttyd
sudo chmod +x /usr/local/bin/ttyd

sudo curl -fsSL \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

AUTH_TMP="$RUNTIME_DIR/htpasswd"
AUTH_FILE="/etc/nginx/actions-desktop.htpasswd"
htpasswd -bcB "$AUTH_TMP" devbox "$DESKTOP_PASSWORD" >/dev/null
sudo install -o root -g www-data -m 640 "$AUTH_TMP" "$AUTH_FILE"
rm -f "$AUTH_TMP"

cat > "$RUNTIME_DIR/nginx.conf" <<EOF
server {
    listen 127.0.0.1:8080;
    server_name _;

    auth_basic "Private Actions Desktop";
    auth_basic_user_file $AUTH_FILE;

    location = / {
        return 302 /vnc.html?autoconnect=true&resize=scale&path=websockify;
    }

    location ~ ^/terminal(.*)$ {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_pass http://127.0.0.1:7681/\$1;
    }

    location / {
        proxy_pass http://127.0.0.1:6080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

sudo cp "$RUNTIME_DIR/nginx.conf" /etc/nginx/conf.d/actions-desktop.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t

Xvfb :1 -screen 0 1440x900x24 -ac -nolisten tcp >"$RUNTIME_DIR/xvfb.log" 2>&1 &
echo $! > "$RUNTIME_DIR/xvfb.pid"
sleep 1

fluxbox >"$RUNTIME_DIR/fluxbox.log" 2>&1 &
echo $! > "$RUNTIME_DIR/fluxbox.pid"

xterm -geometry 120x35+20+20 -title 'Actions Desktop Terminal' >"$RUNTIME_DIR/xterm.log" 2>&1 &

x11vnc \
  -display :1 \
  -forever \
  -shared \
  -nopw \
  -rfbport 5901 \
  -listen 127.0.0.1 \
  -o "$RUNTIME_DIR/x11vnc.log" >/dev/null 2>&1 &
echo $! > "$RUNTIME_DIR/x11vnc.pid"

websockify \
  --web=/usr/share/novnc \
  127.0.0.1:6080 \
  127.0.0.1:5901 >"$RUNTIME_DIR/websockify.log" 2>&1 &
echo $! > "$RUNTIME_DIR/websockify.pid"

ttyd \
  -i 127.0.0.1 \
  -p 7681 \
  -b /terminal \
  -W \
  bash -l >"$RUNTIME_DIR/ttyd.log" 2>&1 &
echo $! > "$RUNTIME_DIR/ttyd.pid"

sudo nginx
sleep 2

for pid_file in "$RUNTIME_DIR"/*.pid; do
  pid="$(cat "$pid_file")"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "process failed: $pid_file" >&2
    exit 1
  fi
done

if ! curl -fsS --user "devbox:${DESKTOP_PASSWORD}" http://127.0.0.1:8080/vnc.html >/dev/null; then
  echo 'noVNC proxy health check failed' >&2
  echo 'direct noVNC HTTP status:' >&2
  curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:6080/vnc.html >&2 || true
  echo 'websockify log:' >&2
  tail -n 80 "$RUNTIME_DIR/websockify.log" >&2 || true
  echo 'nginx error log:' >&2
  sudo tail -n 80 /var/log/nginx/error.log >&2 || true
  exit 1
fi

if ! curl -fsS --user "devbox:${DESKTOP_PASSWORD}" http://127.0.0.1:8080/terminal/ >/dev/null; then
  echo 'terminal proxy health check failed' >&2
  echo 'direct ttyd HTTP status at /:' >&2
  curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7681/ >&2 || true
  echo 'direct ttyd HTTP status at /terminal/:' >&2
  curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7681/terminal/ >&2 || true
  echo 'ttyd log:' >&2
  tail -n 80 "$RUNTIME_DIR/ttyd.log" >&2 || true
  echo 'nginx error log:' >&2
  sudo tail -n 80 /var/log/nginx/error.log >&2 || true
  exit 1
fi

if [[ "${ACTIONS_DESKTOP_SMOKE:-0}" == '1' ]]; then
  echo 'PASS: local Actions Desktop stack is healthy'
  exit 0
fi

TUNNEL_LOG="$RUNTIME_DIR/cloudflared.log"
cloudflared tunnel --url http://127.0.0.1:8080 --no-autoupdate >"$TUNNEL_LOG" 2>&1 &
echo $! > "$RUNTIME_DIR/cloudflared.pid"

DESKTOP_URL=''
for _ in $(seq 1 60); do
  DESKTOP_URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
  if [[ -n "$DESKTOP_URL" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$DESKTOP_URL" ]]; then
  echo 'Cloudflare Quick Tunnel did not provide a URL' >&2
  tail -n 40 "$TUNNEL_LOG" >&2 || true
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DESKTOP_URL=%s\n' "$DESKTOP_URL" >> "$GITHUB_ENV"
fi

{
  echo '## Actions Desktop ready'
  echo
  echo "- Desktop: $DESKTOP_URL"
  echo "- Terminal: $DESKTOP_URL/terminal/"
  echo '- Username: `devbox`'
  echo '- Password: repository secret `DESKTOP_PASSWORD` (not printed)'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "Actions Desktop ready: $DESKTOP_URL"
echo "Terminal: $DESKTOP_URL/terminal/"
echo 'Username: devbox'
echo 'Password: use the repository secret DESKTOP_PASSWORD (not printed)'
echo 'Quick Tunnel domain: trycloudflare.com'
