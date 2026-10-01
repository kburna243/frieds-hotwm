<#
.SYNOPSIS
    Sends test haptic pulses or LED sequences to the running hotwm relay.
.DESCRIPTION
    Connects to the hotwm relay server (localhost:8000 by default) and triggers
    immediate recoil rumble or player LED sequences without launching any game.
.PARAMETER Player
    Player slot to test (1 or 2). Default: 1.
.PARAMETER Action
    Action to trigger: 'Rumble', 'Leds', or 'Ping'. Default: 'Rumble'.
.PARAMETER Port
    TCP port of the hotwm relay. Default: 8000.
.EXAMPLE
    .\Test-HotwmHaptics.ps1 -Player 1 -Action Rumble
.EXAMPLE
    .\Test-HotwmHaptics.ps1 -Player 2 -Action Leds
#>
[CmdletBinding()]
param(
    [ValidateSet(1, 2)]
    [int]$Player = 1,

    [ValidateSet('Rumble', 'Leds', 'Ping')]
    [string]$Action = 'Rumble',

    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Hook of the Wiimote (hotwm) — Haptics Test ===" -ForegroundColor Cyan
Write-Host "Connecting to relay at 127.0.0.1:$Port..." -ForegroundColor Gray

try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $connectTask = $client.ConnectAsync("127.0.0.1", $Port)
    if (-not $connectTask.Wait(2000)) {
        throw "Timeout connecting to 127.0.0.1:$Port. Is hotwm_relay running?"
    }

    $stream = $client.GetStream()
    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII)
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
    $writer.AutoFlush = $true

    $cmd = switch ($Action) {
        'Rumble' { "CMD_TEST_P$($Player)_RUMBLE" }
        'Leds'   { "CMD_TEST_P$($Player)_LEDS" }
        'Ping'   { "PING" }
    }

    Write-Host "Sending command: $cmd" -ForegroundColor Yellow
    $writer.WriteLine($cmd)

    if ($Action -eq 'Ping') {
        $resp = $reader.ReadLine()
        Write-Host "Relay Response: $resp" -ForegroundColor Green
    } else {
        Start-Sleep -Milliseconds 300
        Write-Host "Triggered P$Player $Action on Wiimote via Gunmote!" -ForegroundColor Green
    }

    $client.Close()
} catch {
    Write-Error "Failed to test haptics: $($_.Exception.Message)"
}
