<#
  Show current playlist health and how it has drifted over recent runs.
#>
[CmdletBinding()]
param([int]$Weeks = 12)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\common.ps1"

$playlist = $Script:IPTVPlaylist
if (Test-Path -LiteralPath $playlist) {
  $urls = @(Get-Content -LiteralPath $playlist | Where-Object { $_ -match '^https?://' })
  Write-Host "PLAYLIST" -ForegroundColor Cyan
  Write-Host "  path    : $playlist"
  Write-Host "  channels: $($urls.Count)"
  Write-Host "  size    : $([math]::Round((Get-Item $playlist).Length/1KB,1)) KB"
  Write-Host "  modified: $((Get-Item $playlist).LastWriteTime)"
} else {
  Write-Host "no playlist found" -ForegroundColor Red
}

$hist = "$Script:IPTVDb\history.json"
if (Test-Path -LiteralPath $hist) {
  Write-Host ""
  Write-Host "HISTORY" -ForegroundColor Cyan
  Write-Host ("  {0,-12} {1,-5} {2,7} {3,7} {4,7} {5,8}" -f 'date','geo','total','kept','added','dropped')
  try {
    $rows = @(Get-Content -LiteralPath $hist -Raw | ConvertFrom-Json)
    foreach ($r in ($rows | Select-Object -Last $Weeks)) {
      $d = ([datetime]$r.timestamp).ToString('MM-dd HH:mm')
      Write-Host ("  {0,-10} {1,-4} {2,7} {3,7} {4,7} {5,-14}" -f `
        $d, $r.geo_country, $r.total_channels, $r.kept, $r.added, $r.dropped)
    }
  } catch {
    Write-Host "  (history unreadable: $($_.Exception.Message))" -ForegroundColor Yellow
  }
}

$snap = "$Script:IPTVDb\snapshot-latest.json"
if (Test-Path -LiteralPath $snap) {
  Write-Host ""
  Write-Host "LAST RUN - stream status breakdown" -ForegroundColor Cyan
  try {
    $s = Get-Content -LiteralPath $snap -Raw | ConvertFrom-Json
    foreach ($p in $s.status_breakdown.PSObject.Properties) {
      Write-Host ("  {0,-22} {1}" -f $p.Name, $p.Value)
    }
  } catch { }
}

$log = Get-ChildItem -LiteralPath $Script:IPTVDlogs -Filter 'refresh_*.log' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($log) {
  Write-Host ""
  Write-Host "LOG: $($log.FullName)" -ForegroundColor Cyan
  Get-Content -LiteralPath $log.FullName -Tail 15
}
