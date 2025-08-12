# Discord Module for PingCastle-Notify

function Initialize-DiscordConfig {
    param(
        [hashtable]$envVars
    )
    
    $script:discordEnabled = if ($envVars["DISCORD_ENABLED"]) { [int]$envVars["DISCORD_ENABLED"] } else { 0 }
    $script:discordWebhook = if ($envVars["DISCORD_WEBHOOK"]) { $envVars["DISCORD_WEBHOOK"] } else { "https://discord.com/api/webhooks/your-webhook-url" }
    
    $script:BodyDiscord = @{
        username = "PingCastle Bot"
        avatar_url = "https://example.com/pingcastle-icon.png"
        content = "Domain **domain_env** - date_scan - **Global Score abc** :"
        embeds = @(
            @{
                title = "PingCastle Scan Results"
                description = "add_new_vuln"
                color = 0
                fields = @(
                    @{ name = "Trusts"; value = "cbd"; inline = $true }
                    @{ name = "Stale Objects"; value = "def"; inline = $true }
                    @{ name = "Privileged Accounts"; value = "asx"; inline = $true }
                    @{ name = "Anomalies"; value = "dse"; inline = $true }
                )
            }
        )
    }
}

function Update-DiscordBody {
    param(
        [hashtable]$body,
        [string]$domainName,
        [datetime]$dateScan,
        [string]$str_total_point,
        [string]$str_trusts,
        [string]$str_staleObject,
        [string]$str_privilegeAccount,
        [string]$str_anomalies,
        [string]$anssiMaturityText = ""
    )
    
    $body['content'] = $body['content'].Replace("abc", $str_total_point).Replace("domain_env", $domainName).Replace("date_scan", $dateScan.ToString("dd/MM/yyyy"))
    $body['embeds'][0]['fields'][0]['value'] = $str_trusts
    $body['embeds'][0]['fields'][1]['value'] = $str_staleObject
    $body['embeds'][0]['fields'][2]['value'] = $str_privilegeAccount
    $body['embeds'][0]['fields'][3]['value'] = $str_anomalies
    
    return $body
}

function Send-DiscordMessage {
    param(
        [hashtable]$body,
        [string]$final_thread = "",
        [string]$current_scan = "",
        [bool]$print_current_result = $true
    )
    
    if (-not $script:discordEnabled) {
        return $null
    }
    
    try {
        # Add final_thread to description if available
        if ($final_thread) {
            $body['embeds'][0]['description'] = $body['embeds'][0]['description'] + "`n`n" + $final_thread
        }
        
        # Add current scan results if enabled
        if ($print_current_result -and $current_scan) {
            $body['embeds'][0]['description'] = $body['embeds'][0]['description'] + "`n`n**Detected anomalies:**`n" + $current_scan
        }
        
        # Convert Slack emojis to Discord-compatible format
        $bodyJson = $body | ConvertTo-Json -Depth 5   
        # Fix markdown formatting - Discord uses ** for bold, not *
        $bodyJson = $bodyJson.Replace("*", "**")
        
        # Convert emojis
        $bodyJson = $bodyJson.Replace(":red_circle:", "🔴").Replace(":large_orange_circle:", "🟠").Replace(":large_yellow_circle:", "🟡").Replace(":large_green_circle:", "🟢")
        $bodyJson = $bodyJson.Replace(":heavy_exclamation_mark:", "❗").Replace(":white_check_mark:", "✅").Replace(":arrow_forward:", "▶️").Replace(":tada:", "🎉").Replace(":rage:", "😡").Replace(":smile:", "😊")
        
        Write-Host "[+] Sending to Discord"
        $response = Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $bodyJson -Uri $script:discordWebhook
        
        # Discord webhooks return either empty response or message object when successful
        # If no exception was thrown, the message was sent successfully
        Write-Host "[+] Discord message sent successfully" -ForegroundColor Green
        
        return $response
    }
    catch {
        Write-Error "Failed to send Discord message: $_"
        return $null
    }
}

function Update-DiscordFirstScanMessage {
    param(
        [hashtable]$body
    )
    
    $body['embeds'][0]['description'] = "First PingCastle scan ! 🎉"
    return $body
}

function Update-DiscordStatusMessage {
    param(
        [hashtable]$body,
        [string]$message
    )
    
    $body['embeds'][0]['description'] = $message
    return $body
}

function Get-DiscordBody {
    return $script:BodyDiscord
}

function Get-DiscordEnabled {
    return $script:discordEnabled
}

Export-ModuleMember -Function Initialize-DiscordConfig, Update-DiscordBody, Send-DiscordMessage, Update-DiscordFirstScanMessage, Update-DiscordStatusMessage, Get-DiscordBody, Get-DiscordEnabled
