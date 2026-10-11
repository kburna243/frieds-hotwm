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
        $script:ui.Controls.TextDiscoveryStatus.Text | Should Match 'not|Not|PnP'
        $script:ui.Controls.TextConfigSaveStatus | Should Not Be $null
    }

    It 'validates RetroBat folders read-only and reports unsupported targets without blocking folder selection' {
        $configBefore = $script:ui.Config
        $script:ui.Controls.TextSetupFolder.Text = $script:validTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'read-only'
        $script:ui.Config | Should Be $configBefore
        $script:ui.Controls.TextSetupFolder.Text = $script:unknownTarget
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'not recognized'
        $script:ui.Controls.TextSetupFolder.Text = (Join-Path $script:folderFixtures 'missing')
        $script:ui.Controls.BtnValidateSetupFolder.RaiseEvent(([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)))
        $script:ui.Controls.TextSetupFolderStatus.Text | Should Match 'not found'
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
        $script:ui.Controls.SliderHoldMs.Value | Should Be 190
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
        $xaml | Should Match 'does not prove Bluetooth identity'
        $xaml | Should Match 'Calibration is manual'
        $xaml | Should Match 'Pairing is semi-automatic'
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
