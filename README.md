# Hermes Workspace VNC Image

[![Build and Publish](https://github.com/aicodewith-team/hermes-workspace-image/actions/workflows/build.yml/badge.svg)](https://github.com/aicodewith-team/hermes-workspace-image/actions/workflows/build.yml)

Pre-baked Docker image for Hermes agent workspaces that require VNC browser access. Extends the official [`nousresearch/hermes-agent`](https://github.com/nousresearch/hermes-agent) image with:

- **Xvfb** — virtual framebuffer (headless display)
- **x11vnc** — VNC server (with Debian snapshot libraries baked at build time)
- **websockify** — WebSocket-to-TCP bridge
- **noVNC 1.5.0** — browser-based VNC client
- **nginx** — HTTP server for static files + WebSocket proxy

**Image:** `ghcr.io/aicodewith-team/hermes-workspace-vnc`

## Startup contract (`entrypoint.sh`)

The image owns its full startup contract. `entrypoint.sh` (the `ENTRYPOINT`) reads
**environment variables only** and branches on `ENABLE_VNC`:

| Env | Required | Purpose |
|---|---|---|
| `HERMES_HOME` | ✅ | agent home — `config.yaml` + `public/` live here |
| `MODEL_ID` | ✅ | default model |
| `PROVIDER_NAME` | ✅ | custom provider name |
| `OPENAI_BASE_URL` | ✅ | provider `base_url` (LLM endpoint) |
| `API_SERVER_KEY` | ✅ | gateway API key (also used by the webui bridge) |
| `ENABLE_VNC` | — | `true`/`false` (default `false`) |

On boot it: generates `$HERMES_HOME/config.yaml` (validating that `custom_providers`
is a list), starts hermes-webui on `0.0.0.0:8787`, optionally starts the VNC stack +
`hermes dashboard` (`ENABLE_VNC=true`), then `exec`s `hermes gateway run --no-supervise`
as PID 1 so it receives `SIGTERM` on shutdown.

```bash
# Non-VNC
docker run -d -e ENABLE_VNC=false \
  -e MODEL_ID=claude-opus-4-7 -e PROVIDER_NAME=mergio-api \
  -e OPENAI_BASE_URL=https://mergio.ai/api/gateway/v1 \
  -e LLM_API_KEY=... -e API_SERVER_KEY=... -e HERMES_HOME=/tmp/home \
  -e API_SERVER_ENABLED=true -e API_SERVER_HOST=0.0.0.0 -e API_SERVER_PORT=8642 \
  -e HERMES_DASHBOARD=1 -p 9119:9119 -p 8642:8642 \
  ghcr.io/aicodewith-team/hermes-workspace-vnc:latest
```

## Quick Start

```bash
# Pull the image (use digest for reproducibility)
docker pull ghcr.io/aicodewith-team/hermes-workspace-vnc:latest

# Run a container with VNC enabled (entrypoint.sh starts the VNC stack)
docker run -d --name hermes-vnc \
  -e ENABLE_VNC=true \
  -e MODEL_ID=claude-opus-4-7 -e PROVIDER_NAME=mergio-api \
  -e OPENAI_BASE_URL=https://mergio.ai/api/gateway/v1 \
  -e LLM_API_KEY=... -e API_SERVER_KEY=... -e HERMES_HOME=/opt/data/home \
  -p 80:80 \
  -v hermes-data:/opt/data \
  ghcr.io/aicodewith-team/hermes-workspace-vnc:latest

# Open http://localhost/vnc/vnc.html in your browser
```

## Build Locally

```bash
docker build -t hermes-workspace-vnc .
```

## CI/CD

Pushes to `main` that modify `Dockerfile`, `entrypoint.sh`, `start-vnc.sh`, or `nginx-workspace.conf` automatically build and push to `ghcr.io/aicodewith-team/hermes-workspace-vnc` with tags:
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
├── entrypoint.sh           # Startup contract (config.yaml + webui + gateway)
├── start-vnc.sh            # VNC stack launcher (called by entrypoint when ENABLE_VNC=true)
├── nginx-workspace.conf    # Nginx configuration
├── .github/
│   └── workflows/
│       └── build.yml       # CI pipeline
└── README.md
```
