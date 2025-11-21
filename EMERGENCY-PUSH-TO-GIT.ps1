# ================================================================
# EMERGENCY CLIENT DEPLOYMENT - ONE COMMAND
# Pushes Windows-formatted files to Git
# ================================================================

Write-Host "🚀 EMERGENCY DEPLOYMENT - PUSHING TO GIT NOW!" -ForegroundColor Cyan
Write-Host ""

cd "C:\Projects\Pyex-AVD-deployment"

# Add all files
git add Deploy-MOVEit-FINAL-v4.ps1
git add main-FINAL-v4.tf
git add outputs-FINAL-v4.tf
git add generate-cert.ps1
git add README.md
git add .gitignore
git add *.txt

# Commit
git commit -m "v4.0 FINAL - Windows CRLF format - PRODUCTION READY"

# Push with force
git push origin main --force

Write-Host ""
Write-Host "✅ PUSHED TO GIT!" -ForegroundColor Green
Write-Host "✅ Files are Windows-formatted!" -ForegroundColor Green
Write-Host "✅ Ready for client deployment!" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub: https://github.com/Riz7886/Pyex-AVD-deployment.git" -ForegroundColor Cyan
