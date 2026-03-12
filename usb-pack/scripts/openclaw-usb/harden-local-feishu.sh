#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
runtime_root="${USB_RUNTIME_ROOT:-${project_root}/runtime}"
BUNDLED_NODE_CMD="${runtime_root}/node/bin/node"
BUNDLED_OPENCLAW_ENTRY="${runtime_root}/openclaw/openclaw.mjs"
NODE_CMD=""
OPENCLAW_MODE="none"

OPENCLAW_PROFILE_NAME="${OPENCLAW_PROFILE_NAME:-usb-portable}"
OPENCLAW_DM_POLICY="${OPENCLAW_DM_POLICY:-pairing}"
OPENCLAW_ALLOW_FROM_JSON="${OPENCLAW_ALLOW_FROM_JSON:-[]}"
OPENCLAW_REQUIRE_MENTION="${OPENCLAW_REQUIRE_MENTION:-true}"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/openclaw-usb/harden-local-feishu.sh [options]

Options:
  --profile <name>           OpenClaw isolated profile. Default: usb-portable
  --dm-policy <mode>         pairing | allowlist | open. Default: pairing
  --allow-from-json <json>   Feishu allowFrom JSON. Default: []
  --require-mention <bool>   true | false. Default: true
  -h, --help                 Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      OPENCLAW_PROFILE_NAME="$2"
      shift 2
      ;;
    --dm-policy)
      OPENCLAW_DM_POLICY="$2"
      shift 2
      ;;
    --allow-from-json)
      OPENCLAW_ALLOW_FROM_JSON="$2"
      shift 2
      ;;
    --require-mention)
      OPENCLAW_REQUIRE_MENTION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

resolve_runtime() {
  if [[ -x "$BUNDLED_NODE_CMD" ]]; then
    NODE_CMD="$BUNDLED_NODE_CMD"
  elif command -v node >/dev/null 2>&1; then
    NODE_CMD="$(command -v node)"
  else
    NODE_CMD=""
  fi

  if [[ -n "$NODE_CMD" && -f "$BUNDLED_OPENCLAW_ENTRY" ]]; then
    OPENCLAW_MODE="bundled"
  elif command -v openclaw >/dev/null 2>&1; then
    OPENCLAW_MODE="global"
  else
    OPENCLAW_MODE="none"
  fi
}

oc_raw() {
  case "$OPENCLAW_MODE" in
    bundled)
      "$NODE_CMD" "$BUNDLED_OPENCLAW_ENTRY" "$@"
      ;;
    global)
      openclaw "$@"
      ;;
    *)
      echo "[ERROR] OpenClaw runtime is unavailable." >&2
      exit 1
      ;;
  esac
}

oc() {
  oc_raw --profile "$OPENCLAW_PROFILE_NAME" "$@"
}

resolve_runtime
[[ -n "$NODE_CMD" ]] || { echo "[ERROR] Node runtime not found." >&2; exit 1; }
[[ "$OPENCLAW_MODE" != "none" ]] || { echo "[ERROR] OpenClaw runtime not found." >&2; exit 1; }

case "$OPENCLAW_DM_POLICY" in
  pairing|allowlist|open) ;;
  *) echo "[ERROR] Unsupported dm policy: ${OPENCLAW_DM_POLICY}" >&2; exit 1 ;;
esac
case "$OPENCLAW_REQUIRE_MENTION" in
  true|false) ;;
  *) echo "[ERROR] require-mention must be true or false" >&2; exit 1 ;;
esac
"$NODE_CMD" -e 'JSON.parse(process.argv[1])' "$OPENCLAW_ALLOW_FROM_JSON" >/dev/null 2>&1 || {
  echo "[ERROR] Invalid JSON for allowFrom" >&2
  exit 1
}

oc config set channels.feishu.dmPolicy "\"${OPENCLAW_DM_POLICY}\"" --strict-json
oc config set channels.feishu.allowFrom "$OPENCLAW_ALLOW_FROM_JSON" --strict-json
oc config set channels.feishu.requireMention "$OPENCLAW_REQUIRE_MENTION" --strict-json
oc daemon restart
oc channels status --probe

echo "[DONE] Hardened profile ${OPENCLAW_PROFILE_NAME} to dmPolicy=${OPENCLAW_DM_POLICY}."
