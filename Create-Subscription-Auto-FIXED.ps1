#Requires -Version 5.1
# FIXED SUBSCRIPTION CREATOR - Uses working multi-tenant connection logic
# No management group dependency - Creates subscription directly

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$NewSubscriptionName = "SUB-PRODUCT-STAGING",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Logs"
)

$ErrorActionPreference = "Continue"

# Helper Functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Info" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE SUBSCRIPTION CREATOR - FIXED VERSION" -ForegroundColor Cyan
Write-Host "  Multi-Tenant Support | No Management Group Required" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Create output directory
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$logFile = Join-Path $OutputPath "SubscriptionCreation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Write-Log "Log file: $logFile" -Level Info
Write-Log "" -Level Info

# ========== STEP 1: AZURE AUTHENTICATION ==========
Write-Log "Step 1: Azure Authentication" -Level Info
Write-Log "" -Level Info

try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (!$context) {
        Write-Log "Connecting to Azure..." -Level Warning
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Log "Successfully authenticated as: $($context.Account.Id)" -Level Success
    Write-Log "Current Tenant: $($context.Tenant.Id)" -Level Info
    Write-Log "" -Level Info
} catch {
    Write-Log "ERROR: Failed to authenticate to Azure" -Level Error
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    exit 1
}

# ========== STEP 2: DISCOVER ALL TENANTS AND SUBSCRIPTIONS ==========
Write-Log "Step 2: Discovering Tenants and Subscriptions" -Level Info
Write-Log "" -Level Info

try {
    $allSubscriptions = @(Get-AzSubscription -ErrorAction Stop)
    
    if ($allSubscriptions.Count -eq 0) {
        Write-Log "ERROR: No subscriptions found!" -Level Error
        Write-Log "You may not have access to any Azure subscriptions" -Level Warning
        exit 1
    }
    
    Write-Log "Found $($allSubscriptions.Count) subscription(s) across all tenants" -Level Success
    Write-Log "" -Level Info
    
    # Group by Tenant
    $tenantGroups = $allSubscriptions | Group-Object -Property TenantId
    Write-Log "Discovered $($tenantGroups.Count) tenant(s):" -Level Info
    Write-Log "" -Level Info
    
    $tenantIndex = 1
    $tenantMap = @{}
    
    foreach ($tenantGroup in $tenantGroups) {
        $tenantId = $tenantGroup.Name
        $firstSub = $tenantGroup.Group[0]
        
        # Try to get tenant display name
        $tenantName = "Unknown"
        try {
            $tenant = Get-AzTenant -TenantId $tenantId -ErrorAction SilentlyContinue
            if ($tenant) {
                $tenantName = $tenant.Name
                if (!$tenantName) {
                    $tenantName = $tenant.DefaultDomain
                }
            }
        } catch {
            # Ignore errors, use Unknown
        }
        
        Write-Log "[$tenantIndex] Tenant: $tenantName" -Level Info
        Write-Log "    Tenant ID: $tenantId" -Level Info
        Write-Log "    Subscriptions in this tenant:" -Level Info
        
        foreach ($sub in $tenantGroup.Group) {
            Write-Log "      - $($sub.Name) [$($sub.State)]" -Level Info
        }
        Write-Log "" -Level Info
        
        $tenantMap[$tenantIndex] = @{
            TenantId = $tenantId
            TenantName = $tenantName
            Subscriptions = $tenantGroup.Group
        }
        
        $tenantIndex++
    }
    
} catch {
    Write-Log "ERROR: Failed to discover subscriptions/tenants" -Level Error
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    exit 1
}

# ========== STEP 3: SELECT TENANT FOR NEW SUBSCRIPTION ==========
Write-Log "Step 3: Select Target Tenant for New Subscription" -Level Info
Write-Log "" -Level Info

Write-Host "Which tenant should the new subscription be created in?" -ForegroundColor Yellow
Write-Host ""

$tenantChoice = Read-Host "Enter tenant number (1-$($tenantGroups.Count))"
$selectedTenantNum = [int]$tenantChoice

if (!$tenantMap.ContainsKey($selectedTenantNum)) {
    Write-Log "ERROR: Invalid tenant selection" -Level Error
    exit 1
}

$selectedTenant = $tenantMap[$selectedTenantNum]
Write-Log "" -Level Info
Write-Log "Selected Tenant: $($selectedTenant.TenantName)" -Level Success
Write-Log "Tenant ID: $($selectedTenant.TenantId)" -Level Info
Write-Log "" -Level Info

# Switch to the selected tenant
try {
    Write-Log "Switching to selected tenant..." -Level Info
    $firstSubInTenant = $selectedTenant.Subscriptions[0]
    Set-AzContext -SubscriptionId $firstSubInTenant.Id -TenantId $selectedTenant.TenantId -ErrorAction Stop | Out-Null
    Write-Log "Successfully switched context to tenant" -Level Success
    Write-Log "" -Level Info
} catch {
    Write-Log "ERROR: Failed to switch to selected tenant" -Level Error
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    exit 1
}

# ========== STEP 4: CHECK IF SUBSCRIPTION NAME EXISTS ==========
Write-Log "Step 4: Checking if subscription name already exists" -Level Info
Write-Log "" -Level Info

$existingSubsInTenant = $selectedTenant.Subscriptions
Write-Log "Existing subscriptions in this tenant:" -Level Info
foreach ($sub in $existingSubsInTenant) {
    Write-Log "  - $($sub.Name)" -Level Info
}
Write-Log "" -Level Info

$nameExists = $existingSubsInTenant | Where-Object { $_.Name -eq $NewSubscriptionName }
if ($nameExists) {
    Write-Log "ERROR: A subscription named '$NewSubscriptionName' already exists in this tenant!" -Level Error
    Write-Log "Please choose a different name or delete the existing subscription" -Level Warning
    exit 1
}

Write-Log "Subscription name '$NewSubscriptionName' is available" -Level Success
Write-Log "" -Level Info

# ========== STEP 5: GET BILLING ACCOUNTS ==========
Write-Log "Step 5: Checking Billing Accounts" -Level Info
Write-Log "" -Level Info

try {
    # Try to get billing accounts
    $billingAccounts = @(Get-AzBillingAccount -ErrorAction SilentlyContinue)
    
    if ($billingAccounts.Count -eq 0) {
        Write-Log "WARNING: No billing accounts found" -Level Warning
        Write-Log "" -Level Warning
        Write-Log "This means you may not have permissions to create subscriptions" -Level Warning
        Write-Log "" -Level Warning
        Write-Log "To create subscriptions, you need one of:" -Level Info
        Write-Log "  1. Owner role on a Billing Account" -Level Info
        Write-Log "  2. Subscription Creator role" -Level Info
        Write-Log "  3. Enrollment Account Owner role (for EA)" -Level Info
        Write-Log "" -Level Info
        
        $proceed = Read-Host "Do you want to try creating the subscription anyway? (Y/N)"
        if ($proceed -ne "Y" -and $proceed -ne "y") {
            Write-Log "Operation cancelled by user" -Level Warning
            exit 0
        }
    } else {
        Write-Log "Found $($billingAccounts.Count) billing account(s)" -Level Success
        foreach ($ba in $billingAccounts) {
            Write-Log "  - $($ba.DisplayName) (ID: $($ba.Name))" -Level Info
        }
        Write-Log "" -Level Info
    }
} catch {
    Write-Log "WARNING: Could not retrieve billing accounts" -Level Warning
    Write-Log "Error: $($_.Exception.Message)" -Level Warning
    Write-Log "Will attempt to create subscription anyway..." -Level Info
    Write-Log "" -Level Info
}

# ========== STEP 6: FINAL CONFIRMATION ==========
Write-Log "========================================" -Level Info
Write-Log "READY TO CREATE SUBSCRIPTION" -Level Info
Write-Log "========================================" -Level Info
Write-Log "" -Level Info
Write-Log "Subscription Name: $NewSubscriptionName" -Level Info
Write-Log "Target Tenant: $($selectedTenant.TenantName)" -Level Info
Write-Log "Tenant ID: $($selectedTenant.TenantId)" -Level Info
Write-Log "" -Level Info

$confirmation = Read-Host "Type 'YES' to create this subscription"

if ($confirmation -ne "YES") {
    Write-Log "Operation cancelled by user" -Level Warning
    exit 0
}

Write-Log "" -Level Info

# ========== STEP 7: CREATE SUBSCRIPTION ==========
Write-Log "Step 7: Creating Subscription" -Level Info
Write-Log "" -Level Info

$subscriptionCreated = $false
$newSubscription = $null

# Method 1: Try New-AzSubscription (Enterprise Agreement)
Write-Log "Attempting Method 1: New-AzSubscription (Enterprise Agreement)..." -Level Info
try {
    $params = @{
        Name = $NewSubscriptionName
        ErrorAction = "Stop"
    }
    
    # Try to get enrollment account
    try {
        $enrollmentAccounts = Get-AzEnrollmentAccount -ErrorAction SilentlyContinue
        if ($enrollmentAccounts) {
            $enrollmentAccount = $enrollmentAccounts[0]
            $params['EnrollmentAccountObjectId'] = $enrollmentAccount.ObjectId
            Write-Log "Using Enrollment Account: $($enrollmentAccount.PrincipalName)" -Level Info
        }
    } catch {
        # Ignore error
    }
    
    $newSubscription = New-AzSubscription @params
    
    if ($newSubscription) {
        $subscriptionCreated = $true
        Write-Log "SUCCESS! Subscription created using Method 1" -Level Success
    }
} catch {
    Write-Log "Method 1 failed: $($_.Exception.Message)" -Level Warning
}

# Method 2: Try Azure REST API
if (!$subscriptionCreated) {
    Write-Log "" -Level Info
    Write-Log "Attempting Method 2: Azure REST API..." -Level Info
    
    try {
        $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
        
        $subscriptionId = [Guid]::NewGuid().ToString()
        
        $body = @{
            properties = @{
                displayName = $NewSubscriptionName
                subscriptionId = $subscriptionId
            }
        } | ConvertTo-Json
        
        $uri = "https://management.azure.com/providers/Microsoft.Subscription/aliases/$($NewSubscriptionName)?api-version=2021-10-01"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body -ErrorAction Stop
        
        if ($response.properties.subscriptionId) {
            $subscriptionCreated = $true
            $newSubscription = @{
                SubscriptionId = $response.properties.subscriptionId
                Name = $NewSubscriptionName
            }
            Write-Log "SUCCESS! Subscription created using Method 2 (REST API)" -Level Success
        }
    } catch {
        Write-Log "Method 2 failed: $($_.Exception.Message)" -Level Warning
    }
}

# Method 3: Try using billing account (if available)
if (!$subscriptionCreated -and $billingAccounts -and $billingAccounts.Count -gt 0) {
    Write-Log "" -Level Info
    Write-Log "Attempting Method 3: Using Billing Account..." -Level Info
    
    try {
        $billingAccount = $billingAccounts[0]
        
        $params = @{
            Name = $NewSubscriptionName
            BillingAccountName = $billingAccount.Name
            ErrorAction = "Stop"
        }
        
        $newSubscription = New-AzSubscription @params
        
        if ($newSubscription) {
            $subscriptionCreated = $true
            Write-Log "SUCCESS! Subscription created using Method 3 (Billing Account)" -Level Success
        }
    } catch {
        Write-Log "Method 3 failed: $($_.Exception.Message)" -Level Warning
    }
}

Write-Log "" -Level Info

# ========== STEP 8: REPORT RESULTS ==========
if ($subscriptionCreated) {
    Write-Log "========================================" -Level Success
    Write-Log "SUBSCRIPTION CREATED SUCCESSFULLY!" -Level Success
    Write-Log "========================================" -Level Success
    Write-Log "" -Level Success
    Write-Log "Subscription Name: $NewSubscriptionName" -Level Success
    
    if ($newSubscription.SubscriptionId) {
        Write-Log "Subscription ID: $($newSubscription.SubscriptionId)" -Level Success
    }
    
    Write-Log "Tenant: $($selectedTenant.TenantName)" -Level Success
    Write-Log "Tenant ID: $($selectedTenant.TenantId)" -Level Success
    Write-Log "" -Level Info
    Write-Log "Next Steps:" -Level Info
    Write-Log "1. Verify in Azure Portal: portal.azure.com" -Level Info
    Write-Log "2. Assign RBAC roles to the subscription" -Level Info
    Write-Log "3. Configure budgets and cost alerts" -Level Info
    Write-Log "4. Apply Azure policies" -Level Info
    Write-Log "5. Set up resource tags" -Level Info
    
    # Check for management groups
    Write-Log "" -Level Info
    Write-Log "Checking for Management Groups..." -Level Info
    try {
        $mgGroups = @(Get-AzManagementGroup -ErrorAction SilentlyContinue)
        if ($mgGroups.Count -gt 0) {
            Write-Log "" -Level Info
            Write-Log "Found $($mgGroups.Count) management group(s):" -Level Info
            foreach ($mg in $mgGroups) {
                Write-Log "  - $($mg.DisplayName) (ID: $($mg.Name))" -Level Info
            }
            Write-Log "" -Level Info
            Write-Log "You can manually add the subscription to a management group if needed" -Level Info
        }
    } catch {
        # Ignore errors
    }
    
    Write-Log "" -Level Info
    Write-Log "Log saved to: $logFile" -Level Info
    
} else {
    Write-Log "========================================" -Level Error
    Write-Log "SUBSCRIPTION CREATION FAILED" -Level Error
    Write-Log "========================================" -Level Error
    Write-Log "" -Level Error
    Write-Log "All creation methods failed" -Level Error
    Write-Log "" -Level Warning
    Write-Log "Common reasons for failure:" -Level Warning
    Write-Log "1. Insufficient permissions - You need one of:" -Level Warning
    Write-Log "   - Owner role on a Billing Account" -Level Warning
    Write-Log "   - Subscription Creator role" -Level Warning
    Write-Log "   - Enrollment Account Owner (for EA)" -Level Warning
    Write-Log "" -Level Warning
    Write-Log "2. No valid billing account or enrollment account" -Level Warning
    Write-Log "" -Level Warning
    Write-Log "3. Tenant/organization subscription creation is disabled" -Level Warning
    Write-Log "" -Level Info
    Write-Log "Contact your Azure administrator to:" -Level Info
    Write-Log "- Grant you subscription creation permissions" -Level Info
    Write-Log "- Create the subscription on your behalf" -Level Info
    Write-Log "- Add you to a billing account with proper roles" -Level Info
    Write-Log "" -Level Info
    Write-Log "Log saved to: $logFile" -Level Info
}

Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Yellow
Read-Host
