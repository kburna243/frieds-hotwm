$script:repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:repoRoot 'src\HotwmSetup.ps1')
. (Join-Path $script:repoRoot 'src\HotwmGunmote.ps1')

Describe 'Hotwm Gunmote layouts' {
    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('hotwm-gunmote-' + [Guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:testRoot)
        $script:keymapsDir = Join-Path $script:testRoot 'Keymaps'
        [void][System.IO.Directory]::CreateDirectory($script:keymapsDir)
        $script:keymapsPath = Join-Path $script:keymapsDir 'Keymaps.json'
        [System.IO.File]::WriteAllText($script:keymapsPath, '{"Default":"default.json","LayoutChooser":[],"Applications":[],"Other":{"keep":true}}', (New-Object System.Text.UTF8Encoding($false)))
    }
    AfterEach { Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue }

    It 'loads the versioned Kit snapshot with explicit maps for every supported kind' {
        $catalog = Get-HotwmGunmoteLayouts
        $catalog.source.version | Should Be '1.4.0'
        @($catalog.layouts.PSObject.Properties).Count | Should Be 6
        foreach ($kind in @('Menu','Pad43','TP','Mouse','Mouse43','MouseShoot')) {
            $layout = $catalog.layouts.$kind
            $layout.All.OnScreen | Should Not Be $null
            $layout.All.OffScreen | Should Not Be $null
            @($layout.All.OnScreen.PSObject.Properties).Count | Should BeGreaterThan 50
        }
        $catalog.layouts.Pad43.All.OnScreen.Pointer | Should Be '360.stickl-light-4:3'
        $catalog.layouts.TP.All.OnScreen.Pointer | Should Be '360.stickr-light'
        $catalog.layouts.MouseShoot.All.OffScreen.B | Should Be 'mouseleft'
    }

    It 'returns an independent editable copy of a shipped layout' {
        $userLayout = New-HotwmGunmoteUserLayout -Kind Mouse43 -Title 'My Mouse 4:3'
        $userLayout.All.OnScreen.A = 'custom-aim-button'
        $userLayout.Title | Should Be 'My Mouse 4:3'
        (Get-HotwmGunmoteLayouts).layouts.Mouse43.All.OnScreen.A | Should Be 'mouseright'
    }

    It 'imports layouts while preserving unknown fields and validates mappings' {
        $layout = New-HotwmGunmoteUserLayout -Kind TP
        $layout | Add-Member -NotePropertyName VendorExtension -NotePropertyValue @{ revision = 9 }
        $layout.All.OnScreen | Add-Member -NotePropertyName VendorInput -NotePropertyValue 'custom-input'
        $path = Join-Path $script:keymapsDir 'imported.json'
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json $layout -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
        $loaded = Import-HotwmGunmoteLayout -Path $path
        $loaded.VendorExtension.revision | Should Be 9
        $loaded.All.OnScreen.VendorInput | Should Be 'custom-input'
        $loaded.All.OnScreen.A = "bad`nvalue"
        { Test-HotwmGunmoteLayout $loaded } | Should Throw
    }

    It 'rejects shipped filenames and invalid mapping values' {
        $layout = New-HotwmGunmoteUserLayout -Kind Menu
        { New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'rck_menu.json' } | Should Throw
        $layout.All.OffScreen.A = ''
        { New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'my-menu.json' } | Should Throw
        $layout.All.OffScreen.A = ('x' * 129)
        { Test-HotwmGunmoteLayout $layout } | Should Throw
        { New-HotwmGunmoteLayoutAction -Layout (New-HotwmGunmoteUserLayout -Kind Menu) -KeymapsDir (Join-Path $script:repoRoot 'config\templates') -FileName 'user-layout.json' } | Should Throw
    }

    It 'declines without writing and requires Gunmote to be closed immediately before apply' {
        $layout = New-HotwmGunmoteUserLayout -Kind Pad43
        $declined = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'user-pad.json'
        $result = Invoke-HotwmGunmoteLayoutAction -Action $declined -Confirm { return $false } -ProcessChecker { return $true }
        $result.Status | Should Be 'declined'
        (Test-Path (Join-Path $script:keymapsDir 'user-pad.json')) | Should Be $false

        $blocked = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'user-pad.json'
        { Invoke-HotwmGunmoteLayoutAction -Action $blocked -Confirm { return $true } -ProcessChecker { return $false } } | Should Throw
        (Test-Path (Join-Path $script:keymapsDir 'user-pad.json')) | Should Be $false
    }

    It 'writes only the approved layout and preserves unknown existing layout keys' {
        $path = Join-Path $script:keymapsDir 'user-mouse.json'
        $original = New-HotwmGunmoteUserLayout -Kind Mouse
        $original | Add-Member -NotePropertyName VendorData -NotePropertyValue @{ keep = 'original' }
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllBytes($path, $utf8Bom.GetPreamble() + $utf8Bom.GetBytes((ConvertTo-Json $original -Depth 100)))
        $edited = New-HotwmGunmoteUserLayout -Kind Mouse -Title 'Edited mouse layout'
        $edited.All.OnScreen.A = 'custom-trigger'
        $action = New-HotwmGunmoteLayoutAction -Layout $edited -KeymapsDir $script:keymapsDir -FileName 'user-mouse.json'
        $result = Invoke-HotwmGunmoteLayoutAction -Action $action -Confirm { return $true } -ProcessChecker { return $true }
        $result.Success | Should Be $true
        $saved = ConvertFrom-Json ([System.IO.File]::ReadAllText($path))
        $saved.Title | Should Be 'Edited mouse layout'
        $saved.All.OnScreen.A | Should Be 'custom-trigger'
        $saved.VendorData.keep | Should Be 'original'
    }

    It 'requires a verified installed layout before proposing a chooser entry' {
        $layout = New-HotwmGunmoteUserLayout -Kind Mouse
        { New-HotwmGunmoteChooserAction -LayoutResult ([pscustomobject]@{ Success=$true; LayoutPath='missing' }) -KeymapsPath $script:keymapsPath -LayoutTitle 'My mouse' } | Should Throw
        $proposal = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'user-mouse.json'
        $declined = Invoke-HotwmGunmoteLayoutAction -Action $proposal -Confirm { return $false } -ProcessChecker { return $true }
        { New-HotwmGunmoteChooserAction -LayoutResult $declined -KeymapsPath $script:keymapsPath -LayoutTitle 'My mouse' } | Should Throw
    }

    It 'rechecks the installed layout hash before a separately approved chooser write' {
        $layout = New-HotwmGunmoteUserLayout -Kind Mouse43
        $write = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'user-mouse43.json'
        $installed = Invoke-HotwmGunmoteLayoutAction -Action $write -Confirm { return $true } -ProcessChecker { return $true }
        $chooser = New-HotwmGunmoteChooserAction -LayoutResult $installed -KeymapsPath $script:keymapsPath -LayoutTitle 'User Mouse 4:3'
        [System.IO.File]::WriteAllText($installed.LayoutPath, 'foreign edit', (New-Object System.Text.UTF8Encoding($false)))
        { Invoke-HotwmGunmoteChooserAction -Action $chooser -Confirm { return $true } -ProcessChecker { return $true } } | Should Throw
        (Get-Content $script:keymapsPath -Raw) | Should Not Match 'user-mouse43.json'
    }

    It 'adds a chooser entry as its own action and preserves other Keymaps settings' {
        $layout = New-HotwmGunmoteUserLayout -Kind TP
        $write = New-HotwmGunmoteLayoutAction -Layout $layout -KeymapsDir $script:keymapsDir -FileName 'user-tp.json'
        $installed = Invoke-HotwmGunmoteLayoutAction -Action $write -Confirm { return $true } -ProcessChecker { return $true }
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $keymapsText = [System.IO.File]::ReadAllText($script:keymapsPath)
        [System.IO.File]::WriteAllBytes($script:keymapsPath, $utf8Bom.GetPreamble() + $utf8Bom.GetBytes($keymapsText))
        $chooser = New-HotwmGunmoteChooserAction -LayoutResult $installed -KeymapsPath $script:keymapsPath -LayoutTitle 'My TP layout'
        $result = Invoke-HotwmGunmoteChooserAction -Action $chooser -Confirm { return $true } -ProcessChecker { return $true }
        $result.Success | Should Be $true
        $keymaps = ConvertFrom-Json ([System.IO.File]::ReadAllText($script:keymapsPath))
        $keymaps.Other.keep | Should Be $true
        $keymaps.LayoutChooser[0].Keymap | Should Be 'user-tp.json'
        $keymaps.LayoutChooser[0].Title | Should Be 'My TP layout'
        $keymaps.Default | Should Be 'default.json'
        $keymaps.Applications.Count | Should Be 0
    }
}
