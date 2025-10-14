#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix RBAC Issues

.DESCRIPTION
    1. Removes stale role assignments (deleted principals)
    2. Reports users with Owner role (for review)
    
.EXAMPLE
    .\Fix-RBAC-Issues.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX RBAC ISSUES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Remove stale assignments (deleted principals)" -ForegroundColor White
Write-Host "  2. Report users with Owner role" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Getting role assignments..." -ForegroundColor Yellow
$assignmentsJson = az role assignment list --all -o json 2>&1
$assignments = $assignmentsJson | ConvertFrom-Json

Write-Host "Found: $($assignments.Count)" -ForegroundColor White

$removedStale = 0
$ownerUsers = @()

foreach ($assignment in $assignments) {
    # Fix 1: Remove stale assignments
    if ([string]::IsNullOrEmpty($assignment.principalName)) {
        Write-Host ""
        Write-Host "Removing stale assignment:" -ForegroundColor Yellow
        Write-Host "  Principal ID: $($assignment.principalId)" -ForegroundColor Gray
        Write-Host "  Role: $($assignment.roleDefinitionName)" -ForegroundColor Gray
        
        try {
            az role assignment delete --ids $assignment.id --output none
            Write-Host "  REMOVED" -ForegroundColor Green
            $removedStale++
        } catch {
            Write-Host "  ERROR" -ForegroundColor Red
        }
    }
    
    # Report 2: Owner users
    if ($assignment.roleDefinitionName -eq "Owner" -and $assignment.principalType -eq "User") {
        $ownerUsers += $assignment
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Stale assignments removed: $removedStale" -ForegroundColor Cyan
Write-Host ""

if ($ownerUsers.Count -gt 0) {
    Write-Host "USERS WITH OWNER ROLE: $($ownerUsers.Count)" -ForegroundColor Yellow
    Write-Host ""
    foreach ($owner in $ownerUsers) {
        Write-Host "  - $($owner.principalName)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "ACTION REQUIRED: Review and minimize Owner assignments" -ForegroundColor Yellow
}

Write-Host ""
