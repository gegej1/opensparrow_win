#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
runtime_root="${USB_RUNTIME_ROOT:-${project_root}/runtime}"
if [[ -d "${project_root}/longrun/workspaces/openclaw-usb-portable/execution" ]]; then
  default_execution_root="${project_root}/longrun/workspaces/openclaw-usb-portable/execution"
else
  default_execution_root="${project_root}/.openclaw-usb-runtime"
fi
default_logs_dir="${default_execution_root}/logs"
default_evidence_root="${default_execution_root}/evidence"

OPENCLAW_PROFILE_NAME="${OPENCLAW_PROFILE_NAME:-usb-portable}"
OPENCLAW_AGENT_ID="${OPENCLAW_AGENT_ID:-main}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18889}"
OPENCLAW_MODEL="${OPENCLAW_MODEL:-openai/gpt-4o-mini}"
OPENCLAW_DM_POLICY="${OPENCLAW_DM_POLICY:-open}"
OPENCLAW_ALLOW_FROM_JSON="${OPENCLAW_ALLOW_FROM_JSON:-[\"*\"]}"
OPENCLAW_REQUIRE_MENTION="${OPENCLAW_REQUIRE_MENTION:-false}"
FEISHU_DOMAIN="${FEISHU_DOMAIN:-feishu}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
LOG_DIR="${LOG_DIR:-${default_logs_dir}}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${default_evidence_root}/$(date +%Y%m%d-%H%M%S)-install}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
PORT_SCAN_LIMIT="${OPENCLAW_PORT_SCAN_LIMIT:-50}"

FEISHU_APP_ID="${FEISHU_APP_ID:-}"
FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

NODE_CMD=""
OPENCLAW_MODE="none"
BUNDLED_NODE_CMD="${runtime_root}/node/bin/node"
BUNDLED_OPENCLAW_ENTRY="${runtime_root}/openclaw/openclaw.mjs"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/openclaw-usb/install-local-feishu.sh [options]

Options:
  --profile <name>            OpenClaw isolated profile name. Default: usb-portable
  --agent <id>                Agent id to configure. Default: main
  --port <port>               Dedicated gateway port for this isolated profile. Default: 18889
  --model <provider/model>    Default model. Default: openai/gpt-4o-mini
  --dm-policy <mode>          Feishu DM policy. Default: open
  --allow-from-json <json>    Feishu allowFrom JSON. Default: ["*"]
  --require-mention <bool>    Whether mentions are required. Default: false
  --base-url <url>            Optional OpenAI-compatible base URL
  --feishu-app-id <value>     Optional CLI injection. Prefer env/interactive input.
  --feishu-app-secret <value> Optional CLI injection. Prefer env/interactive input.
  --openai-api-key <value>    Optional CLI injection. Prefer env/interactive input.
  --log-dir <path>            Installer log directory
  --evidence-dir <path>       Evidence directory for status/probe outputs
  --non-interactive           Fail instead of prompting for missing secrets
  -h, --help                  Show help

Port behavior:
  - Preferred port defaults to 18889
  - If the requested port is occupied, the installer automatically scans the next free port

Runtime resolution order:
  1) bundled Node/OpenClaw under ./runtime/
  2) system node/openclaw
  3) npm install -g openclaw (if openclaw is missing)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      OPENCLAW_PROFILE_NAME="$2"
      shift 2
      ;;
    --agent)
      OPENCLAW_AGENT_ID="$2"
      shift 2
      ;;
    --port)
      OPENCLAW_GATEWAY_PORT="$2"
      shift 2
      ;;
    --model)
      OPENCLAW_MODEL="$2"
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
    --base-url)
      OPENAI_BASE_URL="$2"
      shift 2
      ;;
    --feishu-app-id)
      FEISHU_APP_ID="$2"
      shift 2
      ;;
    --feishu-app-secret)
      FEISHU_APP_SECRET="$2"
      shift 2
      ;;
    --openai-api-key)
      OPENAI_API_KEY="$2"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --evidence-dir)
      EVIDENCE_DIR="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
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

profile_state_dir="${HOME}/.openclaw-${OPENCLAW_PROFILE_NAME}"
profile_workspace_dir="${profile_state_dir}/workspace"
profile_agent_dir="${profile_state_dir}/agents/${OPENCLAW_AGENT_ID}/agent"
auth_profiles_file="${profile_agent_dir}/auth-profiles.json"
install_log_file="${LOG_DIR}/install-${OPENCLAW_PROFILE_NAME}-$(date +%Y%m%d-%H%M%S).log"

log() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

fail() {
  log ERROR "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

resolve_runtime() {
  if [[ -x "$BUNDLED_NODE_CMD" ]]; then
    NODE_CMD="$BUNDLED_NODE_CMD"
  elif command_exists node; then
    NODE_CMD="$(command -v node)"
  else
    NODE_CMD=""
  fi

  if [[ -n "$NODE_CMD" && -f "$BUNDLED_OPENCLAW_ENTRY" ]]; then
    OPENCLAW_MODE="bundled"
  elif command_exists openclaw; then
    OPENCLAW_MODE="global"
  else
    OPENCLAW_MODE="none"
  fi
}

require_node() {
  [[ -n "$NODE_CMD" ]] || fail "Node runtime not found. Install Node.js or provide runtime/node/bin/node in the package."
}

prompt_secret() {
  local var_name="$1"
  local label="$2"
  local secret_mode="$3"
  local current_value="${!var_name:-}"
  if [[ -n "$current_value" ]]; then
    return 0
  fi
  if [[ "$NON_INTERACTIVE" == "1" || ! -t 0 ]]; then
    fail "${label} is required. Provide it via env or CLI flag."
  fi
  if [[ "$secret_mode" == "secret" ]]; then
    read -r -s -p "${label}: " current_value
    printf '\n'
  else
    read -r -p "${label}: " current_value
  fi
  [[ -n "$current_value" ]] || fail "${label} cannot be empty."
  printf -v "$var_name" '%s' "$current_value"
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
      fail "OpenClaw runtime is unavailable."
      ;;
  esac
}

oc() {
  oc_raw --profile "$OPENCLAW_PROFILE_NAME" "$@"
}

validate_json() {
  local json_payload="$1"
  "$NODE_CMD" -e 'JSON.parse(process.argv[1]);' "$json_payload" >/dev/null 2>&1 || fail "Invalid JSON payload: ${json_payload}"
}

validate_bool() {
  case "$1" in
    true|false) ;;
    *) fail "Boolean flag must be true or false, got: $1" ;;
  esac
}

is_port_busy() {
  local port="$1"
  if command_exists lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if [[ -n "$NODE_CMD" ]]; then
    "$NODE_CMD" -e 'const net = require("net"); const port = Number(process.argv[1]); const server = net.createServer(); server.once("error", (err) => { if (err && (err.code === "EADDRINUSE" || err.code === "EACCES")) process.exit(0); process.exit(2); }); server.once("listening", () => server.close(() => process.exit(1))); server.listen({ host: "127.0.0.1", port, exclusive: true });' "$port" >/dev/null 2>&1
    case $? in
      0) return 0 ;;
      1) return 1 ;;
      *) return 0 ;;
    esac
  fi
  return 1
}

find_available_port() {
  local start_port="$1"
  local max_attempts="$2"
  local candidate_port="$start_port"
  local attempt
  for ((attempt=0; attempt<max_attempts; attempt+=1)); do
    if ! is_port_busy "$candidate_port"; then
      printf '%s\n' "$candidate_port"
      return 0
    fi
    candidate_port=$((candidate_port + 1))
  done
  return 1
}

resolve_gateway_port() {
  local requested_port="$1"
  if ! is_port_busy "$requested_port"; then
    return 0
  fi
  local fallback_port
  fallback_port="$(find_available_port "$((requested_port + 1))" "$PORT_SCAN_LIMIT")" || fail "Port ${requested_port} is busy and no free fallback port was found within ${PORT_SCAN_LIMIT} attempts."
  log WARN "Port ${requested_port} is already listening; automatically switching to ${fallback_port}."
  OPENCLAW_GATEWAY_PORT="$fallback_port"
}

capture_cmd() {
  local output_file="$1"
  shift
  if "$@" >"${output_file}" 2>&1; then
    return 0
  fi
  cat "${output_file}" >&2
  return 1
}

ensure_openclaw_available() {
  resolve_runtime
  require_node

  case "$OPENCLAW_MODE" in
    bundled)
      log INFO "Using bundled OpenClaw runtime: ${BUNDLED_OPENCLAW_ENTRY}"
      ;;
    global)
      log INFO "Using global openclaw: $(command -v openclaw) ($(oc_raw --version || true))"
      ;;
    none)
      command_exists npm || fail "npm not found. Install npm or provide bundled OpenClaw runtime under runtime/openclaw/."
      log INFO "openclaw not found, installing with npm -g"
      npm install -g openclaw || fail "npm install -g openclaw failed. Check npm permissions or use the bundled runtime."
      resolve_runtime
      [[ "$OPENCLAW_MODE" != "none" ]] || fail "OpenClaw is still unavailable after npm install."
      ;;
  esac
}

upsert_auth_profile() {
  mkdir -p "$profile_agent_dir"
  "$NODE_CMD" - "$auth_profiles_file" "$OPENAI_API_KEY" <<'NODE'
const fs = require('fs');
const [authFile, apiKey] = process.argv.slice(2);
let store = { version: 1, profiles: {}, order: {} };
if (fs.existsSync(authFile)) {
  store = JSON.parse(fs.readFileSync(authFile, 'utf8'));
}
if (!store || typeof store !== 'object') store = { version: 1, profiles: {}, order: {} };
if (!store.profiles || typeof store.profiles !== 'object') store.profiles = {};
if (!store.order || typeof store.order !== 'object') store.order = {};
store.version = 1;
store.profiles['openai:default'] = {
  type: 'api_key',
  provider: 'openai',
  key: apiKey
};
store.order.openai = ['openai:default'];
fs.mkdirSync(require('path').dirname(authFile), { recursive: true });
fs.writeFileSync(authFile, JSON.stringify(store, null, 2) + '\n', { mode: 0o600 });
NODE
  chmod 600 "$auth_profiles_file"
}

configure_openai_provider() {
  if [[ -z "$OPENAI_BASE_URL" ]]; then
    return 0
  fi
  local provider_model_id="$OPENCLAW_MODEL"
  if [[ "$provider_model_id" == openai/* ]]; then
    provider_model_id="${provider_model_id#openai/}"
  fi
  local provider_json
  provider_json="$("$NODE_CMD" -e 'const [baseUrl, modelId] = process.argv.slice(1); process.stdout.write(JSON.stringify({ baseUrl, models: [{ id: modelId, name: modelId, api: "openai-completions" }] }));' "$OPENAI_BASE_URL" "$provider_model_id")"
  oc config set models.providers.openai "$provider_json" --strict-json
}

wait_for_gateway() {
  local health_file="$1"
  local attempts=20
  local sleep_seconds=2
  local attempt
  for ((attempt=1; attempt<=attempts; attempt+=1)); do
    if capture_cmd "$health_file" oc health --json --timeout 5000; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

resolve_runtime
require_node
validate_json "$OPENCLAW_ALLOW_FROM_JSON"
validate_bool "$OPENCLAW_REQUIRE_MENTION"
[[ "$OPENCLAW_GATEWAY_PORT" =~ ^[0-9]+$ ]] || fail "Gateway port must be numeric."
[[ "$PORT_SCAN_LIMIT" =~ ^[0-9]+$ ]] || fail "Port scan limit must be numeric."
(( PORT_SCAN_LIMIT > 0 )) || fail "Port scan limit must be positive."
requested_gateway_port="$OPENCLAW_GATEWAY_PORT"

prompt_secret FEISHU_APP_ID "FEISHU_APP_ID" plain
prompt_secret FEISHU_APP_SECRET "FEISHU_APP_SECRET" secret
prompt_secret OPENAI_API_KEY "OPENAI_API_KEY" secret

mkdir -p "$LOG_DIR" "$EVIDENCE_DIR" "$profile_workspace_dir" "$profile_agent_dir"
exec > >(tee -a "$install_log_file") 2>&1

resolve_gateway_port "$requested_gateway_port"

log INFO "Installing into isolated profile: ${OPENCLAW_PROFILE_NAME}"
log INFO "Isolated state dir: ${profile_state_dir}"
log INFO "Isolated workspace dir: ${profile_workspace_dir}"
log INFO "Requested gateway port: ${requested_gateway_port}"
log INFO "Dedicated gateway port: ${OPENCLAW_GATEWAY_PORT}"
log INFO "Evidence dir: ${EVIDENCE_DIR}"
log INFO "Log file: ${install_log_file}"
log INFO "Runtime root candidate: ${runtime_root}"
log INFO "Node runtime: ${NODE_CMD}"

ensure_openclaw_available

log INFO "Writing isolated OpenClaw config"
oc config set gateway.mode '"local"' --strict-json
oc config set gateway.bind '"loopback"' --strict-json
oc config set gateway.port "$OPENCLAW_GATEWAY_PORT" --strict-json
oc config set agents.defaults.workspace "\"${profile_workspace_dir}\"" --strict-json
oc config set plugins.entries.feishu.enabled true --strict-json
oc config set channels.feishu.enabled true --strict-json
oc config set channels.feishu.connectionMode '"websocket"' --strict-json
oc config set channels.feishu.domain "\"${FEISHU_DOMAIN}\"" --strict-json
oc config set channels.feishu.appId "\"${FEISHU_APP_ID}\"" --strict-json
oc config set channels.feishu.appSecret "\"${FEISHU_APP_SECRET}\"" --strict-json
oc config set channels.feishu.dmPolicy "\"${OPENCLAW_DM_POLICY}\"" --strict-json
oc config set channels.feishu.allowFrom "$OPENCLAW_ALLOW_FROM_JSON" --strict-json
oc config set channels.feishu.requireMention "$OPENCLAW_REQUIRE_MENTION" --strict-json

log INFO "Writing isolated auth-profiles.json"
upsert_auth_profile

log INFO "Configuring model provider"
configure_openai_provider
oc models set "$OPENCLAW_MODEL"

log INFO "Validating isolated config"
capture_cmd "${EVIDENCE_DIR}/config-validate.json" oc config validate --json

log INFO "Installing/reinstalling isolated daemon service"
oc daemon install --force --port "$OPENCLAW_GATEWAY_PORT"
log INFO "Restarting isolated daemon service"
oc daemon restart

log INFO "Waiting for gateway health"
if ! wait_for_gateway "${EVIDENCE_DIR}/health.json"; then
  capture_cmd "${EVIDENCE_DIR}/daemon-status.txt" oc daemon status || true
  capture_cmd "${EVIDENCE_DIR}/gateway-logs.txt" oc logs --plain --limit 200 --timeout 5000 || true
  fail "Gateway did not become healthy. See ${EVIDENCE_DIR}/daemon-status.txt and ${EVIDENCE_DIR}/gateway-logs.txt"
fi

log INFO "Capturing daemon status"
capture_cmd "${EVIDENCE_DIR}/daemon-status.txt" oc daemon status
log INFO "Capturing channel probe"
capture_cmd "${EVIDENCE_DIR}/channels-probe.json" oc channels status --probe --json --timeout 10000
log INFO "Running agent smoke test"
capture_cmd "${EVIDENCE_DIR}/agent-smoke.json" oc agent --agent "$OPENCLAW_AGENT_ID" --message "请只回复OK" --json

cat > "${EVIDENCE_DIR}/session-metadata.txt" <<META
profile=${OPENCLAW_PROFILE_NAME}
state_dir=${profile_state_dir}
workspace_dir=${profile_workspace_dir}
config_file=${profile_state_dir}/openclaw.json
agent_auth_file=${auth_profiles_file}
requested_gateway_port=${requested_gateway_port}
gateway_port=${OPENCLAW_GATEWAY_PORT}
model=${OPENCLAW_MODEL}
dm_policy=${OPENCLAW_DM_POLICY}
allow_from=${OPENCLAW_ALLOW_FROM_JSON}
require_mention=${OPENCLAW_REQUIRE_MENTION}
log_file=${install_log_file}
runtime_root=${runtime_root}
node_cmd=${NODE_CMD}
openclaw_mode=${OPENCLAW_MODE}
META

cat <<EOF2
[DONE] OpenClaw local portable baseline is configured.

Isolation summary:
- profile: ${OPENCLAW_PROFILE_NAME}
- isolated state: ${profile_state_dir}
- isolated workspace: ${profile_workspace_dir}
- requested port: ${requested_gateway_port}
- dedicated port: ${OPENCLAW_GATEWAY_PORT}
- evidence: ${EVIDENCE_DIR}
- openclaw mode: ${OPENCLAW_MODE}

Manual checks:
1) openclaw --profile ${OPENCLAW_PROFILE_NAME} channels status --probe
2) openclaw --profile ${OPENCLAW_PROFILE_NAME} agent --agent ${OPENCLAW_AGENT_ID} --message "请只回复OK" --json
3) 在飞书里给机器人发送 ok，确认能收到回复
4) 完成联调后运行 harden 脚本收口权限
EOF2
