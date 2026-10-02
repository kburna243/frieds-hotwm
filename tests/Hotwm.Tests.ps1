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

Describe 'hotwm — Kit API Live Contract (Cabinets with RetroCabinetKit)' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
        . (Join-Path $script:repoRoot 'src\KitClient.ps1')
        $script:realKit = Get-HotwmKitRoot
        $script:kitAvailable = [bool]($script:realKit -and (Test-Path (Join-Path $script:realKit 'api\Invoke-KitApi.ps1')) -and ($script:realKit -notlike '*fake-kit*'))
    }

    It 'contract snapshot kit-contract-v1.json exists and targets ApiVersion 1.6 (Kit 1.4.0)' {
        $cPath = Join-Path $script:repoRoot 'contract\kit-contract-v1.json'
        (Test-Path $cPath) | Should Be $true
        $contract = Get-Content -LiteralPath $cPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $contract.TargetKit.ApiVersion | Should Be '1.6'
        $contract.TargetKit.KitVersion | Should Be '1.4.0'
        $hookOp = $contract.RequiredOperations | Where-Object { $_.Name -eq 'outputs.wiimote_hook' }
        $hookOp | Should Not Be $null
        $hookOp.Parameters | Should Not Be $null
    }

    It 'Test-ContractDrift passes against local Kit when present' -Skip:(-not $script:kitAvailable) {
        $driftScript = Join-Path $script:repoRoot 'tools\Test-ContractDrift.ps1'
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$driftScript`"" -NoNewWindow -PassThru -Wait
        $p.ExitCode | Should Be 0
    }

    It 'Get-HotwmInputProfiles queries Kit v1.3.0 controllers.input_profiles successfully' -Skip:(-not $script:kitAvailable) {
        $res = Get-HotwmInputProfiles
        $res | Should Not Be $null
        $res.Success | Should Be $true
        $res.Data.Profiles | Should Not Be $null
        ($res.Data.Profiles | Where-Object { $_.Name -eq 'ipac2-default' }) | Should Not Be $null
    }

    It 'Get-HotwmOutputSafety queries Kit operation outputs.verify_safety successfully' -Skip:(-not $script:kitAvailable) {
        $res = Get-HotwmOutputSafety
        $res | Should Not Be $null
        $res.Success | Should Be $true
        $res.Data.SolenoidGuard | Should Not Be $null
        $res.Data.DetectedOutputs | Should Not Be $null
    }
}

Describe 'hotwm — KitClient against Fake-Kit (Offline / CI)' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
        $script:origEnvKit = $env:RETRO_CABINET_KIT_ROOT
        $env:RETRO_CABINET_KIT_ROOT = Join-Path $script:repoRoot 'tests\fixtures\fake-kit'
        . (Join-Path $script:repoRoot 'src\KitClient.ps1')
    }

    AfterAll {
        if ($script:origEnvKit) {
            $env:RETRO_CABINET_KIT_ROOT = $script:origEnvKit
        } else {
            Remove-Item env:RETRO_CABINET_KIT_ROOT -ErrorAction SilentlyContinue
        }
    }

    It 'KitClient correctly detects and communicates with Fake-Kit' {
        (Test-HotwmKitAvailable) | Should Be $true
        $root = Get-HotwmKitRoot
        $root | Should Match 'fake-kit'
    }

    It 'Get-HotwmSystemStatus returns parsed output hook data from Fake-Kit' {
        $res = Get-HotwmSystemStatus
        $res | Should Not Be $null
        $res.Success | Should Be $true
        $res.Data.WiimoteDetected | Should Be $true
        $res.Data.RelayInstalled | Should Be $true
    }

    It 'Get-HotwmInputProfiles returns input profiles from Fake-Kit' {
        $res = Get-HotwmInputProfiles
        $res | Should Not Be $null
        $res.Success | Should Be $true
        $res.Data.Profiles | Should Not Be $null
        $res.Data.Profiles[0].Name | Should Be 'ipac2-default'
    }

    It 'Get-HotwmOutputSafety returns safety data from Fake-Kit' {
        $res = Get-HotwmOutputSafety
        $res | Should Not Be $null
        $res.Success | Should Be $true
        $res.Data.SolenoidGuard.Ok | Should Be $true
        ($res.Data.DetectedOutputs -contains 'GunmoteOutput') | Should Be $true
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

    It 'Live Log Monitor tails the same trace file the relay writes' {
        # hotwm_relay.py: TRACE_LOG = Path(__file__).resolve().parent.parent / "recoil-stretch-trace.log"
        $relay = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'src\hotwm_relay.py'))
        $relay | Should Match 'TRACE_LOG = Path\(__file__\)\.resolve\(\)\.parent\.parent / "recoil-stretch-trace\.log"'
        $ui = & (Join-Path $script:repoRoot 'gui\HotwmDashboard.ps1') -NoShow
        $ui.TraceLog | Should Be (Join-Path $script:repoRoot 'recoil-stretch-trace.log')
    }
}

Describe 'hotwm — Packaging' {
    BeforeAll {
        if (-not $script:repoRoot -or -not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
            $script:repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
            if (-not (Test-Path (Join-Path $script:repoRoot 'config\hotw.json'))) {
                $script:repoRoot = (Get-Location).Path
            }
        }
        $script:tempOut = Join-Path ([System.IO.Path]::GetTempPath()) "hotwm_pkg_test_$([System.Guid]::NewGuid().ToString('N'))"
    }

    AfterAll {
        if (Test-Path $script:tempOut) {
            Remove-Item -Path $script:tempOut -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Build-HotwmPackage.ps1 script exists' {
        (Test-Path (Join-Path $script:repoRoot 'tools\Build-HotwmPackage.ps1')) | Should Be $true
    }

    It 'Build-HotwmPackage builds a valid zip archive and sha256 checksum' {
        $buildScript = Join-Path $script:repoRoot 'tools\Build-HotwmPackage.ps1'
        $pkg = & $buildScript -OutDir $script:tempOut -Version '9.9.9'
        $pkg | Should Not Be $null
        (Test-Path $pkg.ArchiveFile) | Should Be $true
        (Test-Path $pkg.Sha256File) | Should Be $true
        ($pkg.FileCount -gt 10) | Should Be $true
        $pkg.Sha256.Length | Should Be 64

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($pkg.ArchiveFile)
        $entryNames = $zip.Entries | ForEach-Object { $_.FullName }
        $zip.Dispose()

        ($entryNames -contains 'src\hotwm_relay.py') | Should Be $true
        ($entryNames -contains 'gui\HotwmDashboard.ps1') | Should Be $true
        ($entryNames -contains 'gui\HotwmDashboard.xaml') | Should Be $true
        ($entryNames -contains 'config\hotw.json') | Should Be $true
        ($entryNames -contains 'README.md') | Should Be $true
        ($entryNames -contains 'README.de.md') | Should Be $true
        ($entryNames -contains 'Start-HotwmDashboard.bat') | Should Be $true
    }
}



