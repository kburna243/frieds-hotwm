<#
.SYNOPSIS
    Runs Pester tests with the Pester 3.x module (ships with Windows).
#>
[CmdletBinding()]
param(
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Path) {
    $Path = @((Join-Path $testsDir 'Hotwm.Tests.ps1'))
}

Import-Module Pester -MaximumVersion 3.99
$result = Invoke-Pester -Script $Path -PassThru

Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}  Skipped: {2}  Pending: {3}  Total: {4}' -f `
    $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.PendingCount, $result.TotalCount)

if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) {
    exit 1
}
exit 0
