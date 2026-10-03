<#
  Sweep every publisher-owned channel on the upstream index, across all
  languages, and emit a URL list for segment-level verification.

  Language is inferred from the iptv-org country field and channel name. That
  is a heuristic: iptv-org has no language field, so a country maps to a
  language family. Indian channels are further split by name into Hindi,
  Marathi, Tamil, Telugu, Bengali, Malayalam, Kannada, Punjabi and the rest,
  since "India" alone cannot tell them apart.

  Usage: pwsh -File sweep-all.ps1
#>
[CmdletBinding()]
param(
  [string]$OutUrls = "C:\Users\Punit\iptv\cache\all-urls.txt",
  [string]$OutMeta = "C:\Users\Punit\iptv\cache\all-meta.csv"
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

# Fresh index, so the sweep is not limited to whatever was cached hours ago.
Write-Host "fetching upstream index..."
Invoke-WebRequest -Uri 'https://iptv-org.github.io/api/channels.json' `
  -OutFile "$Script:IPTVDbCache\channels.json" -TimeoutSec 180
Invoke-WebRequest -Uri 'https://iptv-org.github.io/api/streams.json' `
  -OutFile "$Script:IPTVDbCache\streams.json" -TimeoutSec 300

$channels = Get-Content "$Script:IPTVDbCache\channels.json" -Raw | ConvertFrom-Json
$streams  = Get-Content "$Script:IPTVDbCache\streams.json" -Raw | ConvertFrom-Json
Write-Host "index: $($channels.Count) channels, $($streams.Count) streams"

$byId = @{}
foreach ($c in $channels) { if ($c.id) { $byId[$c.id] = $c } }

# existing -> never retest what we already know plays
$existing = @{}
$cur = $null
foreach ($line in (Get-Content -LiteralPath $Script:IPTVPlaylist)) {
  if ($line.StartsWith('#EXTINF')) { $cur = $line }
  elseif ($line -match '^https?://') { $existing[$line] = $true }
}
Write-Host "already in playlist: $($existing.Count)"

# Indian language detection by name. Ordered: first match wins.
$langPatterns = [ordered]@{
  'Marathi'    = 'Marathi|Maharashtra'
  'Tamil'      = 'Tamil'
  'Telugu'     = 'Telugu'
  'Bengali'    = 'Bengali|Bangla'
  'Malayalam'  = 'Malayalam'
  'Kannada'    = 'Kannada'
  'Punjabi'    = 'Punjabi'
  'Gujarati'   = 'Gujarati'
  'Odia'       = 'Odia|Orissa'
  'Assamese'   = 'Assam|Prag News'
  'Urdu'       = 'Urdu'
  'Nepali'     = 'Nepali'
  'Sindhi'     = 'Sindhi'
  'Konkani'    = 'Konkani'
  'Kashmiri'   = 'Kashmir'
  'Dogri'      = 'Dogri'
  'Maithili'   = 'Maithili'
  'Bhojpuri'   = 'Bhojpuri'
  'Haryanvi'   = 'Haryanvi'
}

function Get-Lang($channel) {
  $n = $channel.name
  foreach ($k in $langPatterns.Keys) {
    if ($n -match $langPatterns[$k]) { return $k }
  }
  if ($channel.country -eq 'IN') { return 'Hindi' }
  return 'English'
}

$entCats = @('general','news','movies','series','entertainment','classic','comedy',
             'animation','family','documentary','kids','sports','music','religious',
             'lifestyle','education','business','culture','outdoor','travel','cooking')

$rows = @()
foreach ($st in $streams) {
  if (-not $st.channel -or -not $st.url) { continue }
  if ($existing.ContainsKey($st.url)) { continue }
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
  $rows += [pscustomobject]@{
    Id = $c.id; Name = $c.name; Country = $c.country
    Cats = ($c.categories -join ';'); Lang = (Get-Lang $c); Q = $q; Host = $h; Url = $st.url
  }
}

Write-Host ""
Write-Host "candidates by language:"
$rows | Group-Object Lang | Sort-Object Count -Descending | ForEach-Object {
  Write-Host ("  {0,-12} {1}" -f $_.Name, $_.Count)
}
Write-Host ("  {0,-12} {1}" -f 'TOTAL', $rows.Count)

$rows | ForEach-Object { $_.Url } | Sort-Object -Unique | Set-Content -LiteralPath $OutUrls -Encoding utf8
$rows | Sort-Object Lang, Id, Q | Export-Csv -LiteralPath $OutMeta -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "unique URLs to verify: $((Get-Content -LiteralPath $OutUrls).Count)"