#Requires -Version 5.1

<#
.SYNOPSIS
    Automatically Fix Fancy Characters in Scripts

.DESCRIPTION
    Removes all non-ASCII characters (emojis, boxes, fancy symbols)
    from the 3 scripts that have issues
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectPath = "D:\PYEX-AVD-Deployment"
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  FIXING FANCY CHARACTERS IN SCRIPTS"
Write-Host "=============================================================="
Write-Host ""

# Scripts that need fixing
$scriptsToFix = @(
    "Audit-Complete.ps1",
    "Deploy-AVD.ps1",
    "Execute-AzureFixes.ps1"
)

# Create backup
$backupPath = Join-Path $ProjectPath "Backup-Character-Fix"
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
}

Write-Host "Creating backup..." -ForegroundColor Cyan
foreach ($script in $scriptsToFix) {
    $sourcePath = Join-Path $ProjectPath $script
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $backupPath -Force
        Write-Host "  Backed up: $script" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Cleaning scripts..." -ForegroundColor Cyan
Write-Host ""

$fixedCount = 0

foreach ($scriptName in $scriptsToFix) {
    $scriptPath = Join-Path $ProjectPath $scriptName
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "SKIP: $scriptName (not found)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Processing: $scriptName" -ForegroundColor Yellow
    
    try {
        # Read the file
        $content = Get-Content -Path $scriptPath -Raw -Encoding UTF8
        
        # Count fancy characters before
        $fancyCharsBefore = ([regex]::Matches($content, '[^\x00-\x7F]')).Count
        
        if ($fancyCharsBefore -eq 0) {
            Write-Host "  Already clean!" -ForegroundColor Green
            continue
        }
        
        # Remove all non-ASCII characters (fancy characters, emojis, boxes)
        # Replace them with spaces or nothing
        $cleanContent = $content -replace '[^\x00-\x7F]', ''
        
        # Clean up multiple spaces
        $cleanContent = $cleanContent -replace '  +', ' '
        
        # Clean up empty lines with just spaces
        $cleanContent = $cleanContent -replace '(?m)^\s+$', ''
        
        # Save the cleaned content
        $cleanContent | Out-File -FilePath $scriptPath -Encoding UTF8 -NoNewline
        
        Write-Host "  Removed $fancyCharsBefore fancy characters" -ForegroundColor Green
        Write-Host "  File cleaned successfully!" -ForegroundColor Green
        $fixedCount++
        
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "=============================================================="
Write-Host "  CLEANUP COMPLETE"
Write-Host "=============================================================="
Write-Host ""
Write-Host "Scripts fixed: $fixedCount"
Write-Host "Backup location: $backupPath"
Write-Host ""

# Verify the fix
Write-Host "Verifying scripts are now clean..." -ForegroundColor Cyan
Write-Host ""

$stillHaveIssues = @()

foreach ($scriptName in $scriptsToFix) {
    $scriptPath = Join-Path $ProjectPath $scriptName
    
    if (Test-Path $scriptPath) {
        $content = Get-Content -Path $scriptPath -Raw
        
        if ($content -match '[^\x00-\x7F]') {
            $stillHaveIssues += $scriptName
            Write-Host "STILL HAS ISSUES: $scriptName" -ForegroundColor Red
        } else {
            Write-Host "CLEAN: $scriptName" -ForegroundColor Green
        }
    }
}

Write-Host ""

if ($stillHaveIssues.Count -eq 0) {
    Write-Host "=============================================================="
    Write-Host "  SUCCESS - ALL SCRIPTS ARE NOW CLEAN"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "All 3 scripts are now clean and ready to use!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: Push to GitHub" -ForegroundColor Yellow
    Write-Host "git add ." -ForegroundColor White
    Write-Host "git commit -m 'Fixed fancy characters in scripts'" -ForegroundColor White
    Write-Host "git push origin main" -ForegroundColor White
} else {
    Write-Host "=============================================================="
    Write-Host "  WARNING - SOME SCRIPTS STILL HAVE ISSUES"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Scripts that still need manual fixing:" -ForegroundColor Yellow
    $stillHaveIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""
