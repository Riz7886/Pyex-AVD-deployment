#Requires -Version 5.1

<#
.SYNOPSIS
    Disable mDNS on ALL Intune Managed Devices
#>

[CmdletBinding()]
param()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor $colors[$Level]
}

Write-Host "`n================================================================"
Write-Host "  INTUNE mDNS DISABLER - ALL DEVICES"
Write-Host "================================================================`n"

Write-Log "Checking Microsoft Graph PowerShell..." "INFO"

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

Write-Host "`n================================================================"
Write-Host "  CREATING REMEDIATION SCRIPTS"
Write-Host "================================================================`n"

# Detection Script Content
$detectionContent = @"
`$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
`$regName = "EnableMDNS"

try {
    `$value = Get-ItemProperty -Path `$regPath -Name `$regName -ErrorAction SilentlyContinue
    
    if (`$null -eq `$value) {
        Write-Output "mDNS enabled (default)"
        exit 1
    }
    
    if (`$value.EnableMDNS -eq 0) {
        Write-Output "mDNS disabled"
        exit 0
    } else {
        Write-Output "mDNS enabled"
        exit 1
    }
} catch {
    Write-Output "Error: `$_"
    exit 1
}
"@

# Remediation Script Content
$remediationContent = @"
`$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
`$regName = "EnableMDNS"

try {
    if (-not (Test-Path `$regPath)) {
        Write-Output "Registry path missing"
        exit 1
    }
    
    Set-ItemProperty -Path `$regPath -Name `$regName -Value 0 -Type DWord -Force
    Write-Output "mDNS disabled (EnableMDNS = 0)"
    exit 0
} catch {
    Write-Output "Error: `$_"
    exit 1
}
"@

$detectionFile = "$env:TEMP\mDNS-Detection.ps1"
$remediationFile = "$env:TEMP\mDNS-Remediation.ps1"

$detectionContent | Out-File -FilePath $detectionFile -Encoding UTF8 -Force
$remediationContent | Out-File -FilePath $remediationFile -Encoding UTF8 -Force

Write-Log "Scripts created successfully" "SUCCESS"

Write-Host "`n================================================================"
Write-Host "  DEPLOY VIA INTUNE PORTAL"
Write-Host "================================================================`n"
Write-Host "1. Go to: https://intune.microsoft.com"
Write-Host "2. Reports > Endpoint Analytics > Proactive Remediations"
Write-Host "3. Create script package"
Write-Host "4. Upload Detection: $detectionFile"
Write-Host "5. Upload Remediation: $remediationFile"
Write-Host "6. Assign to: All devices`n"

try {
    $devices = Get-MgDeviceManagementManagedDevice -All
    $windowsDevices = $devices | Where-Object { $_.OperatingSystem -like "Windows*" }
    Write-Host "Total Devices: $($devices.Count)"
    Write-Host "Windows Devices: $($windowsDevices.Count)`n"
} catch {
    Write-Log "Could not query devices (need to login first)" "WARNING"
}

Write-Host "`n================================================================"
Write-Host "  SUMMARY"
Write-Host "================================================================`n"
Write-Host "Registry Change: EnableMDNS = 0" -ForegroundColor Cyan
Write-Host "Path: HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -ForegroundColor Gray
Write-Host "`nSafe for production - Changes ONLY mDNS setting`n" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
Write-Log "Complete!" "SUCCESS"

