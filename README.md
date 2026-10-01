# IPTV — free-to-air playlist (Vietnam)

A curated, **self-verifying** playlist of free-to-air TV channels that play from Vietnam.

## TV playlist URL

```
https://raw.githubusercontent.com/ganjarapunit/IPTV/main/playlists/latest.m3u
```

Paste this into any IPTV player that accepts an M3U URL. Playback does **not**
require this PC to be on — GitHub serves the file.

## What is in here

Only **publisher-owned** streams: Prasar Bharati/DD, Zee, Sony, NDTV, News18,
Amagi FAST, Samsung TV Plus, Yupp, Roku, Rakuten, Tarang, and each channel's own CDN.

**Not included:** HBO, Sky Sports, Star Sports, Sony Max, Hotstar, or any other
subscription channel. Those appear in public indexes only as unauthorized
relays, and they are excluded here — see `scripts/common.ps1`
(`$BlockedHosts`). This list is free-to-air only.

## How channels get verified

A playlist returning HTTP 200 proves nothing. The `.m3u` can load while every
video segment behind it returns `403`. That failure mode shipped a broken
Willow feed here once.

So `scripts/Test-StreamStatus.ps1` resolves the playlist, walks to the media
playlist, and **downloads real `.ts` segments**, measuring bytes. A channel is
only kept if actual video data arrives.

## Why refresh runs on a PC, not GitHub Actions

`refresh.ps1` must test from Vietnam, because results are geo-dependent.
GitHub-hosted runners execute in US/EU Azure datacenters, where the answer
inverts: Vietnamese FTA channels fail and US-only channels succeed. There is
also no Vietnam probe available from any public multi-region checker
(checked: 59 check-host.net nodes, zero VN).

So the split is:

- **`refresh.ps1`** — runs on your PC via Windows Task Scheduler (weekly,
  Sunday 05:00). Tests from Vietnam. This is the authoritative source.
- **`publish.ps1`** — commits the verified playlist and pushes it.
- GitHub serves the file to the TV; Actions are not used for geo-testing.

## Commands

```powershell
cd C:\Users\Punit\iptv

.\scripts\publish.ps1              # refresh if stale, then commit + push
.\scripts\publish.ps1 -NoRefresh   # push current playlist unchanged
.\scripts\refresh.ps1             # verification only, no git
.\scripts\status.ps1              # health + week-by-week drift table
.\scripts\serve.ps1               # local server (faster than GitHub for LAN TV)
.\scripts\serve.ps1 -Port 8000    # LAN playback, use the LAN URL instead
```

Run the scheduled task on demand:

```powershell
Start-ScheduledTask -TaskName 'IPTV Playlist Refresh'
```

## Layout

```
playlists/latest.m3u      the file the TV fetches
playlists/YYYY-MM-DD.m3u  dated snapshots (last 30 kept)
status.json               last refresh summary
scripts/                  refresh, verify, publish, serve, status
db/                       snapshot + history (local, gitignored)
```

## Caching

`raw.githubusercontent.com` sends `Cache-Control: max-age=300`, and some Tizen
players cache for far longer than five minutes. A fresh push may not appear on
the TV straight away — reload the playlist in the player, or use the local
`serve.ps1` URL while testing.

## Caveats

- Availability tracks Viettel's international routing. Channels geo-blocked
  now may recover later, or regress. That is what the weekly refresh is for.
- A handful of "English" channels carry Hindi or regional content. Check the
  `group-title` in the M3U.
- Programming is not licensed by this playlist. Each publisher's own terms
  and territorial rights still apply to you as a viewer.
