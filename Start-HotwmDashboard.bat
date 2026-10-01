@echo off
setlocal
cd /d "%~dp0"
start "" powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0gui\HotwmDashboard.ps1"
