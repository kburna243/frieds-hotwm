$script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }

Describe 'hotwm — Code & Schema Integrity' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
    }
    It 'hotw.json exists and is valid JSON with global and games sections' {
        $cfgPath = Join-Path $script:repoRoot 'config\hotw.json'
        (Test-Path $cfgPath) | Should Be $true
        $content = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $content.global.hold_ms | Should Be 150
        $content.global.ammo_drop_shot | Should Be $true
        @($content.games.psobject.Properties).Count | Should BeGreaterThan 5
    }

    It 'all PowerShell scripts have valid syntax' {
        $scripts = Get-ChildItem -LiteralPath $script:repoRoot -Filter '*.ps1' -Recurse
        $scripts.Count | Should BeGreaterThan 0
        foreach ($s in $scripts) {
            $tokens = $null; $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
            $errors.Count | Should Be 0 -Because "Script $($s.Name) should parse cleanly"
        }
    }

    It 'all PowerShell scripts have UTF-8 BOM' {
        $scripts = Get-ChildItem -LiteralPath $script:repoRoot -Filter '*.ps1' -Recurse
        foreach ($s in $scripts) {
            $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should Be $true -Because "Script $($s.Name) must have UTF-8 BOM"
        }
    }
}

Describe 'hotwm — Python Relay Selftest' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
    }
    It 'python selftest executes and passes with zero exit code' {
        $relayPy = Join-Path $script:repoRoot 'src\hotwm_relay.py'
        $p = Start-Process -FilePath "python.exe" -ArgumentList "`"$relayPy`" --selftest" -NoNewWindow -PassThru -Wait
        $p.ExitCode | Should Be 0
    }

    It 'python unit tests pass' {
        $p = Start-Process -FilePath "python.exe" -ArgumentList "-m unittest tests/test_hotwm_relay.py" -WorkingDirectory $script:repoRoot -NoNewWindow -PassThru -Wait
        $p.ExitCode | Should Be 0
    }
}

Describe 'hotwm — Kit API Contract Compatibility' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
    }

    It 'contract snapshot kit-contract-v1.json exists and targets ApiVersion 1.5 (Kit 1.3.0)' {
        $cPath = Join-Path $script:repoRoot 'contract\kit-contract-v1.json'
        (Test-Path $cPath) | Should Be $true
        $contract = Get-Content -LiteralPath $cPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $contract.TargetKit.ApiVersion | Should Be '1.5'
        $contract.TargetKit.KitVersion | Should Be '1.3.0'
        $hookOp = $contract.RequiredOperations | Where-Object { $_.Name -eq 'outputs.wiimote_hook' }
        $hookOp | Should Not Be $null
    }

    It 'Test-ContractDrift passes against local Kit when present' {
        . (Join-Path $script:repoRoot 'src\KitClient.ps1')
        if (Test-HotwmKitAvailable) {
            $driftScript = Join-Path $script:repoRoot 'tools\Test-ContractDrift.ps1'
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$driftScript`"" -NoNewWindow -PassThru -Wait
            $p.ExitCode | Should Be 0
        }
    }

    It 'Get-HotwmInputProfiles queries Kit v1.3.0 controllers.input_profiles successfully' {
        . (Join-Path $script:repoRoot 'src\KitClient.ps1')
        if (Test-HotwmKitAvailable) {
            $res = Get-HotwmInputProfiles
            $res | Should Not Be $null
            $res.Success | Should Be $true
            $res.Data.Profiles | Should Not Be $null
            ($res.Data.Profiles | Where-Object { $_.Name -eq 'ipac2-default' }) | Should Not Be $null
        }
    }

    It 'Get-HotwmOutputSafety queries Kit operation outputs.verify_safety successfully' {
        . (Join-Path $script:repoRoot 'src\KitClient.ps1')
        if (Test-HotwmKitAvailable) {
            $res = Get-HotwmOutputSafety
            $res | Should Not Be $null
            $res.Success | Should Be $true
            $res.Data.SolenoidGuard | Should Not Be $null
            $res.Data.DetectedOutputs | Should Not Be $null
        }
    }
}

Describe 'hotwm — GUI Dashboard' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
    }

    It 'HotwmDashboard.xaml and HotwmDashboard.ps1 exist' {
        (Test-Path (Join-Path $script:repoRoot 'gui\HotwmDashboard.xaml')) | Should Be $true
        (Test-Path (Join-Path $script:repoRoot 'gui\HotwmDashboard.ps1')) | Should Be $true
    }

    It 'HotwmDashboard instantiates headlessly with -NoShow' {
        $dashScript = Join-Path $script:repoRoot 'gui\HotwmDashboard.ps1'
        $ui = & $dashScript -NoShow
        $ui | Should Not Be $null
        $ui.Window | Should Not Be $null
        $ui.Controls.BtnTestP1Rumble | Should Not Be $null
        $ui.Controls.SliderHoldMs | Should Not Be $null
        $ui.Controls.GridGameProfiles | Should Not Be $null
        $ui.Controls.BtnQueryInputMatrix | Should Not Be $null
        $ui.Controls.BtnVerifyOutputSafety | Should Not Be $null
    }
}



