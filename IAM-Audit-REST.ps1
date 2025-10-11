<#
.SYNOPSIS
    IAM Audit using REST API - Works with ANY Azure module version
.DESCRIPTION
    Uses Azure REST API directly - no module dependencies
#>

param(
    [string]$OutputPath = ".\IAM-Reports"
)

Write-Host ""
Write-Host "IAM Security Audit - REST API Version"
Write-Host "======================================"
Write-Host ""

# Create output folder
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Get Azure context and token
Write-Host "Getting Azure access token..." -ForegroundColor Yellow

try {
    # Try to get context from current session
    $context = Get-AzContext -ErrorAction Stop
    
    if (-not $context) {
        Write-Host "Not connected. Please run: Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
    
    $subscriptionId = $context.Subscription.Id
    $tenantId = $context.Tenant.Id
    
    Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    
    # Get access token
    $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
    
    if (-not $token) {
        Write-Host "Failed to get access token" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Access token obtained" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run: Connect-AzAccount" -ForegroundColor Yellow
    exit 1
}

# Function to call Azure REST API
function Invoke-AzureRestApi {
    param(
        [string]$Uri,
        [string]$Token
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type" = "application/json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
        return $response
    } catch {
        Write-Host "API Error: $_" -ForegroundColor Red
        return $null
    }
}

# Get role assignments using REST API
Write-Host "Getting role assignments via REST API..." -ForegroundColor Yellow

$apiVersion = "2022-04-01"
$uri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=$apiVersion"

$result = Invoke-AzureRestApi -Uri $uri -Token $token

if (-not $result) {
    Write-Host "Failed to get role assignments" -ForegroundColor Red
    exit 1
}

$assignments = $result.value
Write-Host "Found $($assignments.Count) role assignments" -ForegroundColor Green
Write-Host ""

# Analyze assignments
$findings = @()
$stats = @{
    Total = $assignments.Count
    Users = 0
    ServicePrincipals = 0
    Groups = 0
}

Write-Host "Analyzing assignments..." -ForegroundColor Yellow

foreach ($assignment in $assignments) {
    $principalType = $assignment.properties.principalType
    $roleId = $assignment.properties.roleDefinitionId
    $roleName = ($roleId -split '/')[-1]
    
    # Count by type
    switch ($principalType) {
        "User" { $stats.Users++ }
        "ServicePrincipal" { $stats.ServicePrincipals++ }
        "Group" { $stats.Groups++ }
    }
    
    # Check for Owner role (common GUID)
    if ($roleId -match "8e3af657-a8ff-443c-a75c-2fe8c4bcb635") {
        $findings += [PSCustomObject]@{
            Severity = if ($principalType -eq "ServicePrincipal") { "CRITICAL" } else { "HIGH" }
            Type = "$principalType with Owner Role"
            PrincipalId = $assignment.properties.principalId
            Scope = $assignment.properties.scope
            Recommendation = "Review if Owner role is necessary"
        }
    }
}

Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "=========" -ForegroundColor Cyan
Write-Host "Total Assignments: $($stats.Total)"
Write-Host "Users: $($stats.Users)"
Write-Host "Service Principals: $($stats.ServicePrincipals)"
Write-Host "Groups: $($stats.Groups)"
Write-Host ""
Write-Host "Security Findings: $($findings.Count)" -ForegroundColor $(if ($findings.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# Save reports
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = Join-Path $OutputPath "IAM-Findings-REST-$timestamp.csv"
$jsonFile = Join-Path $OutputPath "IAM-RawData-$timestamp.json"

# Save findings
if ($findings.Count -gt 0) {
    $findings | Export-Csv -Path $csvFile -NoTypeInformation
    Write-Host "Findings saved to: $csvFile" -ForegroundColor Green
}

# Save raw data
$assignments | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding UTF8
Write-Host "Raw data saved to: $jsonFile" -ForegroundColor Green
Write-Host ""

# Display findings
if ($findings.Count -gt 0) {
    Write-Host "SECURITY FINDINGS:" -ForegroundColor Yellow
    $findings | Format-Table Severity, Type, Recommendation -AutoSize
} else {
    Write-Host "No critical security findings!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Audit complete!" -ForegroundColor Green