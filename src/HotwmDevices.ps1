#requires -Version 5.1
<#
.SYNOPSIS
    Read-only Bluetooth Wiimote discovery and stable player mapping helpers.
.DESCRIPTION
    PnP presence is only detection evidence. It does not prove player mapping,
    calibration, target response, or readiness. No pairing or device changes occur.
#>

function ConvertTo-HotwmBluetoothMac {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$DeviceRecord)

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($propertyName in @('InstanceId', 'DeviceID', 'DeviceId', 'BluetoothAddress', 'Address')) {
        $value = $DeviceRecord.$propertyName
        if ($value -is [string] -and $value) { $candidates.Add([pscustomobject]@{ Value=$value; IsAddress=($propertyName -in @('BluetoothAddress','Address')) }) }
    }
    if ($DeviceRecord.Properties) {
        foreach ($property in $DeviceRecord.Properties) {
            $key = [string]$property.KeyName
            if ($key -match 'Bluetooth.*Address|DeviceAddress') {
                $value = $property.Data
                if ($null -ne $value) { $candidates.Add([pscustomobject]@{ Value=[string]$value; IsAddress=$true }) }
            }
        }
    }

    foreach ($candidateRecord in $candidates) {
        $candidate = $candidateRecord.Value
        # DEV_ addresses in Bluetooth PnP instance IDs are device addresses.
        # Do not accept arbitrary 12-hex strings from names or USB identifiers.
        $hex = $null
        if ($candidate -match '(?i)^BTH(?:ENUM|LEDEVICE)\\.*?DEV_([0-9A-F]{12})(?:\\|$)') {
            $hex = $Matches[1].ToUpperInvariant()
        }
        elseif ($candidateRecord.IsAddress -and $candidate -match '(?i)^(?:0x)?([0-9A-F]{12}|[0-9A-F]{2}(?:[:-][0-9A-F]{2}){5})$') {
            $hex = $Matches[1].ToUpperInvariant()
            $hex = $hex -replace '[:-]', ''
        } else { continue }
        if ($hex -eq '000000000000' -or $hex -eq 'FFFFFFFFFFFF' -or ([Convert]::ToInt32($hex.Substring(0,2),16) -band 1)) { continue }
        if ($hex -match '^[0-9A-F]{12}$') {
            return (0,2,4,6,8,10 | ForEach-Object { $hex.Substring($_, 2) }) -join ':'
        }
    }
    return $null
}

function Get-HotwmDeviceDiscovery {
    [CmdletBinding()]
    param([object[]]$DeviceRecords)

    $records = @()
    $queryAvailable = $true
    if ($PSBoundParameters.ContainsKey('DeviceRecords')) {
        $records = @($DeviceRecords)
    } else {
        try {
            if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) { throw 'Get-PnpDevice is unavailable' }
            $records = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
            foreach ($record in $records) {
                if ($record.InstanceId -notmatch '^(?i)BTH(?:ENUM|LEDEVICE)\\' -or
                    ($record.FriendlyName -notmatch '(?i)Wiimote|RVL-CNT-01|Nintendo RVL' -and $record.InstanceId -notmatch '(?i)RVL-CNT-01|Nintendo.*Wiimote')) { continue }
                try {
                    $record | Add-Member -NotePropertyName Properties -NotePropertyValue @(
                        Get-PnpDeviceProperty -InstanceId $record.InstanceId -ErrorAction Stop
                    ) -Force
                } catch { }
            }
        } catch { $queryAvailable = $false }
    }

    $discovered = New-Object 'System.Collections.Generic.List[object]'
    $barDetected = $false
    foreach ($record in $records) {
        $name = [string]$record.FriendlyName
        $instanceId = [string]$record.InstanceId
        $isBluetooth = $instanceId -match '^(?i)BTH(?:ENUM|LEDEVICE)\\'
        $isWiimote = ($name -match '(?i)Wiimote|RVL-CNT-01|Nintendo RVL') -or
            ($instanceId -match '(?i)RVL-CNT-01|Nintendo.*Wiimote')
        if ($name -match '(?i)DolphinBar') { $barDetected = $true }
        if (-not $isBluetooth -or -not $isWiimote -or $record.Status -ne 'OK') { continue }
        $mac = ConvertTo-HotwmBluetoothMac -DeviceRecord $record
        $discovered.Add([pscustomobject]@{
            Mac = $mac
            DisplayName = $name
            InstanceId = $instanceId
            Player = $null
            Detected = $true
            IdentityConfirmed = [bool]$mac
            MappingConfirmed = $false
            ManuallyCalibrated = $false
            Tested = $false
            Ready = $false
        })
    }

    foreach ($group in @($discovered | Where-Object { $_.Mac } | Group-Object Mac)) {
        if ($group.Count -gt 1) {
            foreach ($device in $group.Group) {
                $device.IdentityConfirmed = $false
                $device.Mac = $null
            }
        }
    }
    [pscustomobject]@{
        QueryAvailable = $queryAvailable
        Detected = ([bool]$discovered.Count -or $barDetected)
        DolphinBarDetected = $barDetected
        Devices = @($discovered.ToArray())
        Message = if (-not $queryAvailable) { 'PnP discovery unavailable' }
                  elseif ($discovered.Count -eq 0 -and $barDetected) { 'DolphinBar detected; individual Wiimote identity is not exposed' }
                  elseif ($discovered.Count -eq 0) { 'No connected Bluetooth Wiimote detected' }
                  else { 'Bluetooth Wiimote presence detected; mapping and calibration are unconfirmed' }
    }
}

function Resolve-HotwmPlayerMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Devices,
        [Parameter(Mandatory=$true)][object[]]$Mappings
    )

    $normalized = @($Mappings | ForEach-Object {
        $mac = ConvertTo-HotwmBluetoothMac -DeviceRecord ([pscustomobject]@{ BluetoothAddress = $_.Mac })
        $player = 0
        if (-not [int]::TryParse([string]$_.Player, [ref]$player) -or $player -notin @(1,2)) { $mac = $null }
        [pscustomobject]@{ Mac = $mac; Player = $player }
    })
    $validMap = @($normalized | Where-Object { $_.Mac })
    $duplicateMacs = @($validMap | Group-Object Mac | Where-Object Count -gt 1 | ForEach-Object Name)
    $duplicatePlayers = @($validMap | Group-Object Player | Where-Object Count -gt 1 | ForEach-Object Name)
    $deviceGroups = @($Devices | Where-Object { $_.Mac } | Group-Object Mac)
    $duplicateDeviceMacs = @($deviceGroups | Where-Object Count -gt 1 | ForEach-Object Name)
    $result = foreach ($device in $Devices) {
        $confirmed = $false
        $player = $null
        if ($device.IdentityConfirmed -and $device.Mac -and $device.Mac -notin $duplicateDeviceMacs) {
            $matches = @($validMap | Where-Object { $_.Mac -eq $device.Mac })
            if ($matches.Count -eq 1 -and $device.Mac -notin $duplicateMacs -and [string]$matches[0].Player -notin $duplicatePlayers) {
                $confirmed = $true
                $player = $matches[0].Player
            }
        }
        $copy = [ordered]@{}
        foreach ($property in $device.PSObject.Properties) { $copy[$property.Name] = $property.Value }
        $copy['Player'] = $player
        $copy['MappingConfirmed'] = $confirmed
        [pscustomobject]$copy
    }
    return ,@($result)
}
