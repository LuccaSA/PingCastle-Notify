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
        - update slack module to use new function
        - update teams module to use new function
        - add .env file
    date: 08/08/2025
    version: 1.3
#>

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

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

# Import modules
Import-Module (Join-Path $PSScriptRoot "modules\Slack.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\Teams.psm1") -Force

# Load environment variables
$envPath = Join-Path $PSScriptRoot ".env"
$envVars = Read-EnvFile -Path $envPath

### CONFIGURATION FROM .env FILE ###
# Initialize modules with configuration
Initialize-SlackConfig -envVars $envVars
Initialize-TeamsConfig -envVars $envVars

# Get configuration values for backward compatibility
$slack = Get-SlackEnabled
$teams = Get-TeamsEnabled
$print_current_result = if ($envVars["PRINT_CURRENT_RESULT"]) { [int]$envVars["PRINT_CURRENT_RESULT"] } else { 1 }
$domain = $envVars["DOMAIN"]
### END CONFIGURATION ###

# Handle Mac compatibility - USERDNSDOMAIN doesn't exist on Mac
$domainSuffix = if ($domain) { 
    $domain
} else { 
    ($env:USERDNSDOMAIN).ToLower() 
}

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

# Function update slack color (deprecated - now handled by module)
Function updateSlackColor($body, $point) {
    return Update-SlackColor -body $body -point $point
}

# function send to webhook (updated to use modules)
Function Send_WebHook($body, $connector) {
    if ($connector -eq "slack") {
        return Send-SlackMessage -body $body
    }
    if ($connector -eq "teams") {
        return Send-TeamsMessage -body $body
    }
}

# function update body (updated to use modules)
Function Update_Body($body, $connector) {
    if ($connector -eq "slack") {
        return Update-SlackBody -body $body -domainName $domainName -dateScan $dateScan -total_point $total_point -str_trusts $str_trusts -str_staleObject $str_staleObject -str_privilegeAccount $str_privilegeAccount -str_anomalies $str_anomalies
    }
    if ($connector -eq "teams") {
        return Update-TeamsBody -body $body -domainName $domainName -dateScan $dateScan -str_total_point $str_total_point -str_trusts $str_trusts -str_staleObject $str_staleObject -str_privilegeAccount $str_privilegeAccount -str_anomalies $str_anomalies
    }
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
                    Write-Host $action  + " *+" + $rule.Points + "* - " + $rule.Rationale $rule2.Rationale
                    $found = 2
                    break   
                }
            }
        }
        if ($found -eq 0 -and $rule.Rationale -and $action -ne ":arrow_forward:") {
            Write-Host $action  + " *+" + $rule.Points + "* - " + $rule.Rationale  $rule2.RiskId $rule.RiskId
            If ($action -eq ":heavy_exclamation_mark:") {
                $result = $result + $action  + " *+" + $rule.Points + "* - " + $rule.Rationale + "`n"
            } else {
                $result = $result + $action  + " *-" + $rule.Points + "* - " + $rule.Rationale + "`n"
            }
        } elseIf ($found -eq 2 -and $rule.Rationale) {
            $result = $result + $action  + " *" + $rule.Points + "* - " + $rule.Rationale + "`n"
        }
    } 
    return $result   
}

# Check if program exist
if (-not(Test-Path $pingCastleFullpath)) {
    Write-Error -Message ("Path not found {0}" -f $pingCastleFullpath)
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

# Try to start program and catch any error
try {
    Set-Location -Path $PingCastle.ProgramPath
    Start-Process -FilePath $pingCastleFullpath -ArgumentList $PingCastle.Arguments @splatProcess
}
Catch {
    Write-Error -Message ("Error for execute {0}" -f $pingCastleFullpath)
}

# Check if report exist after execution
foreach ($pingCastleTestFile in ($pingCastleReportFullpath, $pingCastleReportXMLFullpath)) {
    if (-not (Test-Path $pingCastleTestFile)) {
        Write-Error -Message ("Report file not found {0}" -f $pingCastleTestFile)
    }
}

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
$BodySlack = updateSlackColor $BodySlack $total_point
$BodySlack = Update_Body $BodySlack "slack"
$BodyTeams = Update_Body $BodyTeams "teams"

$old_report = (Get-ChildItem -Path "Reports" -Filter "*.xml" -Attributes !Directory | Sort-Object -Descending -Property LastWriteTime | select -First 1)
$old_report.FullName
$current_scan = ""
$final_thread = ""
# Check if PingCastle previous score file exist
if (-not ($old_report.FullName)) {
    # if don't exist, sent report
    $sentNotification = $true
    Write-Host "First time run"
    $BodySlack['attachments'][0]['fields'][4]['value'] = "First PingCastle scan ! :tada:"
    $BodyTeams = $BodyTeams.Replace("add_new_vuln", "First PingCastle scan ! &#129395; `n`n ")
    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    $result = ""
    Foreach ($rule in $newCategoryContent) {

        $action = ":heavy_exclamation_mark: *+"
        if ($rule.RiskId) {
            $result = $result + $action + $rule.Points + "* - " + $rule.Rationale + "`n"
        }
    }
    $final_thread = $result
} else {
    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    Foreach ($rule in $newCategoryContent) {

        $action = ":heavy_exclamation_mark: *+"
        if ($rule.RiskId) {
            $current_scan = $current_scan + $action + $rule.Points + "* - " + $rule.Rationale + "`n"
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

        Write-Host "Previous score " $previous_score
        Write-Host "Current score " $total_point
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
            $BodySlack['attachments'][0]['fields'][4]['value'] = "There is no new vulnerability yet some rules have changed !"
            $BodyTeams = $BodyTeams.Replace("add_new_vuln", "There is no new vulnerability yet some rules have changed !")
        } else {
            $sentNotification = $False
            $BodySlack['attachments'][0]['fields'][4]['value'] = "There is no new vulnerability ! :tada:"
            $BodyTeams = $BodyTeams.Replace("add_new_vuln", "There is no new vulnerability ! &#129395;")

        }
    } elseIf  ([int]$previous_score -lt [int]$total_point) {
        Write-Host "rage"
        $sentNotification = $true
        $BodySlack['attachments'][0]['fields'][4]['value'] = "New rules flagged *+" + [string]([int]$total_point-[int]$previous_score) + " points* :rage: "
        $BodyTeams = $BodyTeams.Replace("add_new_vuln", "New rules flagged **+" + [string]([int]$total_point-[int]$previous_score) + " points** &#128544; `n`n")
    } elseIf  ([int]$previous_score -gt [int]$total_point) {
        Write-Host "no rage"
        $sentNotification = $true
        $BodySlack['attachments'][0]['fields'][4]['value'] = "Yeah, some improvement have been made *-" +  [string]([int]$previous_score-[int]$total_point) + " points* :smile: "
        $BodyTeams = $BodyTeams.Replace("add_new_vuln", "Yeah, some improvement have been made *-" +  [string]([int]$previous_score-[int]$total_point) + " points* &#128516; `n`n")
    } else {
        Write-Host "same global score but different score in categories"
        $sentNotification = $true
        $BodySlack['attachments'][0]['fields'][4]['value'] = "New rules flagged but also some fix, yet same score than previous scan"
        $BodyTeams = $BodyTeams.Replace("add_new_vuln", "New rules flagged but also some fix, yet same score than previous scan `n`n")
    }
    $final_thread = $addedVuln + $removedVuln + $warningVuln
}

$logreport = $PingCastle.ReportFolder + "\\scan.log"

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
    if ($slack) {
        $r = Send_WebHook $BodySlack "slack"
        if ($final_thread) {
            Send-SlackThread -channel $r.channel -thread_ts $r.ts -text $final_thread
        }
        if ($print_current_result) {
            $current_scanslack = "`n *Detected anomalies* `n" + $current_scan
            Send-SlackThread -channel $r.channel -thread_ts $r.ts -text $current_scanslack
        }
    } 
    if ($teams) {
        $formattedTeamsMessage = Format-TeamsMessage -message $BodyTeams -final_thread $final_thread -current_scan $current_scan -print_current_result $print_current_result
        $r = Send_WebHook $formattedTeamsMessage "teams"
    }
    # write log report
    "Last scan " + $dateScan | out-file -append $logreport 
    $log = $BodyTeams 
    $log = $log + $final_thread
    $log = $log.Replace("*","").Replace(":large_green_circle:","").Replace(":large_orange_circle:","").Replace(":large_yellow_circle:","").Replace(":red_circle:","").Replace(":heavy_exclamation_mark:","!").Replace(":white_check_mark:","-").Replace(":arrow_forward:",">").Replace(":tada:","")
    $log = $log.Replace("{","").Replace("   text:'","").Replace("&#129395;","")
    $log | out-file -append $logreport

    $log

    $pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDate)
    Move-Item -Path $pingCastleReportFullpath -Destination $pingCastleMoveFile
    $pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDateXML)
    Move-Item -Path $pingCastleReportXMLFullpath -Destination $pingCastleMoveFile
    Remove-Item ("{0}.{1}" -f (Join-Path $PingCastle.ProgramPath $PingCastle.ReportFileName), '*')
}
catch {
    Write-Error -Message ("Error for move report file to logs directory {0}" -f $pingCastleReportFullpath)
}

# Try to start update program and catch any error
try {
    Write-Information "Trying to update"
    Start-Process -FilePath $pingCastleUpdateFullpath -ArgumentList $PingCastle.ArgumentsUpdate @splatProcess
    Write-Information "Update completed"
}
Catch {
    Write-Error -Message ("Error for execute update program {0}" -f $pingCastleUpdateFullpath)
}
