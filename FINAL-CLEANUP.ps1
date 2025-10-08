#Requires -Version 5.1

<#
.SYNOPSIS
    Final Cleanup - Keep Only Working Scripts
.DESCRIPTION
    Removes all duplicate, broken, and cleanup scripts
    Keeps only production-ready working scripts
#>

Write-Host ""
Write-Host "=============================================================="
Write-Host "  FINAL CLEANUP - KEEPING ONLY WORKING SCRIPTS"
Write-Host "=============================================================="
Write-Host ""

$projectPath = "D:\PYEX-AVD-Deployment"
Set-Location $projectPath

# Scripts to KEEP (production ready)
$keepScripts = @(
    "Deploy-AVD.ps1",
    "Audit-Complete.ps1",
    "Analyze-AzureEnvironment.ps1",
    "Execute-AzureFixes.ps1",
    "IAM-Audit-MINIMAL.ps1",
    "Schedule-IAMAudit.ps1",
    "Send-IAMReport.ps1"
)

# Scripts to DELETE (duplicates, broken, cleanup scripts)
$deleteScripts = @(
    "Audit-IAMSecurity.ps1",
    "Audit-IAMSecurity-WORKING.ps1",
    "PROFESSIONAL-CLEANUP.ps1",
    "FIX-FANCY-CHARACTERS.ps1",
    "FINAL-PUSH-TO-GITHUB.ps1",
    "Remove-CompanyNames.ps1",
    "GITHUB.ps1"
)

Write-Host "Step 1: Removing duplicate and cleanup scripts..." -ForegroundColor Cyan
$deletedCount = 0

foreach ($script in $deleteScripts) {
    $scriptPath = Join-Path $projectPath $script
    if (Test-Path $scriptPath) {
        Remove-Item -Path $scriptPath -Force
        Write-Host "  Deleted: $script" -ForegroundColor Yellow
        $deletedCount++
    }
}

Write-Host "  Removed $deletedCount unnecessary scripts" -ForegroundColor Green
Write-Host ""

# Remove empty folders
Write-Host "Step 2: Cleaning up folders..." -ForegroundColor Cyan
$foldersToCheck = @("Scripts\Archive", "Documentation", "Configuration")

foreach ($folder in $foldersToCheck) {
    $folderPath = Join-Path $projectPath $folder
    if (Test-Path $folderPath) {
        $files = Get-ChildItem -Path $folderPath -Recurse
        if ($files.Count -eq 0) {
            Write-Host "  Keeping: $folder (empty but needed)" -ForegroundColor Gray
        } else {
            Write-Host "  Keeping: $folder ($($files.Count) files)" -ForegroundColor Green
        }
    }
}

Write-Host ""

# Show final structure
Write-Host "Step 3: Final Production Scripts:" -ForegroundColor Cyan
Write-Host ""

Write-Host "AVD DEPLOYMENT:" -ForegroundColor Yellow
Write-Host "  - Deploy-AVD.ps1           (Deploy Azure Virtual Desktop)"
Write-Host "  - Audit-Complete.ps1       (Audit AVD environment)"
Write-Host ""

Write-Host "AZURE SECURITY:" -ForegroundColor Yellow
Write-Host "  - Analyze-AzureEnvironment.ps1  (Detect all Azure issues)"
Write-Host "  - Execute-AzureFixes.ps1        (Fix detected issues)"
Write-Host ""

Write-Host "IAM SECURITY:" -ForegroundColor Yellow
Write-Host "  - IAM-Audit-MINIMAL.ps1    (IAM security audit - works everywhere)"
Write-Host "  - Schedule-IAMAudit.ps1    (Schedule automated audits)"
Write-Host "  - Send-IAMReport.ps1       (Email reports to management)"
Write-Host ""

Write-Host "FOLDERS:" -ForegroundColor Yellow
Get-ChildItem -Path $projectPath -Directory | Where-Object {
    $_.Name -notlike ".*"
} | ForEach-Object {
    Write-Host "  - $($_.Name)/"
}

Write-Host ""

# Update README
Write-Host "Step 4: Updating README..." -ForegroundColor Cyan

$readmeContent = @"
# Azure DevOps & Security Automation Suite

Professional Azure deployment, security audit, and IAM monitoring scripts.

## Core Scripts

### AVD Deployment
- **Deploy-AVD.ps1** - Deploy complete Azure Virtual Desktop environment
- **Audit-Complete.ps1** - Comprehensive AVD environment audit

### Azure Security Analysis
- **Analyze-AzureEnvironment.ps1** - Detect RBAC, Network, Security issues
- **Execute-AzureFixes.ps1** - Safe remediation with rollback capability

### IAM Security Monitoring
- **IAM-Audit-MINIMAL.ps1** - Identity and Access Management security audit
- **Schedule-IAMAudit.ps1** - Automated bi-weekly audits
- **Send-IAMReport.ps1** - Email reports to stakeholders

## Quick Start

### Deploy AVD
\`\`\`powershell
Connect-AzAccount
.\Deploy-AVD.ps1 -TargetUsers 10 -CompanyName "YourCompany"
\`\`\`

### Run IAM Security Audit
\`\`\`powershell
Connect-AzAccount
.\IAM-Audit-MINIMAL.ps1
\`\`\`

### Analyze Azure Environment
\`\`\`powershell
Connect-AzAccount
.\Analyze-AzureEnvironment.ps1
\`\`\`

## Features

- Professional enterprise-grade scripts
- No company-specific names
- Clean, tested code
- Comprehensive documentation
- Production-ready

## Repository Structure

\`\`\`
/
├── Deploy-AVD.ps1
├── Audit-Complete.ps1
├── Analyze-AzureEnvironment.ps1
├── Execute-AzureFixes.ps1
├── IAM-Audit-MINIMAL.ps1
├── Schedule-IAMAudit.ps1
├── Send-IAMReport.ps1
├── README.md
├── Configuration/
├── Documentation/
└── Scripts/
\`\`\`

## Requirements

- Azure PowerShell
- Azure subscription access
- PowerShell 5.1 or higher

## Installation

\`\`\`powershell
Install-Module -Name Az -Scope CurrentUser
Connect-AzAccount
\`\`\`

## License

Internal use - Professional toolkit

---

Last Updated: $(Get-Date -Format "yyyy-MM-dd")
"@

$readmeContent | Out-File -FilePath (Join-Path $projectPath "README.md") -Encoding UTF8 -Force
Write-Host "  README.md updated" -ForegroundColor Green
Write-Host ""

# Git operations
Write-Host "=============================================================="
Write-Host "  PUSHING TO GITHUB"
Write-Host "=============================================================="
Write-Host ""

Write-Host "Adding changes..." -ForegroundColor Cyan
git add .

Write-Host "Creating commit..." -ForegroundColor Cyan
git commit -m "Final cleanup - Production ready repository

Removed:
- Duplicate IAM audit scripts
- Cleanup and utility scripts
- Broken or non-working scripts

Kept only 7 production-ready scripts:
- AVD Deployment (2 scripts)
- Azure Security Analysis (2 scripts)
- IAM Security Monitoring (3 scripts)

Repository is now clean, professional, and production-ready."

Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "  SUCCESS - REPOSITORY IS PRODUCTION READY"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Your repository now has:" -ForegroundColor Green
    Write-Host "  - 7 production-ready scripts" -ForegroundColor White
    Write-Host "  - Clean professional structure" -ForegroundColor White
    Write-Host "  - Updated documentation" -ForegroundColor White
    Write-Host "  - No duplicate or broken scripts" -ForegroundColor White
    Write-Host ""
    Write-Host "View your repository:" -ForegroundColor Cyan
    Write-Host "https://github.com/Riz7886/Pyex-AVD-deployment" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Push failed. Run manually:" -ForegroundColor Yellow
    Write-Host "git push origin main" -ForegroundColor White
    Write-Host ""
}

Write-Host "Done!" -ForegroundColor Green
Write-Host ""