#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix Storage Account Security

.DESCRIPTION
    1. Configures storage account firewalls (deny all, allow specific networks)
    2. Disables public blob access
    
.EXAMPLE
    .\Fix-Storage-Security.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX STORAGE SECURITY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Configure storage firewalls (default deny)" -ForegroundColor White
Write-Host "  2. Disable public blob access" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

# Backup
$backupFolder = "C:\Azure-Fixes-Backup\Storage"
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFile = "$backupFolder\storage-before-$timestamp.json"

Write-Host ""
Write-Host "Getting storage accounts..." -ForegroundColor Yellow
$storageJson = az storage account list -o json 2>&1
$storageAccounts = $storageJson | ConvertFrom-Json

Write-Host "Found: $($storageAccounts.Count)" -ForegroundColor White

# Backup
$storageAccounts | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
Write-Host "Backup: $backupFile" -ForegroundColor Green

$fixedFirewall = 0
$fixedBlob = 0

foreach ($sa in $storageAccounts) {
    Write-Host ""
    Write-Host "Processing: $($sa.name)" -ForegroundColor Cyan
    
    # Fix 1: Configure firewall
    if ($sa.networkRuleSet.defaultAction -eq "Allow") {
        Write-Host "  Configuring firewall..." -NoNewline
        try {
            az storage account update `
                --name $sa.name `
                --resource-group $sa.resourceGroup `
                --default-action Deny `
                --output none
            
            Write-Host " FIXED" -ForegroundColor Green
            $fixedFirewall++
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
        }
    }
    
    # Fix 2: Disable public blob access
    if ($sa.allowBlobPublicAccess -eq $true) {
        Write-Host "  Disabling public blob access..." -NoNewline
        try {
            az storage account update `
                --name $sa.name `
                --resource-group $sa.resourceGroup `
                --allow-blob-public-access false `
                --output none
            
            Write-Host " FIXED" -ForegroundColor Green
            $fixedBlob++
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Firewalls configured: $fixedFirewall" -ForegroundColor Cyan
Write-Host "Public blob disabled: $fixedBlob" -ForegroundColor Cyan
Write-Host "Backup: $backupFile" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: You may need to add trusted IPs to firewall" -ForegroundColor Yellow
Write-Host "Use: az storage account network-rule add" -ForegroundColor Gray
Write-Host ""
