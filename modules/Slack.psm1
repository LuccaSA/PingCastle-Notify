# Slack Module for PingCastle-Notify

function Initialize-SlackConfig {
    param(
        [hashtable]$envVars
    )
    
    $script:slackChannel = if ($envVars["SLACK_CHANNEL"]) { $envVars["SLACK_CHANNEL"] } else { "#pingcastle-scan" }
    $script:slackToken = if ($envVars["SLACK_TOKEN"]) { $envVars["SLACK_TOKEN"] } else { "xoxb-xxxxx-xxxxx-xxxxx-xxxxx" }
    $script:slackEnabled = if ($envVars["SLACK_ENABLED"]) { [int]$envVars["SLACK_ENABLED"] } else { 1 }
    
    $script:headers = @{
        Authorization = "Bearer $script:slackToken"
    }
    
    $script:BodySlack = @{
        channel = $script:slackChannel;
        attachments = @(
            @{
                "mrkdwn_in" = @("text")
                "color" = ""
                "text" = ""
                "fields" = @(
                    @{
                        "value" = ""
                        "short" = "True"
                    },
                    @{
                        "value" = ""
                        "short" = "True"
                    },
                    @{
                        "value" = ""
                        "short" = "True"
                    },
                    @{
                        "value" = ""
                        "short" = "True"
                    },
                    @{
                        "value" = ""
                        "short" = $False
                    }
                )
                "footer" = "<https://github.com/LuccaSA/PingCastle-Notify|Pingcastle-Notify> v1.2"
                "footer_icon" = "https://github.githubassets.com/assets/GitHub-Mark-ea2971cee799.png"
            }
        );
        icon_emoji = ":ghost:";
        username = "PingCastle Automatic run";
    }
}

function Update-SlackColor {
    param(
        [hashtable]$body,
        [int]$point
    )
    
    if ($point -ge 75) {
        $body['attachments'][0]['color'] = "#f12828"
    } elseIf ($point -ge 50 -and $point -lt 75) {
        $body['attachments'][0]['color'] = "#ff6a00"
    } elseIf ($point -ge 25 -and $point -lt 50) {
        $body['attachments'][0]['color'] = "#ffd800"
    } elseIf ($point -ge 0 -and $point -lt 25) {
        $body['attachments'][0]['color'] = "#83e043"
    } else {
        $body['attachments'][0]['color'] = "#83e043"
    }
    return $body
}

function Update-SlackBody {
    param(
        [hashtable]$body,
        [string]$domainName,
        [datetime]$dateScan,
        [int]$total_point,
        [string]$str_trusts,
        [string]$str_staleObject,
        [string]$str_privilegeAccount,
        [string]$str_anomalies
    )
    
    $body['attachments'][0]['text'] = "Domain *" + $domainName + "* - " + $dateScan.ToString("dd/MM/yyyy") + " - *Global Score " + [string]$total_point + "* : "
    $body['attachments'][0]['fields'][0]['value'] = $str_trusts.Split(" ")[1].Trim() + " Trusts: " + $str_trusts.Split(" ")[0].Trim()
    $body['attachments'][0]['fields'][1]['value'] = $str_staleObject.Split(" ")[1].Trim() + " Stale Object: " + $str_staleObject.Split(" ")[0].Trim()
    $body['attachments'][0]['fields'][2]['value'] = $str_privilegeAccount.Split(" ")[1].Trim() + " Privileged Group: " + $str_privilegeAccount.Split(" ")[0].Trim()
    $body['attachments'][0]['fields'][3]['value'] = $str_anomalies.Split(" ")[1].Trim() + " Anomalies: " + $str_anomalies.Split(" ")[0].Trim()
    
    return $body
}

function Send-SlackMessage {
    param(
        [hashtable]$body
    )
    
    if (-not $script:slackEnabled) {
        return $null
    }
    
    try {
        $BodySlackJson = $body | ConvertTo-Json -Depth 5
        Write-Host "[+] Sending to slack"
        $response = Invoke-RestMethod -Uri https://slack.com/api/chat.postMessage -Headers $script:headers -Body $BodySlackJson -Method Post -ContentType 'application/json'
        
        if ($response.ok -eq $true) {
            Write-Host "[+] Slack message sent successfully" -ForegroundColor Green
        } else {
            Write-Error "Slack API returned error: $($response.error)"
        }
        
        return $response
    }
    catch {
        Write-Error "Failed to send Slack message: $_"
        return $null
    }
}

function Send-SlackThread {
    param(
        [string]$channel,
        [string]$thread_ts,
        [string]$text
    )
    
    if (-not $script:slackEnabled -or -not $text) {
        return $null
    }
    
    $threadBody = @{
        channel = $channel;
        thread_ts = $thread_ts
        text = $text;
        icon_emoji = ":ghost:"
        username = "PingCastle Automatic run"
    }
    
    return Send-SlackMessage -body $threadBody
}

function Get-SlackBody {
    return $script:BodySlack
}

function Get-SlackEnabled {
    return $script:slackEnabled
}

function Update-SlackFirstScanMessage {
    param(
        [hashtable]$body
    )
    
    $body['attachments'][0]['fields'][4]['value'] = "First PingCastle scan ! :tada:"
    return $body
}

function Update-SlackStatusMessage {
    param(
        [hashtable]$body,
        [string]$message
    )
    
    $body['attachments'][0]['fields'][4]['value'] = $message
    return $body
}

Export-ModuleMember -Function Initialize-SlackConfig, Update-SlackColor, Update-SlackBody, Send-SlackMessage, Send-SlackThread, Get-SlackBody, Get-SlackEnabled, Update-SlackFirstScanMessage, Update-SlackStatusMessage
