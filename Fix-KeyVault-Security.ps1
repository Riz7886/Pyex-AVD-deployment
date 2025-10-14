#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix Key Vault Security

.DESCRIPTION
    1. Enables soft delete (90-day retention)
    2. Enables purge protection
    
.EXAMPLE
    .\Fix-KeyVault-Security.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX KEY VAULT SECURITY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Enable soft delete (90 days)" -ForegroundColor White
Write-Host "  2. Enable purge protection" -ForegroundColor White
Write-Host ""
Write-Host "WARNING: These changes CANNOT be reversed!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Getting Key Vaults..." -ForegroundColor Yellow
$kvJson = az keyvault list -o json 2>&1
$keyVaults = $kvJson | ConvertFrom-Json

Write-Host "Found: $($keyVaults.Count)" -ForegroundColor White

$fixedSoftDelete = 0
$fixedPurge = 0

foreach ($kv in $keyVaults) {
    Write-Host ""
    Write-Host "Processing: $($kv.name)" -ForegroundColor Cyan
    
    # Fix 1: Enable soft delete
    if ($kv.properties.enableSoftDelete -ne $true) {
        Write-Host "  Enabling soft delete..." -NoNewline
        try {
            az keyvault update `
                --name $kv.name `
                --resource-group $kv.resourceGroup `
                --enable-soft-delete true `
                --output none
            
            Write-Host " FIXED" -ForegroundColor Green
            $fixedSoftDelete++
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
        }
    } else {
        Write-Host "  Soft delete already enabled" -ForegroundColor Gray
    }
    
    # Fix 2: Enable purge protection
    if ($kv.properties.enablePurgeProtection -ne $true) {
        Write-Host "  Enabling purge protection..." -NoNewline
        try {
            az keyvault update `
                --name $kv.name `
                --resource-group $kv.resourceGroup `
                --enable-purge-protection true `
                --output none
            
            Write-Host " FIXED" -ForegroundColor Green
            $fixedPurge++
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
        }
    } else {
        Write-Host "  Purge protection already enabled" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Soft delete enabled: $fixedSoftDelete" -ForegroundColor Cyan
Write-Host "Purge protection enabled: $fixedPurge" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: These changes are permanent and cannot be reversed" -ForegroundColor Yellow
Write-Host ""
