#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/export-common.sh"

workspace_dir="$(usb_exec_workspace_dir)"
project_root="$(usb_project_root "$workspace_dir")"
export_root="${workspace_dir}/export/mac-feishu-usb-copy-$(date +%Y%m%d-%H%M%S)"
archive_path="${export_root}.tar.gz"
usb_pack_dir="${export_root}/usb-pack"
feishu_source_dir="${export_root}/feishu-source"
runtime_dir="${usb_pack_dir}/runtime"
node_version="$(node -v | sed 's/^v//')"
openclaw_version="$(openclaw --version)"
arch="$(uname -m)"
case "$arch" in
  arm64) node_arch='arm64' ;;
  x86_64) node_arch='x64' ;;
  *) echo "[ERROR] Unsupported macOS arch: $arch" >&2; exit 1 ;;
esac
node_url="https://nodejs.org/dist/v${node_version}/node-v${node_version}-darwin-${node_arch}.tar.gz"
node_tmp_tar="/tmp/node-v${node_version}-darwin-${node_arch}.tar.gz"

mkdir -p "${workspace_dir}/export"
usb_build_stage_pack "$workspace_dir"
usb_prepare_export_root "$export_root" "$archive_path"
mkdir -p "$usb_pack_dir" "$feishu_source_dir" "$runtime_dir/node"

usb_copy_stage_pack "$workspace_dir" "$usb_pack_dir"
usb_sync_openclaw_runtime "$runtime_dir"

curl -L --fail --retry 3 --retry-delay 2 "$node_url" -o "$node_tmp_tar"
tar -xzf "$node_tmp_tar" -C "${runtime_dir}/node" --strip-components=1

usb_copy_feature_snapshot "$project_root" "$feishu_source_dir"
usb_prune_feature_snapshot "$feishu_source_dir"

cat > "${export_root}/README-FIRST.txt" <<README
OpenClaw USB Portable - Mac handoff copy (Feishu-only)
======================================================

这是明天拷到 U 盘用的 Mac 副本，内容包含：

1. usb-pack/
   - 可直接用于 U 盘交付的安装包
   - 已内置 Node 运行时与 OpenClaw 运行时
   - 只包含 OpenClaw + Feishu 本地/U盘部署内容
2. feishu-source/
   - 与本次 002 USB/Feishu 本地部署直接相关的源码与文档快照
   - 不包含 Notion、VPS、群聊归档、知识检索等扩展主题

本副本针对当前机器架构构建：
- macOS arch: ${arch}
- bundled Node: v${node_version} (${node_arch})
- bundled OpenClaw: ${openclaw_version}

推荐使用方式：
- 直接把 usb-pack/ 整个目录拷到 U 盘
- 在目标 Mac 上双击 usb-pack/mac/run-openclaw-usb.command

注意：
- 该副本已经尽量把运行依赖带上，但飞书凭证 / API key 仍需目标机输入
- 该副本不绕过 Gatekeeper，也不绕过 U 盘自动执行限制
- 该副本明确排除 Notion / VPS 相关内容，后续 Windows 导出也应保持同一边界
- 若目标 Mac 架构与 ${arch} 不一致，包内 Node 可能不适用
README

usb_write_versions_file "$export_root" "mac_arch" "$arch" "$node_version" "$openclaw_version"
usb_write_checksums "$export_root"
tar -czf "$archive_path" -C "$(dirname "$export_root")" "$(basename "$export_root")"

echo "[DONE] Mac handoff copy created: $export_root"
echo "[DONE] Archive created: $archive_path"
echo "[INFO] usb-pack path: $usb_pack_dir"
echo "[INFO] feishu source path: $feishu_source_dir"
