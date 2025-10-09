#Requires -Version 5.1
<#
.SYNOPSIS
    Ultimate Multi-Subscription Azure Audit - FIXED
.EXAMPLE
    .\Ultimate-Multi-Subscription-Audit.ps1
#>
[CmdletBinding()]
param([string]$OutputPath = ".\Complete-Audit-Reports")

function Write-AuditLog {
    param([string]$Message, [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "PROGRESS")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red";"PROGRESS"="Magenta"}
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

function Get-SafeValue {
    param($Value, $Default = "N/A")
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    return $Value
}

function Get-AzureJsonData {
    param([string]$Command)
    try {
        $output = Invoke-Expression $Command
        if ($LASTEXITCODE -eq 0) { return ($output | ConvertFrom-Json) }
        return @()
    } catch { return @() }
}

$scriptStartTime = Get-Date
$subscriptionReports = @()

Write-Host "`n================================================================"
Write-Host "  ULTIMATE MULTI-SUBSCRIPTION AZURE AUDIT"
Write-Host "================================================================`n"
Write-Host "  READ-ONLY MODE - No changes will be made" -ForegroundColor Green
Write-Host "`n================================================================`n"

if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$masterReportPath = Join-Path $OutputPath "Master-Report-$timestamp"
New-Item -ItemType Directory -Path $masterReportPath -Force | Out-Null

Write-AuditLog "Output: $masterReportPath" "INFO"
Write-AuditLog "Checking Azure CLI..." "INFO"

try {
    $null = az account show --output json
    if ($LASTEXITCODE -ne 0) {
        Write-AuditLog "Not logged in" "ERROR"
        Write-Host "`nPlease run: az login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-AuditLog "Azure CLI not available" "ERROR"
    exit 1
}

$allSubscriptions = Get-AzureJsonData -Command "az account list --all --output json"
if ($allSubscriptions.Count -eq 0) { Write-AuditLog "No subscriptions found" "ERROR"; exit 1 }

Write-AuditLog "Found $($allSubscriptions.Count) subscriptions" "SUCCESS"
foreach ($sub in $allSubscriptions) {
    $status = if ($sub.state -eq "Enabled") { "ACTIVE" } else { $sub.state }
    Write-Host "  - $($sub.name) [$status]" -ForegroundColor $(if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" })
}

foreach ($subscription in $allSubscriptions) {
    if ($subscription.state -ne "Enabled") { continue }
    
    Write-Host "`n================================================================"
    Write-Host "  ANALYZING: $($subscription.name)"
    Write-Host "================================================================`n"
    
    az account set --subscription $subscription.id | Out-Null
    
    $subData = @{
        SubscriptionName = $subscription.name
        SubscriptionId = $subscription.id
        Resources = @()
        IAM = @()
        Policies = @()
        Findings = @()
        Statistics = @{
            TotalResourceGroups = 0
            TotalResources = 0
            TotalIAMAssignments = 0
            CriticalFindings = 0
            HighFindings = 0
        }
    }
    
    $resourceGroups = Get-AzureJsonData -Command "az group list --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalResourceGroups = $resourceGroups.Count
    
    $allResources = Get-AzureJsonData -Command "az resource list --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalResources = $allResources.Count
    
    foreach ($resource in $allResources) {
        $subData.Resources += [PSCustomObject]@{
            Name = Get-SafeValue $resource.name
            Type = Get-SafeValue $resource.type
            Location = Get-SafeValue $resource.location
        }
    }
    
    $roleAssignments = Get-AzureJsonData -Command "az role assignment list --all --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalIAMAssignments = $roleAssignments.Count
    
    $subscriptionReports += $subData
    Write-AuditLog "Completed $($subscription.name)" "SUCCESS"
}

$totalStats = @{
    TotalSubscriptions = $subscriptionReports.Count
    TotalResourceGroups = ($subscriptionReports | ForEach-Object { $_.Statistics.TotalResourceGroups } | Measure-Object -Sum).Sum
    TotalResources = ($subscriptionReports | ForEach-Object { $_.Statistics.TotalResources } | Measure-Object -Sum).Sum
}

foreach ($subReport in $subscriptionReports) {
    $subFolder = Join-Path $masterReportPath $subReport.SubscriptionName.Replace(" ", "_")
    New-Item -ItemType Directory -Path $subFolder -Force | Out-Null
    if ($subReport.Resources.Count -gt 0) {
        $subReport.Resources | Export-Csv -Path (Join-Path $subFolder "Resources.csv") -NoTypeInformation
    }
}

$endTime = Get-Date
$duration = $endTime - $scriptStartTime

Write-Host "`n================================================================"
Write-Host "  AUDIT COMPLETE!"
Write-Host "================================================================`n"
Write-Host "  Subscriptions: $($totalStats.TotalSubscriptions)" -ForegroundColor White
Write-Host "  Resources: $($totalStats.TotalResources)" -ForegroundColor White
Write-Host "  Time: $($duration.ToString('hh\:mm\:ss'))`n" -ForegroundColor White
Write-Host "Reports: $masterReportPath" -ForegroundColor Green
Write-Host "`nREAD-ONLY - No changes made`n" -ForegroundColor Green
