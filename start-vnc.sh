#!/bin/bash
# VNC stack launcher for pre-baked hermes-workspace-vnc image.
# No apt-get — everything is installed in the image at build time.
set -e

VNC_PASSWORD="${VNC_PASSWORD:-$(head -c 12 /dev/urandom | base64 | tr -d '=+/')}"
echo "$VNC_PASSWORD" > /tmp/vnc-password.txt
chmod 600 /tmp/vnc-password.txt

# 0. Link noVNC to web root (nginx serves from /opt/data/www)
echo "[VNC] Linking noVNC to web root"
mkdir -p /opt/data/www
ln -sf /opt/vnc/noVNC /opt/data/www/vnc

# 1. Virtual display
echo "[VNC] Starting Xvfb :99"
Xvfb :99 -screen 0 1280x720x24 &
sleep 1

# 2. x11vnc (pre-built, libs in /opt/vnc)
echo "[VNC] Starting x11vnc on :5900"
LD_LIBRARY_PATH=/opt/vnc/usr/lib/x86_64-linux-gnu:/opt/vnc/lib/x86_64-linux-gnu \
  /opt/vnc/usr/bin/x11vnc -display :99 -forever -passwd "$VNC_PASSWORD" \
  -rfbport 5900 -quiet &
sleep 1

# 3. websockify (WebSocket → TCP bridge)
echo "[VNC] Starting websockify on :6080"
/opt/hermes/.venv/bin/python -m websockify 127.0.0.1:6080 127.0.0.1:5900 &

# 4. nginx (pre-configured in image)
echo "[VNC] Starting nginx on :80"
sed -i 's/^user www-data/user hermes/' /etc/nginx/nginx.conf
ln -sf /etc/nginx/sites-available/workspace /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
/usr/sbin/nginx

echo "[VNC] Ready. Password: $VNC_PASSWORD"
echo "[VNC] noVNC: http://localhost:80/vnc/vnc.html"
