# Shared config + helpers for the IPTV playlist maintenance scripts.

$Script:IPTVRoot = "C:\Users\Punit\iptv"
$Script:IPTVDir  = "$Script:IPTVRoot\scripts"
$Script:IPTVDb   = "$Script:IPTVRoot\db"
$Script:IPTVDbCache = "$Script:IPTVRoot\cache"
$Script:IPTVDlogs = "$Script:IPTVRoot\logs"
$Script:IPTVChan = "$Script:IPTVRoot\channels.json"
$Script:IPTVStreams = "$Script:IPTVRoot\streams.json"
$Script:IPTVPlaylist = "$Script:IPTVRoot\india-free-vietnam.m3u"

foreach ($d in @($Script:IPTVDb, $Script:IPTVDbCache, $Script:IPTVDlogs)) {
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# Publisher-owned / officially-licensed CDN infrastructure.
# Third-party relays and proxy wrappers are deliberately absent.
$Script:AllowedHosts = @(
  # Prasar Bharati / AIR / DD
  'playhls.media.nic.in',
  # Indian publishers and FAST partners
  'tarangplus.in','smartplaytv.in','tangotv.in','intoday.in','vgcdn.net',
  'timeiptv.in','newscapital.com','vrlivegujarat.com','ekamraott.com',
  'rajtv.tv','castmaxcloud.com','guaranteenews.in','roncastnet.in',
  # Zee / Sony / Viacom / Star
  'pishow.tv','sonyliv.com','colors.in',
  # Yupp
  'yuppcdn.net',
  # FAST platforms
  'amagi.tv','samsungtv.plus','wurl.tv','wurl.com','roku.com','xumo.com',
  'cloudfront.net','akamaized.net','akamaihd.net','mediatailor',
  'streamlock.net','nexcdn.online','fastly.net','llnwd.net',
  # Regional / ethnic publisher groups (official sites)
  'wrencdn.in','smartstream.video','wiseplayout.com','vstream.online',
  'sofast.tv','lotus.stingray.com','kbpnews.cloud','dksmedia.tv',
  'henico.net','abnvideos.com','cdn2.in','live247stream.com','runn.tv',
  # Educational / government
  'doordash.tv'
)

# Known-bad relay infrastructure. Belt-and-braces: a stream is rejected if its
# host matches these even if something else would have allowed it.
$Script:BlockedHosts = @(
  '51.75.127.199','aynaott.com','aynascope.net','nellaiiptv.com','ncare.live',
  'jmp2.uk','rutube.ru','thelegitpro.in','legitpro.co.in','bozztv.com',
  'zillarbarta.com','dpdns.org','duckdns.org','iptelevision.live',
  'iptelevishion.com','livebox.co.in','ottlive.co.in','jswk.online',
  'gigabitcdn.net','galaxyott.live','bhagyam.net','proxy','workers.dev'
)

function Test-AllowedHost([string]$Host_) {
  if (-not $Host_) { return $false }
  $h = $Host_.ToLower()
  foreach ($b in $Script:BlockedHosts) { if ($h.Contains($b)) { return $false } }
  foreach ($a in $Script:AllowedHosts) {
    if ($h -eq $a) { return $true }
    if ($h.EndsWith("." + $a)) { return $true }
  }
  return $false
}

function Get-QualityRank([string]$q) {
  switch ($q) {
    '2160p' { 5 } '4K' { 5 } '1440p' { 4.5 } '1080p' { 4 } 'FHD' { 4 }
    '720p'  { 3 } 'HD'   { 3 } '576p' { 2 } 'SD' { 2 }
    '480p'  { 1 } '360p'  { 0.5 }
    default { 0 }
  }
}

function Write-Log([string]$Message, [string]$Level = 'INFO') {
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "$ts [$Level] $Message"
  Write-Host $line
  $f = Join-Path $Script:IPTVDlogs ("refresh_{0}.log" -f (Get-Date -Format 'yyyy-MM'))
  Add-Content -LiteralPath $f -Value $line -Encoding utf8
}
