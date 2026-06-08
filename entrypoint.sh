#!/usr/bin/env bash
# ── Hermes Workspace entrypoint ──
# Single startup contract for the workspace container. Reads its config from
# environment variables only (the Nomad template just fills these in) and
# branches on ENABLE_VNC. This replaces the inline shell that used to live in
# the control-plane Nomad template (see docs/workspace-image-refactor.md §4.2).
#
# Required env:
#   HERMES_HOME       agent home (config.yaml + public/ live here)
#   MODEL_ID          default model
#   PROVIDER_NAME     custom provider name
#   OPENAI_BASE_URL   provider base_url (LLM API endpoint)
#   API_SERVER_KEY    gateway API key (also used by webui bridge)
# Mode switch:
#   ENABLE_VNC=true|false   (default false)
set -euo pipefail

PY=/opt/hermes/.venv/bin/python3
HERMES=/opt/hermes/.venv/bin/hermes

: "${HERMES_HOME:?HERMES_HOME is required}"
: "${MODEL_ID:?MODEL_ID is required}"
: "${PROVIDER_NAME:?PROVIDER_NAME is required}"
: "${OPENAI_BASE_URL:=}"
: "${API_SERVER_KEY:=}"

mkdir -p "$HERMES_HOME" "$HERMES_HOME/public"

# ── 1. Generate config.yaml ──
# Format must match the old template printf exactly: a custom_providers LIST.
cat > "$HERMES_HOME/config.yaml" <<EOF
model:
  default: ${MODEL_ID}
  provider: custom:${PROVIDER_NAME}
custom_providers:
  - name: ${PROVIDER_NAME}
    base_url: ${OPENAI_BASE_URL}
    key_env: LLM_API_KEY
    api_mode: chat_completions
    model: ${MODEL_ID}
EOF

# Minimal validation — guards against the dict-vs-list mistake that caused
# "Unknown provider" incidents. Fails the container start loudly if malformed.
"$PY" - "$HERMES_HOME/config.yaml" <<'PYEOF'
import sys, yaml
with open(sys.argv[1]) as fh:
    cfg = yaml.safe_load(fh)
providers = cfg.get("custom_providers")
if not isinstance(providers, list):
    sys.exit(f"[entrypoint] config.yaml invalid: custom_providers must be a list, got {type(providers).__name__}")
print("[entrypoint] config.yaml validated (custom_providers is a list)")
PYEOF

# ── 2. hermes-webui (both modes) ──
# Non-VNC maps :8787 straight to the host, so webui must bind 0.0.0.0.
# In VNC mode nginx fronts it, but 0.0.0.0 is still fine.
echo "[entrypoint] Starting hermes-webui on 0.0.0.0:${HERMES_WEBUI_PORT:-8787}"
HERMES_WEBUI_GATEWAY_API_KEY="$API_SERVER_KEY" \
HERMES_WEBUI_HOST=0.0.0.0 \
  "$PY" /opt/hermes-webui/server.py &

# ── 3. VNC stack (ENABLE_VNC=true only) ──
if [ "${ENABLE_VNC:-false}" = "true" ]; then
    echo "[entrypoint] ENABLE_VNC=true — starting VNC stack + dashboard"
    /opt/vnc/start-vnc.sh
    "$HERMES" dashboard --host 0.0.0.0 --port 9119 --no-open --insecure &
fi

# ── 4. Main process (PID 1) ──
# exec so gateway becomes PID 1, receives nomad stop's SIGTERM, and exits
# cleanly. Without exec, bash swallows the signal and Nomad SIGKILLs us.
echo "[entrypoint] exec hermes gateway run --no-supervise"
exec "$HERMES" gateway run --no-supervise
