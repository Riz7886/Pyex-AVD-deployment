#Requires -Version 5.1
<#
.SYNOPSIS
    Run All Azure Audit Scripts
.DESCRIPTION
    Executes all 9 audit scripts and generates comprehensive reports
#>

param()

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AZURE COMPREHENSIVE AUDIT SUITE" -ForegroundColor Cyan
Write-Host "  Running All 9 Security and Compliance Audits" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're in the right directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (!$scriptDir) {
    $scriptDir = Get-Location
}

Write-Host "Script Directory: $scriptDir" -ForegroundColor Cyan
Write-Host ""

# List of audit scripts to run
$auditScripts = @(
    "1-RBAC-Audit.ps1",
    "2-NSG-Audit.ps1",
    "3-Encryption-Audit.ps1",
    "4-Backup-Audit.ps1",
    "5-Cost-Tagging-Audit.ps1",
    "6-Policy-Compliance-Audit.ps1",
    "7-Identity-AAD-Audit.ps1",
    "8-SecurityCenter-Audit.ps1",
    "9-AuditLog-Collection.ps1"
)

Write-Host "Checking for audit scripts..." -ForegroundColor Yellow
Write-Host ""

# Check which scripts exist
$foundScripts = @()
$missingScripts = @()

foreach ($script in $auditScripts) {
    $scriptPath = Join-Path $scriptDir $script
    if (Test-Path $scriptPath) {
        $foundScripts += $script
        Write-Host "  [OK] Found: $script" -ForegroundColor Green
    } else {
        $missingScripts += $script
        Write-Host "  [MISSING] Not found: $script" -ForegroundColor Red
    }
}

Write-Host ""

if ($foundScripts.Count -eq 0) {
    Write-Host "ERROR: No audit scripts found in $scriptDir" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you're running this from the correct directory." -ForegroundColor Yellow
    Write-Host "Expected location: D:\Azure-Production-Scripts\" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($foundScripts.Count) of $($auditScripts.Count) audit scripts" -ForegroundColor Cyan
Write-Host ""

# Ask for confirmation
Write-Host "Ready to run $($foundScripts.Count) audit scripts." -ForegroundColor Yellow
Write-Host ""
Write-Host "Each script will:" -ForegroundColor White
Write-Host "  - Connect to Azure (you'll login once)" -ForegroundColor Gray
Write-Host "  - Select a subscription" -ForegroundColor Gray
Write-Host "  - Collect complete inventory" -ForegroundColor Gray
Write-Host "  - Generate HTML + CSV reports" -ForegroundColor Gray
Write-Host ""

$response = Read-Host "Continue? (Y/N)"
if ($response -ne 'Y' -and $response -ne 'y') {
    Write-Host "Cancelled by user" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  STARTING AUDIT EXECUTION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$completedCount = 0
$failedCount = 0
$results = @()

foreach ($script in $foundScripts) {
    $scriptPath = Join-Path $scriptDir $script
    
    Write-Host ""
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Running: $script" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Run the script
        & $scriptPath
        
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            $completedCount++
            $results += [PSCustomObject]@{
                Script = $script
                Status = "Success"
                Message = "Completed successfully"
            }
            Write-Host ""
            Write-Host "[SUCCESS] $script completed" -ForegroundColor Green
        } else {
            $failedCount++
            $results += [PSCustomObject]@{
                Script = $script
                Status = "Failed"
                Message = "Exit code: $LASTEXITCODE"
            }
            Write-Host ""
            Write-Host "[FAILED] $script failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        }
    } catch {
        $failedCount++
        $results += [PSCustomObject]@{
            Script = $script
            Status = "Error"
            Message = $_.Exception.Message
        }
        Write-Host ""
        Write-Host "[ERROR] $script encountered an error:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  AUDIT SUITE EXECUTION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total Scripts: $($foundScripts.Count)" -ForegroundColor White
Write-Host "  Completed: $completedCount" -ForegroundColor Green
Write-Host "  Failed: $failedCount" -ForegroundColor $(if($failedCount -gt 0){"Red"}else{"Gray"})
Write-Host ""

# Show results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
Write-Host ""
$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Reports Location:" -ForegroundColor Cyan
Write-Host "  $scriptDir\Reports\" -ForegroundColor White
Write-Host ""
Write-Host "Look for HTML and CSV files in the Reports folder" -ForegroundColor Yellow
Write-Host ""

# Check if Reports folder exists and show files
$reportsPath = Join-Path $scriptDir "Reports"
if (Test-Path $reportsPath) {
    $reportFiles = Get-ChildItem $reportsPath -Filter "*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 10
    if ($reportFiles.Count -gt 0) {
        Write-Host "Recent Reports:" -ForegroundColor Cyan
        foreach ($file in $reportFiles) {
            Write-Host "  - $($file.Name)" -ForegroundColor White
        }
        Write-Host ""
        
        # Ask if user wants to open the most recent report
        $response = Read-Host "Open the most recent report in browser? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            Start-Process $reportFiles[0].FullName
        }
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
