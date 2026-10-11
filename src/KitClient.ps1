<#
.SYNOPSIS
    Client interface connecting Hook of the Wiimote (hotwm) to Fried's Retrogaming Kit.
.DESCRIPTION
    hotwm is an application sitting on top of Fried's Retrogaming Kit.
    Instead of duplicating hardware detection, INI writing, and backup logic,
    hotwm communicates with the Kit through its stable API (ApiVersion 1.4+).
#>
[CmdletBinding()]
param()

function Get-HotwmKitRoot {
    [CmdletBinding()]
    param(
        [string]$ApplicationRoot = (Split-Path -Parent $PSScriptRoot)
    )

    # An explicit override is authoritative. A stale or invalid override must not
    # silently connect this application to a different Kit checkout.
    if ($null -ne $env:RETRO_CABINET_KIT_ROOT -and $env:RETRO_CABINET_KIT_ROOT.Length -gt 0) {
        $explicitRoot = $env:RETRO_CABINET_KIT_ROOT
        try {
            $resolved = Resolve-Path -LiteralPath $explicitRoot -ErrorAction Stop
            if (-not $resolved.ProviderPath -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)) { return $null }
            $apiEntry = Join-Path $resolved.ProviderPath 'api\Invoke-KitApi.ps1'
            if (-not (Test-Path -LiteralPath $apiEntry -PathType Leaf)) { return $null }
            return [System.IO.Path]::GetFullPath($resolved.ProviderPath)
        } catch {
            return $null
        }
    }

    # Search only known adjacent layouts. This supports source (code/src) and
    # portable (gui/src) deployments without scanning drives or the working dir.
    try {
        $appResolved = Resolve-Path -LiteralPath $ApplicationRoot -ErrorAction Stop
        if (-not $appResolved.ProviderPath -or -not (Test-Path -LiteralPath $appResolved.ProviderPath -PathType Container)) { return $null }
        $appPath = [System.IO.Path]::GetFullPath($appResolved.ProviderPath)
    } catch {
        return $null
    }

    $firstParent = Split-Path -Parent $appPath
    if ([string]::IsNullOrWhiteSpace($firstParent)) { return $null }
    $secondParent = Split-Path -Parent $firstParent
    $bases = @($firstParent)
    if (-not [string]::IsNullOrWhiteSpace($secondParent) -and $secondParent -ne $firstParent) { $bases += $secondParent }

    foreach ($base in $bases) {
        foreach ($candidateName in @('retro-cabinet-kit', 'frieds-retrogaming-kit')) {
            $candidate = Join-Path $base $candidateName
            try {
                $resolvedCandidate = Resolve-Path -LiteralPath $candidate -ErrorAction Stop
                if (-not $resolvedCandidate.ProviderPath -or -not (Test-Path -LiteralPath $resolvedCandidate.ProviderPath -PathType Container)) { continue }
                $apiEntry = Join-Path $resolvedCandidate.ProviderPath 'api\Invoke-KitApi.ps1'
                if (Test-Path -LiteralPath $apiEntry -PathType Leaf) {
                    return [System.IO.Path]::GetFullPath($resolvedCandidate.ProviderPath)
                }
            } catch {
                continue
            }
        }
    }

    return $null
}

function Test-HotwmKitAvailable {
    [CmdletBinding()]
    param()
    $kit = Get-HotwmKitRoot
    if (-not $kit) { return $false }
    return (Test-Path (Join-Path $kit "api\Invoke-KitApi.ps1"))
}

function Get-HotwmKitVersion {
    # The kit's VERSION file is the same source its API reports as KitVersion; reading it avoids a slow API call.
    [CmdletBinding()]
    param()
    $kit = Get-HotwmKitRoot
    if (-not $kit) { return $null }
    $file = Join-Path $kit 'VERSION'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    return ([IO.File]::ReadAllText($file)).Trim()
}

function Invoke-HotwmKitApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [hashtable]$Parameters = @{},
        [switch]$Apply
    )

    $kit = Get-HotwmKitRoot
    if (-not $kit) {
        return [pscustomobject]@{
            Success    = $false
            Message    = "Fried's Retrogaming Kit was not found on this system."
            ApiVersion = $null
            Data       = $null
        }
    }

    $apiScript = Join-Path $kit "api\Invoke-KitApi.ps1"
    if (-not (Test-Path $apiScript)) {
        return [pscustomobject]@{
            Success    = $false
            Message    = "Kit API entry point missing at: $apiScript"
            ApiVersion = $null
            Data       = $null
        }
    }

    $splat = @{
        Operation = $Operation
    }
    if ($Parameters -and $Parameters.Count -gt 0) {
        $splat['ParametersJson'] = ($Parameters | ConvertTo-Json -Compress)
    }
    if ($Apply) {
        $splat['Apply'] = $true
    }

    try {
        $raw = & $apiScript @splat
        if (-not $raw) {
            return [pscustomobject]@{
                Success    = $false
                Message    = "No response returned from Kit API."
                ApiVersion = $null
                Data       = $null
            }
        }
        $json = ($raw -join "`n")
        return ($json | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{
            Success    = $false
            Message    = "Failed calling Kit API: $($_.Exception.Message)"
            ApiVersion = $null
            Data       = $null
        }
    }
}

function Get-HotwmSystemStatus {
    <#
    .SYNOPSIS
        Queries the Wiimote output chain status via Kit operation 'outputs.wiimote_hook'.
    #>
    [CmdletBinding()]
    param([string]$RetroBatRoot = "")

    $params = @{}
    if ($RetroBatRoot) { $params['RetroBatRoot'] = $RetroBatRoot }

    $res = Invoke-HotwmKitApi -Operation "outputs.wiimote_hook" -Parameters $params
    return $res
}

function Get-HotwmInputProfiles {
    <#
    .SYNOPSIS
        Queries available arcade button input profiles via Kit operation 'controllers.input_profiles' (Kit v1.3.0 / API 1.5).
    #>
    [CmdletBinding()]
    param()

    return Invoke-HotwmKitApi -Operation "controllers.input_profiles"
}

function Set-HotwmInputProfile {
    <#
    .SYNOPSIS
        Applies an arcade input profile (e.g. 'ipac2-default') via Kit operation 'controllers.input_apply' (Kit v1.3.0 / API 1.5).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Profile,

        [string]$RetroBatRoot = "",
        [switch]$Apply
    )

    $params = @{ Profile = $Profile }
    if ($RetroBatRoot) { $params['RetroBatRoot'] = $RetroBatRoot }

    return Invoke-HotwmKitApi -Operation "controllers.input_apply" -Parameters $params -Apply:$Apply
}

function Get-HotwmOutputSafety {
    <#
    .SYNOPSIS
        Verifies output middleware safety (port conflicts on 8000, double consumers, solenoid guard) via Kit operation 'outputs.verify_safety'.
    #>
    [CmdletBinding()]
    param([string]$RetroBatRoot = "")

    $params = @{}
    if ($RetroBatRoot) { $params['RetroBatRoot'] = $RetroBatRoot }

    return Invoke-HotwmKitApi -Operation "outputs.verify_safety" -Parameters $params
}


