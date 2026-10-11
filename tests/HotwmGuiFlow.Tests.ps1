Describe 'Hotwm first setup flow' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:dashboardScript = Join-Path $script:repoRoot 'gui\HotwmDashboard.ps1'
        . (Join-Path $script:repoRoot 'src\HotwmSetup.ps1')
        $script:ui = & $script:dashboardScript -NoShow
        $script:folderFixtures = Join-Path $PSScriptRoot ('.hotwm_setup_flow_' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:folderFixtures)
        $script:validTarget = Join-Path $script:folderFixtures 'RetroBat'
        $script:unknownTarget = Join-Path $script:folderFixtures 'Unknown'
        [void][IO.Directory]::CreateDirectory($script:validTarget)
        [void][IO.Directory]::CreateDirectory($script:unknownTarget)
        [IO.File]::WriteAllText((Join-Path $script:validTarget 'retrobat.exe'), '')
    }

    AfterAll {
        if ($script:ui -and $script:ui.Window) { $script:ui.Window.Close() }
        if (Test-Path -LiteralPath $script:folderFixtures) { Remove-Item -LiteralPath $script:folderFixtures -Recurse -Force }
    }

    It 'exposes folder validation, shared modes, and read-only discovery controls' {
        $script:ui.Controls.TextSetupFolder | Should Not Be $null
        $script:ui.Controls.BtnBrowseSetupFolder | Should Not Be $null
        $script:ui.Controls.BtnValidateSetupFolder | Should Not Be $null
        $script:ui.Controls.RadioQuickMode | Should Not Be $null
        $script:ui.Controls.RadioCustomMode | Should Not Be $null
        $script:ui.Controls.RadioExpertMode | Should Not Be $null
        $script:ui.Controls.BtnRefreshDiscovery | Should Not Be $null
        $script:ui.Controls.ListDiscoveredDevices | Should Not Be $null
        $script:ui.Controls.TextDiscoveryStatus.Text | Should Match 'Noch nicht geprüft'
        $script:ui.Controls.TextConfigSaveStatus | Should Not Be $null
    }

    It 'validates RetroBat folders read-only and reports unsupported targets without blocking folder selection' {
        $configBefore = $script:ui.Config
        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'nur lesend'
        $script:ui.Config | Should Be $configBefore
        $script:ui.Controls.TextSetupFolder.Text = $script:unknownTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'nicht.*erkannt'
        $script:ui.WizardSession.Session | Should Not Be $null
        $script:ui.WizardSession.Session.Ready | Should Be $false
        $script:ui.Controls.TextSetupFolder.Text = (Join-Path $script:folderFixtures 'missing')
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'nicht gefunden'
    }

    It 'clears the actionable error mascot after either kind of folder validates successfully' {
        $missing = Join-Path $script:folderFixtures 'missing-again'
        $script:ui.Controls.TextSetupFolder.Text = $missing
        (& $script:ui.ValidateFolder) | Should Be $false
        $script:ui.Controls.BrandSurprisedMascot.Visibility | Should Be ([Windows.Visibility]::Visible)

        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        (& $script:ui.ValidateFolder) | Should Be $true
        $script:ui.Controls.BrandSurprisedMascot.Visibility | Should Be ([Windows.Visibility]::Collapsed)

        $script:ui.Controls.TextSetupFolder.Text = $missing
        (& $script:ui.ValidateFolder) | Should Be $false
        $script:ui.Controls.BrandSurprisedMascot.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.TextSetupFolder.Text = $script:unknownTarget
        (& $script:ui.ValidateFolder) | Should Be $true
        $script:ui.Controls.BrandSurprisedMascot.Visibility | Should Be ([Windows.Visibility]::Collapsed)
    }

    It 'wraps the manual-attestation status at the minimum window width' {
        $script:ui.Window.Width = 850
        $script:ui.Controls.MainTabs.SelectedIndex = 0
        $script:ui.Controls.TextWizardStatus.Text = 'Alle manuellen Prüfungen wurden von dir bestätigt. Nicht unabhängig verifiziert; keine Garantie auf Spielfunktion.'
        $script:ui.Window.Show()
        try {
            $script:ui.Window.UpdateLayout()
            $script:ui.Controls.TextWizardStatus.TextWrapping | Should Be ([Windows.TextWrapping]::Wrap)
            $script:ui.Controls.TextWizardStatus.ActualWidth | Should BeGreaterThan 300
            $script:ui.Controls.TextWizardStatus.IsVisible | Should Be $true
            $script:ui.Controls.BtnConfirmTrigger.ActualWidth | Should BeGreaterThan 0
            $node = [System.Windows.DependencyObject]$script:ui.Controls.BtnConfirmTrigger
            $scrollViewer = $null
            while ($node -and -not $scrollViewer) {
                if ($node -is [System.Windows.Controls.ScrollViewer]) { $scrollViewer = $node; break }
                $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
            }
            $scrollViewer | Should Not Be $null
            $buttonBottomRight = $script:ui.Controls.BtnConfirmTrigger.TranslatePoint([Windows.Point]::new($script:ui.Controls.BtnConfirmTrigger.ActualWidth, $script:ui.Controls.BtnConfirmTrigger.ActualHeight), $scrollViewer)
            ($buttonBottomRight.X + $script:ui.Controls.BtnConfirmTrigger.Margin.Right -le $scrollViewer.ViewportWidth) | Should Be $true
        } finally { $script:ui.Window.Hide() }
    }

    It 'passes the validated RetroBat root to Kit status calls' {
        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $received = & $script:ui.KitStatus { param($root) $root }
        $received | Should Be ([IO.Path]::GetFullPath($script:validTarget))
    }

    It 'keeps tuning values shared when switching modes and changes the visible mode details' {
        $script:ui.Controls.SliderHoldMs.Value = 190
        $script:ui.Controls.RadioCustomMode.IsChecked = $true
        $script:ui.Controls.TextCustomModeDetail.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.RadioExpertMode.IsChecked = $true
        $script:ui.Controls.TextExpertModeDetail.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.RadioQuickMode.IsChecked = $true
        $script:ui.Controls.TextQuickModeDetail.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.BtnHeaderStartRelay.Visibility | Should Be ([Windows.Visibility]::Collapsed)
        $script:ui.Controls.RelayHeaderStatus.Text | Should Match 'Rückstoßdienst'
        $script:ui.Controls.SliderHoldMs.Value | Should Be 190
    }

    It 'loads the semantic theme and local mascots from any current directory' {
        $theme = $script:ui.Window.FindResource('BackgroundBrush')
        $theme.Color.ToString() | Should Be '#FF0E1B23'
        $script:ui.Controls.BrandFriendlyMascot.Source | Should Not Be $null
        $script:ui.Controls.BrandControllerMascot.Source | Should Not Be $null
        $pushError = $null
        Push-Location $env:TEMP
        try { $otherUi = & $script:dashboardScript -NoShow }
        finally { Pop-Location }
        try {
            $otherUi.Window.FindResource('TextBrush').Color.ToString() | Should Be '#FFF6F2E9'
            $otherUi.Controls.BrandFriendlyMascot.Source.UriSource.LocalPath | Should Be (Join-Path $script:repoRoot 'gui\assets\brand\character-friendly.png')
        } finally { $otherUi.Window.Close() }
    }

    It 'keeps native selections themed and explains preset purpose when the choice changes' {
        $combo = $script:ui.Controls.CmbGunmoteKind
        $combo.Template | Should Not Be $null
        $script:ui.Controls.GridGameProfiles.Columns.Count | Should BeGreaterThan 0
        $script:ui.Window.FindResource([System.Windows.Controls.DataGridRow]).TargetType | Should Be ([System.Windows.Controls.DataGridRow])
        $script:ui.Window.FindResource([System.Windows.Controls.DataGridCell]).TargetType | Should Be ([System.Windows.Controls.DataGridCell])
        $combo.SelectedItem.Description | Should Match 'ohne Zeiger'
        $combo.SelectedIndex = 1
        $combo.SelectedItem.Kind | Should Be 'Pad43'
        $script:ui.Controls.TextGunmoteKindHelp.Text | Should Match 'Analogstick.*4:3'
        $tab = $script:ui.Window.FindName('MainTabs').Items[0]
        $tab.Template | Should Not Be $null
        $script:ui.Window.FindResource('StatusWarningBrush').Color.ToString() | Should Be '#FFFFC857'
        @($script:ui.Window.FindResource([System.Windows.Controls.TextBlock]).Setters | Where-Object { $_.Property -eq [System.Windows.Controls.TextBlock]::ForegroundProperty }).Count | Should Be 0
    }

    It 'renders selected preset names in the live WPF ComboBox templates' {
        function Find-HotwmRenderedText([System.Windows.DependencyObject]$Node) {
            if ($Node -is [System.Windows.Controls.TextBlock]) { return [string]$Node.Text }
            if ($Node -is [System.Windows.Media.Visual] -or $Node -is [System.Windows.Media.Media3D.Visual3D]) {
                for ($i=0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Node); $i++) {
                    $texts = @(Find-HotwmRenderedText ([System.Windows.Media.VisualTreeHelper]::GetChild($Node,$i)))
                    if ($texts.Count) { return $texts[0] }
                }
            }
        }
        function Assert-HotwmComboDisplayedText($Combo, [int]$TabIndex, [string]$Expected) {
            $script:ui.Controls.MainTabs.SelectedIndex = $TabIndex
            $script:ui.Window.UpdateLayout()
            $Combo.BringIntoView()
            $Combo.ApplyTemplate() | Out-Null
            $script:ui.Window.UpdateLayout()
            $presenter = $Combo.Template.FindName('SelectionContent',$Combo)
            $presenter | Should Not Be $null
            $presenter.ApplyTemplate() | Out-Null
            $actual = Find-HotwmRenderedText $presenter
            $actual | Should Be $Expected
        }

        $null = & $script:ui.ProfileDispatch 'Initialize' $null
        $effect = $script:ui.Controls.CmbEffectPreset.SelectedItem
        Assert-HotwmComboDisplayedText $script:ui.Controls.CmbEffectPreset 2 ([string]$effect.Name)
        $button = $script:ui.Controls.CmbButtonTemplate.SelectedItem
        Assert-HotwmComboDisplayedText $script:ui.Controls.CmbButtonTemplate 3 ([string]$button.Name)
        $gunmote = $script:ui.Controls.CmbGunmoteKind.SelectedItem
        Assert-HotwmComboDisplayedText $script:ui.Controls.CmbGunmoteKind 3 ([string]$gunmote.DisplayTitle)
    }

    It 'keeps an inspected Quick session and its assignment when the same folder is validated again' {
        $records = @([pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01'; Status='OK' })
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=$records; DependencyRecords=@() }
        $null = & $script:ui.WizardDispatch 'Assign' @{ DeviceKey=$started.Session.Devices[0].DeviceKey; Player=1 }
        $sessionId = $started.Session.SessionId
        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.WizardSession.Session.SessionId | Should Be $sessionId
        $script:ui.WizardSession.Session.Devices[0].DesiredPlayer | Should Be 1
        $script:ui.WizardSession.Session.Ready | Should Be $false
    }

    It 'exposes guided session controls and preserves one session across modes' {
        foreach ($name in @('BtnStartWizard','BtnRefreshWizard','CmbWizardDevice','CmbWizardPlayer','CmbWizardRuntimeSlot','BtnAssignWizardPlayer','BtnConfirmRuntimeSlot','BtnConfirmCalibration','BtnConfirmAim','BtnConfirmTrigger','BtnImportWizardState','BtnSaveWizardState','ListWizardChecklist')) {
            $script:ui.Controls[$name] | Should Not Be $null
        }
        $records = @([pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01'; Status='OK' })
        $dependencies = @([pscustomobject]@{ Name='Python'; Status='detected'; Message='fixture only' })
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=$records; DependencyRecords=$dependencies }
        $started.Success | Should Be $true
        $sessionId = $started.Session.SessionId
        $started.Session.Ready | Should Be $false
        & $script:ui.WizardDispatch 'Assign' @{ DeviceKey=$started.Session.Devices[0].DeviceKey; Player=1 } | Out-Null
        $script:ui.Controls.RadioCustomMode.IsChecked = $true
        $custom = & $script:ui.WizardDispatch 'Mode' $null
        $custom.Session.SessionId | Should Be $sessionId
        $custom.Session.Devices[0].DesiredPlayer | Should Be 1
        $script:ui.Controls.RadioExpertMode.IsChecked = $true
        $expert = & $script:ui.WizardDispatch 'Mode' $null
        $expert.Session.SessionId | Should Be $sessionId
        $expert.Session.Mode | Should Be 'Expert'
        $script:ui.Controls.RadioQuickMode.IsChecked = $true
        $quick = & $script:ui.WizardDispatch 'Mode' $null
        $quick.Session.Devices[0].DesiredPlayer | Should Be 1
    }

    It 'rejects duplicate desired assignments without changing the existing mapping' {
        $records = @(
            [pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01 Player A'; Status='OK' },
            [pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334466\7&123&0&BLUETOOTHDEVICE_001122334466'; FriendlyName='Nintendo RVL-CNT-01 Player B'; Status='OK' }
        )
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=$records; DependencyRecords=@() }
        $devices = @($started.Session.Devices)
        $null = & $script:ui.WizardDispatch 'Assign' @{ DeviceKey=$devices[0].DeviceKey; Player=1 }
        $failed = & $script:ui.WizardDispatch 'Assign' @{ DeviceKey=$devices[1].DeviceKey; Player=1 }
        $failed.Success | Should Be $false
        $started.Session.Devices[0].DesiredPlayer | Should Be 1
        $started.Session.Devices[1].DesiredPlayer | Should Be $null
    }

    It 'keeps the second selected device through assignment and mode changes before checking it' {
        $records = @(
            [pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01 Player A'; Status='OK' },
            [pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334466\7&123&0&BLUETOOTHDEVICE_001122334466'; FriendlyName='Nintendo RVL-CNT-01 Player B'; Status='OK' }
        )
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=$records; DependencyRecords=@() }
        $secondKey = $started.Session.Devices[1].DeviceKey
        $script:ui.Controls.CmbWizardDevice.SelectedValue = $secondKey
        $script:ui.Controls.CmbWizardPlayer.SelectedIndex = 2
        $assigned = & $script:ui.WizardDispatch 'Assign' $null
        $assigned.Success | Should Be $true
        $script:ui.Controls.RadioExpertMode.IsChecked = $true
        $null = & $script:ui.WizardDispatch 'Mode' $null
        $script:ui.Controls.CmbWizardDevice.SelectedValue | Should Be $secondKey
        $script:ui.Controls.CmbWizardDevice.SelectedItem.DeviceKey | Should Be $secondKey
        $checked = & $script:ui.WizardDispatch 'RuntimeSlot' @{ Confirm={ param($prompt,$device) $device.DeviceKey | Should Be $secondKey; [pscustomobject]@{ Confirmed=$true; RuntimeSlot=2 } } }
        $checked.Success | Should Be $true
        $checked.Confirmation.DeviceKey | Should Be $secondKey
        $assigned.Session.Devices[0].DesiredPlayer | Should Be $null
        $assigned.Session.Devices[1].DesiredPlayer | Should Be 2
    }

    It 'blocks a save when the selected folder text changes after a session starts' {
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=@(); DependencyRecords=@() }
        $started.Success | Should Be $true
        $script:ui.Controls.TextSetupFolder.Text = $script:unknownTarget
        $save = & $script:ui.WizardDispatch 'Save' @{ Confirm={ throw 'Confirmation must not be reached for a stale folder.' } }
        $save.Success | Should Be $false
        $save.Message | Should Match 'folder changed|folder.*session|validate'
        (Test-Path -LiteralPath (Join-Path $script:validTarget '.hotwm-setup.json')) | Should Be $false
    }

    It 'requires a real runtime-slot attestation before later checks and invalidates checks after refresh' {
        $records = @([pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01'; Status='OK' })
        $started = & $script:ui.WizardDispatch 'Start' @{ Root=$script:validTarget; Mode='Quick'; DeviceRecords=$records; DependencyRecords=@() }
        $key = $started.Session.Devices[0].DeviceKey
        $null = & $script:ui.WizardDispatch 'Assign' @{ DeviceKey=$key; Player=1 }
        $blocked = & $script:ui.WizardDispatch 'Calibration' @{ DeviceKey=$key; Confirm={ return $true } }
        $blocked.Success | Should Be $false
        $runtime = & $script:ui.WizardDispatch 'RuntimeSlot' @{ DeviceKey=$key; Confirm={ param($prompt,$device) [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } }
        $runtime.Success | Should Be $true
        $calibrated = & $script:ui.WizardDispatch 'Calibration' @{ DeviceKey=$key; Confirm={ return $true } }
        $calibrated.Success | Should Be $true
        $refresh = & $script:ui.WizardDispatch 'Refresh' @{ DeviceRecords=$records }
        $refresh.Success | Should Be $true
        $checklist = & $script:ui.WizardDispatch 'Render' $null
        @($checklist.Steps | Where-Object { $_.DeviceKey -eq $key -and $_.Check -eq 'RuntimeSlot' -and $_.Status -eq 'stale-retest-required' }).Count | Should Be 1
        $refresh.Session.Ready | Should Be $false
    }

    It 'imports old observations only as history and leaves declined save untouched' {
        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $records = @([pscustomobject]@{ InstanceId='BTHENUM\DEV_001122334455\7&123&0&BLUETOOTHDEVICE_001122334455'; FriendlyName='Nintendo RVL-CNT-01'; Status='OK' })
        $statePath = Join-Path $script:validTarget '.hotwm-setup.json'
        $fixture = [ordered]@{ SchemaVersion=1; Root=[IO.Path]::GetFullPath($script:validTarget); Mode='Custom'; DesiredMappings=@([ordered]@{ Mac='00:11:22:33:44:55'; Player=1 }); HistoricalConfirmations=@([ordered]@{ DeviceMac='00:11:22:33:44:55'; DesiredPlayer=1; RuntimeGunmoteSlot=2; Check='RuntimeSlot'; ConfirmedAtUtc='2020-01-01T00:00:00Z' }); SavedAtUtc='2020-01-01T00:00:00Z' }
        [IO.File]::WriteAllText($statePath, (ConvertTo-Json -InputObject $fixture -Depth 10), [Text.Encoding]::UTF8)
        try {
            $imported = & $script:ui.WizardDispatch 'Import' @{ Root=$script:validTarget; DeviceRecords=$records; DependencyRecords=@() }
            $imported.Success | Should Be $true
            $imported.Session.Devices[0].DesiredPlayer | Should Be 1
            $script:ui.Controls.RadioCustomMode.IsChecked | Should Be $true
            $script:ui.Controls.RadioExpertMode.IsChecked | Should Be $false
            $check = & $script:ui.WizardDispatch 'Render' $null
            @($check.Steps | Where-Object { $_.Check -eq 'RuntimeSlot' -and $_.Status -eq 'historical-retest-required' }).Count | Should Be 1
            $key = $imported.Session.Devices[0].DeviceKey
            $runtime = & $script:ui.WizardDispatch 'RuntimeSlot' @{ DeviceKey=$key; Confirm={ param($prompt,$device) [pscustomobject]@{ Confirmed=$true; RuntimeSlot=1 } } }
            $runtime.Success | Should Be $true
            $script:receivedWizardProposal = $null
            $declined = & $script:ui.WizardDispatch 'Save' @{ Confirm={ param($proposal) $script:receivedWizardProposal = $proposal; return $false } }
            $declined.Success | Should Be $false
            $declined.Action.TargetPath | Should Be $statePath
            $script:receivedWizardProposal.TargetPath | Should Be $statePath
            ($script:receivedWizardProposal.ProposedContent | ConvertFrom-Json).HistoricalConfirmations.Count | Should Be 2
            $persistedStamp = (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).SavedAtUtc
            if ($persistedStamp -is [DateTime]) { $persistedStamp = $persistedStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
            [string]$persistedStamp | Should Be '2020-01-01T00:00:00Z'
        } finally { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
    }

    It 'applies only UI-controlled config values and preserves concurrent unknown fields' {
        $path = Join-Path $script:folderFixtures 'concurrent-config.json'
        $staleUiSnapshot = '{"global":{"hold_ms":100,"vendor_global":{"version":"old"}},"games":{"sample":{"rumble":false,"leds":false,"vendor_game":"old"}},"vendor_root":{"version":"old"}}'
        [IO.File]::WriteAllText($path, $staleUiSnapshot, [Text.Encoding]::UTF8)
        $uiBaseline = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $uiBaseline.global.vendor_global.version | Should Be 'old'

        # Another writer updates vendor-owned data after the UI's conceptual load.
        $latest = '{"global":{"hold_ms":120,"ammo_drop_shot":false,"vendor_global":{"version":"new"}},"games":{"sample":{"rumble":false,"leds":false,"vendor_game":"new"}},"vendor_root":{"version":"new"}}'
        [IO.File]::WriteAllText($path, $latest, [Text.Encoding]::UTF8)
        $globalChanges = [ordered]@{ hold_ms = 180; trace_enabled = $true }
        $games = @([pscustomobject]@{ Name='sample'; Rumble=$true; Leds=$false })
        $updates = & $script:ui.ConfigMerge $globalChanges $games
        $updates.global.Contains('vendor_global') | Should Be $false
        $updates.games.sample.Contains('vendor_game') | Should Be $false

        $action = Update-HotwmJsonFileAction -Path $path -Updates $updates -Explanation 'Test isolated config update merge.'
        $applied = Invoke-HotwmFileAction -Action $action -Confirm { param($proposal) return $true }
        $applied.Success | Should Be $true
        $result = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.global.hold_ms | Should Be 180
        $result.global.vendor_global.version | Should Be 'new'
        $result.games.sample.rumble | Should Be $true
        $result.games.sample.vendor_game | Should Be 'new'
        $result.vendor_root.version | Should Be 'new'
    }
    It 'states that detection is not readiness and calibration remains manual' {
        $xaml = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'gui\HotwmDashboard.xaml'))
        $xaml | Should Match 'Spielfunktion'
        $xaml | Should Match 'Kalibrierung erfolgen manuell'
        $xaml | Should Match 'Windows-Bluetooth-Einstellungen'
        $script:ui.Controls.TextWiimoteBadge.Text | Should Not Be 'CONNECTED'
        $script:ui.Controls.TextKitBadge.Text | Should Not Be 'CONNECTED'
    }

    It 'copies and imports editable effect profiles, then requires a proposal approval to apply' {
        $script:ui.Controls.CmbEffectPreset.SelectedIndex = 1
        $copied = & $script:ui.ProfileDispatch 'CopyEffect' $null
        $copied.Success | Should Be $true
        $copied.Profile.Settings.global.hold_ms | Should Be 100
        $script:ui.Controls.SliderHoldMs.Value = 185
        $built = & $script:ui.ProfileDispatch 'BuildEffect' $null
        $built.Success | Should Be $true
        $built.Profile.Settings.global.hold_ms | Should Be 185

        $importPath = Join-Path $script:folderFixtures 'effect-import.json'
        $importProfileObject = $built.Profile
        $importProfileObject.Settings.games.Rambo | Add-Member -NotePropertyName hold_ms -NotePropertyValue 222
        $importProfile = $importProfileObject | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($importPath, $importProfile, (New-Object Text.UTF8Encoding($false)))
        $imported = & $script:ui.ProfileDispatch 'ImportEffect' @{ Path = $importPath }
        $imported.Success | Should Be $true
        $script:ui.Controls.TextEffectProfileName.Text = 'Imported and edited'
        $script:ui.Controls.SliderHoldMs.Value = 205

        $configPath = Join-Path $script:folderFixtures 'effect-target.json'
        $configObject = Get-Content -LiteralPath (Join-Path $script:repoRoot 'config\hotw.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $configObject.global | Add-Member -NotePropertyName vendor -NotePropertyValue 'retain'
        $configObject.games.Rambo | Add-Member -NotePropertyName vendor -NotePropertyValue 'retain'
        $configObject | Add-Member -NotePropertyName root_vendor -NotePropertyValue @{ tag = 7 }
        $original = ConvertTo-Json -InputObject $configObject -Depth 20
        [IO.File]::WriteAllText($configPath, $original, (New-Object Text.UTF8Encoding($false)))
        $capturedProposals = New-Object 'System.Collections.Generic.List[object]'
        $declined = & $script:ui.ProfileDispatch 'ApplyEffect' @{
            ConfigPath = $configPath
            Confirm = { param($proposal) [void]$capturedProposals.Add($proposal); return $false }.GetNewClosure()
        }
        $declined.Success | Should Be $false
        $capturedProposals.Count | Should Be 1
        $capturedProposals[0].TargetPath | Should Be ([IO.Path]::GetFullPath($configPath))
        $preview = $capturedProposals[0].ProposedContent | ConvertFrom-Json
        $preview.global.hold_ms | Should Be 205
        $preview.global.vendor | Should Be 'retain'
        $preview.games.Rambo.hold_ms | Should Be 222
        $after = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8)
        $after | Should Be $original
        $script:ui.Controls.TextEffectProfileStatus.Text | Should Match 'declined'
    }

    It 'copies editable semantic button intents without claiming they configure hardware' {
        $copy = & $script:ui.ProfileDispatch 'CopyButtons' $null
        $copy.Success | Should Be $true
        $copy.Profile.TargetCapability | Should Be 'manual-or-kit-profile'
        $intent = $script:ui.Controls.GridButtonIntents.ItemsSource | Where-Object { $_.Id -eq 'shoot' } | Select-Object -First 1
        $intent.Label = 'Fire primary'
        $built = & $script:ui.ProfileDispatch 'BuildButtons' $null
        $built.Success | Should Be $true
        ($built.Profile.Intents | Where-Object Id -eq 'shoot').Label | Should Be 'Fire primary'
        $script:ui.Controls.TextButtonProfileStatus.Text | Should Match 'manual|checklist|No button profile'
        $built.Profile.TargetCapability | Should Be 'manual-or-kit-profile'
        $exportPath = Join-Path $script:folderFixtures 'button-export.json'
        $capturedProposals = New-Object 'System.Collections.Generic.List[object]'
        $declined = & $script:ui.ProfileDispatch 'ExportButtons' @{
            Path = $exportPath
            Confirm = { param($proposal) [void]$capturedProposals.Add($proposal); return $false }.GetNewClosure()
        }
        $declined.Success | Should Be $false
        $capturedProposals.Count | Should Be 1
        $capturedProposals[0].TargetPath | Should Be ([IO.Path]::GetFullPath($exportPath))
        (Test-Path -LiteralPath $exportPath) | Should Be $false
    }

    It 'previews an existing per-game hold override when the profile inherits global timing' {
        $copied = & $script:ui.ProfileDispatch 'CopyEffect' $null
        $copied.Success | Should Be $true
        $profile = & $script:ui.ProfileDispatch 'BuildEffect' $null
        $profile.Success | Should Be $true
        $profile.Profile.Settings.games.Rambo.PSObject.Properties['hold_ms'] | Should Be $null

        $configPath = Join-Path $script:folderFixtures 'inherited-hold-target.json'
        $config = Get-Content -LiteralPath (Join-Path $script:repoRoot 'config\hotw.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.games.Rambo | Add-Member -NotePropertyName hold_ms -NotePropertyValue 177
        $original = ConvertTo-Json -InputObject $config -Depth 20
        [IO.File]::WriteAllText($configPath, $original, (New-Object Text.UTF8Encoding($false)))

        $proposals = New-Object 'System.Collections.Generic.List[object]'
        $applied = & $script:ui.ProfileDispatch 'ApplyEffect' @{
            ConfigPath=$configPath
            Confirm={ param($proposal) [void]$proposals.Add($proposal); return $false }.GetNewClosure()
        }
        $applied.Success | Should Be $false
        $proposals.Count | Should Be 1
        $proposed = $proposals[0].ProposedContent | ConvertFrom-Json
        $proposed.games.Rambo.hold_ms | Should Be 177
        $applied.Preview | Should Match 'Rambo: rumble=True, LEDs=True, hold_ms=177'
        $applied.Preview | Should Match 'Target:.*inherited-hold-target.json'
        [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8) | Should Be $original
    }

    It 'retains imported games outside this installation for export and rejects applying them explicitly' {
        $null = & $script:ui.ProfileDispatch 'CopyEffect' $null
        $built = & $script:ui.ProfileDispatch 'BuildEffect' $null
        $profileObject = $built.Profile
        $profileObject.Settings.games | Add-Member -NotePropertyName externalGame -NotePropertyValue ([pscustomobject]@{ rumble=$false; leds=$true; hold_ms=130 })
        $importPath = Join-Path $script:folderFixtures 'external-game-profile.json'
        [IO.File]::WriteAllText($importPath, ($profileObject | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        $imported = & $script:ui.ProfileDispatch 'ImportEffect' @{ Path=$importPath }
        $imported.Success | Should Be $true
        $builtWithExternal = & $script:ui.ProfileDispatch 'BuildEffect' $null
        $builtWithExternal.Success | Should Be $true
        $builtWithExternal.Profile.Settings.games.externalGame.hold_ms | Should Be 130

        $exportPath = Join-Path $script:folderFixtures 'external-game-export.json'
        $exportProposals = New-Object 'System.Collections.Generic.List[object]'
        $exported = & $script:ui.ProfileDispatch 'ExportEffect' @{
            Path=$exportPath
            Confirm={ param($proposal) [void]$exportProposals.Add($proposal); return $false }.GetNewClosure()
        }
        $exported.Success | Should Be $false
        $exportProposals.Count | Should Be 1
        $exportedProfile = $exportProposals[0].ProposedContent | ConvertFrom-Json
        $exportedProfile.Settings.games.externalGame.hold_ms | Should Be 130
        (Test-Path -LiteralPath $exportPath) | Should Be $false

        $configPath = Join-Path $script:folderFixtures 'external-game-target.json'
        $original = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'config\hotw.json'), [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($configPath, $original, (New-Object Text.UTF8Encoding($false)))
        $confirmCalls = New-Object 'System.Collections.Generic.List[object]'
        $apply = & $script:ui.ProfileDispatch 'ApplyEffect' @{
            ConfigPath=$configPath
            Confirm={ param($proposal) [void]$confirmCalls.Add($proposal); return $true }.GetNewClosure()
        }
        $apply.Success | Should Be $false
        $apply.Message | Should Match 'externalGame.*not present'
        $confirmCalls.Count | Should Be 0
        [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8) | Should Be $original
    }

    It 'loads six real Gunmote presets and edits OnScreen and OffScreen mappings on a user copy' {
        $script:ui.Controls.CmbGunmoteKind.Items.Count | Should Be 6
        $copy = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $copy.Success | Should Be $true
        $copy.MappingCount | Should BeGreaterThan 0
        $row = $script:ui.Controls.GridGunmoteMappings.ItemsSource | Where-Object Input -eq 'A' | Select-Object -First 1
        $row | Should Not Be $null
        $row.OnScreen = '360.custom-fire'
        $row.OffScreen = '360.custom-reload'
        $script:ui.Controls.TextGunmoteTitle.Text = 'Editable test layout'
        $built = & $script:ui.GunmoteDispatch 'BuildLayout' $null
        $built.Success | Should Be $true
        $built.Layout.Title | Should Be 'Editable test layout'
        $built.Layout.All.OnScreen.A | Should Be '360.custom-fire'
        $built.Layout.All.OffScreen.A | Should Be '360.custom-reload'
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Collapsed)
    }

    It 'keeps layout and chooser previews in Expert mode while reviewing in every mode' {
        $null = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $directory = Join-Path $script:folderFixtures 'GunmoteModePreview'
        [void][IO.Directory]::CreateDirectory($directory)
        $target = Join-Path $directory 'mode-preview.json'
        $script:ui.Controls.RadioQuickMode.IsChecked = $true
        $save = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='mode-preview.json'
            Confirm={ param($proposal) $proposal.TargetPath | Should Be ([IO.Path]::GetFullPath($target)); return $true }
            ProcessChecker={ return $true }
        }
        $save.Success | Should Be $true
        (Test-Path -LiteralPath $target) | Should Be $true
        $script:ui.Controls.TextGunmotePreview.Text | Should Match '"Title"'
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Collapsed)

        $script:ui.Controls.RadioExpertMode.IsChecked = $true
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.RadioCustomMode.IsChecked = $true
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Collapsed)

        $chooserPath = Join-Path $directory 'Keymaps.json'
        $originalChooser = '{"LayoutChooser":[]}'
        [IO.File]::WriteAllText($chooserPath, $originalChooser, (New-Object Text.UTF8Encoding($false)))
        $chooserConfirmations = New-Object 'System.Collections.Generic.List[object]'
        $chooser = & $script:ui.GunmoteDispatch 'AddChooser' @{
            KeymapsPath=$chooserPath
            Confirm={ param($proposal) [void]$chooserConfirmations.Add($proposal); return $false }.GetNewClosure()
            ProcessChecker={ return $true }
        }
        $chooser.Success | Should Be $false
        $chooserConfirmations.Count | Should Be 1
        $script:ui.Controls.TextGunmotePreview.Text | Should Match 'LayoutChooser'
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Collapsed)
        [IO.File]::ReadAllText($chooserPath, [Text.Encoding]::UTF8) | Should Be $originalChooser
        $script:ui.Controls.RadioExpertMode.IsChecked = $true
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Visible)
        $script:ui.Controls.RadioQuickMode.IsChecked = $true
        $script:ui.Controls.TextGunmotePreview.Visibility | Should Be ([Windows.Visibility]::Collapsed)
    }

    It 'commits an active WPF mapping cell before building the reviewed save proposal' {
        $null = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $script:ui.Window.Show()
        $script:ui.Controls.MainTabs.SelectedIndex = 3
        $script:ui.Window.UpdateLayout()
        $grid = $script:ui.Controls.GridGunmoteMappings
        $row = $grid.ItemsSource | Where-Object Input -eq 'A' | Select-Object -First 1
        $grid.ScrollIntoView($row)
        $grid.SelectedItem = $row
        $grid.CurrentCell = [System.Windows.Controls.DataGridCellInfo]::new($row, $grid.Columns[1])
        $grid.BeginEdit() | Should Be $true
        $grid.UpdateLayout()

        function Find-HotwmVisibleTextBox([System.Windows.DependencyObject]$Node) {
            if ($Node -is [System.Windows.Controls.TextBox] -and $Node.IsVisible) { return $Node }
            for ($childIndex = 0; $childIndex -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Node); $childIndex++) {
                $match = Find-HotwmVisibleTextBox ([System.Windows.Media.VisualTreeHelper]::GetChild($Node, $childIndex))
                if ($match) { return $match }
            }
        }
        $editor = Find-HotwmVisibleTextBox $grid
        $editor | Should Not Be $null
        $editor.Text = '360.edited-in-cell'

        $directory = Join-Path $script:folderFixtures 'GunmoteCellEditKeymaps'
        [void][IO.Directory]::CreateDirectory($directory)
        $proposals = New-Object 'System.Collections.Generic.List[object]'
        $save = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='cell-edit.json'
            Confirm={ param($proposal) [void]$proposals.Add($proposal); return $false }.GetNewClosure()
            ProcessChecker={ return $true }
        }
        $save.Success | Should Be $false
        $proposals.Count | Should Be 1
        ($proposals[0].ProposedContent | ConvertFrom-Json).All.OnScreen.A | Should Be '360.edited-in-cell'
        (Test-Path -LiteralPath (Join-Path $directory 'cell-edit.json')) | Should Be $false
        $script:ui.Window.Hide()
    }

    It 'imports an existing Gunmote layout read-only into the mapping editor' {
        $null = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $built = & $script:ui.GunmoteDispatch 'BuildLayout' $null
        $importPath = Join-Path $script:folderFixtures 'existing-gunmote-layout.json'
        $source = ConvertTo-Json -InputObject $built.Layout -Depth 100
        [IO.File]::WriteAllText($importPath, $source, (New-Object Text.UTF8Encoding($false)))
        $imported = & $script:ui.GunmoteDispatch 'ImportLayout' @{ Path=$importPath }
        $imported.Success | Should Be $true
        $imported.Layout.Title | Should Be $built.Layout.Title
        $script:ui.Controls.GridGunmoteMappings.Items.Count | Should Be $imported.MappingCount
        [IO.File]::ReadAllText($importPath, [Text.Encoding]::UTF8) | Should Be $source
    }

    It 'requires explicit approval and a closed Gunmote process before writing a layout' {
        $null = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $directory = Join-Path $script:folderFixtures 'GunmoteKeymaps'
        [void][IO.Directory]::CreateDirectory($directory)
        $target = Join-Path $directory 'reviewed-user-layout.json'
        $confirmCalls = New-Object 'System.Collections.Generic.List[object]'
        $declined = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='reviewed-user-layout.json'
            Confirm={ param($proposal) [void]$confirmCalls.Add($proposal); return $false }.GetNewClosure()
            ProcessChecker={ return $true }
        }
        $declined.Success | Should Be $false
        $confirmCalls.Count | Should Be 1
        $confirmCalls[0].TargetPath | Should Be ([IO.Path]::GetFullPath($target))
        (Test-Path -LiteralPath $target) | Should Be $false

        $approved = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='reviewed-user-layout.json'
            Confirm={ param($proposal) return $true }
            ProcessChecker={ return $false }
        }
        $approved.Success | Should Be $false
        $approved.Message | Should Match 'Gunmote is running'
        (Test-Path -LiteralPath $target) | Should Be $false

        $script:ui.Controls.TextGunmoteTitle.Text = '   '
        $invalid = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='invalid-title.json'
            Confirm={ param($proposal) throw 'Confirmation must not run for invalid layout.' }
            ProcessChecker={ return $true }
        }
        $invalid.Success | Should Be $false
        $invalid.Message | Should Match 'valid Title'
        (Test-Path -LiteralPath (Join-Path $directory 'invalid-title.json')) | Should Be $false
    }

    It 'rejects a target changed during confirmation and does not overwrite the concurrent file' {
        $null = & $script:ui.GunmoteDispatch 'CopyLayout' $null
        $directory = Join-Path $script:folderFixtures 'GunmoteChangedKeymaps'
        [void][IO.Directory]::CreateDirectory($directory)
        $target = Join-Path $directory 'changed-user-layout.json'
        $changedText = '{"concurrent":"writer"}'
        $changed = & $script:ui.GunmoteDispatch 'SaveLayout' @{
            KeymapsDir=$directory; FileName='changed-user-layout.json'
            Confirm={ param($proposal) [IO.File]::WriteAllText($target, $changedText, (New-Object Text.UTF8Encoding($false))); return $true }.GetNewClosure()
            ProcessChecker={ return $true }
        }
        $changed.Success | Should Be $false
        $changed.Message | Should Match 'changed|snapshot|modified|state'
        [IO.File]::ReadAllText($target, [Text.Encoding]::UTF8) | Should Be $changedText
    }

    It 'does not offer a chooser write until a layout save succeeds' {
        $directory = Join-Path $script:folderFixtures 'GunmoteChooserKeymaps'
        [void][IO.Directory]::CreateDirectory($directory)
        $chooserPath = Join-Path $directory 'Keymaps.json'
        $original = '{"LayoutChooser":[]}'
        [IO.File]::WriteAllText($chooserPath, $original, (New-Object Text.UTF8Encoding($false)))
        $result = & $script:ui.GunmoteDispatch 'AddChooser' @{ KeymapsPath=$chooserPath; Confirm={ return $true }; ProcessChecker={ return $true } }
        $result.Success | Should Be $false
        $result.Message | Should Match 'Save a layout successfully'
        [IO.File]::ReadAllText($chooserPath, [Text.Encoding]::UTF8) | Should Be $original
    }
}
