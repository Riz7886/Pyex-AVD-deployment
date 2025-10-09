#Requires -Version 5.1

param()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor $colors[$Level]
}

Write-Host "`nINTUNE mDNS DISABLER`n" -ForegroundColor Cyan
Write-Log "Checking modules..." "INFO"

$mods = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement")
foreach ($m in $mods) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser
    }
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.DeviceManagement

Write-Log "Connecting..." "INFO"
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All" -NoWelcome

Write-Log "Creating scripts..." "INFO"

$detection = "# Detection Script`n"
$detection += "`$regPath = `"HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters`"`n"
$detection += "`$regName = `"EnableMDNS`"`n"
$detection += "try {`n"
$detection += "    `$v = Get-ItemProperty -Path `$regPath -Name `$regName -EA SilentlyContinue`n"
$detection += "    if (`$null -eq `$v) { Write-Output `"Enabled`"; exit 1 }`n"
$detection += "    if (`$v.EnableMDNS -eq 0) { exit 0 } else { exit 1 }`n"
$detection += "} catch { exit 1 }`n"

$remediation = "# Remediation Script`n"
$remediation += "`$regPath = `"HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters`"`n"
$remediation += "try {`n"
$remediation += "    Set-ItemProperty -Path `$regPath -Name EnableMDNS -Value 0 -Type DWord -Force`n"
$remediation += "    Write-Output `"Disabled`"; exit 0`n"
$remediation += "} catch { exit 1 }`n"

$detFile = "$env:TEMP\mDNS-Detection.ps1"
$remFile = "$env:TEMP\mDNS-Remediation.ps1"

$detection | Out-File $detFile -Encoding UTF8 -Force
$remediation | Out-File $remFile -Encoding UTF8 -Force

Write-Log "Scripts created!" "SUCCESS"
Write-Host "`nDETECTION: $detFile" -ForegroundColor Cyan
Write-Host "REMEDIATION: $remFile" -ForegroundColor Cyan

Write-Host "`nUPLOAD TO: https://intune.microsoft.com" -ForegroundColor Yellow
Write-Host "Reports > Proactive Remediations > Create script package`n"

try {
    $d = Get-MgDeviceManagementManagedDevice -All
    $w = $d | Where-Object { $_.OperatingSystem -like "Windows*" }
    Write-Host "Windows Devices: $($w.Count)`n" -ForegroundColor Green
} catch { }

Disconnect-MgGraph | Out-Null
Write-Log "Done!" "SUCCESS"
