# Cleanup Script - Run this in D:\Azure-Production-Scripts
# This will delete all old/duplicate scripts and keep only the 2 we need

Write-Host "Cleaning up old scripts..." -ForegroundColor Yellow
Write-Host ""

# Delete all old deployment scripts
$oldScripts = @(
    "Deploy-Bastion-FIXED.ps1",
    "Deploy-DataDog-Automated.ps1",
    "Deploy-DataDog-FIXED.ps1",
    "Deploy-Reporting-Server-Automated.ps1",
    "Deploy-Reporting-Server-FIXED.ps1",
    "Deploy-Reporting-Server-CLEAN.ps1",
    "Install-Reporting-Software-Automated.ps1",
    "Install-Reporting-Software-Complete.ps1",
    "datadog-config-template.txt"
)

foreach ($script in $oldScripts) {
    if (Test-Path $script) {
        Remove-Item $script -Force
        Write-Host "Deleted: $script" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Now you have only 2 simple scripts:" -ForegroundColor Yellow
Write-Host "  1. Deploy-Reporting-Server.ps1" -ForegroundColor Green
Write-Host "  2. Install-Software.ps1" -ForegroundColor Green
Write-Host ""
