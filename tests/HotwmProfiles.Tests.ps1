$script:profilesRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:profilesRoot 'src\HotwmSetup.ps1')
. (Join-Path $script:profilesRoot 'src\HotwmProfiles.ps1')

Describe 'hotwm versioned templates and file proposals' {
    BeforeEach {
        $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hotwm-profiles-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:tempRoot)
    }
    AfterEach { Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

    It 'loads shipped version 1 effect and semantic button templates' {
        $effects = @(Get-HotwmTemplates -Kind Effects)
        $buttons = @(Get-HotwmTemplates -Kind Buttons)
        $effects.Count | Should BeGreaterThan 0
        $effects[0].Kind | Should Be 'effects'
        $buttons[0].TargetCapability | Should Be 'manual-or-kit-profile'
        @($buttons[0].Intents | Where-Object { $_.Id -eq 'shoot' }).Count | Should Be 1
    }

    It 'copies a template into a named profile without changing the shipped source' {
        $templatePath = Join-Path $script:profilesRoot 'config\templates\effects.json'
        $before = [IO.File]::ReadAllText($templatePath)
        $template = (Get-HotwmTemplates -Kind Effects)[0]
        $userProfile = New-HotwmUserProfile -Template $template -Name 'My effects'
        $userProfile.Name | Should Be 'My effects'
        $userProfile.SourceTemplate | Should Be $template.Id
        (Test-HotwmProfile $userProfile).Valid | Should Be $true
        [IO.File]::ReadAllText($templatePath) | Should Be $before
    }

    It 'rejects malformed schemas, unsupported player fields, bad ranges, and unknown effect fields' {
        $template = (Get-HotwmTemplates Effects)[0]
        $userProfile = New-HotwmUserProfile -Template $template -Name 'Check'
        $userProfile.Settings.global.hold_ms = 301
        (Test-HotwmProfile $userProfile).Valid | Should Be $false
        $userProfile = New-HotwmUserProfile -Template $template -Name 'Check'
        $userProfile | Add-Member -NotePropertyName PlayerOverrides -NotePropertyValue @{}
        (Test-HotwmProfile $userProfile).Valid | Should Be $false
        $userProfile = New-HotwmUserProfile -Template $template -Name 'Check'
        $userProfile.Settings.global | Add-Member -NotePropertyName unknown -NotePropertyValue $true
        (Test-HotwmProfile $userProfile).Valid | Should Be $false
        $userProfile = New-HotwmUserProfile -Template $template -Name 'Check'
        $userProfile.Settings.games = @()
        (Test-HotwmProfile $userProfile).Valid | Should Be $false
        $userProfile = New-HotwmUserProfile -Template $template -Name 'Check'
        $userProfile.Settings.games | Add-Member -NotePropertyName Rambo -NotePropertyValue ([pscustomobject]@{ hold_ms=79 })
        (Test-HotwmProfile $userProfile).Valid | Should Be $false
    }

    It 'imports a valid profile read-only and rejects malformed or unknown schemas' {
        $userProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Effects)[0] -Name 'Imported'
        $path = Join-Path $script:tempRoot 'profile.json'
        [IO.File]::WriteAllText($path, (ConvertTo-Json $userProfile -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        (Import-HotwmProfile -Path $path).Name | Should Be 'Imported'
        [IO.File]::WriteAllText($path, '{bad json', (New-Object System.Text.UTF8Encoding($false)))
        { Import-HotwmProfile -Path $path } | Should Throw
        [IO.File]::WriteAllText($path, '{"SchemaVersion":99,"Kind":"unknown","Name":"x"}', (New-Object System.Text.UTF8Encoding($false)))
        { Import-HotwmProfile -Path $path } | Should Throw
    }

    It 'exports as a confirmation proposal and leaves the target untouched when declined' {
        $userProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Buttons)[0] -Name 'Bindings checklist'
        $path = Join-Path $script:tempRoot 'export.json'
        $proposal = Export-HotwmProfileAction -Profile $userProfile -Path $path
        $proposal.Kind | Should Be 'write'
        $proposal.ProposedContent | Should Match 'manual-or-kit-profile'
        $result = Invoke-HotwmFileAction -Action $proposal -Confirm { return $false }
        $result.Status | Should Be 'declined'
        (Test-Path -LiteralPath $path) | Should Be $false
    }

    It 'blocks direct and traversal export targets for immutable shipped catalogs' {
        $templateDir = Join-Path $script:profilesRoot 'config\templates'
        $effectsPath = Join-Path $templateDir 'effects.json'
        $buttonsPath = Join-Path $templateDir 'buttons.json'
        $effectsBefore = [IO.File]::ReadAllBytes($effectsPath)
        $buttonsBefore = [IO.File]::ReadAllBytes($buttonsPath)
        $effectProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Effects)[0] -Name 'Cannot overwrite'
        $buttonProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Buttons)[0] -Name 'Cannot overwrite'
        { Export-HotwmProfileAction -Profile $effectProfile -Path $effectsPath } | Should Throw
        { Export-HotwmProfileAction -Profile $buttonProfile -Path $buttonsPath } | Should Throw
        $traversalPath = Join-Path $templateDir 'nested\..\effects.json'
        { Export-HotwmProfileAction -Profile $effectProfile -Path $traversalPath } | Should Throw
        { New-HotwmEffectProfileAction -Profile $effectProfile -ConfigPath (Join-Path $templateDir 'nested\..\effects.json') } | Should Throw
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($effectsPath)) | Should Be ([Convert]::ToBase64String($effectsBefore))
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($buttonsPath)) | Should Be ([Convert]::ToBase64String($buttonsBefore))
    }

    It 'proposes only supported effects settings and preserves unrelated config keys' {
        $configPath = Join-Path $script:tempRoot 'hotw.json'
        $source = Get-Content -LiteralPath (Join-Path $script:profilesRoot 'config\hotw.json') -Raw -Encoding UTF8
        $object = $source | ConvertFrom-Json
        $object | Add-Member -NotePropertyName KeepMe -NotePropertyValue 'preserved'
        [IO.File]::WriteAllText($configPath, (ConvertTo-Json $object -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        $userProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Effects)[0] -Name 'Apply candidate'
        $userProfile.Settings.games | Add-Member -NotePropertyName Rambo -NotePropertyValue ([pscustomobject]@{ rumble=$false; hold_ms=220 })
        $action = New-HotwmEffectProfileAction -Profile $userProfile -ConfigPath $configPath
        $candidate = $action.ProposedContent | ConvertFrom-Json
        $candidate.global.hold_ms | Should Be $userProfile.Settings.global.hold_ms
        $candidate.KeepMe | Should Be 'preserved'
        $candidate.games.Rambo.rumble | Should Be $false
        $candidate.games.Rambo.hold_ms | Should Be 220
        $candidate.games.Rambo.leds | Should Be $object.games.Rambo.leds
        (Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json).KeepMe | Should Be 'preserved'
    }

    It 'refuses malformed current configuration without changing it' {
        $configPath = Join-Path $script:tempRoot 'broken-hotw.json'
        [IO.File]::WriteAllText($configPath, '{"global":{},"games":{}}', (New-Object System.Text.UTF8Encoding($false)))
        $before = [IO.File]::ReadAllText($configPath)
        $userProfile = New-HotwmUserProfile -Template (Get-HotwmTemplates Effects)[0] -Name 'Candidate'
        { New-HotwmEffectProfileAction -Profile $userProfile -ConfigPath $configPath } | Should Throw
        [IO.File]::ReadAllText($configPath) | Should Be $before
    }
}
