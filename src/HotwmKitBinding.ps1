#requires -Version 5.1
<#
.SYNOPSIS
    Hands the confirmed Bluetooth-MAC player mapping to the Retrogaming Kit.
.DESCRIPTION
    The Kit owns the cabinet-wide Wiimote ledger (controllers.wiimote_bind,
    API 1.8+). Hotwm asks the Kit for a plan, shows exactly that plan to the
    person through the -Confirm callback, and applies only with the plan's
    PlanId, so the Kit writes nothing if the ledger or the binding changed in
    between. A plan without PlanId (older Kit) is never applied.
#>

if (-not (Get-Command ConvertTo-HotwmValidatedDesiredMappings -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'HotwmWizard.ps1') }
if (-not (Get-Command Invoke-HotwmKitApi -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot 'KitClient.ps1'))) { . (Join-Path $PSScriptRoot 'KitClient.ps1') }

function Publish-HotwmKitWiimoteBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Mappings,
        # Called once with the Kit's plan; only a person's yes in the trusted UI may return $true.
        [Parameter(Mandatory)][scriptblock]$Confirm,
        # Test seam: & $KitInvoker $Operation $Parameters $Apply
        [scriptblock]$KitInvoker
    )
    $call = {
        param([hashtable]$Parameters, [bool]$Apply)
        if ($KitInvoker) { return (& $KitInvoker 'controllers.wiimote_bind' $Parameters $Apply) }
        return (Invoke-HotwmKitApi -Operation 'controllers.wiimote_bind' -Parameters $Parameters -Apply:$Apply)
    }
    $binding = $null
    $outcome = { param($Status, $Message, $Plan, $Result, $Binding) [pscustomobject]@{ Success = ($Status -eq 'Done'); Status = $Status; Message = $Message; Binding = $Binding; Plan = $Plan; Result = $Result } }

    $valid = @(ConvertTo-HotwmValidatedDesiredMappings -Mappings $Mappings)
    if (-not $valid.Count) { return (& $outcome 'Failed' 'Keine bestätigte MAC-Zuordnung: ordne zuerst erkannte Wiimotes einem Spieler zu.' $null $null $binding) }
    $binding = (@($valid | Sort-Object Player | ForEach-Object { '{0}={1}' -f ($_.Mac -replace '[:-]', ''), $_.Player }) -join ',')

    $plan = & $call @{ Binding = $binding } $false
    if (-not $plan -or -not $plan.Success -or [string]$plan.Status -ne 'WhatIf') {
        $why = if ($plan) { [string]$plan.Message } else { 'keine Antwort' }
        return (& $outcome 'Failed' "Das Kit hat keinen Plan geliefert: $why" $plan $null $binding)
    }
    $planId = [string]$plan.Data.PlanId
    if ($planId -notmatch '^[0-9a-f]{64}$') {
        return (& $outcome 'Failed' 'Dieses Kit bindet die Freigabe nicht an den Plan (Kit-API 1.8 nötig). Nichts geschrieben.' $plan $null $binding)
    }
    # The Kit must plan exactly what Hotwm asked for, not its own reading of it.
    $planned = (@($plan.Data.Wiimotes | Sort-Object { [int]$_.Player } | ForEach-Object { '{0}={1}' -f $_.Mac, $_.Player }) -join ',')
    if ($planned -cne $binding) { return (& $outcome 'Failed' "Der Kit-Plan weicht von der Zuordnung ab ($planned). Nichts geschrieben." $plan $null $binding) }

    if ((& $Confirm $plan) -ne $true) { return (& $outcome 'Declined' 'Abgelehnt: das Kit wurde nicht geändert.' $plan $null $binding) }

    $applied = & $call @{ Binding = $binding; PlanId = $planId } $true
    $status = if ($applied -and [string]$applied.Status -eq 'Done') { 'Done' } else { 'Failed' }
    $message = if ($applied) { [string]$applied.Message } else { 'Keine Antwort vom Kit.' }
    return (& $outcome $status $message $plan $applied $binding)
}
