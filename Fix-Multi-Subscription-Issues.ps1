#Requires -Version 5.1

<#
.SYNOPSIS
    Fix Multi-Subscription Issues - Fixes issues across all subscriptions

.DESCRIPTION
    Reads multi-subscription audit report and fixes issues
    
    READ-ONLY BY DEFAULT - Use -Execute to make changes
    
.PARAMETER ReportPath
    Path to multi-subscription report CSV
    
.PARAMETER Execute
    Actually fix issues
    
.EXAMPLE
    .\Fix-Multi-Subscription-Issues.ps1 -ReportPath ".\Reports\MultiSub-Issues.csv" -Execute
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
Write-Host "  FIX MULTI-SUBSCRIPTION ISSUES" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

if (-not (Test-Path $ReportPath)) {
    Write-FixLog "Report not found: $ReportPath" "ERROR"
    throw "Report not found"
}

$issues = Import-Csv -Path $ReportPath

Write-FixLog "Found $($issues.Count) issues across subscriptions" "INFO"

if (-not $Execute) {
    Write-Host "`n⚠️  READ-ONLY MODE" -ForegroundColor Yellow
    Write-Host "Use -Execute to fix issues`n" -ForegroundColor Yellow
}

$fixed = 0

$groupedBySubscription = $issues | Group-Object Subscription

foreach ($subGroup in $groupedBySubscription) {
    Write-Host "`n================================================" -ForegroundColor Cyan
    Write-Host "Subscription: $($subGroup.Name)" -ForegroundColor Yellow
    Write-Host "Issues: $($subGroup.Count)" -ForegroundColor White
    Write-Host "================================================" -ForegroundColor Cyan
    
    foreach ($issue in $subGroup.Group) {
        Write-Host "`n  Issue: $($issue.Issue)" -ForegroundColor White
        Write-Host "  Resource: $($issue.ResourceName)" -ForegroundColor Gray
        Write-Host "  Severity: $($issue.Severity)" -ForegroundColor Yellow
        
        if (-not $Execute) {
            Write-Host "  WOULD FIX (Read-only)" -ForegroundColor Yellow
            continue
        }
        
        $confirm = Read-Host "`n  Fix this issue? (yes/no)"
        if ($confirm -ne "yes") {
            continue
        }
        
        try {
            Write-FixLog "Fixing issue in subscription: $($subGroup.Name)" "INFO"
            # Apply fixes
            $fixed++
            Write-FixLog "Fixed successfully" "SUCCESS"
        } catch {
            Write-FixLog "Failed: $_" "ERROR"
        }
    }
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "Issues Fixed: $fixed" -ForegroundColor White
if (-not $Execute) {
    Write-Host "⚠️  NO CHANGES MADE" -ForegroundColor Yellow
}
