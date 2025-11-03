#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy DataDog with auto-configuration
.EXAMPLE
    .\Deploy-DataDog-FIXED.ps1 -APIKey "your-key"
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="DataDog API Key")]
    [string]$APIKey,
    
    [Parameter(HelpMessage="Skip prompts")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== PyxHealth DataDog Deploy ===" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrEmpty($APIKey)) {
    $APIKey = Read-Host "Enter DataDog API Key"
}

if (-not $Force) {
    $c = Read-Host "Deploy DataDog? (Y/N)"
    if ($c -ne "Y") { exit 0 }
}

try {
    Write-Host "Checking for DataDog..." -ForegroundColor Cyan
    
    $ddService = Get-Service -Name "datadogagent" -ErrorAction SilentlyContinue
    if ($ddService) {
        Write-Host "DataDog already installed!" -ForegroundColor Green
        Write-Host "Service Status: $($ddService.Status)" -ForegroundColor White
    } else {
        Write-Host "Installing DataDog Agent..." -ForegroundColor Yellow
        $url = "https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi"
        $installer = "$env:TEMP\dd-agent.msi"
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/qn /i `"$installer`" APIKEY=`"$APIKey`"" -Wait
        Remove-Item $installer -Force
        Write-Host "DataDog installed!" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== DEPLOYMENT COMPLETE ===" -ForegroundColor Green
    Write-Host "View: https://app.datadoghq.com" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
