#Requires -Version 5.1

<#
.SYNOPSIS
    Professional Repository Cleanup

.DESCRIPTION
    - Deletes empty scripts
    - Removes backup folders
    - Cleans up unnecessary files
    - Organizes structure professionally
    - Pushes to GitHub
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectPath = "D:\PYEX-AVD-Deployment"
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  PROFESSIONAL REPOSITORY CLEANUP"
Write-Host "=============================================================="
Write-Host ""

Set-Location $ProjectPath

# Step 1: Remove backup folders
Write-Host "Step 1: Removing backup folders..." -ForegroundColor Cyan
$backupFolders = @(
    "Backup-Before-Cleanup",
    "Backup-Character-Fix"
)

foreach ($folder in $backupFolders) {
    $folderPath = Join-Path $ProjectPath $folder
    if (Test-Path $folderPath) {
        Remove-Item -Path $folderPath -Recurse -Force
        Write-Host "  Removed: $folder" -ForegroundColor Green
    }
}

Write-Host ""

# Step 2: Delete empty or very small scripts
Write-Host "Step 2: Removing empty or very small scripts..." -ForegroundColor Cyan

$allScripts = Get-ChildItem -Path $ProjectPath -Filter "*.ps1" -Recurse | Where-Object {
    $_.FullName -notlike "*\.git\*"
}

$deletedCount = 0
foreach ($script in $allScripts) {
    $content = Get-Content -Path $script.FullName -Raw -ErrorAction SilentlyContinue
    
    # Delete if empty or less than 100 characters
    if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 100) {
        Remove-Item -Path $script.FullName -Force
        Write-Host "  Deleted empty: $($script.Name)" -ForegroundColor Yellow
        $deletedCount++
    }
}

if ($deletedCount -eq 0) {
    Write-Host "  No empty scripts found" -ForegroundColor Green
}

Write-Host ""

# Step 3: Remove unnecessary files
Write-Host "Step 3: Removing unnecessary files..." -ForegroundColor Cyan

$unnecessaryFiles = @(
    "*.tmp",
    "*.log",
    "*.bak",
    "*-copy.ps1",
    "*-old.ps1"
)

$removedFiles = 0
foreach ($pattern in $unnecessaryFiles) {
    $files = Get-ChildItem -Path $ProjectPath -Filter $pattern -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notlike "*\.git\*"
    }
    
    foreach ($file in $files) {
        Remove-Item -Path $file.FullName -Force
        Write-Host "  Removed: $($file.Name)" -ForegroundColor Yellow
        $removedFiles++
    }
}

if ($removedFiles -eq 0) {
    Write-Host "  No unnecessary files found" -ForegroundColor Green
}

Write-Host ""

# Step 4: Update .gitignore
Write-Host "Step 4: Updating .gitignore..." -ForegroundColor Cyan

$gitignoreContent = @"
# Backup folders
Backup-*/

# Configuration files with secrets
Config/*.json
Configuration/*.json

# Audit reports
Audit-Reports/*.csv
Audit-Reports/*.html
IAM-Security-Reports/*.csv
IAM-Security-Reports/*.html

# Logs
*.log
*.tmp
*.bak

# OS files
.DS_Store
Thumbs.db
desktop.ini

# IDE files
.vscode/
.idea/
*.code-workspace
"@

$gitignoreContent | Out-File -FilePath (Join-Path $ProjectPath ".gitignore") -Encoding UTF8 -Force
Write-Host "  .gitignore updated" -ForegroundColor Green

Write-Host ""

# Step 5: Show final structure
Write-Host "Step 5: Final repository structure..." -ForegroundColor Cyan
Write-Host ""

Write-Host "Core Scripts:" -ForegroundColor Yellow
Get-ChildItem -Path $ProjectPath -Filter "*.ps1" | Where-Object {
    $_.Name -notlike "*Archive*"
} | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor White
}

Write-Host ""
Write-Host "Folders:" -ForegroundColor Yellow
Get-ChildItem -Path $ProjectPath -Directory | Where-Object {
    $_.Name -notlike ".*" -and
    $_.Name -notlike "Backup*"
} | ForEach-Object {
    Write-Host "  - $($_.Name)/" -ForegroundColor White
}

Write-Host ""

# Step 6: Git commit and push
Write-Host "=============================================================="
Write-Host "  PUSHING TO GITHUB"
Write-Host "=============================================================="
Write-Host ""

Write-Host "Adding all changes..." -ForegroundColor Cyan
git add .

Write-Host "Creating commit..." -ForegroundColor Cyan
git commit -m "Professional cleanup - Removed backups and empty files

- Removed all backup folders
- Deleted empty scripts
- Cleaned up unnecessary files
- Updated .gitignore
- Professional repository structure
- Ready for production"

Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "  SUCCESS - REPOSITORY IS NOW PROFESSIONAL"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Your repository is now:" -ForegroundColor Green
    Write-Host "  - Clean and organized" -ForegroundColor White
    Write-Host "  - No backup folders" -ForegroundColor White
    Write-Host "  - No empty scripts" -ForegroundColor White
    Write-Host "  - Professional structure" -ForegroundColor White
    Write-Host "  - Pushed to GitHub" -ForegroundColor White
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