#Requires -Version 5.1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Azure Subscription Creator - PYX Tenant" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Continue"
$LogFile = "C:\Scripts\SubscriptionCreation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor White }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
    }
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

Write-Log "Target Tenant: PYX Application Tenant (supportpyxhealth.onmicrosoft.com)" -Level Info
Write-Log "Creating subscription under PRODUCT management group" -Level Info
Write-Log ""

Write-Log "Step 1: Connecting to Azure..." -Level Info
try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $context) {
        Connect-AzAccount -ErrorAction Stop | Out-Null
        $context = Get-AzContext
    }
    Write-Log "Connected to Tenant: $($context.Tenant.Id)" -Level Success
    Write-Log "Account: $($context.Account.Id)" -Level Success
    Write-Log ""
} catch {
    Write-Log "Failed to connect: $($_.Exception.Message)" -Level Error
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Log "Step 2: Finding PRODUCT management group..." -Level Info
$productMG = $null
$allMGs = Get-AzManagementGroup -ErrorAction SilentlyContinue

if ($allMGs) {
    Write-Log "Searching through $($allMGs.Count) management groups..." -Level Info
    foreach ($mg in $allMGs) {
        Write-Log "  Checking: $($mg.DisplayName) (ID: $($mg.Name))" -Level Info
        if ($mg.DisplayName -like "*PRODUCT*" -or $mg.Name -like "*PRODUCT*" -or $mg.Name -eq "PRODUCT" -or $mg.DisplayName -eq "PRODUCT") {
            $productMG = $mg
            Write-Log "FOUND PRODUCT Management Group!" -Level Success
            Write-Log "  Display Name: $($mg.DisplayName)" -Level Success
            Write-Log "  ID/Name: $($mg.Name)" -Level Success
            break
        }
    }
}

if ($null -eq $productMG) {
    Write-Log "Could not find PRODUCT management group!" -Level Error
    Write-Log "Available management groups:" -Level Warning
    foreach ($mg in $allMGs) {
        Write-Log "  - $($mg.DisplayName) (ID: $($mg.Name))" -Level Info
    }
    Write-Log ""
    Write-Log "Please check Azure Portal: Resource Manager > Management Groups" -Level Warning
    Read-Host "Press Enter to exit"
    exit 1
}

$mgId = $productMG.Name
Write-Log ""

Write-Log "Step 3: Getting existing subscriptions under PRODUCT..." -Level Info
try {
    $subs = Get-AzManagementGroupSubscription -GroupName $mgId -ErrorAction SilentlyContinue
    if ($null -eq $subs -or $subs.Count -eq 0) {
        Write-Log "No existing subscriptions found under PRODUCT" -Level Warning
    } else {
        Write-Log "Found $($subs.Count) existing subscription(s) under PRODUCT:" -Level Success
        $index = 1
        foreach ($sub in $subs) {
            $subDetails = Get-AzSubscription -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
            if ($subDetails) {
                Write-Log "  [$index] $($subDetails.Name)" -Level Info
                if ($subDetails.Name -like "*preprod*" -or $subDetails.Name -like "*prod*") {
                    Write-Log "      (Matches expected: sub-product-preprod or sub-product-prod)" -Level Success
                }
                $index++
            }
        }
        Write-Log "New subscription will be #$($subs.Count + 1)" -Level Info
    }
    Write-Log ""
} catch {
    Write-Log "Could not retrieve subscriptions under PRODUCT" -Level Warning
    Write-Log ""
}

Write-Log "Step 4: Checking if SUB-PRODUCT-STAGING already exists..." -Level Info
$allSubs = Get-AzSubscription -ErrorAction SilentlyContinue
$existing = $allSubs | Where-Object { $_.Name -eq "SUB-PRODUCT-STAGING" }
if ($existing) {
    Write-Log "Subscription SUB-PRODUCT-STAGING already exists!" -Level Error
    Write-Log "Subscription ID: $($existing.Id)" -Level Info
    Write-Log "State: $($existing.State)" -Level Info
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Log "Subscription name SUB-PRODUCT-STAGING is available!" -Level Success
Write-Log ""

Write-Log "============================================" -Level Info
Write-Log "READY TO CREATE SUBSCRIPTION" -Level Info
Write-Log "============================================" -Level Info
Write-Log "Subscription Name: SUB-PRODUCT-STAGING" -Level Info
Write-Log "Management Group: $($productMG.DisplayName)" -Level Info
Write-Log "Management Group ID: $mgId" -Level Info
Write-Log "Tenant: PYX Application Tenant" -Level Info
Write-Log ""

$confirm = Read-Host "Type YES to proceed with creation"
if ($confirm -ne "YES") {
    Write-Log "Creation cancelled by user" -Level Warning
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Log ""
Write-Log "Step 5: Creating subscription SUB-PRODUCT-STAGING..." -Level Info
Write-Log "This may take 1-2 minutes..." -Level Warning
Write-Log ""

$ErrorActionPreference = "Stop"

try {
    Write-Log "Attempting Method 1: New-AzSubscription..." -Level Info
    $params = @{
        Name = "SUB-PRODUCT-STAGING"
        OfferType = 'MS-AZR-0017P'
        ErrorAction = 'Stop'
    }
    
    $newSub = New-AzSubscription @params
    
    if ($newSub) {
        Write-Log "Subscription created successfully!" -Level Success
        Write-Log "Subscription ID: $($newSub.SubscriptionId)" -Level Success
        Write-Log ""
        Write-Log "Waiting 15 seconds for provisioning..." -Level Info
        Start-Sleep -Seconds 15
        
        Write-Log "Adding subscription to PRODUCT management group..." -Level Info
        try {
            New-AzManagementGroupSubscription -GroupName $mgId -SubscriptionId $newSub.SubscriptionId -ErrorAction Stop
            Write-Log "Added to PRODUCT management group successfully!" -Level Success
        } catch {
            Write-Log "Attempting alternative method to add to management group..." -Level Warning
            try {
                $uri = "https://management.azure.com/providers/Microsoft.Management/managementGroups/$mgId/subscriptions/$($newSub.SubscriptionId)?api-version=2020-05-01"
                $token = (Get-AzAccessToken).Token
                $headers = @{ 'Authorization' = "Bearer $token"; 'Content-Type' = 'application/json' }
                Invoke-RestMethod -Uri $uri -Method Put -Headers $headers
                Write-Log "Added to PRODUCT management group via REST API!" -Level Success
            } catch {
                Write-Log "Could not add to management group automatically" -Level Warning
                Write-Log "Please add manually: Azure Portal > Management Groups > PRODUCT > Add Subscription" -Level Warning
            }
        }
        
        Write-Log ""
        Write-Log "============================================" -Level Success
        Write-Log "SUBSCRIPTION CREATED SUCCESSFULLY!" -Level Success
        Write-Log "============================================" -Level Success
        Write-Log ""
        Write-Log "Subscription Name: SUB-PRODUCT-STAGING" -Level Success
        Write-Log "Subscription ID: $($newSub.SubscriptionId)" -Level Success
        Write-Log "Management Group: PRODUCT" -Level Success
        Write-Log "Log File: $LogFile" -Level Info
        Write-Log ""
        Write-Log "Verify in Azure Portal:" -Level Info
        Write-Log "Resource Manager > Management Groups > PRODUCT > Subscriptions" -Level Info
        Write-Log ""
        Write-Log "Next Steps:" -Level Info
        Write-Log "1. Configure RBAC roles" -Level Info
        Write-Log "2. Set up budgets and cost alerts" -Level Info
        Write-Log "3. Apply Azure policies" -Level Info
        Write-Log "4. Configure resource tags" -Level Info
        Write-Log ""
    }
} catch {
    Write-Log ""
    Write-Log "============================================" -Level Error
    Write-Log "SUBSCRIPTION CREATION FAILED" -Level Error
    Write-Log "============================================" -Level Error
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log ""
    
    if ($_.Exception.Message -like "*insufficient*" -or $_.Exception.Message -like "*authorization*" -or $_.Exception.Message -like "*permission*") {
        Write-Log "PERMISSION ERROR!" -Level Error
        Write-Log ""
        Write-Log "You need one of these roles:" -Level Warning
        Write-Log "  1. Owner role on PRODUCT Management Group" -Level Warning
        Write-Log "  2. Subscription Creator role on Billing Account" -Level Warning
        Write-Log "  3. Enrollment Account Subscription Creator role" -Level Warning
        Write-Log ""
        Write-Log "To fix this:" -Level Info
        Write-Log "1. Go to Azure Portal" -Level Info
        Write-Log "2. Navigate to Management Groups > PRODUCT" -Level Info
        Write-Log "3. Click Access Control (IAM)" -Level Info
        Write-Log "4. Add role assignment: Owner or Contributor" -Level Info
        Write-Log "5. Assign to your account: $($context.Account.Id)" -Level Info
    } elseif ($_.Exception.Message -like "*billing*" -or $_.Exception.Message -like "*enrollment*") {
        Write-Log "BILLING ACCOUNT ERROR!" -Level Error
        Write-Log ""
        Write-Log "You need access to a billing/enrollment account" -Level Warning
        Write-Log "Contact your Azure billing administrator" -Level Warning
    } else {
        Write-Log "UNKNOWN ERROR!" -Level Error
        Write-Log "Full error details saved in log file" -Level Info
    }
    
    Write-Log ""
    Write-Log "Log file: $LogFile" -Level Info
}

Write-Host ""
Read-Host "Press Enter to exit"
