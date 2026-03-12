param(
  [string]$Profile = '',
  [string]$DmPolicy = '',
  [string]$AllowFromJson = '',
  [string]$RequireMention = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$RuntimeRoot = if ($env:USB_RUNTIME_ROOT) { $env:USB_RUNTIME_ROOT } else { Join-Path $ProjectRoot 'runtime' }
$BundledNodeCmd = Join-Path $RuntimeRoot 'node\node.exe'
$BundledOpenClawEntry = Join-Path $RuntimeRoot 'openclaw\openclaw.mjs'
$script:NodeCmd = $null
$script:OpenClawMode = 'none'
$script:OpenClawCmd = $null

if (-not $Profile) { $Profile = if ($env:OPENCLAW_PROFILE_NAME) { $env:OPENCLAW_PROFILE_NAME } else { 'usb-portable' } }
if (-not $DmPolicy) { $DmPolicy = if ($env:OPENCLAW_DM_POLICY) { $env:OPENCLAW_DM_POLICY } else { 'pairing' } }
if (-not $AllowFromJson) { $AllowFromJson = if ($env:OPENCLAW_ALLOW_FROM_JSON) { $env:OPENCLAW_ALLOW_FROM_JSON } else { '[]' } }
if (-not $RequireMention) { $RequireMention = if ($env:OPENCLAW_REQUIRE_MENTION) { $env:OPENCLAW_REQUIRE_MENTION } else { 'true' } }

function Fail([string]$Message) {
  throw $Message
}

function Resolve-Runtime {
  $script:NodeCmd = $null
  $script:OpenClawMode = 'none'
  $script:OpenClawCmd = $null

  if (Test-Path $BundledNodeCmd) {
    $script:NodeCmd = (Resolve-Path $BundledNodeCmd).Path
  }
  else {
    $nodeCandidate = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCandidate) {
      $script:NodeCmd = $nodeCandidate.Source
    }
  }

  if ($script:NodeCmd -and (Test-Path $BundledOpenClawEntry)) {
    $script:OpenClawMode = 'bundled'
  }
  else {
    $openClawCandidate = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
    if (-not $openClawCandidate) { $openClawCandidate = Get-Command openclaw -ErrorAction SilentlyContinue }
    if ($openClawCandidate) {
      $script:OpenClawMode = 'global'
      $script:OpenClawCmd = $openClawCandidate.Source
    }
  }
}

function Invoke-OcRaw([string[]]$Arguments) {
  switch ($script:OpenClawMode) {
    'bundled' {
      & $script:NodeCmd $BundledOpenClawEntry @Arguments
      break
    }
    'global' {
      & $script:OpenClawCmd @Arguments
      break
    }
    default {
      Fail 'OpenClaw runtime is unavailable.'
    }
  }

  $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($exitCode -ne 0) {
    Fail ('OpenClaw command failed ({0}): {1}' -f $exitCode, ($Arguments -join ' '))
  }
}

function Invoke-Oc([string[]]$Arguments) {
  $allArgs = @('--profile', $Profile) + $Arguments
  Invoke-OcRaw -Arguments $allArgs
}

function Validate-JsonPayload([string]$JsonPayload) {
  & $script:NodeCmd -e 'JSON.parse(process.argv[1]);' $JsonPayload *> $null
  if ($LASTEXITCODE -ne 0) {
    Fail 'Invalid JSON for allowFrom'
  }
}

Resolve-Runtime
if (-not $script:NodeCmd) { Fail 'Node runtime not found.' }
if ($script:OpenClawMode -eq 'none') { Fail 'OpenClaw runtime not found.' }
if ($DmPolicy -notin @('pairing', 'allowlist', 'open')) { Fail ('Unsupported dm policy: {0}' -f $DmPolicy) }
if ($RequireMention -notin @('true', 'false')) { Fail 'require-mention must be true or false' }
Validate-JsonPayload $AllowFromJson

Invoke-Oc @('config', 'set', 'channels.feishu.dmPolicy', ($DmPolicy | ConvertTo-Json -Compress), '--strict-json')
Invoke-Oc @('config', 'set', 'channels.feishu.allowFrom', $AllowFromJson, '--strict-json')
Invoke-Oc @('config', 'set', 'channels.feishu.requireMention', $RequireMention, '--strict-json')
Invoke-Oc @('daemon', 'restart')
Invoke-Oc @('channels', 'status', '--probe')

Write-Host ('[DONE] Hardened profile {0} to dmPolicy={1}.' -f $Profile, $DmPolicy)
