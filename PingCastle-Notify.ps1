<#
    author: Martial Puygrenier - @mpgn_x64
    original work from Romain Tiennot at ManoMano - aikiox
    original gist from aikiox: https://gist.github.com/aikiox/98f97ccc092557acc1ea958d65f8f361#file-send-pingcastlereport-ps1
    change: 
        - better slack integration
        - rule diff between two pingcastle scan
    date: 14/09/2022
    verion: 1.0
#>

### EDIT THIS PARAMETERS ###
$slackChannel = "#pingcastle-scan"
$slackToken="xoxb-xxxxxx-xxxxxx-xxxxxx-xxxxxx"
### END ###

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

#region Variable
$ApplicationName = 'PingCastle'
$PingCastle = [pscustomobject]@{
    Name            = $ApplicationName
    ProgramPath     = Join-Path $PSScriptRoot $ApplicationName
    ProgramName     = '{0}.exe' -f $ApplicationName
    Arguments       = '--healthcheck --level Full'
    ReportFileName  = 'ad_hc_{0}' -f ($env:USERDNSDOMAIN).ToLower()
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

$BodySlack = @{
    channel = $slackChannel;
    text = "
Domain *domain_env* - date_scan - *Global Score abc* : 
- Score: *[cbd Trusts | def Stale Object | asx Privileged Group | dse Anomalies]*
- add_new_vuln";
    icon_emoji = ":ghost:"
    username = "PingCastle Automatic run"
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
    $value = $xml.HealthcheckRiskRule | Select-Object Category, Points, Rationale | Where-Object Category -eq $category 
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
                    $found = 2
                    break   
                }
            }
        }
        if ($found -eq 0 -and $rule.Rationale -and $action -ne ":arrow_forward:") {
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
$BodySlack.Text = $BodySlack.Text.Replace("abc",$str_total_point).Replace("cbd", $str_trusts).Replace("def", $str_staleObject).Replace("asx", $str_privilegeAccount).Replace("dse", $str_anomalies).Replace("domain_env", $domainName).Replace("date_scan", $dateScan.ToString("dd/MM/yyyy"))

$old_report = (Get-ChildItem -Path "Reports" -Filter "*.xml" -Attributes !Directory | Sort-Object -Descending -Property LastWriteTime | select -First 1)
$old_report.FullName
$final_thread = ""
# Check if PingCastle previous score file exist
if (-not ($old_report.FullName)) {
    # if don't exist, sent report
    $sentNotification = $true
    Write-Host "First time run"
    $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "First PingCastle scan ! :tada:")
    $newCategoryContent = $Anomalies + $PrivilegedAccounts + $StaleObjects + $Trusts 
    $result = ""
    Foreach ($rule in $newCategoryContent) {
        $result = $result + ":heavy_exclamation_mark: *+" + $rule.Points + "* - " + $rule.Rationale + "`n"
    }
    $final_thread = $result
} else {
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
            $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "There is no new vulnerability yet some rules have changed !")
        } else {
            $sentNotification = $False
            $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "There is no new vulnerability ! :tada:")
        }
    } elseIf  ([int]$previous_score -lt [int]$total_point) {
        Write-Host "rage"
        $sentNotification = $true
        $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "New rules flagged *+" + [string]([int]$total_point-[int]$previous_score) + " points* :rage: ")
    } elseIf  ([int]$previous_score -gt [int]$total_point) {
        Write-Host "no rage"
        $sentNotification = $true
        $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "Yeah, some improvement have been made *-" +  [string]([int]$previous_score-[int]$total_point) + " points* :smile: ")
    } else {
        Write-Host "same global score but different score in categories"
        $sentNotification = $true
        $BodySlack.Text = $BodySlack.Text.Replace("add_new_vuln", "New rules flagged but also some fix, yet same score than previous scan")
    }
    $final_thread = $addedVuln + $removedVuln + $warningVuln
}

$BodySlack.Text
$final_thread
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
    # send to slack
    $BodySlack.Text
    $r = Invoke-RestMethod -Uri https://slack.com/api/chat.postMessage -Headers $headers -Body $BodySlack -Method Post
    if ($final_thread) {
        $BodySlack2 = @{
            channel = $r.channel;
            thread_ts = $r.ts
            text = $final_thread;
            icon_emoji = ":ghost:"
	    username = "PingCastle Automatic run"
        }
        Invoke-RestMethod -Uri https://slack.com/api/chat.postMessage -Headers $headers -Body $BodySlack2 -Method Post
    }
    $pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDate)
    Move-Item -Path $pingCastleReportFullpath -Destination $pingCastleMoveFile
	$pingCastleMoveFile = (Join-Path $pingCastleReportLogs $pingCastleReportFileNameDateXML)
	Move-Item -Path $pingCastleReportXMLFullpath -Destination $pingCastleMoveFile
    Remove-Item ("{0}.{1}" -f (Join-Path $PingCastle.ProgramPath $PingCastle.ReportFileName), '*')
	"Last scan " + $dateScan | out-file -append $logreport 
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
