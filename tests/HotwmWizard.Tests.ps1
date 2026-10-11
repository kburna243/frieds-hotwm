$script:wizardRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:wizardRoot 'src\HotwmSetup.ps1')
. (Join-Path $script:wizardRoot 'src\HotwmDevices.ps1')
. (Join-Path $script:wizardRoot 'src\HotwmWizard.ps1')

Describe 'hotwm guided setup session state' {
    BeforeEach {
        $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hotwm-wizard-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory((Join-Path $script:testRoot 'config'))
        $script:configPath = Join-Path $script:testRoot 'config\hotw.json'
        [IO.File]::WriteAllText($script:configPath, '{"global":{"hold_ms":150}}', (New-Object System.Text.UTF8Encoding($false)))
        $script:records = @(
            @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\7&1'; Status='OK' },
            @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_001122334455\7&2'; Status='OK' }
        )
    }
    AfterEach { Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue }

    It 'creates Quick, Custom, and Expert sessions with the same engine and unknown folder layout' {
        foreach ($mode in @('Quick','Custom','Expert')) {
            $session = New-HotwmSetupSession -Root $script:testRoot -Mode $mode -DeviceRecords $script:records -ConfigPath $script:configPath -DependencyRecords @(@{ Name='Python'; Status='detected'; Message='observed' })
            $session.Mode | Should Be $mode
            $session.WorkflowEngine | Should Be 'shared'
            $session.LayoutStatus | Should Be 'unknown'
            $session.ConfigStatus | Should Be 'observed'
            $session.Ready | Should Be $false
            @($session.DependencyStatus | Where-Object Name -eq 'Python').Count | Should Be 1
        }
    }

    It 'starts with an identified first controller when there are no saved mappings without marking it ready' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @()

        @($session.Devices).Count | Should Be 1
        $session.Devices[0].Mac | Should Be 'AA:BB:CC:DD:EE:FF'
        $session.Devices[0].DesiredPlayer | Should Be $null
        $session.Devices[0].MappingConfirmed | Should Be $false
        @($session.Mappings).Count | Should Be 0
        $session.Ready | Should Be $false
    }

    It 'rejects a missing setup folder and ambiguous persistent mapping inputs' {
        { New-HotwmSetupSession -Root (Join-Path $script:testRoot 'missing') -Mode Quick -DeviceRecords @() } | Should Throw
        { New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords $script:records -Mappings @(
            @{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 }, @{ Mac='AA:BB:CC:DD:EE:FF'; Player=2 }
        ) } | Should Throw
    }

    It 'matches normalized desired mappings and never confuses them with runtime slots' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Custom -DeviceRecords $script:records -ConfigPath $script:configPath -Mappings @(
            @{ Mac='00-11-22-33-44-55'; Player=1 }, @{ Mac='aa:bb:cc:dd:ee:ff'; Player=2 }
        )
        $session.Devices[0].DesiredPlayer | Should Be 2
        $session.Devices[0].RuntimeGunmoteSlot | Should Be $null
        $session.Devices[0].MappingConfirmed | Should Be $true
    }

    It 'allows an unidentifiable controller a session-only assignment but never saves a fake MAC' {
        $unknownRecord = @{ FriendlyName='Wiimote'; InstanceId='BTHENUM\DEV_INVALID\1'; Status='OK' }
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @($unknownRecord) -ConfigPath $script:configPath
        $device = Set-HotwmSessionPlayerAssignment -Session $session -DeviceKey $session.Devices[0].DeviceKey -Player 1
        $device.DesiredPlayer | Should Be 1
        $device.MappingConfirmed | Should Be $false
        $device.MappingScope | Should Be 'session-only-unconfirmed-identity'
        $action = New-HotwmSetupSessionAction -Session $session -Path (Join-Path $script:testRoot '.hotwm-setup.json')
        @((ConvertFrom-Json $action.ProposedContent).DesiredMappings).Count | Should Be 0
    }

    It 'requires callback-confirmed runtime slot before calibration and target tests' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Expert -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $key = $session.Devices[0].DeviceKey
        { Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check Calibration -ConfirmationCallback { return $true } } | Should Throw
        { Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { return $true } } | Should Throw
        $runtime = Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=2 } }
        $runtime.RuntimeGunmoteSlot | Should Be 2
        $device = $session.Devices[0]
        $device.RuntimeGunmoteSlot | Should Be 2
        foreach ($check in @('Calibration','Aim','Trigger')) {
            Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check $check -ConfirmationCallback { return $true } | Out-Null
        }
        $status = Get-HotwmSetupChecklist -Session $session
        $status.WorkflowCompleteByUserAttestation | Should Be $true
        $status.Ready | Should Be $false
        $status.ReadinessStatus | Should Match 'not independently verified'
    }

    It 'invalidates downstream checks when the runtime slot changes and rejects a callback that changes it' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Expert -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $key = $session.Devices[0].DeviceKey
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } | Out-Null
        foreach ($check in @('Calibration','Aim','Trigger')) { Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check $check -ConfirmationCallback { $true } | Out-Null }
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { [pscustomobject]@{ Confirmed=$true; RuntimeSlot=2 } } | Out-Null
        $downstream = @(Get-HotwmSetupChecklist -Session $session | ForEach-Object Steps | Where-Object { $_.Check -in @('Calibration','Aim','Trigger') })
        @($downstream | Where-Object Status -eq 'needs-user-confirmation').Count | Should Be 3
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } | Out-Null
        $returnedSlot = @(Get-HotwmSetupChecklist -Session $session | ForEach-Object Steps | Where-Object { $_.Check -in @('Calibration','Aim','Trigger') })
        @($returnedSlot | Where-Object Status -eq 'needs-user-confirmation').Count | Should Be 3
        $changeSlotDuringPrompt = {
            $session.Devices[0].RuntimeGunmoteSlot = 2
            return $true
        }.GetNewClosure()
        { Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check Calibration -ConfirmationCallback $changeSlotDuringPrompt } | Should Throw
        $session.Devices[0].RuntimeGunmoteSlot = 1
        @($session.Confirmations | Where-Object Check -eq 'Calibration').Count | Should Be 0
    }

    It 'leaves device and mappings unchanged when an assignment conflicts with an offline saved player' {
        $record = @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_001122334455\7&2'; Status='OK' }
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @($record) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $device = $session.Devices[0]
        $key = $device.DeviceKey
        $beforeMappings = ConvertTo-Json -InputObject @($session.Mappings) -Depth 5
        { Set-HotwmSessionPlayerAssignment -Session $session -DeviceKey $key -Player 1 } | Should Throw
        $device.DesiredPlayer | Should Be $null
        $device.Player | Should Be $null
        $device.MappingConfirmed | Should Be $false
        (ConvertTo-Json -InputObject @($session.Mappings) -Depth 5) | Should Be $beforeMappings
    }

    It 'invalidates all user confirmations after a device reconnect snapshot changes' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $key = $session.Devices[0].DeviceKey
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } | Out-Null
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check Calibration -ConfirmationCallback { return $true } | Out-Null
        $reconnected = @{ FriendlyName='Nintendo RVL-CNT-01'; InstanceId='BTHENUM\DEV_AABBCCDDEEFF\8&9'; Status='OK' }
        Refresh-HotwmSetupSession -Session $session -DeviceRecords @($reconnected) | Out-Null
        $checklist = Get-HotwmSetupChecklist -Session $session
        @($checklist.Steps | Where-Object Status -eq 'stale-retest-required').Count | Should BeGreaterThan 0
        $session.Devices[0].RuntimeGunmoteSlot | Should Be $null
    }

    It 'invalidates confirmations when the config file changes and treats a missing config path as unknown' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $key = $session.Devices[0].DeviceKey
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } | Out-Null
        [IO.File]::AppendAllText($script:configPath, ' ')
        (Get-HotwmSetupChecklist -Session $session).Steps | Where-Object Check -eq 'RuntimeSlot' | Select-Object -First 1 | ForEach-Object { $_.Status | Should Be 'stale-retest-required' }
        $unknown = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @() -Mappings @() 
        $unknown.ConfigStatus | Should Be 'unknown'
        (Get-HotwmSetupChecklist -Session $unknown).Ready | Should Be $false
    }

    It 'persists only stable mappings through a cancellable action and imports history as untrusted' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Custom -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        $key = $session.Devices[0].DeviceKey
        Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback { return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } | Out-Null
        $path = Join-Path $script:testRoot '.hotwm-setup.json'
        $action = New-HotwmSetupSessionAction -Session $session -Path $path
        $action.ProposedContent | Should Match 'AA:BB:CC:DD:EE:FF'
        $declined = Invoke-HotwmFileAction -Action $action -Confirm { return $false }
        $declined.Status | Should Be 'declined'
        (Test-Path -LiteralPath $path) | Should Be $false
        [IO.File]::WriteAllText($path, (New-HotwmSetupSessionAction -Session $session -Path $path).ProposedContent, (New-Object System.Text.UTF8Encoding($false)))
        $imported = Import-HotwmSetupState -Path $path -Root $script:testRoot
        $imported.DesiredMappings[0].Mac | Should Be 'AA:BB:CC:DD:EE:FF'
        $imported.HistoricalConfirmations[0].EvidenceSource | Should Be 'UntrustedHistorical'
        $next = New-HotwmSetupSession -Root $script:testRoot -Mode Custom -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -SavedState $imported
        (Get-HotwmSetupChecklist -Session $next).Ready | Should Be $false
        (Get-HotwmSetupChecklist -Session $next).Steps | Where-Object Status -eq 'historical-retest-required' | Should Not BeNullOrEmpty
    }

    It 'rejects imported duplicate mappings and a state associated with another root' {
        $path = Join-Path $script:testRoot '.hotwm-setup.json'
        $state = [pscustomobject]@{ SchemaVersion=1; Root=$script:testRoot; Mode='Quick'; DesiredMappings=@(
            @{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 }, @{ Mac='00:11:22:33:44:55'; Player=1 }
        ); HistoricalConfirmations=@(); SavedAtUtc=[DateTime]::UtcNow.ToString('o') }
        [IO.File]::WriteAllText($path, (ConvertTo-Json $state -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        { Import-HotwmSetupState -Path $path -Root $script:testRoot } | Should Throw
        $state.DesiredMappings = @()
        $state.Root = Join-Path $script:testRoot 'other'
        [IO.File]::WriteAllText($path, (ConvertTo-Json $state -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        { Import-HotwmSetupState -Path $path -Root $script:testRoot } | Should Throw
    }

    It 'rejects general config targets and blocks confirmation if config changes during the prompt' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Custom -DeviceRecords @($script:records[0]) -ConfigPath $script:configPath -Mappings @(@{ Mac='AA:BB:CC:DD:EE:FF'; Player=1 })
        { New-HotwmSetupSessionAction -Session $session -Path $script:configPath } | Should Throw
        $key = $session.Devices[0].DeviceKey
        $callback = {
            [IO.File]::AppendAllText($script:configPath, ' ')
            return [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 }
        }.GetNewClosure()
        { Confirm-HotwmSetupObservation -Session $session -DeviceKey $key -Check RuntimeSlot -ConfirmationCallback $callback } | Should Throw
        @($session.Confirmations).Count | Should Be 0
    }

    It 'rejects an existing dedicated state file with an unexpected schema without replacing it' {
        $session = New-HotwmSetupSession -Root $script:testRoot -Mode Quick -DeviceRecords @() -ConfigPath $script:configPath
        $path = Join-Path $script:testRoot '.hotwm-setup.json'
        [IO.File]::WriteAllText($path, '{"SchemaVersion":1,"Root":"' + $script:testRoot + '","unexpected":true}', (New-Object System.Text.UTF8Encoding($false)))
        $before = [IO.File]::ReadAllText($path)
        { New-HotwmSetupSessionAction -Session $session -Path $path } | Should Throw
        [IO.File]::ReadAllText($path) | Should Be $before
    }
}
