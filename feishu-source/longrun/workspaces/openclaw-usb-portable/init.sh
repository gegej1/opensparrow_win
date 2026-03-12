#!/usr/bin/env bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="${PROJECT_ROOT:-$(cd "${workspace_dir}/../../.." && pwd)}"

echo "[init] Workspace dir: $workspace_dir"
echo "[init] Project root: $project_root"
cd "$project_root"

echo "[init] Checking required commands..."
required_cmds=(bash curl node npm)
for command_name in "${required_cmds[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "[init] OK: $command_name"
  else
    echo "[init] MISSING: $command_name"
  fi
done

echo "[init] Installer script:"
echo "       scripts/openclaw-usb/install-local-feishu.sh"
echo "[init] Example run:"
echo "       FEISHU_APP_ID=... FEISHU_APP_SECRET=... OPENAI_API_KEY=... bash scripts/openclaw-usb/install-local-feishu.sh"

echo "[init] Done."
