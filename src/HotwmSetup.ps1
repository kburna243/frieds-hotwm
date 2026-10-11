<#
.SYNOPSIS
    Single-action file proposal, confirmation, and recovery helpers for Hotwm.
.DESCRIPTION
    Confirmation is an application workflow guard, not an OS security boundary:
    arbitrary code running as the same user can modify files or call these functions.
    Callers must show the returned proposal and obtain a fresh, deliberate user decision.
    The named mutex coordinates cooperating Hotwm writers only; it does not isolate
    this process from arbitrary same-user writers.
#>

$script:HotwmActions = @{}
$script:HotwmResults = @{}

function Get-HotwmBytesHash {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-HotwmFileSnapshot {
    param([string]$CanonicalPath)
    if (Test-Path -LiteralPath $CanonicalPath -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($CanonicalPath)
        return [pscustomobject]@{ Exists = $true; Hash = (Get-HotwmBytesHash $bytes); Bytes = $bytes }
    }
    return [pscustomobject]@{ Exists = $false; Hash = $null; Bytes = $null }
}

function New-HotwmRegisteredAction {
    param([string]$Path, [byte[]]$ProposedBytes, [string]$Explanation, [string]$Kind, [string]$BackupSource, [object]$ExpectedOriginalSnapshot)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A target path is required.' }
    $canonical = [System.IO.Path]::GetFullPath($Path)
    $parent = [System.IO.Path]::GetDirectoryName($canonical)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Target directory does not exist: $parent" }
    $before = Get-HotwmFileSnapshot $canonical
    if ($null -ne $ExpectedOriginalSnapshot -and ($before.Exists -ne $ExpectedOriginalSnapshot.Exists -or ($before.Exists -and $before.Hash -ne $ExpectedOriginalSnapshot.Hash))) {
        throw 'Target changed while its proposal was being prepared; read it again and create a fresh proposal.'
    }
    $id = [Guid]::NewGuid().ToString('N')
    $action = [pscustomobject]@{
        Id = $id; Kind = $Kind; TargetPath = $canonical
        OriginalExists = $before.Exists; OriginalHash = $before.Hash
        ProposedBytes = $ProposedBytes; ProposedHash = (Get-HotwmBytesHash $ProposedBytes)
        ProposedContent = [System.Text.Encoding]::UTF8.GetString($ProposedBytes)
        Explanation = $Explanation; BackupSource = $BackupSource
    }
    $script:HotwmActions[$id] = @{
        Action = $action; State = 'proposed'; OriginalBytes = $before.Bytes
        TargetPath = $canonical; Kind = $Kind; OriginalExists = $before.Exists; OriginalHash = $before.Hash
        ProposedBytes = $ProposedBytes.Clone(); ProposedHash = $action.ProposedHash
        Explanation = $Explanation; BackupSource = $BackupSource
    }
    return $action
}

function New-HotwmFileAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content, [Parameter(Mandatory=$true)][string]$Explanation, [object]$ExpectedOriginalSnapshot)
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Content)
    New-HotwmRegisteredAction -Path $Path -ProposedBytes $bytes -Explanation $Explanation -Kind 'write' -BackupSource $null -ExpectedOriginalSnapshot $ExpectedOriginalSnapshot
}

function New-HotwmRestoreAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$AppliedResult, [Parameter(Mandatory=$true)][string]$Explanation)
    if (-not $AppliedResult.ResultId -or -not $script:HotwmResults.ContainsKey([string]$AppliedResult.ResultId)) { throw 'A verified successful action result is required to propose restoration.' }
    $proof = $script:HotwmResults[[string]$AppliedResult.ResultId]
    if (-not [object]::ReferenceEquals($proof.Result, $AppliedResult) -or -not $proof.Success -or -not $proof.BackupPath) { throw 'Result is not a verified, restorable action from this session.' }
    $current = Get-HotwmFileSnapshot $proof.TargetPath
    if (-not $current.Exists -or $current.Hash -ne $proof.PostHash) { throw 'Target has changed since the action; restoration is blocked.' }
    $backup = $proof.BackupPath
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-HotwmBytesHash ([System.IO.File]::ReadAllBytes($backup))) -ne $proof.PreHash) { throw 'Verified preimage backup is missing or changed.' }
    $bytes = [System.IO.File]::ReadAllBytes($backup)
    New-HotwmRegisteredAction -Path $proof.TargetPath -ProposedBytes $bytes -Explanation $Explanation -Kind 'restore' -BackupSource $backup -ExpectedOriginalSnapshot $current
}

function Update-HotwmJsonFileAction {
    <# Recursively merge dictionaries; supplied scalar/array values replace their matching property. #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][System.Collections.IDictionary]$Updates, [Parameter(Mandatory=$true)][string]$Explanation)
    $canonical = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) { throw "JSON configuration does not exist: $canonical" }
    $original = Get-HotwmFileSnapshot $canonical
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $raw = $utf8.GetString($original.Bytes) }
    catch { throw "Configuration is not valid UTF-8; it was not changed: $($_.Exception.Message)" }
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    try { $object = ConvertFrom-Json -InputObject $raw -ErrorAction Stop }
    catch { throw "Malformed JSON; configuration was not changed: $($_.Exception.Message)" }
    if ($null -eq $object -or $object -is [string] -or $object -is [ValueType] -or $object -is [array]) { throw 'JSON root must be an object.' }
    Merge-HotwmJsonObject -Target $object -Updates $Updates
    $json = ConvertTo-Json -InputObject $object -Depth 100
    New-HotwmFileAction -Path $canonical -Content $json -Explanation $Explanation -ExpectedOriginalSnapshot $original
}

function Merge-HotwmJsonObject {
    param([object]$Target, [System.Collections.IDictionary]$Updates)
    foreach ($key in $Updates.Keys) {
        if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) { throw 'Update property names must be non-empty.' }
        $existing = $Target.PSObject.Properties[[string]$key]
        $value = $Updates[$key]
        if ($null -ne $existing -and $value -is [System.Collections.IDictionary] -and $null -ne $existing.Value -and $existing.Value -isnot [array] -and $existing.Value -isnot [string] -and $existing.Value -isnot [ValueType]) {
            Merge-HotwmJsonObject -Target $existing.Value -Updates $value
        } elseif ($null -ne $existing) { $existing.Value = $value }
        else { $Target | Add-Member -NotePropertyName ([string]$key) -NotePropertyValue $value }
    }
}

function Invoke-HotwmFileAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Action, [Parameter(Mandatory=$true)][scriptblock]$Confirm)
    if (-not $Action.Id -or -not $script:HotwmActions.ContainsKey([string]$Action.Id)) { throw 'Action is unknown or was not created in this session.' }
    $entry = $script:HotwmActions[[string]$Action.Id]
    if (-not [object]::ReferenceEquals($entry.Action, $Action) -or $entry.State -ne 'proposed') { throw 'Action is invalid, modified, or already consumed.' }
    if ($Action.TargetPath -cne $entry.TargetPath -or $Action.Kind -cne $entry.Kind -or $Action.OriginalExists -ne $entry.OriginalExists -or $Action.OriginalHash -cne $entry.OriginalHash -or $Action.ProposedHash -cne $entry.ProposedHash -or $Action.Explanation -cne $entry.Explanation -or $Action.BackupSource -cne $entry.BackupSource) { throw 'Action details changed after review.' }
    if ((Get-HotwmBytesHash $Action.ProposedBytes) -ne $entry.ProposedHash) { throw 'Proposed content changed after review.' }
    if ($Action.ProposedContent -cne [System.Text.Encoding]::UTF8.GetString($entry.ProposedBytes)) { throw 'Displayed proposal content does not match the content to be written.' }
    if (-not (& $Confirm $Action)) { $entry.State = 'declined'; return [pscustomobject]@{ Success=$false; Status='declined'; BackupPath=$null } }
    if ($Action.TargetPath -cne $entry.TargetPath -or $Action.Kind -cne $entry.Kind -or $Action.OriginalExists -ne $entry.OriginalExists -or $Action.OriginalHash -cne $entry.OriginalHash -or $Action.ProposedHash -cne $entry.ProposedHash -or $Action.Explanation -cne $entry.Explanation -or $Action.BackupSource -cne $entry.BackupSource -or (Get-HotwmBytesHash $Action.ProposedBytes) -ne $entry.ProposedHash -or $Action.ProposedContent -cne [System.Text.Encoding]::UTF8.GetString($entry.ProposedBytes)) { throw 'Action details changed during confirmation.' }

    $canonical = $Action.TargetPath
    $nameHash = (Get-HotwmBytesHash ([System.Text.Encoding]::UTF8.GetBytes($canonical.ToUpperInvariant())))
    $mutex = New-Object System.Threading.Mutex($false, ('Global\HotwmFile-' + $nameHash))
    $locked = $false
    try { $locked = $mutex.WaitOne() } catch [System.Threading.AbandonedMutexException] { $locked = $true }
    try {
        if ($entry.State -ne 'proposed') { throw 'Action was already consumed.' }
        # Bind execution to the exact proposal and its original file state.
        if ((Get-HotwmBytesHash $entry.ProposedBytes) -ne $entry.ProposedHash) { throw 'Registered proposal content is invalid.' }
        $current = Get-HotwmFileSnapshot $entry.TargetPath
        if ($current.Exists -ne $entry.OriginalExists -or ($current.Exists -and $current.Hash -ne $entry.OriginalHash)) { throw 'Target changed after review; create a fresh proposal.' }
        if ($entry.Kind -eq 'restore') {
            if (-not (Test-Path -LiteralPath $entry.BackupSource -PathType Leaf) -or (Get-HotwmBytesHash ([System.IO.File]::ReadAllBytes($entry.BackupSource))) -ne $entry.ProposedHash) { throw 'Restore backup changed after review.' }
        }
        $entry.State = 'running'
        $backupPath = $null
        if ($current.Exists) {
            $backupDir = Join-Path ([System.IO.Path]::GetDirectoryName($canonical)) '.hotwm-backups'
            if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($backupDir) }
            $backupPath = Join-Path $backupDir (([System.IO.Path]::GetFileName($canonical)) + '.' + $Action.Id + '.bak')
            [System.IO.File]::WriteAllBytes($backupPath, $current.Bytes)
            if ((Get-HotwmBytesHash ([System.IO.File]::ReadAllBytes($backupPath))) -ne $entry.OriginalHash) { throw 'Preimage backup did not match the reviewed file.' }
        }
        $temp = Join-Path ([System.IO.Path]::GetDirectoryName($canonical)) ('.' + [System.IO.Path]::GetFileName($canonical) + '.' + $Action.Id + '.tmp')
        try {
            if ($current.Exists) {
                [System.IO.File]::Copy($canonical, $temp)
                $stream = New-Object System.IO.FileStream($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try { $stream.Write([byte[]]$entry.ProposedBytes, 0, $entry.ProposedBytes.Length); $stream.Flush($true) }
                finally { $stream.Dispose() }
                $replaceBackup = $temp + '.replace-backup'
                try {
                    [System.IO.File]::Replace($temp, $canonical, $replaceBackup, $false)
                } finally {
                    if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force }
                }
            }
            else {
                [System.IO.File]::WriteAllBytes($temp, [byte[]]$entry.ProposedBytes)
                [System.IO.File]::Move($temp, $canonical)
            }
            $written = [System.IO.File]::ReadAllBytes($canonical)
            if ((Get-HotwmBytesHash $written) -ne $Action.ProposedHash) { throw 'Written file did not match the reviewed content.' }
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
        $entry.State = 'succeeded'
        $result = [pscustomobject]@{ ResultId=([Guid]::NewGuid().ToString('N')); Success=$true; Status='succeeded'; BackupPath=$backupPath }
        $script:HotwmResults[$result.ResultId] = @{ Result=$result; Success=$true; TargetPath=$canonical; BackupPath=$backupPath; PreHash=$Action.OriginalHash; PostHash=$Action.ProposedHash }
        return $result
    } catch {
        $entry.State = 'failed'
        throw
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
