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
$wizardState = [pscustomobject]@{ Session = $null; Root = $null; LastImport = $null; Render = $null; Checklist = $null; SelectedDeviceKey = $null; SuppressModeChange = $false; Dispatch = $null }
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
$wizardScript = Join-Path $srcDir 'HotwmWizard.ps1'
$profileScript = Join-Path $srcDir 'HotwmProfiles.ps1'
if (Test-Path $profileScript) { . $profileScript }
$gunmoteScript = Join-Path $srcDir 'HotwmGunmote.ps1'

if (-not (Test-Path $xamlPath)) {
    throw "XAML file not found at: $xamlPath"
}

# 1. Load and parse XAML
$xaml = [System.IO.File]::ReadAllText($xamlPath)
$parserContext = [System.Windows.Markup.ParserContext]::new()
$parserContext.BaseUri = [Uri]::new([System.IO.Path]::GetFullPath($xamlPath))
$xamlStream = [System.IO.File]::OpenRead($xamlPath)
try { $window = [System.Windows.Markup.XamlReader]::Load($xamlStream, $parserContext) }
finally { $xamlStream.Dispose() }

# 2. Map named controls
$controls = @{}
foreach ($m in [regex]::Matches($xaml, 'x:Name="([A-Za-z0-9_]+)"')) {
    $name = $m.Groups[1].Value
    $element = $window.FindName($name)
    if ($element) { $controls[$name] = $element }
}
$presetHelpBinding = [System.Windows.Data.Binding]::new('SelectedItem.Description')
$presetHelpBinding.ElementName = 'CmbGunmoteKind'
$presetHelpBinding.TargetNullValue = 'Wähle eine Vorlage; ihre Originaldatei bleibt unverändert.'
$controls.TextGunmoteKindHelp.SetBinding([System.Windows.Controls.TextBlock]::TextProperty, $presetHelpBinding) | Out-Null

# hotwm's own version: the VERSION file is the one source (the package builder reads it too)
$controls.TextVersion.Text = 'v' + $(try { ([IO.File]::ReadAllText((Join-Path $repoDir 'VERSION'))).Trim() } catch { '?' })

# Helper: Brushes
$brushGreen  = $window.FindResource('StatusSuccessBrush')
$brushRed    = $window.FindResource('StatusDangerBrush')
$brushYellow = $window.FindResource('StatusWarningBrush')
$brushGray   = $window.FindResource('MutedTextBrush')
$brushCyan   = $window.FindResource('AccentBrush')

function Set-HotwmMascotImage {
    param([System.Windows.Controls.Image]$Image, [string]$FileName)
    $imagePath = Join-Path (Join-Path $guiDir 'assets\brand') $FileName
    if (-not $Image -or -not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { return $false }
    try {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [Uri]::new((Get-Item -LiteralPath $imagePath).FullName)
        $bitmap.EndInit()
        $bitmap.Freeze()
        $Image.Source = $bitmap
        return $true
    } catch { return $false }
}

$null = Set-HotwmMascotImage -Image $controls.BrandFriendlyMascot -FileName 'character-friendly.png'
$null = Set-HotwmMascotImage -Image $controls.BrandControllerMascot -FileName 'character-controller.png'
$null = Set-HotwmMascotImage -Image $controls.BrandSurprisedMascot -FileName 'character-surprised.png'
$null = Set-HotwmMascotImage -Image $controls.BrandCelebrateMascot -FileName 'character-celebrate.png'

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
        return @{ Connected = $true; Message = "Windows-Gerät erkannt: $names. Spielerzuordnung und Spielfunktion sind noch offen." }
    }
    return @{ Connected = $false; Message = "Kein passendes Wiimote- oder DolphinBar-Gerät in Windows gefunden." }
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
        $controls.RelayHeaderStatus.Text = "Rückstoßdienst aktiv"
        $controls.RelayHeaderStatus.Foreground = $brushGreen
        $controls.DotRelay.Fill = $brushGreen
        $controls.TextRelayBadge.Text = "AKTIV"
        $controls.TextRelayBadge.Foreground = $brushGreen
        $controls.TextRelayDetail.Text = $r.Message
    } else {
        $controls.RelayHeaderDot.Fill = $brushRed
        $controls.RelayHeaderStatus.Text = "Rückstoßdienst inaktiv"
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
        $controls.TextGunmoteBadge.Text = "LÄUFT"
        $controls.TextGunmoteBadge.Foreground = $brushGreen
        $controls.TextGunmoteDetail.Text = $gm.Message
    } else {
        $controls.DotGunmote.Fill = $brushGray
        $controls.TextGunmoteBadge.Text = "INAKTIV"
        $controls.TextGunmoteBadge.Foreground = $brushGray
        $controls.TextGunmoteDetail.Text = $gm.Message
    }

    # ViGEmBus
    $vg = Get-ViGEmBusStatus
    if ($vg.Running) {
        $controls.DotVigem.Fill = $brushGreen
        $controls.TextVigemBadge.Text = "VORHANDEN"
        $controls.TextVigemBadge.Foreground = $brushGreen
        $controls.TextVigemDetail.Text = $vg.Message
    } else {
        $controls.DotVigem.Fill = $brushYellow
        $controls.TextVigemBadge.Text = "FEHLT"
        $controls.TextVigemBadge.Foreground = $brushYellow
        $controls.TextVigemDetail.Text = $vg.Message
    }

    # Wiimote / DolphinBar
    $wm = Get-WiimoteDevicesStatus
    if ($wm.Connected) {
        $controls.DotWiimote.Fill = $brushGreen
        $controls.TextWiimoteBadge.Text = "ERKANNT"
        $controls.TextWiimoteBadge.Foreground = $brushGreen
        $controls.TextWiimoteDetail.Text = $wm.Message
    } else {
        $controls.DotWiimote.Fill = $brushYellow
        $controls.TextWiimoteBadge.Text = "NICHT GEFUNDEN"
        $controls.TextWiimoteBadge.Foreground = $brushYellow
        $controls.TextWiimoteDetail.Text = $wm.Message
    }

    # Task Autostart
    $ts = Get-HotwmTaskStatus
    if ($ts.Installed) {
        $controls.DotTask.Fill = $brushGreen
        $controls.TextTaskBadge.Text = "EINGERICHTET"
        $controls.TextTaskBadge.Foreground = $brushGreen
        $controls.TextTaskDetail.Text = "Scheduled task: $($ts.State)"
    } else {
        $controls.DotTask.Fill = $brushGray
        $controls.TextTaskBadge.Text = "NICHT EINGERICHTET"
        $controls.TextTaskBadge.Foreground = $brushGray
        $controls.TextTaskDetail.Text = "Not registered in Task Scheduler"
    }

    # Kit Integration
    if (Get-Command Test-HotwmKitAvailable -ErrorAction SilentlyContinue) {
        $kitAvail = Test-HotwmKitAvailable
        if ($kitAvail) {
            $kitVersion = Get-HotwmKitVersion
            $controls.DotKit.Fill = $brushGreen
            $controls.TextKitBadge.Text = "API GEFUNDEN"
            $controls.TextKitBadge.Foreground = $brushGreen
            $controls.TextKitDetail.Text = "Kit v$($kitVersion): API-Einstiegspunkt gefunden; keine erfolgreiche Verbindung bestätigt."
        } else {
            $controls.DotKit.Fill = $brushGray
            $controls.TextKitBadge.Text = "OHNE KIT"
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
        $controls.TextSetupFolderStatus.Text = 'Ordner nicht gefunden. Wähle einen vorhandenen Emulator-Ordner.'
        $controls.TextSetupFolderStatus.Foreground = $brushRed
        $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Visible
        $controls.BrandCelebrateMascot.Visibility = [System.Windows.Visibility]::Collapsed
        return $false
    }
    try {
        $candidate = [System.IO.Path]::GetFullPath($candidate)
        $entries = @(Get-ChildItem -LiteralPath $candidate -Force -ErrorAction Stop | Select-Object -ExpandProperty Name)
        $markers = @('retrobat.exe', 'retrobat.ini', 'system', 'roms', 'bios')
        $foundMarkers = @($markers | Where-Object { $entries -contains $_ -or $entries -contains $_.ToUpperInvariant() })
        if ($foundMarkers.Count -eq 0) {
            $controls.TextSetupFolderStatus.Text = "Ordner ist lesbar, wurde aber nicht als RetroBat-Installation erkannt: $candidate"
            $controls.TextSetupFolderStatus.Foreground = $brushYellow
            $setupState.Root = $candidate
            if ($wizardState -and $wizardState.Session -and -not [string]::Equals([string]$wizardState.Session.Root, $candidate, [StringComparison]::OrdinalIgnoreCase)) {
                $wizardState.Session = $null
                $controls.TextWizardStatus.Text = 'Ordner geändert. Die vorige Sitzung wurde verworfen; starte eine neue Sitzung für diesen Ordner.'
            }
            if ($controls.RadioQuickMode.IsChecked -and -not $wizardState.Session -and $wizardState.Dispatch) {
                $null = & $wizardState.Dispatch 'Start' @{ Root=$candidate; Mode='Quick' }
            }
            $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Collapsed
            return $true
        }
        $controls.TextSetupFolder.Text = $candidate
        $setupState.Root = $candidate
        $setupState.RetroBatRoot = $candidate
        if ($wizardState -and $wizardState.Session -and -not [string]::Equals([string]$wizardState.Session.Root, $candidate, [StringComparison]::OrdinalIgnoreCase)) {
            $wizardState.Session = $null
            $controls.TextWizardStatus.Text = 'Ordner geändert. Die vorige Sitzung wurde verworfen; starte eine neue Sitzung für diesen Ordner.'
        }
        $controls.TextSetupFolderStatus.Text = "RetroBat-Ordner erkannt (Merkmale: $($foundMarkers -join ', ')). Die Prüfung ist nur lesend und bestätigt keine Einsatzbereitschaft."
        $controls.TextSetupFolderStatus.Foreground = $brushGreen
        if ($controls.RadioQuickMode.IsChecked -and -not $wizardState.Session -and $wizardState.Dispatch) {
            $null = & $wizardState.Dispatch 'Start' @{ Root=$candidate; Mode='Quick' }
        }
        $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Collapsed
        return $true
    } catch {
        $controls.TextSetupFolderStatus.Text = "Ordner konnte nicht geprüft werden: $($_.Exception.Message)"
        $controls.TextSetupFolderStatus.Foreground = $brushRed
        $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Visible
        $controls.BrandCelebrateMascot.Visibility = [System.Windows.Visibility]::Collapsed
        return $false
    }
}.GetNewClosure()
function Update-HotwmDiscoveryView {
    $controls.ListDiscoveredDevices.Items.Clear()
    if (-not (Get-Command Get-HotwmDeviceDiscovery -ErrorAction SilentlyContinue)) {
        $controls.TextDiscoveryStatus.Text = 'Geräteerkennung nicht verfügbar. Ein Windows-Eintrag bestätigt keine Spielfunktion.'
        $controls.ListDiscoveredDevices.Items.Add('Geräteidentität und Spielerzuordnung sind nicht bestätigt.') | Out-Null
        return
    }
    try {
        $discovery = Get-HotwmDeviceDiscovery
        $devices = @($discovery.Devices)
        if ($devices.Count -eq 0) {
            $controls.TextDiscoveryStatus.Text = if ($discovery.Detected) { 'Gerätehinweis gefunden, aber keine stabile Gerätekennung bestätigt.' } else { 'Keine unterstützten Geräte gefunden.' }
            $controls.ListDiscoveredDevices.Items.Add([string]$discovery.Message) | Out-Null
            return
        }
        foreach ($device in $devices) {
            $macText = if ($device.Mac -and $device.IdentityConfirmed) { [string]$device.Mac } else { 'Bluetooth-Identität offen' }
            $playerText = if ($device.MappingConfirmed -and $device.Player) { "Spieler $($device.Player) zugeordnet" } else { 'Spieler nicht zugeordnet' }
            $calibration = if ($device.ManuallyCalibrated) { 'manuelle Kalibrierung notiert' } else { 'Kalibrierung offen' }
            $targetTest = if ($device.Tested) { 'Zieltest notiert' } else { 'Zieltest offen' }
            $instanceText = if ($controls.RadioExpertMode.IsChecked) { " — Gerätekennung: $($device.InstanceId)" } else { "" }
            $controls.ListDiscoveredDevices.Items.Add("Gerät: $($device.DisplayName) — $macText — $playerText — $calibration — $targetTest$instanceText") | Out-Null
        }
        $controls.TextDiscoveryStatus.Text = "Nur lesende Erkennung: $($devices.Count) Gerät(e). Identität und Zuordnung müssen manuell geprüft werden; Spielfunktion ist nicht bestätigt."
    } catch {
        $controls.TextDiscoveryStatus.Text = "Geräteerkennung fehlgeschlagen: $($_.Exception.Message)"
        $controls.ListDiscoveredDevices.Items.Add('Prüfe den Windows-Gerätezugriff und versuche es erneut.') | Out-Null
    }
}

$controls.TextSetupFolder.Text = ''
$controls.CmbWizardPlayer.SelectedIndex = 0
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
    $relayActionVisibility = if ($controls.RadioQuickMode.IsChecked) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $controls.BtnHeaderStartRelay.Visibility = $relayActionVisibility
    $controls.BtnHeaderStopRelay.Visibility = $relayActionVisibility
    $hasGunmotePreview = -not [string]::IsNullOrWhiteSpace([string]$controls.TextGunmotePreview.Text)
    $controls.TextGunmotePreview.Visibility = if ($controls.RadioExpertMode.IsChecked -and $hasGunmotePreview) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    if ($controls.RadioExpertMode.IsChecked) { $controls.TextExpertModeDetail.Text = "Zielordner: $($controls.TextSetupFolder.Text)`nRohe Gerätekennungen und Prüfnachweise werden eingeblendet. Geräteerkennung allein bestätigt keine Spielfunktion." }
}
$modeChanged = $modeChanged.GetNewClosure()
$controls.RadioQuickMode.Add_Checked($modeChanged)
$controls.RadioCustomMode.Add_Checked($modeChanged)
$controls.RadioExpertMode.Add_Checked($modeChanged)
& $modeChanged
$wizardDispatcher = {
    param([string]$Operation, [object]$Argument)
    try {
        if (-not (Test-Path -LiteralPath $wizardScript -PathType Leaf)) { throw 'Guided setup module is unavailable.' }
        $savedSessions = $script:HotwmWizardSessions
        . $wizardScript
        if ($savedSessions) { $script:HotwmWizardSessions = $savedSessions }
        $controls.TextWizardStatus.Foreground = $brushGray
        $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Collapsed
        switch ($Operation) {
            'Start' {
                $root = if ($Argument -and $Argument.Root) { [string]$Argument.Root } else { [string]$setupState.Root }
                if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Validate an existing setup folder first.' }
                if (-not ($Argument -and $Argument.Root) -and -not [string]::Equals([System.IO.Path]::GetFullPath($root).TrimEnd('\','/'), [System.IO.Path]::GetFullPath([string]$controls.TextSetupFolder.Text).TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The folder field changed after validation. Validate it again before starting a session.' }
                $mode = if ($Argument -and $Argument.Mode) { [string]$Argument.Mode } elseif ($controls.RadioExpertMode.IsChecked) { 'Expert' } elseif ($controls.RadioCustomMode.IsChecked) { 'Custom' } else { 'Quick' }
                $params = @{ Root=$root; Mode=$mode; ConfigPath=$script:configPath; Mappings=@() }
                if ($Argument -and $Argument.Contains('DeviceRecords')) { $params.DeviceRecords = @($Argument.DeviceRecords) }
                if ($Argument -and $Argument.Contains('DependencyRecords')) { $params.DependencyRecords = @($Argument.DependencyRecords) }
                if ($Argument -and $Argument.SavedState) { $params.SavedState = $Argument.SavedState }
                $hadSession = [bool]$wizardState.Session
                $wizardState.Session = New-HotwmSetupSession @params
                $wizardState.Root = $wizardState.Session.Root
                $controls.TextWizardStatus.Text = if ($hadSession) { 'Neue Sitzung gestartet. Frühere Prüfungen gelten nicht weiter; wiederhole die manuellen Prüfungen.' } else { 'Sitzung gestartet. Die Erkennung ist nur lesend; Prüfungen erfordern deine eigene Beobachtung.' }
            }
            'Mode' {
                if ($wizardState.Session) { $wizardState.Session.Mode = if ($Argument -and $Argument.Mode) { [string]$Argument.Mode } elseif ($controls.RadioExpertMode.IsChecked) { 'Expert' } elseif ($controls.RadioCustomMode.IsChecked) { 'Custom' } else { 'Quick' } }
                if ($wizardState.Session) { $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session }
                return [pscustomobject]@{ Success=$true; Session=$wizardState.Session; Mode=if ($wizardState.Session) { $wizardState.Session.Mode } elseif ($controls.RadioExpertMode.IsChecked) { 'Expert' } elseif ($controls.RadioCustomMode.IsChecked) { 'Custom' } else { 'Quick' } }
            }
            'Assign' {
                if (-not $wizardState.Session) { throw 'Start a setup session first.' }
                $key = if ($Argument -and $Argument.DeviceKey) { [string]$Argument.DeviceKey } else { [string]$controls.CmbWizardDevice.SelectedValue }
                $player = if ($Argument -and $Argument.Contains('Player')) { [int]$Argument.Player } else { [int]$controls.CmbWizardPlayer.SelectedItem.Tag }
                if ($player -notin @(1,2)) { throw 'Choose Desired Player 1 or 2.' }
                $device = Set-HotwmSessionPlayerAssignment -Session $wizardState.Session -DeviceKey $key -Player $player
                $controls.TextWizardStatus.Text = "Gewünschter Spieler $player zugewiesen. Der beobachtete Gunmote-Laufzeitplatz bleibt davon getrennt."
                $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session
                $null = & $wizardState.Render
                return [pscustomobject]@{ Success=$true; Device=$device; Session=$wizardState.Session }
            }
            { $_ -in @('RuntimeSlot','Calibration','Aim','Trigger') } {
                if (-not $wizardState.Session) { throw 'Start a setup session first.' }
                $check = if ($Operation -eq 'RuntimeSlot') { 'RuntimeSlot' } else { $Operation }
                $key = if ($Argument -and $Argument.DeviceKey) { [string]$Argument.DeviceKey } else { [string]$controls.CmbWizardDevice.SelectedValue }
                $selectedDevice = @($wizardState.Session.Devices | Where-Object DeviceKey -CEQ $key) | Select-Object -First 1
                $callback = if ($Argument -and $Argument.Confirm) { $Argument.Confirm } else {
                    $display = if ($selectedDevice) { [string]$selectedDevice.DisplayName } else { 'Controller' }
                    $playerText = if ($selectedDevice -and $selectedDevice.DesiredPlayer) { "Spieler $($selectedDevice.DesiredPlayer)" } else { 'nicht zugewiesen' }
                    $slot = if ($controls.CmbWizardRuntimeSlot.SelectedItem) { [int]$controls.CmbWizardRuntimeSlot.SelectedItem.Tag } else { 0 }
                    if ($check -eq 'RuntimeSlot' -and $slot -notin @(1,2)) { throw 'Wähle zuerst den beobachteten Gunmote-Platz 1 oder 2 aus.' }
                    $checkText = switch ($check) { 'RuntimeSlot' { "Hast du den physischen Controller erkannt und seinen Gunmote-Laufzeitplatz $slot beobachtet?" }; 'Calibration' { 'Hast du diesen Controller manuell kalibriert?' }; 'Aim' { 'Hast du die Zielbewegung dieses Controllers an einem Ziel geprüft?' }; 'Trigger' { 'Hast du den Abzug gedrückt und die Reaktion am Ziel geprüft?' } }
                    { param($prompt,$device) if (Confirm-HotwmOperation -Title 'Selbst durchgeführte Prüfung bestätigen' -Effect "$checkText`n`nGerät: $display`nGewünschter Spieler: $playerText`n`nDies speichert nur deine manuelle Bestätigung. Hotwm koppelt und kalibriert den Controller nicht automatisch.") { if ($check -eq 'RuntimeSlot') { return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=$slot } }; return $true }; return $false }.GetNewClosure()
                }
                $entry = Confirm-HotwmSetupObservation -Session $wizardState.Session -DeviceKey $key -Check $check -ConfirmationCallback $callback
                $controls.TextWizardStatus.Text = "Deine Bestätigung ($check) wurde für diese Verbindungssitzung erfasst. Sie wurde nicht unabhängig geprüft."
                $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session
                $null = & $wizardState.Render
                return [pscustomobject]@{ Success=$true; Confirmation=$entry; Session=$wizardState.Session }
            }
            'Refresh' {
                if (-not $wizardState.Session) { throw 'Start a setup session first.' }
                if ($Argument -and $Argument.Contains('DeviceRecords')) { $null = Refresh-HotwmSetupSession -Session $wizardState.Session -DeviceRecords @($Argument.DeviceRecords) }
                else { $null = Refresh-HotwmSetupSession -Session $wizardState.Session }
                $controls.TextWizardStatus.Text = 'Verbindung aktualisiert. Frühere Bestätigungen sind veraltet; wiederhole jede manuelle Prüfung.'
                $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session
                $null = & $wizardState.Render
                return [pscustomobject]@{ Success=$true; Session=$wizardState.Session }
            }
            'Import' {
                $root = if ($Argument -and $Argument.Root) { [string]$Argument.Root } else { [string]$setupState.Root }
                if (-not $root) { throw 'Validate a setup folder before importing history.' }
                $path = if ($Argument -and $Argument.Path) { [string]$Argument.Path } else { Join-Path $root '.hotwm-setup.json' }
                $saved = Import-HotwmSetupState -Path $path -Root $root
                $params = @{ Root=$root; Mode=[string]$saved.Mode; ConfigPath=$script:configPath; SavedState=$saved; Mappings=@() }
                if ($Argument -and $Argument.Contains('DeviceRecords')) { $params.DeviceRecords = @($Argument.DeviceRecords) }
                if ($Argument -and $Argument.Contains('DependencyRecords')) { $params.DependencyRecords = @($Argument.DependencyRecords) }
                $wizardState.SuppressModeChange = $true
                try {
                    $controls.RadioQuickMode.IsChecked = ([string]$saved.Mode -eq 'Quick')
                    $controls.RadioCustomMode.IsChecked = ([string]$saved.Mode -eq 'Custom')
                    $controls.RadioExpertMode.IsChecked = ([string]$saved.Mode -eq 'Expert')
                    $wizardState.Session = New-HotwmSetupSession @params
                } finally { $wizardState.SuppressModeChange = $false }
                $wizardState.Root = $wizardState.Session.Root
                $wizardState.LastImport = $saved
                $controls.TextWizardStatus.Text = 'Spielerzuordnungen und frühere Hinweise importiert. Alte Prüfungen gelten nicht; wiederhole sie in dieser Sitzung.'
                $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session
                $null = & $wizardState.Render
                return [pscustomobject]@{ Success=$true; Imported=$saved; Session=$wizardState.Session }
            }
            'Save' {
                if (-not $wizardState.Session) { throw 'Start a setup session first.' }
                $visibleRoot = [string]$controls.TextSetupFolder.Text
                if (-not $visibleRoot -or -not [string]::Equals([System.IO.Path]::GetFullPath($visibleRoot).TrimEnd('\','/'), [System.IO.Path]::GetFullPath([string]$wizardState.Session.Root).TrimEnd('\','/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'The selected folder changed after this session began. Validate the folder and start a new session before saving.' }
                $path = if ($Argument -and $Argument.Path) { [string]$Argument.Path } else { Join-Path $wizardState.Session.Root '.hotwm-setup.json' }
                $action = New-HotwmSetupSessionAction -Session $wizardState.Session -Path $path
                $mappingText = if ($wizardState.Session.Mappings.Count) { ($wizardState.Session.Mappings | ForEach-Object { "$($_.Mac) → gewünschter Spieler $($_.Player)" }) -join "`n" } else { 'Keine dauerhafte MAC-Zuordnung; sitzungsgebundene Zuordnungen werden nicht gespeichert.' }
                $proposedState = ConvertFrom-Json -InputObject $action.ProposedContent
                $historyCount = @($proposedState.HistoricalConfirmations).Count
                $summary = "Gewünschte Spielerzuordnungen und $historyCount frühere Prüfnotiz(en) nach $($action.TargetPath) speichern? Frühere Prüfungen bestätigen keine aktuelle Einsatzbereitschaft."
                $confirm = if ($Argument -and $Argument.Confirm) { $Argument.Confirm } else {
                    $display = "$summary`n`n$mappingText"; $content = $action.ProposedContent; $target = $action.TargetPath
                    { param($proposal) Show-HotwmReviewedFileProposal -Title 'Setup-Verlauf prüfen' -TargetPath $target -Content $content -Effect $display }.GetNewClosure()
                }
                $result = Invoke-HotwmFileAction -Action $action -Confirm $confirm
                $controls.TextWizardStatus.Text = if ($result.Success) { 'Setup-Verlauf gespeichert. Aktuelle Prüfungen bleiben unbestätigte Nutzeraussagen.' } else { 'Speichern abgebrochen; die Verlaufsdatei wurde nicht geändert.' }
                return [pscustomobject]@{ Success=$result.Success; Action=$action; Result=$result; Session=$wizardState.Session }
            }
            'Render' { if ($wizardState.Session) { $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session }; return (& $wizardState.Render) }
            default { throw "Unknown setup wizard operation: $Operation" }
        }
        if ($wizardState.Session) { $wizardState.Checklist = Get-HotwmSetupChecklist -Session $wizardState.Session }
        $null = & $wizardState.Render
        return [pscustomobject]@{ Success=$true; Session=$wizardState.Session }
    } catch {
        $controls.TextWizardStatus.Text = "Einrichtung: $($_.Exception.Message)"
        $controls.TextWizardStatus.Foreground = $brushRed
        $controls.BrandSurprisedMascot.Visibility = [System.Windows.Visibility]::Visible
        $controls.BrandCelebrateMascot.Visibility = [System.Windows.Visibility]::Collapsed
        return [pscustomobject]@{ Success=$false; Message=$_.Exception.Message; Session=$wizardState.Session }
    }
}.GetNewClosure()
$wizardState.Dispatch = $wizardDispatcher
$renderWizard = {
    $session = $wizardState.Session
    $selectedDeviceKey = if ($wizardState.SelectedDeviceKey) { [string]$wizardState.SelectedDeviceKey } else { [string]$controls.CmbWizardDevice.SelectedValue }
    $controls.CmbWizardDevice.ItemsSource = $null
    $controls.ListWizardChecklist.Items.Clear()
    if (-not $session) { return $null }
    $devices = @($session.Devices | ForEach-Object {
        $desired = if ($_.DesiredPlayer) { "gewünschter Spieler $($_.DesiredPlayer)" } else { 'Spieler nicht zugewiesen' }
        $runtime = if ($_.RuntimeGunmoteSlot) { "Gunmote-Platz $($_.RuntimeGunmoteSlot) beobachtet" } else { 'Gunmote-Platz unbestätigt' }
        $identity = if ($_.IdentityConfirmed -and $_.Mac) { [string]$_.Mac } else { 'Identität nicht bestätigt' }
        [pscustomobject]@{ DeviceKey=$_.DeviceKey; Label=("{0} | {1} | {2} | {3}" -f $_.DisplayName, $identity, $desired, $runtime); Expert=("{0} | {1}" -f $_.Mac, $_.InstanceId) }
    })
    $controls.CmbWizardDevice.DisplayMemberPath = if ($controls.RadioExpertMode.IsChecked) { 'Expert' } else { 'Label' }
    $controls.CmbWizardDevice.SelectedValuePath = 'DeviceKey'
    $controls.CmbWizardDevice.ItemsSource = $devices
    if ($devices.Count -gt 0) {
        $matchingDevice = @($devices | Where-Object DeviceKey -CEQ $selectedDeviceKey) | Select-Object -First 1
        if ($matchingDevice) { $controls.CmbWizardDevice.SelectedValue = $selectedDeviceKey }
        else { $controls.CmbWizardDevice.SelectedIndex = 0; $wizardState.SelectedDeviceKey = [string]$controls.CmbWizardDevice.SelectedValue }
    } else { $wizardState.SelectedDeviceKey = $null }
    $checklist = $wizardState.Checklist
    $controls.BrandCelebrateMascot.Visibility = if ($checklist -and $checklist.ChecksCompleteByUserAttestation) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    if ($checklist -and $checklist.ChecksCompleteByUserAttestation) {
        $controls.TextWizardStatus.Text = 'Alle manuellen Prüfungen wurden von dir bestätigt. Nicht unabhängig verifiziert; keine Garantie auf Spielfunktion.'
    }
    foreach ($step in $checklist.Steps) {
        if ($step.Type -eq 'ReadOnlyObservation') { foreach ($dep in $step.Items) { [void]$controls.ListWizardChecklist.Items.Add("Abhängigkeit $($dep.Name): $($dep.Status) — $($dep.Message)") }; continue }
        if ($step.Type -eq 'UserAttestation') {
            $device = @($session.Devices | Where-Object DeviceKey -CEQ $step.DeviceKey) | Select-Object -First 1
            $deviceLabel = if ($controls.RadioExpertMode.IsChecked) { $step.DeviceKey } elseif ($device) { $device.DisplayName } else { 'Controller' }
            $statusLabel = switch ($step.Status) {
                'user-confirmed-current' { 'von dir bestätigt (aktuelle Sitzung)' }
                'stale-retest-required' { 'veraltet — erneut prüfen' }
                'historical-retest-required' { 'früher notiert — erneut prüfen' }
                default { 'noch nicht geprüft' }
            }
            $checkLabel = switch ($step.Check) { 'RuntimeSlot' { 'Laufzeitplatz' }; 'Calibration' { 'Kalibrierung' }; 'Aim' { 'Zieltest' }; 'Trigger' { 'Abzugstest' } }
            [void]$controls.ListWizardChecklist.Items.Add("$deviceLabel — ${checkLabel}: $statusLabel")
        }
    }
    $controls.TextWizardExpertDetails.Text = "Installationsordner: $($session.Root)`nKonfiguration: $($session.ConfigPath) [$($session.ConfigStatus)]`nVerbindungssitzung: $($session.ConnectionSnapshotId)`nEinsatzbereitschaft wird hier nicht bestätigt; Prüfungen sind nur manuelle Nutzeraussagen."
    $controls.TextWizardExpertDetails.Visibility = if ($controls.RadioExpertMode.IsChecked) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
    return $checklist
}.GetNewClosure()
$wizardState.Render = $renderWizard
$controls.BtnStartWizard.Add_Click({ [void](& $wizardDispatcher 'Start' $null) }.GetNewClosure())
$controls.BtnRefreshWizard.Add_Click({ [void](& $wizardDispatcher 'Refresh' $null) }.GetNewClosure())
$controls.BtnAssignWizardPlayer.Add_Click({ [void](& $wizardDispatcher 'Assign' $null) }.GetNewClosure())
$controls.BtnConfirmRuntimeSlot.Add_Click({ [void](& $wizardDispatcher 'RuntimeSlot' $null) }.GetNewClosure())
$controls.BtnConfirmCalibration.Add_Click({ [void](& $wizardDispatcher 'Calibration' $null) }.GetNewClosure())
$controls.BtnConfirmAim.Add_Click({ [void](& $wizardDispatcher 'Aim' $null) }.GetNewClosure())
$controls.BtnConfirmTrigger.Add_Click({ [void](& $wizardDispatcher 'Trigger' $null) }.GetNewClosure())
$controls.BtnImportWizardState.Add_Click({ [void](& $wizardDispatcher 'Import' $null) }.GetNewClosure())
$controls.BtnSaveWizardState.Add_Click({ [void](& $wizardDispatcher 'Save' $null) }.GetNewClosure())
$controls.CmbWizardDevice.Add_SelectionChanged({
    $selected = $controls.CmbWizardDevice.SelectedItem
    if ($selected -and $wizardState.Session) {
        $wizardState.SelectedDeviceKey = [string]$selected.DeviceKey
        $device = @($wizardState.Session.Devices | Where-Object DeviceKey -CEQ $selected.DeviceKey) | Select-Object -First 1
        if ($device) { $controls.CmbWizardPlayer.SelectedIndex = if ($device.DesiredPlayer) { [int]$device.DesiredPlayer } else { 0 } }
    }
}.GetNewClosure())
$wizardModeChanged = { if ($wizardState.Session -and -not $wizardState.SuppressModeChange) { [void](& $wizardDispatcher 'Mode' $null); [void](& $wizardState.Render) } }.GetNewClosure()
$controls.RadioQuickMode.Add_Checked($wizardModeChanged)
$controls.RadioCustomMode.Add_Checked($wizardModeChanged)
$controls.RadioExpertMode.Add_Checked($wizardModeChanged)
# Profile editor state is separate from shipped templates. The dispatcher reuses the same file-action transaction for each proposal.
$profileState = [pscustomobject]@{ EffectTemplates = @(); ButtonTemplates = @(); ActiveEffect = $null; ActiveButtons = $null }
$buildEffectProfile = {
    if (-not $profileState.ActiveEffect) { throw 'Copy or import an effect profile before editing or applying it.' }
    $profile = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $profileState.ActiveEffect -Depth 30)
    $profile.Name = [string]$controls.TextEffectProfileName.Text
    $profile.Settings.global.hold_ms = [int]$controls.SliderHoldMs.Value
    $profile.Settings.global.ammo_drop_shot = [bool]$controls.ChkAmmoDrop.IsChecked
    $profile.Settings.global.led_mode = if ($controls.ChkLedLifeBar.IsChecked) { 'life_bar' } else { 'none' }
    $profile.Settings.global.trace_enabled = [bool]$controls.ChkTraceLog.IsChecked
    $games = [ordered]@{}
    # Keep imported game entries even when this installation has no matching row.
    # Applying such an entry is rejected by the profile action with an explicit diagnostic.
    foreach ($importedGame in $profile.Settings.games.PSObject.Properties) {
        $games[$importedGame.Name] = $importedGame.Value
    }
    foreach ($gameRow in $controls.GridGameProfiles.ItemsSource) {
        $game = [ordered]@{ rumble = [bool]$gameRow.Rumble; leds = [bool]$gameRow.Leds }
        $previous = $profile.Settings.games.PSObject.Properties[[string]$gameRow.Name]
        if ($null -ne $previous -and $null -ne $previous.Value.PSObject.Properties['hold_ms']) { $game.hold_ms = [int]$previous.Value.hold_ms }
        $games[[string]$gameRow.Name] = $game
    }
    $profile.Settings.games = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $games -Depth 20)
    $profile
}.GetNewClosure()
$buildButtonProfile = {
    if (-not $profileState.ActiveButtons) { throw 'Copy or import a button template before editing it.' }
    $profile = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $profileState.ActiveButtons -Depth 30)
    $profile.Name = [string]$controls.TextButtonProfileName.Text
    $profile.Intents = @($controls.GridButtonIntents.ItemsSource | ForEach-Object { [pscustomobject]@{ Id=[string]$_.Id; Label=[string]$_.Label } })
    $profile
}.GetNewClosure()
$profileDispatcher = {
    param([string]$Operation, [object]$Argument)
    try {
        . $setupCoreScript
        . $profileScript
        switch ($Operation) {
            'Initialize' {
                $profileState.EffectTemplates = @(Get-HotwmTemplates -Kind Effects)
                $profileState.ButtonTemplates = @(Get-HotwmTemplates -Kind Buttons)
                $controls.CmbEffectPreset.ItemsSource = $profileState.EffectTemplates
                $controls.CmbEffectPreset.SelectedIndex = 0
                $controls.CmbButtonTemplate.ItemsSource = $profileState.ButtonTemplates
                $controls.CmbButtonTemplate.SelectedIndex = 0
                $controls.TextEffectPresetDescription.Text = $profileState.EffectTemplates[0].Description
                if ($controls.GridButtonIntents.Columns.Count -eq 0) {
                    $idColumn = [System.Windows.Controls.DataGridTextColumn]::new()
                    $idColumn.Header = 'Intent'
                    $idColumn.Binding = [System.Windows.Data.Binding]::new('Id')
                    $idColumn.IsReadOnly = $true
                    [void]$controls.GridButtonIntents.Columns.Add($idColumn)
                    $labelColumn = [System.Windows.Controls.DataGridTextColumn]::new()
                    $labelColumn.Header = 'Editable label'
                    $labelColumn.Binding = [System.Windows.Data.Binding]::new('Label')
                    $labelColumn.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                    [void]$controls.GridButtonIntents.Columns.Add($labelColumn)
                }
                return [pscustomobject]@{ Success=$true; Effects=$profileState.EffectTemplates.Count; Buttons=$profileState.ButtonTemplates.Count }
            }
            'CopyEffect' {
                $template = $controls.CmbEffectPreset.SelectedItem
                if (-not $template) { throw 'Choose a shipped effect preset first.' }
                $profileState.ActiveEffect = New-HotwmUserProfile -Template $template -Name ([string]$controls.TextEffectProfileName.Text)
                $settings = $profileState.ActiveEffect.Settings.global
                $controls.SliderHoldMs.Value = [double]$settings.hold_ms
                $controls.ChkAmmoDrop.IsChecked = [bool]$settings.ammo_drop_shot
                $controls.ChkLedLifeBar.IsChecked = ($settings.led_mode -eq 'life_bar')
                $controls.ChkTraceLog.IsChecked = [bool]$settings.trace_enabled
                $controls.TextEffectProfileStatus.Text = "Copied '$($template.Name)' to editable user profile '$($profileState.ActiveEffect.Name)'. Shipped preset unchanged; adjust shared values in Recoil & Profiles Tuning."
                return [pscustomobject]@{ Success=$true; Profile=$profileState.ActiveEffect }
            }
            'BuildEffect' {
                $profile = & $buildEffectProfile
                $profile = Assert-HotwmProfile -Profile $profile
                return [pscustomobject]@{ Success=$true; Profile=$profile }
            }
            'ImportEffect' {
                $profile = Import-HotwmProfile -Path ([string]$Argument.Path)
                if ($profile.Kind -cne 'effects') { throw 'Selected file is not an effects profile.' }
                $profileState.ActiveEffect = $profile
                $controls.TextEffectProfileName.Text = $profile.Name
                $controls.SliderHoldMs.Value = [double]$profile.Settings.global.hold_ms
                $controls.ChkAmmoDrop.IsChecked = [bool]$profile.Settings.global.ammo_drop_shot
                $controls.ChkLedLifeBar.IsChecked = ($profile.Settings.global.led_mode -eq 'life_bar')
                $controls.ChkTraceLog.IsChecked = [bool]$profile.Settings.global.trace_enabled
                foreach ($game in $profile.Settings.games.PSObject.Properties) {
                    $row = @($controls.GridGameProfiles.ItemsSource | Where-Object { $_.Name -eq $game.Name }) | Select-Object -First 1
                    if ($row) {
                        if ($null -ne $game.Value.PSObject.Properties['rumble']) { $row.Rumble = [bool]$game.Value.rumble }
                        if ($null -ne $game.Value.PSObject.Properties['leds']) { $row.Leds = [bool]$game.Value.leds }
                    }
                }
                $controls.TextEffectProfileStatus.Text = "Imported editable profile '$($profile.Name)'. Import only reads the file; Apply requires separate approval."
                return [pscustomobject]@{ Success=$true; Profile=$profile }
            }
            'ApplyEffect' {
                $profile = & $buildEffectProfile
                $profile = Assert-HotwmProfile -Profile $profile
                $configTarget = if ($Argument -and $Argument.ConfigPath) { [string]$Argument.ConfigPath } else { [string]$configPath }
                $action = New-HotwmEffectProfileAction -Profile $profile -ConfigPath $configTarget
                # Preview the actual merged postimage. A profile can inherit a game's
                # existing hold_ms even when its own profile value omits that field.
                $proposedConfig = ConvertFrom-Json -InputObject $action.ProposedContent
                $gamePreview = ($proposedConfig.games.PSObject.Properties | ForEach-Object {
                    $gameHold = if ($null -ne $_.Value.PSObject.Properties['hold_ms']) { [string]$_.Value.hold_ms } else { "global ($($proposedConfig.global.hold_ms))" }
                    "$($_.Name): rumble=$($_.Value.rumble), LEDs=$($_.Value.leds), hold_ms=$gameHold"
                }) -join "`n"
                $summary = "Profile: $($profile.Name)`nTarget: $($action.TargetPath)`nGlobal: hold_ms=$($proposedConfig.global.hold_ms), ammo_drop_shot=$($proposedConfig.global.ammo_drop_shot), led_mode=$($proposedConfig.global.led_mode), trace_enabled=$($proposedConfig.global.trace_enabled)`nPer-game settings:`n$gamePreview`nScope is global/per-game; no per-player effects or physical output confirmation."
                $confirm = if ($Argument -and $Argument.Confirm) { $Argument.Confirm } else {
                    $display = $summary
                    { param($proposal) [System.Windows.MessageBox]::Show("Apply this effect profile?`n`n$display`n`nOther configuration fields are preserved. A backup is made before writing.", 'Confirm effect profile', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes }.GetNewClosure()
                }
                $applied = Invoke-HotwmFileAction -Action $action -Confirm $confirm
                $controls.TextEffectProfileStatus.Text = if ($applied.Success) { "Applied '$($profile.Name)' to $configTarget. Backup: $($applied.BackupPath)" } else { 'Apply declined; no configuration changes were made.' }
                return [pscustomobject]@{ Success=$applied.Success; Status=$applied.Status; Profile=$profile; Action=$action; Preview=$summary; Applied=$applied }
            }
            'ExportEffect' {
                $profile = & $buildEffectProfile
                $profile = Assert-HotwmProfile -Profile $profile
                $action = Export-HotwmProfileAction -Profile $profile -Path ([string]$Argument.Path)
                $summary = "Export effects profile '$($profile.Name)' to:`n$($action.TargetPath)`n`nThe export contains the editable global and per-game values."
                $confirm = if ($Argument.Confirm) { $Argument.Confirm } else {
                    $display = $summary
                    { param($proposal) [System.Windows.MessageBox]::Show("$display`n`nProceed?", 'Confirm profile export', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes }.GetNewClosure()
                }
                $applied = Invoke-HotwmFileAction -Action $action -Confirm $confirm
                $controls.TextEffectProfileStatus.Text = if ($applied.Success) { "Exported profile to $($action.TargetPath)." } else { 'Export declined; no file was written.' }
                return [pscustomobject]@{ Success=$applied.Success; Status=$applied.Status; Profile=$profile; Action=$action; Applied=$applied }
            }
            'CopyButtons' {
                $template = $controls.CmbButtonTemplate.SelectedItem
                if (-not $template) { throw 'Choose a shipped button template first.' }
                $profileState.ActiveButtons = New-HotwmUserProfile -Template $template -Name ([string]$controls.TextButtonProfileName.Text)
                $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                foreach ($intent in $profileState.ActiveButtons.Intents) {
                    $row = [pscustomobject]@{ Id=[string]$intent.Id; Label=[string]$intent.Label }; $items.Add($row)
                }
                $controls.GridButtonIntents.ItemsSource = $items
                $controls.TextButtonProfileStatus.Text = "Copied '$($template.Name)' into an editable checklist. These intent labels do not configure a controller or game."
                return [pscustomobject]@{ Success=$true; Profile=$profileState.ActiveButtons }
            }
            'BuildButtons' {
                $profile = & $buildButtonProfile
                $profile = Assert-HotwmProfile -Profile $profile
                return [pscustomobject]@{ Success=$true; Profile=$profile }
            }
            'ImportButtons' {
                $profile = Import-HotwmProfile -Path ([string]$Argument.Path)
                if ($profile.Kind -cne 'buttons') { throw 'Selected file is not a button intent profile.' }
                $profileState.ActiveButtons = $profile
                $controls.TextButtonProfileName.Text = $profile.Name
                $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                foreach ($intent in $profile.Intents) {
                    $row = [pscustomobject]@{ Id=[string]$intent.Id; Label=[string]$intent.Label }; $items.Add($row)
                }
                $controls.GridButtonIntents.ItemsSource = $items
                $controls.TextButtonProfileStatus.Text = "Imported editable intent profile '$($profile.Name)'. It remains a manual/Kit-profile checklist."
                return [pscustomobject]@{ Success=$true; Profile=$profile }
            }
            'ExportButtons' {
                $profile = & $buildButtonProfile
                $profile = Assert-HotwmProfile -Profile $profile
                $action = Export-HotwmProfileAction -Profile $profile -Path ([string]$Argument.Path)
                $summary = "Export button intent profile '$($profile.Name)' to:`n$($action.TargetPath)`n`nThis stores semantic labels only; it does not configure hardware."
                $confirm = if ($Argument.Confirm) { $Argument.Confirm } else {
                    $display = $summary
                    { param($proposal) [System.Windows.MessageBox]::Show("$display`n`nProceed?", 'Confirm button profile export', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes }.GetNewClosure()
                }
                $applied = Invoke-HotwmFileAction -Action $action -Confirm $confirm
                $controls.TextButtonProfileStatus.Text = if ($applied.Success) { "Exported checklist to $($action.TargetPath)." } else { 'Export declined; no file was written.' }
                return [pscustomobject]@{ Success=$applied.Success; Status=$applied.Status; Profile=$profile; Action=$action; Applied=$applied }
            }
            default { throw "Unknown profile editor operation: $Operation" }
        }
    } catch {
        $message = $_.Exception.Message
        if ($Operation -in @('CopyEffect','BuildEffect','ImportEffect','ApplyEffect','ExportEffect')) { $controls.TextEffectProfileStatus.Text = "Profile error: $message" }
        elseif ($Operation -in @('CopyButtons','BuildButtons','ImportButtons','ExportButtons')) { $controls.TextButtonProfileStatus.Text = "Profile error: $message" }
        return [pscustomobject]@{ Success=$false; Message=$message }
    }
}.GetNewClosure()
# Initialize template choices after the editor's shared controls exist.
[void](& $profileDispatcher 'Initialize' $null)
$controls.CmbEffectPreset.Add_SelectionChanged({
    if ($controls.CmbEffectPreset.SelectedItem) { $controls.TextEffectPresetDescription.Text = [string]$controls.CmbEffectPreset.SelectedItem.Description }
}.GetNewClosure())
$controls.BtnCopyEffectProfile.Add_Click({ [void](& $profileDispatcher 'CopyEffect' $null) }.GetNewClosure())
$controls.BtnApplyEffectProfile.Add_Click({ [void](& $profileDispatcher 'ApplyEffect' $null) }.GetNewClosure())
$controls.BtnImportEffectProfile.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Import Hotwm effects profile'
    $dialog.Filter = 'Hotwm profile (*.json)|*.json|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq $true) { [void](& $profileDispatcher 'ImportEffect' @{ Path = $dialog.FileName }) }
}.GetNewClosure())
$controls.BtnExportEffectProfile.Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Export Hotwm effects profile'
    $dialog.Filter = 'Hotwm profile (*.json)|*.json'
    $dialog.FileName = ([string]$controls.TextEffectProfileName.Text) + '.json'
    if ($dialog.ShowDialog() -eq $true) { [void](& $profileDispatcher 'ExportEffect' @{ Path = $dialog.FileName }) }
}.GetNewClosure())
$controls.BtnOpenEffectTuning.Add_Click({
    $effectTab = $null
    foreach ($tab in $controls.MainTabs.Items) { if ([string]$tab.Header -eq 'Effekte') { $effectTab = $tab; break } }
    if ($effectTab) { $controls.MainTabs.SelectedItem = $effectTab }
    $controls.GlobalEffectControls.BringIntoView()
}.GetNewClosure())
$controls.BtnCopyButtonProfile.Add_Click({ [void](& $profileDispatcher 'CopyButtons' $null) }.GetNewClosure())
$controls.BtnImportButtonProfile.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Import Hotwm button intent profile'
    $dialog.Filter = 'Hotwm profile (*.json)|*.json|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq $true) { [void](& $profileDispatcher 'ImportButtons' @{ Path = $dialog.FileName }) }
}.GetNewClosure())
$controls.BtnExportButtonProfile.Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = 'Export Hotwm button intent profile'
    $dialog.Filter = 'Hotwm profile (*.json)|*.json'
    $dialog.FileName = ([string]$controls.TextButtonProfileName.Text) + '.json'
    if ($dialog.ShowDialog() -eq $true) { [void](& $profileDispatcher 'ExportButtons' @{ Path = $dialog.FileName }) }
}.GetNewClosure())

function Show-HotwmReviewedFileProposal {
    param([string]$Title, [string]$TargetPath, [string]$Content, [string]$Effect, [switch]$RequireGunmoteClosed)
    $dialog = New-Object System.Windows.Window
    $dialog.Title = $Title
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.Width = 760
    $dialog.Height = 620
    $dialog.MinWidth = 560
    $dialog.MinHeight = 420
    $dialog.Background = $window.FindResource('BackgroundBrush')
    $dialog.Foreground = $window.FindResource('TextBrush')
    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = [System.Windows.Thickness]::new(14)
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height=[System.Windows.GridLength]::Auto }))
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height=[System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star) }))
    [void]$root.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height=[System.Windows.GridLength]::Auto }))
    $summary = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetRow($summary, 0)
    $targetText = New-Object System.Windows.Controls.TextBlock
    $guidance = if ($RequireGunmoteClosed) { "`nGunmote must be closed before this file change can be applied. This does not select or activate a layout." } else { '' }
    $targetText.Text = "Ziel: $TargetPath`n$Effect$guidance"
    $targetText.TextWrapping = 'Wrap'
    $targetText.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    [void]$summary.Children.Add($targetText)
    [void]$root.Children.Add($summary)
    $contentBox = New-Object System.Windows.Controls.TextBox
    $contentBox.Text = $Content
    $contentBox.IsReadOnly = $true
    $contentBox.AcceptsReturn = $true
    $contentBox.VerticalScrollBarVisibility = 'Auto'
    $contentBox.HorizontalScrollBarVisibility = 'Auto'
    $contentBox.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    $contentBox.Background = $window.FindResource('BackgroundBrush')
    $contentBox.Foreground = $window.FindResource('TextBrush')
    $contentBox.BorderBrush = $window.FindResource('BorderBrush')
    $contentBox.BorderThickness = [System.Windows.Thickness]::new(1)
    [System.Windows.Controls.Grid]::SetRow($contentBox, 1)
    [void]$root.Children.Add($contentBox)
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = [System.Windows.Thickness]::new(0,10,0,0)
    [System.Windows.Controls.Grid]::SetRow($buttons, 2)
    $approve = New-Object System.Windows.Controls.Button
    $approve.Content = 'Dateiänderung bestätigen'
    $approve.Margin = [System.Windows.Thickness]::new(0,0,8,0)
    $approve.Padding = [System.Windows.Thickness]::new(12,6,12,6)
    $approve.IsDefault = $true
    $approve.Add_Click({ $dialog.DialogResult = $true; $dialog.Close() }.GetNewClosure())
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Abbrechen'
    $cancel.Padding = [System.Windows.Thickness]::new(12,6,12,6)
    $cancel.IsCancel = $true
    $cancel.Add_Click({ $dialog.DialogResult = $false; $dialog.Close() }.GetNewClosure())
    [void]$buttons.Children.Add($approve)
    [void]$buttons.Children.Add($cancel)
    [void]$root.Children.Add($buttons)
    $dialog.Content = $root
    return ($dialog.ShowDialog() -eq $true)
}

$gunmoteState = [pscustomobject]@{
    Initialized=$false; Catalog=$null; Layout=$null; LayoutResult=$null; SavedLayoutTitle=$null; SavedPath=$null; Actions=$null; Applied=$null
}
$buildGunmoteLayout = {
    if (-not $gunmoteState.Layout) { throw 'Copy a shipped preset or import a layout first.' }
    $layout = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $gunmoteState.Layout -Depth 100)
    $layout.Title = [string]$controls.TextGunmoteTitle.Text
    $onMap = [ordered]@{}
    $offMap = [ordered]@{}
    foreach ($row in $controls.GridGunmoteMappings.ItemsSource) {
        if (-not [string]::IsNullOrWhiteSpace([string]$row.OnScreen)) { $onMap[[string]$row.Input] = [string]$row.OnScreen }
        if (-not [string]::IsNullOrWhiteSpace([string]$row.OffScreen)) { $offMap[[string]$row.Input] = [string]$row.OffScreen }
    }
    $layout.All.OnScreen = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $onMap -Depth 100)
    $layout.All.OffScreen = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $offMap -Depth 100)
    $layout
}.GetNewClosure()
$gunmoteDispatcher = {
    param([string]$Operation, [object]$Argument)
    try {
        $previousActions = $gunmoteState.Actions
        $previousApplied = $gunmoteState.Applied
        . $setupCoreScript
        . $gunmoteScript
        if ($previousActions) { $script:HotwmGunmoteActions = $previousActions }
        if ($previousApplied) { $script:HotwmGunmoteApplied = $previousApplied }
        $gunmoteState.Actions = $script:HotwmGunmoteActions
        $gunmoteState.Applied = $script:HotwmGunmoteApplied
        if (-not $gunmoteState.Initialized) {
            $gunmoteState.Catalog = Get-HotwmGunmoteLayouts
            $presetDescriptions = @{
                Menu = 'Menütasten ohne Zeigersteuerung.'
                Pad43 = 'Linker Analogstick als Zeiger für 4:3-Bildschirme.'
                TP = 'Linker Stick bewegt den Zeiger, rechter Stick steuert TeknoParrot.'
                Mouse = 'Zeiger und Tasten als Mausbelegung.'
                Mouse43 = 'Mauszeiger mit Anpassung für 4:3-Bildschirme.'
                MouseShoot = 'Mauszeiger mit separater Abzugstaste außerhalb des Bildes.'
            }
            $kinds = @($gunmoteState.Catalog.layouts.PSObject.Properties | ForEach-Object {
                [pscustomobject]@{ Kind=$_.Name; Title=$_.Value.Title; Description=$presetDescriptions[$_.Name]; DisplayTitle=('{0} — {1}' -f $_.Value.Title, $presetDescriptions[$_.Name]) }
            })
            $controls.CmbGunmoteKind.ItemsSource = $kinds
            $controls.CmbGunmoteKind.SelectedIndex = 0
            $onColumn = [System.Windows.Controls.DataGridTextColumn]::new()
            $onColumn.Header = 'Zuordnung OnScreen'
            $onColumn.Binding = [System.Windows.Data.Binding]::new('OnScreen')
            $onColumn.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
            [void]$controls.GridGunmoteMappings.Columns.Add($onColumn)
            $inputColumn = [System.Windows.Controls.DataGridTextColumn]::new()
            $inputColumn.Header = 'Taste'
            $inputColumn.Binding = [System.Windows.Data.Binding]::new('Input')
            $inputColumn.IsReadOnly = $true
            $inputColumn.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Auto)
            [void]$controls.GridGunmoteMappings.Columns.Insert(0, $inputColumn)
            $offColumn = [System.Windows.Controls.DataGridTextColumn]::new()
            $offColumn.Header = 'Zuordnung OffScreen'
            $offColumn.Binding = [System.Windows.Data.Binding]::new('OffScreen')
            $offColumn.Width = [System.Windows.Controls.DataGridLength]::new(1, [System.Windows.Controls.DataGridLengthUnitType]::Star)
            [void]$controls.GridGunmoteMappings.Columns.Add($offColumn)
            $gunmoteState.Initialized = $true
        }
        switch ($Operation) {
            'Initialize' { return [pscustomobject]@{ Success=$true; LayoutKinds=$gunmoteState.Catalog.layouts.PSObject.Properties.Count } }
            'CopyLayout' {
                $selected = $controls.CmbGunmoteKind.SelectedItem
                if (-not $selected) { throw 'Choose a shipped layout preset first.' }
                $layout = New-HotwmGunmoteUserLayout -Kind ([string]$selected.Kind) -Title ([string]$selected.Title)
                $gunmoteState.Layout = $layout
                $controls.TextGunmoteTitle.Text = [string]$layout.Title
                $controls.TextGunmoteFileName.Text = ($selected.Kind.ToLowerInvariant() + '_user.json')
                $gunmoteState.LayoutResult = $null
                $controls.BtnAddGunmoteChooser.IsEnabled = $false
                $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                $keys = @($layout.All.OnScreen.PSObject.Properties.Name) + @($layout.All.OffScreen.PSObject.Properties.Name) | Sort-Object -Unique
                foreach ($key in $keys) {
                    $on = $layout.All.OnScreen.PSObject.Properties[[string]$key]
                    $off = $layout.All.OffScreen.PSObject.Properties[[string]$key]
                    $items.Add([pscustomobject]@{
                        Input=[string]$key
                        OnScreen=if ($on) { [string]$on.Value } else { '' }
                        OffScreen=if ($off) { [string]$off.Value } else { '' }
                    })
                }
                $controls.GridGunmoteMappings.ItemsSource = $items
                $controls.TextGunmoteStatus.Text = "Copied $($selected.Title). Edit the mappings and review the exact file before saving."
                return [pscustomobject]@{ Success=$true; Layout=$layout; MappingCount=$items.Count }
            }
            'ImportLayout' {
                $layout = Import-HotwmGunmoteLayout -Path ([string]$Argument.Path)
                $gunmoteState.Layout = $layout
                $controls.TextGunmoteTitle.Text = [string]$layout.Title
                $controls.TextGunmoteFileName.Text = [System.IO.Path]::GetFileName([string]$Argument.Path)
                $gunmoteState.LayoutResult = $null
                $controls.BtnAddGunmoteChooser.IsEnabled = $false
                $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
                $keys = @($layout.All.OnScreen.PSObject.Properties.Name) + @($layout.All.OffScreen.PSObject.Properties.Name) | Sort-Object -Unique
                foreach ($key in $keys) {
                    $on = $layout.All.OnScreen.PSObject.Properties[[string]$key]
                    $off = $layout.All.OffScreen.PSObject.Properties[[string]$key]
                    $items.Add([pscustomobject]@{
                        Input=[string]$key
                        OnScreen=if ($on) { [string]$on.Value } else { '' }
                        OffScreen=if ($off) { [string]$off.Value } else { '' }
                    })
                }
                $controls.GridGunmoteMappings.ItemsSource = $items
                $controls.TextGunmoteStatus.Text = 'Imported existing layout for editing. No file was changed.'
                return [pscustomobject]@{ Success=$true; Layout=$layout; MappingCount=$items.Count }
            }
            'BuildLayout' {
                $layout = & $buildGunmoteLayout
                Test-HotwmGunmoteLayout -Layout $layout | Out-Null
                return [pscustomobject]@{ Success=$true; Layout=$layout }
            }
            'SaveLayout' {
                if (-not $controls.GridGunmoteMappings.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true)) { throw 'Finish the active mapping edit with a valid value before saving.' }
                if (-not $controls.GridGunmoteMappings.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true)) { throw 'Finish the active mapping row with valid values before saving.' }
                $layout = & $buildGunmoteLayout
                Test-HotwmGunmoteLayout -Layout $layout | Out-Null
                $directory = if ($Argument -and $Argument.KeymapsDir) { [string]$Argument.KeymapsDir } else { [string]$controls.TextGunmoteKeymapsDir.Text }
                $fileName = if ($Argument -and $Argument.FileName) { [string]$Argument.FileName } else { [string]$controls.TextGunmoteFileName.Text }
                $action = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $directory -FileName $fileName
                $controls.TextGunmotePreview.Text = $action.ProposedContent
                $controls.TextGunmotePreview.Visibility = if ($controls.RadioExpertMode.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
                $summary = "Save the edited layout '$($layout.Title)' to $($action.TargetPath). This writes the file only; it will not select it or restart Gunmote."
                $confirm = if ($Argument -and $Argument.Confirm) { $Argument.Confirm } else {
                    $display = $summary; $content = $action.ProposedContent; $target = $action.TargetPath
                    { param($proposal) Show-HotwmReviewedFileProposal -Title 'Review Gunmote layout file' -TargetPath $target -Content $content -Effect $display -RequireGunmoteClosed }.GetNewClosure()
                }
                $checker = if ($Argument -and $Argument.ProcessChecker) { $Argument.ProcessChecker } else { $null }
                $result = Invoke-HotwmGunmoteLayoutAction -Action $action -Confirm $confirm -ProcessChecker $checker
                if ($result.Success) {
                    $gunmoteState.LayoutResult = $result
                    $gunmoteState.SavedLayoutTitle = [string]$layout.Title
                    $gunmoteState.SavedPath = [string]$result.LayoutPath
                    $controls.BtnAddGunmoteChooser.IsEnabled = $true
                    $controls.TextGunmoteStatus.Text = "Saved reviewed layout to $($result.LayoutPath). The active layout was not changed."
                } else {
                    $controls.TextGunmoteStatus.Text = 'Save declined; no layout file was written.'
                }
                return [pscustomobject]@{ Success=$result.Success; Action=$action; Result=$result; Layout=$layout }
            }
            'AddChooser' {
                if (-not $gunmoteState.LayoutResult -or -not $gunmoteState.LayoutResult.Success) { throw 'Save a layout successfully before adding its chooser entry.' }
                $keymapsPath = if ($Argument -and $Argument.KeymapsPath) { [string]$Argument.KeymapsPath } else { [string]$controls.TextGunmoteChooserPath.Text }
                $action = New-HotwmGunmoteChooserAction -LayoutResult $gunmoteState.LayoutResult -KeymapsPath $keymapsPath -LayoutTitle ([string]$gunmoteState.SavedLayoutTitle)
                $controls.TextGunmotePreview.Text = $action.ProposedContent
                $controls.TextGunmotePreview.Visibility = if ($controls.RadioExpertMode.IsChecked) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
                $summary = "Add '$($gunmoteState.SavedLayoutTitle)' pointing to $($gunmoteState.SavedPath) in $($action.TargetPath). This does not select or activate the layout."
                $confirm = if ($Argument -and $Argument.Confirm) { $Argument.Confirm } else {
                    $display = $summary; $content = $action.ProposedContent; $target = $action.TargetPath
                    { param($proposal) Show-HotwmReviewedFileProposal -Title 'Review Gunmote chooser update' -TargetPath $target -Content $content -Effect $display -RequireGunmoteClosed }.GetNewClosure()
                }
                $checker = if ($Argument -and $Argument.ProcessChecker) { $Argument.ProcessChecker } else { $null }
                $result = Invoke-HotwmGunmoteChooserAction -Action $action -Confirm $confirm -ProcessChecker $checker
                $controls.TextGunmoteStatus.Text = if ($result.Success) { 'Chooser entry added. Gunmote was not restarted and no layout was selected.' } else { 'Chooser update declined; Keymaps.json was unchanged.' }
                return [pscustomobject]@{ Success=$result.Success; Action=$action; Result=$result }
            }
            default { throw "Unknown Gunmote layout operation: $Operation" }
        }
    } catch {
        $message = $_.Exception.Message
        $controls.TextGunmoteStatus.Text = "Layout editor: $message"
        return [pscustomobject]@{ Success=$false; Message=$message }
    }
}.GetNewClosure()
$controls.BtnCopyGunmoteLayout.Add_Click({ [void](& $gunmoteDispatcher 'CopyLayout' $null) }.GetNewClosure())
$controls.BtnImportGunmoteLayout.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Import existing Gunmote layout'
    $dialog.Filter = 'Gunmote layout (*.json)|*.json|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq $true) { [void](& $gunmoteDispatcher 'ImportLayout' @{ Path=$dialog.FileName }) }
}.GetNewClosure())
$controls.BtnBrowseGunmoteKeymapsDir.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choose the Gunmote Keymaps directory for a new layout file'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $controls.TextGunmoteKeymapsDir.Text = $dialog.SelectedPath }
}.GetNewClosure())
$controls.BtnBrowseGunmoteChooser.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Choose existing Gunmote Keymaps.json'
    $dialog.Filter = 'Keymaps.json|Keymaps.json|JSON files (*.json)|*.json'
    $dialog.FileName = 'Keymaps.json'
    if ($dialog.ShowDialog() -eq $true) {
        $controls.TextGunmoteChooserPath.Text = $dialog.FileName
        if ([string]::IsNullOrWhiteSpace($controls.TextGunmoteKeymapsDir.Text)) { $controls.TextGunmoteKeymapsDir.Text = [System.IO.Path]::GetDirectoryName($dialog.FileName) }
    }
}.GetNewClosure())
$controls.BtnSaveGunmoteLayout.Add_Click({ [void](& $gunmoteDispatcher 'SaveLayout' $null) }.GetNewClosure())
$controls.BtnAddGunmoteChooser.Add_Click({ [void](& $gunmoteDispatcher 'AddChooser' $null) }.GetNewClosure())
$layoutDirtyHandler = {
    if ($gunmoteState.LayoutResult) {
        $gunmoteState.LayoutResult = $null
        $controls.BtnAddGunmoteChooser.IsEnabled = $false
        $controls.TextGunmoteStatus.Text = 'Layout edits changed after save. Review and save again before adding a chooser entry.'
    }
}.GetNewClosure()
$controls.TextGunmoteTitle.Add_TextChanged($layoutDirtyHandler)
$controls.TextGunmoteFileName.Add_TextChanged($layoutDirtyHandler)
$controls.TextGunmoteKeymapsDir.Add_TextChanged($layoutDirtyHandler)
$controls.GridGunmoteMappings.Add_CellEditEnding($layoutDirtyHandler)
[void](& $gunmoteDispatcher 'Initialize' $null)

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
    ProfileDispatch = $profileDispatcher
    GunmoteDispatch = $gunmoteDispatcher
    WizardDispatch = $wizardDispatcher
    WizardSession = $wizardState
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
