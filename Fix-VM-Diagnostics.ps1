#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix VM Diagnostics

.DESCRIPTION
    Enables boot diagnostics on all VMs
    
.EXAMPLE
    .\Fix-VM-Diagnostics.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX VM DIAGNOSTICS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will enable boot diagnostics on all VMs" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Getting VMs..." -ForegroundColor Yellow
$vmsJson = az vm list -o json 2>&1
$vms = $vmsJson | ConvertFrom-Json

Write-Host "Found: $($vms.Count)" -ForegroundColor White

$enabled = 0

foreach ($vm in $vms) {
    Write-Host ""
    Write-Host "Processing: $($vm.name)" -ForegroundColor Cyan
    
    try {
        az vm boot-diagnostics enable `
            --name $vm.name `
            --resource-group $vm.resourceGroup `
            --output none
        
        Write-Host "  ENABLED" -ForegroundColor Green
        $enabled++
    } catch {
        Write-Host "  ERROR" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Boot diagnostics enabled: $enabled" -ForegroundColor Cyan
Write-Host ""
