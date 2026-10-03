<#
  Rebuild the playlist from scratch: keep only verified-playable channels,
  add newly verified ones, group by language and category.

  Usage: pwsh -File rebuild-all.ps1
#>
[CmdletBinding()]
param(
  [string]$MetaCsv   = "C:\Users\Punit\iptv\cache\all-meta.csv",
  [string]$StatusCsv = "C:\Users\Punit\iptv\cache\combined-status.csv",
  [string]$Playlist = ""
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
if (-not $Playlist) { $Playlist = $Script:IPTVPlaylist }

# --------------------------------------------------- verified URL whitelist
$okSet = @{}
foreach ($row in (Import-Csv -LiteralPath $StatusCsv)) {
  if ($row.Status -eq 'ok' -and $row.Url -and $row.Url.Trim() -ne '') {
    $okSet[$row.Url.Trim()] = $true
  }
}
Write-Host "verified playable URLs: $($okSet.Count)"

# ------------------------------------------------------------- existing rows
$existing = @()
$cur = $null
foreach ($line in (Get-Content -LiteralPath $Playlist)) {
  if ($line.StartsWith('#EXTINF')) { $cur = $line }
  elseif ($line -match '^https?://') {
    $id = ''; if ($cur -match 'tvg-id="([^"]*)"')   { $id = $matches[1] }
    $g  = ''; if ($cur -match 'group-title="([^"]*)"') { $g = $matches[1] }
    $existing += [pscustomobject]@{
      Id = $id; Group = $g; Name = ($cur -split ',')[-1]; Meta = $cur; Url = $line
    }
  }
}
Write-Host "existing rows          : $($existing.Count)"

$kept = @($existing | Where-Object { $okSet.ContainsKey($_.Url) })
$dropped = $existing.Count - $kept.Count
Write-Host "kept / dropped         : $(@($kept).Count) / $dropped"

# --------------------------------------------------------------- new channels
$seenUrl = @{}
foreach ($r in $kept) { $seenUrl[$r.Url] = $true }
$seenId = @{}
foreach ($r in $kept) { if ($r.Id) { $seenId[$r.Id] = $true } }

$catMap = @{
  'movies'='Movies'; 'classic'='Movies'; 'series'='TV Shows'
  'entertainment'='Entertainment'; 'comedy'='Comedy'
  'animation'='Animation'; 'kids'='Animation'; 'family'='Family'
  'documentary'='Documentary'; 'news'='News'; 'sports'='Sports'
  'music'='Music'; 'religious'='Religious'; 'general'='General'
  'lifestyle'='Lifestyle'; 'education'='Education'
  'business'='Business'; 'culture'='Culture'
}

$metaRows = @(Import-Csv -LiteralPath $MetaCsv)
$added = @()
$metaRows |
  Sort-Object -Property @{ Expression = { Get-QualityRank $_.Q }; Descending = $true } |
  ForEach-Object {
    $c = $_
    if (-not $c.Url) { return }
    if (-not $okSet.ContainsKey($c.Url.Trim())) { return }
    if ($seenUrl.ContainsKey($c.Url)) { return }
    if ($c.Id -and $seenId.ContainsKey($c.Id)) { return }

    $seenUrl[$c.Url] = $true
    if ($c.Id) { $seenId[$c.Id] = $true }

    $cat = ($c.Cats -split ';')[0]
    $base = if ($catMap.ContainsKey($cat)) { $catMap[$cat] } else { 'Entertainment' }
    $group = "$($c.Lang) $base"
    $logo = "https://assets.iptv-org.github.io/assets/logo/$($c.Id).png"
    $name = "$($c.Name) ($($c.Q))"

    $added += [pscustomobject]@{
      Id = $c.Id; Group = $group; Name = $name; Lang = $c.Lang
      Meta = "#EXTINF:-1 tvg-id=""$($c.Id)@$($c.Q)"" tvg-name=""$($c.Name)"" tvg-logo=""$logo"" group-title=""$group"",$name"
      Url  = $c.Url
    }
  }
Write-Host "new channels added     : $($added.Count)"

$all = @($kept) + @($added)
$o = New-Object System.Collections.ArrayList
[void]$o.Add('#EXTM3U')
foreach ($g in ($all | Group-Object Group | Sort-Object Name)) {
  foreach ($r in ($g.Group | Sort-Object Name)) { [void]$o.Add($r.Meta); [void]$o.Add($r.Url) }
}
Set-Content -LiteralPath $Playlist -Value $o -Encoding utf8
$total = ($o | Where-Object { $_ -match '^https?://' }).Count

Write-Host ""
Write-Host "TOTAL: $total"
Write-Host ""
Write-Host "by language:"
$langTotals = @{}
foreach ($r in $all) {
  $l = ($r.Group -split ' ')[0]
  if (-not $langTotals.ContainsKey($l)) { $langTotals[$l] = 0 }
  $langTotals[$l]++
}
$langTotals.GetEnumerator() | Sort-Object Value -Descending |
  ForEach-Object { Write-Host ("  {0,-12} {1}" -f $_.Key, $_.Value) }