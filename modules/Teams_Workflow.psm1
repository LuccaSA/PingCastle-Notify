# Teams Workflow Module for PingCastle-Notify
# When a Teams webhook request is received (Who can trigger: Anyone) -> Post Message in a chat or channel -> Flow bot, channel, your team, your channel -> expression triggerBody()?['pingcastle']

function Initialize-Teams_WorkflowConfig {
    param(
        [hashtable]$envVars
    )
    
    $script:teamsWorkflowEnabled = if ($envVars["TEAMS_WORKFLOW_ENABLED"]) { [int]$envVars["TEAMS_WORKFLOW_ENABLED"] } else { 0 }
    $script:teamsWorkflowUri = if ($envVars["TEAMS_WORKFLOW_URI"]) { $envVars["TEAMS_WORKFLOW_URI"] } else { "https://xxxxxxxx.xx.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/xxxxxxxxxxxxxxx/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=xxxxxxxxxxxxxxxxx" }
    
    $script:BodyTeamsWorkflow = @"
{ 'pingcastle': '`nDomain *domain_env* - date_scan - *Global Score abc* anssi_maturity : 
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
        [string]$str_anomalies,
        [string]$anssiMaturityText = ""
    )
    
    return $body.Replace("abc", $str_total_point).Replace("cbd", $str_trusts).Replace("def", $str_staleObject).Replace("asx", $str_privilegeAccount).Replace("dse", $str_anomalies).Replace("domain_env", $domainName).Replace("date_scan", $dateScan.ToString("dd/MM/yyyy")).Replace("anssi_maturity", $anssiMaturityText)
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
    
    $json = $null
    try {
        # Build final message content (no manual quote escaping - ConvertTo-Json handles it)
        $messageContent = $body
        if ($print_current_result -and -not [string]::IsNullOrWhiteSpace($current_scan)) {
            $current_scan = "`n`---`n Detected anomalies: `n" + $current_scan
            $messageContent = $messageContent.Replace("'}", $final_thread + $current_scan + "'}")
        } else {
            $messageContent = $messageContent.Replace("'}", $final_thread + "'}")
        }
        
        # Unwrap the template's pseudo-JSON wrapper { 'pingcastle': '...'} to get the plain text
        if ($messageContent -match "(?s)^\s*\{\s*'pingcastle'\s*:\s*'(.*)'\s*\}\s*$") {
            $text = $Matches[1]
        } else {
            $text = $messageContent
        }
        
        # Replace leftover placeholder on diff runs
        $text = $text.Replace("add_new_vuln", "Changes since last scan:`n")
        
        # Convert markdown and emojis for Teams
        $text = $text.Replace("*","**").Replace("`n","`n`n")
        $text = $text.Replace(":red_circle:","&#128308;").Replace(":large_orange_circle:","&#128992;").Replace(":large_yellow_circle:","&#128993;").Replace(":large_green_circle:","&#128994;")
        $text = $text.Replace(":heavy_exclamation_mark:", "&#10071;").Replace(":white_check_mark:", "&#9989;").Replace(":arrow_forward:", "&#128312;")
        $text = $text.Replace(":smile:", "&#128522;`n").Replace(":tada:", "&#127881;`n").Replace(":rage:", "&#128548;`n")
        
        # Proper JSON serialization + explicit UTF-8 bytes (PS 5.1 otherwise sends ISO-8859-1)
        $json  = @{ pingcastle = $text } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        
        Write-Host "[+] Sending to Teams Workflow ($($bytes.Length) bytes)"

        $response = Invoke-WebRequest -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -Uri $script:teamsWorkflowUri -UseBasicParsing
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            Write-Host "[+] Teams Workflow message sent successfully" -ForegroundColor Green
        } else {
            Write-Error "Teams Workflow webhook returned unexpected response: $($response.StatusCode) $($response.Content)"
        }
        
        return $response
    }
    catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        if ($json) {
            $dumpPath = Join-Path $PSScriptRoot "teams_workflow_failed_payload.json"
            [System.IO.File]::WriteAllText($dumpPath, $json, (New-Object System.Text.UTF8Encoding $false))
            $detail += "`nPayload saved to: $dumpPath"
        }
        Write-Error "Failed to send Teams Workflow message: $_`n$detail"
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
