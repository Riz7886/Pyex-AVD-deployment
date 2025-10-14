#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix SQL Server Security

.DESCRIPTION
    1. Removes "Allow Azure Services" firewall rule
    2. Enables SQL auditing to Log Analytics
    
.PARAMETER LogAnalyticsWorkspaceId
    Log Analytics Workspace ID for auditing (optional)
    
.EXAMPLE
    .\Fix-SQL-Security.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspaceId = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX SQL SECURITY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Remove 'Allow Azure Services' firewall rule" -ForegroundColor White
Write-Host "  2. Enable SQL auditing" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Getting SQL Servers..." -ForegroundColor Yellow
$sqlJson = az sql server list -o json 2>&1
$sqlServers = $sqlJson | ConvertFrom-Json

Write-Host "Found: $($sqlServers.Count)" -ForegroundColor White

$removedRules = 0
$enabledAuditing = 0

foreach ($server in $sqlServers) {
    Write-Host ""
    Write-Host "Processing: $($server.name)" -ForegroundColor Cyan
    
    # Fix 1: Remove Azure Services rule
    $rulesJson = az sql server firewall-rule list --server $server.name --resource-group $server.resourceGroup -o json 2>&1
    $rules = $rulesJson | ConvertFrom-Json
    
    foreach ($rule in $rules) {
        if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "0.0.0.0") {
            Write-Host "  Removing Azure Services rule: $($rule.name)..." -NoNewline
            try {
                az sql server firewall-rule delete `
                    --server $server.name `
                    --resource-group $server.resourceGroup `
                    --name $rule.name `
                    --output none
                
                Write-Host " REMOVED" -ForegroundColor Green
                $removedRules++
            } catch {
                Write-Host " ERROR" -ForegroundColor Red
            }
        }
    }
    
    # Fix 2: Enable auditing
    Write-Host "  Enabling auditing..." -NoNewline
    try {
        if ($LogAnalyticsWorkspaceId) {
            az sql server audit-policy update `
                --name $server.name `
                --resource-group $server.resourceGroup `
                --state Enabled `
                --log-analytics-workspace-resource-id $LogAnalyticsWorkspaceId `
                --output none
        } else {
            az sql server audit-policy update `
                --name $server.name `
                --resource-group $server.resourceGroup `
                --state Enabled `
                --output none
        }
        
        Write-Host " ENABLED" -ForegroundColor Green
        $enabledAuditing++
    } catch {
        Write-Host " ERROR" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Azure Services rules removed: $removedRules" -ForegroundColor Cyan
Write-Host "Auditing enabled: $enabledAuditing" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: Configure VNet service endpoints for secure access" -ForegroundColor Yellow
Write-Host ""
