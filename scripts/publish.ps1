<#
  Publish the verified playlist to GitHub so a TV can fetch it 24/7.

  Refresh runs on THIS machine (correct Vietnam egress), then commits and pushes.
  The TV pulls from raw.githubusercontent.com, so playback survives this PC
  being asleep or off. See README.md for why refresh cannot run in Actions.

  Run:  pwsh -File publish.ps1              # refresh (if stale) + push
        pwsh -File publish.ps1 -NoRefresh   # push current playlist as-is
        pwsh -File publish.ps1 -NoPush      # refresh and commit locally only
#>
[CmdletBinding()]
param(
  [switch]$NoRefresh,
  [switch]$NoPush,
  [int]$RefreshMinAgeMinutes = 120,
  [string]$Remote = "origin",
  [string]$Branch = "main"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"

$repoRoot = $Script:IPTVRoot
$playlist = $Script:IPTVPlaylist
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

Set-Location $repoRoot

# ---------------------------------------------------------------- git sanity
if (-not (Test-Path -LiteralPath "$repoRoot\.git")) {
  Write-Log "initialising git repository" 'WARN'
  git init -b $Branch | Out-Null
}

Write-Host "=== IPTV playlist publish ===" -ForegroundColor Cyan
Write-Host "repo : $repoRoot"
Write-Host "branch: $Branch"
Write-Host ""

# ------------------------------------------------------------------ refresh
$age = [double]::MaxValue
if (Test-Path -LiteralPath $playlist) {
  $age = ((Get-Date) - (Get-Item $playlist).LastWriteTime).TotalMinutes
}
if ($NoRefresh) {
  Write-Host "refresh: skipped (-NoRefresh)" -ForegroundColor Yellow
} elseif ($age -lt $RefreshMinAgeMinutes) {
  Write-Host ("refresh: skipped, playlist is only {0:N0} min old" -f $age) -ForegroundColor Yellow
} else {
  Write-Host "refresh: running full Vietnam-egress verification..." -ForegroundColor Cyan
  Write-Host "(this takes a while, ~1-2h for the full sweep)" -ForegroundColor DarkGray
  & "$PSScriptRoot\refresh.ps1"
}

if (-not (Test-Path -LiteralPath $playlist)) {
  Write-Log "no playlist to publish" 'ERROR'; exit 1
}

$count = @(Get-Content -LiteralPath $playlist | Where-Object { $_ -match '^https?://' }).Count
Write-Host ""
Write-Host "playlist: $count channels, $([math]::Round((Get-Item $playlist).Length/1KB,1)) KB" -ForegroundColor Green

# ------------------------------------------------------- versioned copy for Git
# The TV fetches a stable, predictable path. A dated copy is committed too so
# history shows what changed between refreshes.
$snaps = "$Script:IPTVRoot\playlists"
if (-not (Test-Path -LiteralPath $snaps)) { New-Item -ItemType Directory -Path $snaps -Force | Out-Null }
Copy-Item -LiteralPath $playlist -Destination "$snaps\latest.m3u" -Force
$dated = "playlists\{0}.m3u" -f (Get-Date -Format 'yyyy-MM-dd')
Copy-Item -LiteralPath $playlist -Destination $dated -Force

# Some Tizen players (IPTV Smarters in particular) reject or mishandle certain
# extensions and cache aggressively. Identical content under three names so the
# player has something that works, plus a .txt for hosts that reject .m3u paths.
Copy-Item -LiteralPath $playlist -Destination "$snaps\latest.m3u8" -Force
Copy-Item -LiteralPath $playlist -Destination "$repoRoot\playlist.txt" -Force

# keep the dated history bounded
Get-ChildItem -LiteralPath $snaps -Filter '*.m3u' -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne 'latest.m3u' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -Skip 30 |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

# ------------------------------------------------------------- status.json
$snap = "$Script:IPTVDb\snapshot-latest.json"
$meta = [ordered]@{
  generated      = $stamp
  channels       = $count
  refreshed_from = 'Vietnam (authoritative)'
  raw_url        = 'https://raw.githubusercontent.com/ganjarapunit/IPTV/main/playlists/latest.m3u'
  note           = 'Only publisher-owned free-to-air streams. No subscription or pirated feeds.'
}
if (Test-Path -LiteralPath $snap) {
  try {
    $s = Get-Content -LiteralPath $snap -Raw | ConvertFrom-Json
    $meta['last_verification'] = $s.timestamp
    $meta['tested'] = $s.tested
    $meta['dropped_last_run'] = $s.dropped
    $meta['added_last_run'] = $s.added
    $meta['status_breakdown'] = $s.status_breakdown
  } catch { }
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$repoRoot\status.json" -Encoding utf8

# ------------------------------------------------------------------ commit
git add -A 2>&1 | Out-Null
$changed = @(git status --porcelain)
if ($changed.Count -eq 0) {
  Write-Host ""
  Write-Host "git: no changes, nothing to commit" -ForegroundColor Yellow
} else {
  $msg = "playlist: $count channels, verified $stamp (VN)"
  git commit -m $msg 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Log "commit failed" 'ERROR'
    git log -1 --oneline
  } else {
    Write-Host "git: committed - $msg" -ForegroundColor Green
  }
}

# --------------------------------------------------------------------- push
if ($NoPush) {
  Write-Host ""
  Write-Host "push: skipped (-NoPush). To publish later: git push $Remote $Branch" -ForegroundColor Yellow
  exit 0
}

Write-Host ""
Write-Host "pushing to $Remote/$Branch ..." -ForegroundColor Cyan
git push $Remote $Branch 2>&1 | ForEach-Object { Write-Host "  $_" }

if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "published." -ForegroundColor Green
  Write-Host ""
  Write-Host "TV playlist URL:" -ForegroundColor Cyan
  Write-Host "  https://raw.githubusercontent.com/ganjarapunit/IPTV/main/playlists/latest.m3u" -ForegroundColor White
  Write-Host ""
  Write-Host "note: raw.githubusercontent.com caches for ~5 min, and some TV" -ForegroundColor DarkGray
  Write-Host "      players cache longer, so a refresh may not appear on the" -ForegroundColor DarkGray
  Write-Host "      TV immediately." -ForegroundColor DarkGray
} else {
  Write-Host ""
  Write-Host "push FAILED - local commit is safe, push again with:" -ForegroundColor Red
  Write-Host "  cd $repoRoot ; git push $Remote $Branch" -ForegroundColor Yellow
  exit 1
}
