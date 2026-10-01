<#
  Segment-verify a URL list and record results.

  Usage: pwsh -File verify-urls.ps1 -Urls cache\sweep-urls.txt -Out cache\sweep-status.csv
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Urls,
  [string]$Out = "C:\Users\Punit\iptv\cache\sweep-status.csv",
  [int]$ThrottleLimit = 24
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$list = @(Get-Content -LiteralPath $Urls | Where-Object { $_.Trim() })
Write-Host "verifying $($list.Count) URLs from $((Invoke-RestMethod 'https://ipinfo.io/json' -TimeoutSec 20).country)..."

$sw = [Diagnostics.Stopwatch]::StartNew()
$res = $list | ForEach-Object -Parallel {
  $u = $_
  . "$using:PSScriptRoot\Test-StreamStatus.ps1"
  $r = Get-StreamStatus $u
  [pscustomobject]@{ Url = $u; Status = $r.Status }
} -ThrottleLimit $ThrottleLimit
$sw.Stop()

$res | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding utf8

Write-Host ""
$res | Group-Object Status | Sort-Object Count -Descending | ForEach-Object {
  Write-Host ("  {0,-22} {1}" -f $_.Name, $_.Count)
}
$ok = @($res | Where-Object { $_.Status -eq 'ok' }).Count
Write-Host ""
Write-Host "PLAYABLE: $ok / $($res.Count)   ($([math]::Round($sw.Elapsed.TotalMinutes,1)) min)"
