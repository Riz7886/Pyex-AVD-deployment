# ================================================================
# AZURE FRONT DOOR - COMPLETE AUTOMATED DEPLOYMENT
# Production-ready deployment with Git synchronization
# No special characters, emojis, or boxes
# ================================================================

param(
    [string]$ProjectRoot = "C:\Projects\Terraform-Cloud-Deployments",
    [string]$DeploymentFolder = "Pyx-AVD-deployment\DriversHealth-FrontDoor"
)

$ErrorActionPreference = "Stop"
$DeploymentPath = Join-Path $ProjectRoot $DeploymentFolder

Write-Host "================================================================"
Write-Host "AZURE FRONT DOOR - PRODUCTION DEPLOYMENT AUTOMATION"
Write-Host "Drivers Health - Complete Deployment Suite"
Write-Host "================================================================"
Write-Host ""
Write-Host "Deployment Path: $DeploymentPath"
Write-Host ""

# STEP 1: Azure Authentication
Write-Host "================================================================"
Write-Host "STEP 1: Azure Authentication"
Write-Host "================================================================"
Write-Host ""
Write-Host "Checking Azure CLI authentication..."

$account = az account show 2>$null
if (-not $account) {
    Write-Host "Not authenticated. Initiating Azure login..."
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Azure login failed"
        exit 1
    }
}
Write-Host "SUCCESS: Authenticated to Azure"
Write-Host ""

# STEP 2: Load All Subscriptions
Write-Host "================================================================"
Write-Host "STEP 2: Azure Subscription Management"
Write-Host "================================================================"
Write-Host ""
Write-Host "Loading all Azure subscriptions..."

$subs = az account list | ConvertFrom-Json
$currentSub = az account show | ConvertFrom-Json

Write-Host ""
Write-Host "================================================================"
Write-Host "AVAILABLE AZURE SUBSCRIPTIONS"
Write-Host "================================================================"
Write-Host ""
Write-Host "Total Subscriptions Found: $($subs.Count)"
Write-Host ""

# Display all subscriptions with complete details
for ($i = 0; $i -lt $subs.Count; $i++) {
    $isCurrent = $subs[$i].id -eq $currentSub.id
    $marker = if ($isCurrent) { " CURRENTLY ACTIVE" } else { "" }
    
    Write-Host "SUBSCRIPTION $($i + 1)$marker"
    Write-Host "  Display Name: $($subs[$i].name)"
    Write-Host "  Subscription ID: $($subs[$i].id)"
    Write-Host "  State: $($subs[$i].state)"
    Write-Host "  Tenant ID: $($subs[$i].tenantId)"
    Write-Host "  Cloud Environment: $($subs[$i].cloudName)"
    Write-Host "  Home Tenant: $($subs[$i].homeTenantId)"
    Write-Host ""
}

Write-Host "================================================================"
Write-Host ""
Write-Host "SUBSCRIPTION SELECTION OPTIONS:"
Write-Host "  1. Enter number 1 through $($subs.Count) to select existing subscription"
Write-Host "  2. Press ENTER to use currently active subscription"
Write-Host "  3. Type NEW to create a new subscription for this deployment"
Write-Host ""

$selectedSub = $null
$isNewSubscription = $false

while ($true) {
    Write-Host "Enter your selection: "
    $input = Read-Host
    
    # Option 1: Empty input - use current subscription
    if ([string]::IsNullOrWhiteSpace($input)) {
        $selectedSub = $currentSub
        Write-Host ""
        Write-Host "Selected current subscription: $($currentSub.name)"
        Write-Host "Subscription ID: $($currentSub.id)"
        break
    }
    
    # Option 2: NEW - create new subscription
    if ($input -eq "NEW" -or $input -eq "new" -or $input -eq "New") {
        Write-Host ""
        Write-Host "================================================================"
        Write-Host "NEW SUBSCRIPTION CREATION"
        Write-Host "================================================================"
        Write-Host ""
        Write-Host "You are creating a new Azure subscription"
        Write-Host ""
        Write-Host "Requirements:"
        Write-Host "  - Enterprise Agreement OR Microsoft Customer Agreement"
        Write-Host "  - Subscription Creator role"
        Write-Host "  - Valid billing account access"
        Write-Host ""
        Write-Host "Enter name for new subscription:"
        Write-Host "  Suggested names:"
        Write-Host "    - DriversHealth-FrontDoor"
        Write-Host "    - DH-Production-FrontDoor"
        Write-Host "    - DriversHealth-CDN-Production"
        Write-Host ""
        
        $newSubName = $null
        while ([string]::IsNullOrWhiteSpace($newSubName)) {
            Write-Host "New subscription name: "
            $newSubName = Read-Host
            if ([string]::IsNullOrWhiteSpace($newSubName)) {
                Write-Host "  ERROR: Subscription name cannot be empty"
                Write-Host ""
            }
        }
        
        Write-Host ""
        Write-Host "Subscription name: $newSubName"
        Write-Host ""
        Write-Host "Checking for available billing accounts..."
        
        $billingAccounts = az billing account list 2>$null | ConvertFrom-Json
        
        if ($billingAccounts -and $billingAccounts.Count -gt 0) {
            Write-Host "Found $($billingAccounts.Count) billing account(s)"
            Write-Host ""
            
            for ($i = 0; $i -lt $billingAccounts.Count; $i++) {
                Write-Host "BILLING ACCOUNT $($i + 1)"
                Write-Host "  Display Name: $($billingAccounts[$i].displayName)"
                Write-Host "  Account ID: $($billingAccounts[$i].name)"
                Write-Host "  Type: $($billingAccounts[$i].accountType)"
                Write-Host ""
            }
            
            Write-Host "Select billing account (1-$($billingAccounts.Count)): "
            $billingChoice = Read-Host
            
            if ($billingChoice -match '^\d+$' -and [int]$billingChoice -ge 1 -and [int]$billingChoice -le $billingAccounts.Count) {
                $billingAccount = $billingAccounts[[int]$billingChoice - 1]
                
                Write-Host ""
                Write-Host "Creating subscription..."
                Write-Host "  Name: $newSubName"
                Write-Host "  Billing Account: $($billingAccount.displayName)"
                Write-Host ""
                
                $createResult = az account create --offer-type "MS-AZR-0017P" --display-name $newSubName --enrollment-account-name $billingAccount.name 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "SUCCESS: Subscription created"
                    Write-Host ""
                    Write-Host "Waiting for Azure to provision subscription..."
                    Start-Sleep -Seconds 20
                    
                    # Refresh subscription list
                    $subs = az account list | ConvertFrom-Json
                    $selectedSub = $subs | Where-Object { $_.name -eq $newSubName } | Select-Object -First 1
                    
                    if ($selectedSub) {
                        Write-Host "SUCCESS: Subscription is ready"
                        Write-Host "  Name: $($selectedSub.name)"
                        Write-Host "  ID: $($selectedSub.id)"
                        az account set --subscription $selectedSub.id
                        $isNewSubscription = $true
                        break
                    } else {
                        Write-Host "WARNING: Subscription created but not yet visible in account list"
                        Write-Host "Please wait 2-3 minutes and re-run this script"
                        exit 0
                    }
                } else {
                    Write-Host ""
                    Write-Host "ERROR: Automatic subscription creation failed"
                    Write-Host ""
                    Write-Host "MANUAL CREATION STEPS:"
                    Write-Host "  1. Open Azure Portal: https://portal.azure.com"
                    Write-Host "  2. Navigate to Subscriptions section"
                    Write-Host "  3. Click Add or Create Subscription"
                    Write-Host "  4. Enter subscription name: $newSubName"
                    Write-Host "  5. Select billing account and offer type"
                    Write-Host "  6. Complete subscription creation"
                    Write-Host "  7. Re-run this deployment script"
                    Write-Host ""
                    
                    $useExisting = Read-Host "Use existing subscription instead? (yes/no)"
                    if ($useExisting -eq "yes" -or $useExisting -eq "y") {
                        continue
                    } else {
                        Write-Host "Exiting. Please create subscription and re-run script."
                        exit 0
                    }
                }
            } else {
                Write-Host "ERROR: Invalid billing account selection"
                continue
            }
        } else {
            Write-Host "No billing accounts found or insufficient permissions"
            Write-Host ""
            Write-Host "MANUAL SUBSCRIPTION CREATION:"
            Write-Host "  1. Contact your Azure EA administrator"
            Write-Host "  2. Request new subscription: $newSubName"
            Write-Host "  3. Purpose: Front Door CDN deployment for Drivers Health"
            Write-Host "  4. After creation, re-run this script"
            Write-Host ""
            
            $useExisting = Read-Host "Use existing subscription now? (yes/no)"
            if ($useExisting -eq "yes" -or $useExisting -eq "y") {
                continue
            } else {
                Write-Host "Exiting. Create subscription and re-run script."
                exit 0
            }
        }
    }
    
    # Option 3: Numeric selection
    if ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $subs.Count) {
        $choice = [int]$input - 1
        $selectedSub = $subs[$choice]
        Write-Host ""
        Write-Host "Selected subscription: $($selectedSub.name)"
        Write-Host "Subscription ID: $($selectedSub.id)"
        break
    }
    
    Write-Host ""
    Write-Host "ERROR: Invalid selection"
    Write-Host "Enter a number from 1 to $($subs.Count), press ENTER, or type NEW"
    Write-Host ""
}

# Set active subscription
if ($selectedSub.id -ne $currentSub.id) {
    Write-Host ""
    Write-Host "Switching to selected subscription..."
    az account set --subscription $selectedSub.id
    Write-Host "SUCCESS: Subscription changed"
}

Write-Host ""
Write-Host "================================================================"
Write-Host "ACTIVE SUBSCRIPTION DETAILS"
Write-Host "================================================================"
Write-Host ""
az account show --query "{DisplayName:name, SubscriptionID:id, State:state, TenantID:tenantId, CloudEnvironment:environmentName}" --output table
Write-Host ""

if ($isNewSubscription) {
    Write-Host "NOTE: New subscription detected"
    Write-Host "Waiting for Azure resource providers to register..."
    Start-Sleep -Seconds 30
    Write-Host "Ready to proceed"
    Write-Host ""
}

# STEP 3: Backend Configuration
Write-Host "================================================================"
Write-Host "STEP 3: Backend Server Configuration"
Write-Host "================================================================"
Write-Host ""
Write-Host "Searching for existing App Services in subscription..."

$appServices = az webapp list --query "[].{name:name, host:defaultHostName, state:state}" 2>$null | ConvertFrom-Json

$backend = $null

if ($appServices -and $appServices.Count -gt 0) {
    Write-Host "Found $($appServices.Count) App Service(s) in subscription"
    Write-Host ""
    
    $displayCount = [Math]::Min($appServices.Count, 15)
    for ($i = 0; $i -lt $displayCount; $i++) {
        Write-Host "  Option $($i + 1): $($appServices[$i].host) - State: $($appServices[$i].state)"
    }
    
    if ($appServices.Count -gt 15) {
        Write-Host "  ... and $($appServices.Count - 15) more"
    }
    
    Write-Host "  Option 0: Enter custom backend hostname"
    Write-Host ""
    Write-Host "Select App Service (0-$displayCount) or press ENTER for custom: "
    $appChoice = Read-Host
    
    if ($appChoice -match '^\d+$' -and [int]$appChoice -ge 1 -and [int]$appChoice -le $displayCount) {
        $backend = $appServices[[int]$appChoice - 1].host
        Write-Host "Selected backend: $backend"
    } else {
        Write-Host ""
        Write-Host "Enter backend hostname:"
        Write-Host "  Examples:"
        Write-Host "    - drivershealth.azurewebsites.net"
        Write-Host "    - dh-api-prod.azurewebsites.net"
        Write-Host "    - app.drivershealth.com"
        Write-Host ""
        Write-Host "Backend hostname (default: drivershealth.azurewebsites.net): "
        $backend = Read-Host
        if ([string]::IsNullOrWhiteSpace($backend)) {
            $backend = "drivershealth.azurewebsites.net"
            Write-Host "Using default: $backend"
        }
    }
} else {
    Write-Host "No App Services found in subscription"
    Write-Host ""
    Write-Host "Enter backend hostname (default: drivershealth.azurewebsites.net): "
    $backend = Read-Host
    if ([string]::IsNullOrWhiteSpace($backend)) {
        $backend = "drivershealth.azurewebsites.net"
        Write-Host "Using default: $backend"
    }
}

# STEP 4: Alert Email Configuration
Write-Host ""
Write-Host "================================================================"
Write-Host "STEP 4: Alert Email Configuration"
Write-Host "================================================================"
Write-Host ""
Write-Host "Enter email address for security and monitoring alerts:"
Write-Host "  (default: devops@drivershealth.com)"
Write-Host ""
Write-Host "Alert email: "
$alertEmail = Read-Host
if ([string]::IsNullOrWhiteSpace($alertEmail)) {
    $alertEmail = "devops@drivershealth.com"
    Write-Host "Using default: $alertEmail"
}

# STEP 5: Create Deployment Directory
Write-Host ""
Write-Host "================================================================"
Write-Host "STEP 5: Deployment Directory Setup"
Write-Host "================================================================"
Write-Host ""

if (-not (Test-Path $DeploymentPath)) {
    Write-Host "Creating deployment directory: $DeploymentPath"
    New-Item -ItemType Directory -Path $DeploymentPath -Force | Out-Null
    Write-Host "SUCCESS: Directory created"
} else {
    Write-Host "Deployment directory exists: $DeploymentPath"
}

Set-Location $DeploymentPath
Write-Host "Working directory: $DeploymentPath"
Write-Host ""

# STEP 6: Create Terraform Files
Write-Host "================================================================"
Write-Host "STEP 6: Creating Terraform Configuration Files"
Write-Host "================================================================"
Write-Host ""

Write-Host "Creating main.tf..."
# Main.tf content will be created from the file we already have
$mainTfPath = Join-Path $DeploymentPath "main.tf"
Copy-Item "/home/claude/main.tf" $mainTfPath -Force
Write-Host "SUCCESS: main.tf created"

Write-Host "Creating variables.tf..."
$variablesTfPath = Join-Path $DeploymentPath "variables.tf"
Copy-Item "/home/claude/variables.tf" $variablesTfPath -Force
Write-Host "SUCCESS: variables.tf created"

Write-Host "Creating outputs.tf..."
$outputsTfPath = Join-Path $DeploymentPath "outputs.tf"
Copy-Item "/home/claude/outputs.tf" $outputsTfPath -Force
Write-Host "SUCCESS: outputs.tf created"

Write-Host "Creating terraform.tfvars..."
$tfvarsContent = @"
# Azure Front Door Configuration - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Subscription: $($selectedSub.name)
# Subscription ID: $($selectedSub.id)

project_name        = "DriversHealth"
environment         = "prod"
location            = "East US"
backend_host_name   = "$backend"
health_probe_path   = "/"
alert_email_address = "$alertEmail"

tags = {
  ManagedBy   = "Terraform"
  Deployment  = "Automated"
  CreatedDate = "$(Get-Date -Format 'yyyy-MM-dd')"
}
"@
$tfvarsContent | Out-File -FilePath "terraform.tfvars" -Encoding UTF8 -Force
Write-Host "SUCCESS: terraform.tfvars created"

Write-Host "Creating .gitignore..."
$gitignoreContent = @"
# Terraform files
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
!terraform.tfvars.example
.terraformrc
terraform.rc
*.backup
backup_*/

# OS files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# Logs
*.log
"@
$gitignoreContent | Out-File -FilePath ".gitignore" -Encoding UTF8 -Force
Write-Host "SUCCESS: .gitignore created"

Write-Host ""
Write-Host "All Terraform files created successfully"
Write-Host ""

# STEP 7: Terraform Initialization
Write-Host "================================================================"
Write-Host "STEP 7: Terraform Initialization"
Write-Host "================================================================"
Write-Host ""

Write-Host "Initializing Terraform..."
terraform init -upgrade

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Terraform initialization failed"
    Write-Host "Please check Terraform installation and try again"
    exit 1
}

Write-Host "SUCCESS: Terraform initialized"
Write-Host ""

# STEP 8: Terraform Validation
Write-Host "================================================================"
Write-Host "STEP 8: Configuration Validation"
Write-Host "================================================================"
Write-Host ""

Write-Host "Validating Terraform configuration..."
terraform validate

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Configuration validation failed"
    Write-Host "Please review the errors above"
    exit 1
}

Write-Host "SUCCESS: Configuration is valid"
Write-Host ""

# STEP 9: Deployment Plan
Write-Host "================================================================"
Write-Host "STEP 9: Deployment Plan Preview"
Write-Host "================================================================"
Write-Host ""

Write-Host "Generating deployment plan..."
Write-Host ""
terraform plan

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Plan generation failed"
    exit 1
}

# STEP 10: Deployment Summary
Write-Host ""
Write-Host "================================================================"
Write-Host "DEPLOYMENT CONFIGURATION SUMMARY"
Write-Host "================================================================"
Write-Host ""
Write-Host "Subscription Details:"
Write-Host "  Name: $($selectedSub.name)"
Write-Host "  ID: $($selectedSub.id)"
Write-Host "  Tenant: $($selectedSub.tenantId)"
if ($isNewSubscription) {
    Write-Host "  Status: NEWLY CREATED"
}
Write-Host ""
Write-Host "Deployment Configuration:"
Write-Host "  Project: DriversHealth"
Write-Host "  Environment: Production"
Write-Host "  Location: East US"
Write-Host "  Backend Server: $backend"
Write-Host "  Alert Email: $alertEmail"
Write-Host ""
Write-Host "Resources to Deploy:"
Write-Host "  1. Resource Group"
Write-Host "  2. Front Door Profile (Premium SKU)"
Write-Host "  3. Front Door Endpoint"
Write-Host "  4. Origin Group"
Write-Host "  5. Origin (Backend Connection)"
Write-Host "  6. Route (HTTPS Redirect Enabled)"
Write-Host "  7. WAF Policy (Prevention Mode)"
Write-Host "  8. Security Policy"
Write-Host "  9. Log Analytics Workspace (90-day retention)"
Write-Host "  10. Diagnostic Settings (Front Door)"
Write-Host "  11. Diagnostic Settings (WAF)"
Write-Host "  12. Action Group (Alerts)"
Write-Host "  13. Metric Alert (Backend Health)"
Write-Host "  14. Metric Alert (WAF Blocks)"
Write-Host "  15. Metric Alert (Response Time)"
Write-Host "  16. Metric Alert (Error Rate)"
Write-Host ""
Write-Host "Security Features:"
Write-Host "  - WAF Policy: Prevention Mode"
Write-Host "  - Microsoft Default Rule Set 2.1 (OWASP Top 10)"
Write-Host "  - Bot Manager Rule Set 1.0"
Write-Host "  - Rate Limiting: 100 requests per minute"
Write-Host "  - SQL Injection Protection"
Write-Host "  - Suspicious User Agent Blocking"
Write-Host "  - HTTPS Redirect: Enforced"
Write-Host "  - Certificate Validation: Enabled"
Write-Host "  - Ports: 80 (HTTP) and 443 (HTTPS)"
Write-Host "  - Diagnostic Logging: Full"
Write-Host ""
Write-Host "Monitoring and Alerts:"
Write-Host "  - Backend Health Monitoring"
Write-Host "  - WAF Block Detection"
Write-Host "  - Response Time Tracking"
Write-Host "  - Error Rate Monitoring"
Write-Host "  - Email Notifications: $alertEmail"
Write-Host ""
Write-Host "Estimated Monthly Cost: $340-400 USD"
Write-Host "Deployment Time: 5-10 minutes"
Write-Host ""
Write-Host "================================================================"
Write-Host ""

# STEP 11: Deploy
Write-Host "Press ENTER to start deployment or CTRL+C to cancel..."
Read-Host

Write-Host ""
Write-Host "================================================================"
Write-Host "DEPLOYING TO AZURE"
Write-Host "================================================================"
Write-Host ""
Write-Host "Deployment started: $(Get-Date -Format 'HH:mm:ss')"
Write-Host "Please wait..."
Write-Host ""

$startTime = Get-Date
terraform apply -auto-approve

if ($LASTEXITCODE -eq 0) {
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "DEPLOYMENT SUCCESSFUL"
    Write-Host "================================================================"
    Write-Host ""
    Write-Host "Deployment completed: $(Get-Date -Format 'HH:mm:ss')"
    Write-Host "Total duration: $($duration.Minutes) minutes $($duration.Seconds) seconds"
    Write-Host ""
    
    # Display outputs
    $fdUrl = terraform output -raw frontdoor_url 2>$null
    
    if ($fdUrl) {
        Write-Host "================================================================"
        Write-Host "FRONT DOOR DEPLOYMENT COMPLETE"
        Write-Host "================================================================"
        Write-Host ""
        Write-Host "Front Door URL: $fdUrl"
        Write-Host "Subscription: $($selectedSub.name)"
        Write-Host "Resource Group: rg-DriversHealth-prod"
        Write-Host "Backend: $backend"
        Write-Host "Alert Email: $alertEmail"
        Write-Host ""
        Write-Host "Azure Portal: https://portal.azure.com"
        Write-Host ""
        Write-Host "================================================================"
        Write-Host "NEXT STEPS"
        Write-Host "================================================================"
        Write-Host ""
        Write-Host "1. Test Front Door URL:"
        Write-Host "   $fdUrl"
        Write-Host ""
        Write-Host "2. Verify backend health:"
        Write-Host "   Portal > Front Door > fdh-prod > Origins"
        Write-Host ""
        Write-Host "3. Monitor WAF protection:"
        Write-Host "   Portal > Front Door > fdh-prod > Security"
        Write-Host ""
        Write-Host "4. Review logs:"
        Write-Host "   Portal > Log Analytics > law-fdh-prod"
        Write-Host ""
        Write-Host "5. Configure DNS CNAME (when ready):"
        Write-Host "   Point your domain to: $(($fdUrl -replace 'https://', ''))"
        Write-Host ""
        Write-Host "================================================================"
        Write-Host ""
    }
    
    # STEP 12: Git Sync
    Write-Host "================================================================"
    Write-Host "STEP 12: Git Synchronization"
    Write-Host "================================================================"
    Write-Host ""
    
    $gitRoot = $ProjectRoot
    if (Test-Path (Join-Path $gitRoot ".git")) {
        Write-Host "Git repository detected"
        Write-Host ""
        Write-Host "Do you want to commit and push changes to Git? (yes/no): "
        $gitSync = Read-Host
        
        if ($gitSync -eq "yes" -or $gitSync -eq "y") {
            Push-Location $gitRoot
            
            Write-Host ""
            Write-Host "Staging changes..."
            git add "$DeploymentFolder/*"
            
            Write-Host "Committing changes..."
            $commitMsg = "Deploy Front Door for DriversHealth - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            git commit -m "$commitMsg"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Changes committed"
                Write-Host ""
                Write-Host "Push to remote? (yes/no): "
                $doPush = Read-Host
                
                if ($doPush -eq "yes" -or $doPush -eq "y") {
                    Write-Host "Pushing to remote..."
                    git push
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "SUCCESS: Changes pushed to remote repository"
                    } else {
                        Write-Host "WARNING: Push failed. Push manually when ready."
                    }
                }
            } else {
                Write-Host "No changes to commit or commit failed"
            }
            
            Pop-Location
        } else {
            Write-Host "Skipping Git synchronization"
            Write-Host "To sync manually later:"
            Write-Host "  git add $DeploymentFolder"
            Write-Host "  git commit -m 'Deploy Front Door'"
            Write-Host "  git push"
        }
    } else {
        Write-Host "No Git repository found at $gitRoot"
        Write-Host "To initialize Git:"
        Write-Host "  cd $gitRoot"
        Write-Host "  git init"
        Write-Host "  git add ."
        Write-Host "  git commit -m 'Initial commit'"
    }
    
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "DEPLOYMENT COMPLETE"
    Write-Host "================================================================"
    Write-Host ""
    
} else {
    Write-Host ""
    Write-Host "================================================================"
    Write-Host "DEPLOYMENT FAILED"
    Write-Host "================================================================"
    Write-Host ""
    Write-Host "Common Issues and Solutions:"
    Write-Host ""
    Write-Host "1. Backend server unreachable:"
    Write-Host "   - Verify backend hostname is correct"
    Write-Host "   - Check backend is accessible via HTTPS"
    Write-Host "   - Ensure firewall allows Azure Front Door IP ranges"
    Write-Host ""
    Write-Host "2. Insufficient permissions:"
    Write-Host "   - Verify Contributor role on subscription"
    Write-Host "   - Check resource provider registrations"
    Write-Host ""
    Write-Host "3. Resource quota limits:"
    Write-Host "   - Front Door quota may be exhausted"
    Write-Host "   - Contact Azure support for quota increase"
    Write-Host ""
    Write-Host "4. Network connectivity:"
    Write-Host "   - Check internet connection"
    Write-Host "   - Verify Azure service availability"
    Write-Host ""
    Write-Host "To retry deployment:"
    Write-Host "  terraform apply"
    Write-Host ""
    Write-Host "To clean up failed deployment:"
    Write-Host "  terraform destroy"
    Write-Host ""
    exit 1
}

Write-Host "Press ENTER to exit..."
Read-Host
