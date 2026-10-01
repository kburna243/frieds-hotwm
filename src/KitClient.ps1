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
    param()

    # 1. Environment variable override
    if ($env:RETRO_CABINET_KIT_ROOT -and (Test-Path $env:RETRO_CABINET_KIT_ROOT)) {
        return $env:RETRO_CABINET_KIT_ROOT
    }

    # 2. Known default path in this cabinet ecosystem
    $knownCabinetPath = "I:\claude-system\data\projects\retro-cabinet-kit"
    if (Test-Path $knownCabinetPath) {
        return $knownCabinetPath
    }

    # 3. Sibling folder check (e.g. ..\retro-cabinet-kit or ..\frieds-retrogaming-kit)
    $parent = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if ($parent) {
        foreach ($candidate in @("retro-cabinet-kit", "frieds-retrogaming-kit")) {
            $p = Join-Path $parent $candidate
            if (Test-Path $p) { return $p }
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


