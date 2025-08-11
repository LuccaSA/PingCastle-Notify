# Teams Workflow Module for PingCastle-Notify
# When a Teams webhook request is received -> Post Message in a chat or channel -> Flow bot, channel, your team, you channel -> `@{triggerBody()?['pingcastle']}

function Initialize-Teams_WorkflowConfig {
    param(
        [hashtable]$envVars
    )
    
    $script:teamsWorkflowEnabled = if ($envVars["TEAMS_WORKFLOW_ENABLED"]) { [int]$envVars["TEAMS_WORKFLOW_ENABLED"] } else { 0 }
    $script:teamsWorkflowUri = if ($envVars["TEAMS_WORKFLOW_URI"]) { $envVars["TEAMS_WORKFLOW_URI"] } else { "https://prod-xx.westus.logic.azure.com:443/workflows/xxxxxxxxxxxxxxx/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=xxxxxxxxxxxxxxxxx" }
    
    $script:BodyTeamsWorkflow = @"
{ 'pingcastle': '`nDomain *domain_env* - date_scan - *Global Score abc* : 
- Score: *[cbd Trusts | def Stale Object | asx Privileged Group | dse Anomalies]*
- add_new_vuln'}
"@
}

function Update-Teams_WorkflowBody {
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

function Send-Teams_WorkflowMessage {
    param(
        [string]$body,
        [string]$final_thread = "",
        [string]$current_scan = "",
        [bool]$print_current_result = $true
    )
    
    if (-not $script:teamsWorkflowEnabled) {
        return $null
    }
    
    try {
        # Escape single quotes
        $current_scan = $current_scan.replace("'", "\'")
        $final_thread = $final_thread.replace("'", "\'")
        
        # Build final message content
        $messageContent = $body
        if ($print_current_result) {
            $current_scan = "`n`---`n Detected anomalies: `n" + $current_scan
            $messageContent = $messageContent.Replace("'}", $final_thread + $current_scan + "'}")
        } else {
            $messageContent = $messageContent.Replace("'}", $final_thread + "'}")
        }
        
        # Convert markdown and emojis for Teams
        $finalMessage = $messageContent.Replace("*","**").Replace("`n","`n`n")
        $finalMessage = $finalMessage.Replace(":red_circle:","&#128308;").Replace(":large_orange_circle:","&#128992;").Replace(":large_yellow_circle:","&#128993;").Replace(":large_green_circle:","&#128994;")
        $finalMessage = $finalMessage.Replace(":heavy_exclamation_mark:", "&#10071;").Replace(":white_check_mark:", "&#9989;").Replace(":arrow_forward:", "&#128312;")
        
        Write-Host "[+] Sending to Teams Workflow"

        $response = Invoke-WebRequest -Method Post -ContentType 'application/json' -Body $finalMessage -Uri $script:teamsWorkflowUri
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            Write-Host "[+] Teams Workflow message sent successfully" -ForegroundColor Green
        } else {
            Write-Error "Teams Workflow webhook returned unexpected response: $response"
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to send Teams Workflow message: $_"
        return $null
    }
}

function Update-Teams_WorkflowFirstScanMessage {
    param(
        [string]$body
    )
    
    return $body.Replace("add_new_vuln", "First PingCastle scan ! 🎉`n`n")
}

function Update-Teams_WorkflowStatusMessage {
    param(
        [string]$body,
        [string]$message
    )
    
    return $body.Replace("add_new_vuln", $message + "`n`n")
}

function Get-Teams_WorkflowBody {
    return $script:BodyTeamsWorkflow
}

function Get-Teams_WorkflowEnabled {
    return $script:teamsWorkflowEnabled
}

Export-ModuleMember -Function Initialize-Teams_WorkflowConfig, Update-Teams_WorkflowBody, Send-Teams_WorkflowMessage, Update-Teams_WorkflowFirstScanMessage, Update-Teams_WorkflowStatusMessage, Get-Teams_WorkflowBody, Get-Teams_WorkflowEnabled
