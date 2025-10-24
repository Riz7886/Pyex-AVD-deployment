#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionName = "SUB-PRODUCT-STAGING",
    [Parameter(Mandatory=$false)]
    [string]$ManagementGroupName = "PRODUCT",
    [Parameter(Mandatory=$false)]
    [string]$BillingAccountId,
    [Parameter(Mandatory=$false)]
    [string]$EnrollmentAccountName,
    [Parameter(Mandatory=$false)]
    [bool]$AutoDetect = $true
)

$ErrorActionPreference = "Stop"
$LogFile = "SubscriptionCreation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info')
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

function Test-RequiredModules {
    Write-Log "Checking required PowerShell modules..." -Level Info
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Billing')
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) { $missingModules += $module }
    }
    if ($missingModules.Count -gt 0) {
        Write-Log "Missing: $($missingModules -join ', ')" -Level Error
        Write-Log "Install with: Install-Module $($missingModules -join ', ') -Force" -Level Warning
        return $false
    }
    Write-Log "All required modules installed" -Level Success
    return $true
}

function Connect-ToAzure {
    Write-Log "Connecting to Azure..." -Level Info
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($null -eq $context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $context = Get-AzContext
        }
        Write-Log "Connected - Tenant: $($context.Tenant.Id)" -Level Success
        return $true
    } catch {
        Write-Log "Connection failed: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-ManagementGroup {
    param([string]$GroupName)
    Write-Log "Verifying management group: $GroupName" -Level Info
    try {
        $mg = Get-AzManagementGroup -GroupName $GroupName -ErrorAction SilentlyContinue
        if ($null -eq $mg) {
            Write-Log "Management group '$GroupName' not found" -Level Error
            return $false
        }
        Write-Log "Management group found: $($mg.DisplayName)" -Level Success
        return $true
    } catch {
        Write-Log "Error: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-ExistingSubscriptions {
    param([string]$ManagementGroup)
    Write-Log "Retrieving existing subscriptions..." -Level Info
    try {
        $subs = Get-AzManagementGroupSubscription -GroupName $ManagementGroup -ErrorAction SilentlyContinue
        if ($null -eq $subs -or $subs.Count -eq 0) {
            Write-Log "No existing subscriptions found" -Level Warning
            return @()
        }
        Write-Log "Found $($subs.Count) subscription(s):" -Level Success
        $index = 1
        foreach ($sub in $subs) {
            $subDetails = Get-AzSubscription -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
            if ($subDetails) {
                Write-Log "  [$index] $($subDetails.Name)" -Level Info
                $index++
            }
        }
        return $subs
    } catch {
        Write-Log "Error: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Test-SubscriptionExists {
    param([string]$Name)
    Write-Log "Checking if subscription name exists..." -Level Info
    try {
        $existing = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
        if ($existing) {
            Write-Log "Subscription '$Name' already exists!" -Level Error
            return $true
        }
        Write-Log "Subscription name is available" -Level Success
        return $false
    } catch {
        return $false
    }
}

function New-AzureSubscription {
    param([string]$Name, [string]$ManagementGroup, [string]$BillingAccount, [string]$EnrollmentAccount)
    Write-Log "Creating subscription: $Name" -Level Info
    try {
        $params = @{ Name = $Name; OfferType = 'MS-AZR-0017P'; ErrorAction = 'Stop' }
        if ($BillingAccount) { $params['BillingAccount'] = $BillingAccount }
        if ($EnrollmentAccount) { $params['EnrollmentAccountObjectId'] = $EnrollmentAccount }
        
        $newSub = New-AzSubscription @params
        if ($newSub) {
            Write-Log "Subscription created! ID: $($newSub.SubscriptionId)" -Level Success
            Start-Sleep -Seconds 10
            try {
                New-AzManagementGroupSubscription -GroupName $ManagementGroup -SubscriptionId $newSub.SubscriptionId -ErrorAction Stop
                Write-Log "Added to management group" -Level Success
            } catch {
                Write-Log "Warning: Could not add to management group" -Level Warning
            }
            return $newSub
        }
    } catch {
        Write-Log "Failed: $($_.Exception.Message)" -Level Error
        return $null
    }
}

Write-Log "======================================" -Level Info
Write-Log "Azure Subscription Creator" -Level Info
Write-Log "======================================" -Level Info
Write-Log "Target: PYX Application Tenant" -Level Info
Write-Log "Management Group: $ManagementGroupName" -Level Info
Write-Log "Subscription Name: $SubscriptionName" -Level Info

if (!(Test-RequiredModules)) { exit 1 }
if (!(Connect-ToAzure)) { exit 1 }
if (!(Test-ManagementGroup -GroupName $ManagementGroupName)) { exit 1 }

$existingSubs = Get-ExistingSubscriptions -ManagementGroup $ManagementGroupName
Write-Log "This will be subscription #$($existingSubs.Count + 1)" -Level Info

if (Test-SubscriptionExists -Name $SubscriptionName) { exit 1 }

$confirm = Read-Host "`nProceed with creation? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Log "Cancelled by user" -Level Warning
    exit 0
}

$result = New-AzureSubscription -Name $SubscriptionName -ManagementGroup $ManagementGroupName

if ($result) {
    Write-Log "======================================" -Level Success
    Write-Log "SUBSCRIPTION CREATED SUCCESSFULLY!" -Level Success
    Write-Log "======================================" -Level Success
} else {
    Write-Log "SUBSCRIPTION CREATION FAILED" -Level Error
    exit 1
}
