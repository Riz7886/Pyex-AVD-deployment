#Requires -Version 5.1

<#
.SYNOPSIS
    Disable mDNS on ALL Intune Managed Devices
    
.DESCRIPTION
    Creates Intune Remediation Scripts to disable mDNS
    Changes ONLY EnableMDNS = 0
    Safe for production
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

$detectionScript = @'
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
$regName = "EnableMDNS"
try {
    $value = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($null -eq $value) { Write-Output "mDNS enabled"; exit 1 }
    if ($value.EnableMDNS -eq 0) { Write-Output "mDNS disabled"; exit 0 }
    else { Write-Output "mDNS enabled"; exit 1 }
} catch { Write-Output "Error: $_"; exit 1 }
