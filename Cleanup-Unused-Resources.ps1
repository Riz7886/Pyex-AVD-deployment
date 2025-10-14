#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Cleanup Unused Resources

.DESCRIPTION
    1. Deletes empty resource groups
    2. Deletes unused public IPs
    
.EXAMPLE
    .\Cleanup-Unused-Resources.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - CLEANUP UNUSED RESOURCES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Delete empty resource groups" -ForegroundColor White
Write-Host "  2. Delete unused public IPs" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

$deletedRGs = 0
$deletedIPs = 0

# Cleanup 1: Empty Resource Groups
Write-Host ""
Write-Host "Finding empty resource groups..." -ForegroundColor Yellow
$rgsJson = az group list -o json 2>&1
$rgs = $rgsJson | ConvertFrom-Json

foreach ($rg in $rgs) {
    $resourcesJson = az resource list --resource-group $rg.name -o json 2>&1
    $resources = $resourcesJson | ConvertFrom-Json
    
    if ($resources.Count -eq 0) {
        Write-Host "  Deleting: $($rg.name)..." -NoNewline
        try {
            az group delete --name $rg.name --yes --no-wait --output none
            Write-Host " DELETED" -ForegroundColor Green
            $deletedRGs++
        } catch {
            Write-Host " ERROR" -ForegroundColor Red
        }
    }
}

# Cleanup 2: Unused Public IPs
Write-Host ""
Write-Host "Finding unused public IPs..." -ForegroundColor Yellow
$ipsJson = az network public-ip list -o json 2>&1
$ips = $ipsJson | ConvertFrom-Json

foreach ($ip in $ips) {
    if ($ip.ipConfiguration -eq $null) {
        Write-Host "  Deleting: $($ip.name)..." -NoNewline
        try {
            az network public-ip delete `
                --name $ip.name `
                --resource-group $ip.resourceGroup `
                --output none
            
            Write-Host " DELETED" -ForegroundColor Green
            $deletedIPs++
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
Write-Host "Empty resource groups deleted: $deletedRGs" -ForegroundColor Cyan
Write-Host "Unused public IPs deleted: $deletedIPs" -ForegroundColor Cyan
Write-Host "Cost savings: Approximately $" -NoNewline -ForegroundColor Cyan
Write-Host "$($deletedIPs * 3)" -NoNewline -ForegroundColor Green
Write-Host "/month" -ForegroundColor Cyan
Write-Host ""
