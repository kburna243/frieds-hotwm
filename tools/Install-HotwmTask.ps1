<#
.SYNOPSIS
    Installs a Windows Scheduled Task to run hotwm_relay automatically at logon.
.DESCRIPTION
    Creates or updates the task 'Gunmote Recoil Stretch' to launch pythonw.exe
    with hotwm_relay.py whenever the user logs into Windows.
.PARAMETER TaskName
    Name of the scheduled task. Default: 'Gunmote Recoil Stretch'.
#>
[CmdletBinding()]
param(
    [string]$TaskName = "Gunmote Recoil Stretch"
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSScriptRoot
$relayPy   = Join-Path $scriptDir "src\hotwm_relay.py"

if (-not (Test-Path $relayPy)) {
    throw "Relay script not found at: $relayPy"
}

$pywCmd = Get-Command pythonw.exe -ErrorAction SilentlyContinue
$pythonw = if ($pywCmd) { $pywCmd.Source } else { $null }
if (-not $pythonw) {
    $pyCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    $pythonw = if ($pyCmd) { $pyCmd.Source } else { $null }
    if (-not $pythonw) {
        throw "Neither pythonw.exe nor python.exe found on PATH."
    }
}

Write-Host "=== Registering Scheduled Task: '$TaskName' ===" -ForegroundColor Cyan
Write-Host "Action: `"$pythonw`" `"$relayPy`"" -ForegroundColor Gray

$workDir = $scriptDir
$action = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$relayPy`"" -WorkingDirectory $workDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Task '$TaskName' registered successfully." -ForegroundColor Green
Write-Host "It will run silently at every user logon." -ForegroundColor Gray
