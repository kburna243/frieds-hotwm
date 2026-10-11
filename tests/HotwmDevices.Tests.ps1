$script:deviceModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\HotwmDevices.ps1'
. $script:deviceModule

Describe 'hotwm read-only device identity and player mapping' {
    It 'matches persistent mappings regardless of device enumeration order' {
        $devices = @(Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_001122334455\7&2'; Status='OK' }
        )).Devices
        $result = Resolve-HotwmPlayerMappings -Devices @($devices[1], $devices[0]) -Mappings @(
            @{ Mac='AA:BB:CC:DD:EE:FF'; Player=2 }, @{ Mac='00:11:22:33:44:55'; Player=1 }
        )
        $result[0].DesiredPlayer | Should Be 1
        $result[1].DesiredPlayer | Should Be 2
        $result[0].MappingConfirmed | Should Be $true
        $result[0].RuntimeGunmoteSlot | Should Be $null
        $result[0].Ready | Should Be $false
    }

    It 'recognizes a reconnect by stable Bluetooth MAC despite a changed instance suffix' {
        $first = Get-HotwmDeviceDiscovery -DeviceRecords @(@{ FriendlyName='RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' })
        $again = Get-HotwmDeviceDiscovery -DeviceRecords @(@{ FriendlyName='RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\8&9'; Status='OK' })
        $first.Devices[0].Mac | Should Be $again.Devices[0].Mac
        $first.Devices[0].Mac | Should Be 'AA:BB:CC:DD:EE:FF'
    }

    It 'normalizes explicit colon and hyphen address fields and rejects invalid addresses' {
        (ConvertTo-HotwmBluetoothMac @{ BluetoothAddress='aa-bb-cc-dd-ee-ff' }) | Should Be 'AA:BB:CC:DD:EE:FF'
        (ConvertTo-HotwmBluetoothMac @{ BluetoothAddress='00:00:00:00:00:00' }) | Should Be $null
        (ConvertTo-HotwmBluetoothMac @{ BluetoothAddress='FF:FF:FF:FF:FF:FF' }) | Should Be $null
        (ConvertTo-HotwmBluetoothMac @{ BluetoothAddress='01:00:5E:00:00:01' }) | Should Be $null
        (ConvertTo-HotwmBluetoothMac @{ InstanceId='USB\DEV_AABBCCDDEEFF\1' }) | Should Be $null
    }

    It 'leaves missing and invalid Bluetooth identifiers unconfirmed' {
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_NOT-A-MAC\7'; Status='OK' },
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\'; Status='OK' }
        )
        @($result.Devices | Where-Object IdentityConfirmed).Count | Should Be 0
    }

    It 'marks duplicate discovered identities as ambiguous' {
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&2'; Status='OK' }
        )
        @($result.Devices | Where-Object IdentityConfirmed).Count | Should Be 0
        @($result.Devices | Where-Object Mac).Count | Should Be 0
    }

    It 'rejects duplicate MAC mappings and duplicate player assignments' {
        $devices = @(Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_001122334455\7&2'; Status='OK' }
        )).Devices
        $result = Resolve-HotwmPlayerMappings -Devices $devices -Mappings @(
            @{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 }, @{ Mac='AABBCCDDEEFF'; Player=2 },
            @{ Mac='00:11:22:33:44:55'; Player=1 }
        )
        @($result | Where-Object MappingConfirmed).Count | Should Be 0
    }

    It 'rejects duplicate device records and player slots outside one or two' {
        $devices = @(Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_001122334455\7&2'; Status='OK' }
        )).Devices
        $duplicateInput = @($devices[0], $devices[0])
        $result = Resolve-HotwmPlayerMappings -Devices $duplicateInput -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        @($result | Where-Object MappingConfirmed).Count | Should Be 0
        $invalidSlot = Resolve-HotwmPlayerMappings -Devices @($devices[1]) -Mappings @(@{ Mac='00:11:22:33:44:55'; Player=3 })
        $invalidSlot[0].MappingConfirmed | Should Be $false
        $devices[1].MappingConfirmed | Should Be $false
    }

    It 'reports a DolphinBar without inventing an individual Wiimote MAC' {
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='DolphinBar'; InstanceId='USB\VID_057E&PID_0306\1'; Status='OK' }
        )
        $result.Detected | Should Be $true
        $result.DolphinBarDetected | Should Be $true
        $result.Devices.Count | Should Be 0
        $result.Message | Should Match 'individual Wiimote identity is not exposed'
    }

    It 'extracts the stable MAC from a supported Nintendo HID parent identifier' {
        $parent = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0306&AABBCCDDEEFF_C00000000'
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='HID-compliant game controller'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0306&1'; Status='OK'; Properties=@(@{ KeyName='DEVPKEY_Device_Parent'; Data=$parent }) }
        )
        $result.Devices.Count | Should Be 1
        $result.Devices[0].Mac | Should Be 'AA:BB:CC:DD:EE:FF'
        (@($result.Devices[0].IdentitySources) -contains 'NintendoHidParent') | Should Be $true
        $result.Devices[0].IdentityConfirmed | Should Be $true
        $result.Devices[0].Ready | Should Be $false
    }

    It 'rejects unrelated HID devices and Bluetooth adapters' {
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Other HID device'; InstanceId='HID\{11111111-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0306&1'; Status='OK'; ParentInstanceId='BTHENUM\{x}&AABBCCDDEEFF_C00000000' },
            @{ FriendlyName='Bluetooth Device'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' }
        )
        $result.Devices.Count | Should Be 0
    }

    It 'keeps a known Nintendo HID device detected but identity-unconfirmed when parent is missing' {
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='HID-compliant game controller'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0330&1'; Status='OK' }
        )
        $result.Detected | Should Be $true
        $result.Devices.Count | Should Be 1
        $result.Devices[0].IdentityConfirmed | Should Be $false
        $result.Devices[0].Mac | Should Be $null
        $result.Devices[0].Ready | Should Be $false
    }

    It 'collapses a Bluetooth device and its proven Nintendo HID parent into one controller' {
        $parent = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0330&AABBCCDDEEFF_C00000000'
        $result = Get-HotwmDeviceDiscovery -DeviceRecords @(
            @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='HID-compliant game controller'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0330&1'; Status='OK'; ParentInstanceId=$parent }
        )
        $result.Devices.Count | Should Be 1
        $result.Devices[0].Mac | Should Be 'AA:BB:CC:DD:EE:FF'
        (@($result.Devices[0].IdentitySources) -contains 'BluetoothPnP') | Should Be $true
        (@($result.Devices[0].IdentitySources) -contains 'NintendoHidParent') | Should Be $true
        $result.Devices[0].InstanceIds.Count | Should Be 2
    }
}
