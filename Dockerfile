# ── Hermes Workspace VNC Image ──
# Extends the Hermes public image with pre-baked VNC dependencies.
# Repository: https://github.com/aicodewith-team/hermes-workspace-image
# Image:      ghcr.io/aicodewith-team/hermes-workspace-vnc
#
# ⚠️ Always use SHA256 digest for the FROM image, not tags.
# Hermes tags are mutable and can cause non-reproducible builds.
# Update the digest when upgrading Hermes versions.

FROM nousresearch/hermes-agent@sha256:2bba4ab37729ebdd864d4caf277b24fec4cd8bfc2855185fd9f4c90f9bf7bfa3

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

# Runtime defaults — HERMES_WEBUI_GATEWAY_API_KEY is injected at runtime by Nomad template
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes \
    HERMES_WEBUI_CHAT_BACKEND=gateway \
    HERMES_WEBUI_GATEWAY_BASE_URL=http://127.0.0.1:8642 \
    HERMES_WEBUI_HOST=127.0.0.1 \
    HERMES_WEBUI_PORT=8787
