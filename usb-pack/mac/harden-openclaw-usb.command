#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
pack_root="$(cd "$script_dir/.." && pwd)"
export OPENCLAW_PROFILE_NAME="${OPENCLAW_PROFILE_NAME:-usb-portable}"

bash "$pack_root/scripts/openclaw-usb/harden-local-feishu.sh" \
  --profile "$OPENCLAW_PROFILE_NAME" \
  --dm-policy pairing \
  --allow-from-json '[]' \
  --require-mention true

echo
echo "Hardening complete. Press Enter to close."
read -r _
