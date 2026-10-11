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
        elseif ($candidate -match '(?i)^BTHENUM\\.*&([0-9A-F]{12})_C00000000$') {
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

function Get-HotwmDevicePropertyValue {
    param([object]$DeviceRecord, [string]$KeyName)
    if ($DeviceRecord.ParentInstanceId -and $KeyName -eq 'DEVPKEY_Device_Parent') { return [string]$DeviceRecord.ParentInstanceId }
    foreach ($property in @($DeviceRecord.Properties)) {
        if ([string]$property.KeyName -eq $KeyName) { return [string]$property.Data }
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
                $isNintendoHid = $record.InstanceId -match '(?i)^HID\\\{00001124-0000-1000-8000-00805F9B34FB\}_VID&0002057E_PID&03(?:06|30)(?:&|\\|$)'
                $isNamedBluetoothWiimote = $record.InstanceId -match '^(?i)BTH(?:ENUM|LEDEVICE)\\' -and
                    ($record.FriendlyName -match '(?i)Wiimote|RVL-CNT-01|Nintendo RVL' -or $record.InstanceId -match '(?i)RVL-CNT-01|Nintendo.*Wiimote')
                if (-not $isNintendoHid -and -not $isNamedBluetoothWiimote) { continue }
                try {
                    if ($isNintendoHid) {
                        $parent = Get-PnpDeviceProperty -InstanceId $record.InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
                        $record | Add-Member -NotePropertyName Properties -NotePropertyValue @($parent) -Force
                    } else {
                        $record | Add-Member -NotePropertyName Properties -NotePropertyValue @(
                            Get-PnpDeviceProperty -InstanceId $record.InstanceId -ErrorAction Stop
                        ) -Force
                    }
                } catch { }
            }
        } catch { $queryAvailable = $false }
    }

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $barDetected = $false
    foreach ($record in $records) {
        $name = [string]$record.FriendlyName
        $instanceId = [string]$record.InstanceId
        $isBluetooth = $instanceId -match '^(?i)BTH(?:ENUM|LEDEVICE)\\'
        $isWiimote = ($name -match '(?i)Wiimote|RVL-CNT-01|Nintendo RVL') -or
            ($instanceId -match '(?i)RVL-CNT-01|Nintendo.*Wiimote')
        $isNintendoHid = $instanceId -match '(?i)^HID\\\{00001124-0000-1000-8000-00805F9B34FB\}_VID&0002057E_PID&03(?:06|30)(?:&|\\|$)'
        if ($name -match '(?i)DolphinBar') { $barDetected = $true }
        if ($record.Status -ne 'OK') { continue }
        if ($isBluetooth -and $isWiimote) {
            $mac = ConvertTo-HotwmBluetoothMac -DeviceRecord $record
            $candidates.Add([pscustomobject]@{ Mac=$mac; Source='BluetoothPnP'; DisplayName=$name; InstanceId=$instanceId; ParentInstanceId=$null })
        } elseif ($isNintendoHid) {
            $parentId = Get-HotwmDevicePropertyValue -DeviceRecord $record -KeyName 'DEVPKEY_Device_Parent'
            $mac = if ($parentId) { ConvertTo-HotwmBluetoothMac -DeviceRecord ([pscustomobject]@{ InstanceId=$parentId }) } else { $null }
            $displayName = if ($name) { $name } else { 'Nintendo Wiimote HID controller' }
            $candidates.Add([pscustomobject]@{ Mac=$mac; Source='NintendoHidParent'; DisplayName=$displayName; InstanceId=$instanceId; ParentInstanceId=$parentId })
        }
    }

    $discovered = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($candidates | Where-Object { -not $_.Mac })) {
        $discovered.Add([pscustomobject]@{
            Mac = $null; DisplayName = $item.DisplayName; InstanceId = $item.InstanceId
            InstanceIds = @($item.InstanceId); IdentitySources = @($item.Source); Detected = $true
            IdentityConfirmed = $false; DesiredPlayer = $null; Player = $null; RuntimeGunmoteSlot = $null
            MappingConfirmed = $false; ManuallyCalibrated = $false; Tested = $false; Ready = $false
        })
    }
    foreach ($group in @($candidates | Where-Object { $_.Mac } | Group-Object Mac)) {
        $items = @($group.Group)
        $btItems = @($items | Where-Object Source -eq 'BluetoothPnP')
        $hidItems = @($items | Where-Object Source -eq 'NintendoHidParent')
        $canCollapseAliases = $items.Count -eq 1 -or
            ($btItems.Count -le 1 -and $hidItems.Count -gt 0 -and
                @($hidItems | Where-Object { $_.ParentInstanceId -and (ConvertTo-HotwmBluetoothMac -DeviceRecord ([pscustomobject]@{ InstanceId=$_.ParentInstanceId })) -eq $group.Name }).Count -eq $hidItems.Count -and
                (($btItems.Count -eq 1) -or @($hidItems.ParentInstanceId | Select-Object -Unique).Count -eq 1))
        if ($canCollapseAliases) {
            $primary = if ($hidItems.Count -gt 0) { $hidItems[0] } else { $btItems[0] }
            $sources = @($items | Select-Object -ExpandProperty Source -Unique)
            $ids = @($items | Select-Object -ExpandProperty InstanceId -Unique)
            $discovered.Add([pscustomobject]@{
                Mac = $group.Name
                DisplayName = $primary.DisplayName
                InstanceId = $primary.InstanceId
                InstanceIds = $ids
                IdentitySources = $sources
                Detected = $true
                IdentityConfirmed = $true
                DesiredPlayer = $null
                Player = $null
                RuntimeGunmoteSlot = $null
                MappingConfirmed = $false
                ManuallyCalibrated = $false
                Tested = $false
                Ready = $false
            })
        } else {
            foreach ($item in $items) {
                $discovered.Add([pscustomobject]@{
                    Mac = $null
                    DisplayName = $item.DisplayName
                    InstanceId = $item.InstanceId
                    InstanceIds = @($item.InstanceId)
                    IdentitySources = @($item.Source)
                    Detected = $true
                    IdentityConfirmed = $false
                    DesiredPlayer = $null
                    Player = $null
                    RuntimeGunmoteSlot = $null
                    MappingConfirmed = $false
                    ManuallyCalibrated = $false
                    Tested = $false
                    Ready = $false
                })
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
        $copy['DesiredPlayer'] = $player
        $copy['Player'] = $player # Compatibility alias; this is the desired profile player, never a runtime slot.
        $copy['RuntimeGunmoteSlot'] = $null
        $copy['MappingConfirmed'] = $confirmed
        [pscustomobject]$copy
    }
    return ,@($result)
}
