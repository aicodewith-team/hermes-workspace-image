# ── Hermes Workspace VNC Image ──
# Extends the Hermes public image with pre-baked VNC dependencies.
# Repository: https://github.com/aicodewith-team/hermes-workspace-image
# Image:      ghcr.io/aicodewith-team/hermes-workspace-vnc
#
# ⚠️ Always use SHA256 digest for the FROM image, not tags.
# Hermes tags are mutable and can cause non-reproducible builds.
# Update the digest when upgrading Hermes versions.

FROM nousresearch/hermes-agent@sha256:b89ec23f35fbdbdafa754551d94bbca64b1a9a53db8c3a9885654abcd81d114b

# ── VNC runtime packages (apt) ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    nginx \
    libgcrypt20 liblzo2-2 libxtst6 libxinerama1 libx11-xcb1 \
    libxrandr2 libxfixes3 libxdamage1 libxi6 \
    && rm -rf /var/lib/apt/lists/*

# ── x11vnc (Debian snapshot libraries + apt binary, bake at build time) ──
# NOTE: libvncserver1/libvncclient1 removed from Trixie → must use snapshot.
# x11vnc binary is still available in Trixie apt.
RUN mkdir -p /opt/vnc && cd /opt/vnc && \
    apt-get update && apt-get download x11vnc && \
    for url in \
      "https://snapshot.debian.org/archive/debian/20250501T024231Z/pool/main/libv/libvncserver/libvncserver1_0.9.15+dfsg-1_amd64.deb" \
      "https://snapshot.debian.org/archive/debian/20250501T024231Z/pool/main/libv/libvncserver/libvncclient1_0.9.15+dfsg-1_amd64.deb"; \
    do curl -sLO "$url"; done && \
    for deb in *.deb; do dpkg -x "$deb" .; done && \
    rm *.deb && rm -rf /var/lib/apt/lists/*

# ── websockify (Python WebSocket→TCP bridge) ──
# NOTE: Hermes venv has no pip — use /usr/local/bin/uv instead.
RUN /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python3 websockify

# ── noVNC 1.5.0 (static HTML client) ──
# NOTE: noVNC 1.5.0 has NO include/ directory (removed since v1.4.x).
# Pipe with \ continuation is unreliable in Docker RUN; download first.
RUN set -ex && \
    curl -sL https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.tar.gz -o /tmp/novnc.tar.gz && \
    tar xzf /tmp/novnc.tar.gz -C /tmp && \
    mkdir -p /opt/vnc/noVNC && \
    cp /tmp/noVNC-1.5.0/vnc.html /opt/vnc/noVNC/ && \
    cp -r /tmp/noVNC-1.5.0/app /tmp/noVNC-1.5.0/core /tmp/noVNC-1.5.0/vendor /opt/vnc/noVNC/ && \
    rm -rf /tmp/noVNC-1.5.0 /tmp/novnc.tar.gz

# ── Nginx config (pre-placed, start-vnc.sh symlinks it at runtime) ──
COPY nginx-workspace.conf /etc/nginx/sites-available/workspace

# ── Launch script ──
COPY start-vnc.sh /opt/vnc/start-vnc.sh
RUN chmod +x /opt/vnc/start-vnc.sh

# ═══════════════════════════════════════════════════════════════
# ── hermes-webui: browser-based agent management panel ──
# Gateway Bridge mode — proxies browser chat to Gateway API :8642.
# No Agent instance conflict (does NOT import AIAgent directly).
# ═══════════════════════════════════════════════════════════════
RUN git clone --depth 1 https://github.com/nesquena/hermes-webui.git \
      /opt/hermes-webui && \
    /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python3 \
      --no-cache-dir pyyaml cryptography && \
    chown -R hermes:hermes /opt/hermes-webui

# Runtime defaults — HERMES_WEBUI_GATEWAY_API_KEY / HERMES_WEBUI_HOST are set
# by entrypoint.sh at startup (host 0.0.0.0 + the gateway key).
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes \
    HERMES_WEBUI_CHAT_BACKEND=gateway \
    HERMES_WEBUI_GATEWAY_BASE_URL=http://127.0.0.1:8642 \
    HERMES_WEBUI_HOST=127.0.0.1 \
    HERMES_WEBUI_PORT=8787

# ═══════════════════════════════════════════════════════════════
# ── /publish StaticFiles mount (build-time patch) ──
# Hermes web_server.py has no /publish mount upstream. Patch it here at build
# time (not at container startup) so a structural change upstream fails the CI
# build loudly instead of silently no-op'ing on every boot.
# ═══════════════════════════════════════════════════════════════
RUN WEB_SERVER=/opt/hermes/hermes_cli/web_server.py && \
    if [ ! -f "$WEB_SERVER" ]; then \
      echo "ERROR: $WEB_SERVER not found — Hermes layout changed" >&2; exit 1; \
    fi && \
    if ! grep -q '"/publish"' "$WEB_SERVER"; then \
      sed -i '/def mount_spa(application: FastAPI):/a\    app.mount("/publish", StaticFiles(directory=get_hermes_home() / "public", html=True), name="publish")' "$WEB_SERVER" && \
      grep -q '"/publish"' "$WEB_SERVER" || { echo "ERROR: /publish patch did not apply" >&2; exit 1; } && \
      echo "[build] Patched web_server.py with /publish StaticFiles mount"; \
    fi

# ── Startup contract ──
# entrypoint.sh reads env (MODEL_ID / PROVIDER_NAME / OPENAI_BASE_URL /
# API_SERVER_KEY / ENABLE_VNC / HERMES_HOME), generates config.yaml, starts
# webui + (optionally) the VNC stack, and exec's the gateway as PID 1.
COPY entrypoint.sh /opt/vnc/entrypoint.sh
RUN chmod +x /opt/vnc/entrypoint.sh
ENTRYPOINT ["/opt/vnc/entrypoint.sh"]
