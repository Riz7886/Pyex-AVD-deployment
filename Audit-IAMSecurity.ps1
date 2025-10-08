#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Comprehensive IAM Security Audit - Enterprise Edition

.DESCRIPTION
    Professional-grade Identity and Access Management (IAM) security audit script.
    DETECTS (Never changes production)

.PARAMETER SubscriptionId
    Azure Subscription ID to audit

.PARAMETER ReportPath
    Path where reports will be saved. Default: .\IAM-Security-Reports\

.PARAMETER SendEmail
    Switch to enable email delivery of reports

.EXAMPLE
    .\Audit-IAMSecurity.ps1

.EXAMPLE
    .\Audit-IAMSecurity.ps1 -SendEmail
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\IAM-Security-Reports",

    [Parameter(Mandatory = $false)]
    [switch]$SendEmail
)

function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "CRITICAL")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"     = "Cyan"
        "WARNING"  = "Yellow"
        "ERROR"    = "Red"
        "SUCCESS"  = "Green"
        "CRITICAL" = "Magenta"
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
    
    $logFile = Join-Path $ReportPath "audit-log.txt"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function New-SecurityFinding {
    param(
        [string]$FindingId,
        [string]$Category,
        [ValidateSet("Critical", "High", "Medium", "Low")]
        [string]$Severity,
        [string]$Resource,
        [string]$Description,
        [string]$Impact,
        [string]$Recommendation
    )
    
    return [PSCustomObject]@{
        FindingId      = $FindingId
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Category       = $Category
        Severity       = $Severity
        Resource       = $Resource
        Description    = $Description
        Impact         = $Impact
        Recommendation = $Recommendation
        Status         = "Open"
    }
}

$startTime = Get-Date
$findings = @()
$statistics = @{
    TotalUsers             = 0
    TotalServicePrincipals = 0
    TotalRoleAssignments   = 0
    TotalGroups            = 0
    OverprivilegedAccounts = 0
    StaleCredentials       = 0
    GuestUsers             = 0
    TotalFindings          = 0
    CriticalFindings       = 0
    HighFindings           = 0
    MediumFindings         = 0
    LowFindings            = 0
    RiskScore              = 0
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "  IAM SECURITY AUDIT - ENTERPRISE EDITION"
Write-Host "=============================================================="
Write-Host ""

if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

Write-AuditLog "Starting IAM Security Audit..." "INFO"

try {
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    $context = Get-AzContext
    Write-AuditLog "Connected to: $($context.Subscription.Name)" "SUCCESS"
} catch {
    Write-AuditLog "Failed to connect to Azure: $_" "ERROR"
    exit 1
}

Write-Host ""
Write-Host "Analyzing user accounts..."
Write-Host ""

$allAssignments = Get-AzRoleAssignment
$userAssignments = $allAssignments | Where-Object { $_.ObjectType -eq "User" }
$statistics.TotalUsers = ($userAssignments | Select-Object -Unique ObjectId).Count
$statistics.TotalRoleAssignments = $allAssignments.Count

foreach ($assignment in ($userAssignments | Group-Object ObjectId)) {
    $user = $assignment.Group[0]
    
    if ($assignment.Group.RoleDefinitionName -contains "Owner") {
        $findings += New-SecurityFinding `
            -FindingId "IAM-USER-001" `
            -Category "User Privileges" `
            -Severity "High" `
            -Resource $user.DisplayName `
            -Description "User has Owner role which grants full control" `
            -Impact "User can perform any action including deleting resources" `
            -Recommendation "Review if Owner role is necessary. Consider Contributor instead."
        
        $statistics.OverprivilegedAccounts++
    }
}

$guestAssignments = $userAssignments | Where-Object { $_.SignInName -like "*#EXT#*" }
$statistics.GuestUsers = ($guestAssignments | Select-Object -Unique ObjectId).Count

foreach ($guest in ($guestAssignments | Group-Object ObjectId)) {
    $guestUser = $guest.Group[0]
    $privilegedRoles = @("Owner", "Contributor", "User Access Administrator")
    
    if ($guest.Group.RoleDefinitionName | Where-Object { $_ -in $privilegedRoles }) {
        $findings += New-SecurityFinding `
            -FindingId "IAM-GUEST-001" `
            -Category "Guest User Security" `
            -Severity "Critical" `
            -Resource $guestUser.DisplayName `
            -Description "Guest user has elevated permissions" `
            -Impact "External users with elevated access pose security risk" `
            -Recommendation "Remove guest user or downgrade permissions."
    }
}

Write-Host "Analyzing service principals..."
Write-Host ""

$spAssignments = $allAssignments | Where-Object { $_.ObjectType -eq "ServicePrincipal" }
$statistics.TotalServicePrincipals = ($spAssignments | Select-Object -Unique ObjectId).Count

foreach ($sp in ($spAssignments | Group-Object ObjectId)) {
    $servicePrincipal = $sp.Group[0]
    
    if ($sp.Group.RoleDefinitionName -contains "Owner") {
        $findings += New-SecurityFinding `
            -FindingId "IAM-SP-001" `
            -Category "Service Principal Security" `
            -Severity "Critical" `
            -Resource $servicePrincipal.DisplayName `
            -Description "Service Principal has Owner role with full control" `
            -Impact "Compromised SP could lead to environment takeover" `
            -Recommendation "Remove Owner role. Use Managed Identities."
    }
}

Write-Host "Analyzing role assignments..."
Write-Host ""

$orphanedAssignments = $allAssignments | Where-Object { 
    $_.ObjectType -eq "Unknown" -or [string]::IsNullOrEmpty($_.DisplayName)
}

foreach ($orphaned in $orphanedAssignments) {
    $findings += New-SecurityFinding `
        -FindingId "IAM-ROLE-001" `
        -Category "Role Assignment" `
        -Severity "Medium" `
        -Resource "ObjectId: $($orphaned.ObjectId)" `
        -Description "Orphaned role assignment detected" `
        -Impact "Stale permissions that clutter IAM" `
        -Recommendation "Remove orphaned role assignment"
    
    $statistics.StaleCredentials++
}

$customRoles = Get-AzRoleDefinition | Where-Object { $_.IsCustom -eq $true }

foreach ($role in $customRoles) {
    if ($role.Actions -contains "*") {
        $findings += New-SecurityFinding `
            -FindingId "IAM-ROLE-002" `
            -Category "Custom Role Security" `
            -Severity "Critical" `
            -Resource $role.Name `
            -Description "Custom role has wildcard permissions" `
            -Impact "Wildcard permissions grant unrestricted access" `
            -Recommendation "Replace wildcard with specific actions."
    }
}

Write-Host "Calculating risk score..."
Write-Host ""

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

Write-Host "Generating reports..."
Write-Host ""

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
.header { background: #4CAF50; color: white; padding: 20px; border-radius: 5px; }
.stat { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #4CAF50; }
.finding { background: white; padding: 15px; margin: 10px 0; border-left: 4px solid #ff9800; }
.critical { border-left-color: #f44336; }
.high { border-left-color: #ff9800; }
.medium { border-left-color: #ffc107; }
.low { border-left-color: #8bc34a; }
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
</div>
"@

foreach ($finding in $findings) {
    $htmlReport += @"
<div class="finding $($finding.Severity.ToLower())">
<h4>$($finding.Category) - $($finding.Severity)</h4>
<p><strong>Resource:</strong> $($finding.Resource)</p>
<p><strong>Description:</strong> $($finding.Description)</p>
<p><strong>Impact:</strong> $($finding.Impact)</p>
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
Write-Host "Risk Score: $($statistics.RiskScore)/100 - $riskLevel"
Write-Host "Total Findings: $($statistics.TotalFindings)"
Write-Host "Critical: $($statistics.CriticalFindings)"
Write-Host "High: $($statistics.HighFindings)"
Write-Host ""
Write-Host "Reports saved:"
Write-Host "HTML: $htmlFile"
Write-Host "CSV:  $csvFile"
Write-Host ""

if ($SendEmail) {
    $emailMetadata = @{
        ReportDate = $reportDate
        HtmlFile = $htmlFile
        CsvFile = $csvFile
        RiskScore = $statistics.RiskScore
        RiskLevel = $riskLevel
        CriticalCount = $statistics.CriticalFindings
        HighCount = $statistics.HighFindings
    } | ConvertTo-Json
    
    $emailMetadataFile = Join-Path $ReportPath "email-metadata-$timestamp.json"
    $emailMetadata | Out-File -FilePath $emailMetadataFile -Encoding UTF8
}

Start-Process $htmlFile

Write-Host "Done!" -ForegroundColor Green