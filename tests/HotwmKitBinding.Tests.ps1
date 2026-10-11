#requires -Version 5.1
$script:repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:repoRoot 'src\HotwmKitBinding.ps1')

# A fake Kit with the API 1.8 contract of controllers.wiimote_bind: plan, PlanId over binding + ledger, stale refusal.
function New-FakeKitBinding {
    $state = [pscustomobject]@{ Ledger = 'old'; Calls = New-Object System.Collections.ArrayList; PlanIdSupport = $true }
    $invoker = {
        param($operation, $parameters, $apply)
        [void]$state.Calls.Add([pscustomobject]@{ Operation = $operation; Parameters = $parameters; Apply = $apply })
        $rows = @(foreach ($part in ([string]$parameters.Binding -split ',')) { $mac, $player = $part -split '='; [pscustomobject]@{ Player = [int]$player; Mac = $mac; Model = 'RVL-CNT-01' } })
        $id = if ($state.PlanIdSupport) { -join ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($state.Ledger + '|' + $parameters.Binding)) | ForEach-Object { $_.ToString('x2') }) } else { $null }
        if (-not $apply) { return [pscustomobject]@{ Success = $true; Status = 'WhatIf'; Message = 'Plan'; Data = [pscustomobject]@{ Wiimotes = $rows; Source = 'Binding'; PlanId = $id } } }
        if ($parameters.PlanId -ne $id) { return [pscustomobject]@{ Success = $false; Status = 'Failed'; Message = 'changed since this plan'; Data = $null } }
        $state.Ledger = $parameters.Binding
        return [pscustomobject]@{ Success = $true; Status = 'Done'; Message = 'Wiimote binding saved'; Data = [pscustomobject]@{ Wiimotes = $rows } }
    }.GetNewClosure()
    [pscustomobject]@{ State = $state; Invoker = $invoker }
}

Describe 'Hotwm hands the MAC player mapping to the Kit' {
    $mappings = @([pscustomobject]@{ Mac = '34:AF:2C:D5:79:5B'; Player = 2 }, [pscustomobject]@{ Mac = '00:17:AB:2C:D0:A0'; Player = 1 })

    It 'plans by MAC, asks the person once with the Kit plan, and applies with the plan id' {
        $kit = New-FakeKitBinding
        $script:shown = $null
        $r = Publish-HotwmKitWiimoteBinding -Mappings $mappings -KitInvoker $kit.Invoker -Confirm { param($plan) $script:shown = $plan; $true }
        $r.Status | Should Be 'Done'
        $r.Binding | Should Be '0017AB2CD0A0=1,34AF2CD5795B=2'
        $script:shown.Data.PlanId | Should Not BeNullOrEmpty
        $kit.State.Calls.Count | Should Be 2
        $kit.State.Calls[0].Apply | Should Be $false
        $kit.State.Calls[1].Apply | Should Be $true
        $kit.State.Calls[1].Parameters.PlanId | Should Be $script:shown.Data.PlanId
        $kit.State.Ledger | Should Be '0017AB2CD0A0=1,34AF2CD5795B=2'
    }

    It 'a declined plan never reaches the Kit as an apply' {
        $kit = New-FakeKitBinding
        $r = Publish-HotwmKitWiimoteBinding -Mappings $mappings -KitInvoker $kit.Invoker -Confirm { $false }
        $r.Status | Should Be 'Declined'
        @($kit.State.Calls | Where-Object Apply).Count | Should Be 0
        $kit.State.Ledger | Should Be 'old'
    }

    It 'a ledger changed between plan and yes is refused by the Kit and reported as failed' {
        $kit = New-FakeKitBinding
        $r = Publish-HotwmKitWiimoteBinding -Mappings $mappings -KitInvoker $kit.Invoker -Confirm { $kit.State.Ledger = 'someone else'; $true }.GetNewClosure()
        $r.Status | Should Be 'Failed'
        $r.Success | Should Be $false
        $kit.State.Ledger | Should Be 'someone else'
    }

    It 'never applies on a Kit without plan ids, without mappings, or with an invalid MAC' {
        $kit = New-FakeKitBinding; $kit.State.PlanIdSupport = $false
        (Publish-HotwmKitWiimoteBinding -Mappings $mappings -KitInvoker $kit.Invoker -Confirm { throw 'must not ask' }).Message | Should Match 'API 1.8'
        @($kit.State.Calls | Where-Object Apply).Count | Should Be 0
        (Publish-HotwmKitWiimoteBinding -Mappings @() -KitInvoker $kit.Invoker -Confirm { throw 'must not ask' }).Status | Should Be 'Failed'
        { Publish-HotwmKitWiimoteBinding -Mappings @([pscustomobject]@{ Mac = 'Wiimote 1'; Player = 1 }) -KitInvoker $kit.Invoker -Confirm { $true } } | Should Throw
    }

    It 'the local Kit plans a MAC binding with a plan id and writes nothing (dry run only)' {
        if (-not (Test-HotwmKitAvailable)) { Set-TestInconclusive 'No local Kit next to Hotwm.'; return }
        $plan = Invoke-HotwmKitApi -Operation 'controllers.wiimote_bind' -Parameters @{ Binding = '0017AB2CD0A0=1' }
        $plan.Status | Should Be 'WhatIf'
        $plan.Applied | Should Be $false
        $plan.Data.Source | Should Be 'Binding'
        $plan.Data.PlanId | Should Match '^[0-9a-f]{64}$'
    }
}