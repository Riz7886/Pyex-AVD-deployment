#Requires -Version 5.1

<#
.SYNOPSIS
    Disable WPAD on ALL Intune Managed Devices
.DESCRIPTION
    Disables Web Proxy Auto-Discovery (WPAD)
    Changes ONLY WPAD setting
    Safe for production
#>

param()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  INTUNE WPAD DISABLER - ALL WINDOWS DEVICES" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

Write-Log "Checking Microsoft Graph modules..." "INFO"

$requiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement")

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Log "Installing $module..." "WARNING"
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.DeviceManagement

Write-Log "Connecting to Microsoft Graph..." "INFO"
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All" -NoWelcome

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  CREATING REMEDIATION SCRIPTS" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

$detectionScript = "# Detection Script - Check if WPAD is enabled`n"
$detectionScript += "`$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad'`n"
$detectionScript += "`n"
$detectionScript += "try {`n"
$detectionScript += "    `$wpadExists = Test-Path `$regPath`n"
$detectionScript += "    `n"
$detectionScript += "    if (`$wpadExists) {`n"
$detectionScript += "        `$value = Get-ItemProperty -Path `$regPath -Name WpadOverride -ErrorAction SilentlyContinue`n"
$detectionScript += "        if (`$null -eq `$value -or `$value.WpadOverride -ne 1) {`n"
$detectionScript += "            Write-Output 'WPAD is enabled'`n"
$detectionScript += "            exit 1`n"
$detectionScript += "        }`n"
$detectionScript += "    } else {`n"
$detectionScript += "        Write-Output 'WPAD registry path does not exist - needs creation'`n"
$detectionScript += "        exit 1`n"
$detectionScript += "    }`n"
$detectionScript += "    `n"
$detectionScript += "    Write-Output 'WPAD is disabled'`n"
$detectionScript += "    exit 0`n"
$detectionScript += "} catch {`n"
$detectionScript += "    Write-Output 'Error checking WPAD: `$_'`n"
$detectionScript += "    exit 1`n"
$detectionScript += "}`n"

$remediationScript = "# Remediation Script - Disable WPAD`n"
$remediationScript += "`$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad'`n"
$remediationScript += "`n"
$remediationScript += "try {`n"
$remediationScript += "    if (-not (Test-Path `$regPath)) {`n"
$remediationScript += "        New-Item -Path `$regPath -Force | Out-Null`n"
$remediationScript += "    }`n"
$remediationScript += "    `n"
$remediationScript += "    Set-ItemProperty -Path `$regPath -Name WpadOverride -Value 1 -Type DWord -Force`n"
$remediationScript += "    `n"
$remediationScript += "    Write-Output 'WPAD disabled successfully (WpadOverride = 1)'`n"
$remediationScript += "    exit 0`n"
$remediationScript += "} catch {`n"
$remediationScript += "    Write-Output 'Error disabling WPAD: `$_'`n"
$remediationScript += "    exit 1`n"
$remediationScript += "}`n"

$detectionFile = "$env:TEMP\WPAD-Detection.ps1"
$remediationFile = "$env:TEMP\WPAD-Remediation.ps1"

$detectionScript | Out-File -FilePath $detectionFile -Encoding UTF8 -Force
$remediationScript | Out-File -FilePath $remediationFile -Encoding UTF8 -Force

Write-Log "WPAD remediation scripts created!" "SUCCESS"

Write-Host "`n================================================================" -ForegroundColor Yellow
Write-Host "  MANUAL DEPLOYMENT REQUIRED" -ForegroundColor Yellow
Write-Host "================================================================`n" -ForegroundColor Yellow
Write-Host "1. Go to: https://intune.microsoft.com" -ForegroundColor White
Write-Host "2. Reports > Endpoint Analytics > Proactive Remediations" -ForegroundColor White
Write-Host "3. Create script package" -ForegroundColor White
Write-Host "4. Name: Disable WPAD for All Devices" -ForegroundColor White
Write-Host "5. Upload Detection: $detectionFile" -ForegroundColor Cyan
Write-Host "6. Upload Remediation: $remediationFile" -ForegroundColor Cyan
Write-Host "7. Assign to: All devices`n" -ForegroundColor White

try {
    $allDevices = Get-MgDeviceManagementManagedDevice -All
    $windowsDevices = $allDevices | Where-Object { $_.OperatingSystem -like "Windows*" }
    Write-Host "Total Devices: $($allDevices.Count)" -ForegroundColor White
    Write-Host "Windows Devices: $($windowsDevices.Count)`n" -ForegroundColor Green
} catch {
    Write-Log "Could not query devices" "WARNING"
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  SUMMARY" -ForegroundColor Green
Write-Host "================================================================`n" -ForegroundColor Green
Write-Host "Registry Change: WpadOverride = 1 (Disabled)" -ForegroundColor Cyan
Write-Host "Path: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad`n" -ForegroundColor Gray
Write-Host "Safe for production - Disables WPAD only" -ForegroundColor Green
Write-Host "Prevents automatic proxy discovery`n" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
Write-Log "Complete!" "SUCCESS"
