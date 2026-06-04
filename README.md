# Hermes Workspace VNC Image

[![Build and Publish](https://github.com/aicodewith-team/hermes-workspace-image/actions/workflows/build.yml/badge.svg)](https://github.com/aicodewith-team/hermes-workspace-image/actions/workflows/build.yml)

Pre-baked Docker image for Hermes agent workspaces that require VNC browser access. Extends the official [`nousresearch/hermes-agent`](https://github.com/nousresearch/hermes-agent) image with:

- **Xvfb** — virtual framebuffer (headless display)
- **x11vnc** — VNC server (with Debian snapshot libraries baked at build time)
- **websockify** — WebSocket-to-TCP bridge
- **noVNC 1.5.0** — browser-based VNC client
- **nginx** — HTTP server for static files + WebSocket proxy

**Image:** `ghcr.io/aicodewith-team/hermes-workspace-vnc`

## Quick Start

```bash
# Pull the image (use digest for reproducibility)
docker pull ghcr.io/aicodewith-team/hermes-workspace-vnc:latest

# Run a container with VNC enabled
docker run -d --name hermes-vnc \
  -p 80:80 \
  -v hermes-data:/opt/data \
  ghcr.io/aicodewith-team/hermes-workspace-vnc:latest

# Inside the container, launch the VNC stack
docker exec hermes-vnc bash /opt/vnc/start-vnc.sh

# Open http://localhost/vnc/vnc.html in your browser
```

## Build Locally

```bash
docker build -t hermes-workspace-vnc .
```

## CI/CD

Pushes to `main` that modify `Dockerfile`, `start-vnc.sh`, or `nginx-workspace.conf` automatically build and push to `ghcr.io/aicodewith-team/hermes-workspace-vnc` with tags:
- `latest`
- `<git-sha>` (for pinning to specific builds)

## Upgrading the Hermes Base Image

1. Find the latest verified Hermes image digest:
   ```bash
   docker pull nousresearch/hermes-agent:latest
   docker inspect nousresearch/hermes-agent:latest --format='{{index .RepoDigests 0}}'
   ```

2. Update the `FROM` line in `Dockerfile` with the new SHA256 digest.

3. Commit and push — CI handles the rest.

## File Structure

```
├── Dockerfile              # Image definition
├── start-vnc.sh            # VNC stack launcher
├── nginx-workspace.conf    # Nginx configuration
├── .github/
│   └── workflows/
│       └── build.yml       # CI pipeline
└── README.md
```
