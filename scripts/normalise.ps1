<#
  Normalise the playlist for stricter M3U parsers.

  Two fixes:
   1. Multi-value group-titles ("Education;News;Science") are ambiguous. Some
      players treat the whole string as one literal group name; others split on
      ';' and drop the entry. Collapse each to its primary (first) category,
      which is how the iptv-org feed already groups the rest.
   2. Guarantee every entry has a non-empty tvg-id, group-title and tvg-name,
      since several players discard entries missing any of these.

  Usage:  pwsh -File normalise.ps1 -InFile playlists\latest.m3u -OutFile playlists\normalised.m3u
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$InFile,
  [string]$OutFile = ""
)

$ErrorActionPreference = 'Stop'

if (-not $OutFile) {
  $OutFile = [System.IO.Path]::ChangeExtension($InFile, 'normalised.m3u')
}

$lines = Get-Content -LiteralPath $InFile
$rows = @()
$cur = $null
foreach ($x in $lines) {
  if ($x.StartsWith('#EXTINF')) {
    $cur = $x
  } elseif ($x -match '^https?://') {
    if ($cur) { $rows += [pscustomobject]@{ Meta = $cur; Url = $x } }
  }
}
Write-Host "parsed $($rows.Count) entries from $InFile"

$fixed = 0
$out = New-Object System.Collections.ArrayList
[void]$out.Add('#EXTM3U')

$seq = 0
foreach ($r in $rows) {
  $meta = $r.Meta
  $id = '';   if ($meta -match 'tvg-id="([^"]*)"')   { $id = $matches[1] }
  $nm  = '';   if ($meta -match 'tvg-name="([^"]*)"') { $nm = $matches[1] }
  $grp = '';   if ($meta -match 'group-title="([^"]*)"') { $grp = $matches[1] }
  $logo = '';  if ($meta -match 'tvg-logo="([^"]*)"')  { $logo = $matches[1] }
  $name = ($meta -split ',')[-1]

  # 1. collapse multi-value group to its primary category
  if ($grp -match ';') {
    $primary = ($grp -split ';')[0].Trim()
    if (-not $primary) { $primary = 'General' }
    $grp = $primary
    $fixed++
  }

  # 2. fill gaps that make strict parsers drop the entry
  if (-not $id) { $id = "ch$seq"; $fixed++ }
  if (-not $grp) { $grp = 'General'; $fixed++ }
  if (-not $nm) { $nm = $name; $fixed++ }
  if (-not $logo) { $logo = "https://assets.iptv-org.github.io/assets/logo/$id.png" }

  $new = "#EXTINF:-1 tvg-id=""$id"" tvg-name=""$nm"" tvg-logo=""$logo"" group-title=""$grp"",$name"
  [void]$out.Add($new)
  [void]$out.Add($r.Url)
  $seq++
}

Set-Content -LiteralPath $OutFile -Value $out -Encoding utf8
Write-Host "normalised entries: $($out.Count - 1)"
Write-Host "fields repaired   : $fixed"

$check = Get-Content -LiteralPath $OutFile
$bad = @($check | Where-Object { $_ -match '^#EXTINF' -and ($_ -match 'group-title=""' -or $_ -match 'tvg-id=""') })
Write-Host "entries missing required attrs: $($bad.Count)"
