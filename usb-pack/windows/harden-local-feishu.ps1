param(
  [string]$Profile = 'usb-portable'
)

$ErrorActionPreference = 'Stop'
$PackRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Script = Join-Path $PackRoot 'scripts\openclaw-usb\harden-local-feishu.ps1'

& $Script -Profile $Profile -DmPolicy pairing -AllowFromJson '[]' -RequireMention true
Read-Host 'Hardening complete. Press Enter to close'
