#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix Disabled Alert Rules

.DESCRIPTION
    Enables all disabled metric alert rules
    
.EXAMPLE
    .\Fix-Disabled-Alerts.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX DISABLED ALERTS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will enable all disabled alert rules" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Getting metric alerts..." -ForegroundColor Yellow
$alertsJson = az monitor metrics alert list -o json 2>&1
$alerts = $alertsJson | ConvertFrom-Json

Write-Host "Found: $($alerts.Count)" -ForegroundColor White

$enabled = 0

foreach ($alert in $alerts) {
    if ($alert.enabled -ne $true) {
        Write-Host ""
        Write-Host "Enabling: $($alert.name)" -ForegroundColor Yellow
        
        try {
            az monitor metrics alert update `
                --name $alert.name `
                --resource-group $alert.resourceGroup `
                --enabled true `
                --output none
            
            Write-Host "  ENABLED" -ForegroundColor Green
            $enabled++
        } catch {
            Write-Host "  ERROR" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Alerts enabled: $enabled" -ForegroundColor Cyan
Write-Host ""
