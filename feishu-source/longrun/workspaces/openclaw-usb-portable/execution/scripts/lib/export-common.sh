#!/usr/bin/env bash

set -euo pipefail

readonly OPENCLAW_USB_FEATURE_SNAPSHOT_PATHS=(
  'AGENTS.md'
  '.specify/memory/constitution.md'
  'specs/002-openclaw-usb-installer'
  'research/openclaw-usb-installer'
  'skills/openclaw-local-feishu-usb'
  'scripts/openclaw-usb'
  'longrun/workspaces/openclaw-usb-portable/app_spec.md'
  'longrun/workspaces/openclaw-usb-portable/feature_list.json'
  'longrun/workspaces/openclaw-usb-portable/init.sh'
  'longrun/workspaces/openclaw-usb-portable/claude-progress.txt'
  'longrun/workspaces/openclaw-usb-portable/execution/README.md'
  'longrun/workspaces/openclaw-usb-portable/execution/docs'
  'longrun/workspaces/openclaw-usb-portable/execution/runbooks'
  'longrun/workspaces/openclaw-usb-portable/execution/scripts'
)

usb_exec_workspace_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

usb_project_root() {
  local workspace_dir="$1"
  cd "${workspace_dir}/../../../.." && pwd
}

usb_prepare_export_root() {
  local export_root="$1"
  local archive_path="$2"
  rm -rf "$export_root" "$archive_path"
  mkdir -p "$export_root"
}

usb_stage_pack_dir() {
  local workspace_dir="$1"
  printf '%s\n' "${workspace_dir}/delivery-pack/staged/openclaw-usb-pack"
}

usb_build_stage_pack() {
  local workspace_dir="$1"
  bash "${workspace_dir}/scripts/build-delivery-pack.sh"
}

usb_copy_stage_pack() {
  local workspace_dir="$1"
  local usb_pack_dir="$2"
  mkdir -p "$usb_pack_dir"
  cp -R "$(usb_stage_pack_dir "$workspace_dir")/." "$usb_pack_dir/"
}

usb_sync_openclaw_runtime() {
  local runtime_dir="$1"
  mkdir -p "${runtime_dir}/openclaw"
  rsync -a --delete \
    "$HOME/.npm-global/lib/node_modules/openclaw/" \
    "${runtime_dir}/openclaw/"
}

usb_copy_feature_snapshot() {
  local project_root="$1"
  local snapshot_root="$2"
  local relative_path

  for relative_path in "${OPENCLAW_USB_FEATURE_SNAPSHOT_PATHS[@]}"; do
    mkdir -p "${snapshot_root}/$(dirname "$relative_path")"
    rsync -a "${project_root}/${relative_path}" "${snapshot_root}/$(dirname "$relative_path")/"
  done
}

usb_prune_feature_snapshot() {
  local snapshot_root="$1"
  find "$snapshot_root" -type f -name '.env*' ! -name '.env.example' -delete
  rm -rf \
    "$snapshot_root/longrun/workspaces/openclaw-usb-portable/execution/export" \
    "$snapshot_root/longrun/workspaces/openclaw-usb-portable/execution/delivery-pack/staged" \
    "$snapshot_root/longrun/workspaces/openclaw-usb-portable/execution/evidence" \
    "$snapshot_root/longrun/workspaces/openclaw-usb-portable/execution/logs"
}

usb_write_checksums() {
  local export_root="$1"
  (
    cd "$export_root"
    find . -type f ! -name 'CHECKSUMS.sha256' -print0 | sort -z | xargs -0 shasum -a 256 > CHECKSUMS.sha256
  )
}

usb_write_versions_file() {
  local export_root="$1"
  local platform_key="$2"
  local platform_value="$3"
  local node_version="$4"
  local openclaw_version="$5"

  cat > "${export_root}/VERSIONS.txt" <<VERSIONS
bundle_scope=feishu-only-local-usb
${platform_key}=${platform_value}
bundled_node_version=v${node_version}
system_node_version=$(node -v)
npm_version=$(npm -v)
openclaw_version=${openclaw_version}
openclaw_runtime_source=npm-global snapshot
usb_pack_dir=./usb-pack
feishu_source_dir=./feishu-source
VERSIONS
}
