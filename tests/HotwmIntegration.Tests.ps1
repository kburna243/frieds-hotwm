#requires -Version 5.1
$script:repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:repoRoot 'src\HotwmIntegration.ps1')

Describe 'HOTWM integration snapshot v1' {
    It 'separates current runtime order from saved desired binding and masks MACs in nested details' {
        $invoker = {
            param($operation, $parameters)
            switch ($operation) {
                'operations' { return [pscustomobject]@{ Success=$true; ApiVersion='1.7'; KitVersion='1.5.0'; Data=[pscustomobject]@{ Operations=@([pscustomobject]@{Name='controllers.wiimote_order';Available=$true;Kind='Read'},[pscustomobject]@{Name='outputs.wiimote_hook';Available=$true;Kind='Read'}) } } }
                'controllers.wiimote_order' { $keyedProperties = '{"AABBCCDDEEFF":"property","001122334455":"bare-property"}' | ConvertFrom-Json; return [pscustomobject]@{ Success=$true; Status='Ok'; Data=[pscustomobject]@{ State='Swapped'; Wiimotes=@([pscustomobject]@{Player=1;Mac='AABBCCDDEEFF';Model='RVL-CNT-01';Arrived='one';Expected=2;InstanceId='HID\BTHENUM&001122334455'},[pscustomobject]@{Player=2;Mac='11:22:33:44:55:66';Model='RVL-CNT-01-TR';Arrived='two';Expected=1;InstanceId='HID\BTHENUM&112233445566'}); DiagnosticMap=@{ 'AABBCCDDEEFF'='one'; '001122334455'='bare'; 'HID\BTHENUM&001122334455'='parent'; '11:22:33:44:55:66'='two' }; PropertyMap=$keyedProperties } } }
                'outputs.wiimote_hook' { return [pscustomobject]@{ Success=$true; Status='Ok'; Data=[pscustomobject]@{ Recommendation='Ready'; GunmoteRunning=$true; Detail='device 112233445566' } } }
            }
        }
        $snapshot = Get-HotwmIntegrationSnapshot -RetroBatRoot 'R:\RetroBat' -KitInvoker $invoker
        $snapshot.ContractVersion | Should Be 1
        $snapshot.State | Should Be 'Swapped'
        $snapshot.Runtime.WiimoteOrder.ReportedRuntimeOrder[0].Player | Should Be 1
        $snapshot.Runtime.WiimoteOrder.ReportedRuntimeOrder[0].Mac | Should Be '[REDACTED-MAC]'
        $snapshot.Desired.WiimoteBinding[0].Player | Should Be 1
        $snapshot.Desired.WiimoteBinding[0].Mac | Should Be '[REDACTED-MAC]'
        $snapshot.Runtime.WiimoteOrder.RawDetails.Wiimotes[0].InstanceId | Should Match '\[REDACTED-MAC\]'
        $snapshot.Runtime.WiimoteOrder.RawDetails.DiagnosticMap['[REDACTED-MAC]'] | Should Be 'bare'
        $snapshot.Runtime.WiimoteOrder.RawDetails.DiagnosticMap['[REDACTED-MAC] [2]'] | Should Be 'two'
        $snapshot.Runtime.WiimoteOrder.RawDetails.DiagnosticMap['[REDACTED-MAC] [3]'] | Should Be 'one'
        $snapshot.Runtime.WiimoteOrder.RawDetails.DiagnosticMap['HID\BTHENUM&[REDACTED-MAC]'] | Should Be 'parent'
        $snapshot.Runtime.WiimoteOrder.RawDetails.PropertyMap['[REDACTED-MAC]'] | Should Be 'bare-property'
        $snapshot.Runtime.WiimoteOrder.RawDetails.PropertyMap['[REDACTED-MAC] [2]'] | Should Be 'property'
        $snapshot.Runtime.OutputHook.Data.Recommendation | Should Be $null
        $snapshot.Runtime.OutputHook.KitRecommendation | Should Be 'Ready'
        $snapshot.Scope.WiimoteOrder | Should Match 'global'
    }

    It 'returns raw MAC and nested identifiers only when explicitly requested' {
        $invoker = {
            param($operation, $parameters)
            if ($operation -eq 'operations') { return [pscustomobject]@{ Success=$true; Data=[pscustomobject]@{Operations=@([pscustomobject]@{Name='controllers.wiimote_order';Available=$true},[pscustomobject]@{Name='outputs.wiimote_hook';Available=$false})} } }
            return [pscustomobject]@{ Success=$true; Status='Ok'; Data=[pscustomobject]@{ State='Ok'; Wiimotes=@([pscustomobject]@{Player=1;Mac='AABBCCDDEEFF';Model='RVL-CNT-01';Expected=1;InstanceId='HID\BTHENUM&001122334455'}) } }
        }
        $snapshot = Get-HotwmIntegrationSnapshot -KitInvoker $invoker -IncludeSensitive
        $snapshot.Runtime.WiimoteOrder.ReportedRuntimeOrder[0].Mac | Should Be 'AABBCCDDEEFF'
        $snapshot.Runtime.WiimoteOrder.RawDetails.Wiimotes[0].InstanceId | Should Match '001122334455'
    }

    It 'does not call the Kit when it is unavailable' {
        Mock Test-HotwmKitAvailable { return $false }
        $snapshot = Get-HotwmIntegrationSnapshot
        $snapshot.Kit.Available | Should Be $false
        $snapshot.Kit.Errors.Count | Should BeGreaterThan 0
        $snapshot.State | Should Be 'Unavailable'
    }

    It 'marks an absent operation unsupported without invoking it' {
        $script:called = @()
        $invoker = { param($operation,$parameters) $script:called += $operation; if ($operation -eq 'operations') { return [pscustomobject]@{ Success=$true; ApiVersion='1.6'; KitVersion='1.4.0'; Data=[pscustomobject]@{Operations=@()} } }; throw 'unsupported operation was called' }
        $snapshot = Get-HotwmIntegrationSnapshot -KitInvoker $invoker
        $snapshot.Runtime.WiimoteOrder.Support | Should Be 'Unsupported'
        $snapshot.Runtime.OutputHook.Support | Should Be 'Unsupported'
        $script:called.Count | Should Be 1
    }

    It 'reports operation failures without throwing and preserves NoGunmote and Unclear states' {
        $script:state = 'NoGunmote'
        $invoker = {
            param($operation,$parameters)
            if ($operation -eq 'operations') { return [pscustomobject]@{ Success=$true; Data=[pscustomobject]@{Operations=@([pscustomobject]@{Name='controllers.wiimote_order';Available=$true},[pscustomobject]@{Name='outputs.wiimote_hook';Available=$true})} } }
            if ($operation -eq 'controllers.wiimote_order') { return [pscustomobject]@{ Success=$true; Status='Ok'; Data=[pscustomobject]@{ State=$script:state; Wiimotes=@() } } }
            return [pscustomobject]@{ Success=$false; Status='Failed'; Message='hook failed'; Data=$null }
        }
        $snapshot = Get-HotwmIntegrationSnapshot -KitInvoker $invoker
        $snapshot.State | Should Be 'NoGunmote'
        $snapshot.Runtime.OutputHook.Success | Should Be $false
        $snapshot.Kit.Success | Should Be $true
        $script:state = 'Unclear'
        (Get-HotwmIntegrationSnapshot -KitInvoker $invoker).State | Should Be 'Unclear'
    }

    It 'passes the selected RetroBat root only to the root-scoped hook operation' {
        $script:seen = @{}
        $invoker = { param($operation,$parameters) $script:seen[$operation] = $parameters; if ($operation -eq 'operations') { return [pscustomobject]@{ Success=$true; Data=[pscustomobject]@{Operations=@([pscustomobject]@{Name='controllers.wiimote_order';Available=$true},[pscustomobject]@{Name='outputs.wiimote_hook';Available=$true})} } }; if ($operation -eq 'controllers.wiimote_order') { return [pscustomobject]@{Success=$true;Data=[pscustomobject]@{State='Unbound';Wiimotes=@()}} }; return [pscustomobject]@{Success=$true;Data=[pscustomobject]@{}} }
        $null = Get-HotwmIntegrationSnapshot -RetroBatRoot 'R:\Cabinet' -KitInvoker $invoker
        $script:seen['controllers.wiimote_order'].Count | Should Be 0
        $script:seen['outputs.wiimote_hook'].RetroBatRoot | Should Be 'R:\Cabinet'
    }
}
