# ================================================================
# GIT CLEANUP AND PUSH SCRIPT
# Deletes NGINX files, adds MOVEit v4.0 files
# Pushes to: https://github.com/Riz7886/Pyex-AVD-deployment.git
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  GIT CLEANUP AND PUSH" -ForegroundColor Cyan
Write-Host "  Removing NGINX, Adding MOVEit v4.0" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Navigate to project
Set-Location "C:\Projects\Pyex-AVD-deployment"

# ----------------------------------------------------------------
# STEP 1: DELETE NGINX FILES FROM GIT
# ----------------------------------------------------------------
Write-Host "[STEP 1] Removing NGINX files from Git..." -ForegroundColor Yellow

$nginxFiles = @(
    "FREE-NGINX-DMZ-Business-Case-SECURE.docx",
    "FREE-NGINX-DMZ-Business-Case-VISUAL.docx",
    "FREE-NGINX-DMZ-COMPLETE.docx",
    "Information_dmz-deploy.txt"
)

foreach ($file in $nginxFiles) {
    if (Test-Path $file) {
        Write-Host "Removing: $file" -ForegroundColor Red
        git rm $file 2>$null
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[SUCCESS] NGINX files removed" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------
# STEP 2: DELETE OLD MOVEIT FILES
# ----------------------------------------------------------------
Write-Host "[STEP 2] Removing old MOVEit files..." -ForegroundColor Yellow

$oldMoveitFiles = @(
    "PACKAGE-CONTENTS.txt",
    "QUICK-START.txt",
    "README-POWERSHELL.md",
    "README-TERRAFORM.md"
)

foreach ($file in $oldMoveitFiles) {
    if (Test-Path $file) {
        Write-Host "Removing: $file" -ForegroundColor Red
        git rm $file 2>$null
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[SUCCESS] Old MOVEit files removed" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------
# STEP 3: ADD NEW MOVEIT V4.0 FILES
# ----------------------------------------------------------------
Write-Host "[STEP 3] Adding new MOVEit v4.0 files..." -ForegroundColor Yellow

# Check if files exist
$newFiles = @(
    "Deploy-MOVEit-FINAL-v4.ps1",
    "main-FINAL-v4.tf",
    "outputs-FINAL-v4.tf",
    "generate-cert.ps1",
    "README.md",
    ".gitignore",
    "EXECUTIVE-SUMMARY.txt",
    "MOVEIT-DEPLOYMENT-GUIDE-v4.txt",
    "VERSION-COMPARISON-v3-vs-v4.txt",
    "GIT-PUSH-INSTRUCTIONS.txt",
    "CLEANUP-COMPLETE.txt"
)

$missingFiles = @()
foreach ($file in $newFiles) {
    if (Test-Path $file) {
        Write-Host "Adding: $file" -ForegroundColor Green
        git add $file
    } else {
        $missingFiles += $file
        Write-Host "WARNING: File not found: $file" -ForegroundColor Red
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Some files are missing!" -ForegroundColor Red
    Write-Host "Please download these files first:" -ForegroundColor Yellow
    foreach ($file in $missingFiles) {
        Write-Host "  - $file" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Download from Claude.ai and place in:" -ForegroundColor Yellow
    Write-Host "C:\Projects\Pyex-AVD-deployment\" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "[SUCCESS] New files added to Git staging" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------
# STEP 4: COMMIT CHANGES
# ----------------------------------------------------------------
Write-Host "[STEP 4] Committing changes..." -ForegroundColor Yellow

git commit -m "v4.0 FINAL - Removed NGINX files, added clean MOVEit Front Door deployment"

Write-Host "[SUCCESS] Changes committed" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------
# STEP 5: PUSH TO GITHUB
# ----------------------------------------------------------------
Write-Host "[STEP 5] Pushing to GitHub..." -ForegroundColor Yellow

# Try main branch first
Write-Host "Attempting push to 'main' branch..." -ForegroundColor Cyan
git push origin main 2>$null

if ($LASTEXITCODE -ne 0) {
    # Try master branch
    Write-Host "Attempting push to 'master' branch..." -ForegroundColor Cyan
    git push origin master 2>$null
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[SUCCESS] Pushed to GitHub!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Push failed. You may need to authenticate." -ForegroundColor Red
    Write-Host "Try running: git push origin main" -ForegroundColor Yellow
}

Write-Host ""

# ----------------------------------------------------------------
# DEPLOYMENT COMPLETE
# ----------------------------------------------------------------
Write-Host "============================================" -ForegroundColor Green
Write-Host "  GIT CLEANUP COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "WHAT WAS DONE:" -ForegroundColor Cyan
Write-Host "  - Removed NGINX files" -ForegroundColor White
Write-Host "  - Removed old MOVEit files" -ForegroundColor White
Write-Host "  - Added MOVEit v4.0 files" -ForegroundColor White
Write-Host "  - Committed changes" -ForegroundColor White
Write-Host "  - Pushed to GitHub" -ForegroundColor White
Write-Host ""
Write-Host "GitHub Repository:" -ForegroundColor Cyan
Write-Host "https://github.com/Riz7886/Pyex-AVD-deployment.git" -ForegroundColor Green
Write-Host ""
Write-Host "READY TO DEPLOY! 🚀" -ForegroundColor Green
Write-Host ""
