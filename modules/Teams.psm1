# Teams Module for PingCastle-Notify

function Initialize-TeamsConfig {
    param(
        [hashtable]$envVars
    )
    
    $script:teamsEnabled = if ($envVars["TEAMS_ENABLED"]) { [int]$envVars["TEAMS_ENABLED"] } else { 0 }
    $script:teamsUri = if ($envVars["TEAMS_URI"]) { $envVars["TEAMS_URI"] } else { "https://xxxxxxxxx.office.com/webhookb2/xxxxxxxxxxxxx/IncomingWebhook/xxxxxxxxx/xxxxxxxxx" }
    
    $script:BodyTeams = @"
{
   text:'Domain *domain_env* - date_scan - *Global Score abc* : 
- Score: *[cbd Trusts | def Stale Object | asx Privileged Group | dse Anomalies]*
- add_new_vuln
"@
}

function Update-TeamsBody {
    param(
        [string]$body,
        [string]$domainName,
        [datetime]$dateScan,
        [string]$str_total_point,
        [string]$str_trusts,
        [string]$str_staleObject,
        [string]$str_privilegeAccount,
        [string]$str_anomalies
    )
    
    return $body.Replace("abc", $str_total_point).Replace("cbd", $str_trusts).Replace("def", $str_staleObject).Replace("asx", $str_privilegeAccount).Replace("dse", $str_anomalies).Replace("domain_env", $domainName).Replace("date_scan", $dateScan.ToString("dd/MM/yyyy"))
}

function Send-TeamsMessage {
    param(
        [string]$body
    )
    
    if (-not $script:teamsEnabled) {
        return $null
    }
    
    try {
        Write-Host "Sending to teams"
        return Invoke-RestMethod -Method Post -ContentType 'application/Json' -Body $body -Uri $script:teamsUri
    }
    catch {
        Write-Error "Failed to send Teams message: $_"
        return $null
    }
}

function Format-TeamsMessage {
    param(
        [string]$message,
        [string]$final_thread = "",
        [string]$current_scan = "",
        [bool]$print_current_result = $true
    )
    
    # Escape single quotes
    $current_scan = $current_scan.replace("'", "\'")
    $final_thread = $final_thread.replace("'", "\'")
    
    # Build final message
    if ($print_current_result) {
        $current_scan = "`n`---`n Detected anomalies: `n" + $current_scan
        $finalMessage = $message + $final_thread + $current_scan + "'}"
    } else {
        $finalMessage = $message + $final_thread + "'}"
    }
    
    # Convert markdown and emojis for Teams
    $finalMessage = $finalMessage.Replace("*","**").Replace("`n","`n`n")
    $finalMessage = $finalMessage.Replace(":red_circle:","&#128308;").Replace(":large_orange_circle:","&#128992;").Replace(":large_yellow_circle:","&#128993;").Replace(":large_green_circle:","&#128994;")
    $finalMessage = $finalMessage.Replace(":heavy_exclamation_mark:", "&#10071;").Replace(":white_check_mark:", "&#9989;").Replace(":arrow_forward:", "&#128312;")
    
    return $finalMessage
}

function Get-TeamsBody {
    return $script:BodyTeams
}

function Get-TeamsEnabled {
    return $script:teamsEnabled
}

function Update-TeamsFirstScanMessage {
    param(
        [string]$body
    )
    
    return $body.Replace("add_new_vuln", "First PingCastle scan ! 🎉`n`n")
}

function Update-TeamsStatusMessage {
    param(
        [string]$body,
        [string]$message
    )
    
    return $body.Replace("add_new_vuln", $message + "`n`n")
}

Export-ModuleMember -Function Initialize-TeamsConfig, Update-TeamsBody, Send-TeamsMessage, Format-TeamsMessage, Get-TeamsBody, Get-TeamsEnabled, Update-TeamsFirstScanMessage, Update-TeamsStatusMessage
