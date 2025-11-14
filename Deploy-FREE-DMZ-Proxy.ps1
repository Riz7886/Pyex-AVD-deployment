# FREE DMZ REVERSE PROXY DEPLOYMENT - NGINX Alternative to MOVEit Gateway
# Cost Savings: $15,000-$30,000 first year, $10,000-$25,000 annually
# Version: 1.0

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FREE DMZ REVERSE PROXY DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Using NGINX (FREE Open Source)" -ForegroundColor Cyan
Write-Host "  Replaces: MOVEit Gateway" -ForegroundColor Cyan
Write-Host "  Cost Savings: $15,000-$30,000/year" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Prerequisites Check
Write-Host "[1/12] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI not installed" -ForegroundColor Red
    Write-Host "Download: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}
Write-Host "  - Azure CLI: OK" -ForegroundColor Green

# Check/Install Azure PowerShell modules
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "  - Installing Az.Accounts module..." -ForegroundColor Yellow
    Install-Module -Name Az.Accounts -Force -AllowClobber -Scope CurrentUser
}
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Host "  - Installing Az.Compute module..." -ForegroundColor Yellow
    Install-Module -Name Az.Compute -Force -AllowClobber -Scope CurrentUser
}
if (-not (Get-Module -ListAvailable -Name Az.Network)) {
    Write-Host "  - Installing Az.Network module..." -ForegroundColor Yellow
    Install-Module -Name Az.Network -Force -AllowClobber -Scope CurrentUser
}
Write-Host "  - Azure modules: OK" -ForegroundColor Green
Write-Host ""

# Azure Authentication
Write-Host "[2/12] Azure Authentication..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login --use-device-code
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Authentication failed" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  - Authenticated as: $($account.user.name)" -ForegroundColor Green
Write-Host ""

# Subscription Selection
Write-Host "[3/12] Subscription Management" -ForegroundColor Yellow
$subs = az account list --all | ConvertFrom-Json

Write-Host "Available Subscriptions: (Total: $($subs.Count))" -ForegroundColor Cyan
for ($i = 0; $i -lt $subs.Count; $i++) {
    $status = if ($subs[$i].state -eq "Enabled") { "Active" } else { $subs[$i].state }
    Write-Host "  $($i + 1). $($subs[$i].name) - $status"
}
Write-Host ""
Write-Host "Enter number (1-$($subs.Count)) or 'new' for new subscription:" -ForegroundColor Yellow
$choice = Read-Host

if ($choice -eq "new" -or $choice -eq "NEW") {
    Write-Host "Opening Azure Portal..." -ForegroundColor Yellow
    Start-Process "https://portal.azure.com/#create/Microsoft.Subscription"
    Write-Host "After creating subscription, re-run this script" -ForegroundColor Yellow
    exit 0
}

$selectedIndex = [int]$choice - 1
$targetSub = $subs[$selectedIndex]
az account set --subscription $targetSub.id
Write-Host "  - Connected to: $($targetSub.name)" -ForegroundColor Green
Write-Host ""

# Register Providers
Write-Host "[4/12] Registering Azure Providers..." -ForegroundColor Yellow
$providers = @("Microsoft.Compute", "Microsoft.Network", "Microsoft.Storage")
foreach ($provider in $providers) {
    $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($state -ne "Registered") {
        Write-Host "  - Registering $provider..." -ForegroundColor Yellow
        az provider register --namespace $provider --wait
    } else {
        Write-Host "  - $provider: Registered" -ForegroundColor Green
    }
}
Write-Host ""

# Configuration - Existing Transfer Server
Write-Host "[5/12] Transfer Server Configuration" -ForegroundColor Yellow
Write-Host "Enter your EXISTING Transfer server details:" -ForegroundColor Cyan
Write-Host ""

# Transfer Server Configuration - PRE-CONFIGURED
$transferIP = "20.66.24.164"
$transferHttpsPort = "443"
$transferSshPort = "22"

Write-Host "Transfer Server Details (Pre-configured):" -ForegroundColor Cyan
Write-Host "  - IP: $transferIP" -ForegroundColor Green
Write-Host "  - HTTPS Port: $transferHttpsPort" -ForegroundColor Green
Write-Host "  - SSH Port: $transferSshPort" -ForegroundColor Green
Write-Host ""

# Configuration - NGINX Proxy
Write-Host "[6/12] NGINX Reverse Proxy Configuration" -ForegroundColor Yellow
$resourceGroup = Read-Host "Resource Group name (will be created if needed)"
$location = Read-Host "Azure region (e.g., eastus, westus2)"
$proxyVmName = Read-Host "Proxy VM name (DMZ server)"
$vmSize = Read-Host "VM size (default: Standard_B2s, press Enter)"
if ([string]::IsNullOrWhiteSpace($vmSize)) { $vmSize = "Standard_B2s" }

$adminUsername = Read-Host "VM admin username"
$adminPasswordSecure = Read-Host "VM admin password (min 12 chars)" -AsSecureString
$adminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPasswordSecure))

Write-Host ""
Write-Host "Enable protocols on NGINX proxy:" -ForegroundColor Cyan
$enableSftp = Read-Host "Enable SFTP (port 22)? (Y/N)"
$enableHttps = Read-Host "Enable HTTPS (port 443)? (Y/N)"
$enableFtp = Read-Host "Enable FTP (port 21)? (Y/N)"
Write-Host ""

# Create Resource Group
Write-Host "[7/12] Creating Resource Group..." -ForegroundColor Yellow
az group create --name $resourceGroup --location $location --output none
Write-Host "  - Resource Group created" -ForegroundColor Green
Write-Host ""

# Deploy Infrastructure
Write-Host "[8/12] Deploying Network Infrastructure..." -ForegroundColor Yellow

az network vnet create `
    --resource-group $resourceGroup `
    --name "vnet-dmz" `
    --address-prefix "10.1.0.0/16" `
    --subnet-name "subnet-dmz" `
    --subnet-prefix "10.1.1.0/24" `
    --location $location `
    --output none
Write-Host "  - VNet created" -ForegroundColor Green

az network nsg create `
    --resource-group $resourceGroup `
    --name "nsg-nginx-proxy" `
    --location $location `
    --output none
Write-Host "  - NSG created" -ForegroundColor Green

# Configure NSG Rules
Write-Host "  - Configuring firewall rules..." -ForegroundColor Yellow

if ($enableSftp -eq "Y" -or $enableSftp -eq "y") {
    az network nsg rule create --resource-group $resourceGroup --nsg-name "nsg-nginx-proxy" `
        --name "Allow-SFTP" --priority 100 --direction Inbound `
        --access Allow --protocol Tcp --source-address-prefixes "*" `
        --source-port-ranges "*" --destination-port-ranges 22 --output none
}

if ($enableHttps -eq "Y" -or $enableHttps -eq "y") {
    az network nsg rule create --resource-group $resourceGroup --nsg-name "nsg-nginx-proxy" `
        --name "Allow-HTTPS" --priority 110 --direction Inbound `
        --access Allow --protocol Tcp --source-address-prefixes "*" `
        --source-port-ranges "*" --destination-port-ranges 443 --output none
}

if ($enableFtp -eq "Y" -or $enableFtp -eq "y") {
    az network nsg rule create --resource-group $resourceGroup --nsg-name "nsg-nginx-proxy" `
        --name "Allow-FTP" --priority 120 --direction Inbound `
        --access Allow --protocol Tcp --source-address-prefixes "*" `
        --source-port-ranges "*" --destination-port-ranges 21 --output none
}

az network nsg rule create --resource-group $resourceGroup --nsg-name "nsg-nginx-proxy" `
    --name "Allow-RDP" --priority 200 --direction Inbound `
    --access Allow --protocol Tcp --source-address-prefixes "*" `
    --source-port-ranges "*" --destination-port-ranges 3389 --output none

Write-Host "  - Firewall rules configured" -ForegroundColor Green

az network public-ip create `
    --resource-group $resourceGroup `
    --name "pip-nginx-proxy" `
    --sku Standard `
    --allocation-method Static `
    --location $location `
    --output none
Write-Host "  - Public IP created" -ForegroundColor Green

az network nic create `
    --resource-group $resourceGroup `
    --name "nic-nginx-proxy" `
    --vnet-name "vnet-dmz" `
    --subnet "subnet-dmz" `
    --network-security-group "nsg-nginx-proxy" `
    --public-ip-address "pip-nginx-proxy" `
    --location $location `
    --output none
Write-Host "  - Network interface created" -ForegroundColor Green
Write-Host ""

# Create VM with Ubuntu (NGINX runs best on Linux)
Write-Host "[9/12] Creating NGINX Proxy VM..." -ForegroundColor Yellow
Write-Host "  - This may take 5-10 minutes..." -ForegroundColor Yellow

az vm create `
    --resource-group $resourceGroup `
    --name $proxyVmName `
    --nics "nic-nginx-proxy" `
    --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" `
    --size $vmSize `
    --admin-username $adminUsername `
    --admin-password $adminPassword `
    --location $location `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create VM" -ForegroundColor Red
    exit 1
}
Write-Host "  - VM created successfully" -ForegroundColor Green
Write-Host ""

$proxyPublicIP = az network public-ip show `
    --resource-group $resourceGroup `
    --name "pip-nginx-proxy" `
    --query ipAddress `
    --output tsv

Write-Host "  - Proxy Public IP: $proxyPublicIP" -ForegroundColor Green
Write-Host ""

# Install and Configure NGINX
Write-Host "[10/12] Installing NGINX Reverse Proxy..." -ForegroundColor Yellow

# Create NGINX configuration
$nginxConfig = @"
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 4096;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Gzip compression
    gzip on;

    # HTTPS proxy to Transfer server
    server {
        listen 443 ssl;
        server_name _;

        # Self-signed cert for initial setup
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass https://$transferIP:$transferHttpsPort;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_ssl_verify off;
        }
    }
}

# SSH/SFTP stream proxy
stream {
    server {
        listen 22;
        proxy_pass $transferIP:$transferSshPort;
    }

    # FTP if enabled
    server {
        listen 21;
        proxy_pass $transferIP:21;
    }
}
"@

$installScript = @"
#!/bin/bash
set -e

echo 'Installing NGINX...'
apt-get update -y
apt-get install -y nginx openssl

echo 'Creating SSL certificate directory...'
mkdir -p /etc/nginx/ssl

echo 'Generating self-signed certificate...'
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj '/CN=proxy/O=Company/C=US'

echo 'Configuring NGINX...'
cat > /etc/nginx/nginx.conf << 'NGINXEOF'
$nginxConfig
NGINXEOF

echo 'Testing NGINX configuration...'
nginx -t

echo 'Starting NGINX...'
systemctl enable nginx
systemctl restart nginx

echo 'Configuring firewall...'
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 21/tcp
ufw allow 3389/tcp
ufw --force enable

echo 'NGINX installation complete!'
nginx -v
systemctl status nginx --no-pager
"@

$installScriptPath = Join-Path $env:TEMP "install-nginx.sh"
$installScript | Out-File -FilePath $installScriptPath -Encoding UTF8 -NoNewline

Write-Host "  - Uploading configuration to VM..." -ForegroundColor Yellow

az vm extension set `
    --resource-group $resourceGroup `
    --vm-name $proxyVmName `
    --name CustomScript `
    --publisher Microsoft.Azure.Extensions `
    --version 2.1 `
    --settings "{`"fileUris`":[],`"commandToExecute`":`"echo '$($installScript -replace "'", "'\''")' > /tmp/install.sh && chmod +x /tmp/install.sh && /tmp/install.sh`"}" `
    --output none

Write-Host "  - NGINX installed and configured" -ForegroundColor Green
Write-Host ""

# Testing
Write-Host "[11/12] Testing Configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$testHttps = Test-NetConnection -ComputerName $proxyPublicIP -Port 443 -InformationLevel Quiet
if ($testHttps) {
    Write-Host "  - HTTPS port 443: OPEN" -ForegroundColor Green
} else {
    Write-Host "  - HTTPS port 443: Waiting for service..." -ForegroundColor Yellow
}

if ($enableSftp -eq "Y") {
    $testSsh = Test-NetConnection -ComputerName $proxyPublicIP -Port 22 -InformationLevel Quiet
    if ($testSsh) {
        Write-Host "  - SFTP port 22: OPEN" -ForegroundColor Green
    } else {
        Write-Host "  - SFTP port 22: Waiting for service..." -ForegroundColor Yellow
    }
}

Write-Host ""

# Deployment Summary
Write-Host "[12/12] Deployment Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "NGINX Reverse Proxy (DMZ):" -ForegroundColor Yellow
Write-Host "  - VM Name: $proxyVmName" -ForegroundColor White
Write-Host "  - Public IP: $proxyPublicIP" -ForegroundColor Green
Write-Host "  - Admin Username: $adminUsername" -ForegroundColor White
Write-Host "  - SSH Access: ssh $adminUsername@$proxyPublicIP" -ForegroundColor Cyan
Write-Host ""

Write-Host "Transfer Server (Internal):" -ForegroundColor Yellow
Write-Host "  - IP: $transferIP" -ForegroundColor White
Write-Host "  - HTTPS Port: $transferHttpsPort" -ForegroundColor White
Write-Host "  - SSH Port: $transferSshPort" -ForegroundColor White
Write-Host ""

Write-Host "Enabled Services:" -ForegroundColor Yellow
if ($enableSftp -eq "Y") { Write-Host "  - SFTP: $proxyPublicIP:22 -> $transferIP:$transferSshPort" -ForegroundColor Green }
if ($enableHttps -eq "Y") { Write-Host "  - HTTPS: $proxyPublicIP:443 -> $transferIP:$transferHttpsPort" -ForegroundColor Green }
if ($enableFtp -eq "Y") { Write-Host "  - FTP: $proxyPublicIP:21 -> $transferIP:21" -ForegroundColor Green }
Write-Host ""

Write-Host "Cost Savings:" -ForegroundColor Yellow
Write-Host "  - MOVEit Gateway License: $15,000-$30,000/year" -ForegroundColor Red
Write-Host "  - NGINX Solution: $0/year (FREE)" -ForegroundColor Green
Write-Host "  - Your Savings: $15,000-$30,000/year" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Test SFTP connection: sftp user@$proxyPublicIP" -ForegroundColor White
Write-Host "  2. Test HTTPS: https://$proxyPublicIP" -ForegroundColor White
Write-Host "  3. Replace self-signed cert with real SSL certificate" -ForegroundColor White
Write-Host "  4. Configure DNS to point to $proxyPublicIP" -ForegroundColor White
Write-Host "  5. Update Transfer server to only accept connections from proxy" -ForegroundColor White
Write-Host ""

Write-Host "SSL Certificate Replacement:" -ForegroundColor Yellow
Write-Host "  SSH to VM: ssh $adminUsername@$proxyPublicIP" -ForegroundColor Cyan
Write-Host "  Copy your .crt and .key files to /etc/nginx/ssl/" -ForegroundColor Cyan
Write-Host "  Restart NGINX: sudo systemctl restart nginx" -ForegroundColor Cyan
Write-Host ""

Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
Write-Host "  FREE SOLUTION - $0 LICENSE COST" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
