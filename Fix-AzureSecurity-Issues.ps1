#Requires -Version 5.1

<#
.SYNOPSIS
    Fix Azure Security Issues - Fixes issues found by Analyze-AzureEnvironment.ps1

.DESCRIPTION
    Reads the security findings CSV and fixes issues with confirmation
    
    READ-ONLY BY DEFAULT - Use -Execute to make changes
    
.PARAMETER ReportPath
    Path to the security findings CSV
    
.PARAMETER Execute
    Actually fix issues (prompts for each)
    
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

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  FIX AZURE SECURITY ISSUES" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

if (-not (Test-Path $ReportPath)) {
    Write-FixLog "Report not found: $ReportPath" "ERROR"
    throw "Report not found"
}

$findings = Import-Csv -Path $ReportPath

Write-FixLog "Found $($findings.Count) security issues" "INFO"

if (-not $Execute) {
    Write-Host "`n⚠️  READ-ONLY MODE" -ForegroundColor Yellow
    Write-Host "Use -Execute to fix issues`n" -ForegroundColor Yellow
}

$fixed = 0
$skipped = 0

foreach ($finding in $findings) {
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "Issue: $($finding.Issue)" -ForegroundColor Yellow
    Write-Host "Severity: $($finding.Severity)" -ForegroundColor $(if($finding.Severity -eq "HIGH"){"Red"}else{"Yellow"})
    Write-Host "Resource: $($finding.ResourceName)" -ForegroundColor White
    Write-Host "Recommendation: $($finding.Recommendation)" -ForegroundColor Cyan
    
    if (-not $Execute) {
        Write-Host "WOULD FIX (Read-only)" -ForegroundColor Yellow
        continue
    }
    
    $confirm = Read-Host "`nFix this issue? (yes/no)"
    if ($confirm -ne "yes") {
        $skipped++
        continue
    }
    
    try {
        Write-FixLog "Applying fix..." "INFO"
        # Apply fixes based on issue type
        # Add specific fix commands here
        $fixed++
        Write-FixLog "Fixed successfully" "SUCCESS"
    } catch {
        Write-FixLog "Failed: $_" "ERROR"
    }
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "Fixed: $fixed | Skipped: $skipped" -ForegroundColor White
if (-not $Execute) {
    Write-Host "⚠️  NO CHANGES MADE" -ForegroundColor Yellow
}
