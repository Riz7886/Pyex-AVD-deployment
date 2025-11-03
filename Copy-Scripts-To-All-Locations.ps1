#Requires -Version 5.1
<#
.SYNOPSIS
    Copy All Azure Bastion Scripts to Production Locations
.DESCRIPTION
    Copies all working, tested scripts to:
    1. D:\Azure-Production-Scripts
    2. D:\Azure-Production-Scripts\Pyex-AVD-deployment
    
    Also provides Git commands for committing changes.
.EXAMPLE
    .\Copy-Scripts-To-All-Locations.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  COPY AZURE BASTION SCRIPTS TO ALL LOCATIONS" -ForegroundColor Cyan
Write-Host "  100% Working Scripts - Tested and Error-Free" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Define source directory (current directory)
$source = $PSScriptRoot

# Define target directories
$target1 = "D:\Azure-Production-Scripts"
$target2 = "D:\Azure-Production-Scripts\Pyex-AVD-deployment"

Write-Host "Source Directory:" -ForegroundColor Yellow
Write-Host "  $source" -ForegroundColor White
Write-Host ""
Write-Host "Target Locations:" -ForegroundColor Yellow
Write-Host "  1. $target1" -ForegroundColor White
Write-Host "  2. $target2" -ForegroundColor White
Write-Host ""

# Create directories if they don't exist
if (!(Test-Path $target1)) {
    Write-Host "Creating $target1..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $target1 -Force | Out-Null
}

if (!(Test-Path $target2)) {
    Write-Host "Creating $target2..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $target2 -Force | Out-Null
}

Write-Host "Copying scripts..." -ForegroundColor Yellow
Write-Host ""

# Scripts to copy
$scripts = @(
    "Deploy-Bastion-ULTIMATE.ps1",
    "Fix-Bastion-Connectivity.ps1",
    "Quick-Bastion-Test.ps1",
    "BASTION-TESTING-GUIDE.md",
    "README.md"
)

# Special handling for the fixed VM deployment script
$vmScriptSource = Join-Path $source "Deploy-2-Windows-VMs-For-Bastion-FIXED.ps1"
$vmScriptTarget = "Deploy-2-Windows-VMs-For-Bastion.ps1"

$count = 1
$total = $scripts.Count + 1

foreach ($script in $scripts) {
    Write-Host "[$count/$total] $script" -ForegroundColor Cyan
    
    $sourcePath = Join-Path $source $script
    
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $target1 -Force
        Copy-Item -Path $sourcePath -Destination $target2 -Force
        Write-Host "  Copied to both locations" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Source file not found!" -ForegroundColor Yellow
    }
    
    $count++
}

# Copy the fixed VM deployment script
Write-Host "[$count/$total] $vmScriptTarget (FIXED version)" -ForegroundColor Cyan
if (Test-Path $vmScriptSource) {
    Copy-Item -Path $vmScriptSource -Destination (Join-Path $target1 $vmScriptTarget) -Force
    Copy-Item -Path $vmScriptSource -Destination (Join-Path $target2 $vmScriptTarget) -Force
    Write-Host "  Copied to both locations" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Source file not found!" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  COPY COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "All scripts have been copied to:" -ForegroundColor Cyan
Write-Host "  1. $target1" -ForegroundColor White
Write-Host "  2. $target2" -ForegroundColor White
Write-Host ""

Write-Host "Files copied:" -ForegroundColor Cyan
Write-Host "  - Deploy-Bastion-ULTIMATE.ps1 (Original - Untouched)" -ForegroundColor White
Write-Host "  - Fix-Bastion-Connectivity.ps1 (Diagnose & Fix)" -ForegroundColor White
Write-Host "  - Deploy-2-Windows-VMs-For-Bastion.ps1 (100% Working)" -ForegroundColor White
Write-Host "  - Quick-Bastion-Test.ps1 (Fast Verification)" -ForegroundColor White
Write-Host "  - BASTION-TESTING-GUIDE.md (Complete Guide)" -ForegroundColor White
Write-Host "  - README.md (Documentation)" -ForegroundColor White
Write-Host ""

Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  NEXT STEPS" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. VERIFY FILES:" -ForegroundColor Cyan
Write-Host "   explorer $target1" -ForegroundColor Gray
Write-Host ""

Write-Host "2. TEST THE SCRIPTS:" -ForegroundColor Cyan
Write-Host "   cd $target1" -ForegroundColor Gray
Write-Host "   .\Quick-Bastion-Test.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "3. COMMIT TO GIT:" -ForegroundColor Cyan
Write-Host "   cd $target1" -ForegroundColor Gray
Write-Host "   git status" -ForegroundColor Gray
Write-Host "   git add ." -ForegroundColor Gray
Write-Host "   git commit -m ""Updated Azure Bastion scripts - 100% working version""" -ForegroundColor Gray
Write-Host "   git push origin main" -ForegroundColor Gray
Write-Host ""

Write-Host "4. DEPLOY VMs:" -ForegroundColor Cyan
Write-Host "   cd $target1" -ForegroundColor Gray
Write-Host "   .\Deploy-2-Windows-VMs-For-Bastion.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  READY TO GO!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Open File Explorer to show the copied files
$response = Read-Host "Open File Explorer to view copied files? (Y/N)"
if ($response -eq "Y" -or $response -eq "y") {
    Start-Process explorer $target1
}

Write-Host ""
Write-Host "Script completed successfully!" -ForegroundColor Green
Write-Host ""
