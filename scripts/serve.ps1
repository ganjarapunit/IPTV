<#
  Swap the running server over to the Range-capable one in iptv_server.py.
  Idempotent: kills any existing listener on the port, then starts fresh.
#>
[CmdletBinding()]
param(
  [int]$Port = 8000,
  [switch]$NoRestart
)

$ErrorActionPreference = 'Continue'

. "$PSScriptRoot\common.ps1"

$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = 'C:\Program Files\Python314\python.exe' }
if (-not (Test-Path -LiteralPath $py)) {
  Write-Host "python not found at $py" -ForegroundColor Red
  exit 1
}

if (-not $NoRestart) {
  $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  foreach ($l in $listeners) {
    Write-Host "stopping pid $($l.OwningProcess) on port $Port"
    Stop-Process -Id $l.OwningProcess -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
}

$script = "$Script:IPTVDir\iptv_server.py"
Write-Host "starting: $py $script $Script:IPTVRoot $Port"
Start-Process -FilePath $py `
  -ArgumentList @($script, $Script:IPTVRoot, "$Port") `
  -WindowStyle Hidden

Start-Sleep -Seconds 3
try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/india-free-vietnam.m3u" -TimeoutSec 10
  Write-Host "OK  local fetch HTTP $($r.StatusCode), $($r.RawContentLength) bytes" -ForegroundColor Green
} catch {
  Write-Host "FAILED to serve playlist: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

try {
  $ip = (Get-NetIPAddress -AddressFamily IPv4 |
         Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
         Select-Object -First 1).IPAddress
  $r = Invoke-WebRequest -Uri "http://$ip`:$Port/india-free-vietnam.m3u" -TimeoutSec 10
  Write-Host "OK  LAN fetch   HTTP $($r.StatusCode) from $ip" -ForegroundColor Green
  Write-Host ""
  Write-Host "Playlist URL: http://${ip}:$Port/india-free-vietnam.m3u" -ForegroundColor Cyan
} catch {
  Write-Host "LAN fetch failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
