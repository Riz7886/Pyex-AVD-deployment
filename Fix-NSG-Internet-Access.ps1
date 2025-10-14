#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PYX Health - Fix NSG Rules Open to Internet

.DESCRIPTION
    Restricts NSG rules that allow inbound from Internet on dangerous ports
    Ports: 3389 (RDP), 443 (HTTPS), 990, 9855
    
.PARAMETER SourceIP
    Your specific IP address to allow (e.g., "203.0.113.5")
    
.EXAMPLE
    .\Fix-NSG-Internet-Access.ps1 -SourceIP "203.0.113.5"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceIP
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - FIX NSG INTERNET ACCESS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will restrict the following ports from Internet access:" -ForegroundColor Yellow
Write-Host "  - Port 3389 (RDP)" -ForegroundColor White
Write-Host "  - Port 443 (HTTPS)" -ForegroundColor White
Write-Host "  - Port 990" -ForegroundColor White
Write-Host "  - Port 9855" -ForegroundColor White
Write-Host ""
Write-Host "Source IP will be changed to: $SourceIP" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit 0
}

# Backup folder
$backupFolder = "C:\Azure-Fixes-Backup\NSG-Rules"
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFile = "$backupFolder\nsg-rules-before-$timestamp.json"

# Get all NSGs
Write-Host ""
Write-Host "Getting all NSGs..." -ForegroundColor Yellow
$nsgsJson = az network nsg list -o json 2>&1
$nsgs = $nsgsJson | ConvertFrom-Json

Write-Host "Found: $($nsgs.Count) NSGs" -ForegroundColor White

# Backup
Write-Host "Creating backup..." -ForegroundColor Yellow
$nsgs | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
Write-Host "Backup: $backupFile" -ForegroundColor Green

# Dangerous ports to check
$dangerousPorts = @("3389", "443", "990", "9855")
$fixedCount = 0

foreach ($nsg in $nsgs) {
    Write-Host ""
    Write-Host "Checking NSG: $($nsg.name)" -ForegroundColor Cyan
    
    $rulesJson = az network nsg rule list --nsg-name $nsg.name --resource-group $nsg.resourceGroup -o json 2>&1
    $rules = $rulesJson | ConvertFrom-Json
    
    foreach ($rule in $rules) {
        if ($rule.direction -eq "Inbound" -and $rule.access -eq "Allow") {
            $isInternet = $rule.sourceAddressPrefix -in @("*", "Internet", "0.0.0.0/0")
            
            if ($isInternet) {
                $portInfo = if ($rule.destinationPortRange) { $rule.destinationPortRange } else { "multiple" }
                
                # Check if this rule affects dangerous ports
                foreach ($dangerousPort in $dangerousPorts) {
                    if ($portInfo -match $dangerousPort) {
                        Write-Host "  FIXING: $($rule.name) (Port $portInfo)" -ForegroundColor Yellow
                        
                        try {
                            az network nsg rule update `
                                --nsg-name $nsg.name `
                                --resource-group $nsg.resourceGroup `
                                --name $rule.name `
                                --source-address-prefixes $SourceIP `
                                --output none
                            
                            Write-Host "    FIXED - Now restricted to $SourceIP" -ForegroundColor Green
                            $fixedCount++
                        } catch {
                            Write-Host "    ERROR: $($_.Exception.Message)" -ForegroundColor Red
                        }
                        
                        break
                    }
                }
            }
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Rules Fixed: $fixedCount" -ForegroundColor Cyan
Write-Host "Backup: $backupFile" -ForegroundColor White
Write-Host ""
Write-Host "ROLLBACK (if needed):" -ForegroundColor Yellow
Write-Host "  Manually restore source to Internet using Azure Portal" -ForegroundColor Gray
Write-Host ""
