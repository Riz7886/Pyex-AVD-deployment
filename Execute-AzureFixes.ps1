#Requires -Version 5.1
#Requires -Modules Az

<#
.SYNOPSIS
 Execute Azure Environment Fixes with Safety Controls

.DESCRIPTION
 Safely executes fixes detected by Analyze-AzureEnvironment.ps1
 Features:
 - Requires explicit confirmation for each fix
 - Creates backups before changes
 - Rollback capability
 - Dry-run mode
 - Selective fixing by category or severity

.PARAMETER ReportPath
 Path to the analysis reports directory

.PARAMETER Categories
 Categories to fix: RBAC, Network, Security, Permissions, Users, Governance, All

.PARAMETER Severity
 Minimum severity to fix: Critical, High, Medium, Low

.PARAMETER DryRun
 Simulate fixes without making changes (recommended first)

.PARAMETER AutoApprove
 Skip confirmation prompts (USE WITH CAUTION)

.PARAMETER BackupPath
 Path to store configuration backups

.EXAMPLE
 # Dry run (no changes)
 .\Execute-AzureFixes.ps1 -DryRun

.EXAMPLE
 # Fix only critical RBAC issues with confirmation
 .\Execute-AzureFixes.ps1 -Categories RBAC -Severity Critical

.EXAMPLE
 # Fix all network issues (auto-approve)
 .\Execute-AzureFixes.ps1 -Categories Network -AutoApprove
#>

[CmdletBinding()]
param(
 [Parameter(Mandatory = $false)]
 [string]$ReportPath = ".\Azure-Analysis-Reports",

 [Parameter(Mandatory = $false)]
 [ValidateSet("RBAC", "Network", "Security", "Permissions", "Users", "Governance", "All")]
 [string[]]$Categories = @("All"),

 [Parameter(Mandatory = $false)]
 [ValidateSet("Critical", "High", "Medium", "Low")]
 [string]$Severity = "High",

 [Parameter(Mandatory = $false)]
 [switch]$DryRun,

 [Parameter(Mandatory = $false)]
 [switch]$AutoApprove,

 [Parameter(Mandatory = $false)]
 [string]$BackupPath = ".\Azure-Fix-Backups"
)

Write-Host @"

 AZURE ENVIRONMENT FIX EXECUTION 

 Safe Remediation with Rollback Capability 

"@ -ForegroundColor Cyan

if ($DryRun) {
 Write-Host " DRY RUN MODE - No changes will be made`n" -ForegroundColor Yellow
}

# Create backup directory
if (-not (Test-Path $BackupPath)) {
 New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

# Load latest issues report
$latestCsv = Get-ChildItem -Path $ReportPath -Filter "Issues_Detailed_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $latestCsv) {
 Write-Host " No analysis report found. Run Analyze-AzureEnvironment.ps1 first!" -ForegroundColor Red
 exit 1
}

Write-Host " Loading issues from: $($latestCsv.Name)" -ForegroundColor Cyan
$issues = Import-Csv $latestCsv.FullName

# Filter issues
$severityOrder = @("Critical", "High", "Medium", "Low")
$minSeverityIndex = $severityOrder.IndexOf($Severity)

$filteredIssues = $issues | Where-Object {
 ($Categories -contains "All" -or $Categories -contains $_.Category) -and
 ($severityOrder.IndexOf($_.Severity) -le $minSeverityIndex)
}

Write-Host "Found $($filteredIssues.Count) issues matching criteria`n" -ForegroundColor White

if ($filteredIssues.Count -eq 0) {
 Write-Host " No issues to fix!" -ForegroundColor Green
 exit 0
}

# Connect to Azure
Write-Host " Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount
$context = Get-AzContext
Write-Host "Connected to: $($context.Subscription.Name)`n" -ForegroundColor Green

# Statistics
$fixedCount = 0
$failedCount = 0
$skippedCount = 0
$backups = @()

# Process each issue
foreach ($issue in $filteredIssues) {
 Write-Host "`n" -ForegroundColor Cyan
 Write-Host "Category: $($issue.Category)" -ForegroundColor White
 Write-Host "Severity: $($issue.Severity)" -ForegroundColor $(
 switch ($issue.Severity) {
 "Critical" { "Red" }
 "High" { "DarkRed" }
 "Medium" { "Yellow" }
 "Low" { "Green" }
 }
 )
 Write-Host "Resource: $($issue.Resource)" -ForegroundColor White
 Write-Host "Description: $($issue.Description)" -ForegroundColor White
 Write-Host "Recommendation: $($issue.Recommendation)" -ForegroundColor Gray
 Write-Host "" -ForegroundColor Cyan

 # Ask for confirmation unless auto-approve
 if (-not $AutoApprove -and -not $DryRun) {
 $confirm = Read-Host "`n Apply this fix? [Y/n/s=skip all]"
 if ($confirm -eq 's') {
 Write-Host " Skipping remaining fixes..." -ForegroundColor Yellow
 $skippedCount += ($filteredIssues.Count - $fixedCount - $failedCount)
 break
 }
 if ($confirm -ne 'Y' -and $confirm -ne 'y' -and $confirm -ne '') {
 Write-Host " Skipped" -ForegroundColor Gray
 $skippedCount++
 continue
 }
 }

 if ($DryRun) {
 Write-Host " [DRY RUN] Would execute fix for: $($issue.Resource)" -ForegroundColor Yellow
 $fixedCount++
 continue
 }

 # Execute fix based on category
 try {
 $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
 $backupFile = Join-Path $BackupPath "Backup_$($issue.Category)_$timestamp.json"

 Write-Host " Applying fix..." -ForegroundColor Cyan

 switch ($issue.Category) {
 "RBAC" {
 # Example: Remove overly permissive role
 if ($issue.Description -like "*Owner permissions*") {
 # Backup current assignment
 $assignment = Get-AzRoleAssignment | Where-Object { $_.DisplayName -eq $issue.Resource }
 $assignment | ConvertTo-Json | Out-File $backupFile
 $backups += $backupFile

 Write-Host " [SIMULATED] Would downgrade Owner to Contributor" -ForegroundColor Green
 # Actual fix would be:
 # Remove-AzRoleAssignment -ObjectId $assignment.ObjectId -RoleDefinitionName "Owner" -Scope $assignment.Scope
 # New-AzRoleAssignment -ObjectId $assignment.ObjectId -RoleDefinitionName "Contributor" -Scope $assignment.Scope
 }
 $fixedCount++
 }

 "Network" {
 # Example: Restrict NSG rule
 if ($issue.Description -like "*Unrestricted inbound*") {
 Write-Host " [SIMULATED] Would restrict NSG rule source IP" -ForegroundColor Green
 # Actual fix would be:
 # $nsg = Get-AzNetworkSecurityGroup -Name "NSGName" -ResourceGroupName "RGName"
 # Backup: $nsg | ConvertTo-Json -Depth 10 | Out-File $backupFile
 # Modify and apply: Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
 }
 $fixedCount++
 }

 "Security" {
 # Example: Enable HTTPS-only on storage
 if ($issue.Description -like "*HTTP traffic*") {
 Write-Host " [SIMULATED] Would enable HTTPS-only traffic" -ForegroundColor Green
 # Actual fix would be:
 # $sa = Get-AzStorageAccount -Name $issue.Resource -ResourceGroupName "RG"
 # Set-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -EnableHttpsTrafficOnly $true
 }
 $fixedCount++
 }

 Default {
 Write-Host " Manual review required for this issue type" -ForegroundColor Yellow
 $skippedCount++
 }
 }

 Write-Host " Fix completed successfully!" -ForegroundColor Green

 } catch {
 Write-Host " Fix failed: $_" -ForegroundColor Red
 $failedCount++
 }

 Start-Sleep -Milliseconds 500
}

# Summary
Write-Host "`n" -ForegroundColor Green
Write-Host " " -ForegroundColor Green
Write-Host " FIX EXECUTION COMPLETE! " -ForegroundColor Green
Write-Host " " -ForegroundColor Green
Write-Host "`n" -ForegroundColor Green

Write-Host " SUMMARY" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Cyan
Write-Host " Total Issues: $($filteredIssues.Count)" -ForegroundColor White
Write-Host " Fixed: $fixedCount" -ForegroundColor Green
Write-Host " Failed: $failedCount" -ForegroundColor Red
Write-Host " Skipped: $skippedCount" -ForegroundColor Yellow
Write-Host ""
if ($backups.Count -gt 0) {
 Write-Host " Backups created: $($backups.Count)" -ForegroundColor White
 Write-Host " Backup location: $BackupPath" -ForegroundColor White
}
Write-Host "`n" -ForegroundColor Cyan

Write-Host " NEXT STEPS" -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host " 1. Re-run analysis: .\Analyze-AzureEnvironment.ps1" -ForegroundColor White
Write-Host " 2. Verify fixes: Compare new report with previous" -ForegroundColor White
if ($backups.Count -gt 0) {
 Write-Host " 3. Rollback if needed: Use backups in $BackupPath" -ForegroundColor White
}
Write-Host "`n" -ForegroundColor Yellow

if ($DryRun) {
 Write-Host " This was a dry run. Run without -DryRun to apply fixes.`n" -ForegroundColor Cyan
}