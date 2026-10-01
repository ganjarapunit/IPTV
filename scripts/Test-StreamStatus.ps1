# Segment-level stream verification.
#
# A playlist returning HTTP 200 proves nothing: the segments behind it may 403.
# (This is exactly how Willow passed an earlier check and played nothing.)
# So we resolve the playlist, then download real media segments and measure.

function Get-StreamStatus($Url) {
  $res = [pscustomobject]@{ Url = $Url; Status = 'fail'; Bytes = 0; Note = '' }
  try {
    $r = Invoke-WebRequest -Uri $Url -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
         -TimeoutSec 15 -MaximumRedirection 3
    $b = $r.Content
    if ($b -is [byte[]]) { $b = [System.Text.Encoding]::UTF8.GetString($b) }
    if ($b -notmatch '#EXTM3U') { $res.Status = 'not-playlist'; return $res }

    $base = $Url.Substring(0, $Url.LastIndexOf('/') + 1)
    $targets = @()
    if ($b -match '#EXT-X-STREAM-INF') {
      $ln = $b -split "`n"
      for ($i = 0; $i -lt $ln.Count; $i++) {
        if ($ln[$i] -match '#EXT-X-STREAM-INF') {
          $u = $ln[$i + 1].Trim()
          if ($u -ne '') {
            if ($u -notmatch '^http') { $u = "$base$u" }
            $targets += $u
          }
        }
      }
      if ($targets.Count -eq 0) { $res.Status = 'no-variants'; return $res }
      $targets = @($targets | Select-Object -First 4)
    } else {
      $targets = @($Url)
    }

    $sawSegments = $false
    foreach ($m in $targets) {
      try {
        $v = Invoke-WebRequest -Uri $m -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
             -TimeoutSec 15 -MaximumRedirection 3
        $vb = $v.Content
        if ($vb -is [byte[]]) { $vb = [System.Text.Encoding]::UTF8.GetString($vb) }
        $segs = @($vb -split "`n" | Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' })
        if ($segs.Count -eq 0) { continue }
        $sawSegments = $true
        $mb = $m.Substring(0, $m.LastIndexOf('/') + 1)
        $pick = @($segs[0], $segs[[int]($segs.Count / 2)], $segs[$segs.Count - 1]) |
                Select-Object -Unique
        $good = 0; $bytes = 0
        foreach ($sg in $pick) {
          $su = $sg.Trim()
          if ($su -notmatch '^http') { $su = "$mb$su" }
          try {
            $sv = Invoke-WebRequest -Uri $su -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
                  -TimeoutSec 20 -MaximumRedirection 3
            if ($sv.RawContentLength -gt 20000) { $good++; $bytes += $sv.RawContentLength }
          } catch { }
        }
        if ($good -gt 0) {
          $res.Status = 'ok'; $res.Bytes = $bytes
          $res.Note = "$good/$($pick.Count) segs"
          return $res
        }
      } catch {
        if ($_.Exception.Message -match '403') { $res.Note = 'geo-blocked' }
      }
    }
    if ($sawSegments) { $res.Status = 'segments-blocked' }
    elseif ($res.Note -eq '') { $res.Status = 'segments-unreachable' }
    return $res
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match '403')      { $res.Status = 'geo-blocked';       $res.Note = 'playlist 403' }
    elseif ($msg -match '404')  { $res.Status = 'dead' }
    elseif ($msg -match 'timed out|timeout') { $res.Status = 'timeout' }
    else { $res.Note = ($msg -replace '\s+', ' ') }
    return $res
  }
}
