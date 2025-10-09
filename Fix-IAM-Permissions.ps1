#Requires -Version 5.1

<#
.SYNOPSIS
    Fix IAM Permission Issues - Fixes excessive permissions found by IAM audits

.DESCRIPTION
    Reads IAM audit reports and removes excessive permissions
    
    READ-ONLY BY DEFAULT - Use -Execute to make changes
    
.PARAMETER ReportPath
    Path to IAM audit report CSV
    
.PARAMETER Execute
    Actually remove permissions (prompts for each)
    
.EXAMPLE
    .\Fix-IAM-Permissions.ps1 -ReportPath ".\Reports\IAM-Issues.csv" -Execute
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
Write-Host "  FIX IAM PERMISSIONS" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

if (-not (Test-Path $ReportPath)) {
    Write-FixLog "Report not found: $ReportPath" "ERROR"
    throw "Report not found"
}

$permissions = Import-Csv -Path $ReportPath

Write-FixLog "Found $($permissions.Count) permission issues" "INFO"

if (-not $Execute) {
    Write-Host "`n⚠️  READ-ONLY MODE" -ForegroundColor Yellow
    Write-Host "Use -Execute to remove permissions`n" -ForegroundColor Yellow
}

$removed = 0

foreach ($perm in $permissions) {
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "User: $($perm.User)" -ForegroundColor White
    Write-Host "Role: $($perm.Role)" -ForegroundColor Yellow
    Write-Host "Scope: $($perm.Scope)" -ForegroundColor Gray
    Write-Host "Issue: $($perm.Issue)" -ForegroundColor Red
    
    if (-not $Execute) {
        Write-Host "WOULD REMOVE (Read-only)" -ForegroundColor Yellow
        continue
    }
    
    $confirm = Read-Host "`nRemove this permission? (yes/no)"
    if ($confirm -ne "yes") {
        continue
    }
    
    try {
        Write-FixLog "Removing permission..." "INFO"
        az role assignment delete --assignee $perm.User --role $perm.Role --scope $perm.Scope
        $removed++
        Write-FixLog "Removed successfully" "SUCCESS"
    } catch {
        Write-FixLog "Failed: $_" "ERROR"
    }
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "Permissions Removed: $removed" -ForegroundColor White
if (-not $Execute) {
    Write-Host "⚠️  NO CHANGES MADE" -ForegroundColor Yellow
}
