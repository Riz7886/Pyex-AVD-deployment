#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Master Installer - All 4 Automated Reports with Email
.DESCRIPTION
    Installs all 4 tasks that automatically email reports to:
    - John.pinto@pyxhealth.com
    - shaun.raj@pyxhealth.com
    - anthony.schlak@pyxhealth.com
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  MASTER INSTALLER - AUTOMATED REPORTS WITH EMAIL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Host "BEFORE RUNNING: Configure SMTP settings in each wrapper script!" -ForegroundColor Yellow
Write-Host "Edit these files and replace YOUR_EMAIL and YOUR_PASSWORD:" -ForegroundColor Yellow
Write-Host "  - Run-MonitorReports-WithEmail.ps1" -ForegroundColor White
Write-Host "  - Run-CostReports-WithEmail.ps1" -ForegroundColor White
Write-Host "  - Run-SecurityAudit-WithEmail.ps1" -ForegroundColor White
Write-Host "  - Run-ADSecurity-WithEmail.ps1" -ForegroundColor White
Write-Host ""

$continue = Read-Host "Have you configured SMTP settings? (yes/no)"
if ($continue -ne "yes") {
    Write-Host "Please configure SMTP first, then run this script again" -ForegroundColor Yellow
    exit
}

$scripts = @(
    "Schedule-MonitorReports.ps1",
    "Schedule-CostOptimizationReports.ps1",
    "Schedule-SecurityAuditReports.ps1",
    "Schedule-ADSecurityReports.ps1"
)

foreach ($script in $scripts) {
    Write-Host "Installing: $script" -ForegroundColor Cyan
    & ".\$script"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  ALL TASKS INSTALLED WITH EMAIL!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Reports will be emailed automatically to:" -ForegroundColor Yellow
Write-Host "  - John.pinto@pyxhealth.com" -ForegroundColor White
Write-Host "  - shaun.raj@pyxhealth.com" -ForegroundColor White
Write-Host "  - anthony.schlak@pyxhealth.com" -ForegroundColor White
Write-Host ""
