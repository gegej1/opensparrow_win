#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}" )/../../../../.." && pwd)"
default_config="${HOME}/.openclaw/openclaw.json"
default_auth="${HOME}/.openclaw/agents/main/agent/auth-profiles.json"
evidence_dir="${project_root}/longrun/workspaces/openclaw-usb-portable/execution/evidence/f001-local-defaults-$(date +%Y%m%d-%H%M%S)"

[[ -f "$default_config" ]] || { echo "[ERROR] Missing default config: $default_config" >&2; exit 1; }
[[ -f "$default_auth" ]] || { echo "[ERROR] Missing default auth: $default_auth" >&2; exit 1; }

FEISHU_APP_ID="$(jq -r '.channels.feishu.appId // empty' "$default_config")"
FEISHU_APP_SECRET="$(jq -r '.channels.feishu.appSecret // empty' "$default_config")"
OPENAI_BASE_URL="$(jq -r '.models.providers.openai.baseUrl // empty' "$default_config")"
OPENAI_API_KEY="$(jq -r '.profiles["openai:default"].key // empty' "$default_auth")"

[[ -n "$FEISHU_APP_ID" ]] || { echo "[ERROR] default profile missing channels.feishu.appId" >&2; exit 1; }
[[ -n "$FEISHU_APP_SECRET" ]] || { echo "[ERROR] default profile missing channels.feishu.appSecret" >&2; exit 1; }
[[ -n "$OPENAI_API_KEY" ]] || { echo "[ERROR] default profile missing openai:default key" >&2; exit 1; }

export FEISHU_APP_ID
export FEISHU_APP_SECRET
export OPENAI_API_KEY
export OPENAI_BASE_URL
export OPENCLAW_PROFILE_NAME="usb-portable"
export OPENCLAW_GATEWAY_PORT="18889"
export EVIDENCE_DIR="$evidence_dir"
export LOG_DIR="${project_root}/longrun/workspaces/openclaw-usb-portable/execution/logs"

bash "${project_root}/scripts/openclaw-usb/install-local-feishu.sh" \
  --profile "$OPENCLAW_PROFILE_NAME" \
  --port "$OPENCLAW_GATEWAY_PORT" \
  --evidence-dir "$EVIDENCE_DIR" \
  --log-dir "$LOG_DIR"
