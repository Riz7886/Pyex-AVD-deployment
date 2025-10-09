#Requires -Version 5.1

<#
.SYNOPSIS
    Disable NetBIOS on ALL Intune Managed Devices
.DESCRIPTION
    Disables NetBIOS over TCP/IP on all network adapters
    Changes ONLY NetBIOS setting
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
Write-Host "  INTUNE NETBIOS DISABLER - ALL WINDOWS DEVICES" -ForegroundColor Cyan
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

$detectionScript = "# Detection Script - Check if NetBIOS is enabled`n"
$detectionScript += "`$interfaces = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue`n"
$detectionScript += "`n"
$detectionScript += "if (-not `$interfaces) {`n"
$detectionScript += "    Write-Output 'No NetBT interfaces found'`n"
$detectionScript += "    exit 0`n"
$detectionScript += "}`n"
$detectionScript += "`n"
$detectionScript += "`$needsRemediation = `$false`n"
$detectionScript += "`n"
$detectionScript += "foreach (`$interface in `$interfaces) {`n"
$detectionScript += "    try {`n"
$detectionScript += "        `$value = Get-ItemProperty -Path `$interface.PSPath -Name NetbiosOptions -ErrorAction SilentlyContinue`n"
$detectionScript += "        if (`$null -eq `$value -or `$value.NetbiosOptions -ne 2) {`n"
$detectionScript += "            `$needsRemediation = `$true`n"
$detectionScript += "            break`n"
$detectionScript += "        }`n"
$detectionScript += "    } catch { }`n"
$detectionScript += "}`n"
$detectionScript += "`n"
$detectionScript += "if (`$needsRemediation) {`n"
$detectionScript += "    Write-Output 'NetBIOS is enabled on one or more adapters'`n"
$detectionScript += "    exit 1`n"
$detectionScript += "} else {`n"
$detectionScript += "    Write-Output 'NetBIOS is disabled on all adapters'`n"
$detectionScript += "    exit 0`n"
$detectionScript += "}`n"

$remediationScript = "# Remediation Script - Disable NetBIOS on all adapters`n"
$remediationScript += "`$interfaces = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue`n"
$remediationScript += "`n"
$remediationScript += "if (-not `$interfaces) {`n"
$remediationScript += "    Write-Output 'No NetBT interfaces found'`n"
$remediationScript += "    exit 0`n"
$remediationScript += "}`n"
$remediationScript += "`n"
$remediationScript += "`$disabledCount = 0`n"
$remediationScript += "`n"
$remediationScript += "foreach (`$interface in `$interfaces) {`n"
$remediationScript += "    try {`n"
$remediationScript += "        Set-ItemProperty -Path `$interface.PSPath -Name NetbiosOptions -Value 2 -Type DWord -Force`n"
$remediationScript += "        `$disabledCount++`n"
$remediationScript += "    } catch {`n"
$remediationScript += "        Write-Output 'Error on interface: `$_'`n"
$remediationScript += "    }`n"
$remediationScript += "}`n"
$remediationScript += "`n"
$remediationScript += "Write-Output 'NetBIOS disabled on `$disabledCount adapters'`n"
$remediationScript += "exit 0`n"

$detectionFile = "$env:TEMP\NetBIOS-Detection.ps1"
$remediationFile = "$env:TEMP\NetBIOS-Remediation.ps1"

$detectionScript | Out-File -FilePath $detectionFile -Encoding UTF8 -Force
$remediationScript | Out-File -FilePath $remediationFile -Encoding UTF8 -Force

Write-Log "NetBIOS remediation scripts created!" "SUCCESS"

Write-Host "`n================================================================" -ForegroundColor Yellow
Write-Host "  MANUAL DEPLOYMENT REQUIRED" -ForegroundColor Yellow
Write-Host "================================================================`n" -ForegroundColor Yellow
Write-Host "1. Go to: https://intune.microsoft.com" -ForegroundColor White
Write-Host "2. Reports > Endpoint Analytics > Proactive Remediations" -ForegroundColor White
Write-Host "3. Create script package" -ForegroundColor White
Write-Host "4. Name: Disable NetBIOS for All Devices" -ForegroundColor White
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
Write-Host "Registry Change: NetbiosOptions = 2 (Disabled)" -ForegroundColor Cyan
Write-Host "Path: HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\*`n" -ForegroundColor Gray
Write-Host "Safe for production - Disables NetBIOS only" -ForegroundColor Green
Write-Host "Applied to ALL network adapters`n" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
Write-Log "Complete!" "SUCCESS"
