#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
pack_root="$(cd "$script_dir/.." && pwd)"
export OPENCLAW_PROFILE_NAME="${OPENCLAW_PROFILE_NAME:-usb-portable}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18889}"

if [[ -z "${FEISHU_APP_ID:-}" ]]; then
  read -r -p "FEISHU_APP_ID: " FEISHU_APP_ID
  export FEISHU_APP_ID
fi
if [[ -z "${FEISHU_APP_SECRET:-}" ]]; then
  read -r -s -p "FEISHU_APP_SECRET: " FEISHU_APP_SECRET
  printf '\n'
  export FEISHU_APP_SECRET
fi
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  read -r -s -p "OPENAI_API_KEY: " OPENAI_API_KEY
  printf '\n'
  export OPENAI_API_KEY
fi
if [[ -z "${OPENAI_BASE_URL:-}" ]]; then
  read -r -p "OPENAI_BASE_URL (optional, press Enter to skip): " OPENAI_BASE_URL || true
  export OPENAI_BASE_URL
fi

bash "$pack_root/scripts/openclaw-usb/install-local-feishu.sh" \
  --profile "$OPENCLAW_PROFILE_NAME" \
  --port "$OPENCLAW_GATEWAY_PORT"

echo
echo "Done. Press Enter to close."
read -r _
