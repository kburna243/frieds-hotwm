<#
.SYNOPSIS
    Editable, validated Gunmote layout proposals backed by the Kit 1.4.0 schema.
.DESCRIPTION
    Layout and Keymaps writes use the shared single-action confirmation layer.
    UI callers must use the Gunmote invoke wrappers so the running-process and
    installed-layout dependency checks happen after confirmation and before write.
    These checks are an application workflow guard, not an OS security boundary.
#>

if (-not (Get-Command New-HotwmFileAction -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'HotwmSetup.ps1')
}

$script:HotwmGunmoteCatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\templates\gunmote-layouts.json'
$script:HotwmGunmoteActions = @{}
$script:HotwmGunmoteApplied = @{}

function Get-HotwmGunmoteProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Copy-HotwmGunmoteObject {
    param([object]$Object)
    ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Object -Depth 100)
}

function ConvertFrom-HotwmGunmoteSnapshot {
    param([object]$Snapshot, [string]$Description)
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $raw = $utf8.GetString($Snapshot.Bytes) }
    catch { throw "$Description is not valid UTF-8: $($_.Exception.Message)" }
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    try { return (ConvertFrom-Json -InputObject $raw -ErrorAction Stop) }
    catch { throw "$Description is malformed JSON: $($_.Exception.Message)" }
}

function Test-HotwmGunmoteTemplatePath {
    param([string]$Path)
    $templateDirectory = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'config\templates')).TrimEnd('\')
    $canonical = [System.IO.Path]::GetFullPath($Path)
    return ($canonical.StartsWith(($templateDirectory + '\'), [StringComparison]::OrdinalIgnoreCase) -or $canonical -ieq $templateDirectory)
}

function Get-HotwmGunmoteLayouts {
    [CmdletBinding()]
    param()
    if (-not (Test-Path -LiteralPath $script:HotwmGunmoteCatalogPath -PathType Leaf)) { throw 'The shipped Gunmote layout catalog is missing.' }
    $catalog = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($script:HotwmGunmoteCatalogPath, [System.Text.Encoding]::UTF8)) -ErrorAction Stop
    if ($catalog.schema_version -ne 1 -or $catalog.source.version -ne '1.4.0' -or $null -eq $catalog.layouts) { throw 'The shipped Gunmote layout catalog has invalid provenance or structure.' }
    Copy-HotwmGunmoteObject $catalog
}

function Test-HotwmGunmoteText {
    param([object]$Value, [int]$MaximumLength)
    if ($Value -isnot [string] -or $Value.Trim().Length -eq 0 -or $Value.Length -gt $MaximumLength) { return $false }
    foreach ($character in $Value.ToCharArray()) { if ([char]::IsControl($character)) { return $false } }
    return $true
}

function Test-HotwmGunmoteLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout)
    $title = Get-HotwmGunmoteProperty $Layout 'Title'
    $all = Get-HotwmGunmoteProperty $Layout 'All'
    if (-not (Test-HotwmGunmoteText $title 64) -or $null -eq $all) { throw 'Layout must have a valid Title and All object.' }
    foreach ($stateName in @('OnScreen', 'OffScreen')) {
        $map = Get-HotwmGunmoteProperty $all $stateName
        if ($null -eq $map -or $map -is [string] -or $map -is [array] -or $map -is [ValueType]) { throw "Layout All.$stateName must be a mapping object." }
        $properties = if ($map -is [System.Collections.IDictionary]) { @($map.Keys) } else { @($map.PSObject.Properties | ForEach-Object { $_.Name }) }
        foreach ($key in $properties) {
            $value = Get-HotwmGunmoteProperty $map ([string]$key)
            if (-not (Test-HotwmGunmoteText ([string]$key) 64)) { throw "Layout $stateName contains an invalid input name." }
            if (-not (Test-HotwmGunmoteText $value 128)) { throw "Layout $stateName mapping '$key' must be a non-empty string of at most 128 characters without control characters." }
        }
    }
    return $true
}

function New-HotwmGunmoteUserLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Kind, [string]$Title)
    $catalog = Get-HotwmGunmoteLayouts
    $layout = Get-HotwmGunmoteProperty $catalog.layouts $Kind
    if ($null -eq $layout) { throw "Unknown shipped layout kind '$Kind'." }
    $copy = Copy-HotwmGunmoteObject $layout
    if ($PSBoundParameters.ContainsKey('Title')) { $copy.Title = $Title }
    Test-HotwmGunmoteLayout $copy | Out-Null
    return $copy
}

function Import-HotwmGunmoteLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $canonical = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) { throw "Layout file does not exist: $canonical" }
    try { $layout = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($canonical, [System.Text.Encoding]::UTF8)) -ErrorAction Stop }
    catch { throw "Layout JSON is invalid: $($_.Exception.Message)" }
    Test-HotwmGunmoteLayout $layout | Out-Null
    return $layout
}

function Get-HotwmGunmoteTargetPath {
    param([string]$KeymapsDir, [string]$FileName)
    $directory = [System.IO.Path]::GetFullPath($KeymapsDir)
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Keymaps directory does not exist: $directory" }
    if (Test-HotwmGunmoteTemplatePath $directory) { throw 'Choose a Gunmote Keymaps directory outside the shipped templates folder.' }
    if ($FileName -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]{0,70}\.json$') { throw 'Choose a simple .json filename without path separators.' }
    $reserved = @('default.json', 'mouse43.json', 'keymaps.json')
    $catalog = Get-HotwmGunmoteLayouts
    foreach ($layout in $catalog.layouts.PSObject.Properties) {
        if ($layout.Name) { $reserved += ('rck_' + $layout.Name.ToLowerInvariant() + '.json') }
    }
    # The source catalog uses explicit file names; keep these exact Kit originals reserved.
    $reserved += @('rck_menu.json','rck_pad43.json','rck_tp.json','rck_mouse.json','rck_mouse43.json','rck_mouseshoot.json')
    if ($reserved -contains $FileName.ToLowerInvariant()) { throw 'Shipped Gunmote layouts are read-only. Choose a new user filename.' }
    $target = [System.IO.Path]::GetFullPath((Join-Path $directory $FileName))
    if ([System.IO.Path]::GetDirectoryName($target) -ine $directory.TrimEnd('\')) { throw 'Layout target must be directly inside the chosen Keymaps directory.' }
    return $target
}

function Merge-HotwmGunmoteObject {
    param([object]$Target, [object]$Updates)
    $updateProperties = if ($Updates -is [System.Collections.IDictionary]) { @($Updates.Keys) } else { @($Updates.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($name in $updateProperties) {
        $value = Get-HotwmGunmoteProperty $Updates ([string]$name)
        $existing = Get-HotwmGunmoteProperty $Target ([string]$name)
        if ($null -ne $existing -and $null -ne $value -and $existing -isnot [array] -and $existing -isnot [string] -and $existing -isnot [ValueType] -and $value -isnot [array] -and $value -isnot [string] -and $value -isnot [ValueType]) {
            Merge-HotwmGunmoteObject -Target $existing -Updates $value
        } elseif ($Target -is [System.Collections.IDictionary]) { $Target[[string]$name] = $value }
        elseif ($null -ne $Target.PSObject.Properties[[string]$name]) { $Target.PSObject.Properties[[string]$name].Value = $value }
        else { $Target | Add-Member -NotePropertyName ([string]$name) -NotePropertyValue $value }
    }
}

function New-HotwmGunmoteLayoutAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Layout, [Parameter(Mandatory=$true)][string]$KeymapsDir, [Parameter(Mandatory=$true)][string]$FileName)
    Test-HotwmGunmoteLayout $Layout | Out-Null
    $target = Get-HotwmGunmoteTargetPath -KeymapsDir $KeymapsDir -FileName $FileName
    $original = Get-HotwmFileSnapshot $target
    $contentObject = Copy-HotwmGunmoteObject $Layout
    if ($original.Exists) {
        $existing = ConvertFrom-HotwmGunmoteSnapshot -Snapshot $original -Description 'Existing layout'
        Merge-HotwmGunmoteObject -Target $existing -Updates $contentObject
        $contentObject = $existing
    }
    Test-HotwmGunmoteLayout $contentObject | Out-Null
    $content = ConvertTo-Json -InputObject $contentObject -Depth 100
    $action = New-HotwmFileAction -Path $target -Content $content -Explanation ("Write Gunmote layout '{0}' to {1}" -f $contentObject.Title, $FileName) -ExpectedOriginalSnapshot $original
    $script:HotwmGunmoteActions[$action.Id] = @{ Action=$action; Type='layout'; Path=$target }
    return $action
}

function Test-HotwmGunmoteClosed {
    param([scriptblock]$ProcessChecker)
    if ($ProcessChecker) { return [bool](& $ProcessChecker) }
    return (@(Get-Process -Name 'Gunmote' -ErrorAction SilentlyContinue).Count -eq 0)
}

function Invoke-HotwmGunmoteAction {
    param([object]$Action, [scriptblock]$Confirm, [scriptblock]$ProcessChecker)
    if (-not $script:HotwmGunmoteActions.ContainsKey([string]$Action.Id)) { throw 'Action was not created by the Gunmote proposal layer.' }
    $registered = $script:HotwmGunmoteActions[[string]$Action.Id]
    if (-not [object]::ReferenceEquals($registered.Action, $Action)) { throw 'Gunmote action details were replaced.' }
    $userConfirmation = $Confirm
    $guardedConfirm = {
        param($proposal)
        if (-not (& $userConfirmation $proposal)) { return $false }
        if (-not (Test-HotwmGunmoteClosed $ProcessChecker)) { throw 'Gunmote is running. Close it, then review and confirm the action again.' }
        if ($registered.Type -eq 'chooser') {
            $dependency = $script:HotwmGunmoteApplied[[string]$registered.LayoutResultId]
            if ($null -eq $dependency -or -not [object]::ReferenceEquals($dependency.PublicResult, $registered.LayoutResult)) { throw 'Chooser entry requires a verified layout write in this session.' }
            $snapshot = Get-HotwmFileSnapshot $dependency.Path
            if (-not $snapshot.Exists -or $snapshot.Hash -ne $dependency.Hash) { throw 'Installed layout changed after review; chooser entry is blocked.' }
        }
        return $true
    }
    $result = Invoke-HotwmFileAction -Action $Action -Confirm $guardedConfirm
    if ($registered.Type -eq 'layout' -and $result.Success) {
        $snapshot = Get-HotwmFileSnapshot $registered.Path
        if (-not $snapshot.Exists -or $snapshot.Hash -ne $Action.ProposedHash) { throw 'Written layout no longer matches the approved content.' }
        $proof = [pscustomobject]@{ ResultId=([Guid]::NewGuid().ToString('N')); Success=$true; Status='succeeded'; LayoutPath=$registered.Path; LayoutHash=$snapshot.Hash; BackupPath=$result.BackupPath }
        $script:HotwmGunmoteApplied[$proof.ResultId] = @{ PublicResult=$proof; Path=$registered.Path; Hash=$snapshot.Hash }
        return $proof
    }
    return $result
}

function Invoke-HotwmGunmoteLayoutAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Action, [Parameter(Mandatory=$true)][scriptblock]$Confirm, [scriptblock]$ProcessChecker)
    $entry = $script:HotwmGunmoteActions[[string]$Action.Id]
    if ($null -eq $entry -or $entry.Type -ne 'layout') { throw 'A proposed layout write action is required.' }
    Invoke-HotwmGunmoteAction -Action $Action -Confirm $Confirm -ProcessChecker $ProcessChecker
}

function New-HotwmGunmoteChooserAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$LayoutResult, [Parameter(Mandatory=$true)][string]$KeymapsPath, [Parameter(Mandatory=$true)][string]$LayoutTitle)
    if (-not $LayoutResult.ResultId -or -not $script:HotwmGunmoteApplied.ContainsKey([string]$LayoutResult.ResultId)) { throw 'A successful, verified layout write result is required.' }
    $proof = $script:HotwmGunmoteApplied[[string]$LayoutResult.ResultId]
    if (-not [object]::ReferenceEquals($proof.PublicResult, $LayoutResult)) { throw 'The layout result was modified or fabricated.' }
    if (-not $LayoutResult.Success -or $LayoutResult.LayoutPath -cne $proof.Path -or $LayoutResult.LayoutHash -cne $proof.Hash) { throw 'The layout result details no longer match the verified write.' }
    if (-not (Test-HotwmGunmoteText $LayoutTitle 64)) { throw 'Chooser title must be non-empty and at most 64 characters.' }
    $layoutPath = $proof.Path
    if ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($KeymapsPath)) -ine [System.IO.Path]::GetDirectoryName($layoutPath)) { throw 'Layout and Keymaps.json must be in the same chosen Keymaps directory.' }
    $layoutNow = Get-HotwmFileSnapshot $layoutPath
    if (-not $layoutNow.Exists -or $layoutNow.Hash -ne $proof.Hash) { throw 'The installed layout changed; create a new verified layout proposal.' }
    $keymapsCanonical = [System.IO.Path]::GetFullPath($KeymapsPath)
    if ([System.IO.Path]::GetFileName($keymapsCanonical) -ine 'Keymaps.json' -or -not (Test-Path -LiteralPath $keymapsCanonical -PathType Leaf)) { throw 'KeymapsPath must be an existing Keymaps.json file.' }
    if (Test-HotwmGunmoteTemplatePath $keymapsCanonical) { throw 'Keymaps.json must be outside the shipped templates folder.' }
    $original = Get-HotwmFileSnapshot $keymapsCanonical
    $keymaps = ConvertFrom-HotwmGunmoteSnapshot -Snapshot $original -Description 'Keymaps.json'
    if ($null -eq $keymaps -or $keymaps -is [array] -or $keymaps -is [string]) { throw 'Keymaps.json root must be an object.' }
    $chooser = Get-HotwmGunmoteProperty $keymaps 'LayoutChooser'
    if ($null -eq $chooser) { $chooser = @() }
    if ($chooser -isnot [array]) { throw 'Keymaps.json LayoutChooser must be an array.' }
    $fileName = [System.IO.Path]::GetFileName($layoutPath)
    foreach ($item in $chooser) { if ([string]::Equals([string](Get-HotwmGunmoteProperty $item 'Keymap'), $fileName, [StringComparison]::OrdinalIgnoreCase)) { throw 'This layout already has a chooser entry.' } }
    $newEntry = [pscustomobject]@{ Title=$LayoutTitle; Keymap=$fileName }
    if ($keymaps -is [System.Collections.IDictionary]) { $keymaps['LayoutChooser'] = @($chooser) + @($newEntry) }
    elseif ($null -ne $keymaps.PSObject.Properties['LayoutChooser']) { $keymaps.LayoutChooser = @($chooser) + @($newEntry) }
    else { $keymaps | Add-Member -NotePropertyName 'LayoutChooser' -NotePropertyValue (@($chooser) + @($newEntry)) }
    $content = ConvertTo-Json -InputObject $keymaps -Depth 100
    $action = New-HotwmFileAction -Path $keymapsCanonical -Content $content -Explanation ("Add '{0}' to the Gunmote layout chooser" -f $LayoutTitle) -ExpectedOriginalSnapshot $original
    $script:HotwmGunmoteActions[$action.Id] = @{ Action=$action; Type='chooser'; Path=$keymapsCanonical; LayoutResult=$LayoutResult; LayoutResultId=$LayoutResult.ResultId }
    return $action
}

function Invoke-HotwmGunmoteChooserAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Action, [Parameter(Mandatory=$true)][scriptblock]$Confirm, [scriptblock]$ProcessChecker)
    $entry = $script:HotwmGunmoteActions[[string]$Action.Id]
    if ($null -eq $entry -or $entry.Type -ne 'chooser') { throw 'A proposed chooser update action is required.' }
    Invoke-HotwmGunmoteAction -Action $Action -Confirm $Confirm -ProcessChecker $ProcessChecker
}
