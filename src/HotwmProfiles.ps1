#requires -Version 5.1
<#
.SYNOPSIS
    Validates shipped Hotwm profile templates and creates file-change proposals.
.DESCRIPTION
    Discovery/import is read-only. Export and configuration changes are returned
    as New-HotwmFileAction proposals; this module never writes files itself.
#>

function Get-HotwmTemplates {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('Effects','Buttons')][string]$Kind)

    $templatePath = Join-Path $PSScriptRoot ('..\config\templates\{0}.json' -f $Kind.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw "Shipped $Kind templates are missing." }
    try { $catalog = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Shipped $Kind template catalog is invalid JSON: $($_.Exception.Message)" }
    if ($catalog.SchemaVersion -ne 1 -or $catalog.Kind -cne $Kind.ToLowerInvariant() -or @($catalog.Templates).Count -eq 0) {
        throw "Shipped $Kind template catalog has an unsupported schema."
    }
    foreach ($template in $catalog.Templates) {
        $template | Add-Member -NotePropertyName Kind -NotePropertyValue $catalog.Kind -Force
        $check = Test-HotwmProfile -Profile (New-HotwmProfileObject -Template $template -Name $template.Name)
        if (-not $check.Valid) { throw "Shipped template '$($template.Id)' is invalid: $($check.Errors -join '; ')" }
    }
    return @($catalog.Templates)
}

function New-HotwmProfileObject {
    param([object]$Template, [string]$Name)
    $templateJson = ConvertTo-Json -InputObject $Template -Depth 30
    $copy = ConvertFrom-Json -InputObject $templateJson
    $newProfile = [ordered]@{ SchemaVersion = 1; Kind = [string]$copy.Kind }
    if ($copy.Kind -eq 'effects') {
        $newProfile.Name = $Name
        $newProfile.SourceTemplate = [string]$copy.Id
        $newProfile.Settings = $copy.Settings
    } else {
        $newProfile.Name = $Name
        $newProfile.SourceTemplate = [string]$copy.Id
        $newProfile.TargetCapability = [string]$copy.TargetCapability
        $newProfile.Intents = $copy.Intents
    }
    return [pscustomobject]$newProfile
}

function New-HotwmUserProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Template, [Parameter(Mandatory=$true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 80) { throw 'Profile name must contain 1 to 80 characters.' }
    $validTemplate = @((Get-HotwmTemplates -Kind Effects) + (Get-HotwmTemplates -Kind Buttons) | Where-Object { $_.Id -ceq $Template.Id })
    if ($validTemplate.Count -ne 1) { throw 'Template must be one of the validated shipped templates.' }
    $userProfile = New-HotwmProfileObject -Template $validTemplate[0] -Name $Name.Trim()
    Assert-HotwmProfile -Profile $userProfile | Out-Null
    return $userProfile
}

function Test-HotwmProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Alias('Profile')][AllowNull()][object]$ProfileObject)

    $errors = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $ProfileObject -or $ProfileObject -is [array] -or $ProfileObject -is [string] -or $ProfileObject -is [ValueType]) {
        $errors.Add('Profile root must be an object.')
    } else {
        if (($ProfileObject.SchemaVersion -isnot [int] -and $ProfileObject.SchemaVersion -isnot [long]) -or $ProfileObject.SchemaVersion -ne 1) { $errors.Add('SchemaVersion must be integer 1.') }
        if ($ProfileObject.Kind -cnotin @('effects','buttons')) { $errors.Add('Kind must be effects or buttons.') }
        if ([string]::IsNullOrWhiteSpace([string]$ProfileObject.Name) -or ([string]$ProfileObject.Name).Length -gt 80) { $errors.Add('Name must contain 1 to 80 characters.') }
        if ([string]::IsNullOrWhiteSpace([string]$ProfileObject.SourceTemplate)) { $errors.Add('SourceTemplate is required.') }
        if ($ProfileObject.Kind -eq 'effects') {
            $allowedRoot = @('SchemaVersion','Kind','Name','SourceTemplate','Settings')
            foreach ($property in $ProfileObject.PSObject.Properties) { if ($property.Name -notin $allowedRoot) { $errors.Add("Unsupported effects profile field: $($property.Name).") } }
            $settings = $ProfileObject.Settings
            if ($null -eq $settings -or $settings -is [array] -or $settings -is [string] -or @($settings.PSObject.Properties.Name) -notcontains 'global' -or @($settings.PSObject.Properties.Name) -notcontains 'games') {
                $errors.Add('Effects Settings must contain global and games objects.')
            } else {
                foreach ($property in $settings.PSObject.Properties) { if ($property.Name -notin @('global','games')) { $errors.Add("Unsupported settings section: $($property.Name).") } }
                $globalSettings = $settings.global
                if ($null -eq $globalSettings -or $globalSettings -is [array] -or $globalSettings -is [string] -or $globalSettings -is [ValueType]) { $errors.Add('Settings.global must be an object.') }
                $gamesSettings = $settings.games
                if ($null -eq $gamesSettings -or $gamesSettings -is [array] -or $gamesSettings -is [string] -or $gamesSettings -is [ValueType]) { $errors.Add('Settings.games must be an object.') }
                $fields = @('hold_ms','ammo_drop_shot','led_mode','trace_enabled')
                foreach ($requiredField in $fields) { if ($null -eq $globalSettings.PSObject.Properties[$requiredField]) { $errors.Add("Missing global effect field: $requiredField.") } }
                foreach ($property in $globalSettings.PSObject.Properties) { if ($property.Name -notin $fields) { $errors.Add("Unsupported global effect field: $($property.Name).") } }
                if (($globalSettings.hold_ms -isnot [int] -and $globalSettings.hold_ms -isnot [long]) -or $globalSettings.hold_ms -lt 80 -or $globalSettings.hold_ms -gt 300) { $errors.Add('global.hold_ms must be an integer from 80 through 300.') }
                if ($globalSettings.ammo_drop_shot -isnot [bool]) { $errors.Add('global.ammo_drop_shot must be boolean.') }
                if ($globalSettings.led_mode -cnotin @('life_bar','none')) { $errors.Add('global.led_mode must be life_bar or none.') }
                if ($globalSettings.trace_enabled -isnot [bool]) { $errors.Add('global.trace_enabled must be boolean.') }
                foreach ($game in $gamesSettings.PSObject.Properties) {
                    if ($null -eq $game.Value -or $game.Value -is [array] -or $game.Value -is [string] -or $game.Value -is [ValueType]) { $errors.Add("Game '$($game.Name)' must be an object."); continue }
                    foreach ($field in $game.Value.PSObject.Properties) {
                        if ($field.Name -in @('rumble','leds')) {
                            if ($field.Value -isnot [bool]) { $errors.Add("Game '$($game.Name)' $($field.Name) must be boolean.") }
                        } elseif ($field.Name -eq 'hold_ms') {
                            if (($field.Value -isnot [int] -and $field.Value -isnot [long]) -or $field.Value -lt 80 -or $field.Value -gt 300) { $errors.Add("Game '$($game.Name)' hold_ms must be an integer from 80 through 300.") }
                        } else { $errors.Add("Unsupported game effect field: $($game.Name).$($field.Name).") }
                    }
                }
            }
        } elseif ($ProfileObject.Kind -eq 'buttons') {
            $allowedRoot = @('SchemaVersion','Kind','Name','SourceTemplate','TargetCapability','Intents')
            foreach ($property in $ProfileObject.PSObject.Properties) { if ($property.Name -notin $allowedRoot) { $errors.Add("Unsupported buttons profile field: $($property.Name).") } }
            if ($ProfileObject.TargetCapability -cne 'manual-or-kit-profile') { $errors.Add('Button intents must remain manual-or-kit-profile; hardware bindings are unsupported.') }
            if (@($ProfileObject.Intents).Count -eq 0) { $errors.Add('At least one semantic button intent is required.') }
            $ids = @()
            $allowedIntents = @('shoot','reload','start','coin','pause')
            foreach ($intent in $ProfileObject.Intents) {
                if (@($intent.PSObject.Properties.Name) | Where-Object { $_ -notin @('Id','Label') }) { $errors.Add('Button intents may contain only Id and Label.') }
                if ([string]::IsNullOrWhiteSpace([string]$intent.Id) -or [string]::IsNullOrWhiteSpace([string]$intent.Label)) { $errors.Add('Each button intent requires an Id and Label.') }
                if ($intent.Id -notin $allowedIntents) { $errors.Add("Unsupported semantic intent: $($intent.Id).") }
                $ids += [string]$intent.Id
            }
            if (@($ids | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $errors.Add('Button intent IDs must be unique.') }
        }
    }
    [pscustomobject]@{ Valid = ($errors.Count -eq 0); Errors = @($errors.ToArray()) }
}

function Assert-HotwmProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][Alias('Profile')][object]$ProfileObject)
    $result = Test-HotwmProfile -Profile $ProfileObject
    if (-not $result.Valid) { throw ('Invalid Hotwm profile: ' + ($result.Errors -join ' ')) }
    return $ProfileObject
}

function Assert-HotwmNotShippedTemplatePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $templateRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\config\templates')).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $target = [System.IO.Path]::GetFullPath($Path)
    $rootWithSeparator = $templateRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($target.Equals($templateRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Shipped profile templates are immutable and cannot be proposal targets.'
    }
}

function Import-HotwmProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Profile file does not exist: $Path" }
    try { $importedProfile = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($Path), [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "Profile file is invalid JSON: $($_.Exception.Message)" }
    Assert-HotwmProfile -Profile $importedProfile
}

function Export-HotwmProfileAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Profile, [Parameter(Mandatory=$true)][string]$Path)
    Assert-HotwmProfile -Profile $Profile | Out-Null
    Assert-HotwmNotShippedTemplatePath -Path $Path
    if (-not (Get-Command New-HotwmFileAction -ErrorAction SilentlyContinue)) { throw 'Dot-source HotwmSetup.ps1 before proposing a profile export.' }
    $json = ConvertTo-Json -InputObject $Profile -Depth 30
    New-HotwmFileAction -Path $Path -Content $json -Explanation ("Export validated {0} profile '{1}'" -f $Profile.Kind, $Profile.Name)
}

function New-HotwmEffectProfileAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Profile, [Parameter(Mandatory=$true)][string]$ConfigPath)
    Assert-HotwmProfile -Profile $Profile | Out-Null
    if ($Profile.Kind -cne 'effects') { throw 'Only effects profiles can update hotw.json.' }
    Assert-HotwmNotShippedTemplatePath -Path $ConfigPath
    if (-not (Get-Command Update-HotwmJsonFileAction -ErrorAction SilentlyContinue)) { throw 'Dot-source HotwmSetup.ps1 before proposing a configuration change.' }
    $configPath = [System.IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Configuration does not exist: $configPath" }
    try { $config = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Current hotw.json is invalid JSON; no proposal was created.' }
    if ($null -eq $config.global -or $null -eq $config.games) { throw 'Current hotw.json must contain global and games objects.' }
    if (($config.global.hold_ms -isnot [int] -and $config.global.hold_ms -isnot [long]) -or $config.global.hold_ms -lt 80 -or $config.global.hold_ms -gt 300 -or
        $config.global.ammo_drop_shot -isnot [bool] -or $config.global.led_mode -cnotin @('life_bar','none') -or $config.global.trace_enabled -isnot [bool]) {
        throw 'Current hotw.json global settings do not match the supported schema.'
    }
    foreach ($game in $config.games.PSObject.Properties) {
        if ($null -eq $game.Value -or $game.Value -is [array] -or $game.Value -is [string] -or $game.Value -is [ValueType] -or $game.Value.rumble -isnot [bool] -or $game.Value.leds -isnot [bool]) { throw "Current game profile '$($game.Name)' must define boolean rumble and leds." }
        if ($null -ne $game.Value.PSObject.Properties['hold_ms'] -and (($game.Value.hold_ms -isnot [int] -and $game.Value.hold_ms -isnot [long]) -or $game.Value.hold_ms -lt 80 -or $game.Value.hold_ms -gt 300)) { throw "Current game profile '$($game.Name)' hold_ms must be an integer from 80 through 300." }
    }
    foreach ($game in $Profile.Settings.games.PSObject.Properties) {
        if ($null -eq $config.games.PSObject.Properties[$game.Name]) { throw "Game '$($game.Name)' is not present in hotw.json." }
    }
    $updates = @{
        global = @{
            hold_ms = [int]$Profile.Settings.global.hold_ms
            ammo_drop_shot = [bool]$Profile.Settings.global.ammo_drop_shot
            led_mode = [string]$Profile.Settings.global.led_mode
            trace_enabled = [bool]$Profile.Settings.global.trace_enabled
        }
        games = @{}
    }
    foreach ($game in $Profile.Settings.games.PSObject.Properties) {
        $gameUpdate = @{}
        foreach ($field in $game.Value.PSObject.Properties) {
            if ($field.Name -eq 'hold_ms') { $gameUpdate[$field.Name] = [int]$field.Value }
            else { $gameUpdate[$field.Name] = [bool]$field.Value }
        }
        $updates.games[$game.Name] = $gameUpdate
    }
    Update-HotwmJsonFileAction -Path $configPath -Updates $updates -Explanation ("Propose supported effects settings from profile '{0}' for review" -f $Profile.Name)
}
