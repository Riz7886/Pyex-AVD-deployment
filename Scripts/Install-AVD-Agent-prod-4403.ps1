# AVD Agent Installation Script
# Company: pyex | Environment: prod
# Run this on each session host VM

$ErrorActionPreference = 'Stop'
Write-Host "Installing AVD Agents for pyex - prod environment..." -ForegroundColor Cyan

# Download AVD Agent
$agentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
$agentPath = "$env:TEMP\AVDAgent.msi"
Write-Host "Downloading AVD Agent..."
Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath

# Download Boot Loader
$bootLoaderUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
$bootLoaderPath = "$env:TEMP\AVDBootLoader.msi"
Write-Host "Downloading Boot Loader..."
Invoke-WebRequest -Uri $bootLoaderUrl -OutFile $bootLoaderPath

# Install AVD Agent
Write-Host "Installing AVD Agent..."
Start-Process msiexec.exe -ArgumentList "/i $agentPath /quiet /qn /norestart REGISTRATIONTOKEN=" -Wait

# Install Boot Loader
Write-Host "Installing Boot Loader..."
Start-Process msiexec.exe -ArgumentList "/i $bootLoaderPath /quiet /qn /norestart" -Wait

# Configure FSLogix
Write-Host "Configuring FSLogix..."
New-Item -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VHDLocations" -Value "\\pyexavdprod4403.file.core.windows.net\profiles-prod"

Write-Host "
✓ AVD Agent installation complete!" -ForegroundColor Green
Write-Host "Environment: prod | Host Pool: pyex-hp-avd-prod-eus" -ForegroundColor Cyan
Write-Host "Restarting in 10 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
Restart-Computer -Force
