#Requires -Modules Az.Accounts, Az.DesktopVirtualization, AzureAD
#Requires -Version 5.1

<#
.SYNOPSIS
    Bulk user onboarding for Azure Virtual Desktop
    
.DESCRIPTION
    Assigns users to AVD Application Group
    
.PARAMETER CsvPath
    Path to CSV file with user emails
    
.PARAMETER AppGroupName
    Application Group name
    
.PARAMETER ResourceGroupName
    Resource Group name
    
.EXAMPLE
    .\AVD-User-Onboarding.ps1 -CsvPath "Users\avd-users.csv" -AppGroupName "ag-Companyhealth-desktop" -ResourceGroupName "rg-Companyhealth-avd-core-1234"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory = $true)]
    [string]$AppGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Continue'

Write-Host "`n══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "AZURE VIRTUAL DESKTOP - USER ONBOARDING" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Connect to Azure AD
Write-Host "Connecting to Azure AD..." -ForegroundColor Yellow
try {
    Connect-AzureAD -ErrorAction Stop | Out-Null
    Write-Host "✓ Connected to Azure AD`n" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to connect to Azure AD" -ForegroundColor Red
    exit 1
}

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        Connect-AzAccount
    }
    Write-Host "✓ Connected to Azure`n" -ForegroundColor Green
} catch {
    Connect-AzAccount
}

# Read users
if (-not (Test-Path $CsvPath)) {
    Write-Host "✗ CSV file not found: $CsvPath" -ForegroundColor Red
    exit 1
}

$users = Import-Csv $CsvPath
Write-Host "Found $($users.Count) users in CSV`n" -ForegroundColor Cyan

# Get Application Group
$appGroup = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -Name $AppGroupName

if (-not $appGroup) {
    Write-Host "✗ Application Group not found: $AppGroupName" -ForegroundColor Red
    exit 1
}

# Process users
$successCount = 0
$failedCount = 0
$results = @()

foreach ($user in $users) {
    $upn = $user.UserPrincipalName
    Write-Host "Processing: $upn" -ForegroundColor Gray
    
    try {
        $aadUser = Get-AzureADUser -ObjectId $upn -ErrorAction Stop
        
        New-AzRoleAssignment -ObjectId $aadUser.ObjectId `
            -RoleDefinitionName "Desktop Virtualization User" `
            -ResourceName $AppGroupName `
            -ResourceGroupName $ResourceGroupName `
            -ResourceType 'Microsoft.DesktopVirtualization/applicationGroups' `
            -ErrorAction Stop | Out-Null
        
        Write-Host "  ✓ Assigned successfully" -ForegroundColor Green
        $successCount++
        
        $results += [PSCustomObject]@{
            UserPrincipalName = $upn
            DisplayName = $aadUser.DisplayName
            Status = "Success"
        }
    } catch {
        Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        $failedCount++
        
        $results += [PSCustomObject]@{
            UserPrincipalName = $upn
            DisplayName = ""
            Status = "Failed"
        }
    }
}

Write-Host "`n══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "ONBOARDING COMPLETE" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Total Users:  $($users.Count)" -ForegroundColor White
Write-Host "Successful:   $successCount" -ForegroundColor Green
Write-Host "Failed:       $failedCount" -ForegroundColor $(if($failedCount -gt 0){'Red'}else{'Green'})
Write-Host "══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$resultsPath = ".\AVD-User-Onboarding-Results-$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv $resultsPath -NoTypeInformation
Write-Host "Results: $resultsPath" -ForegroundColor Green
Write-Host "`nUsers can access AVD at: https://rdweb.wvd.microsoft.com`n" -ForegroundColor Cyan
