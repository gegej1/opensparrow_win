#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/export-common.sh"

workspace_dir="$(usb_exec_workspace_dir)"
project_root="$(usb_project_root "$workspace_dir")"
export_root="${workspace_dir}/export/windows-feishu-usb-copy-$(date +%Y%m%d-%H%M%S)"
archive_path="${export_root}.zip"
usb_pack_dir="${export_root}/usb-pack"
feishu_source_dir="${export_root}/feishu-source"
runtime_dir="${usb_pack_dir}/runtime"
node_version="$(node -v | sed 's/^v//')"
openclaw_version="$(openclaw --version)"
windows_arch="${WINDOWS_NODE_ARCH:-x64}"
case "$windows_arch" in
  x64|arm64) ;;
  *) echo "[ERROR] Unsupported Windows arch: $windows_arch" >&2; exit 1 ;;
esac
node_url="https://nodejs.org/dist/v${node_version}/node-v${node_version}-win-${windows_arch}.zip"
node_tmp_zip="/tmp/node-v${node_version}-win-${windows_arch}.zip"

mkdir -p "${workspace_dir}/export"
usb_build_stage_pack "$workspace_dir"
usb_prepare_export_root "$export_root" "$archive_path"
mkdir -p "$usb_pack_dir" "$feishu_source_dir" "$runtime_dir/node"

usb_copy_stage_pack "$workspace_dir" "$usb_pack_dir"
usb_sync_openclaw_runtime "$runtime_dir"

curl -L --fail --retry 3 --retry-delay 2 "$node_url" -o "$node_tmp_zip"
ditto -x -k "$node_tmp_zip" "${runtime_dir}"
node_extract_dir="$(find "${runtime_dir}" -maxdepth 1 -mindepth 1 -type d -name 'node-v*-win-*' | head -n 1)"
[[ -n "$node_extract_dir" ]] || { echo "[ERROR] Failed to extract Windows Node runtime" >&2; exit 1; }
rsync -a --delete "${node_extract_dir}/" "${runtime_dir}/node/"
rm -rf "$node_extract_dir"

usb_copy_feature_snapshot "$project_root" "$feishu_source_dir"
usb_prune_feature_snapshot "$feishu_source_dir"

cat > "${export_root}/README-FIRST.txt" <<README
OpenClaw USB Portable - Windows handoff copy (Feishu-only)
=========================================================

这是单独给 Windows 目标机/U 盘交付准备的副本，内容包含：

1. usb-pack/
   - 可直接用于 U 盘交付的安装包
   - 已内置 Windows Node 运行时与 OpenClaw 运行时
   - 只包含 OpenClaw + Feishu 本地/U盘部署内容
2. feishu-source/
   - 与本次 002 USB/Feishu 本地部署直接相关的源码与文档快照
   - 不包含 Notion、VPS、群聊归档、知识检索等扩展主题

本副本针对以下 Windows 架构构建：
- windows arch: ${windows_arch}
- bundled Node: v${node_version}
- bundled OpenClaw: ${openclaw_version}

推荐使用方式：
- 直接把 usb-pack/ 整个目录拷到 U 盘
- 在目标 Windows 上双击 usb-pack/windows/run-openclaw-usb.cmd

注意：
- 该副本已经尽量把运行依赖带上，但飞书凭证 / API key 仍需目标机输入
- 该副本不绕过 AutoRun / AutoPlay，也不绕过 U 盘自动执行限制
- 该副本明确排除 Notion / VPS 相关内容
- 若目标 Windows 架构与 ${windows_arch} 不一致，需要重新导出对应架构包
README

usb_write_versions_file "$export_root" "windows_arch" "$windows_arch" "$node_version" "$openclaw_version"
usb_write_checksums "$export_root"
ditto -c -k --sequesterRsrc --keepParent "$export_root" "$archive_path"

echo "[DONE] Windows handoff copy created: $export_root"
echo "[DONE] Archive created: $archive_path"
echo "[INFO] usb-pack path: $usb_pack_dir"
echo "[INFO] feishu source path: $feishu_source_dir"
