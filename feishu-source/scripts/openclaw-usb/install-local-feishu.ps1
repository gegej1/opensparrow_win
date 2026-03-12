param(
  [string]$Profile = '',
  [string]$Agent = '',
  [int]$Port = 0,
  [string]$Model = '',
  [string]$DmPolicy = '',
  [string]$AllowFromJson = '',
  [string]$RequireMention = '',
  [string]$BaseUrl = '',
  [string]$FeishuAppId = '',
  [string]$FeishuAppSecret = '',
  [string]$OpenAiApiKey = '',
  [string]$LogDir = '',
  [string]$EvidenceDir = '',
  [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$RuntimeRoot = if ($env:USB_RUNTIME_ROOT) { $env:USB_RUNTIME_ROOT } else { Join-Path $ProjectRoot 'runtime' }
$RepoExecutionRoot = Join-Path $ProjectRoot 'longrun\workspaces\openclaw-usb-portable\execution'
$DefaultExecutionRoot = if (Test-Path $RepoExecutionRoot) { $RepoExecutionRoot } else { Join-Path $ProjectRoot '.openclaw-usb-runtime' }

if (-not $Profile) { $Profile = if ($env:OPENCLAW_PROFILE_NAME) { $env:OPENCLAW_PROFILE_NAME } else { 'usb-portable' } }
if (-not $Agent) { $Agent = if ($env:OPENCLAW_AGENT_ID) { $env:OPENCLAW_AGENT_ID } else { 'main' } }
if ($Port -eq 0) {
  if ($env:OPENCLAW_GATEWAY_PORT) {
    $Port = [int]$env:OPENCLAW_GATEWAY_PORT
  }
  else {
    $Port = 18889
  }
}
if (-not $Model) { $Model = if ($env:OPENCLAW_MODEL) { $env:OPENCLAW_MODEL } else { 'openai/gpt-4o-mini' } }
if (-not $DmPolicy) { $DmPolicy = if ($env:OPENCLAW_DM_POLICY) { $env:OPENCLAW_DM_POLICY } else { 'open' } }
if (-not $AllowFromJson) { $AllowFromJson = if ($env:OPENCLAW_ALLOW_FROM_JSON) { $env:OPENCLAW_ALLOW_FROM_JSON } else { '["*"]' } }
if (-not $RequireMention) { $RequireMention = if ($env:OPENCLAW_REQUIRE_MENTION) { $env:OPENCLAW_REQUIRE_MENTION } else { 'false' } }
if (-not $BaseUrl) { $BaseUrl = if ($env:OPENAI_BASE_URL) { $env:OPENAI_BASE_URL } else { '' } }
if (-not $FeishuAppId) { $FeishuAppId = if ($env:FEISHU_APP_ID) { $env:FEISHU_APP_ID } else { '' } }
if (-not $FeishuAppSecret) { $FeishuAppSecret = if ($env:FEISHU_APP_SECRET) { $env:FEISHU_APP_SECRET } else { '' } }
if (-not $OpenAiApiKey) { $OpenAiApiKey = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { '' } }
if (-not $LogDir) { $LogDir = Join-Path $DefaultExecutionRoot 'logs' }
if (-not $EvidenceDir) { $EvidenceDir = Join-Path (Join-Path $DefaultExecutionRoot 'evidence') (('{0:yyyyMMdd-HHmmss}-install' -f (Get-Date))) }
$NonInteractiveMode = $NonInteractive.IsPresent -or ($env:NON_INTERACTIVE -eq '1')
$PortScanLimit = if ($env:OPENCLAW_PORT_SCAN_LIMIT) { [int]$env:OPENCLAW_PORT_SCAN_LIMIT } else { 50 }

$ProfileStateDir = Join-Path $HOME ('.openclaw-{0}' -f $Profile)
$ProfileWorkspaceDir = Join-Path $ProfileStateDir 'workspace'
$ProfileAgentDir = Join-Path $ProfileStateDir (Join-Path 'agents' (Join-Path $Agent 'agent'))
$AuthProfilesFile = Join-Path $ProfileAgentDir 'auth-profiles.json'
$InstallLogFile = Join-Path $LogDir ('install-{0}-{1}.log' -f $Profile, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$BundledNodeCmd = Join-Path $RuntimeRoot 'node\node.exe'
$BundledOpenClawEntry = Join-Path $RuntimeRoot 'openclaw\openclaw.mjs'
$script:NodeCmd = $null
$script:NpmCmd = $null
$script:OpenClawMode = 'none'
$script:OpenClawCmd = $null
$script:FeishuDomain = if ($env:FEISHU_DOMAIN) { $env:FEISHU_DOMAIN } else { 'feishu' }
$script:TranscriptStarted = $false

function Write-Log([string]$Level, [string]$Message) {
  Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Fail([string]$Message) {
  throw $Message
}

function Convert-ToJsonString([string]$Value) {
  return ($Value | ConvertTo-Json -Compress)
}

function Read-SecretValue([string]$Prompt) {
  $secure = Read-Host $Prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Get-RequiredValue([string]$CurrentValue, [string]$Label, [bool]$IsSecret) {
  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue
  }
  if ($NonInteractiveMode) {
    Fail "$Label is required. Provide it via env var or PowerShell parameter."
  }
  $value = if ($IsSecret) { Read-SecretValue $Label } else { Read-Host $Label }
  if ([string]::IsNullOrWhiteSpace($value)) {
    Fail "$Label cannot be empty."
  }
  return $value
}

function Resolve-Runtime {
  $script:NodeCmd = $null
  $script:NpmCmd = $null
  $script:OpenClawCmd = $null
  $script:OpenClawMode = 'none'

  if (Test-Path $BundledNodeCmd) {
    $script:NodeCmd = (Resolve-Path $BundledNodeCmd).Path
    $bundledNpm = Join-Path $RuntimeRoot 'node\npm.cmd'
    if (Test-Path $bundledNpm) {
      $script:NpmCmd = (Resolve-Path $bundledNpm).Path
    }
  }
  else {
    $nodeCandidate = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCandidate) {
      $script:NodeCmd = $nodeCandidate.Source
    }
    $npmCandidate = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCandidate) { $npmCandidate = Get-Command npm -ErrorAction SilentlyContinue }
    if ($npmCandidate) {
      $script:NpmCmd = $npmCandidate.Source
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

function Require-Node {
  if (-not $script:NodeCmd) {
    Fail 'Node runtime not found. Install Node.js or provide runtime\node\node.exe in the package.'
  }
}

function Invoke-NodeExpression([string]$Expression, [string[]]$Arguments) {
  $output = & $script:NodeCmd -e $Expression @Arguments 2>&1
  $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  if ($exitCode -ne 0) {
    $rendered = ($output | Out-String).Trim()
    if ($rendered) {
      Fail $rendered
    }
    Fail 'Node command failed.'
  }
  return ($output | Out-String).Trim()
}

function Invoke-OcRaw([string[]]$Arguments, [switch]$IgnoreExitCode) {
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
  if ((-not $IgnoreExitCode) -and $exitCode -ne 0) {
    Fail ('OpenClaw command failed ({0}): {1}' -f $exitCode, ($Arguments -join ' '))
  }
}

function Invoke-Oc([string[]]$Arguments, [switch]$IgnoreExitCode) {
  $allArgs = @('--profile', $Profile) + $Arguments
  Invoke-OcRaw -Arguments $allArgs -IgnoreExitCode:$IgnoreExitCode
}

function Validate-JsonPayload([string]$JsonPayload) {
  try {
    Invoke-NodeExpression 'JSON.parse(process.argv[1]);' @($JsonPayload) | Out-Null
  }
  catch {
    Fail ('Invalid JSON payload: {0}' -f $JsonPayload)
  }
}

function Validate-BoolFlag([string]$Value) {
  if ($Value -notin @('true', 'false')) {
    Fail ('Boolean flag must be true or false, got: {0}' -f $Value)
  }
}

function Test-PortBusy([int]$PortNumber) {
  $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
  return ($listeners | Where-Object { $_.Port -eq $PortNumber } | Select-Object -First 1) -ne $null
}

function Find-FreePort([int]$StartPort, [int]$MaxAttempts) {
  $candidatePort = $StartPort
  for ($attempt = 0; $attempt -lt $MaxAttempts; $attempt += 1) {
    if (-not (Test-PortBusy $candidatePort)) {
      return $candidatePort
    }
    $candidatePort += 1
  }
  return $null
}

function Resolve-GatewayPort([int]$RequestedPort, [int]$MaxAttempts) {
  if (-not (Test-PortBusy $RequestedPort)) {
    return $RequestedPort
  }
  $fallbackPort = Find-FreePort -StartPort ($RequestedPort + 1) -MaxAttempts $MaxAttempts
  if ($null -eq $fallbackPort) {
    Fail ('Port {0} is busy and no free fallback port was found within {1} attempts.' -f $RequestedPort, $MaxAttempts)
  }
  Write-Log 'WARN' ('Port {0} is already listening; automatically switching to {1}.' -f $RequestedPort, $fallbackPort)
  return $fallbackPort
}

function Capture-OcCommand([string]$OutputFile, [string[]]$Arguments) {
  $outputDir = Split-Path -Parent $OutputFile
  if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }

  try {
    $output = Invoke-Oc -Arguments $Arguments -IgnoreExitCode 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  }
  catch {
    $output = @($_.Exception.Message)
    $exitCode = 1
  }

  @($output) | Out-File -FilePath $OutputFile -Encoding utf8

  if ($exitCode -ne 0) {
    @($output) | ForEach-Object { Write-Host $_ }
    return $false
  }
  return $true
}

function Ensure-OpenClawAvailable {
  Resolve-Runtime
  Require-Node

  switch ($script:OpenClawMode) {
    'bundled' {
      Write-Log 'INFO' ('Using bundled OpenClaw runtime: {0}' -f $BundledOpenClawEntry)
    }
    'global' {
      Write-Log 'INFO' ('Using global openclaw: {0}' -f $script:OpenClawCmd)
    }
    'none' {
      if (-not $script:NpmCmd) {
        Fail 'npm not found. Install npm or provide bundled OpenClaw runtime under runtime\openclaw\.'
      }
      Write-Log 'INFO' 'openclaw not found, installing with npm -g'
      & $script:NpmCmd install -g openclaw
      if ($LASTEXITCODE -ne 0) {
        Fail 'npm install -g openclaw failed. Check npm permissions or use the bundled runtime.'
      }
      Resolve-Runtime
      if ($script:OpenClawMode -eq 'none') {
        Fail 'OpenClaw is still unavailable after npm install.'
      }
    }
  }
}

function Upsert-AuthProfile {
  if (-not (Test-Path $ProfileAgentDir)) {
    New-Item -ItemType Directory -Force -Path $ProfileAgentDir | Out-Null
  }

  $nodeScript = @"
const fs = require('fs');
const path = require('path');
const [authFile, apiKey] = process.argv.slice(1);
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
fs.mkdirSync(path.dirname(authFile), { recursive: true });
fs.writeFileSync(authFile, JSON.stringify(store, null, 2) + '\n');
"@

  & $script:NodeCmd -e $nodeScript $AuthProfilesFile $OpenAiApiKey
  if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to write auth-profiles.json'
  }
}

function Configure-OpenAiProvider {
  if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    return
  }

  $providerModelId = $Model
  if ($providerModelId.StartsWith('openai/')) {
    $providerModelId = $providerModelId.Substring(7)
  }

  $providerJson = @{
    baseUrl = $BaseUrl
    models  = @(@{
        id   = $providerModelId
        name = $providerModelId
        api  = 'openai-completions'
      })
  } | ConvertTo-Json -Compress -Depth 5

  Invoke-Oc @('config', 'set', 'models.providers.openai', $providerJson, '--strict-json')
  if ($LASTEXITCODE -ne 0) {
    Fail 'Failed to configure OpenAI provider.'
  }
}

function Wait-ForGateway([string]$HealthFile) {
  for ($attempt = 1; $attempt -le 20; $attempt += 1) {
    if (Capture-OcCommand -OutputFile $HealthFile -Arguments @('health', '--json', '--timeout', '5000')) {
      return $true
    }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Get-ManualCommandPrefix {
  if ($script:OpenClawMode -eq 'bundled') {
    return ('"{0}" "{1}" --profile {2}' -f $script:NodeCmd, $BundledOpenClawEntry, $Profile)
  }
  return ('openclaw --profile {0}' -f $Profile)
}

try {
  $FeishuAppId = Get-RequiredValue $FeishuAppId 'FEISHU_APP_ID' $false
  $FeishuAppSecret = Get-RequiredValue $FeishuAppSecret 'FEISHU_APP_SECRET' $true
  $OpenAiApiKey = Get-RequiredValue $OpenAiApiKey 'OPENAI_API_KEY' $true

  Resolve-Runtime
  Require-Node
  Validate-JsonPayload $AllowFromJson
  Validate-BoolFlag $RequireMention
  if ($Port -le 0) {
    Fail 'Gateway port must be numeric and positive.'
  }
  if ($PortScanLimit -le 0) {
    Fail 'Port scan limit must be positive.'
  }
  $RequestedPort = $Port

  foreach ($dir in @($LogDir, $EvidenceDir, $ProfileWorkspaceDir, $ProfileAgentDir)) {
    if (-not (Test-Path $dir)) {
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
  }

  Start-Transcript -Path $InstallLogFile -Append | Out-Null
  $script:TranscriptStarted = $true

  $Port = Resolve-GatewayPort -RequestedPort $Port -MaxAttempts $PortScanLimit

  Write-Log 'INFO' ('Installing into isolated profile: {0}' -f $Profile)
  Write-Log 'INFO' ('Isolated state dir: {0}' -f $ProfileStateDir)
  Write-Log 'INFO' ('Isolated workspace dir: {0}' -f $ProfileWorkspaceDir)
  Write-Log 'INFO' ('Requested gateway port: {0}' -f $RequestedPort)
  Write-Log 'INFO' ('Dedicated gateway port: {0}' -f $Port)
  Write-Log 'INFO' ('Evidence dir: {0}' -f $EvidenceDir)
  Write-Log 'INFO' ('Log file: {0}' -f $InstallLogFile)
  Write-Log 'INFO' ('Runtime root candidate: {0}' -f $RuntimeRoot)
  Write-Log 'INFO' ('Node runtime: {0}' -f $script:NodeCmd)

  Ensure-OpenClawAvailable

  Write-Log 'INFO' 'Writing isolated OpenClaw config'
  Invoke-Oc @('config', 'set', 'gateway.mode', (Convert-ToJsonString 'local'), '--strict-json')
  Invoke-Oc @('config', 'set', 'gateway.bind', (Convert-ToJsonString 'loopback'), '--strict-json')
  Invoke-Oc @('config', 'set', 'gateway.port', $Port.ToString(), '--strict-json')
  Invoke-Oc @('config', 'set', 'agents.defaults.workspace', (Convert-ToJsonString $ProfileWorkspaceDir), '--strict-json')
  Invoke-Oc @('config', 'set', 'plugins.entries.feishu.enabled', 'true', '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.enabled', 'true', '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.connectionMode', (Convert-ToJsonString 'websocket'), '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.domain', (Convert-ToJsonString $script:FeishuDomain), '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.appId', (Convert-ToJsonString $FeishuAppId), '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.appSecret', (Convert-ToJsonString $FeishuAppSecret), '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.dmPolicy', (Convert-ToJsonString $DmPolicy), '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.allowFrom', $AllowFromJson, '--strict-json')
  Invoke-Oc @('config', 'set', 'channels.feishu.requireMention', $RequireMention, '--strict-json')

  Write-Log 'INFO' 'Writing isolated auth-profiles.json'
  Upsert-AuthProfile

  Write-Log 'INFO' 'Configuring model provider'
  Configure-OpenAiProvider
  Invoke-Oc @('models', 'set', $Model)

  Write-Log 'INFO' 'Validating isolated config'
  if (-not (Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'config-validate.json') -Arguments @('config', 'validate', '--json'))) {
    Fail 'Config validation failed.'
  }

  Write-Log 'INFO' 'Installing/reinstalling isolated daemon service'
  Invoke-Oc @('daemon', 'install', '--force', '--port', $Port.ToString())
  Write-Log 'INFO' 'Restarting isolated daemon service'
  Invoke-Oc @('daemon', 'restart')

  Write-Log 'INFO' 'Waiting for gateway health'
  $healthFile = Join-Path $EvidenceDir 'health.json'
  if (-not (Wait-ForGateway $healthFile)) {
    Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'daemon-status.txt') -Arguments @('daemon', 'status') | Out-Null
    Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'gateway-logs.txt') -Arguments @('logs', '--plain', '--limit', '200', '--timeout', '5000') | Out-Null
    Fail ('Gateway did not become healthy. See {0} and {1}' -f (Join-Path $EvidenceDir 'daemon-status.txt'), (Join-Path $EvidenceDir 'gateway-logs.txt'))
  }

  Write-Log 'INFO' 'Capturing daemon status'
  Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'daemon-status.txt') -Arguments @('daemon', 'status') | Out-Null
  Write-Log 'INFO' 'Capturing channel probe'
  Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'channels-probe.json') -Arguments @('channels', 'status', '--probe', '--json', '--timeout', '10000') | Out-Null
  Write-Log 'INFO' 'Running agent smoke test'
  Capture-OcCommand -OutputFile (Join-Path $EvidenceDir 'agent-smoke.json') -Arguments @('agent', '--agent', $Agent, '--message', '请只回复OK', '--json') | Out-Null

  @(
    ('profile={0}' -f $Profile),
    ('state_dir={0}' -f $ProfileStateDir),
    ('workspace_dir={0}' -f $ProfileWorkspaceDir),
    ('config_file={0}' -f (Join-Path $ProfileStateDir 'openclaw.json')),
    ('agent_auth_file={0}' -f $AuthProfilesFile),
    ('requested_gateway_port={0}' -f $RequestedPort),
    ('gateway_port={0}' -f $Port),
    ('model={0}' -f $Model),
    ('dm_policy={0}' -f $DmPolicy),
    ('allow_from={0}' -f $AllowFromJson),
    ('require_mention={0}' -f $RequireMention),
    ('log_file={0}' -f $InstallLogFile),
    ('runtime_root={0}' -f $RuntimeRoot),
    ('node_cmd={0}' -f $script:NodeCmd),
    ('openclaw_mode={0}' -f $script:OpenClawMode)
  ) | Set-Content -Path (Join-Path $EvidenceDir 'session-metadata.txt') -Encoding utf8

  $manualPrefix = Get-ManualCommandPrefix
  Write-Host '[DONE] OpenClaw local portable baseline is configured.'
  Write-Host ''
  Write-Host 'Isolation summary:'
  Write-Host ('- profile: {0}' -f $Profile)
  Write-Host ('- isolated state: {0}' -f $ProfileStateDir)
  Write-Host ('- isolated workspace: {0}' -f $ProfileWorkspaceDir)
  Write-Host ('- requested port: {0}' -f $RequestedPort)
  Write-Host ('- dedicated port: {0}' -f $Port)
  Write-Host ('- evidence: {0}' -f $EvidenceDir)
  Write-Host ('- openclaw mode: {0}' -f $script:OpenClawMode)
  Write-Host ''
  Write-Host 'Manual checks:'
  Write-Host ('1) {0} channels status --probe' -f $manualPrefix)
  Write-Host ('2) {0} agent --agent {1} --message "请只回复OK" --json' -f $manualPrefix, $Agent)
  Write-Host '3) 在飞书里给机器人发送 ok，确认能收到回复'
  Write-Host '4) 完成联调后运行 harden 脚本收口权限'
}
catch {
  Write-Log 'ERROR' $_.Exception.Message
  exit 1
}
finally {
  if ($script:TranscriptStarted) {
    Stop-Transcript | Out-Null
  }
}
