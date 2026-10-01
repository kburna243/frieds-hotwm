<#
.SYNOPSIS
    Starts the hotwm output relay server.
.DESCRIPTION
    Checks Python environment, validates config, and launches hotwm_relay.py.
    Can run in the foreground or as a hidden background process via pythonw.exe.
.PARAMETER Background
    If specified, runs invisibly in the background via pythonw.exe.
.PARAMETER ConfigPath
    Optional path to a custom hotw.json configuration file.
#>
[CmdletBinding()]
param(
    [switch]$Background,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSScriptRoot
$relayPy   = Join-Path $scriptDir "src\hotwm_relay.py"

if (-not (Test-Path $relayPy)) {
    throw "Relay script not found at: $relayPy"
}

# 1. Check Python
$pyExe = if ($Background) { "pythonw.exe" } else { "python.exe" }
$pyCmd = Get-Command $pyExe -ErrorAction SilentlyContinue

if (-not $pyCmd) {
    # Fallback to python.exe if pythonw not on PATH
    $pyExe = "python.exe"
    $pyCmd = Get-Command $pyExe -ErrorAction SilentlyContinue
    if (-not $pyCmd) {
        throw "Python was not found on PATH. Please install Python 3.10 or newer."
    }
}

Write-Host "=== Starting Hook of the Wiimote (hotwm) Relay ===" -ForegroundColor Cyan
Write-Host "Python: $($pyCmd.Source)" -ForegroundColor Gray
Write-Host "Script: $relayPy" -ForegroundColor Gray

$argsList = @()
$argsList += "`"$relayPy`""
if ($ConfigPath) {
    $argsList += "--config"
    $argsList += "`"$ConfigPath`""
}

if ($Background) {
    Write-Host "Launching in background (hidden)..." -ForegroundColor Yellow
    $p = Start-Process -FilePath $pyCmd.Source -ArgumentList ($argsList -join " ") -WindowStyle Hidden -PassThru
    Write-Host "hotwm relay running in background with Process ID: $($p.Id)" -ForegroundColor Green
} else {
    Write-Host "Running in foreground (Ctrl+C to stop)..." -ForegroundColor Yellow
    & $pyCmd.Source $relayPy
}
