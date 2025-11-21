# ================================================================
# FIX LINE ENDINGS FOR WORK LAPTOP
# Converts Linux (LF) to Windows (CRLF) line endings
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FIXING LINE ENDINGS FOR WORK LAPTOP" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Files to fix
$filesToFix = @(
    "Deploy-MOVEit-FINAL-v4.ps1",
    "main-FINAL-v4.tf",
    "outputs-FINAL-v4.tf",
    "generate-cert.ps1",
    "Git-Cleanup-And-Push.ps1"
)

$fixedCount = 0

foreach ($file in $filesToFix) {
    if (Test-Path $file) {
        Write-Host "Fixing: $file" -ForegroundColor Yellow
        
        try {
            # Read file content
            $content = Get-Content $file -Raw
            
            # Convert LF to CRLF
            $content = $content -replace "`r`n", "`n"  # Remove existing CRLF
            $content = $content -replace "`n", "`r`n"   # Add CRLF
            
            # Save file
            [System.IO.File]::WriteAllText((Resolve-Path $file), $content)
            
            Write-Host "  ✓ Fixed: $file" -ForegroundColor Green
            $fixedCount++
        }
        catch {
            Write-Host "  ✗ Error fixing: $file" -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  - Not found: $file" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  COMPLETED!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Fixed $fixedCount file(s)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now try running:" -ForegroundColor Yellow
Write-Host "  .\Deploy-MOVEit-FINAL-v4.ps1" -ForegroundColor White
Write-Host ""
