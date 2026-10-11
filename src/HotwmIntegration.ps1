<#
.SYNOPSIS
    Read-only version 1 cabinet and Wiimote snapshot for HOTWM.
.DESCRIPTION
    Reads the Kit operation catalog, controllers.wiimote_order, and (when
    available) outputs.wiimote_hook. Does not apply Kit operations or write
    configuration. This boundary is diagnostic only; it is not an OS security
    boundary against other same-user code.
#>
[CmdletBinding()]
param()

if (-not (Get-Command Invoke-HotwmKitApi -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot 'KitClient.ps1'))) {
    . (Join-Path $PSScriptRoot 'KitClient.ps1')
}

function Get-HotwmSnapshotProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-HotwmSafeDiagnostic {
    param([AllowNull()][object]$Value, [switch]$IncludeSensitive)
    if ($IncludeSensitive -or $null -eq $Value) { return ,$Value }
    if ($Value -is [string]) {
        # Cover colon/dash separated MACs and the contiguous 12-hex form used
        # inside Windows BTHENUM/HID InstanceIds. Preserve surrounding text.
        return [regex]::Replace($Value, '(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])|(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])', '[REDACTED-MAC]')
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $safe = [ordered]@{}
        $keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $safeKey = [regex]::Replace($key, '(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])|(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])', '[REDACTED-MAC]')
            $baseKey = $safeKey; $suffix = 2
            while ($safe.Contains($safeKey)) { $safeKey = '{0} [{1}]' -f $baseKey, $suffix; $suffix++ }
            $safe[$safeKey] = ConvertTo-HotwmSafeDiagnostic -Value $Value[$key]
        }
        return $safe
    }
    if ($Value -is [array]) {
        $safeItems = @(); foreach ($item in $Value) { $safeItems += ,(ConvertTo-HotwmSafeDiagnostic -Value $item) }; return ,$safeItems
    }
    if ($Value -is [pscustomobject]) {
        $safe = [ordered]@{}
        $properties = @($Value.PSObject.Properties | Sort-Object { [string]$_.Name })
        foreach ($property in $properties) {
            $safeKey = [regex]::Replace([string]$property.Name, '(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])|(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])', '[REDACTED-MAC]')
            $baseKey = $safeKey; $suffix = 2
            while ($safe.Contains($safeKey)) { $safeKey = '{0} [{1}]' -f $baseKey, $suffix; $suffix++ }
            $safe[$safeKey] = ConvertTo-HotwmSafeDiagnostic -Value $property.Value
        }
        return $safe
    }
    return $Value
}

function Invoke-HotwmSnapshotRead {
    param([Parameter(Mandatory)][string]$Operation, [hashtable]$Parameters = @{}, [scriptblock]$KitInvoker)
    if ($KitInvoker) { return (& $KitInvoker $Operation $Parameters) }
    return (Invoke-HotwmKitApi -Operation $Operation -Parameters $Parameters)
}

function New-HotwmSnapshotOperation {
    param([string]$Name, [string]$Support, [AllowNull()][object]$Result, [AllowNull()][string]$ErrorMessage, [switch]$IncludeSensitive)
    $success = [bool](Get-HotwmSnapshotProperty -Object $Result -Name 'Success' -Default $false)
    $status = [string](Get-HotwmSnapshotProperty -Object $Result -Name 'Status' -Default $(if ($ErrorMessage) { 'Error' } else { 'Unknown' }))
    $message = if ($ErrorMessage) { $ErrorMessage } else { [string](Get-HotwmSnapshotProperty -Object $Result -Name 'Message' -Default '') }
    $data = Get-HotwmSnapshotProperty -Object $Result -Name 'Data'
    [pscustomobject]@{
        Operation = $Name
        Support = $Support
        Success = $success
        Status = ConvertTo-HotwmSafeDiagnostic -Value $status -IncludeSensitive:$IncludeSensitive
        Message = ConvertTo-HotwmSafeDiagnostic -Value $message -IncludeSensitive:$IncludeSensitive
        Data = ConvertTo-HotwmSafeDiagnostic -Value $data -IncludeSensitive:$IncludeSensitive
    }
}

function Get-HotwmIntegrationSnapshot {
    <#
    .SYNOPSIS
        Collects a read-only Kit catalog, Wiimote order, and optional output-hook snapshot.
    .PARAMETER RetroBatRoot
        Optional root used only for the Kit's outputs.wiimote_hook query. The
        Wiimote order and saved binding are global Kit/user-profile data.
    .PARAMETER KitInvoker
        Test seam: scriptblock called as `& $KitInvoker $Operation $Parameters`.
        It receives read operations only and cannot request Apply/Approved.
    .PARAMETER IncludeSensitive
        Returns Kit details without masking Bluetooth MAC addresses and any
        InstanceId strings that contain them. Do not use for ordinary logs.
    #>
    [CmdletBinding()]
    param(
        [string]$RetroBatRoot,
        [scriptblock]$KitInvoker,
        [switch]$IncludeSensitive
    )

    $injected = [bool]$KitInvoker
    $available = $injected
    if (-not $injected) {
        try { $available = [bool](Test-HotwmKitAvailable) } catch { $available = $false }
    }
    $snapshot = [ordered]@{
        ContractVersion = 1
        CollectedAtUtc = [DateTime]::UtcNow.ToString('o')
        Scope = [pscustomobject]@{
            RetroBatRoot = $RetroBatRoot
            WiimoteOrder = 'Kit-global/user-profile ledger; not scoped to RetroBatRoot'
        }
        Kit = [pscustomobject]@{
            Available = $available
            CatalogSuccess = $false
            ApiVersion = $null
            KitVersion = $null
            Success = $false
            Errors = @()
            Capabilities = @()
        }
        Runtime = [pscustomobject]@{
            WiimoteOrder = $null
            OutputHook = $null
        }
        Desired = [pscustomobject]@{
            WiimoteBinding = @()
            BindingSource = 'Kit-global/user-profile ledger'
        }
        State = 'Unavailable'
    }
    if (-not $available) {
        $snapshot.Kit.Errors = @('RetroCabinetKit API entry point is unavailable.')
        return [pscustomobject]$snapshot
    }

    $errors = @()
    $catalog = $null
    try { $catalog = Invoke-HotwmSnapshotRead -Operation 'operations' -KitInvoker $KitInvoker }
    catch { $errors += $_.Exception.Message }
    $catalogSuccess = [bool](Get-HotwmSnapshotProperty -Object $catalog -Name 'Success' -Default $false)
    $snapshot.Kit.CatalogSuccess = $catalogSuccess
    $snapshot.Kit.ApiVersion = Get-HotwmSnapshotProperty -Object $catalog -Name 'ApiVersion'
    $snapshot.Kit.KitVersion = Get-HotwmSnapshotProperty -Object $catalog -Name 'KitVersion'
    if (-not $catalogSuccess -and $catalog) {
        $errors += [string](Get-HotwmSnapshotProperty -Object $catalog -Name 'Message' -Default 'Kit operation catalog query failed.')
    }
    $catalogOperations = @(Get-HotwmSnapshotProperty -Object (Get-HotwmSnapshotProperty -Object $catalog -Name 'Data') -Name 'Operations' -Default @())
    $snapshot.Kit.Capabilities = @($catalogOperations | Where-Object { (Get-HotwmSnapshotProperty -Object $_ -Name 'Name') -in @('controllers.wiimote_order', 'outputs.wiimote_hook') } | ForEach-Object {
        [pscustomobject]@{
            Name = Get-HotwmSnapshotProperty -Object $_ -Name 'Name'
            Available = [bool](Get-HotwmSnapshotProperty -Object $_ -Name 'Available' -Default $true)
            Kind = Get-HotwmSnapshotProperty -Object $_ -Name 'Kind'
        }
    })

    foreach ($spec in @(
        @{ Name = 'controllers.wiimote_order'; Property = 'WiimoteOrder'; Parameters = @{} }
        @{ Name = 'outputs.wiimote_hook'; Property = 'OutputHook'; Parameters = $(if ($RetroBatRoot) { @{ RetroBatRoot = $RetroBatRoot } } else { @{} }) }
    )) {
        $operation = @($catalogOperations | Where-Object { (Get-HotwmSnapshotProperty -Object $_ -Name 'Name') -eq $spec.Name } | Select-Object -First 1)
        $support = if (-not $catalogSuccess) { 'Unknown' } elseif (-not $operation.Count) { 'Unsupported' } elseif ((Get-HotwmSnapshotProperty -Object $operation[0] -Name 'Available' -Default $true) -eq $false) { 'Unavailable' } else { 'Available' }
        if ($support -ne 'Available') {
            $snapshot.Runtime.($spec.Property) = [pscustomobject]@{ Operation = $spec.Name; Support = $support; Success = $false; Status = $support; Message = ''; Data = $null }
            continue
        }
        $result = $null; $callError = $null
        try { $result = Invoke-HotwmSnapshotRead -Operation $spec.Name -Parameters $spec.Parameters -KitInvoker $KitInvoker }
        catch { $callError = $_.Exception.Message; $errors += $callError }
        $snapshot.Runtime.($spec.Property) = New-HotwmSnapshotOperation -Name $spec.Name -Support $support -Result $result -ErrorMessage $callError -IncludeSensitive:$IncludeSensitive
        if (-not $snapshot.Runtime.($spec.Property).Success) {
            $reportedError = [string]$snapshot.Runtime.($spec.Property).Message
            if ($reportedError) { $errors += $reportedError }
        }
    }

    $orderData = $snapshot.Runtime.WiimoteOrder.Data
    if ($snapshot.Runtime.WiimoteOrder.Success -and $orderData) {
        $reported = @(Get-HotwmSnapshotProperty -Object $orderData -Name 'Wiimotes' -Default @())
        $runtimeRows = @(foreach ($row in $reported) { [pscustomobject]@{ Player = Get-HotwmSnapshotProperty -Object $row -Name 'Player'; Mac = ConvertTo-HotwmSafeDiagnostic -Value (Get-HotwmSnapshotProperty -Object $row -Name 'Mac') -IncludeSensitive:$IncludeSensitive; Model = Get-HotwmSnapshotProperty -Object $row -Name 'Model'; Arrived = Get-HotwmSnapshotProperty -Object $row -Name 'Arrived' } })
        $desiredRows = @(foreach ($row in $reported) { $expectedPlayer = Get-HotwmSnapshotProperty -Object $row -Name 'Expected'; if ($null -ne $expectedPlayer) { [pscustomobject]@{ Player = $expectedPlayer; Mac = ConvertTo-HotwmSafeDiagnostic -Value (Get-HotwmSnapshotProperty -Object $row -Name 'Mac') -IncludeSensitive:$IncludeSensitive; Model = Get-HotwmSnapshotProperty -Object $row -Name 'Model' } } })
        $desiredRows = @($desiredRows | Sort-Object { [int]$_.Player })
        $snapshot.Runtime.WiimoteOrder = [pscustomobject]@{
            Operation = $snapshot.Runtime.WiimoteOrder.Operation
            Support = $snapshot.Runtime.WiimoteOrder.Support
            Success = $snapshot.Runtime.WiimoteOrder.Success
            Status = $snapshot.Runtime.WiimoteOrder.Status
            Message = $snapshot.Runtime.WiimoteOrder.Message
            State = Get-HotwmSnapshotProperty -Object $orderData -Name 'State' -Default 'Unknown'
            ReportedRuntimeOrder = $runtimeRows
            RawDetails = ConvertTo-HotwmSafeDiagnostic -Value $orderData -IncludeSensitive:$IncludeSensitive
        }
        $snapshot.State = [string]$snapshot.Runtime.WiimoteOrder.State
        $snapshot.Desired.WiimoteBinding = $desiredRows
    }
    else {
        $snapshot.State = if ($snapshot.Runtime.WiimoteOrder.Support -eq 'Unsupported') { 'Unsupported' } else { 'Unknown' }
    }
    $snapshot.Kit.Errors = @($errors | ForEach-Object { ConvertTo-HotwmSafeDiagnostic -Value $_ -IncludeSensitive:$IncludeSensitive })
    $snapshot.Kit.Success = [bool]($catalogSuccess -and $snapshot.Runtime.WiimoteOrder.Success)
    if ($snapshot.Runtime.OutputHook.Success -and $snapshot.Runtime.OutputHook.Data) {
        $hookData = $snapshot.Runtime.OutputHook.Data
        $reportedRecommendation = Get-HotwmSnapshotProperty -Object $hookData -Name 'Recommendation'
        $safeHookData = [ordered]@{}
        if ($hookData -is [System.Collections.IDictionary]) {
            foreach ($key in $hookData.Keys) { if ([string]$key -ne 'Recommendation') { $safeHookData[[string]$key] = $hookData[$key] } }
        } else {
            foreach ($property in $hookData.PSObject.Properties) { if ($property.Name -ne 'Recommendation') { $safeHookData[$property.Name] = $property.Value } }
        }
        $snapshot.Runtime.OutputHook.Data = ConvertTo-HotwmSafeDiagnostic -Value $safeHookData -IncludeSensitive:$IncludeSensitive
        Add-Member -InputObject $snapshot.Runtime.OutputHook -MemberType NoteProperty -Name KitRecommendation -Value (ConvertTo-HotwmSafeDiagnostic -Value $reportedRecommendation -IncludeSensitive:$IncludeSensitive) -Force
    }
    return [pscustomobject]$snapshot
}
