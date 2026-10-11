$script:repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:repoRoot 'src\HotwmSetup.ps1')

Describe 'Hotwm single-file action proposals' {
    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('hotwm-action-' + [Guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:testRoot)
        $script:target = Join-Path $script:testRoot 'sample.txt'
        [System.IO.File]::WriteAllText($script:target, 'before', (New-Object System.Text.UTF8Encoding($false)))
    }
    AfterEach { Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue }

    It 'declined confirmation does not write anything' {
        $action = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $result = Invoke-HotwmFileAction -Action $action -Confirm { param($proposal) return $false }
        $result.Status | Should Be 'declined'
        [System.IO.File]::ReadAllText($script:target) | Should Be 'before'
        (Get-ChildItem -LiteralPath $script:testRoot -Recurse).Count | Should Be 1
    }

    It 'rejects a modified proposal and a changed preimage' {
        $changedAction = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $changedAction.ProposedHash = 'tampered'
        { Invoke-HotwmFileAction -Action $changedAction -Confirm { return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'before'

        $changedTarget = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $changedTarget.TargetPath = Join-Path $script:testRoot 'other.txt'
        { Invoke-HotwmFileAction -Action $changedTarget -Confirm { return $true } } | Should Throw
        (Test-Path -LiteralPath (Join-Path $script:testRoot 'other.txt')) | Should Be $false

        $fakeGrant = [pscustomobject]@{ Id='fabricated'; TargetPath=$script:target; Approved=$true }
        { Invoke-HotwmFileAction -Action $fakeGrant -Confirm { return $true } } | Should Throw

        $staleAction = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        [System.IO.File]::WriteAllText($script:target, 'foreign', (New-Object System.Text.UTF8Encoding($false)))
        { Invoke-HotwmFileAction -Action $staleAction -Confirm { return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'foreign'
    }

    It 'consumes an action once and rejects replay' {
        $action = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $result = Invoke-HotwmFileAction -Action $action -Confirm { return $true }
        $result.Success | Should Be $true
        { Invoke-HotwmFileAction -Action $action -Confirm { return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'after'
    }

    It 'rejects a forged preview before or during the confirmation callback' {
        $beforeCallback = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $beforeCallback.ProposedContent = 'different displayed text'
        { Invoke-HotwmFileAction -Action $beforeCallback -Confirm { return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'before'

        $duringCallback = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        { Invoke-HotwmFileAction -Action $duringCallback -Confirm { param($proposal) $proposal.ProposedContent = 'different displayed text'; return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'before'
    }

    It 'backs up a successful write and restores only after a new confirmation' {
        $action = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $applied = Invoke-HotwmFileAction -Action $action -Confirm { return $true }
        (Test-Path -LiteralPath $applied.BackupPath) | Should Be $true
        [System.IO.File]::ReadAllText($applied.BackupPath) | Should Be 'before'
        $restore = New-HotwmRestoreAction -AppliedResult $applied -Explanation 'Restore sample'
        $restored = Invoke-HotwmFileAction -Action $restore -Confirm { param($proposal) return $proposal.Kind -eq 'restore' }
        $restored.Success | Should Be $true
        [System.IO.File]::ReadAllText($script:target) | Should Be 'before'
    }

    It 'rejects restore proposals after foreign edits before or after proposal' {
        $action = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $applied = Invoke-HotwmFileAction -Action $action -Confirm { return $true }
        [System.IO.File]::WriteAllText($script:target, 'foreign-before', (New-Object System.Text.UTF8Encoding($false)))
        { New-HotwmRestoreAction -AppliedResult $applied -Explanation 'Restore sample' } | Should Throw

        $action2 = New-HotwmFileAction -Path $script:target -Content 'after2' -Explanation 'Change sample again'
        $applied2 = Invoke-HotwmFileAction -Action $action2 -Confirm { return $true }
        $restore2 = New-HotwmRestoreAction -AppliedResult $applied2 -Explanation 'Restore sample'
        [System.IO.File]::WriteAllText($script:target, 'foreign-after', (New-Object System.Text.UTF8Encoding($false)))
        { Invoke-HotwmFileAction -Action $restore2 -Confirm { return $true } } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'foreign-after'
    }

    It 'rejects a restore target changed between eligibility check and proposal registration' {
        $action = New-HotwmFileAction -Path $script:target -Content 'after' -Explanation 'Change sample'
        $applied = Invoke-HotwmFileAction -Action $action -Confirm { return $true }
        $postimage = Get-HotwmFileSnapshot ([System.IO.Path]::GetFullPath($script:target))
        [System.IO.File]::WriteAllText($script:target, 'foreign-during-restore-proposal', (New-Object System.Text.UTF8Encoding($false)))
        $backup = [System.IO.File]::ReadAllBytes($applied.BackupPath)
        { New-HotwmRegisteredAction -Path $script:target -ProposedBytes $backup -Explanation 'Restore sample' -Kind 'restore' -BackupSource $applied.BackupPath -ExpectedOriginalSnapshot $postimage } | Should Throw
        [System.IO.File]::ReadAllText($script:target) | Should Be 'foreign-during-restore-proposal'
    }

    It 'preserves unknown JSON properties when merging a named property' {
        $jsonPath = Join-Path $script:testRoot 'hotw.json'
        $jsonText = '{"global":{"hold_ms":150,"future":7},"games":{"game1":{"enabled":true,"future_game":"keep"}},"vendor":{"keep":true}}'
        $jsonEncoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllBytes($jsonPath, $jsonEncoding.GetPreamble() + $jsonEncoding.GetBytes($jsonText))
        $proposal = Update-HotwmJsonFileAction -Path $jsonPath -Updates @{ global = @{ hold_ms = 250 } } -Explanation 'Update hold duration'
        $proposal | Should Not Be $null
        $proposal.ProposedContent | Should Match 'vendor'
        $proposal.ProposedContent | Should Match 'future'
        $proposal.ProposedContent | Should Match 'future_game'
        $result = Invoke-HotwmFileAction -Action $proposal -Confirm { return $true }
        $result.Success | Should Be $true
        $saved = ConvertFrom-Json ([System.IO.File]::ReadAllText($jsonPath))
        $saved.global.hold_ms | Should Be 250
        $saved.global.future | Should Be 7
        $saved.vendor.keep | Should Be $true
        $saved.games.game1.future_game | Should Be 'keep'
    }

    It 'blocks malformed JSON without changing the file' {
        $jsonPath = Join-Path $script:testRoot 'broken.json'
        [System.IO.File]::WriteAllText($jsonPath, '{bad', (New-Object System.Text.UTF8Encoding($false)))
        { Update-HotwmJsonFileAction -Path $jsonPath -Updates @{ global = @{ hold_ms = 250 } } -Explanation 'Update config' } | Should Throw
        [System.IO.File]::ReadAllText($jsonPath) | Should Be '{bad'
    }

    It 'rejects a JSON target changed between parsing snapshot and proposal registration' {
        $jsonPath = Join-Path $script:testRoot 'racing.json'
        [System.IO.File]::WriteAllText($jsonPath, '{"global":{"hold_ms":150}}', (New-Object System.Text.UTF8Encoding($false)))
        $snapshot = Get-HotwmFileSnapshot ([System.IO.Path]::GetFullPath($jsonPath))
        [System.IO.File]::WriteAllText($jsonPath, '{"global":{"hold_ms":999}}', (New-Object System.Text.UTF8Encoding($false)))
        { New-HotwmFileAction -Path $jsonPath -Content '{"global":{"hold_ms":250}}' -Explanation 'Update hold duration' -ExpectedOriginalSnapshot $snapshot } | Should Throw
        [System.IO.File]::ReadAllText($jsonPath) | Should Be '{"global":{"hold_ms":999}}'
    }
}
