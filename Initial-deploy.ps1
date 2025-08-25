<#
    .SYNOPSIS
    Initial deployment script for PingCastle-Notify
    
    .DESCRIPTION
    This script helps with the initial setup of PingCastle-Notify by:
    - Creating .env file from template
    - Configuring domain settings
    - Selecting notification connectors
    - Downloading PingCastle
    - Creating necessary directories
    
    .AUTHOR
    Martial Puygrenier - @mpgn_x64
    
    .VERSION
    1.0
#>

param(
    [switch]$help
)

$ErrorActionPreference = 'Stop'

# Handle help parameter
if ($help) {
    Write-Host @"
PingCastle-Notify Initial Deployment Script

SYNOPSIS
    Initial setup script for PingCastle-Notify environment.

DESCRIPTION
    This script automates the initial deployment process including:
    - Creating .env configuration file from template
    - Domain configuration with auto-detection
    - Connector selection (Slack, Teams, Discord)
    - PingCastle download and extraction
    - Directory structure creation

SYNTAX
    .\initial-deploy.ps1

PARAMETERS
    -help
        Display this help message and exit.

REQUIREMENTS
    - PowerShell 5.1 or higher
    - Internet connection for PingCastle download
    - .env.example file in the same directory

For more information, visit: https://github.com/mpgn/PingCastle-Notify
"@ -ForegroundColor Green
    exit 0
}

# ASCII Art Banner
Write-Host @"

##################################################
#                                                #
#           PINGCASTLE NOTIFY SETUP              #
#           Initial Deployment Script            #
#                                                #
##################################################

"@ -ForegroundColor Cyan

Write-Host "[+] Starting PingCastle-Notify initial deployment..." -ForegroundColor Green
Write-Host ""

# Function to create .env from .env.example
Function New-EnvFile {
    param(
        [string]$ExamplePath = ".env.example",
        [string]$EnvPath = ".env"
    )
    
    if (-not (Test-Path $ExamplePath)) {
        Write-Error "Template file $ExamplePath not found. Please ensure .env.example exists in the current directory."
        return $false
    }
    
    if (Test-Path $EnvPath) {
        $overwrite = Read-Host ".env file already exists. Overwrite? (y/N)"
        if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
            Write-Host "[-] Keeping existing .env file" -ForegroundColor Yellow
            return $true
        }
    }
    
    try {
        Copy-Item $ExamplePath $EnvPath
        Write-Host "[+] Created .env file from template" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to create .env file: $_"
        return $false
    }
}

# Function to update .env file
Function Update-EnvFile {
    param(
        [string]$FilePath = ".env",
        [hashtable]$Updates
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error ".env file not found"
        return $false
    }
    
    try {
        $content = Get-Content $FilePath
        $newContent = @()
        
        foreach ($line in $content) {
            $updated = $false
            foreach ($key in $Updates.Keys) {
                if ($line -match "^$key=") {
                    $newContent += "$key=$($Updates[$key])"
                    $updated = $true
                    break
                }
            }
            if (-not $updated) {
                $newContent += $line
            }
        }
        
        $newContent | Set-Content $FilePath
        Write-Host "[+] Updated .env file with new configuration" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to update .env file: $_"
        return $false
    }
}

# Function to get domain configuration
Function Get-DomainConfiguration {
    Write-Host ""
    Write-Host "=== Domain Configuration ===" -ForegroundColor Cyan
    
    # Try to detect current domain
    $defaultDomain = ""
    try {
        if ($env:USERDNSDOMAIN) {
            $defaultDomain = ($env:USERDNSDOMAIN).ToLower()
            Write-Host "[+] Detected domain: $defaultDomain" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[-] Could not auto-detect domain" -ForegroundColor Yellow
    }
    
    if ($defaultDomain) {
        $domain = Read-Host "Enter your Active Directory domain [$defaultDomain]"
        if ([string]::IsNullOrWhiteSpace($domain)) {
            $domain = $defaultDomain
        }
    }
    else {
        $domain = Read-Host "Enter your Active Directory domain (e.g., contoso.local)"
        while ([string]::IsNullOrWhiteSpace($domain)) {
            Write-Host "[-] Domain cannot be empty" -ForegroundColor Red
            $domain = Read-Host "Enter your Active Directory domain (e.g., contoso.local)"
        }
    }
    
    Write-Host "[+] Domain configured: $domain" -ForegroundColor Green
    return $domain.ToLower()
}

# Function to get connector selection
Function Get-ConnectorConfiguration {
    Write-Host ""
    Write-Host "=== Connector Configuration ===" -ForegroundColor Cyan
    Write-Host "Available connectors:"
    Write-Host "  1. Slack"
    Write-Host "  2. Microsoft Teams"
    Write-Host "  3. Microsoft Teams (Workflow)"
    Write-Host "  4. Discord"
    Write-Host ""
    
    $connectors = @{
        "SLACK_ENABLED" = "0"
        "TEAMS_ENABLED" = "0"
        "TEAMS_WORKFLOW_ENABLED" = "0"
        "DISCORD_ENABLED" = "0"
    }
    
    $selection = Read-Host "Enter connector numbers separated by commas (e.g., 1,3,4)"
    
    if ([string]::IsNullOrWhiteSpace($selection)) {
        Write-Host "[-] No connectors selected. You can configure them later in the .env file" -ForegroundColor Yellow
        return $connectors
    }
    
    $selectedNumbers = $selection -split ',' | ForEach-Object { $_.Trim() }
    
    foreach ($num in $selectedNumbers) {
        switch ($num) {
            "1" { 
                $connectors["SLACK_ENABLED"] = "1"
                Write-Host "[+] Enabled Slack connector" -ForegroundColor Green
            }
            "2" { 
                $connectors["TEAMS_ENABLED"] = "1"
                Write-Host "[+] Enabled Microsoft Teams connector" -ForegroundColor Green
            }
            "3" { 
                $connectors["TEAMS_WORKFLOW_ENABLED"] = "1"
                Write-Host "[+] Enabled Microsoft Teams Workflow connector" -ForegroundColor Green
            }
            "4" { 
                $connectors["DISCORD_ENABLED"] = "1"
                Write-Host "[+] Enabled Discord connector" -ForegroundColor Green
            }
            default {
                Write-Host "[-] Invalid selection: $num" -ForegroundColor Red
            }
        }
    }
    
    return $connectors
}

# Function to download and extract PingCastle
Function Install-PingCastle {
    Write-Host ""
    Write-Host "=== PingCastle Installation ===" -ForegroundColor Cyan
    
    $githubApiUrl = "https://api.github.com/repos/vletoux/pingcastle/releases/latest"
    $downloadPath = Join-Path $PWD "PingCastle.zip"
    $extractPath = Join-Path $PWD "PingCastle"
    
    # Check if PingCastle already exists
    if (Test-Path $extractPath) {
        $overwrite = Read-Host "PingCastle directory already exists. Overwrite? (y/N)"
        if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
            Write-Host "[-] Keeping existing PingCastle installation" -ForegroundColor Yellow
            return $true
        }
        Remove-Item $extractPath -Recurse -Force
    }
    
    try {
        Write-Host "[+] Fetching latest PingCastle release information..." -ForegroundColor Yellow
        
        # Enable TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Get latest release info from GitHub API
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PingCastle-Notify-Setup")
        $releaseJson = $webClient.DownloadString($githubApiUrl)
        $releaseData = $releaseJson | ConvertFrom-Json
        
        # Find the zip file asset
        $zipAsset = $releaseData.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        
        if (-not $zipAsset) {
            Write-Error "No zip file found in the latest PingCastle release"
            return $false
        }
        
        $pingCastleUrl = $zipAsset.browser_download_url
        $actualFileName = $zipAsset.name
        
        Write-Host "[+] Found latest release: $($releaseData.tag_name)" -ForegroundColor Green
        Write-Host "[+] Download file: $actualFileName" -ForegroundColor Green
        Write-Host "[+] Downloading PingCastle from GitHub..." -ForegroundColor Yellow
        
        # Download the actual zip file
        $webClient.DownloadFile($pingCastleUrl, $downloadPath)
        
        Write-Host "[+] Downloaded PingCastle successfully" -ForegroundColor Green
        
        Write-Host "[+] Extracting PingCastle..." -ForegroundColor Yellow
        
        # Extract directly to PingCastle directory
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $extractPath)
        
        Write-Host "[+] Extracted PingCastle successfully" -ForegroundColor Green
        
        # Find and verify PingCastle.exe (might be in a subdirectory)
        $pingCastleExe = Get-ChildItem -Path $extractPath -Name "PingCastle.exe" -Recurse | Select-Object -First 1
        if ($pingCastleExe) {
            Write-Host "[+] Verified PingCastle.exe found at: $pingCastleExe" -ForegroundColor Green
        } else {
            Write-Warning "PingCastle.exe not found in extracted files. Please verify the installation."
        }
        
        # Clean up zip file after successful extraction
        if (Test-Path $downloadPath) {
            Remove-Item $downloadPath -Force
            Write-Host "[+] Cleaned up downloaded zip file" -ForegroundColor Green
        }
        
        # Create Reports folder inside the extracted PingCastle directory
        # If PingCastle.exe is in a subdirectory, create Reports there too
        if ($pingCastleExe) {
            $pingCastleDir = Split-Path (Join-Path $extractPath $pingCastleExe) -Parent
            $reportsPath = Join-Path $pingCastleDir "Reports"
        } else {
            # Fallback to root of extraction if exe not found
            $reportsPath = Join-Path $extractPath "Reports"
        }
        
        if (-not (Test-Path $reportsPath)) {
            New-Item -Path $reportsPath -ItemType Directory | Out-Null
            Write-Host "[+] Created Reports directory at: $reportsPath" -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        Write-Host "[-] Error during PingCastle installation: $_" -ForegroundColor Red
        
        # Clean up on failure (check if files exist first)
        if (Test-Path $downloadPath) {
            try {
                Remove-Item $downloadPath -Force
                Write-Host "[-] Cleaned up downloaded zip file after error" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Could not clean up download file: $_"
            }
        }
        if (Test-Path $extractPath) {
            try {
                Remove-Item $extractPath -Recurse -Force
                Write-Host "[-] Cleaned up extracted files after error" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Could not clean up extracted files: $_"
            }
        }
        
        return $false
    }
}

# Function to display final instructions
Function Show-FinalInstructions {
    param(
        [hashtable]$EnabledConnectors
    )
    
    Write-Host ""
    Write-Host "=== Final Configuration Steps ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: You need to configure tokens/webhooks in the .env file:" -ForegroundColor Yellow
    Write-Host ""
    
    $hasEnabledConnectors = $false
    
    if ($EnabledConnectors["SLACK_ENABLED"] -eq "1") {
        $hasEnabledConnectors = $true
        Write-Host "  • SLACK: Set SLACK_TOKEN with your Slack Bot token" -ForegroundColor White
        Write-Host "    - Create a Slack App at https://api.slack.com/apps" -ForegroundColor Gray
        Write-Host "    - Add Bot Token Scopes: chat:write, channels:read" -ForegroundColor Gray
        Write-Host "    - Install app to workspace and copy Bot User OAuth Token" -ForegroundColor Gray
        Write-Host ""
    }
    
    if ($EnabledConnectors["TEAMS_ENABLED"] -eq "1") {
        $hasEnabledConnectors = $true
        Write-Host "  • TEAMS: Set TEAMS_WEBHOOK_URL with your Teams webhook URL" -ForegroundColor White
        Write-Host "    - Go to your Teams channel → Connectors → Incoming Webhook" -ForegroundColor Gray
        Write-Host "    - Configure and copy the webhook URL" -ForegroundColor Gray
        Write-Host ""
    }
    
    if ($EnabledConnectors["TEAMS_WORKFLOW_ENABLED"] -eq "1") {
        $hasEnabledConnectors = $true
        Write-Host "  • TEAMS WORKFLOW: Set TEAMS_WORKFLOW_URL with your Power Automate workflow URL" -ForegroundColor White
        Write-Host "    - Create a Power Automate workflow with HTTP trigger" -ForegroundColor Gray
        Write-Host "    - Copy the HTTP POST URL" -ForegroundColor Gray
        Write-Host ""
    }
    
    if ($EnabledConnectors["DISCORD_ENABLED"] -eq "1") {
        $hasEnabledConnectors = $true
        Write-Host "  • DISCORD: Set DISCORD_WEBHOOK_URL with your Discord webhook URL" -ForegroundColor White
        Write-Host "    - Go to your Discord server → Server Settings → Integrations → Webhooks" -ForegroundColor Gray
        Write-Host "    - Create New Webhook and copy the webhook URL" -ForegroundColor Gray
        Write-Host ""
    }
    
    if (-not $hasEnabledConnectors) {
        Write-Host "  • No connectors were enabled during setup" -ForegroundColor Yellow
        Write-Host "  • Edit .env file to enable and configure connectors as needed" -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Host "Additional configuration options in .env:" -ForegroundColor Cyan
    Write-Host "  • PRINT_CURRENT_RESULT: Set to 1 to include all flagged rules in notifications" -ForegroundColor White
    Write-Host "  • ANSSI_LVL: Set to 1 to enable ANSSI compliance level reporting" -ForegroundColor White
    Write-Host "  • NOTIFY_WHEN_NO_CHANGES: Set to 1 to enable a report even if nothing change between two scan" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Next steps:" -ForegroundColor Green
    Write-Host "  1. Edit .env file with your tokens/webhooks" -ForegroundColor White
    Write-Host "  2. Run: .\PingCastle-Notify.ps1" -ForegroundColor White
    Write-Host "  3. Use -help for more options" -ForegroundColor White
}

# Main execution
try {
    # Step 1: Create .env file
    Write-Host "[1/4] Creating configuration file..." -ForegroundColor Magenta
    if (-not (New-EnvFile)) {
        exit 1
    }
    
    # Step 2: Configure domain
    Write-Host "[2/4] Configuring domain settings..." -ForegroundColor Magenta
    $domain = Get-DomainConfiguration
    
    # Step 3: Configure connectors
    Write-Host "[3/4] Configuring notification connectors..." -ForegroundColor Magenta
    $connectors = Get-ConnectorConfiguration
    
    # Update .env with domain and connector settings
    $envUpdates = @{
        "DOMAIN" = $domain
    }
    $envUpdates += $connectors
    
    if (-not (Update-EnvFile -Updates $envUpdates)) {
        exit 1
    }
    
    # Step 4: Download and install PingCastle
    Write-Host "[4/4] Installing PingCastle..." -ForegroundColor Magenta
    if (-not (Install-PingCastle)) {
        exit 1
    }
    
    # Show final instructions
    Show-FinalInstructions -EnabledConnectors $connectors
    
    Write-Host ""
    Write-Host "##################################################" -ForegroundColor Cyan
    Write-Host "#                                                #" -ForegroundColor Cyan
    Write-Host "#         DEPLOYMENT COMPLETED SUCCESSFULLY      #" -ForegroundColor Cyan
    Write-Host "#                                                #" -ForegroundColor Cyan
    Write-Host "##################################################" -ForegroundColor Cyan
    Write-Host ""
    
}
catch {
    Write-Host ""
    Write-Host "##################################################" -ForegroundColor Red
    Write-Host "#                                                #" -ForegroundColor Red
    Write-Host "#            DEPLOYMENT FAILED                   #" -ForegroundColor Red
    Write-Host "#                                                #" -ForegroundColor Red
    Write-Host "##################################################" -ForegroundColor Red
    Write-Host ""
    Write-Error "Deployment failed: $_"
    exit 1
}
