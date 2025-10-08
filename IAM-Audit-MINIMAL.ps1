<#
.SYNOPSIS
    Minimal IAM Audit - Works on ANY laptop
.DESCRIPTION
    Uses only Get-AzRoleAssignment - nothing else
    NO MODULE REQUIREMENTS
#>

param(
    [string]$OutputPath = ".\IAM-Reports"
)

Write-Host "IAM Security Audit - Minimal Version" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Create output folder
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Check connection
Write-Host "Checking Azure connection..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        Write-Host "Not connected. Please run: Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
    Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please run: Connect-AzAccount" -ForegroundColor Yellow
    exit 1
}

# Get role assignments
Write-Host "Getting role assignments..." -ForegroundColor Yellow
try {
    $assignments = Get-AzRoleAssignment -ErrorAction Stop
    Write-Host "Found $($assignments.Count) role assignments" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Error getting assignments: $_" -ForegroundColor Red
    exit 1
}

# Analyze
$findings = @()
$users = $assignments | Where-Object { $_.ObjectType -eq "User" }
$sps = $assignments | Where-Object { $_.ObjectType -eq "ServicePrincipal" }
$groups = $assignments | Where-Object { $_.ObjectType -eq "Group" }
$guests = $users | Where-Object { $_.SignInName -like "*#EXT#*" }

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total Assignments: $($assignments.Count)"
Write-Host "  Users: $(($users | Select-Object -Unique ObjectId).Count)"
Write-Host "  Service Principals: $(($sps | Select-Object -Unique ObjectId).Count)"
Write-Host "  Groups: $(($groups | Select-Object -Unique ObjectId).Count)"
Write-Host "  Guest Users: $(($guests | Select-Object -Unique ObjectId).Count)"
Write-Host ""

# Find issues
Write-Host "Finding security issues..." -ForegroundColor Yellow

# Users with Owner
$userOwners = $users | Where-Object { $_.RoleDefinitionName -eq "Owner" } | Select-Object -Unique DisplayName, SignInName
foreach ($u in $userOwners) {
    $findings += [PSCustomObject]@{
        Severity = "HIGH"
        Type = "User with Owner Role"
        Resource = $u.DisplayName
        Email = $u.SignInName
        Recommendation = "Review if Owner role is necessary"
    }
}

# Guests with privileges
$guestPrivileged = $guests | Where-Object { 
    $_.RoleDefinitionName -in @("Owner", "Contributor", "User Access Administrator")
} | Select-Object -Unique DisplayName, RoleDefinitionName
foreach ($g in $guestPrivileged) {
    $findings += [PSCustomObject]@{
        Severity = "CRITICAL"
        Type = "Guest User with Elevated Access"
        Resource = $g.DisplayName
        Email = "Guest"
        Recommendation = "Remove or downgrade guest permissions"
    }
}

# Service Principals with Owner
$spOwners = $sps | Where-Object { $_.RoleDefinitionName -eq "Owner" } | Select-Object -Unique DisplayName
foreach ($sp in $spOwners) {
    $findings += [PSCustomObject]@{
        Severity = "CRITICAL"
        Type = "Service Principal with Owner"
        Resource = $sp.DisplayName
        Email = "N/A"
        Recommendation = "Use Managed Identity with limited permissions"
    }
}

# Orphaned assignments
$orphaned = $assignments | Where-Object { $_.ObjectType -eq "Unknown" }
foreach ($o in $orphaned) {
    $findings += [PSCustomObject]@{
        Severity = "MEDIUM"
        Type = "Orphaned Assignment"
        Resource = $o.ObjectId
        Email = "N/A"
        Recommendation = "Remove deleted identity assignment"
    }
}

Write-Host "Found $($findings.Count) security issues" -ForegroundColor $(if ($findings.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# Save reports
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = Join-Path $OutputPath "IAM-Findings-$timestamp.csv"
$txtFile = Join-Path $OutputPath "IAM-Report-$timestamp.txt"

# CSV
$findings | Export-Csv -Path $csvFile -NoTypeInformation

# Text report
$report = @"
IAM SECURITY AUDIT REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Subscription: $($context.Subscription.Name)

SUMMARY
=======
Total Role Assignments: $($assignments.Count)
Users: $(($users | Select-Object -Unique ObjectId).Count)
Service Principals: $(($sps | Select-Object -Unique ObjectId).Count)
Groups: $(($groups | Select-Object -Unique ObjectId).Count)
Guest Users: $(($guests | Select-Object -Unique ObjectId).Count)

SECURITY FINDINGS: $($findings.Count)
Critical: $(($findings | Where-Object Severity -eq "CRITICAL").Count)
High: $(($findings | Where-Object Severity -eq "HIGH").Count)
Medium: $(($findings | Where-Object Severity -eq "MEDIUM").Count)

DETAILED FINDINGS
=================

"@

foreach ($f in ($findings | Sort-Object Severity)) {
    $report += @"

[$($f.Severity)] $($f.Type)
Resource: $($f.Resource)
Recommendation: $($f.Recommendation)

"@
}

$report | Out-File -FilePath $txtFile -Encoding UTF8

Write-Host "Reports saved:" -ForegroundColor Green
Write-Host "  CSV: $csvFile"
Write-Host "  TXT: $txtFile"
Write-Host ""

# Display findings
if ($findings.Count -gt 0) {
    Write-Host "FINDINGS:" -ForegroundColor Yellow
    Write-Host "=========" -ForegroundColor Yellow
    $findings | Format-Table Severity, Type, Resource -AutoSize
} else {
    Write-Host "No security issues found!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Audit complete!" -ForegroundColor Green