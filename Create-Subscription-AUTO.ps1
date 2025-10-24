#Requires -Version 5.1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Azure Subscription Creator - AUTO MODE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"
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
    Add-Content -Path $LogFile -Value $logMessage
}

Write-Log "Starting Azure Subscription Creator..." -Level Info
Write-Log "Target: PYX Application Tenant" -Level Info
Write-Log "Management Group: PRODUCT" -Level Info
Write-Log "Subscription Name: SUB-PRODUCT-STAGING" -Level Info
Write-Log ""

Write-Log "Step 1: Checking PowerShell modules..." -Level Info
$requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Billing')
$missingModules = @()
foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Log "Missing modules: $($missingModules -join ', ')" -Level Error
    Write-Log "Installing missing modules..." -Level Warning
    foreach ($module in $missingModules) {
        Install-Module $module -Scope CurrentUser -Force -AllowClobber
        Write-Log "Installed: $module" -Level Success
    }
}
Write-Log "All modules ready!" -Level Success
Write-Log ""

Write-Log "Step 2: Connecting to Azure..." -Level Info
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

Write-Log "Step 3: Verifying PRODUCT management group..." -Level Info
try {
    $mg = Get-AzManagementGroup -GroupName "PRODUCT" -ErrorAction SilentlyContinue
    if ($null -eq $mg) {
        Write-Log "Management group PRODUCT not found!" -Level Error
        Write-Log "Available management groups:" -Level Info
        Get-AzManagementGroup | ForEach-Object { Write-Log "  - $($_.Name)" -Level Info }
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Log "Found management group: $($mg.DisplayName)" -Level Success
    Write-Log ""
} catch {
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Log "Step 4: Checking existing subscriptions..." -Level Info
try {
    $subs = Get-AzManagementGroupSubscription -GroupName "PRODUCT" -ErrorAction SilentlyContinue
    if ($null -eq $subs -or $subs.Count -eq 0) {
        Write-Log "No existing subscriptions found" -Level Warning
    } else {
        Write-Log "Found $($subs.Count) existing subscription(s):" -Level Success
        $index = 1
        foreach ($sub in $subs) {
            $subDetails = Get-AzSubscription -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
            if ($subDetails) {
                Write-Log "  [$index] $($subDetails.Name)" -Level Info
                $index++
            }
        }
    }
    Write-Log "This will be subscription #$($subs.Count + 1)" -Level Info
    Write-Log ""
} catch {
    Write-Log "Warning: Could not retrieve existing subscriptions" -Level Warning
}

Write-Log "Step 5: Checking if SUB-PRODUCT-STAGING exists..." -Level Info
try {
    $existing = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "SUB-PRODUCT-STAGING" }
    if ($existing) {
        Write-Log "Subscription SUB-PRODUCT-STAGING already exists!" -Level Error
        Write-Log "Subscription ID: $($existing.Id)" -Level Info
        Write-Log "State: $($existing.State)" -Level Info
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Log "Subscription name is available!" -Level Success
    Write-Log ""
} catch {
    Write-Log "Could not verify subscription name" -Level Warning
}

Write-Log "============================================" -Level Info
Write-Log "READY TO CREATE SUBSCRIPTION" -Level Info
Write-Log "============================================" -Level Info
Write-Log "Name: SUB-PRODUCT-STAGING" -Level Info
Write-Log "Management Group: PRODUCT" -Level Info
Write-Log "Tenant: PYX Application Tenant" -Level Info
Write-Log ""

$confirm = Read-Host "Type YES to proceed with creation"
if ($confirm -ne "YES") {
    Write-Log "Creation cancelled by user" -Level Warning
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Log ""
Write-Log "Step 6: Creating subscription..." -Level Info
Write-Log "This may take 1-2 minutes..." -Level Warning

try {
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
        Write-Log "Waiting 10 seconds for provisioning..." -Level Info
        Start-Sleep -Seconds 10
        
        Write-Log "Adding subscription to PRODUCT management group..." -Level Info
        try {
            New-AzManagementGroupSubscription -GroupName "PRODUCT" -SubscriptionId $newSub.SubscriptionId -ErrorAction Stop
            Write-Log "Added to management group successfully!" -Level Success
        } catch {
            Write-Log "Warning: Could not add to management group automatically" -Level Warning
            Write-Log "You can add it manually in Azure Portal" -Level Warning
        }
        
        Write-Log ""
        Write-Log "============================================" -Level Success
        Write-Log "SUBSCRIPTION CREATED SUCCESSFULLY!" -Level Success
        Write-Log "============================================" -Level Success
        Write-Log ""
        Write-Log "Subscription Name: SUB-PRODUCT-STAGING" -Level Success
        Write-Log "Subscription ID: $($newSub.SubscriptionId)" -Level Success
        Write-Log "Log File: $LogFile" -Level Info
        Write-Log ""
        Write-Log "Next Steps:" -Level Info
        Write-Log "1. Configure RBAC roles" -Level Info
        Write-Log "2. Set up budgets" -Level Info
        Write-Log "3. Apply Azure policies" -Level Info
        Write-Log ""
    }
} catch {
    Write-Log ""
    Write-Log "============================================" -Level Error
    Write-Log "SUBSCRIPTION CREATION FAILED" -Level Error
    Write-Log "============================================" -Level Error
    Write-Log "Error: $($_.Exception.Message)" -Level Error
    Write-Log ""
    
    if ($_.Exception.Message -like "*insufficient*" -or $_.Exception.Message -like "*authorization*") {
        Write-Log "PERMISSION ERROR!" -Level Error
        Write-Log "You need one of these roles:" -Level Warning
        Write-Log "  - Owner on PRODUCT Management Group" -Level Warning
        Write-Log "  - Enrollment Account Subscription Creator" -Level Warning
        Write-Log "  - Subscription Creator on Billing Account" -Level Warning
    }
    
    Write-Log ""
    Write-Log "Log file saved: $LogFile" -Level Info
}

Write-Host ""
Read-Host "Press Enter to exit"
