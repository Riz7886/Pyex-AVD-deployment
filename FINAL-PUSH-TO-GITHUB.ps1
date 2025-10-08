#Requires -Version 5.1

<#
.SYNOPSIS
    Final Push to GitHub - Replace All Files

.DESCRIPTION
    Pushes all cleaned scripts to GitHub
    Keeps IAM security scripts
    Replaces everything else
#>

Write-Host ""
Write-Host "=============================================================="
Write-Host "  FINAL PUSH TO GITHUB"
Write-Host "  Replacing all files except IAM scripts"
Write-Host "=============================================================="
Write-Host ""

# Navigate to project
$projectPath = "D:\PYEX-AVD-Deployment"
Set-Location $projectPath

Write-Host "Current directory: $projectPath" -ForegroundColor Cyan
Write-Host ""

# Show what will be pushed
Write-Host "Files that will be pushed to GitHub:" -ForegroundColor Yellow
Write-Host ""

Write-Host "AVD Deployment Scripts:" -ForegroundColor Green
Write-Host "  - Deploy-AVD.ps1"
Write-Host "  - Audit-Complete.ps1"
Write-Host ""

Write-Host "IAM Security Scripts (NEW):" -ForegroundColor Green
Write-Host "  - Audit-IAMSecurity.ps1"
Write-Host "  - Send-IAMReport.ps1"
Write-Host "  - Schedule-IAMAudit.ps1"
Write-Host ""

Write-Host "Azure Analyzer Scripts:" -ForegroundColor Green
Write-Host "  - Analyze-AzureEnvironment.ps1"
Write-Host "  - Execute-AzureFixes.ps1"
Write-Host ""

Write-Host "Utilities:" -ForegroundColor Green
Write-Host "  - Remove-CompanyNames.ps1"
Write-Host ""

Write-Host "Documentation:" -ForegroundColor Green
Write-Host "  - README.md"
Write-Host "  - AZURE-ANALYZER-README.md"
Write-Host "  - Architecture docs"
Write-Host ""

# Check git status
Write-Host "Checking git status..." -ForegroundColor Cyan
git status

Write-Host ""
$confirm = Read-Host "Do you want to push all these files to GitHub? (Y/n)"

if ($confirm -eq 'n' -or $confirm -eq 'N') {
    Write-Host "Push cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "  PUSHING TO GITHUB"
Write-Host "=============================================================="
Write-Host ""

# Stage all changes
Write-Host "1. Staging all changes..." -ForegroundColor Cyan
git add .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stage files" -ForegroundColor Red
    exit 1
}

Write-Host "   Files staged successfully" -ForegroundColor Green
Write-Host ""

# Commit
Write-Host "2. Creating commit..." -ForegroundColor Cyan
git commit -m "Complete update - Removed company names and added IAM Security Suite

Updated files:
- All scripts cleaned of company-specific names
- Added comprehensive IAM Security Audit system
- Added Azure Environment Analyzer
- Professional documentation
- Ready for production use

New Features:
- Automated IAM security audits (twice weekly)
- Email reporting to stakeholders
- Risk scoring and compliance checking
- Azure environment analysis and auto-remediation
- Clean, generic naming for public use"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create commit" -ForegroundColor Red
    exit 1
}

Write-Host "   Commit created successfully" -ForegroundColor Green
Write-Host ""

# Push to GitHub
Write-Host "3. Pushing to GitHub..." -ForegroundColor Cyan
Write-Host "   Repository: https://github.com/Riz7886/Pyex-AVD-deployment.git" -ForegroundColor Gray
Write-Host ""

git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "  SUCCESS - ALL FILES PUSHED TO GITHUB"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Your repository has been updated!" -ForegroundColor Green
    Write-Host ""
    Write-Host "View your repository:" -ForegroundColor Cyan
    Write-Host "https://github.com/Riz7886/Pyex-AVD-deployment" -ForegroundColor White
    Write-Host ""
    Write-Host "What's included:" -ForegroundColor Yellow
    Write-Host "  - AVD Deployment Scripts" -ForegroundColor White
    Write-Host "  - IAM Security Audit System (NEW)" -ForegroundColor White
    Write-Host "  - Azure Environment Analyzer" -ForegroundColor White
    Write-Host "  - Complete Documentation" -ForegroundColor White
    Write-Host "  - All company names removed" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "  PUSH FAILED"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Error occurred during push. Common solutions:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Check your internet connection" -ForegroundColor White
    Write-Host "2. Verify GitHub credentials" -ForegroundColor White
    Write-Host "3. Try again: git push origin main" -ForegroundColor White
    Write-Host ""
}

Write-Host "Done!" -ForegroundColor Green
Write-Host ""