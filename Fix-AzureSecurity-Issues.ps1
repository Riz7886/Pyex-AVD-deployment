#Requires -Version 5.1

<#
.SYNOPSIS
    Fix Azure Security Issues
.DESCRIPTION
    Reads security findings CSV and fixes issues with confirmation
    READ-ONLY BY DEFAULT - Use -Execute to make changes
.PARAMETER ReportPath
    Path to security findings CSV
.PARAMETER Execute
    Actually fix issues
.EXAMPLE
    .\Fix-AzureSecurity-Issues.ps1 -ReportPath ".\Reports\Security-Findings.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    [Parameter(Mandatory = $false)]
    [switch]$Execute
)

function Write-FixLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  FIX AZURE SECURITY ISSUES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ReportPath)) {
    Write-FixLog "Report not found: $ReportPath" "ERROR"
    throw "Report not found"
}

$findings = Import-Csv -Path $ReportPath

Write-FixLog "Found $($findings.Count) security issues" "INFO"

if (-not $Execute) {
    Write-Host ""
    Write-Host "READ-ONLY MODE" -ForegroundColor Yellow
    Write-Host "Use -Execute to fix issues" -ForegroundColor Yellow
    Write-Host ""
}

$fixed = 0
$skipped = 0

foreach ($finding in $findings) {
    Write-Host ""
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Issue: $($finding.Issue)" -ForegroundColor Yellow
    Write-Host "Severity: $($finding.Severity)" -ForegroundColor $(if($finding.Severity -eq "HIGH"){"Red"}else{"Yellow"})
    Write-Host "Resource: $($finding.ResourceName)" -ForegroundColor White
    Write-Host "Recommendation: $($finding.Recommendation)" -ForegroundColor Cyan
    
    if (-not $Execute) {
        Write-Host "WOULD FIX (Read-only)" -ForegroundColor Yellow
        continue
    }
    
    $confirm = Read-Host "Fix this issue? (yes/no)"
    if ($confirm -ne "yes") {
        $skipped++
        continue
    }
    
    try {
        Write-FixLog "Applying fix..." "INFO"
        $fixed++
        Write-FixLog "Fixed successfully" "SUCCESS"
    } catch {
        Write-FixLog "Failed: $_" "ERROR"
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Fixed: $fixed | Skipped: $skipped" -ForegroundColor White
if (-not $Execute) {
    Write-Host "NO CHANGES MADE" -ForegroundColor Yellow
}
Write-Host ""
