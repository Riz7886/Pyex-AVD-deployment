#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Enable DDoS Protection

.DESCRIPTION
    Reports VNets without DDoS protection
    NOTE: DDoS Protection Standard costs extra ($2,944/month)
    
.EXAMPLE
    .\Enable-DDoS-Protection.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - DDOS PROTECTION REPORT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: DDoS Protection Standard costs $2,944/month" -ForegroundColor Yellow
Write-Host "This script only reports VNets without protection" -ForegroundColor Yellow
Write-Host ""

Write-Host "Getting VNets..." -ForegroundColor Yellow
$vnetsJson = az network vnet list -o json 2>&1
$vnets = $vnetsJson | ConvertFrom-Json

Write-Host "Found: $($vnets.Count)" -ForegroundColor White
Write-Host ""

$withoutDDoS = 0

foreach ($vnet in $vnets) {
    if ($vnet.enableDdosProtection -ne $true) {
        Write-Host "VNet without DDoS: $($vnet.name)" -ForegroundColor Yellow
        $withoutDDoS++
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  REPORT COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "VNets without DDoS protection: $withoutDDoS" -ForegroundColor Yellow
Write-Host ""
Write-Host "To enable DDoS (costs $2,944/month):" -ForegroundColor Yellow
Write-Host "  1. Create DDoS Protection Plan in Azure Portal" -ForegroundColor Gray
Write-Host "  2. Associate VNets with the plan" -ForegroundColor Gray
Write-Host ""
