#Requires -Version 5.1
<#
.SYNOPSIS
    Hook of the Wiimote (hotwm) — Standalone WPF Dashboard & Recoil Stretcher Controller.
.DESCRIPTION
    Native Windows Presentation Foundation GUI for hotwm.
    Provides:
    - Hardware & service health traffic lights (Relay, Gunmote, ViGEmBus, Wiimotes, Kit API)
    - 1-Click Wiimote rumble & LED haptic test bench
    - Real-time pulse stretch duration tuning (80ms - 300ms) with live hot-reload
    - Per-game arcade rumble & LED profile toggles
    - Live trace log monitor for MAME recoil events
.PARAMETER NoShow
    Instantiates and returns the window object without showing it (for automated Pester tests and CI).
#>
[CmdletBinding()]
param(
    [switch]$NoShow
)

$ErrorActionPreference = 'Stop'

# Add WPF assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$guiDir  = $PSScriptRoot
$repoDir = Split-Path -Parent $guiDir
$xamlPath = Join-Path $guiDir "HotwmDashboard.xaml"
$script:configPath = Join-Path $repoDir "config\hotw.json"
$setupState = [pscustomobject]@{ RetroBatRoot = $null; Root = $null }
$toolsDir = Join-Path $repoDir "tools"
$srcDir = Join-Path $repoDir "src"

# Dot-source KitClient if present
$kitClientScript = Join-Path $srcDir "KitClient.ps1"
if (Test-Path $kitClientScript) {
    . $kitClientScript
}
$setupCoreScript = Join-Path $srcDir 'HotwmSetup.ps1'
if (Test-Path $setupCoreScript) { . $setupCoreScript }
$deviceScript = Join-Path $srcDir 'HotwmDevices.ps1'
if (Test-Path $deviceScript) { . $deviceScript }

if (-not (Test-Path $xamlPath)) {
    throw "XAML file not found at: $xamlPath"
}

# 1. Load and parse XAML
$xaml = [System.IO.File]::ReadAllText($xamlPath)
$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

# 2. Map named controls
$controls = @{}
foreach ($m in [regex]::Matches($xaml, 'x:Name="([A-Za-z0-9_]+)"')) {
    $name = $m.Groups[1].Value
    $element = $window.FindName($name)
    if ($element) { $controls[$name] = $element }
}

# hotwm's own version: the VERSION file is the one source (the package builder reads it too)
$controls.TextVersion.Text = 'v' + $(try { ([IO.File]::ReadAllText((Join-Path $repoDir 'VERSION'))).Trim() } catch { '?' })

# Helper: Brushes
$brushGreen  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00E676")
$brushRed    = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FF5252")
$brushYellow = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFB020")
$brushGray   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8F93A2")
$brushCyan   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00E5FF")

# Helper: Send Socket Command
function Send-HotwmSocketCommand {
    param([string]$Command, [int]$Port = 8000, [int]$TimeoutMs = 1500)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connectTask = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $connectTask.Wait($TimeoutMs)) {
            $client.Close()
            return @{ Success = $false; Response = "Connection timed out" }
        }
        $stream = $client.GetStream()
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::ASCII)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
        $writer.AutoFlush = $true

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $writer.WriteLine($Command)

        if ($Command -eq "PING") {
            $readTask = $reader.ReadLineAsync()
            if ($readTask.Wait($TimeoutMs)) {
                $sw.Stop()
                $resp = $readTask.Result
                $client.Close()
                return @{ Success = ($resp -eq "PONG"); Response = $resp; LatencyMs = $sw.ElapsedMilliseconds }
            }
        }
        Start-Sleep -Milliseconds 100
        $client.Close()
        return @{ Success = $true; Response = "OK"; LatencyMs = $sw.ElapsedMilliseconds }
    } catch {
        return @{ Success = $false; Response = $_.Exception.Message }
    }
}

# 3. Component Check Functions
function Get-RelayStatus {
    $ping = Send-HotwmSocketCommand -Command "PING" -TimeoutMs 800
    if ($ping.Success) {
        return @{ Running = $true; Message = "Listening on port 8000 (Ping: $($ping.LatencyMs)ms)" }
    }

    # Fallback process search
    $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'python%.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*hotwm_relay.py*" }
    if ($procs) {
        $pidList = ($procs | ForEach-Object { $_.ProcessId }) -join ", "
        return @{ Running = $true; Message = "Process running (PID $pidList), starting up..." }
    }
    return @{ Running = $false; Message = "Relay is stopped (Port 8000 inactive)" }
}

function Get-GunmoteStatus {
    $p = Get-Process gunmote -ErrorAction SilentlyContinue
    if ($p) {
        return @{ Running = $true; Message = "Running (PID $($p.Id))" }
    }
    return @{ Running = $false; Message = "Process not detected" }
}

function Get-ViGEmBusStatus {
    $svc = Get-Service ViGEmBus -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        return @{ Running = $true; Message = "Driver service active (Running)" }
    }
    # Check driver via PnP
    $dev = Get-PnpDevice -Class "System" -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -like "*ViGEmBus*" -and $_.Status -eq "OK" }
    if ($dev) {
        return @{ Running = $true; Message = "Device active in Device Manager" }
    }
    return @{ Running = $false; Message = "Driver not active or not installed" }
}

function Get-WiimoteDevicesStatus {
    # Wiimotes over Bluetooth (RVL-CNT-01) or a DolphinBar
    $devices = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "DolphinBar|Wiimote|RVL-CNT-01|Nintendo" -and $_.Status -eq "OK" }
    if ($devices) {
        $names = ($devices | ForEach-Object { $_.FriendlyName } | Select-Object -Unique) -join ", "
        return @{ Connected = $true; Message = "Detected: $names" }
    }
    return @{ Connected = $false; Message = "No Wiimote found (Bluetooth or DolphinBar) in Device Manager" }
}

function Get-HotwmTaskStatus {
    $task = Get-ScheduledTask -TaskName "Gunmote Recoil Stretch" -ErrorAction SilentlyContinue
    if ($task) {
        return @{ Installed = $true; State = $task.State.ToString() }
    }
    return @{ Installed = $false; State = "Not registered" }
}

# 4. Status Update Routine
function Update-DashboardStatus {
    # Relay
    $r = Get-RelayStatus
    if ($r.Running) {
        $controls.RelayHeaderDot.Fill = $brushGreen
        $controls.RelayHeaderStatus.Text = "RELAY RUNNING"
        $controls.RelayHeaderStatus.Foreground = $brushGreen
        $controls.DotRelay.Fill = $brushGreen
        $controls.TextRelayBadge.Text = "ACTIVE"
        $controls.TextRelayBadge.Foreground = $brushGreen
        $controls.TextRelayDetail.Text = $r.Message
    } else {
        $controls.RelayHeaderDot.Fill = $brushRed
        $controls.RelayHeaderStatus.Text = "RELAY STOPPED"
        $controls.RelayHeaderStatus.Foreground = $brushRed
        $controls.DotRelay.Fill = $brushRed
        $controls.TextRelayBadge.Text = "OFFLINE"
        $controls.TextRelayBadge.Foreground = $brushRed
        $controls.TextRelayDetail.Text = $r.Message
    }

    # Gunmote
    $gm = Get-GunmoteStatus
    if ($gm.Running) {
        $controls.DotGunmote.Fill = $brushGreen
        $controls.TextGunmoteBadge.Text = "RUNNING"
        $controls.TextGunmoteBadge.Foreground = $brushGreen
        $controls.TextGunmoteDetail.Text = $gm.Message
    } else {
        $controls.DotGunmote.Fill = $brushGray
        $controls.TextGunmoteBadge.Text = "INACTIVE"
        $controls.TextGunmoteBadge.Foreground = $brushGray
        $controls.TextGunmoteDetail.Text = $gm.Message
    }

    # ViGEmBus
    $vg = Get-ViGEmBusStatus
    if ($vg.Running) {
        $controls.DotVigem.Fill = $brushGreen
        $controls.TextVigemBadge.Text = "OK"
        $controls.TextVigemBadge.Foreground = $brushGreen
        $controls.TextVigemDetail.Text = $vg.Message
    } else {
        $controls.DotVigem.Fill = $brushYellow
        $controls.TextVigemBadge.Text = "MISSING"
        $controls.TextVigemBadge.Foreground = $brushYellow
        $controls.TextVigemDetail.Text = $vg.Message
    }

    # Wiimote / DolphinBar
    $wm = Get-WiimoteDevicesStatus
    if ($wm.Connected) {
        $controls.DotWiimote.Fill = $brushGreen
        $controls.TextWiimoteBadge.Text = "CONNECTED"
        $controls.TextWiimoteBadge.Foreground = $brushGreen
        $controls.TextWiimoteDetail.Text = $wm.Message
    } else {
        $controls.DotWiimote.Fill = $brushYellow
        $controls.TextWiimoteBadge.Text = "NOT FOUND"
        $controls.TextWiimoteBadge.Foreground = $brushYellow
        $controls.TextWiimoteDetail.Text = $wm.Message
    }

    # Task Autostart
    $ts = Get-HotwmTaskStatus
    if ($ts.Installed) {
        $controls.DotTask.Fill = $brushGreen
        $controls.TextTaskBadge.Text = "INSTALLED"
        $controls.TextTaskBadge.Foreground = $brushGreen
        $controls.TextTaskDetail.Text = "Scheduled task: $($ts.State)"
    } else {
        $controls.DotTask.Fill = $brushGray
        $controls.TextTaskBadge.Text = "NOT CONFIGURED"
        $controls.TextTaskBadge.Foreground = $brushGray
        $controls.TextTaskDetail.Text = "Not registered in Task Scheduler"
    }

    # Kit Integration
    if (Get-Command Test-HotwmKitAvailable -ErrorAction SilentlyContinue) {
        $kitAvail = Test-HotwmKitAvailable
        if ($kitAvail) {
            $kitVersion = Get-HotwmKitVersion
            $controls.DotKit.Fill = $brushGreen
            $controls.TextKitBadge.Text = "CONNECTED"
            $controls.TextKitBadge.Foreground = $brushGreen
            $controls.TextKitDetail.Text = "Kit v$($kitVersion): outputs.wiimote_hook + Input Matrix"
        } else {
            $controls.DotKit.Fill = $brushGray
            $controls.TextKitBadge.Text = "STANDALONE"
            $controls.TextKitBadge.Foreground = $brushGray
            $controls.TextKitDetail.Text = "Kit not found (Running standalone mode)"
        }
    }
}

# 5. Load and Bind Configuration
class HotwmGameProfile {
    [string]$Name
    [bool]$Rumble
    [bool]$Leds
}

$script:gameProfileList = [System.Collections.ObjectModel.ObservableCollection[HotwmGameProfile]]::new()

function Load-HotwmConfig {
    if (-not (Test-Path $script:configPath)) { return }
    try {
        $raw = Get-Content -LiteralPath $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.global) {
            $controls.SliderHoldMs.Value = [double]$raw.global.hold_ms
            $controls.TextHoldMsValue.Text = "$($raw.global.hold_ms) ms"
            $controls.ChkAmmoDrop.IsChecked = [bool]$raw.global.ammo_drop_shot
            $controls.ChkLedLifeBar.IsChecked = ($raw.global.led_mode -eq "life_bar")
            $controls.ChkTraceLog.IsChecked = [bool]$raw.global.trace_enabled
        }

        $script:gameProfileList.Clear()
        if ($raw.games) {
            $propNames = $raw.games.psobject.Properties.Name
            foreach ($gn in $propNames) {
                $gObj = $raw.games.$gn
                $p = [HotwmGameProfile]::new()
                $p.Name = $gn
                $p.Rumble = [bool]$gObj.rumble
                $p.Leds = [bool]$gObj.leds
                $script:gameProfileList.Add($p)
            }
        }
        $controls.GridGameProfiles.ItemsSource = $script:gameProfileList
    } catch {
        Write-Warning "Failed to load config: $_"
    }
}

function Build-HotwmConfigUpdates {
    param([System.Collections.IDictionary]$GlobalChanges, [object[]]$GameChanges)
    $games = [ordered]@{}
    foreach ($change in $GameChanges) {
        $games[$change.Name] = [ordered]@{
            rumble = [bool]$change.Rumble
            leds = [bool]$change.Leds
        }
    }
    return [ordered]@{ global = $GlobalChanges; games = $games }
}

function Save-HotwmConfig {
    try {
        if (-not (Test-Path -LiteralPath $script:configPath -PathType Leaf)) { throw "Configuration file not found: $script:configPath" }
        $globalChanges = [ordered]@{
            hold_ms = [int]$controls.SliderHoldMs.Value
            ammo_drop_shot = [bool]$controls.ChkAmmoDrop.IsChecked
            led_mode = if ($controls.ChkLedLifeBar.IsChecked) { 'life_bar' } else { 'none' }
            trace_enabled = [bool]$controls.ChkTraceLog.IsChecked
        }
        $updates = Build-HotwmConfigUpdates -GlobalChanges $globalChanges -GameChanges @($script:gameProfileList)
        $action = Update-HotwmJsonFileAction -Path $script:configPath -Updates $updates -Explanation 'Update hotwm recoil and game profile settings while preserving other configuration fields.'
        $result = Invoke-HotwmFileAction -Action $action -Confirm {
            param($proposal)
            $gamePreview = ($script:gameProfileList | ForEach-Object { "$($_.Name): rumble=$($_.Rumble), LEDs=$($_.Leds)" }) -join "`n"
            $preview = "hold_ms: $($updates.global.hold_ms)`nammo_drop_shot: $($updates.global.ammo_drop_shot)`nled_mode: $($updates.global.led_mode)`ntrace_enabled: $($updates.global.trace_enabled)`ngames:`n$gamePreview"
            $message = "Save these settings to:`n$($proposal.TargetPath)`n`n$preview`n`nOther existing fields are retained. A backup is created before writing.`n`nProceed?"
            [System.Windows.MessageBox]::Show($message, 'Confirm configuration save', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes
        }
        if (-not $result.Success) {
            $controls.TextConfigSaveStatus.Text = 'Save cancelled; no changes made.'
            $controls.TextConfigSaveStatus.Foreground = $brushYellow
            return
        }
        $controls.TextConfigSaveStatus.Text = "Saved with backup. Changes hot-reload in < 1s."
        $controls.TextConfigSaveStatus.Foreground = $brushGreen

        # Reset message after 3 seconds
        $clearTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $clearTimer.Interval = [TimeSpan]::FromSeconds(3)
        $clearTimer.Add_Tick({
            $controls.TextConfigSaveStatus.Text = ""
            $clearTimer.Stop()
        })
        $clearTimer.Start()
    } catch {
        $controls.TextConfigSaveStatus.Text = "Save failed; configuration unchanged where possible: $_"
        $controls.TextConfigSaveStatus.Foreground = $brushRed
    }
}

function Confirm-HotwmOperation {
    param([string]$Title, [string]$Effect)
    return ([System.Windows.MessageBox]::Show($Effect, $Title, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -eq [System.Windows.MessageBoxResult]::Yes)
}

function Invoke-HotwmKitStatusQuery {
    param([string]$Root, [scriptblock]$Query)
    if ($Query) { return (& $Query $Root) }
    return Get-HotwmSystemStatus -RetroBatRoot $Root
}

$validateFolderAction = {
    $setupState.RetroBatRoot = $null
    $setupState.Root = $null
    $candidate = [string]$controls.TextSetupFolder.Text
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
        $controls.TextSetupFolderStatus.Text = 'Folder not found. Choose an existing RetroBat installation folder.'
        $controls.TextSetupFolderStatus.Foreground = $brushRed
        return $false
    }
    try {
        $candidate = [System.IO.Path]::GetFullPath($candidate)
        $entries = @(Get-ChildItem -LiteralPath $candidate -Force -ErrorAction Stop | Select-Object -ExpandProperty Name)
        $markers = @('retrobat.exe', 'retrobat.ini', 'system', 'roms', 'bios')
        $foundMarkers = @($markers | Where-Object { $entries -contains $_ -or $entries -contains $_.ToUpperInvariant() })
        if ($foundMarkers.Count -eq 0) {
            $controls.TextSetupFolderStatus.Text = "Folder is accessible, but its layout is not recognized as a RetroBat installation: $candidate"
            $controls.TextSetupFolderStatus.Foreground = $brushYellow
            $setupState.Root = $candidate
            return $true
        }
        $controls.TextSetupFolder.Text = $candidate
        $setupState.Root = $candidate
        $setupState.RetroBatRoot = $candidate
        $controls.TextSetupFolderStatus.Text = "RetroBat folder candidate found (markers: $($foundMarkers -join ', ')). Inspection is read-only; this does not confirm Hotwm readiness."
        $controls.TextSetupFolderStatus.Foreground = $brushGreen
        return $true
    } catch {
        $controls.TextSetupFolderStatus.Text = "Folder could not be inspected: $($_.Exception.Message)"
        $controls.TextSetupFolderStatus.Foreground = $brushRed
        return $false
    }
}.GetNewClosure()
function Update-HotwmDiscoveryView {
    $controls.ListDiscoveredDevices.Items.Clear()
    if (-not (Get-Command Get-HotwmDeviceDiscovery -ErrorAction SilentlyContinue)) {
        $controls.TextDiscoveryStatus.Text = 'Discovery module unavailable; PnP presence alone cannot confirm a playable Wiimote.'
        $controls.ListDiscoveredDevices.Items.Add('No device identity or player mapping was confirmed.') | Out-Null
        return
    }
    try {
        $discovery = Get-HotwmDeviceDiscovery
        $devices = @($discovery.Devices)
        if ($devices.Count -eq 0) {
            $controls.TextDiscoveryStatus.Text = if ($discovery.Detected) { 'Candidates detected, but no stable device records were confirmed.' } else { 'No supported device records found.' }
            $controls.ListDiscoveredDevices.Items.Add([string]$discovery.Message) | Out-Null
            return
        }
        foreach ($device in $devices) {
            $macText = if ($device.Mac -and $device.IdentityConfirmed) { [string]$device.Mac } else { 'Bluetooth identity unconfirmed' }
            $playerText = if ($device.MappingConfirmed -and $device.Player) { [string]$device.Player } else { 'Player unassigned' }
            $calibration = if ($device.ManuallyCalibrated) { 'manual calibration recorded' } else { 'manual calibration needed' }
            $targetTest = if ($device.Tested) { 'target test recorded' } else { 'per-player target test needed' }
            $instanceText = if ($controls.RadioExpertMode.IsChecked) { " — instance: $($device.InstanceId)" } else { "" }
            $controls.ListDiscoveredDevices.Items.Add("Candidate: $($device.DisplayName) — $macText — $playerText — $calibration — $targetTest$instanceText") | Out-Null
        }
        $controls.TextDiscoveryStatus.Text = "Read-only discovery: $($devices.Count) record(s). Verify identity and mapping manually; this is not a playable status."
    } catch {
        $controls.TextDiscoveryStatus.Text = "Discovery failed: $($_.Exception.Message)"
        $controls.ListDiscoveredDevices.Items.Add('No discovery result is available; retry after checking Windows device access.') | Out-Null
    }
}

$controls.TextSetupFolder.Text = ''
$controls.BtnBrowseSetupFolder.Add_Click({
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the hotwm setup folder'
        if (Test-Path -LiteralPath $controls.TextSetupFolder.Text -PathType Container) { $dialog.SelectedPath = $controls.TextSetupFolder.Text }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $controls.TextSetupFolder.Text = $dialog.SelectedPath }
    } catch {
        $controls.TextSetupFolderStatus.Text = "Folder picker unavailable: $($_.Exception.Message)"
        $controls.TextSetupFolderStatus.Foreground = $brushRed
    }
})
$validateFolderClick = { [void](& $validateFolderAction) }.GetNewClosure()
$controls.BtnValidateSetupFolder.Add_Click($validateFolderClick)

$controls.BtnRefreshDiscovery.Add_Click({ Update-HotwmDiscoveryView })
$kitStatusQuery = { param([scriptblock]$Query) if ($Query) { & $Query $setupState.RetroBatRoot } else { Get-HotwmSystemStatus -RetroBatRoot $setupState.RetroBatRoot } }.GetNewClosure()
$modeChanged = {
    $controls.TextQuickModeDetail.Visibility = if ($controls.RadioQuickMode.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $controls.TextCustomModeDetail.Visibility = if ($controls.RadioCustomMode.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $controls.TextExpertModeDetail.Visibility = if ($controls.RadioExpertMode.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    if ($controls.RadioExpertMode.IsChecked) { $controls.TextExpertModeDetail.Text = "Expert details — target: $($controls.TextSetupFolder.Text)`nRaw device instance IDs are shown in discovery rows while Expert is selected. Device presence alone never sets playable status." }
}
$modeChanged = $modeChanged.GetNewClosure()
$controls.RadioQuickMode.Add_Checked($modeChanged)
$controls.RadioCustomMode.Add_Checked($modeChanged)
$controls.RadioExpertMode.Add_Checked($modeChanged)
& $modeChanged
# 6. Event Wiring
# Slider change
$controls.SliderHoldMs.Add_ValueChanged({
    $val = [int]$controls.SliderHoldMs.Value
    $controls.TextHoldMsValue.Text = "$val ms"
}.GetNewClosure())

# Save Button
$controls.BtnSaveConfig.Add_Click({
    Save-HotwmConfig
})

# Refresh Status Button
$controls.BtnRefreshStatus.Add_Click({
    Update-DashboardStatus
})

# Header Start Relay
$controls.BtnHeaderStartRelay.Add_Click({
    $startScript = Join-Path $toolsDir "Start-HotwmRelay.ps1"
    if ((Test-Path $startScript) -and (Confirm-HotwmOperation -Title 'Start hotwm relay' -Effect "Start the hotwm Python relay as a background process using:`n$startScript`n`nThe relay will listen locally for recoil and test commands.")) {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$startScript`" -Background" -WindowStyle Hidden
        Start-Sleep -Milliseconds 600
        Update-DashboardStatus
    }
})

# Header Stop Relay
$controls.BtnHeaderStopRelay.Add_Click({
    $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'python%.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*hotwm_relay.py*" }
    if (-not $procs) { return }
    $pidList = ($procs | ForEach-Object { $_.ProcessId }) -join ', '
    if (-not (Confirm-HotwmOperation -Title 'Stop hotwm relay' -Effect "Force-stop the hotwm_relay.py process(es) with PID(s): $pidList`n`nActive recoil handling will stop.")) { return }
    foreach ($p in $procs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400
    Update-DashboardStatus
})

# Task Install / Uninstall
$controls.BtnInstallTask.Add_Click({
    $installScript = Join-Path $toolsDir "Install-HotwmTask.ps1"
    if ((Test-Path $installScript) -and (Confirm-HotwmOperation -Title 'Install Windows task' -Effect "Run the task installer:`n$installScript`n`nThis registers or updates the Gunmote Recoil Stretch scheduled task.")) {
        & $installScript
        Update-DashboardStatus
    }
})

$controls.BtnUninstallTask.Add_Click({
    $uninstallScript = Join-Path $toolsDir "Uninstall-HotwmTask.ps1"
    if ((Test-Path $uninstallScript) -and (Confirm-HotwmOperation -Title 'Remove Windows task' -Effect "Run the task removal script:`n$uninstallScript`n`nThis unregisters the Gunmote Recoil Stretch scheduled task.")) {
        & $uninstallScript
        Update-DashboardStatus
    }
})

# Query Kit
$controls.BtnQueryKit.Add_Click({
    if (Get-Command Get-HotwmSystemStatus -ErrorAction SilentlyContinue) {
        $res = & $kitStatusQuery
        if ($res.Success) {
            [System.Windows.MessageBox]::Show("Kit reports status:`n$($res.Data | ConvertTo-Json -Depth 3)", "Retro Cabinet Kit Status", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } else {
            [System.Windows.MessageBox]::Show("Kit query returned:`n$($res.Message)", "Retro Cabinet Kit Status", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    } else {
        [System.Windows.MessageBox]::Show("Kit client not loaded or Kit not available.", "Retro Cabinet Kit", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Query Cabinet Input Matrix (Kit v1.3 / API 1.5)
if ($controls.BtnQueryInputMatrix) {
    $controls.BtnQueryInputMatrix.Add_Click({
        if (Get-Command Get-HotwmInputProfiles -ErrorAction SilentlyContinue) {
            $res = Get-HotwmInputProfiles
            if ($res.Success -and $res.Data.Profiles) {
                $pList = ($res.Data.Profiles | ForEach-Object { "• $($_.Name): $($_.Description) ($($_.Intents) intents)" }) -join "`n`n"
                [System.Windows.MessageBox]::Show("Fried's Retrogaming Kit v$(Get-HotwmKitVersion) Input Matrix Profiles:`n`n$pList`n`nProfil 'ipac2-default' stammt aus der I-PAC 2 Werksbelegung (Keyboard + Trackball/Maus).`nGunmote-Wiimotes melden sich als XInput-Gamepad (MAME sieht JOYCODE, z.B. P1_BUTTON1 = KEY_LCONTROL + JOY1_BUTTON2).", "Cabinet Input Matrix (API 1.5)", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } else {
                [System.Windows.MessageBox]::Show("No input profiles found or Kit API returned: $($res.Message)", "Cabinet Input Matrix", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        } else {
            [System.Windows.MessageBox]::Show("Kit client or operation controllers.input_profiles not available.", "Cabinet Input Matrix", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    })
}

# Query Output Safety Check (Kit outputs.verify_safety)
if ($controls.BtnVerifyOutputSafety) {
    $controls.BtnVerifyOutputSafety.Add_Click({
        if (Get-Command Get-HotwmOutputSafety -ErrorAction SilentlyContinue) {
            $res = Get-HotwmOutputSafety
            if ($res.Success -and $res.Data) {
                $d = $res.Data
                $dcText = if ($d.DoubleConsumers -and $d.DoubleConsumers.Count -gt 0) {
                    ($d.DoubleConsumers | ForEach-Object { "⚠ $($_.Detail)" }) -join "`n"
                } else { "✓ No double consumers detected (no double-rumble risk)" }

                $solText = if ($d.SolenoidGuard.Ok) { "✓ Solenoid Guard active" } else { "⚠ Solenoid Guard issue: $($d.SolenoidGuard.Detail)" }
                $gmText = "✓ Gunmote INIs found: $($d.GunmoteConfig.InisFound) (Connected: $($d.GunmoteConfig.Connected))"
                $midText = "Detected Middlewares: $(($d.DetectedOutputs) -join ', ')"

                $warnText = if ($res.Warnings -and $res.Warnings.Count -gt 0) {
                    "`n`nWarnings:`n" + (($res.Warnings | ForEach-Object { "- $_" }) -join "`n")
                } else { "" }

                [System.Windows.MessageBox]::Show("Retro Cabinet Kit Output Safety Verification:`n`n$solText`n$gmText`n$midText`n`nDouble Consumer Status:`n$dcText$warnText", "Cabinet Output Safety Check", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } else {
                [System.Windows.MessageBox]::Show("Output safety check returned:`n$($res.Message)", "Output Safety Check", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        } else {
            [System.Windows.MessageBox]::Show("Kit client or operation outputs.verify_safety not available.", "Output Safety Check", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    })
}

# Haptic Tests
$controls.BtnTestP1Rumble.Add_Click({
    $controls.TextTestFeedback.Text = "Sending P1 Rumble Kick..."
    $res = Send-HotwmSocketCommand -Command "CMD_TEST_P1_RUMBLE"
    if ($res.Success) {
        $controls.TextTestFeedback.Text = 'P1 recoil command sent to relay; hardware effect unconfirmed.'
        $controls.TextTestFeedback.Foreground = $brushGreen
    } else {
        $controls.TextTestFeedback.Text = "Failed: $($res.Response)"
        $controls.TextTestFeedback.Foreground = $brushRed
    }
})

$controls.BtnTestP2Rumble.Add_Click({
    $controls.TextTestFeedback.Text = "Sending P2 Rumble Kick..."
    $res = Send-HotwmSocketCommand -Command "CMD_TEST_P2_RUMBLE"
    if ($res.Success) {
        $controls.TextTestFeedback.Text = 'P2 recoil command sent to relay; hardware effect unconfirmed.'
        $controls.TextTestFeedback.Foreground = $brushGreen
    } else {
        $controls.TextTestFeedback.Text = "Failed: $($res.Response)"
        $controls.TextTestFeedback.Foreground = $brushRed
    }
})

$controls.BtnTestP1Leds.Add_Click({
    $controls.TextTestFeedback.Text = "Cycling P1 LEDs..."
    $res = Send-HotwmSocketCommand -Command "CMD_TEST_P1_LEDS"
    if ($res.Success) {
        $controls.TextTestFeedback.Text = 'P1 LED cycle command sent to relay; hardware effect unconfirmed.'
        $controls.TextTestFeedback.Foreground = $brushCyan
    } else {
        $controls.TextTestFeedback.Text = "Failed: $($res.Response)"
        $controls.TextTestFeedback.Foreground = $brushRed
    }
})

$controls.BtnTestP2Leds.Add_Click({
    $controls.TextTestFeedback.Text = "Cycling P2 LEDs..."
    $res = Send-HotwmSocketCommand -Command "CMD_TEST_P2_LEDS"
    if ($res.Success) {
        $controls.TextTestFeedback.Text = 'P2 LED cycle command sent to relay; hardware effect unconfirmed.'
        $controls.TextTestFeedback.Foreground = $brushCyan
    } else {
        $controls.TextTestFeedback.Text = "Failed: $($res.Response)"
        $controls.TextTestFeedback.Foreground = $brushRed
    }
})

$controls.BtnPingRelay.Add_Click({
    $controls.TextTestFeedback.Text = "Pinging relay..."
    $res = Send-HotwmSocketCommand -Command "PING"
    if ($res.Success) {
        $controls.TextTestFeedback.Text = "PONG received in $($res.LatencyMs) ms!"
        $controls.TextTestFeedback.Foreground = $brushGreen
    } else {
        $controls.TextTestFeedback.Text = "Relay not responding: $($res.Response)"
        $controls.TextTestFeedback.Foreground = $brushRed
    }
})

# Log Controls
# Same file the relay writes (hotwm_relay.py TRACE_LOG: the repo folder above src\)
$traceLogPath = Join-Path $repoDir "recoil-stretch-trace.log"
$controls.BtnClearLog.Add_Click({
    if (-not (Confirm-HotwmOperation -Title 'Clear hotwm trace log' -Effect "Delete all contents of:`n$traceLogPath`n`nThis cannot be undone.")) { return }
    $controls.TextLogOutput.Text = ""
    if (Test-Path $traceLogPath) {
        try { [System.IO.File]::WriteAllText($traceLogPath, "") } catch {}
    }
})

$controls.BtnOpenLogFile.Add_Click({
    if (Test-Path $traceLogPath) {
        Start-Process notepad.exe -ArgumentList "`"$traceLogPath`""
    } else {
        [System.Windows.MessageBox]::Show("Log file does not exist yet at:`n$traceLogPath`n`nEnable 'Trace Logging' in tuning tab and run games to generate logs.", "hotwm Log", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# 7. Background Timers for Status and Log Tailing
$script:logLastOffset = 0
$logTimer = [System.Windows.Threading.DispatcherTimer]::new()
$logTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$logTimer.Add_Tick({
    if (Test-Path $traceLogPath) {
        try {
            $fi = [System.IO.FileInfo]::new($traceLogPath)
            if ($fi.Length -gt $script:logLastOffset) {
                $fs = [System.IO.FileStream]::new($traceLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($script:logLastOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                $newContent = $sr.ReadToEnd()
                $script:logLastOffset = $fs.Position
                $sr.Close()
                $fs.Close()

                if ($newContent) {
                    $controls.TextLogOutput.AppendText($newContent)
                    if ($controls.ChkAutoScroll.IsChecked) {
                        $controls.TextLogOutput.ScrollToEnd()
                    }
                }
            } elseif ($fi.Length -lt $script:logLastOffset) {
                # Log was truncated/cleared
                $script:logLastOffset = 0
            }
        } catch {}
    }
})

$statusTimer = [System.Windows.Threading.DispatcherTimer]::new()
$statusTimer.Interval = [TimeSpan]::FromSeconds(4)
$statusTimer.Add_Tick({
    Update-DashboardStatus
})

# Initialize UI
Load-HotwmConfig
Update-DashboardStatus

# Window closed event: stop timers
$window.Add_Closed({
    $statusTimer.Stop()
    $logTimer.Stop()
}.GetNewClosure())

$result = [pscustomobject]@{
    Window   = $window
    Controls = $controls
    Config   = $script:configPath
    TraceLog = $traceLogPath
    ConfigMerge = ${function:Build-HotwmConfigUpdates}
    ValidateFolder = $validateFolderAction
    KitStatus = $kitStatusQuery
}

if ($NoShow) {
    return $result
}

$logTimer.Start()
$statusTimer.Start()
$window.ShowDialog() | Out-Null
return $result
