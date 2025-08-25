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
        $description = $body['embeds'][0]['description']
        if ($print_current_result) {
            $current_scan = "`n`---`n Detected anomalies: `n" + $current_scan
            $description = $description + $final_thread + $current_scan
        } else {
            $description = $description + $final_thread
        }

        if ($description.Length -gt 4599) {
            $description = $description.Substring(0, 4600) + "`n`n... (truncated)"
            Write-Host "[WARNING] Discord description truncated due to 2000 character limit" -ForegroundColor Yellow
        }
        
        # Update the description only once
        $body['embeds'][0]['description'] = $description
        
        # Convert Slack emojis to Discord-compatible format
        $bodyJson = $body | ConvertTo-Json -Depth 5   
        # Fix markdown formatting - Discord uses ** for bold, not *
        $bodyJson = $bodyJson.Replace("*", "**")
        
        # Convert emojis using Unicode escape sequences
        $bodyJson = $bodyJson.Replace(":red_circle:", [char]::ConvertFromUtf32(0x1F534))
        $bodyJson = $bodyJson.Replace(":large_orange_circle:", [char]::ConvertFromUtf32(0x1F7E0))
        $bodyJson = $bodyJson.Replace(":large_yellow_circle:", [char]::ConvertFromUtf32(0x1F7E1))
        $bodyJson = $bodyJson.Replace(":large_green_circle:", [char]::ConvertFromUtf32(0x1F7E2))
        $bodyJson = $bodyJson.Replace(":heavy_exclamation_mark:", [char]::ConvertFromUtf32(0x2757))
        $bodyJson = $bodyJson.Replace(":white_check_mark:", [char]::ConvertFromUtf32(0x2705))
        $bodyJson = $bodyJson.Replace(":arrow_forward:", [char]::ConvertFromUtf32(0x25B6))
        $bodyJson = $bodyJson.Replace(":tada:", [char]::ConvertFromUtf32(0x1F389))
        $bodyJson = $bodyJson.Replace(":rage:", [char]::ConvertFromUtf32(0x1F621))
        $bodyJson = $bodyJson.Replace(":smile:", [char]::ConvertFromUtf32(0x1F60A))

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
    
    $body['embeds'][0]['description'] = "First PingCastle scan ! " + [char]::ConvertFromUtf32(0x1F389)
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
