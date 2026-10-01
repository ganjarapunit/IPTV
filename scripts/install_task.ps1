<#
  Register a weekly Windows Scheduled Task that runs publish.ps1.

  publish.ps1 verifies every channel from THIS machine (correct Vietnam egress,
  which is why refresh cannot run in GitHub Actions) and then commits and
  pushes, so the playlist the TV fetches from raw.githubusercontent.com stays
  current even while this PC is off most of the week.

  Default: Sundays at 05:00 local time.
#>
[CmdletBinding()]
param(
  [ValidateSet('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')]
  [string]$DayOfWeek = 'Sunday',
  [string]$Time = '05:00',
  [switch]$AsSystem
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$taskName = 'IPTV Playlist Refresh'

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }

# publish.ps1, not refresh.ps1: it verifies AND pushes, so the GitHub copy the
# TV reads is never stale.
$script = "$Script:IPTVDir\publish.ps1"

# Resolve an absolute pwsh path; the task scheduler dislikes PATH lookups.
if (-not $pwsh) { Write-Host 'PowerShell not found' -ForegroundColor Red; exit 1 }

$action = New-ScheduledTaskAction `
  -Execute $pwsh `
  -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -Unattended" `
  -WorkingDirectory $Script:IPTVRoot

$at = [datetime]::ParseExact($Time, 'HH:mm', $null)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $at

# A full sweep verifies ~1800 existing + ~2400 candidate streams. At 24-way
# parallelism that is roughly 20-40 min, but a slow link or a large candidate
# set can push it well past an hour, so allow generous headroom.
$multi = 2
$dur = New-TimeSpan -Hours 6

$principal = if ($AsSystem) {
  New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
} else {
  # Task Scheduler needs DOMAIN\user, not a bare username.
  $userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
}

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit $dur `
  -RestartCount $multi `
  -RestartInterval (New-TimeSpan -Minutes 20)

Write-Host "registering '$taskName': $DayOfWeek $Time"
Write-Host "  executable: $pwsh"
Write-Host "  script:     $script"
Write-Host "  args:       -Unattended"
Write-Host ""
Write-Host "Each run: re-verifies all channels from this PC, then commits and" -ForegroundColor DarkGray
Write-Host "pushes to GitHub so the TV's raw URL stays current." -ForegroundColor DarkGray

# Fail loudly now rather than silently every Sunday.
$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $git) {
  Write-Host "git not found on PATH - publish step would fail" -ForegroundColor Red
  exit 1
}
$helper = git config --get credential.helper
if (-not $helper) {
  Write-Host "no git credential.helper set. 'git push' will prompt for" -ForegroundColor Yellow
  Write-Host "credentials and hang when the task runs unattended." -ForegroundColor Yellow
  Write-Host "  fix: git config --global credential.helper manager" -ForegroundColor Yellow
} else {
  Write-Host "git credential.helper: $helper" -ForegroundColor Green
}

if (-not $AsSystem) {
  Write-Host ""
  Write-Host "NOTE: -LogonType Interactive means this only runs while you are" -ForegroundColor Yellow
  Write-Host "      logged in. For unattended runs use -AsSystem from an admin" -ForegroundColor Yellow
  Write-Host "      prompt, but note SYSTEM's network egress may route differently" -ForegroundColor Yellow
  Write-Host "      from this machine and skew the geo-verification." -ForegroundColor Yellow
}

Register-ScheduledTask -TaskName $taskName `
  -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
  -Force | Out-Null

Write-Host ""
Write-Host "registered. verify with:" -ForegroundColor Green
Write-Host "  Get-ScheduledTask -TaskName '$taskName' | Get-ScheduledTaskInfo"
Write-Host "  Start-ScheduledTask -TaskName '$taskName'   # run now"
