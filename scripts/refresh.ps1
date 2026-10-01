<#
  Refresh the IPTV playlist:
    1. fetch the current upstream channel/stream index
    2. re-verify every channel already in the playlist (segment-level)
    3. discover NEW publisher-owned channels and test them
    4. rewrite the playlist from what actually plays
    5. record a snapshot so drift is visible week to week

  Run:  pwsh -File refresh.ps1
        pwsh -File refresh.ps1 -DiscoverNew:$false   (verify only)
        pwsh -File refresh.ps1 -MaxTest 600         (cap the test count)
#>
[CmdletBinding()]
param(
  [switch]$SkipDiscover,
  [int]$ThrottleLimit = 16,
  [int]$MaxTest = 0,
  [string]$OutFile = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\Test-StreamStatus.ps1"

if (-not $OutFile) { $OutFile = $Script:IPTVPlaylist }
$started = Get-Date

Write-Log "=== refresh started ==="

# ---------------------------------------------------------------- 1. index
Write-Log "fetching upstream index..."
$chUrl = 'https://iptv-org.github.io/api/channels.json'
$stUrl = 'https://iptv-org.github.io/api/streams.json'
Invoke-WebRequest -Uri $chUrl -OutFile "$Script:IPTVDbCache\channels.json" -TimeoutSec 180
Invoke-WebRequest -Uri $stUrl -OutFile "$Script:IPTVDbCache\streams.json" -TimeoutSec 300

$channels = Get-Content "$Script:IPTVDbCache\channels.json" -Raw | ConvertFrom-Json
$streams  = Get-Content "$Script:IPTVDbCache\streams.json" -Raw | ConvertFrom-Json
Write-Log "index: $($channels.Count) channels, $($streams.Count) streams"

$byId = @{}
foreach ($c in $channels) { if ($c.id) { $byId[$c.id] = $c } }

# ------------------------------------------------- 2. existing playlist rows
$existing = @()
if (Test-Path -LiteralPath $OutFile) {
  $cur = $null
  foreach ($line in (Get-Content -LiteralPath $OutFile)) {
    if ($line.StartsWith('#EXTINF')) {
      $cur = $line
    } elseif ($line -match '^https?://') {
      $g = ''; if ($cur -match 'group-title="([^"]*)"') { $g = $matches[1] }
      $id = ''; if ($cur -match 'tvg-id="([^"]*)"') { $id = $matches[1] }
      $existing += [pscustomobject]@{
        Name = ($cur -split ',')[-1]; Group = $g; Id = $id; Meta = $cur; Url = $line
      }
    }
  }
}
Write-Log "existing playlist: $($existing.Count) channels"

# ------------------------------------------------------ 3. discover new ones
$newCands = @()
if (-not $SkipDiscover) {
  Write-Log "discovering new publisher-owned channels..."

  $entCats = @('movies','series','entertainment','classic','comedy','animation',
               'family','documentary','kids','news','sports','music','religious',
               'general','lifestyle','education','business','culture')
  $seenUrls = @{}
  foreach ($e in $existing) { $seenUrls[$e.Url] = $true }

  foreach ($st in $streams) {
    if (-not $st.channel -or -not $st.url) { continue }
    if ($seenUrls.ContainsKey($st.url)) { continue }
    if (-not $byId.ContainsKey($st.channel)) { continue }
    $c = $byId[$st.channel]
    if ($c.is_nsfw -or $c.closed) { continue }

    $hit = $false
    foreach ($x in $c.categories) { if ($entCats -contains $x) { $hit = $true; break } }
    if (-not $hit) { continue }

    $h = ''
    try { $h = ([uri]$st.url).Host } catch { continue }
    if (-not (Test-AllowedHost $h)) { continue }

    $q = if ($st.quality) { $st.quality } else { 'unknown' }
    $newCands += [pscustomobject]@{
      Id = $c.id; Name = $c.name; Cats = $c.categories; Q = $q; Host = $h; Url = $st.url
    }
  }
  Write-Log "new candidates on publisher CDNs: $($newCands.Count)"
} else {
  Write-Log "discovery skipped (verify-only run)"
}

# ------------------------------------------------------------- 4. deep test
$toTest = @($existing.Url)
foreach ($n in $newCands) { $toTest += $n.Url }
$toTest = @($toTest | Sort-Object -Unique)
if ($MaxTest -gt 0 -and $toTest.Count -gt $MaxTest) {
  Write-Log "WARNING: capping test at $MaxTest of $($toTest.Count)"
  $toTest = @($toTest | Get-Random -Count $MaxTest)
}
Write-Log "segment-testing $($toTest.Count) streams from $((Invoke-RestMethod 'https://ipinfo.io/json' -TimeoutSec 20).country)..."

$sw = [Diagnostics.Stopwatch]::StartNew()
$results = $toTest | ForEach-Object -Parallel {
  $u = $_
  . "$using:PSScriptRoot\Test-StreamStatus.ps1"
  $r = Get-StreamStatus $u
  [pscustomobject]@{ Url = $u; Status = $r.Status; Note = $r.Note }
} -ThrottleLimit $ThrottleLimit
$sw.Stop()
Write-Log "test finished in $([math]::Round($sw.Elapsed.TotalMinutes,1)) min"

$statusMap = @{}
foreach ($r in $results) { $statusMap[$r.Url] = $r.Status }
$results | Group-Object Status | Sort-Object Count -Descending |
  ForEach-Object { Write-Log ("  {0,-20} {1}" -f $_.Name, $_.Count) }

# ------------------------------------------------------------- 5. rebuild
$kept = @()
foreach ($e in $existing) {
  if ($statusMap.ContainsKey($e.Url) -and $statusMap[$e.Url] -eq 'ok') { $kept += $e }
}
$dropped = $existing.Count - $kept.Count
Write-Log "kept $((@($kept)).Count) existing, dropped $dropped"

$added = @()
if ($newCands.Count -gt 0) {
  $groupMap = @{
    'movies' = 'English Movies'; 'classic' = 'English Movies'
    'series' = 'English TV'; 'comedy' = 'English Comedy'
    'animation' = 'English Animation'; 'kids' = 'English Animation'
    'family' = 'English Family'; 'documentary' = 'English Documentary'
    'news' = 'News'; 'sports' = 'Sports'; 'music' = 'Music'
    'religious' = 'Religious'; 'general' = 'General'
    'lifestyle' = 'Lifestyle'; 'education' = 'Education'
    'business' = 'Business'; 'culture' = 'Culture'
  }
  $seenId = @{}
  foreach ($k in $kept) { if ($k.Id) { $seenId[$k.Id] = $true } }

  $candsOk = @($newCands | Where-Object {
    $statusMap.ContainsKey($_.Url) -and $statusMap[$_.Url] -eq 'ok'
  })
  $candsOk = @($candsOk | Sort-Object -Property @{ Expression = { Get-QualityRank $_.Q }; Descending = $true })

  foreach ($c in $candsOk) {
    if ($seenId.ContainsKey($c.Id)) { continue }
    $seenId[$c.Id] = $true
    $g = 'English Entertainment'
    foreach ($k in $groupMap.Keys) { if ($c.Cats -contains $k) { $g = $groupMap[$k]; break } }
    $logo = "https://assets.iptv-org.github.io/assets/logo/$($c.Id).png"
    $added += [pscustomobject]@{
      Name = "$($c.Name) ($($c.Q))"; Group = $g; Id = $c.Id
      Meta = "#EXTINF:-1 tvg-id=""$($c.Id)@$($c.Q)"" tvg-name=""$($c.Name)"" tvg-logo=""$logo"" group-title=""$g"",$($c.Name) ($($c.Q))"
      Url  = $c.Url
    }
  }
}
Write-Log "added $(@($added).Count) new channels"

$all = @($kept) + @($added)

# backup before overwrite
if (Test-Path -LiteralPath $OutFile) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
  Copy-Item -LiteralPath $OutFile -Destination "$Script:IPTVRoot\backups\india-$stamp.m3u" -Force `
    -ErrorAction SilentlyContinue
}

$o = New-Object System.Collections.ArrayList
[void]$o.Add('#EXTM3U')
foreach ($g in ($all | Group-Object Group | Sort-Object Name)) {
  foreach ($r in ($g.Group | Sort-Object Name)) { [void]$o.Add($r.Meta); [void]$o.Add($r.Url) }
}
Set-Content -LiteralPath $OutFile -Value $o -Encoding utf8
$total = ($o | Where-Object { $_ -match '^https?://' }).Count

# ------------------------------------------------------------- 6. snapshot
$snap = [pscustomobject]@{
  timestamp      = (Get-Date).ToString('o')
  geo_country    = (Invoke-RestMethod 'https://ipinfo.io/json' -TimeoutSec 20).country
  total_channels = $total
  kept           = @($kept).Count
  dropped        = $dropped
  added          = @($added).Count
  tested         = $toTest.Count
  status_breakdown = @{}
}
foreach ($g in ($results | Group-Object Status)) { $snap.status_breakdown[$g.Name] = $g.Count }
Set-Content -LiteralPath "$Script:IPTVDb\snapshot-latest.json" -Value ($snap | ConvertTo-Json -Depth 4) -Encoding utf8

$hist = "$Script:IPTVDb\history.json"
$all_ = @()
if (Test-Path -LiteralPath $hist) {
  try { $all_ = @(Get-Content -LiteralPath $hist -Raw | ConvertFrom-Json) } catch { $all_ = @() }
}
$all_ += $snap
$all_ | Select-Object -Last 52 |
  ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $hist -Encoding utf8

$elapsed = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
Write-Log "=== done in $elapsed min: $total channels (kept $(@($kept).Count), dropped $dropped, added $(@($added).Count)) ==="
