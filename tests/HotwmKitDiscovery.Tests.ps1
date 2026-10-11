$script:kitClientPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\KitClient.ps1'
. $script:kitClientPath

function New-TestKitRoot {
    param([string]$Path)
    [void][System.IO.Directory]::CreateDirectory((Join-Path $Path 'api'))
    [System.IO.File]::WriteAllText((Join-Path $Path 'api\Invoke-KitApi.ps1'), '# fixture')
    return [System.IO.Path]::GetFullPath($Path)
}

Describe 'Hotwm Kit discovery' {
    BeforeEach {
        $script:previousKitRoot = $env:RETRO_CABINET_KIT_ROOT
        Remove-Item Env:RETRO_CABINET_KIT_ROOT -ErrorAction SilentlyContinue
        $script:discoveryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('hotwm-kit-' + [Guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:discoveryRoot)
    }

    AfterEach {
        if ($null -eq $script:previousKitRoot) {
            Remove-Item Env:RETRO_CABINET_KIT_ROOT -ErrorAction SilentlyContinue
        } else {
            $env:RETRO_CABINET_KIT_ROOT = $script:previousKitRoot
        }
        Remove-Item -LiteralPath $script:discoveryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'uses the explicit valid environment root before adjacent candidates and canonicalizes it' {
        $app = Join-Path $script:discoveryRoot 'portable\gui'
        [void][System.IO.Directory]::CreateDirectory($app)
        $adjacent = New-TestKitRoot (Join-Path (Split-Path -Parent $app) 'retro-cabinet-kit')
        $explicit = New-TestKitRoot (Join-Path $script:discoveryRoot 'explicit-kit')
        $env:RETRO_CABINET_KIT_ROOT = Join-Path $explicit '.'

        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $explicit
        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Not Be $adjacent
    }

    It 'does not fall back when the explicit environment root is invalid' {
        $app = Join-Path $script:discoveryRoot 'portable\gui'
        [void][System.IO.Directory]::CreateDirectory($app)
        [void](New-TestKitRoot (Join-Path (Split-Path -Parent $app) 'retro-cabinet-kit'))
        $env:RETRO_CABINET_KIT_ROOT = Join-Path $script:discoveryRoot 'missing-kit'

        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $null
    }

    It 'discovers the portable flat gui source sibling' {
        $app = Join-Path $script:discoveryRoot 'portable\gui'
        [void][System.IO.Directory]::CreateDirectory($app)
        $expected = New-TestKitRoot (Join-Path (Split-Path -Parent $app) 'frieds-retrogaming-kit')

        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $expected
    }

    It 'discovers the development code src grandparent sibling' {
        $app = Join-Path $script:discoveryRoot 'projects\frieds-hotwm\code'
        [void][System.IO.Directory]::CreateDirectory($app)
        $expected = New-TestKitRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $app)) 'retro-cabinet-kit')

        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $expected
    }

    It 'ignores a known-name folder without the Kit API entry point' {
        $app = Join-Path $script:discoveryRoot 'portable\gui'
        [void][System.IO.Directory]::CreateDirectory($app)
        $invalid = Join-Path (Split-Path -Parent $app) 'retro-cabinet-kit'
        [void][System.IO.Directory]::CreateDirectory($invalid)
        $expected = New-TestKitRoot (Join-Path (Split-Path -Parent $app) 'frieds-retrogaming-kit')

        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $expected
    }

    It 'returns null when no bounded adjacent candidate is valid' {
        $app = Join-Path $script:discoveryRoot 'portable\gui'
        [void][System.IO.Directory]::CreateDirectory($app)
        (Get-HotwmKitRoot -ApplicationRoot $app) | Should Be $null
    }

    It 'contains no machine-specific Kit path' {
        $source = [System.IO.File]::ReadAllText($script:kitClientPath)
        $source.Contains('I:\claude-system\data\projects\retro-cabinet-kit') | Should Be $false
    }
}
