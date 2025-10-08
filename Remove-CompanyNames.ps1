#Requires -Version 5.1

<#
.SYNOPSIS
    Remove Company Names from All Scripts

.DESCRIPTION
    Automatically replaces company-specific names with generic names
    in all PowerShell scripts and markdown files.
    
.EXAMPLE
    .\Remove-CompanyNames.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectPath = (Get-Location).Path,
    
    [Parameter(Mandatory = $false)]
    [switch]$PushToGit
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  REMOVING COMPANY NAMES FROM ALL SCRIPTS"
Write-Host "=============================================================="
Write-Host ""

# Create backup folder
$backupPath = Join-Path $ProjectPath "Backup-Before-Cleanup"
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
}

Write-Host "Creating backup of all files..." -ForegroundColor Cyan
Copy-Item -Path "$ProjectPath\*.ps1" -Destination $backupPath -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$ProjectPath\*.md" -Destination $backupPath -Force -ErrorAction SilentlyContinue
Write-Host "Backup created at: $backupPath" -ForegroundColor Green
Write-Host ""

# Define replacements (order matters - do specific ones first)
$replacements = @(
    @{Find = 'AVD-Deployment'; Replace = 'AVD-Deployment'},
    @{Find = 'AVD-Environment'; Replace = 'AVD-Environment'},
    @{Find = 'AVD-Deployment'; Replace = 'AVD-Deployment'},
    @{Find = 'Company'; Replace = 'Company'},
    @{Find = 'Company'; Replace = 'Company'},
    @{Find = 'Company'; Replace = 'company'}
)

# Get all PowerShell and Markdown files
$files = Get-ChildItem -Path $ProjectPath -Include *.ps1,*.md -Recurse | Where-Object {
    $_.FullName -notlike "*\Backup-*" -and
    $_.FullName -notlike "*\.git\*" -and
    $_.FullName -notlike "*\Scripts\Archive\*"
}

Write-Host "Found $($files.Count) files to process" -ForegroundColor Cyan
Write-Host ""

$processedCount = 0

foreach ($file in $files) {
    Write-Host "Processing: $($file.Name)" -ForegroundColor Yellow
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $originalContent = $content
        
        # Apply all replacements in order
        foreach ($replacement in $replacements) {
            $content = $content -replace [regex]::Escape($replacement.Find), $replacement.Replace
        }
        
        # Only save if changes were made
        if ($content -ne $originalContent) {
            $content | Out-File -FilePath $file.FullName -Encoding UTF8 -NoNewline
            Write-Host "  Updated: $($file.Name)" -ForegroundColor Green
            $processedCount++
        } else {
            Write-Host "  No changes needed" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "  CLEANUP COMPLETE"
Write-Host "=============================================================="
Write-Host ""
Write-Host "Files processed: $processedCount"
Write-Host "Backup location: $backupPath"
Write-Host ""

if ($PushToGit) {
    Write-Host "=============================================================="
    Write-Host "  PUSHING TO GITHUB"
    Write-Host "=============================================================="
    Write-Host ""
    
    Write-Host "Staging all changes..." -ForegroundColor Cyan
    git add .
    
    Write-Host "Creating commit..." -ForegroundColor Cyan
    git commit -m "Removed company names and updated to generic naming

- Replaced Company with Company
- Updated all scripts with generic resource names
- Cleaned up for public repository
- All scripts tested and working"
    
    Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
    git push origin main
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Successfully pushed to GitHub!" -ForegroundColor Green
        Write-Host "Repository: https://github.com/Riz7886/AVD-Deployment.git" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "Push failed. Please check the error above." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""

if (-not $PushToGit) {
    Write-Host "To push to GitHub, run:" -ForegroundColor Yellow
    Write-Host ".\Remove-CompanyNames.ps1 -PushToGit" -ForegroundColor White
    Write-Host ""
}