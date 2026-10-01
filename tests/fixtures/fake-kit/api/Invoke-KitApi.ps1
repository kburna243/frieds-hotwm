<#
.SYNOPSIS
    Fake Kit API for offline and CI testing of KitClient (mimics api\Invoke-KitApi.ps1).
#>
[CmdletBinding()]
param(
    [string]$Operation,
    [string]$ParametersJson,
    [switch]$Apply,
    [switch]$Approved,
    [switch]$Anonymize,
    [switch]$List,
    [string]$Culture = 'en-US'
)

$ErrorActionPreference = 'Stop'

$params = @{}
if ($ParametersJson) {
    try {
        $parsed = ConvertFrom-Json -InputObject $ParametersJson
        foreach ($prop in $parsed.psobject.Properties) {
            $params[$prop.Name] = $prop.Value
        }
    } catch {}
}

$now = [DateTime]::UtcNow.ToString("o")

switch ($Operation) {
    'operations' {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "operations"
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "Catalog"
            Data       = @{
                Operations = @(
                    @{
                        Name        = "outputs.wiimote_hook"
                        Kind        = "Read"
                        Description = "Inspect the Wiimote lightgun output chain"
                        Parameters  = @(
                            @{ Name = "RetroBatRoot"; Type = "String"; Mandatory = $false }
                        )
                    },
                    @{
                        Name        = "outputs.verify_safety"
                        Kind        = "Read"
                        Description = "Verify output safety: solenoid limits, port conflicts, double output consumers."
                        Parameters  = @(
                            @{ Name = "RetroBatRoot"; Type = "String"; Mandatory = $false }
                        )
                    },
                    @{
                        Name        = "controllers.input_profiles"
                        Kind        = "Read"
                        Description = "List the input profiles or one profile with its mapping."
                        Parameters  = @(
                            @{ Name = "Name"; Type = "String"; Mandatory = $false }
                        )
                    },
                    @{
                        Name        = "controllers.input_apply"
                        Kind        = "Change"
                        Description = "Write an input profile as a MAME ctrlr file"
                        Parameters  = @(
                            @{ Name = "Profile"; Type = "String"; Mandatory = $true },
                            @{ Name = "CtrlrName"; Type = "String"; Mandatory = $false },
                            @{ Name = "RetroBatRoot"; Type = "String"; Mandatory = $false }
                        )
                    },
                    @{
                        Name        = "components"
                        Kind        = "Read"
                        Description = "Detected components"
                        Parameters  = @()
                    }
                )
            }
        }
    }
    'outputs.wiimote_hook' {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "outputs.wiimote_hook"
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "Wiimote output chain ok"
            Data       = @{
                Ok                 = $true
                WiimoteDetected    = $true
                GunmoteInstalled   = $true
                GunmoteRunning     = $true
                ViGEmBusInstalled  = $true
                PythonInstalled    = $true
                RelayInstalled     = $true
                TeknoParrotFound   = $true
                DemulShooterFound  = $true
                MameOutputWindows  = $true
                PortConflicts      = @()
                DoubleConsumers    = @()
                Warnings           = @()
                Recommendation     = "Ready"
            }
        }
    }
    'outputs.verify_safety' {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "outputs.verify_safety"
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "Output safety ok"
            Data       = @{
                SolenoidGuard   = @{ Ok = $true; Detail = "" }
                PortConflicts   = @()
                DoubleConsumers = @()
                GunmoteConfig   = @{ InisFound = 8; Connected = $true; RumbleThresholdOk = $true }
                DetectedOutputs = @("GunmoteOutput")
                OutputMode      = ""
            }
        }
    }
    'controllers.input_profiles' {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "controllers.input_profiles"
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "2 input profile(s)"
            Data       = @{
                Profiles = @(
                    @{
                        Name        = "ipac2-default"
                        Description = "Ultimarc I-PAC 2 factory layout (Keyboard + Trackball/Mouse)"
                        Builtin     = $true
                        Intents     = 26
                    },
                    @{
                        Name        = "cabinet"
                        Description = "Frieds Kabinett: Wiimotes via Gunmote (XInput, wie custom1.cfg) plus I-PAC-2-Panel (wie ipac2.cfg), 2 Spieler"
                        Builtin     = $false
                        Intents     = 36
                    }
                )
            }
        }
    }
    'controllers.input_apply' {
        $prof = if ($params.ContainsKey('Profile')) { $params['Profile'] } else { 'ipac2-default' }
        $status = if ($Apply) { "Done" } else { "WhatIf" }
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "controllers.input_apply"
            Kind       = "Change"
            Success    = $true
            Status     = $status
            Applied    = [bool]$Apply
            Message    = "Plan: 26 port(s) for kit-$prof.cfg"
            Data       = @{
                Profile = $prof
                Target  = "C:\FakeRetroBat\saves\mame\ctrlr\kit-$prof.cfg"
                Exists  = $false
            }
        }
    }
    'components' {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = "components"
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "Components detected"
            Data       = @{
                Components = @(
                    @{ Name = "Gunmote"; Present = $true },
                    @{ Name = "ViGEmBus"; Present = $true },
                    @{ Name = "DolphinBar"; Present = $true }
                )
            }
        }
    }
    default {
        $result = @{
            ApiVersion = "1.5"
            KitVersion = "1.3.1"
            Operation  = $Operation
            Kind       = "Read"
            Success    = $true
            Status     = "Ok"
            Applied    = $false
            Message    = "Fake response for $Operation"
            Data       = @{}
        }
    }
}

$result['Duration'] = 0.05
$result['StartedAt'] = $now
$result['Warnings'] = @()
$result['Errors'] = @()
$result['Changes'] = @()
$result['Backups'] = @()
$result['Approvals'] = @()

$json = ConvertTo-Json $result -Depth 5 -Compress
Write-Output $json
