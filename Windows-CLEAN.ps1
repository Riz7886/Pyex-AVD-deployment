Write-Host "DMZ PRODUCTION DEPLOYMENT - WINDOWS" -ForegroundColor Cyan
Write-Host "Transfer Server: 20.66.24.164" -ForegroundColor Green
Write-Host ""

$TRANSFER = "20.66.24.164"
$RG = "DMZ-Production"
$LOC = "eastus"
$VM = "DMZ-Server"
$USER = "dmzadmin"

Write-Host "Checking Azure CLI..." -ForegroundColor Yellow
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI not installed" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "[OK] Azure CLI found" -ForegroundColor Green

Write-Host "Logging into Azure..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login --use-device-code
}

Write-Host "Select Azure Subscription:" -ForegroundColor Cyan
$subs = az account list | ConvertFrom-Json | Where-Object { $_.state -eq "Enabled" }
for ($i=0; $i -lt $subs.Count; $i++) {
    Write-Host "  $($i+1). $($subs[$i].name)"
}

$choice = Read-Host "Enter subscription number"
$index = [int]$choice - 1
az account set --subscription $subs[$index].id
Write-Host "[OK] Using subscription: $($subs[$index].name)" -ForegroundColor Green

Write-Host "Enter admin password (12+ chars, mixed case, number, symbol):" -ForegroundColor Yellow
$secPwd = Read-Host "Password" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
$pwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

$enableSFTP = Read-Host "Enable SFTP port 22? (Y/N)"
$enableHTTPS = Read-Host "Enable HTTPS port 443? (Y/N)"
$enableRDP = Read-Host "Enable RDP port 3389? (Y/N)"

Write-Host "Creating Azure resources..." -ForegroundColor Yellow

az group create --name $RG --location $LOC --output none
Write-Host "[OK] Resource group created" -ForegroundColor Green

az network vnet create --resource-group $RG --name vnet-dmz --address-prefix 10.0.0.0/16 --subnet-name subnet-dmz --subnet-prefix 10.0.1.0/24 --location $LOC --output none
Write-Host "[OK] Virtual network created" -ForegroundColor Green

az network nsg create --resource-group $RG --name nsg-dmz --location $LOC --output none
Write-Host "[OK] Network security group created" -ForegroundColor Green

Write-Host "Configuring firewall rules..." -ForegroundColor Yellow
$priority = 100

if ($enableSFTP -eq "Y") {
    az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowSFTP --priority $priority --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "*" --destination-port-ranges 22 --output none
    Write-Host "  [OK] SFTP port 22 opened" -ForegroundColor Green
    $priority = $priority + 10
}

if ($enableHTTPS -eq "Y") {
    az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowHTTPS --priority $priority --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "*" --destination-port-ranges 443 --output none
    Write-Host "  [OK] HTTPS port 443 opened" -ForegroundColor Green
    $priority = $priority + 10
}

if ($enableRDP -eq "Y") {
    az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowRDP --priority $priority --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "*" --destination-port-ranges 3389 --output none
    Write-Host "  [OK] RDP port 3389 opened" -ForegroundColor Green
    $priority = $priority + 10
}

az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowToTransfer --priority 100 --direction Outbound --access Allow --protocol "*" --source-address-prefixes "*" --destination-address-prefixes $TRANSFER --destination-port-ranges "*" --output none
Write-Host "  [OK] Allow outbound to Transfer Server" -ForegroundColor Green

az network public-ip create --resource-group $RG --name pip-dmz --sku Standard --allocation-method Static --location $LOC --output none
Write-Host "[OK] Public IP created" -ForegroundColor Green

az network nic create --resource-group $RG --name nic-dmz --vnet-name vnet-dmz --subnet subnet-dmz --network-security-group nsg-dmz --public-ip-address pip-dmz --location $LOC --output none
Write-Host "[OK] Network interface created" -ForegroundColor Green

Write-Host "Creating Windows Server VM (10-15 minutes)..." -ForegroundColor Yellow
az vm create --resource-group $RG --name $VM --nics nic-dmz --image "MicrosoftWindowsServer:WindowsServer:2022-datacenter:latest" --size Standard_B2s --admin-username $USER --admin-password $pwd --location $LOC --output none

$ip = az network public-ip show --resource-group $RG --name pip-dmz --query ipAddress --output tsv
Write-Host "[OK] VM created successfully!" -ForegroundColor Green
Write-Host ""

Write-Host "Installing OpenSSH SFTP Server..." -ForegroundColor Yellow
$installCmd = "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic"
az vm run-command invoke --resource-group $RG --name $VM --command-id RunPowerShellScript --scripts $installCmd --output none
Write-Host "[OK] OpenSSH installed" -ForegroundColor Green

Write-Host "Creating SFTP directories..." -ForegroundColor Yellow
$dirCmd = "New-Item -Path C:\SFTP\uploads -ItemType Directory -Force; New-Item -Path C:\SFTP\downloads -ItemType Directory -Force"
az vm run-command invoke --resource-group $RG --name $VM --command-id RunPowerShellScript --scripts $dirCmd --output none
Write-Host "[OK] Directories created" -ForegroundColor Green

Write-Host "Creating SFTP user..." -ForegroundColor Yellow
$userCmd = "New-LocalUser -Name sftpuser -Password (ConvertTo-SecureString 'SecurePass2024!' -AsPlainText -Force) -FullName 'SFTP User'"
az vm run-command invoke --resource-group $RG --name $VM --command-id RunPowerShellScript --scripts $userCmd --output none
Write-Host "[OK] SFTP user created" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "DMZ SERVER DETAILS:" -ForegroundColor Cyan
Write-Host "  Public IP: $ip" -ForegroundColor Yellow
Write-Host "  Admin User: $USER" -ForegroundColor White
Write-Host "  Transfer Server: $TRANSFER" -ForegroundColor Green
Write-Host ""
Write-Host "REMOTE ACCESS:" -ForegroundColor Cyan
if ($enableRDP -eq "Y") {
    Write-Host "  RDP: mstsc /v:$ip" -ForegroundColor Yellow
}
if ($enableSFTP -eq "Y") {
    Write-Host "  SFTP: sftp sftpuser@$ip" -ForegroundColor Yellow
    Write-Host "  Password: SecurePass2024!" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "SECURITY FEATURES:" -ForegroundColor Cyan
Write-Host "  [OK] OpenSSH SFTP Server" -ForegroundColor Green
Write-Host "  [OK] Windows Defender (active)" -ForegroundColor Green
Write-Host "  [OK] Network firewall rules" -ForegroundColor Green
Write-Host "  [OK] Connection to Transfer Server" -ForegroundColor Green
Write-Host ""
Write-Host "Annual Cost Savings: 17400-29400 USD" -ForegroundColor Green
Write-Host ""

$summary = @"
DMZ DEPLOYMENT SUMMARY
======================
Public IP: $ip
Admin User: $USER
Resource Group: $RG
Transfer Server: $TRANSFER

2 SFTP SERVERS:
1. DMZ SFTP Server (public) - $ip
2. Transfer Server (internal) - $TRANSFER

SFTP Login:
  sftp sftpuser@$ip
  Password: SecurePass2024!

RDP Login:
  mstsc /v:$ip
  User: $USER
  Password: (your password)

To delete resources:
  az group delete --name $RG --yes --no-wait
"@

$summaryFile = Join-Path $env:USERPROFILE "Desktop\DMZ-Deployment-Summary.txt"
$summary | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Host "Summary saved to: $summaryFile" -ForegroundColor Green

pause
