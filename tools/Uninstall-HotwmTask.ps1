<#
.SYNOPSIS
    Uninstalls the hotwm Windows Scheduled Task.
.PARAMETER TaskName
    Name of the scheduled task. Default: 'Gunmote Recoil Stretch'.
#>
[CmdletBinding()]
param(
    [string]$TaskName = "Gunmote Recoil Stretch"
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Removing Scheduled Task: '$TaskName' ===" -ForegroundColor Cyan

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Task '$TaskName' removed." -ForegroundColor Green
} else {
    Write-Host "Task '$TaskName' was not found." -ForegroundColor Gray
}
