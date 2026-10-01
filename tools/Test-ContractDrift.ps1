<#
.SYNOPSIS
    Verifies that the live Kit API matches the contract snapshot in contract/kit-contract-v1.json.
.DESCRIPTION
    Ensures hotwm and Fried's Retrogaming Kit do not diverge silently across versions.
    Validates ApiVersion (1.4) and the 'outputs.wiimote_hook' operation contract.
.PARAMETER KitRoot
    Optional path to the kit. If omitted, uses default discovery from KitClient.ps1.
#>
[CmdletBinding()]
param(
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# Load KitClient
. (Join-Path $repoRoot "src\KitClient.ps1")

if ($KitRoot) {
    $env:RETRO_CABINET_KIT_ROOT = $KitRoot
}

$contractPath = Join-Path $repoRoot "contract\kit-contract-v1.json"
if (-not (Test-Path $contractPath)) {
    Write-Error "Contract snapshot missing at: $contractPath"
    exit 2
}

$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "=== Testing Kit API Contract Drift ===" -ForegroundColor Cyan
Write-Host "Pinned Target: ApiVersion $($contract.TargetKit.ApiVersion) (Kit $($contract.TargetKit.KitVersion))" -ForegroundColor Gray

if (-not (Test-HotwmKitAvailable)) {
    Write-Warning "Kit is not installed on this system. Cannot perform live drift test."
    exit 0
}

# 1. Query live operations
$liveOpsRes = Invoke-HotwmKitApi -Operation "operations"
if (-not $liveOpsRes.Success) {
    Write-Error "Live Kit refused operations call: $($liveOpsRes.Message)"
    exit 2
}

Write-Host "Live Kit: ApiVersion $($liveOpsRes.ApiVersion) (Kit $($liveOpsRes.KitVersion))" -ForegroundColor Gray

# 2. Check ApiVersion Major match
$liveMajor = ($liveOpsRes.ApiVersion -split '\.')[0]
$pinnedMajor = ($contract.TargetKit.ApiVersion -split '\.')[0]
if ($liveMajor -ne $pinnedMajor) {
    Write-Error "DRIFT: ApiVersion major mismatch! Live=$($liveOpsRes.ApiVersion), Pinned=$($contract.TargetKit.ApiVersion)"
    exit 1
}

# 3. Check Required Operations
$liveOpList = @($liveOpsRes.Data.Operations | ForEach-Object { $_.Name })
$drifted = $false

foreach ($req in $contract.RequiredOperations) {
    if ($req.Name -notin $liveOpList) {
        Write-Error "DRIFT: Required operation '$($req.Name)' is missing from live Kit!"
        $drifted = $true
    } else {
        Write-Host "  [OK] Operation '$($req.Name)' is available." -ForegroundColor Green
    }
}

# 4. Check outputs.wiimote_hook result fields
$hookRes = Get-HotwmSystemStatus
if (-not $hookRes.Success) {
    Write-Error "DRIFT: Calling 'outputs.wiimote_hook' failed: $($hookRes.Message)"
    exit 1
}

$hookReq = $contract.RequiredOperations | Where-Object { $_.Name -eq 'outputs.wiimote_hook' }
if ($hookReq -and $hookReq.ExpectedResultFields) {
    $liveDataProps = @($hookRes.Data.psobject.Properties | ForEach-Object { $_.Name })
    foreach ($field in $hookReq.ExpectedResultFields) {
        if ($field -notin $liveDataProps) {
            Write-Error "DRIFT: Field '$field' missing in 'outputs.wiimote_hook' Data result!"
            $drifted = $true
        }
    }
}

if ($drifted) {
    Write-Error "Contract drift detected! Update contract/kit-contract-v1.json or adapt hotwm."
    exit 1
}

Write-Host "=== Contract Check PASSED: 0 drift detected ===" -ForegroundColor Green
exit 0
