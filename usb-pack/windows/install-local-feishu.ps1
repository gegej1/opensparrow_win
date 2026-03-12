param(
  [string]$Profile = 'usb-portable',
  [int]$Port = 18889,
  [string]$DmPolicy = 'open'
)

$ErrorActionPreference = 'Stop'
$PackRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Installer = Join-Path $PackRoot 'scripts\openclaw-usb\install-local-feishu.ps1'

& $Installer -Profile $Profile -Port $Port -DmPolicy $DmPolicy
Read-Host 'Done. Press Enter to close'
