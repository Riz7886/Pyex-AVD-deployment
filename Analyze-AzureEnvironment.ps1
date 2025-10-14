#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - Azure Environment Security Analysis (FIXED)

.DESCRIPTION
    Scans Azure subscription for security issues with proper error handling
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Azure-Security-Report.html"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - AZURE SECURITY ANALYSIS" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI
try {
    $null = az version 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "Azure CLI: OK" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Azure CLI not installed!" -ForegroundColor Red
    Write-Host "Install: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}

# Check login
Write-Host "Checking Azure login..." -ForegroundColor Yellow
try {
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Not logged in" }
    
    $account = $accountJson | ConvertFrom-Json -ErrorAction Stop
    Write-Host "Logged in: $($account.user.name)" -ForegroundColor Green
    Write-Host "Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Not logged in to Azure!" -ForegroundColor Red
    Write-Host "Run: az login" -ForegroundColor Yellow
    exit 1
}

# Initialize
$issues = @{ Critical = 0; High = 0; Medium = 0; Low = 0 }
$findings = @()

# Safe JSON parser
function Get-AzResourceSafe {
    param([string]$Command)
    try {
        $output = Invoke-Expression "$Command 2>&1"
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            return @()
        }
        return ($output | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return @()
    }
}

# Scan Storage Accounts
Write-Host ""
Write-Host "[1/3] Scanning Storage Accounts..." -ForegroundColor Yellow
$storageAccounts = Get-AzResourceSafe -Command "az storage account list -o json"

if ($storageAccounts.Count -gt 0) {
    Write-Host "  Found: $($storageAccounts.Count) storage accounts" -ForegroundColor White
    
    foreach ($sa in $storageAccounts) {
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            $findings += [PSCustomObject]@{
                Severity = "High"
                Resource = $sa.name
                Type = "Storage Account"
                Issue = "HTTPS-only not enabled"
                Recommendation = "Enable HTTPS-only traffic"
            }
            $issues.High++
        }
        
        if ($sa.minimumTlsVersion -ne "TLS1_2") {
            $findings += [PSCustomObject]@{
                Severity = "High"
                Resource = $sa.name
                Type = "Storage Account"
                Issue = "TLS 1.2 not enforced"
                Recommendation = "Set minimum TLS to 1.2"
            }
            $issues.High++
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            $findings += [PSCustomObject]@{
                Severity = "Medium"
                Resource = $sa.name
                Type = "Storage Account"
                Issue = "Public blob access enabled"
                Recommendation = "Disable public access"
            }
            $issues.Medium++
        }
    }
}

# Scan Key Vaults
Write-Host "[2/3] Scanning Key Vaults..." -ForegroundColor Yellow
$keyVaults = Get-AzResourceSafe -Command "az keyvault list -o json"

if ($keyVaults.Count -gt 0) {
    Write-Host "  Found: $($keyVaults.Count) key vaults" -ForegroundColor White
    
    foreach ($kv in $keyVaults) {
        if ($kv.properties.enableSoftDelete -ne $true) {
            $findings += [PSCustomObject]@{
                Severity = "High"
                Resource = $kv.name
                Type = "Key Vault"
                Issue = "Soft delete not enabled"
                Recommendation = "Enable soft delete"
            }
            $issues.High++
        }
    }
}

# Scan NSGs
Write-Host "[3/3] Scanning Network Security Groups..." -ForegroundColor Yellow
$nsgs = Get-AzResourceSafe -Command "az network nsg list -o json"

if ($nsgs.Count -gt 0) {
    Write-Host "  Found: $($nsgs.Count) NSGs" -ForegroundColor White
}

# Generate Report
$totalIssues = $issues.Critical + $issues.High + $issues.Medium + $issues.Low

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PYX Health - Azure Security Report</title>
    <style>
        body { font-family: Arial; margin: 20px; background: #f5f5f5; }
        .header { background: #0078d4; color: white; padding: 20px; border-radius: 5px; }
        .summary { background: white; padding: 20px; margin: 20px 0; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px 20px; text-align: center; }
        .metric-value { font-size: 36px; font-weight: bold; }
        .critical { color: #d13438; }
        .high { color: #ff8c00; }
        .medium { color: #ffd700; }
        .low { color: #107c10; }
        table { width: 100%; border-collapse: collapse; background: white; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>PYX Health - Azure Security Analysis</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    <div class="summary">
        <h2>Summary</h2>
        <div class="metric">
            <div class="metric-value">$totalIssues</div>
            <div>Total Issues</div>
        </div>
        <div class="metric">
            <div class="metric-value critical">$($issues.Critical)</div>
            <div>Critical</div>
        </div>
        <div class="metric">
            <div class="metric-value high">$($issues.High)</div>
            <div>High</div>
        </div>
        <div class="metric">
            <div class="metric-value medium">$($issues.Medium)</div>
            <div>Medium</div>
        </div>
        <div class="metric">
            <div class="metric-value low">$($issues.Low)</div>
            <div>Low</div>
        </div>
    </div>
    <h2>Findings</h2>
    <table>
        <tr>
            <th>Severity</th>
            <th>Resource</th>
            <th>Type</th>
            <th>Issue</th>
            <th>Recommendation</th>
        </tr>
"@

foreach ($f in $findings) {
    $html += "<tr><td>$($f.Severity)</td><td>$($f.Resource)</td><td>$($f.Type)</td><td>$($f.Issue)</td><td>$($f.Recommendation)</td></tr>`n"
}

$html += "</table></body></html>"

$html | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host ""
Write-Host "RESULTS:" -ForegroundColor Cyan
Write-Host "  Total: $totalIssues" -ForegroundColor White
Write-Host "  Critical: $($issues.Critical)" -ForegroundColor Red
Write-Host "  High: $($issues.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($issues.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($issues.Low)" -ForegroundColor Green
Write-Host ""
Write-Host "Report: $OutputPath" -ForegroundColor Cyan
