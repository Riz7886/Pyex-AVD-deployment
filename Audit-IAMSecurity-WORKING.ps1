#Requires -Version 5.1

<#
.SYNOPSIS
    IAM Security Audit - Work Laptop Compatible Version
.DESCRIPTION
    Works with basic Azure modules only
    NO CHANGES to Azure - Read only
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\IAM-Security-Reports"
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  IAM SECURITY AUDIT - WORKING VERSION"
Write-Host "=============================================================="
Write-Host ""

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$startTime = Get-Date
$findings = @()
$statistics = @{
    TotalUsers = 0
    TotalServicePrincipals = 0
    TotalRoleAssignments = 0
    TotalGroups = 0
    OverprivilegedAccounts = 0
    GuestUsers = 0
    TotalFindings = 0
    CriticalFindings = 0
    HighFindings = 0
    MediumFindings = 0
    LowFindings = 0
    RiskScore = 0
}

Write-Host "Connecting to Azure..." -ForegroundColor Cyan

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Connecting..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Failed to connect: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Analyzing IAM configuration..." -ForegroundColor Cyan
Write-Host ""

# Get all role assignments
try {
    Write-Host "Getting role assignments..." -ForegroundColor Yellow
    $allAssignments = Get-AzRoleAssignment
    $statistics.TotalRoleAssignments = $allAssignments.Count
    Write-Host "Found $($allAssignments.Count) role assignments" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Error getting role assignments: $_" -ForegroundColor Red
    exit 1
}

# Analyze users
Write-Host "Analyzing users..." -ForegroundColor Yellow
$userAssignments = $allAssignments | Where-Object { $_.ObjectType -eq "User" }
$statistics.TotalUsers = ($userAssignments | Select-Object -Unique ObjectId).Count

foreach ($assignment in ($userAssignments | Group-Object ObjectId)) {
    $user = $assignment.Group[0]
    
    if ($assignment.Group.RoleDefinitionName -contains "Owner") {
        $findings += [PSCustomObject]@{
            Severity = "High"
            Category = "User Privileges"
            Resource = $user.DisplayName
            Description = "User has Owner role"
            Recommendation = "Review if Owner role is necessary"
        }
        $statistics.OverprivilegedAccounts++
    }
}

# Analyze guest users
$guestAssignments = $userAssignments | Where-Object { $_.SignInName -like "*#EXT#*" }
$statistics.GuestUsers = ($guestAssignments | Select-Object -Unique ObjectId).Count

foreach ($guest in ($guestAssignments | Group-Object ObjectId)) {
    $guestUser = $guest.Group[0]
    $privilegedRoles = @("Owner", "Contributor", "User Access Administrator")
    
    if ($guest.Group.RoleDefinitionName | Where-Object { $_ -in $privilegedRoles }) {
        $findings += [PSCustomObject]@{
            Severity = "Critical"
            Category = "Guest User Security"
            Resource = $guestUser.DisplayName
            Description = "Guest user has elevated permissions"
            Recommendation = "Remove guest user or downgrade permissions"
        }
    }
}

# Analyze service principals
Write-Host "Analyzing service principals..." -ForegroundColor Yellow
$spAssignments = $allAssignments | Where-Object { $_.ObjectType -eq "ServicePrincipal" }
$statistics.TotalServicePrincipals = ($spAssignments | Select-Object -Unique ObjectId).Count

foreach ($sp in ($spAssignments | Group-Object ObjectId)) {
    $servicePrincipal = $sp.Group[0]
    
    if ($sp.Group.RoleDefinitionName -contains "Owner") {
        $findings += [PSCustomObject]@{
            Severity = "Critical"
            Category = "Service Principal Security"
            Resource = $servicePrincipal.DisplayName
            Description = "Service Principal has Owner role"
            Recommendation = "Remove Owner role. Use Managed Identities"
        }
    }
}

# Analyze orphaned assignments
Write-Host "Checking for orphaned assignments..." -ForegroundColor Yellow
$orphanedAssignments = $allAssignments | Where-Object { 
    $_.ObjectType -eq "Unknown" -or [string]::IsNullOrEmpty($_.DisplayName)
}

foreach ($orphaned in $orphanedAssignments) {
    $findings += [PSCustomObject]@{
        Severity = "Medium"
        Category = "Orphaned Assignment"
        Resource = $orphaned.ObjectId
        Description = "Orphaned role assignment (identity deleted)"
        Recommendation = "Remove orphaned assignment"
    }
}

# Analyze groups
Write-Host "Analyzing groups..." -ForegroundColor Yellow
$groupAssignments = $allAssignments | Where-Object { $_.ObjectType -eq "Group" }
$statistics.TotalGroups = ($groupAssignments | Select-Object -Unique ObjectId).Count

foreach ($group in ($groupAssignments | Group-Object ObjectId)) {
    $groupInfo = $group.Group[0]
    
    if ($group.Group.RoleDefinitionName -contains "Owner") {
        $findings += [PSCustomObject]@{
            Severity = "High"
            Category = "Group Permissions"
            Resource = $groupInfo.DisplayName
            Description = "Group has Owner role"
            Recommendation = "Review group membership"
        }
    }
}

Write-Host ""
Write-Host "Calculating risk score..." -ForegroundColor Cyan

$statistics.TotalFindings = $findings.Count
$statistics.CriticalFindings = ($findings | Where-Object Severity -eq "Critical").Count
$statistics.HighFindings = ($findings | Where-Object Severity -eq "High").Count
$statistics.MediumFindings = ($findings | Where-Object Severity -eq "Medium").Count
$statistics.LowFindings = ($findings | Where-Object Severity -eq "Low").Count

$statistics.RiskScore = [Math]::Min(100, (
    $statistics.CriticalFindings * 10 +
    $statistics.HighFindings * 5 +
    $statistics.MediumFindings * 2 +
    $statistics.LowFindings * 1
))

$riskLevel = switch ($statistics.RiskScore) {
    {$_ -ge 80} { "CRITICAL"; break }
    {$_ -ge 50} { "HIGH"; break }
    {$_ -ge 20} { "MEDIUM"; break }
    default { "LOW" }
}

Write-Host ""
Write-Host "Generating reports..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDate = Get-Date -Format "MMMM dd, yyyy HH:mm:ss"
$csvFile = Join-Path $ReportPath "IAM_Findings_$timestamp.csv"
$htmlFile = Join-Path $ReportPath "IAM_Report_$timestamp.html"

$findings | Export-Csv -Path $csvFile -NoTypeInformation

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
<title>IAM Security Report</title>
<style>
body { font-family: Arial; padding: 20px; background: #f5f5f5; }
.header { background: #0078d4; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
.stat { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #0078d4; }
.finding { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #ff9800; }
.critical { border-left-color: #f44336; }
.high { border-left-color: #ff9800; }
.medium { border-left-color: #ffc107; }
.low { border-left-color: #8bc34a; }
h3 { margin-top: 0; }
</style>
</head>
<body>
<div class="header">
<h1>IAM Security Audit Report</h1>
<p>Generated: $reportDate</p>
<p>Subscription: $($context.Subscription.Name)</p>
<p>Risk Score: $($statistics.RiskScore)/100 - $riskLevel</p>
</div>
<div class="stat">
<h3>Summary</h3>
<p>Total Findings: $($statistics.TotalFindings)</p>
<p>Critical: $($statistics.CriticalFindings)</p>
<p>High: $($statistics.HighFindings)</p>
<p>Medium: $($statistics.MediumFindings)</p>
<p>Low: $($statistics.LowFindings)</p>
<hr>
<p>Total Users: $($statistics.TotalUsers)</p>
<p>Total Service Principals: $($statistics.TotalServicePrincipals)</p>
<p>Total Groups: $($statistics.TotalGroups)</p>
<p>Guest Users: $($statistics.GuestUsers)</p>
<p>Overprivileged Accounts: $($statistics.OverprivilegedAccounts)</p>
</div>
"@

foreach ($finding in ($findings | Sort-Object Severity)) {
    $htmlReport += @"
<div class="finding $($finding.Severity.ToLower())">
<h3>$($finding.Category) - $($finding.Severity)</h3>
<p><strong>Resource:</strong> $($finding.Resource)</p>
<p><strong>Description:</strong> $($finding.Description)</p>
<p><strong>Recommendation:</strong> $($finding.Recommendation)</p>
</div>
"@
}

$htmlReport += "</body></html>"
$htmlReport | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host ""
Write-Host "=============================================================="
Write-Host "  AUDIT COMPLETE"
Write-Host "=============================================================="
Write-Host ""
Write-Host "Risk Score: $($statistics.RiskScore)/100 - $riskLevel" -ForegroundColor $(
    switch ($riskLevel) {
        "CRITICAL" { "Red" }
        "HIGH" { "Yellow" }
        "MEDIUM" { "Yellow" }
        "LOW" { "Green" }
    }
)
Write-Host "Total Findings: $($statistics.TotalFindings)"
Write-Host "Critical: $($statistics.CriticalFindings)" -ForegroundColor Red
Write-Host "High: $($statistics.HighFindings)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Reports saved:"
Write-Host "HTML: $htmlFile"
Write-Host "CSV:  $csvFile"
Write-Host ""

Start-Process $htmlFile

Write-Host "Done!" -ForegroundColor Green