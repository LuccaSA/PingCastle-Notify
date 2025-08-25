<#
    author: Martial Puygrenier - @mpgn_x64
    original work from Romain Tiennot at ManoMano - aikiox
    original gist from aikiox: https://gist.github.com/aikiox/98f97ccc092557acc1ea958d65f8f361#file-send-pingcastlereport-ps1
    change: 
        - slack integration
        - rule diff between two pingcastle scan
        - teams integration
        - scan log integration
        - option $print_current_result to add all flaged rules
    date: 14/09/2022
    version: 1.1
    change:
        - better slack integration with color
    date: 22/02/2024
    version: 1.2
    change:
        - update slack module to use new module
        - update teams module to use new module
        - add .env file
        - add discord module 
        - refactoring to use new connector modules
        - add -noscan option to skip PingCastle scan
        - add -full_report option to force full report
        - add anssi rules link
    date: 08/08/2025
    version: 2.0
#>

param(
    [switch]$noscan,
    [switch]$version,
    [switch]$help,
    [switch]$full_report
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'SilentlyContinue'

# Version information
$scriptVersion = "2.0"
$scriptAuthor = "@mpgn_x64"
$scriptDate = "08/08/2025"

# Handle help parameter
if ($help) {
    Write-Host @"
PingCastle Notify v$scriptVersion - Help

SYNOPSIS
    Automated notification system for PingCastle security reports.

SYNTAX
    .\PingCastle-Notify.ps1 [parameters]

PARAMETERS
    -noscan
        Skip the PingCastle scan and only process existing reports.
        Useful for testing notifications or processing pre-generated reports.

    -full-report
        Force inclusion of all detected anomalies in notifications.
        Overrides PRINT_CURRENT_RESULT setting in .env file.

    -version
        Display version information and exit.

    -help
        Display this help message and exit.

    -InformationAction Continue
        Enable verbose output for debugging purposes.

CONFIGURATION
    Configure notification settings in the .env file.
    Supported platforms: Slack, Microsoft Teams, Discord

For more information, visit: https://github.com/mpgn/PingCastle-Notify
"@ -ForegroundColor Green
    exit 0
}

# Handle version parameter
if ($version) {
    Write-Host @"
PingCastle Notify v$scriptVersion
Author: Martial Puygrenier ($scriptAuthor)
Release Date: $scriptDate
License: MIT

A PowerShell notification system for PingCastle security reports.
Supports Slack, Microsoft Teams, and Discord notifications.

For more information, visit: https://github.com/mpgn/PingCastle-Notify
"@ -ForegroundColor Cyan
    exit 0
}

# ASCII Art Banner
Write-Host @"

##################################################
#                                                #
#                PINGCASTLE NOTIFY               #
#          Automated Notification System         #
#                                                #
"@ -ForegroundColor Cyan

Write-Host "#" -ForegroundColor Cyan -NoNewline
Write-Host "            v$scriptVersion by $scriptAuthor - Lucca           " -ForegroundColor Magenta -NoNewline  
Write-Host "#" -ForegroundColor Cyan

Write-Host @"
##################################################

"@ -ForegroundColor Cyan

# Function to read .env file
Function Read-EnvFile {
    param(
        [string]$Path = ".env"
    )
    
    $envVars = @{}
    
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            $line = $_.Trim()
            # Skip empty lines and comments
            if ($line -and !$line.StartsWith("#")) {
                if ($line -match "^([^=]+)=(.*)$") {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    # Remove quotes if present
                    $value = $value -replace '^["'']|["'']$', ''
                    $envVars[$key] = $value
                }
            }
        }
        Write-Information "Loaded configuration from $Path"
    } else {
        Write-Warning "Environment file $Path not found, using default values"
    }
    
    return $envVars
}

# Load environment variables
$envPath = Join-Path $PSScriptRoot ".env"
$envVars = Read-EnvFile -Path $envPath

### CONFIGURATION FROM .env FILE ###
# Dynamically import all connector modules
$modulePath = Join-Path $PSScriptRoot "modules"
$connectorModules = @()
$enabledConnectors = @{}

if (Test-Path $modulePath) {
    Get-ChildItem -Path $modulePath -Filter "*.psm1" | ForEach-Object {
        $moduleName = $_.BaseName
        Write-Host "[+] Loading module: $moduleName"
        Import-Module $_.FullName -Force
        $connectorModules += $moduleName
        
        # Initialize connector configuration
        $initFunction = "Initialize-${moduleName}Config"
        if (Get-Command $initFunction -ErrorAction SilentlyContinue) {
            & $initFunction -envVars $envVars
            
            # Check if connector is enabled
            $enabledFunction = "Get-${moduleName}Enabled"
            if (Get-Command $enabledFunction -ErrorAction SilentlyContinue) {
                $enabledConnectors[$moduleName] = & $enabledFunction
            }
        }
    }
}

# Get configuration values for backward compatibility
$print_current_result = if ($full_report) { 
    1 
} elseif ($envVars["PRINT_CURRENT_RESULT"]) { 
    [int]$envVars["PRINT_CURRENT_RESULT"] 
} else { 
    0 
}
# Handle Mac compatibility - USERDNSDOMAIN doesn't exist on Mac
$domainSuffix = if ($envVars["DOMAIN"] ) { $envVars["DOMAIN"] } else { 
    ($env:USERDNSDOMAIN).ToLower() 
}
$anssi_lvl_enabled = if ($envVars["ANSSI_LVL"]) { [int]$envVars["ANSSI_LVL"] } else { 0 }

#region Variable
$ApplicationName = 'PingCastle'
$PingCastle = [pscustomobject]@{
    Name            = $ApplicationName
    ProgramPath     = Join-Path $PSScriptRoot $ApplicationName
    ProgramName     = '{0}.exe' -f $ApplicationName
    Arguments       = '--healthcheck --level Full'
    ReportFileName  = 'ad_hc_{0}' -f $domainSuffix
    ReportFolder    = "Reports"
    ProgramUpdate   = '{0}AutoUpdater.exe' -f $ApplicationName
    ArgumentsUpdate = '--wait-for-days 30'
}

$pingCastleFullpath = Join-Path $PingCastle.ProgramPath $PingCastle.ProgramName
$pingCastleUpdateFullpath = Join-Path $PingCastle.ProgramPath $PingCastle.ProgramUpdate
$pingCastleReportLogs = Join-Path $PingCastle.ProgramPath $PingCastle.ReportFolder
$pingCastleReportFullpath = Join-Path $PingCastle.ProgramPath ('{0}.html' -f $PingCastle.ReportFileName)
$pingCastleReportXMLFullpath = Join-Path $PingCastle.ProgramPath ('{0}.xml' -f $PingCastle.ReportFileName)

$pingCastleReportDate = Get-Date -UFormat %Y%m%d_%H%M%S
$pingCastleReportFileNameDate = ('{0}_{1}' -f $pingCastleReportDate, ('{0}.html' -f $PingCastle.ReportFileName))
$pingCastleReportFileNameDateXML = ('{0}_{1}' -f $pingCastleReportDate, ('{0}.xml' -f $PingCastle.ReportFileName))

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{
    Authorization="Bearer $slackToken"
}

$sentNotification = $false

$splatProcess = @{
    WindowStyle = 'Hidden'
    Wait        = $true
}

$BodySlack = Get-SlackBody
$BodyTeams = Get-TeamsBody

# Initialize connector bodies
$connectorBodies = @{}
foreach ($connector in $connectorModules) {
    $bodyFunction = "Get-${connector}Body"
    if (Get-Command $bodyFunction -ErrorAction SilentlyContinue) {
        $connectorBodies[$connector] = & $bodyFunction
    }
}

# Generic function to update all enabled connectors with first scan message
Function Update-ConnectorsFirstScan($connectorBodies) {
    $updatedBodies = @{}
    foreach ($connector in $connectorModules) {
        $updatedBodies[$connector] = $connectorBodies[$connector]
        
        if ($enabledConnectors[$connector]) {
            $updateFunction = "Update-${connector}FirstScanMessage"
            if (Get-Command $updateFunction -ErrorAction SilentlyContinue) {
                $updatedBodies[$connector] = & $updateFunction -body $connectorBodies[$connector]
            }
        }
    }
    return $updatedBodies
}

# Generic function to update all enabled connectors with status message
Function Update-ConnectorsStatus($connectorBodies, $message) {
    $updatedBodies = @{}
    foreach ($connector in $connectorModules) {
        $updatedBodies[$connector] = $connectorBodies[$connector]
        
        if ($enabledConnectors[$connector]) {
            $updateFunction = "Update-${connector}StatusMessage"
            if (Get-Command $updateFunction -ErrorAction SilentlyContinue) {
                $updatedBodies[$connector] = & $updateFunction -body $connectorBodies[$connector] -message $message
            }
        }
    }
    return $updatedBodies
}

# Function to get ANSSI level for a rule
Function Get-ANSSILevel($riskId) {
    if ($script:ANSSIMapping.ContainsKey($riskId)) {
        return $script:ANSSIMapping[$riskId].Level
    }
    return $null
}

# Function to get ANSSI URL for a rule
Function Get-ANSSIURL($riskId) {
    if ($script:ANSSIMapping.ContainsKey($riskId)) {
        return $script:ANSSIMapping[$riskId].URL
    }
    return $null
}

# Function to format rule with ANSSI level and URL
Function Format-RuleWithANSSILevel($rule) {
    $anssiLevel = Get-ANSSILevel $rule.RiskId
    $anssiURL = Get-ANSSIURL $rule.RiskId
    
    if ($anssiLevel -and $anssiURL) {
        return "$($rule.Rationale) ([ANSSI L$anssiLevel]($anssiURL))"
    } elseif ($anssiLevel) {
        return "$($rule.Rationale) ([ANSSI L$anssiLevel)($anssiURL))"
    }
    return $rule.Rationale
}

# Function to calculate ANSSI maturity level (lowest level found)
Function Get-ANSSIMaturityLevel($rules) {
    $lowestLevel = 5  # Start with highest possible level
    
    foreach ($rule in $rules) {
        if ($rule.RiskId) {
            $level = Get-ANSSILevel $rule.RiskId
            if ($level -and $level -lt $lowestLevel) {
                $lowestLevel = $level
            }
        }
    }
    
    # If no ANSSI rules found or lowest level is 4 or higher, return level 5
    if ($lowestLevel -ge 4) {
        return 5
    } else {
        return $lowestLevel
    }
}

# Generic function to update connector body with scan data
Function Update-ConnectorBodies($connectorBodies, $domainName, $dateScan, $total_point, $str_trusts, $str_staleObject, $str_privilegeAccount, $str_anomalies, $anssiMaturityText) {
    $updatedBodies = @{}
    foreach ($connector in $connectorModules) {
        $updatedBodies[$connector] = $connectorBodies[$connector]
        
        $updateFunction = "Update-${connector}Body"
        if (Get-Command $updateFunction -ErrorAction SilentlyContinue) {
            $params = @{
                body = $connectorBodies[$connector]
                domainName = $domainName
                dateScan = $dateScan
                anssiMaturityText = $anssiMaturityText
            }
            
            # Add connector-specific parameters
            if ($connector -eq "Slack") {
                $params.total_point = $total_point
            } else {
                $params.str_total_point = Add_Color $total_point
            }
            
            $params.str_trusts = $str_trusts
            $params.str_staleObject = $str_staleObject
            $params.str_privilegeAccount = $str_privilegeAccount
            $params.str_anomalies = $str_anomalies
            
            $updatedBodies[$connector] = & $updateFunction @params
        }
    }
    return $updatedBodies
}

# Generic function to send messages to all enabled connectors
Function Send-ConnectorMessages($connectorBodies, $final_thread, $current_scan) {
    $responses = @{}
    
    foreach ($connector in $connectorModules) {
        if ($enabledConnectors[$connector]) {
            $sendFunction = "Send-${connector}Message"
            if (Get-Command $sendFunction -ErrorAction SilentlyContinue) {
                
                # Teams and Discord send everything in one message
                if ($connector -ne "Slack") {
                    $responses[$connector] = & $sendFunction -body $connectorBodies[$connector] -final_thread $final_thread -current_scan $current_scan -print_current_result $print_current_result
                } else {
                    $responses[$connector] = & $sendFunction -body $connectorBodies[$connector]
                    
                    # Handle thread messages for Slack
                    if ($connector -eq "Slack" -and $responses[$connector]) {
                        $threadFunction = "Send-${connector}Thread"
                        if (Get-Command $threadFunction -ErrorAction SilentlyContinue) {
                            if ($final_thread) {
                                & $threadFunction -channel $responses[$connector].channel -thread_ts $responses[$connector].ts -text $final_thread
                            }
                            if ($print_current_result) {
                                $current_scanformatted = "`n *Detected anomalies* `n" + $current_scan
                                & $threadFunction -channel $responses[$connector].channel -thread_ts $responses[$connector].ts -text $current_scanformatted
                            }
                        }
                    }
                }
            }
        }
    }
    
    return $responses
}

# function to deal with slack color
Function Add_Color($p){
    if ($p -is [ValueType]) {
        $point = $p
    } else {
        $p1 = $p | Measure-Object -Sum Points
        $point = $p1.Sum
    }

    if ($point -ge 75) {
        return [string]$point + " :red_circle:"
    } elseIf ($point -ge 50 -and $point -lt 75) {
        return [string]$point + " :large_orange_circle:"
    } elseIf ($point -ge 25 -and $point -lt 50) {
        return [string]$point + " :large_yellow_circle:"
    } elseIf ($point -ge 0 -and $point -lt 25) {
        return [string]$point + " :large_green_circle:"
    } else {
        return [string]$point + " :large_green_circle:"
    }
}

# function extract HealthcheckRiskRule data
Function ExtractXML($xml,$category) {
    $value = $xml.HealthcheckRiskRule | Select-Object Category, Points, Rationale, RiskId | Where-Object Category -eq $category 
    if ($value -eq $null)
    {
        $value = New-Object psobject -Property @{
            Category = $category
            Points = 0
        }
    }
    return $value
}

# function to calc sum from xml
Function CaclSumGroup($a,$b,$c,$d) {
    $a1 = $a | Measure-Object -Sum Points
    $b1 = $b | Measure-Object -Sum Points
    $c1 = $c | Measure-Object -Sum Points
    $d1 = $d | Measure-Object -Sum Points
    return $a1.Sum + $b1.Sum + $c1.Sum + $d1.Sum 
}

# function to calc sum from one source
Function IsEqual($a,$b) {
    [int]$a1 = $a | Measure-Object -Sum Points | Select-Object -Expand Sum
    [int]$b1 = $b | Measure-Object -Sum Points | Select-Object -Expand Sum
    if($a1 -eq $b1) {
        return 1
    }
    return 0
}

# ANSSI Rule Level and URL Mapping
$script:ANSSIMapping = @{
    "S-PwdLastSet-Cluster" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_cluster_no_change_3years" }
    "S-PwdLastSet-45" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_server_no_change_45" }
    "S-PwdLastSet-90" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_server_no_change_90" }
    "S-DC-Inactive" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_inactive_dc" }
    "S-PwdLastSet-DC" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_dc_no_change" }
    "S-Inactive" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_user_accounts_dormant" }
    "S-C-Inactive" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_inactive_servers" }
    "S-C-PrimaryGroup" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_primary_group_id_nochange" }
    "S-PrimaryGroup" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_primary_group_id_nochange" }
    "S-Reversible" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_reversible_password" }
    "S-C-Reversible" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_reversible_password" }
    "S-NoPreAuth" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_kerberos_properties_preauth" }
    "S-NoPreAuthAdmin" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_kerberos_properties_preauth_priv" }
    "S-PwdNeverExpires" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dont_expire" }
    "S-FunctionalLevel1" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_functional_level" }
    "S-FunctionalLevel3" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_functional_level" }
    "S-FunctionalLevel4" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_functional_level" }
    "S-DC-2000" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_warning_dc_obsolete" }
    "S-DC-2003" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_warning_dc_obsolete" }
    "S-DC-2008" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_warning_dc_obsolete" }
    "S-DC-2012" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_warning_dc_obsolete" }
    "S-AesNotEnabled" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_kerberos_properties_encryption" }
    "S-DesEnabled" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_kerberos_properties_deskey" }
    "S-DCRegistration" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dc_inconsistent_uac" }
    "S-ADRegistration" = @{ Level = 4; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_user_accounts_machineaccountquota" }
    "S-ADRegistrationSchema" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_warning_schema_posssuperiors" }
    "P-Kerberoasting" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_spn_priv" }
    "P-AdminPwdTooOld" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_password_change_priv" }
    "P-ProtectedUsers" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_protected_users" }
    "P-DisplaySpecifier" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_display_specifier" }
    "P-DelegationDCt2a4d" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_delegation_t2a4d" }
    "P-DelegationDCa2d2" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_delegation_a2d2" }
    "P-DelegationDCsourcedeleg" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_delegation_sourcedeleg" }
    "P-UnconstrainedDelegation" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_delegation_t4d" }
    "P-ServiceDomainAdmin" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dont_expire_priv" }
    "P-RODCRevealOnDemand" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_reveal" }
    "P-RODCAdminRevealed" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_priv_revealed" }
    "P-RODCNeverReveal" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_never_reveal" }
    "P-RODCAllowedGroup" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_allowed_group" }
    "P-RODCDeniedGroup" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_denied_group" }
    "P-RODCKrbtgtOrphan" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_rodc_orphan_krbtgt" }
    "T-SIDFiltering" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_trusts_forest_sidhistory" }
    "T-SIDHistorySameDomain" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_sidhistory_present" }
    "T-SIDHistoryDangerous" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_sidhistory_dangerous" }
    "T-SIDHistoryUnknownDomain" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_sidhistory_present" }
    "T-TGTDelegation" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_trusts_tgt_deleg" }
    "T-Inactive" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_trusts_accounts" }
    "T-AzureADSSO" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_trusts_accounts" }
    "A-WeakRSARootCert2" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-CertWeakRsaComponent" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-WeakRSARootCert" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-CertWeakDSA" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD2IntermediateCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD4IntermediateCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD5IntermediateCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-SHA0IntermediateCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-SHA1IntermediateCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD2RootCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD4RootCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-MD5RootCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-SHA0RootCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-SHA1RootCert" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-CertROCA" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_certificates_vuln" }
    "A-CertTempCustomSubject" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_adcs_template_auth_enroll_with_name" }
    "A-CertTempNoSecurity" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_adcs_template_auth_enroll_with_name" }
    "A-CertTempAnyone" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_adcs_template_auth_enroll_with_name" }
    "A-CertTempAgent" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_adcs_template_auth_enroll_with_name" }
    "A-CertTempAnyPurpose" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_adcs_template_auth_enroll_with_name" }
    "A-Krbtgt" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_krbtgt" }
    "A-MinPwdLen" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_privileged_members_password" }
    "A-DnsZoneUpdate2" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dnszone_bad_prop" }
    "A-DnsZoneUpdate1" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dnszone_bad_prop" }
    "A-NTFRSOnSysvol" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_sysvol_ntfrs" }
    "A-DsHeuristicsAllowAnonNSPI" = @{ Level = 1; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dsheuristics_bad" }
    "A-DsHeuristicsAnonymous" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dsheuristics_bad" }
    "A-PreWin2000Anonymous" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_compatible_2000_anonymous" }
    "A-DsHeuristicsLDAPSecurity" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dsheuristics_bad" }
    "A-DsHeuristicsDoNotVerifyUniqueness" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_dsheuristics_bad" }
    "A-PreWin2000Other" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_compatible_2000_not_default" }
    "A-AdminSDHolder" = @{ Level = 2; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_privileged_members_no_admincount" }
    "A-ReversiblePwd" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_reversible_password" }
    "A-UnixPwd" = @{ Level = 3; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_reversible_password" }
    "A-SmartCardPwdRotation" = @{ Level = 4; URL = "https://www.cert.ssi.gouv.fr/uploads/ad_checklist.html#vuln_smartcard_expire_passwords" }
}

# function to get diff between two reports
Function DiffReport($xml1,$xml2,$action) {

    $result = ""
    Foreach ($rule in $xml1) {
        $found = 0
        Foreach ($rule2 in $xml2) {
            if ($rule.RiskId -and $rule2.RiskId) {
                # if not warning and ...
                if ($action -ne ":arrow_forward:" -and ($rule2.RiskId -eq $rule.RiskId)) {
                    $found = 1
                    break
                # else if warning and                       
                } elseIf ($action -eq ":arrow_forward:" -and ($rule2.RiskId -eq $rule.RiskId) -and ($rule2.Rationale -ne $rule.Rationale)) {
                    $formattedRationale = Format-RuleWithANSSILevel $rule
                    $formattedRationale2 = Format-RuleWithANSSILevel $rule2
                    Write-Information ($action  + " *+" + $rule.Points + "* - " + $formattedRationale + " " + $formattedRationale2)
                    $found = 2
                    break   
                }
            }
        }
        if ($found -eq 0 -and $rule.Rationale -and $action -ne ":arrow_forward:") {
            $formattedRationale = Format-RuleWithANSSILevel $rule
            
            Write-Information ($action  + " *+" + $rule.Points + "* - " + $formattedRationale + " " + $rule2.RiskId + " " + $rule.RiskId)
            If ($action -eq ":heavy_exclamation_mark:") {
                $result = $result + $action  + " *+" + $rule.Points + "* - " + $formattedRationale + "`n"
            } else {
                $result = $result + $action  + " *-" + $rule.Points + "* - " + $formattedRationale + "`n"
            }
        } elseIf ($found -eq 2 -and $rule.Rationale) {
            $formattedRationale = Format-RuleWithANSSILevel $rule
            $result = $result + $action  + " *" + $rule.Points + "* - " + $formattedRationale + "`n"
        }
    } 
    return $result   
}

# Check if log directory exist. If not, create it
if (-not (Test-Path $pingCastleReportLogs)) {
    try {
        $null = New-Item -Path $pingCastleReportLogs -ItemType directory
    }
    Catch {
        Write-Error -Message ("Error for create directory {0}" -f $pingCastleReportLogs)
    }
}

Set-Location -Path $PingCastle.ProgramPath
Write-Host ""
if (-not $noscan) {
    # Check if program exist
    if (-not(Test-Path $pingCastleFullpath)) {
        Write-Error -Message ("Path not found {0}" -f $pingCastleFullpath)
    }
    try {
        Write-Host "[+] Running PingCastle scan"
        Start-Process -FilePath $pingCastleFullpath -ArgumentList $PingCastle.Arguments @splatProcess
    }
    Catch {
        Write-Error -Message ("Error for execute {0}" -f $pingCastleFullpath)
    }
} else {
    Write-Host "[+] Skipping PingCastle scan (noscan mode)" -ForegroundColor Yellow
}

# Check if report exist after execution
foreach ($pingCastleTestFile in ($pingCastleReportFullpath, $pingCastleReportXMLFullpath)) {
    if (-not (Test-Path $pingCastleTestFile)) {
        Write-Error -Message ("Report file not found {0}" -f $pingCastleTestFile)
    }
}

Write-Host "[+] Analyzing report content"

# Get content on XML file
try {
    $contentPingCastleReportXML = $null
    $contentPingCastleReportXML = (Select-Xml -Path $pingCastleReportXMLFullpath -XPath "/HealthcheckData/RiskRules").node
    $domainName = (Select-Xml -Path $pingCastleReportXMLFullpath -XPath "/HealthcheckData/DomainFQDN").node.InnerXML
    $dateScan = [datetime](Select-Xml -Path $pingCastleReportXMLFullpath -XPath "/HealthcheckData/GenerationDate").node.InnerXML
    # get metrics
    $Anomalies = ExtractXML $contentPingCastleReportXML "Anomalies"
    $PrivilegedAccounts = ExtractXML $contentPingCastleReportXML "PrivilegedAccounts"
    $StaleObjects = ExtractXML $contentPingCastleReportXML "StaleObjects"
    $Trusts = ExtractXML $contentPingCastleReportXML "Trusts"
    $total_point = CaclSumGroup $Trusts $StaleObjects $PrivilegedAccounts $Anomalies 
}
catch {
    Write-Error -Message ("Unable to read the content of the xml file {0}" -f $pingCastleReportXMLFullpath)
}

$str_total_point = Add_Color $total_point
$str_trusts = Add_Color $Trusts
$str_staleObject = Add_Color $StaleObjects
$str_privilegeAccount = Add_Color $PrivilegedAccounts
$str_anomalies = Add_Color $Anomalies

# Calculate ANSSI maturity level
$allRules = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts
$anssiMaturity = Get-ANSSIMaturityLevel $allRules
$anssiMaturityText = if ($anssi_lvl_enabled -and $anssiMaturity) { " (ANSSI Maturity Level $anssiMaturity/5)" } else { "" }

# Update Slack color if enabled
if ($enabledConnectors["Slack"]) {
    $connectorBodies["Slack"] = Update-SlackColor -body $connectorBodies["Slack"] -point $total_point
}
# Update all connector bodies with scan data
$connectorBodies = Update-ConnectorBodies $connectorBodies $domainName $dateScan $total_point $str_trusts $str_staleObject $str_privilegeAccount $str_anomalies $anssiMaturityText
$old_report = (Get-ChildItem -Path "Reports" -Filter "*.xml" -Attributes !Directory | Sort-Object -Descending -Property LastWriteTime | select -First 1)
Write-Information $old_report.FullName
$current_scan = ""
$final_thread = ""
# Check if PingCastle previous score file exist
if (-not ($old_report.FullName)) {
    # if don't exist, sent report
    $sentNotification = $true
    Write-Information "First time run"
    
    # Update all connectors with first scan message
    $connectorBodies = Update-ConnectorsFirstScan $connectorBodies
    
    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    $result = ""
    Foreach ($rule in $newCategoryContent) {
        $action = ":heavy_exclamation_mark: *+"
        if ($rule.RiskId) {
            $formattedRationale = Format-RuleWithANSSILevel $rule
            $result = $result + $action + $rule.Points + "* - " + $formattedRationale + "`n"
        }
    }
    $final_thread = $result
} else {

    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    Foreach ($rule in $newCategoryContent) {

        $action = ":heavy_exclamation_mark: *+"
        if ($rule.RiskId) {
            $formattedRationale = Format-RuleWithANSSILevel $rule
            $current_scan = $current_scan + $action + $rule.Points + "* - " + $formattedRationale + "`n"
        }
    }

    # Get content of previous PingCastle score
    try {
        $pingCastleOldReportXMLFullpath = $old_report.FullName
        $contentOldPingCastleReportXML = (Select-Xml -Path $pingCastleOldReportXMLFullpath -XPath "/HealthcheckData/RiskRules").node
        $Anomalies_old = ExtractXML $contentOldPingCastleReportXML "Anomalies"  
        $PrivilegedAccounts_old = ExtractXML $contentOldPingCastleReportXML "PrivilegedAccounts" 
        $StaleObjects_old = ExtractXML $contentOldPingCastleReportXML "StaleObjects" 
        $Trusts_old = ExtractXML $contentOldPingCastleReportXML "Trusts" 
        $previous_score = CaclSumGroup $Trusts_old $StaleObjects_old $PrivilegedAccounts_old $Anomalies_old

        Write-Information "Previous score $previous_score"
        Write-Information "Current score $total_point"
    }
    catch {
        Write-Error -Message ("Unable to read the content of the xml file {0}" -f $old_report)
    }
    
    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    $oldCategoryContent = $Anomalies_old + $PrivilegedAccounts_old + $StaleObjects_old + $Trusts_old 

    $addedVuln = DiffReport $newCategoryContent $oldCategoryContent ":heavy_exclamation_mark:"
    $removedVuln = DiffReport $oldCategoryContent $newCategoryContent ":white_check_mark:"
    $warningVuln = DiffReport $newCategoryContent $oldCategoryContent ":arrow_forward:"

    # write message regarding previous score
    if ([int]$previous_score -eq [int]$total_point -and (IsEqual $StaleObjects_old $StaleObjects) -and (IsEqual $PrivilegedAccounts_old $PrivilegedAccounts) -and (IsEqual $Anomalies_old $Anomalies) -and (IsEqual $Trusts_old $Trusts)) {
        if ($addedVuln -or $removedVuln -or $warningVuln) {
            $sentNotification = $True
            $connectorBodies = Update-ConnectorsStatus $connectorBodies "There is no new vulnerability yet some rules have changed !"
        } else {
            $sentNotification = $False
            $connectorBodies = Update-ConnectorsStatus $connectorBodies "There is no new vulnerability ! :tada:"
        }
    } elseIf  ([int]$previous_score -lt [int]$total_point) {
        Write-Information "rage"
        $sentNotification = $true
        $message = "New rules flagged *+" + [string]([int]$total_point-[int]$previous_score) + " points* :rage: "
        $connectorBodies = Update-ConnectorsStatus $connectorBodies $message
    } elseIf  ([int]$previous_score -gt [int]$total_point) {
        Write-Information "no rage"
        $sentNotification = $true
        $message = "Yeah, some improvement have been made *-" +  [string]([int]$previous_score-[int]$total_point) + " points* :smile: "
        $connectorBodies = Update-ConnectorsStatus $connectorBodies $message
    } else {
        Write-Information "same global score but different score in categories"
        $sentNotification = $true
        $connectorBodies = Update-ConnectorsStatus $connectorBodies "New rules flagged but also some fix, yet same score than previous scan"
    }
    
    $final_thread = $addedVuln + $removedVuln + $warningVuln
}
$logreport = $PingCastle.ReportFolder + "\\scan.log"

Write-Host "[+] Analyzing report done"
Write-Host ""

# If content is same, don't sent report
if ($sentNotification -eq $false) {
    Remove-Item ("{0}.{1}" -f (Join-Path $PingCastle.ProgramPath $PingCastle.ReportFileName), '*')
    Write-Information "Same value on PingCastle report. Report deleted."
    "Last scan " + $dateScan | out-file -append $logreport 
    exit
}

# Move report to logs directory
try {
    Write-Information "Sending information by email, webhook, etc..."
    
    # Send messages to all enabled connectors
    $responses = Send-ConnectorMessages $connectorBodies $final_thread $current_scan
    
    # write log report
    "Last scan " + $dateScan | out-file -append $logreport 
    
    # Use Teams body for logging if available, otherwise use first available connector
    $logBody = $null
    if ($connectorBodies["Teams"]) {
        $logBody = $connectorBodies["Teams"]
    } else {
        # Get first available connector body for logging
        foreach ($connector in $connectorModules) {
            if ($connectorBodies[$connector]) {
                $logBody = $connectorBodies[$connector]
                break
            }
        }
    }
    
    if ($logBody) {
        $log = $logBody
        $log = $log + $final_thread
        $log = $log.Replace("*","").Replace(":large_green_circle:","").Replace(":large_orange_circle:","").Replace(":large_yellow_circle:","").Replace(":red_circle:","").Replace(":heavy_exclamation_mark:","!").Replace(":white_check_mark:","-").Replace(":arrow_forward:",">").Replace(":tada:","")
        $log = $log.Replace("{","").Replace("   text:'","").Replace("&#129395;","")
        $log | out-file -append $logreport
        Write-Host "[+] Log report written to $logreport" -ForegroundColor Blue
        Write-Information "Log report information: "
        Write-Information $log
    }

    Write-Host "[+] Moving report files to logs directory" -ForegroundColor Green
    $pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDate)
    Move-Item -Path $pingCastleReportFullpath -Destination $pingCastleMoveFile
    Write-Host "    Moved HTML report to: $pingCastleMoveFile" -ForegroundColor Gray
    
    $pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDateXML)
    Move-Item -Path $pingCastleReportXMLFullpath -Destination $pingCastleMoveFile
    Write-Host "    Moved XML report to: $pingCastleMoveFile" -ForegroundColor Gray
    
    Remove-Item ("{0}.{1}" -f (Join-Path $PingCastle.ProgramPath $PingCastle.ReportFileName), '*')
    Write-Host "[+] Cleaned up temporary report files" -ForegroundColor Green
}
catch {
    Write-Error -Message ("Error for move report file to logs directory {0}" -f $pingCastleReportFullpath)
}

if (-not $noscan) {
    # Try to start update program and catch any error
    try {
        Write-Host "[+] Checking for PingCastle updates" -ForegroundColor Yellow
        Write-Information "Trying to update"
        Start-Process -FilePath $pingCastleUpdateFullpath -ArgumentList $PingCastle.ArgumentsUpdate @splatProcess
        Write-Host "[+] PingCastle update completed" -ForegroundColor Green
        Write-Information "Update completed"
    }
    Catch {
        Write-Error -Message ("Error for execute update program {0}" -f $pingCastleUpdateFullpath)
    }
} else {
    Write-Host "[+] Skipping PingCastle update (noscan mode)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[+] PingCastle Notify execution completed successfully" -ForegroundColor Green

