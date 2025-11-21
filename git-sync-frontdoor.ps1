# Git Sync Script for Front Door Deployment
# This script safely removes old Front Door code and syncs new code

param(
    [string]$CommitMessage = "Update Front Door Terraform deployment"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Front Door Terraform - Git Sync" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Host "ERROR: Not in a git repository" -ForegroundColor Red
    Write-Host "Please run this script from your project root" -ForegroundColor Yellow
    exit 1
}

Write-Host "Step 1: Checking Git status..." -ForegroundColor Yellow
$status = git status --porcelain
if ($status) {
    Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
    git status --short
    Write-Host ""
    $response = Read-Host "Do you want to continue? (y/n)"
    if ($response -ne 'y') {
        Write-Host "Aborted by user" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Step 2: Creating backup of old Front Door code..." -ForegroundColor Yellow
$backupDir = "backup_frontdoor_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# Find and backup old Front Door files
Get-ChildItem -Recurse -File | Where-Object {
    $_.Name -like "*frontdoor*.tf" -or 
    $_.Name -like "*front-door*.tf" -or 
    $_.Name -like "*fd-*.tf"
} | Where-Object {
    $_.FullName -notlike "*$backupDir*" -and
    $_.FullName -notlike "*Pyx-AVD-deployment\DriversHealth-FrontDoor*"
} | ForEach-Object {
    Write-Host "  Backing up: $($_.FullName)" -ForegroundColor Gray
    Copy-Item $_.FullName -Destination $backupDir -Force
}

if ((Get-ChildItem $backupDir).Count -eq 0) {
    Write-Host "  No old Front Door files found" -ForegroundColor Gray
} else {
    Write-Host "  Backup created in: $backupDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 3: Removing old Front Door code..." -ForegroundColor Yellow

# Remove old Front Door files (not in new location)
Get-ChildItem -Recurse -File | Where-Object {
    $_.Name -like "*frontdoor*.tf" -or 
    $_.Name -like "*front-door*.tf" -or 
    $_.Name -like "*fd-*.tf"
} | Where-Object {
    $_.FullName -notlike "*$backupDir*" -and
    $_.FullName -notlike "*Pyx-AVD-deployment\DriversHealth-FrontDoor*"
} | ForEach-Object {
    Write-Host "  Removing: $($_.FullName)" -ForegroundColor Gray
    Remove-Item $_.FullName -Force
    git rm --cached $_.FullName -ErrorAction SilentlyContinue
}

# Remove old Front Door directories (not new location)
Get-ChildItem -Recurse -Directory | Where-Object {
    $_.Name -like "*frontdoor*" -or 
    $_.Name -like "*front-door*"
} | Where-Object {
    $_.FullName -notlike "*$backupDir*" -and
    $_.FullName -notlike "*Pyx-AVD-deployment\DriversHealth-FrontDoor*"
} | ForEach-Object {
    Write-Host "  Removing directory: $($_.FullName)" -ForegroundColor Gray
    Remove-Item $_.FullName -Recurse -Force
    git rm -r --cached $_.FullName -ErrorAction SilentlyContinue
}

Write-Host "  Old Front Door code removed" -ForegroundColor Green

Write-Host ""
Write-Host "Step 4: Creating new Front Door deployment structure..." -ForegroundColor Yellow

# Ensure correct directory structure exists
$targetDir = "Pyx-AVD-deployment\DriversHealth-FrontDoor"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "  Created: $targetDir" -ForegroundColor Green
} else {
    Write-Host "  Directory exists: $targetDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 5: Staging new Front Door code..." -ForegroundColor Yellow

# Add new files
git add $targetDir
git add cleanup-and-sync-frontdoor.sh -ErrorAction SilentlyContinue
git add git-sync-frontdoor.ps1 -ErrorAction SilentlyContinue

Write-Host "  New files staged" -ForegroundColor Green

Write-Host ""
Write-Host "Step 6: Committing changes..." -ForegroundColor Yellow

# Commit changes
$hasChanges = git diff-index --quiet HEAD --
if ($LASTEXITCODE -ne 0) {
    git commit -m $CommitMessage -m "- Removed old Front Door Terraform code" -m "- Added new clean Front Door deployment" -m "- Structure: Pyx-AVD-deployment/DriversHealth-FrontDoor" -m "- Deploys ONLY Front Door and backends" -m "- Full security: WAF, HTTPS, monitoring"
    Write-Host "  Changes committed" -ForegroundColor Green
} else {
    Write-Host "  No changes to commit" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 7: Checking remote..." -ForegroundColor Yellow

$remote = git remote -v | Select-String "origin"
if ($remote) {
    Write-Host "  Remote found: origin" -ForegroundColor Green
    Write-Host ""
    $push = Read-Host "Do you want to push to remote? (y/n)"
    if ($push -eq 'y') {
        Write-Host ""
        Write-Host "Pushing to remote..." -ForegroundColor Yellow
        git push
        Write-Host "  Pushed to remote" -ForegroundColor Green
    } else {
        Write-Host "  Skipped push (run 'git push' manually)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  No remote configured" -ForegroundColor Yellow
    Write-Host "  To add remote: git remote add origin <url>" -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Git Sync Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - Old Front Door code removed" -ForegroundColor Gray
Write-Host "  - Backup created: $backupDir" -ForegroundColor Gray
Write-Host "  - New code location: $targetDir" -ForegroundColor Gray
Write-Host "  - Changes committed to Git" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Review changes: git status" -ForegroundColor Gray
Write-Host "  2. Deploy Front Door: cd $targetDir; terraform init; terraform apply" -ForegroundColor Gray
Write-Host "  3. Push to remote (if not done): git push" -ForegroundColor Gray
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
