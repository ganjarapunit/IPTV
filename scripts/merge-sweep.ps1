<#
  Merge verified sweep results into the live playlist.

  Keeps one entry per channel id per group, preferring the highest quality.
  Existing channels are preserved untouched; only genuinely new ones are added.

  Usage: pwsh -File merge-sweep.ps1
#>
[CmdletBinding()]
param(
  # Distinct names: PowerShell variables are case-insensitive, so $Meta/$meta
  # or $Status/$r.Status would silently collide and break the lookups below.
  [string]$MetaCsv = "C:\Users\Punit\iptv\cache\sweep-meta.csv",
  [string]$StatusCsv = "C:\Users\Punit\iptv\cache\sweep-status.csv",
  [string]$Playlist = ""
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
if (-not $Playlist) { $Playlist = $Script:IPTVPlaylist }

$okSet = @{}
foreach ($row in (Import-Csv -LiteralPath $StatusCsv)) {
  if ($row.Status -eq 'ok' -and $row.Url -and $row.Url.Trim() -ne '') {
    $okSet[$row.Url.Trim()] = $true
  }
}
Write-Host "ok URLs loaded: $($okSet.Count)"
$metaRows = @(Import-Csv -LiteralPath $MetaCsv)
Write-Host "meta rows    : $($metaRows.Count)"

$candidates = @($metaRows | Where-Object {
  $_.Url -and $_.Url.Trim() -ne '' -and $okSet.ContainsKey($_.Url.Trim())
})
Write-Host "verified playable: $($candidates.Count)"
# current playlist
$rows = @()
$cur = $null
foreach ($line in (Get-Content -LiteralPath $Playlist)) {
  if ($line.StartsWith('#EXTINF')) { $cur = $line }
  elseif ($line -match '^https?://') {
    $id = '';   if ($cur -match 'tvg-id="([^"]*)"')   { $id = $matches[1] }
    $g  = '';   if ($cur -match 'group-title="([^"]*)"') { $g = $matches[1] }
    $rows += [pscustomobject]@{
      Id = $id; Group = $g; Name = ($cur -split ',')[-1]; Meta = $cur; Url = $line
    }
  }
}
Write-Host "existing playlist : $($rows.Count)"

$seenUrl = @{}
foreach ($r in $rows) { $seenUrl[$r.Url] = $true }
$seenId  = @{}
foreach ($r in $rows) { if ($r.Id) { $seenId[$r.Id] = $true } }

# group by language + primary category
$langMap = @{
  'movies'='Movies'; 'classic'='Movies'; 'series'='TV Shows'
  'entertainment'='Entertainment'; 'comedy'='Comedy'
  'animation'='Animation'; 'kids'='Animation'; 'family'='Family'
  'documentary'='Documentary'; 'news'='News'; 'sports'='Sports'
  'music'='Music'; 'religious'='Religious'; 'general'='General'
  'lifestyle'='Lifestyle'; 'education'='Education'
  'business'='Business'; 'culture'='Culture'
}

$added = @()
$candidates |
  Sort-Object -Property @{ Expression = { Get-QualityRank $_.Q }; Descending = $true } |
  ForEach-Object {
    $c = $_
    if ($seenUrl.ContainsKey($c.Url)) { return }
    if ($seenId.ContainsKey($c.Id)) { return }

    $seenUrl[$c.Url] = $true
    $seenId[$c.Id] = $true

    $cat = ($c.Cats -split ';')[0]
    $base = if ($langMap.ContainsKey($cat)) { $langMap[$cat] } else { 'Entertainment' }
    $group = "$($c.Lang) $base"

    $logo = "https://assets.iptv-org.github.io/assets/logo/$($c.Id).png"
    $name = "$($c.Name) ($($c.Q))"
    $added += [pscustomobject]@{
      Id = $c.Id; Group = $group; Name = $name
      Meta = "#EXTINF:-1 tvg-id=""$($c.Id)@$($c.Q)"" tvg-name=""$($c.Name)"" tvg-logo=""$logo"" group-title=""$group"",$name"
      Url = $c.Url
    }
  }

Write-Host "new channels      : $($added.Count)"
$added | Group-Object Group | Sort-Object Name | ForEach-Object {
  Write-Host ("  {0,-28} {1}" -f $_.Name, $_.Count)
}

$all = @($rows) + @($added)
$o = New-Object System.Collections.ArrayList
[void]$o.Add('#EXTM3U')
foreach ($g in ($all | Group-Object Group | Sort-Object Name)) {
  foreach ($r in ($g.Group | Sort-Object Name)) { [void]$o.Add($r.Meta); [void]$o.Add($r.Url) }
}
Set-Content -LiteralPath $Playlist -Value $o -Encoding utf8
$total = ($o | Where-Object { $_ -match '^https?://' }).Count
Write-Host ""
Write-Host "TOTAL: $total"
