#requires -Version 5.1
<#
.SYNOPSIS
    Read-only guided setup sessions and single-action persistence proposals.
.DESCRIPTION
    Pairing, calibration, runtime-slot identification, and target checks are
    represented as manual user attestations. This module never performs them.
#>

if (-not (Get-Command Get-HotwmDeviceDiscovery -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'HotwmDevices.ps1') }
if (-not (Get-Command Resolve-HotwmPlayerMappings -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'HotwmDevices.ps1') }
if (-not (Get-Command New-HotwmFileAction -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'HotwmSetup.ps1') }
if (-not (Get-Command Test-HotwmKitAvailable -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot 'KitClient.ps1'))) { . (Join-Path $PSScriptRoot 'KitClient.ps1') }
$script:HotwmWizardSessions = @{}

function Get-HotwmWizardFingerprint {
    param([string]$Value)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-HotwmConfigFingerprint {
    param([string]$ConfigPath)
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { return [pscustomobject]@{ Status='unknown'; Path=$null; Fingerprint=$null } }
    try { $path = [System.IO.Path]::GetFullPath($ConfigPath) }
    catch { return [pscustomobject]@{ Status='unavailable'; Path=$ConfigPath; Fingerprint=$null } }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Status='unavailable'; Path=$path; Fingerprint=$null } }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        return [pscustomobject]@{ Status='observed'; Path=$path; Fingerprint=$hash }
    } catch { return [pscustomobject]@{ Status='unavailable'; Path=$path; Fingerprint=$null } }
}

function Get-HotwmWizardDeviceFingerprint {
    param([object]$Device, [string]$SnapshotId)
    $ids = @($Device.InstanceIds | Sort-Object) -join '|'
    Get-HotwmWizardFingerprint -Value (('{0}|{1}|{2}|{3}' -f $Device.Mac, $Device.IdentityConfirmed, $ids, $SnapshotId))
}

function Get-HotwmDependencySnapshot {
    [CmdletBinding()]
    param([object[]]$DependencyRecords)
    if ($PSBoundParameters.ContainsKey('DependencyRecords')) {
        $known = @('Python','Gunmote','Kit')
        return ,@($DependencyRecords | ForEach-Object {
            if ($_.Name -notin $known) { throw "Unknown dependency observation '$($_.Name)'." }
            [pscustomobject]@{ Name=$_.Name; Status=[string]$_.Status; Message=[string]$_.Message; Source='Injected read-only observation' }
        })
    }
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    $gunmote = Get-Process -Name gunmote -ErrorAction SilentlyContinue
    $kitAvailable = $null
    if (Get-Command Test-HotwmKitAvailable -ErrorAction SilentlyContinue) {
        try { $kitAvailable = [bool](Test-HotwmKitAvailable) } catch { $kitAvailable = $null }
    }
    @(
        [pscustomobject]@{ Name='Python'; Status=if ($python) { 'detected' } else { 'unknown' }; Message=if ($python) { 'Executable is present.' } else { 'No python.exe command was detected.' }; Source='Local read-only process/path check' }
        [pscustomobject]@{ Name='Gunmote'; Status=if ($gunmote) { 'detected' } else { 'unknown' }; Message=if ($gunmote) { 'Process is present.' } else { 'Process is not currently detected.' }; Source='Local read-only process check' }
        [pscustomobject]@{ Name='Kit'; Status=if ($kitAvailable -eq $true) { 'detected' } elseif ($kitAvailable -eq $false) { 'not-detected' } else { 'unknown' }; Message=if ($kitAvailable -eq $true) { 'Kit API entry point is present.' } elseif ($kitAvailable -eq $false) { 'Kit API entry point was not found.' } else { 'Kit availability could not be checked.' }; Source='Test-HotwmKitAvailable read-only filesystem check' }
    )
}

function ConvertTo-HotwmValidatedDesiredMappings {
    param([object[]]$Mappings)
    if (@($Mappings).Count -eq 0) { return @() }
    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($mapping in @($Mappings)) {
        if ($null -eq $mapping -or ($mapping -is [array] -and $mapping.Count -eq 0)) { continue }
        $mac = ConvertTo-HotwmBluetoothMac -DeviceRecord ([pscustomobject]@{ BluetoothAddress=[string]$mapping.Mac })
        $player = 0
        if (-not $mac) { throw 'Saved desired mappings require a valid Bluetooth MAC; missing identities cannot be persisted.' }
        if (-not [int]::TryParse([string]$mapping.Player, [ref]$player) -or $player -notin @(1,2)) { throw 'Desired player must be 1 or 2.' }
        $result.Add([pscustomobject]@{ Mac=$mac; Player=$player })
    }
    $duplicateMac = @($result | Group-Object Mac | Where-Object Count -gt 1)
    $duplicatePlayer = @($result | Group-Object Player | Where-Object Count -gt 1)
    if ($duplicateMac.Count -gt 0) { throw 'A Bluetooth MAC cannot be assigned more than once.' }
    if ($duplicatePlayer.Count -gt 0) { throw 'Each desired player slot can be assigned to only one MAC.' }
    return @($result.ToArray())
}

function Get-HotwmMappedDiscovery {
    param([object[]]$DeviceRecords, [object[]]$Mappings)
    if ($PSBoundParameters.ContainsKey('DeviceRecords')) { $discovery = Get-HotwmDeviceDiscovery -DeviceRecords $DeviceRecords }
    else { $discovery = Get-HotwmDeviceDiscovery }
    $devices = @($discovery.Devices)
    if ($devices.Count -gt 0 -and @($Mappings).Count -gt 0) {
        $resolved = @(Resolve-HotwmPlayerMappings -Devices $devices -Mappings $Mappings)
        if ($resolved.Count -eq 1 -and $resolved[0] -is [array]) { $devices = @($resolved[0]) }
        else { $devices = $resolved }
    }
    [pscustomobject]@{ Discovery=$discovery; Devices=$devices }
}

function New-HotwmSetupSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][ValidateSet('Quick','Custom','Expert')][string]$Mode,
        [object[]]$DeviceRecords,
        [object[]]$Mappings = @(),
        [object[]]$DependencyRecords,
        [object]$SavedState,
        [string]$ConfigPath
    )
    try { $canonicalRoot = [System.IO.Path]::GetFullPath($Root) }
    catch { throw 'Setup folder path is invalid.' }
    if (-not (Test-Path -LiteralPath $canonicalRoot -PathType Container)) { throw 'Selected setup folder does not exist or is not a directory.' }
    try { $null = Get-ChildItem -LiteralPath $canonicalRoot -Force -ErrorAction Stop | Select-Object -First 1 }
    catch { throw 'Selected setup folder cannot be read.' }
    if ($SavedState) {
        $savedMappings = ConvertTo-HotwmValidatedDesiredMappings -Mappings @($SavedState.DesiredMappings)
        if (-not $PSBoundParameters.ContainsKey('Mappings') -or @($Mappings).Count -eq 0) { $Mappings = $savedMappings }
    } else { $Mappings = ConvertTo-HotwmValidatedDesiredMappings -Mappings $Mappings }
    $mapped = if ($PSBoundParameters.ContainsKey('DeviceRecords')) {
        Get-HotwmMappedDiscovery -DeviceRecords $DeviceRecords -Mappings $Mappings
    } else { Get-HotwmMappedDiscovery -Mappings $Mappings }
    $snapshotId = [Guid]::NewGuid().ToString('N')
    $config = Get-HotwmConfigFingerprint -ConfigPath $ConfigPath
    $devices = foreach ($device in $mapped.Devices) {
        $copy = [ordered]@{}
        foreach ($property in $device.PSObject.Properties) { $copy[$property.Name] = $property.Value }
        $copy['DeviceKey'] = [string]$device.InstanceId
        if (-not $copy.Contains('MappingScope')) { $copy['MappingScope'] = if ($device.MappingConfirmed) { 'persistent-desired-MAC' } else { 'unassigned' } }
        $copy['RuntimeGunmoteSlot'] = $null
        $copy['CurrentFingerprint'] = Get-HotwmWizardDeviceFingerprint -Device $device -SnapshotId $snapshotId
        [pscustomobject]$copy
    }
    $dependencies = if ($PSBoundParameters.ContainsKey('DependencyRecords')) { Get-HotwmDependencySnapshot -DependencyRecords $DependencyRecords } else { Get-HotwmDependencySnapshot }
    $session = [pscustomobject]@{
        SchemaVersion = 1
        SessionId = [Guid]::NewGuid().ToString('N')
        ConnectionSnapshotId = $snapshotId
        Root = $canonicalRoot
        RootStatus = 'accessible'
        LayoutStatus = 'unknown'
        LayoutMessage = 'Emulator folder layout has not been identified or validated.'
        Mode = $Mode
        WorkflowEngine = 'shared'
        Discovery = $mapped.Discovery
        Devices = @($devices)
        Mappings = @($Mappings)
        SessionOnlyAssignments = @()
        Confirmations = @()
        HistoricalConfirmations = if ($SavedState) { @($SavedState.HistoricalConfirmations) } else { @() }
        DependencyStatus = @($dependencies)
        ConfigPath = $config.Path
        ConfigStatus = $config.Status
        ConfigFingerprint = $config.Fingerprint
        PairingMode = 'semi-automatic-guided'
        PairingUri = 'ms-settings:bluetooth'
        Ready = $false
    }
    $script:HotwmWizardSessions[$session.SessionId] = $session
    return $session
}

function Assert-HotwmLiveSetupSession {
    param([object]$Session)
    if (-not $Session.SessionId -or -not $script:HotwmWizardSessions.ContainsKey([string]$Session.SessionId) -or
        -not [object]::ReferenceEquals($script:HotwmWizardSessions[[string]$Session.SessionId], $Session)) {
        throw 'Setup session is not a live session created by this module instance.'
    }
}

function Get-HotwmSetupChecklist {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session)
    Assert-HotwmLiveSetupSession $Session
    $config = Get-HotwmConfigFingerprint -ConfigPath $Session.ConfigPath
    $configFresh = ([string]$config.Status -ceq [string]$Session.ConfigStatus) -and ([string]$config.Fingerprint -ceq [string]$Session.ConfigFingerprint)
    $steps = New-Object 'System.Collections.Generic.List[object]'
    $steps.Add([pscustomobject]@{ Id='setup-folder'; Status=$Session.RootStatus; Type='Observed'; Message='Folder is readable; emulator layout remains unknown.' })
    $steps.Add([pscustomobject]@{ Id='pairing'; Status='manual-required'; Type='Manual'; Message='Use the controller sync buttons and Windows Bluetooth settings; Hotwm does not pair devices.'; Uri=$Session.PairingUri })
    $steps.Add([pscustomobject]@{ Id='dependencies'; Status='observed-or-unknown'; Type='ReadOnlyObservation'; Items=@($Session.DependencyStatus) })
    foreach ($device in $Session.Devices) {
        $steps.Add([pscustomobject]@{ Id='device-identity'; DeviceKey=$device.DeviceKey; Status=if ($device.IdentityConfirmed) { 'identified' } else { 'unconfirmed' }; Type='PnPObservation'; Mac=$device.Mac })
        $steps.Add([pscustomobject]@{ Id='desired-player'; DeviceKey=$device.DeviceKey; DesiredPlayer=$device.DesiredPlayer; Status=if ($device.MappingConfirmed) { 'confirmed' } elseif ($device.DesiredPlayer) { 'session-only-unconfirmed-identity' } else { 'needs-assignment' }; Type='ProfileMapping' })
        foreach ($check in @('RuntimeSlot','Calibration','Aim','Trigger')) {
            $current = $null
            foreach ($entry in $Session.Confirmations) {
                if ($entry.DeviceKey -eq $device.DeviceKey -and $entry.Check -eq $check -and $entry.SessionId -eq $Session.SessionId -and
                    $entry.DeviceFingerprint -eq $device.CurrentFingerprint -and $entry.ConfigFingerprint -eq $Session.ConfigFingerprint -and $entry.ConfigStatus -eq $Session.ConfigStatus -and $configFresh -and
                    [string]$entry.RuntimeGunmoteSlot -ceq [string]$device.RuntimeGunmoteSlot) { $current = $entry; break }
            }
            $status = if ($current) { 'user-confirmed-current' } else { 'needs-user-confirmation' }
            if (-not $current -and @($Session.Confirmations | Where-Object { (($_.DeviceKey -eq $device.DeviceKey) -or ($_.DeviceMac -and $_.DeviceMac -eq $device.Mac)) -and $_.Check -eq $check }).Count -gt 0) { $status = 'stale-retest-required' }
            if (-not $current -and @($Session.HistoricalConfirmations | Where-Object { $_.DeviceMac -eq $device.Mac -and $_.Check -eq $check }).Count -gt 0) { $status = 'historical-retest-required' }
            $steps.Add([pscustomobject]@{
                Id=('device-{0}' -f $check.ToLowerInvariant()); DeviceKey=$device.DeviceKey
                Check=$check; DesiredPlayer=$device.DesiredPlayer; RuntimeGunmoteSlot=$device.RuntimeGunmoteSlot
                Status=$status; Type='UserAttestation'; EvidenceSource=if ($current) { $current.EvidenceSource } else { $null }
                Message= switch ($check) {
                    'RuntimeSlot' { 'Connect one controller at a time; identify its physical rumble/LED response and record the observed Gunmote runtime slot.' }
                    'Calibration' { 'Manually calibrate this controller for the desired player.' }
                    'Aim' { 'Aim at the target and confirm the cursor/aim response for this physical controller.' }
                    'Trigger' { 'Press the trigger and confirm the intended target responds for this physical controller.' }
                }
            })
        }
    }
    $allChecksCurrent = $Session.Devices.Count -gt 0 -and $configFresh -and @($steps | Where-Object { $_.Type -eq 'UserAttestation' -and $_.Status -ne 'user-confirmed-current' }).Count -eq 0
    [pscustomobject]@{
        Steps = @($steps.ToArray())
        WorkflowCompleteByUserAttestation = $allChecksCurrent
        ReadinessStatus = if ($allChecksCurrent) { 'user-attested; operation not independently verified' } else { 'not verified' }
        Ready = $false
        ConfigStatus = $config.Status
        CurrentConfigFingerprint = $config.Fingerprint
        ConfigFresh = $configFresh
        ChecksCompleteByUserAttestation = $allChecksCurrent
    }
}

function Set-HotwmSessionPlayerAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session, [Parameter(Mandatory=$true)][string]$DeviceKey, [Parameter(Mandatory=$true)][ValidateSet(1,2)][int]$Player)
    Assert-HotwmLiveSetupSession $Session
    $device = @($Session.Devices | Where-Object DeviceKey -CEQ $DeviceKey)
    if ($device.Count -ne 1) { throw 'Device key is missing or ambiguous in this connection snapshot.' }
    if (@($Session.Devices | Where-Object { $_.DeviceKey -cne $DeviceKey -and $_.DesiredPlayer -eq $Player }).Count -gt 0) { throw "Desired player $Player is already assigned in this session." }
    $device = $device[0]
    $candidateMappings = @($Session.Mappings)
    $candidateSessionOnly = @($Session.SessionOnlyAssignments)
    if ($device.IdentityConfirmed -and $device.Mac) {
        $candidateMappings = @(ConvertTo-HotwmValidatedDesiredMappings -Mappings (@($Session.Mappings | Where-Object Mac -ne $device.Mac) + @([pscustomobject]@{ Mac=$device.Mac; Player=$Player })))
        $candidateSessionOnly = @($Session.SessionOnlyAssignments | Where-Object DeviceKey -ne $DeviceKey)
    } else {
        $candidateSessionOnly = @($Session.SessionOnlyAssignments | Where-Object DeviceKey -ne $DeviceKey) + @([pscustomobject]@{ DeviceKey=$DeviceKey; Player=$Player })
    }
    # Commit the in-memory changes only after all candidate mappings have validated.
    $device.DesiredPlayer = $Player
    $device.Player = $Player
    $Session.Mappings = $candidateMappings
    $Session.SessionOnlyAssignments = $candidateSessionOnly
    $device.MappingConfirmed = [bool]($device.IdentityConfirmed -and $device.Mac)
    $device.MappingScope = if ($device.MappingConfirmed) { 'persistent-desired-MAC' } else { 'session-only-unconfirmed-identity' }
    $Session.Confirmations = @($Session.Confirmations | Where-Object DeviceKey -ne $DeviceKey)
    return $device
}

function Confirm-HotwmSetupObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Session,
        [Parameter(Mandatory=$true)][string]$DeviceKey,
        [Parameter(Mandatory=$true)][ValidateSet('RuntimeSlot','Calibration','Aim','Trigger')][string]$Check,
        [Parameter(Mandatory=$true)][scriptblock]$ConfirmationCallback
    )
    Assert-HotwmLiveSetupSession $Session
    $device = @($Session.Devices | Where-Object DeviceKey -CEQ $DeviceKey)
    if ($device.Count -ne 1) { throw 'Device key is missing or ambiguous in this connection snapshot.' }
    $device = $device[0]
    if (-not $device.DesiredPlayer) { throw 'Assign a desired player before recording a device check.' }
    $beforeConfig = Get-HotwmConfigFingerprint -ConfigPath $Session.ConfigPath
    if ([string]$beforeConfig.Status -cne [string]$Session.ConfigStatus -or [string]$beforeConfig.Fingerprint -cne [string]$Session.ConfigFingerprint) { throw 'Configuration changed or became unavailable; refresh the setup session before confirming this check.' }
    $beforeSessionId = [string]$Session.SessionId
    $beforeSnapshotId = [string]$Session.ConnectionSnapshotId
    $beforeDeviceFingerprint = [string]$device.CurrentFingerprint
    $beforeDesiredPlayer = [int]$device.DesiredPlayer
    $beforeRuntimeSlot = $device.RuntimeGunmoteSlot
    if ($Check -ne 'RuntimeSlot') {
        $checklist = Get-HotwmSetupChecklist -Session $Session
        $slotStep = @($checklist.Steps | Where-Object { $_.DeviceKey -eq $DeviceKey -and $_.Check -eq 'RuntimeSlot' -and $_.Status -eq 'user-confirmed-current' })
        if ($slotStep.Count -ne 1) { throw 'Identify and confirm the actual Gunmote runtime slot before calibration or target checks.' }
    }
    $prompt = switch ($Check) {
        'RuntimeSlot' { "Did you identify the physical controller and confirm it uses Gunmote runtime slot 1 or 2 for desired Player $($device.DesiredPlayer)? Return a confirmation object with Confirmed and RuntimeSlot." }
        'Calibration' { "Did you manually calibrate this controller for desired Player $($device.DesiredPlayer)?" }
        'Aim' { "Did you aim at a target and confirm the aim response for desired Player $($device.DesiredPlayer)?" }
        'Trigger' { "Did you press the trigger and confirm the intended target response for desired Player $($device.DesiredPlayer)?" }
    }
    $response = & $ConfirmationCallback $prompt $device
    $afterConfig = Get-HotwmConfigFingerprint -ConfigPath $Session.ConfigPath
    if ([string]$afterConfig.Status -cne [string]$beforeConfig.Status -or [string]$afterConfig.Fingerprint -cne [string]$beforeConfig.Fingerprint -or
        $Session.SessionId -cne $beforeSessionId -or $Session.ConnectionSnapshotId -cne $beforeSnapshotId -or
        $device.CurrentFingerprint -cne $beforeDeviceFingerprint -or $device.DesiredPlayer -ne $beforeDesiredPlayer -or
        [string]$device.RuntimeGunmoteSlot -cne [string]$beforeRuntimeSlot) {
        throw 'Setup state changed while the confirmation prompt was open; discard that response and retest.'
    }
    if ($Check -eq 'RuntimeSlot') {
        $runtimeSlot = 0
        if ($null -eq $response -or -not $response.Confirmed -or -not [int]::TryParse([string]$response.RuntimeSlot, [ref]$runtimeSlot) -or $runtimeSlot -notin @(1,2)) {
            throw 'Runtime slot requires an explicit callback confirmation and observed slot 1 or 2.'
        }
        if (@($Session.Devices | Where-Object { $_.DeviceKey -cne $DeviceKey -and $_.RuntimeGunmoteSlot -eq $runtimeSlot }).Count -gt 0) { throw "Runtime slot $runtimeSlot is already identified for another device in this session." }
    } elseif (-not [bool]$response) { throw 'The UI confirmation callback did not confirm the check.' }
    $config = $afterConfig
    $entry = [pscustomobject]@{
        DeviceKey=$DeviceKey; DeviceMac=$device.Mac; DesiredPlayer=$device.DesiredPlayer
        RuntimeGunmoteSlot=if ($Check -eq 'RuntimeSlot') { $runtimeSlot } else { $device.RuntimeGunmoteSlot }
        Check=$Check; EvidenceSource='UserConfirmed'; ConfirmedAtUtc=[DateTime]::UtcNow.ToString('o')
        SessionId=$Session.SessionId; ConnectionSnapshotId=$Session.ConnectionSnapshotId; ConfigStatus=$config.Status
        DeviceFingerprint=$device.CurrentFingerprint; ConfigFingerprint=$config.Fingerprint
    }
    if ($Check -eq 'RuntimeSlot' -and [string]$device.RuntimeGunmoteSlot -cne [string]$runtimeSlot) {
        # A changed runtime slot means prior calibration and target checks may describe a different controller.
        # Drop those attestations so switching back to an earlier slot can never revive them.
        $Session.Confirmations = @($Session.Confirmations | Where-Object { $_.DeviceKey -ne $DeviceKey -or $_.Check -notin @('Calibration','Aim','Trigger') })
    }
    $Session.Confirmations = @($Session.Confirmations | Where-Object { $_.DeviceKey -ne $DeviceKey -or $_.Check -ne $Check }) + @($entry)
    if ($Check -eq 'RuntimeSlot') { $device.RuntimeGunmoteSlot = $runtimeSlot }
    return $entry
}

function Refresh-HotwmSetupSession {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session, [object[]]$DeviceRecords, [string]$ConfigPath)
    Assert-HotwmLiveSetupSession $Session
    $oldConfigPath = $Session.ConfigPath
    if ($PSBoundParameters.ContainsKey('ConfigPath')) { $oldConfigPath = $ConfigPath }
    $mapped = if ($PSBoundParameters.ContainsKey('DeviceRecords')) {
        Get-HotwmMappedDiscovery -DeviceRecords $DeviceRecords -Mappings $Session.Mappings
    } else { Get-HotwmMappedDiscovery -Mappings $Session.Mappings }
    $snapshotId = [Guid]::NewGuid().ToString('N')
    $Session.ConnectionSnapshotId = $snapshotId
    $Session.Discovery = $mapped.Discovery
    $Session.Devices = @(foreach ($device in $mapped.Devices) {
        $copy = [ordered]@{}
        foreach ($property in $device.PSObject.Properties) { $copy[$property.Name] = $property.Value }
        $copy['DeviceKey'] = [string]$device.InstanceId
        if (-not $copy.Contains('MappingScope')) { $copy['MappingScope'] = if ($device.MappingConfirmed) { 'persistent-desired-MAC' } else { 'unassigned' } }
        $copy['RuntimeGunmoteSlot'] = $null
        $copy['CurrentFingerprint'] = Get-HotwmWizardDeviceFingerprint -Device $device -SnapshotId $snapshotId
        [pscustomobject]$copy
    })
    $Session.Confirmations = @($Session.Confirmations) # old snapshot records remain historical/stale and cannot match.
    $config = Get-HotwmConfigFingerprint -ConfigPath $oldConfigPath
    $Session.ConfigPath = $config.Path
    $Session.ConfigStatus = $config.Status
    $Session.ConfigFingerprint = $config.Fingerprint
    return $Session
}

function New-HotwmSetupSessionAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Session, [Parameter(Mandatory=$true)][string]$Path)
    Assert-HotwmLiveSetupSession $Session
    $config = Get-HotwmConfigFingerprint -ConfigPath $Session.ConfigPath
    if ([string]$config.Status -cne [string]$Session.ConfigStatus -or [string]$config.Fingerprint -cne [string]$Session.ConfigFingerprint) { throw 'Configuration changed or became unavailable; refresh the setup session before saving.' }
    $canonicalPath = [System.IO.Path]::GetFullPath($Path)
    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $Session.Root '.hotwm-setup.json'))
    if (-not [string]::Equals($canonicalPath.TrimEnd('\','/'), $expectedPath.TrimEnd('\','/'), [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Setup state can only be saved to .hotwm-setup.json directly inside the selected folder.' }
    if (Test-Path -LiteralPath $canonicalPath -PathType Leaf) { $null = Import-HotwmSetupState -Path $canonicalPath -Root $Session.Root }
    $mappings = @(ConvertTo-HotwmValidatedDesiredMappings -Mappings @($Session.Mappings))
    $confirmations = foreach ($entry in $Session.Confirmations) {
        [pscustomobject]@{
            DeviceMac=$entry.DeviceMac; DesiredPlayer=$entry.DesiredPlayer; RuntimeGunmoteSlot=$entry.RuntimeGunmoteSlot
            Check=$entry.Check; EvidenceSource=$entry.EvidenceSource; ConfirmedAtUtc=$entry.ConfirmedAtUtc
            SessionId=$entry.SessionId; ConnectionSnapshotId=$entry.ConnectionSnapshotId; ConfigStatus=$entry.ConfigStatus
            DeviceFingerprint=$entry.DeviceFingerprint; ConfigFingerprint=$entry.ConfigFingerprint
        }
    }
    $state = [ordered]@{
        SchemaVersion=1; Root=$Session.Root; Mode=$Session.Mode; DesiredMappings=$mappings
        HistoricalConfirmations=@($confirmations)
        SavedAtUtc=[DateTime]::UtcNow.ToString('o')
    }
    New-HotwmFileAction -Path $canonicalPath -Content (ConvertTo-Json -InputObject $state -Depth 30) -Explanation 'Save desired Wiimote MAC-to-player mappings and historical user-check evidence'
}

function Import-HotwmSetupState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Root)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Setup state file does not exist.' }
    try { $state = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($Path), [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Setup state file is malformed JSON.' }
    if ($null -eq $state -or $state -is [array] -or $state -is [string] -or $state.SchemaVersion -ne 1) { throw 'Unsupported setup state schema.' }
    $allowed = @('SchemaVersion','Root','Mode','DesiredMappings','HistoricalConfirmations','SavedAtUtc')
    if (@($state.PSObject.Properties | Where-Object { $_.Name -notin $allowed }).Count -gt 0 -or @($allowed | Where-Object { $null -eq $state.PSObject.Properties[$_] }).Count -gt 0) { throw 'Setup state contains unknown or missing schema fields.' }
    $canonicalRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not [string]::Equals(([System.IO.Path]::GetFullPath([string]$state.Root)).TrimEnd('\','/'), $canonicalRoot.TrimEnd('\','/'), [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Saved setup state belongs to a different root folder.' }
    $expectedPath = [System.IO.Path]::GetFullPath((Join-Path $canonicalRoot '.hotwm-setup.json'))
    if (-not [string]::Equals(([System.IO.Path]::GetFullPath($Path)).TrimEnd('\','/'), $expectedPath.TrimEnd('\','/'), [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Setup state must be the dedicated .hotwm-setup.json file in the selected root.' }
    if ($state.Mode -cnotin @('Quick','Custom','Expert')) { throw 'Saved setup mode is invalid.' }
    $mappings = ConvertTo-HotwmValidatedDesiredMappings -Mappings @($state.DesiredMappings)
    $history = foreach ($entry in @($state.HistoricalConfirmations)) {
        if ($entry.Check -notin @('RuntimeSlot','Calibration','Aim','Trigger')) { continue }
        [pscustomobject]@{
            DeviceMac=$entry.DeviceMac; DesiredPlayer=$entry.DesiredPlayer; RuntimeGunmoteSlot=$entry.RuntimeGunmoteSlot
            Check=$entry.Check; EvidenceSource='UntrustedHistorical'; Historical=$true; Current=$false
        }
    }
    [pscustomobject]@{
        SchemaVersion=1; Root=$canonicalRoot; Mode=$state.Mode
        DesiredMappings=@($mappings); HistoricalConfirmations=@($history)
        ImportStatus='validated historical setup state; confirmations require fresh retest'
    }
}
