<#
  Sweep for additional Hindi and English channels on publisher-owned CDNs.

  Hindi  = Indian-language channels (India country code), any category.
  English= non-India English-language entertainment/news/sports on FAST CDNs,
           since no legal free English-language Indian movie channels exist.

  Emits a URL list for segment-level verification, and a metadata map the
  rebuild step reads back so groups and names stay consistent.
#>
[CmdletBinding()]
param(
  [string]$OutUrls  = "C:\Users\Punit\iptv\cache\sweep-urls.txt",
  [string]$OutMeta  = "C:\Users\Punit\iptv\cache\sweep-meta.csv"
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$channels = Get-Content "$Script:IPTVDbCache\channels.json" -Raw | ConvertFrom-Json
$streams  = Get-Content "$Script:IPTVDbCache\streams.json" -Raw | ConvertFrom-Json

$byId = @{}
foreach ($c in $channels) { if ($c.id) { $byId[$c.id] = $c } }

# already in the live playlist -> don't retest
$existing = @{}
$cur = $null
foreach ($line in (Get-Content -LiteralPath $Script:IPTVPlaylist)) {
  if ($line.StartsWith('#EXTINF')) { $cur = $line }
  elseif ($line -match '^https?://') { $existing[$line] = $true }
}
Write-Host "already in playlist: $($existing.Count)"

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

  # language routing: India = Hindi/Indian-language; elsewhere = English
  $lang = if ($c.country -eq 'IN') { 'Hindi' } else { 'English' }

  $q = if ($st.quality) { $st.quality } else { 'unknown' }
  $rows += [pscustomobject]@{
    Id = $c.id; Name = $c.name; Country = $c.country
    Cats = ($c.categories -join ';'); Lang = $lang; Q = $q; Host = $h; Url = $st.url
  }
}

Write-Host ""
Write-Host "candidates on publisher CDNs:"
$rows | Group-Object Lang | Sort-Object Name | ForEach-Object {
  Write-Host ("  {0,-8} {1}" -f $_.Name, $_.Count)
}

$rows | ForEach-Object { $_.Url } | Sort-Object -Unique | Set-Content -LiteralPath $OutUrls -Encoding utf8
$rows | Sort-Object Lang, Id, Q | Export-Csv -LiteralPath $OutMeta -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "unique URLs to verify: $((Get-Content -LiteralPath $OutUrls).Count)"
Write-Host "meta rows            : $($rows.Count)"
