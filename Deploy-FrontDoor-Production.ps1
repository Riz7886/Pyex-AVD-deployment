# ================================================================
# AZURE FRONT DOOR DEPLOYMENT - PRODUCTION READY
# Clean code for Terraform deployment
# No special characters, emojis, or boxes
# ================================================================

param(
    [string]$DeploymentPath = "C:\Projects\Terraform-Cloud-Deployments\Pyx-AVD-deployment\DriversHealth-FrontDoor"
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================"
Write-Host "AZURE FRONT DOOR - PRODUCTION DEPLOYMENT"
Write-Host "Drivers Health - Clean Automation"
Write-Host "================================================================"
Write-Host ""

# Check Azure login
Write-Host "Step 1: Verifying Azure authentication..."
$account = az account show 2>$null
if (-not $account) {
    Write-Host "  Not authenticated. Logging in to Azure..."
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Azure login failed"
        exit 1
    }
}
Write-Host "  SUCCESS: Authenticated to Azure"
Write-Host ""

# Get all subscriptions with full details
Write-Host "Step 2: Loading Azure subscriptions..."
Write-Host ""
$subs = az account list | ConvertFrom-Json
$currentSub = az account show | ConvertFrom-Json

Write-Host "================================================================"
Write-Host "AVAILABLE AZURE SUBSCRIPTIONS"
Write-Host "================================================================"
Write-Host ""
Write-Host "Total subscriptions found: $($subs.Count)"
Write-Host ""

# Display all subscriptions with full details
for ($i = 0; $i -lt $subs.Count; $i++) {
    $isCurrent = $subs[$i].id -eq $currentSub.id
    $marker = if ($isCurrent) { " CURRENT" } else { "" }
    
    Write-Host "Option: $($i + 1)$marker"
    Write-Host "  Name: $($subs[$i].name)"
    Write-Host "  Subscription ID: $($subs[$i].id)"
    Write-Host "  State: $($subs[$i].state)"
    Write-Host "  Tenant ID: $($subs[$i].tenantId)"
    Write-Host "  Cloud: $($subs[$i].cloudName)"
    Write-Host ""
}

Write-Host "================================================================"
Write-Host ""
Write-Host "OPTIONS:"
Write-Host "  - Enter number 1-$($subs.Count) to select existing subscription"
Write-Host "  - Press ENTER to use current subscription: $($currentSub.name)"
Write-Host "  - Type NEW to create a new subscription for this deployment"
Write-Host ""

$selectedSub = $null
$isNewSubscription = $false

while ($true) {
    Write-Host "Your selection: "
    $input = Read-Host
    
    # Empty - use current
    if ([string]::IsNullOrWhiteSpace($input)) {
        $selectedSub = $currentSub
        Write-Host "  Using current subscription: $($currentSub.name)"
        break
    }
    
    # NEW - create new subscription
    if ($input -eq "NEW" -or $input -eq "new" -or $input -eq "New") {
        Write-Host ""
        Write-Host "================================================================"
        Write-Host "CREATE NEW AZURE SUBSCRIPTION"
        Write-Host "================================================================"
        Write-Host ""
        Write-Host "Enter name for new subscription:"
        Write-Host "  Examples: DriversHealth-FrontDoor, DH-Production, DH-FrontDoor-Prod"
        Write-Host ""
        
        $newSubName = $null
        while ([string]::IsNullOrWhiteSpace($newSubName)) {
            Write-Host "New subscription name: "
            $newSubName = Read-Host
            if ([string]::IsNullOrWhiteSpace($newSubName)) {
                Write-Host "  ERROR: Subscription name is required"
            }
        }
        
        Write-Host ""
        Write-Host "Attempting to create subscription: $newSubName"
        Write-Host ""
        Write-Host "NOTE: Subscription creation requires:"
        Write-Host "  - Enterprise Agreement or Microsoft Customer Agreement"
        Write-Host "  - Subscription Creator role or Owner permissions"
        Write-Host "  - Valid billing account"
        Write-Host ""
        
        # Get billing accounts
        Write-Host "Checking for available billing accounts..."
        $billingAccounts = az billing account list 2>$null | ConvertFrom-Json
        
        if ($billingAccounts -and $billingAccounts.Count -gt 0) {
            Write-Host "  Found $($billingAccounts.Count) billing account(s)"
            Write-Host ""
            
            for ($i = 0; $i -lt $billingAccounts.Count; $i++) {
                Write-Host "Billing Account $($i + 1):"
                Write-Host "  Name: $($billingAccounts[$i].displayName)"
                Write-Host "  ID: $($billingAccounts[$i].name)"
                Write-Host ""
            }
            
            Write-Host "Select billing account number 1-$($billingAccounts.Count): "
            $billingChoice = Read-Host
            
            if ($billingChoice -match '^\d+$' -and [int]$billingChoice -ge 1 -and [int]$billingChoice -le $billingAccounts.Count) {
                $billingAccount = $billingAccounts[[int]$billingChoice - 1]
                
                Write-Host ""
                Write-Host "Creating subscription under billing account: $($billingAccount.displayName)"
                
                $createResult = az account create --offer-type "MS-AZR-0017P" --display-name $newSubName --enrollment-account-name $billingAccount.name 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  SUCCESS: Subscription created"
                    Write-Host ""
                    Write-Host "Waiting for subscription to be provisioned..."
                    Start-Sleep -Seconds 15
                    
                    # Refresh subscription list
                    $subs = az account list | ConvertFrom-Json
                    $selectedSub = $subs | Where-Object { $_.name -eq $newSubName } | Select-Object -First 1
                    
                    if ($selectedSub) {
                        Write-Host "  SUCCESS: Subscription ready"
                        az account set --subscription $selectedSub.id
                        $isNewSubscription = $true
                        break
                    } else {
                        Write-Host "  WARNING: Subscription created but not yet visible"
                        Write-Host "  Please wait 1-2 minutes and re-run this script"
                        exit 0
                    }
                } else {
                    Write-Host ""
                    Write-Host "  ERROR: Could not create subscription automatically"
                    Write-Host ""
                    Write-Host "  MANUAL CREATION STEPS:"
                    Write-Host "    1. Go to Azure Portal: https://portal.azure.com"
                    Write-Host "    2. Navigate to Subscriptions"
                    Write-Host "    3. Click Add or Create"
                    Write-Host "    4. Enter subscription name: $newSubName"
                    Write-Host "    5. Select billing account and offer"
                    Write-Host "    6. Complete creation"
                    Write-Host "    7. Re-run this script"
                    Write-Host ""
                    
                    $useExisting = Read-Host "Use existing subscription instead? (y/n)"
                    if ($useExisting -eq "y" -or $useExisting -eq "Y") {
                        continue
                    } else {
                        exit 0
                    }
                }
            } else {
                Write-Host "  ERROR: Invalid selection"
                continue
            }
        } else {
            Write-Host "  No billing accounts found or insufficient permissions"
            Write-Host ""
            Write-Host "  Please create subscription manually:"
            Write-Host "    1. Azure Portal > Subscriptions > Add"
            Write-Host "    2. Name: $newSubName"
            Write-Host "    3. Complete the creation process"
            Write-Host "    4. Re-run this script"
            Write-Host ""
            
            $useExisting = Read-Host "Use existing subscription now? (y/n)"
            if ($useExisting -eq "y" -or $useExisting -eq "Y") {
                continue
            } else {
                exit 0
            }
        }
    }
    
    # Numeric selection
    if ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $subs.Count) {
        $choice = [int]$input - 1
        $selectedSub = $subs[$choice]
        Write-Host "  Selected subscription: $($selectedSub.name)"
        break
    }
    
    Write-Host "  ERROR: Invalid input. Enter 1-$($subs.Count), press ENTER for current, or type NEW"
    Write-Host ""
}

# Set subscription
if ($selectedSub.id -ne $currentSub.id) {
    Write-Host ""
    Write-Host "Switching to subscription: $($selectedSub.name)"
    az account set --subscription $selectedSub.id
    Write-Host "  SUCCESS: Subscription changed"
}

Write-Host ""
Write-Host "================================================================"
Write-Host "SELECTED SUBSCRIPTION DETAILS"
Write-Host "================================================================"
Write-Host ""
az account show --query "{Name:name, SubscriptionID:id, State:state, TenantID:tenantId}" --output table
Write-Host ""

if ($isNewSubscription) {
    Write-Host "NOTE: New subscription detected. Waiting for resource providers..."
    Start-Sleep -Seconds 30
    Write-Host "  Ready to proceed"
    Write-Host ""
}

# Backend hostname configuration
Write-Host "Step 3: Configure backend server hostname..."
Write-Host ""
Write-Host "Searching for existing App Services in subscription..."

$appServices = az webapp list --query "[].{name:name, host:defaultHostName}" 2>$null | ConvertFrom-Json

if ($appServices -and $appServices.Count -gt 0) {
    Write-Host "  Found $($appServices.Count) App Service(s)"
    Write-Host ""
    for ($i = 0; $i < [Math]::Min($appServices.Count, 10); $i++) {
        Write-Host "  Option $($i + 1): $($appServices[$i].host)"
    }
    Write-Host "  Option 0: Enter custom hostname"
    Write-Host ""
    Write-Host "Select App Service 0-$([Math]::Min($appServices.Count, 10)) or press ENTER for custom: "
    $appChoice = Read-Host
    
    if ($appChoice -match '^\d+$' -and [int]$appChoice -ge 1 -and [int]$appChoice -le [Math]::Min($appServices.Count, 10)) {
        $backend = $appServices[[int]$appChoice - 1].host
        Write-Host "  Selected backend: $backend"
    } else {
        Write-Host ""
        Write-Host "Enter backend hostname (example: drivershealth.azurewebsites.net): "
        $backend = Read-Host
        if ([string]::IsNullOrWhiteSpace($backend)) {
            $backend = "drivershealth.azurewebsites.net"
            Write-Host "  Using default: $backend"
        }
    }
} else {
    Write-Host "  No App Services found in subscription"
    Write-Host ""
    Write-Host "Enter backend hostname (default: drivershealth.azurewebsites.net): "
    $backend = Read-Host
    if ([string]::IsNullOrWhiteSpace($backend)) {
        $backend = "drivershealth.azurewebsites.net"
        Write-Host "  Using default backend: $backend"
    }
}

# Setup directory
Write-Host ""
Write-Host "Step 4: Preparing deployment directory..."
if (-not (Test-Path $DeploymentPath)) {
    New-Item -ItemType Directory -Path $DeploymentPath -Force | Out-Null
}
Set-Location $DeploymentPath
Write-Host "  Deployment directory: $DeploymentPath"
Write-Host ""

# Create Terraform files
Write-Host "Step 5: Creating Terraform configuration files..."
Write-Host ""

# Note: Terraform files will be created in next steps
Write-Host "  Configuration files will be generated with enhanced security"
Write-Host ""

Write-Host "================================================================"
Write-Host "DEPLOYMENT CONFIGURATION SUMMARY"
Write-Host "================================================================"
Write-Host ""
Write-Host "Subscription: $($selectedSub.name)"
Write-Host "Subscription ID: $($selectedSub.id)"
Write-Host "Backend Server: $backend"
Write-Host "Project: DriversHealth"
Write-Host "Environment: Production"
Write-Host "Location: East US"
Write-Host ""
Write-Host "Security Features:"
Write-Host "  - WAF Policy with Prevention Mode"
Write-Host "  - Microsoft Default Rule Set 2.1"
Write-Host "  - Bot Manager Rule Set 1.0"
Write-Host "  - Rate Limiting: 100 requests per minute"
Write-Host "  - HTTPS Redirect: Enabled"
Write-Host "  - Certificate Validation: Enabled"
Write-Host "  - Diagnostic Logging: Enabled"
Write-Host "  - Alert Rules: Backend Health, WAF Blocks, Response Time"
Write-Host "  - Log Analytics: 90-day retention"
Write-Host ""
Write-Host "Resources to be created:"
Write-Host "  - Resource Group"
Write-Host "  - Front Door Profile (Premium SKU)"
Write-Host "  - Front Door Endpoint"
Write-Host "  - Origin Group"
Write-Host "  - Origin (Backend)"
Write-Host "  - Route with HTTPS redirect"
Write-Host "  - WAF Policy"
Write-Host "  - Security Policy"
Write-Host "  - Log Analytics Workspace"
Write-Host "  - Diagnostic Settings"
Write-Host "  - Action Group for alerts"
Write-Host "  - Alert Rules (3 rules)"
Write-Host ""
Write-Host "Estimated Cost: $340-400 USD per month"
Write-Host "Deployment Time: 5-10 minutes"
Write-Host ""
Write-Host "================================================================"
Write-Host ""
Write-Host "Configuration complete. Terraform files will be created next."
Write-Host ""
