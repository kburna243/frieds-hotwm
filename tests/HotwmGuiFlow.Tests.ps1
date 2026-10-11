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
}
