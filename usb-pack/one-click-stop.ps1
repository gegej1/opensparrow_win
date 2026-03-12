param(
  [int]$UiPort = 19000,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Finish-AndExit([int]$Code, [string]$Message) {
  if ($Message) {
    if ($Code -eq 0) {
      Write-Host ("[done] {0}" -f $Message)
    } else {
      Write-Host ("[error] {0}" -f $Message)
    }
  }
  if (-not $NoPause.IsPresent) {
    Read-Host 'Press Enter to close'
  }
  exit $Code
}

function Try-StopViaApi([int]$Port) {
  try {
    $body = @{ action = 'stop' } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri ("http://127.0.0.1:{0}/api/daemon" -f $Port) -ContentType 'application/json' -Body $body -TimeoutSec 12 | Out-Null
    return $true
  }
  catch {
    return $false
  }
}

function Stop-NodeByPattern([string]$Pattern) {
  $targets = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
    $_.CommandLine -like $Pattern
  }

  foreach ($proc in $targets) {
    try {
      Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
    }
    catch {}
  }

  return @($targets).Count
}

try {
  $stoppedByApi = Try-StopViaApi -Port $UiPort
  $gatewayCount = Stop-NodeByPattern -Pattern '*gateway run*--port 18889*'
  $serverCount = Stop-NodeByPattern -Pattern '*ui\server.mjs*'

  $detail = "apiStop=$stoppedByApi, gatewayProc=$gatewayCount, uiProc=$serverCount"
  Finish-AndExit 0 ("Local services stopped. {0}" -f $detail)
}
catch {
  Finish-AndExit 1 $_.Exception.Message
}
