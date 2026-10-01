<#
  Register a weekly Windows Scheduled Task that runs refresh.ps1.

  Default: Sundays at 05:00 local time. Requires admin for SYSTEM-level runs;
  without -AsSystem it registers under the current user, which is enough and
  avoids storing credentials.
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

$refresh = "$Script:IPTVDir\refresh.ps1"

# Resolve an absolute pwsh path; the task scheduler dislikes PATH lookups.
if (-not $pwsh) { Write-Host 'PowerShell not found' -ForegroundColor Red; exit 1 }

$action = New-ScheduledTaskAction `
  -Execute $pwsh `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$refresh`"" `
  -WorkingDirectory $Script:IPTVRoot

$at = [datetime]::ParseExact($Time, 'HH:mm', $null)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $at

# Don't hammer the upstream index if runs overlap
$multi = 3
$dur = New-TimeSpan -Hours 1

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
Write-Host "  script:     $refresh"

if (-not $AsSystem) {
  Write-Host ""
  Write-Host "NOTE: with -LogonType Interactive this only runs while you are" -ForegroundColor Yellow
  Write-Host "      logged in. Re-run with -AsSystem from an admin prompt for" -ForegroundColor Yellow
  Write-Host "      unattended weekly runs." -ForegroundColor Yellow
}

Register-ScheduledTask -TaskName $taskName `
  -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
  -Force | Out-Null

Write-Host ""
Write-Host "registered. verify with:" -ForegroundColor Green
Write-Host "  Get-ScheduledTask -TaskName '$taskName' | Get-ScheduledTaskInfo"
Write-Host "  Start-ScheduledTask -TaskName '$taskName'   # run now"
