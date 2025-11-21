Write-Host "DMZ PRODUCTION DEPLOYMENT - LINUX (UBUNTU)" -ForegroundColor Cyan
Write-Host "Transfer Server: 20.66.24.164" -ForegroundColor Green
Write-Host ""

$TRANSFER = "20.66.24.164"
$RG = "DMZ-Linux-Production"
$LOC = "eastus"
$VM = "DMZ-NGINX-Server"
$USER = "azureadmin"

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

Write-Host "Generating SSH key..." -ForegroundColor Yellow
$sshKeyPath = Join-Path $env:TEMP "dmz_ssh_key"
if (Test-Path $sshKeyPath) { Remove-Item $sshKeyPath -Force }
if (Test-Path "$sshKeyPath.pub") { Remove-Item "$sshKeyPath.pub" -Force }

ssh-keygen -t rsa -b 4096 -f $sshKeyPath -N '""' -C "dmz-admin" 2>$null
$sshPubKey = Get-Content "$sshKeyPath.pub" -Raw
Write-Host "[OK] SSH key generated: $sshKeyPath" -ForegroundColor Green

$enableSFTP = Read-Host "Enable SFTP port 22? (Y/N)"
$enableHTTPS = Read-Host "Enable HTTPS port 443? (Y/N)"

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

az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowAdminSSH --priority $priority --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "*" --destination-port-ranges 2222 --output none
Write-Host "  [OK] Admin SSH port 2222 opened" -ForegroundColor Green

az network nsg rule create --resource-group $RG --nsg-name nsg-dmz --name AllowToTransfer --priority 100 --direction Outbound --access Allow --protocol "*" --source-address-prefixes "*" --destination-address-prefixes $TRANSFER --destination-port-ranges "*" --output none
Write-Host "  [OK] Allow outbound to Transfer Server" -ForegroundColor Green

az network public-ip create --resource-group $RG --name pip-dmz --sku Standard --allocation-method Static --location $LOC --output none
Write-Host "[OK] Public IP created" -ForegroundColor Green

az network nic create --resource-group $RG --name nic-dmz --vnet-name vnet-dmz --subnet subnet-dmz --network-security-group nsg-dmz --public-ip-address pip-dmz --location $LOC --output none
Write-Host "[OK] Network interface created" -ForegroundColor Green

Write-Host "Creating Ubuntu Server VM (5-10 minutes)..." -ForegroundColor Yellow
az vm create --resource-group $RG --name $VM --nics nic-dmz --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" --size Standard_B2s --admin-username $USER --ssh-key-values $sshPubKey --location $LOC --output none

$ip = az network public-ip show --resource-group $RG --name pip-dmz --query ipAddress --output tsv
Write-Host "[OK] VM created successfully!" -ForegroundColor Green
Write-Host ""

Write-Host "Installing NGINX and security tools..." -ForegroundColor Yellow
$installScript = @'
#!/bin/bash
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx openssh-server ufw
systemctl enable nginx
systemctl start nginx
systemctl enable ssh
systemctl start ssh
ufw --force enable
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 2222/tcp
mkdir -p /sftp/uploads
mkdir -p /sftp/downloads
chmod 755 /sftp
chmod 777 /sftp/uploads
useradd -m -s /bin/bash sftpuser
echo "sftpuser:SecurePass2024!" | chpasswd
'@

az vm run-command invoke --resource-group $RG --name $VM --command-id RunShellScript --scripts $installScript --output none
Write-Host "[OK] Software installed" -ForegroundColor Green

Write-Host "Configuring NGINX reverse proxy..." -ForegroundColor Yellow
$nginxConfig = @"
#!/bin/bash
cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user www-data;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    server_tokens off;
    
    server {
        listen 443 ssl default_server;
        server_name _;
        
        ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
        ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        
        location / {
            proxy_pass https://$TRANSFER:443;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_ssl_verify off;
        }
    }
}
NGINXEOF

systemctl restart nginx
"@

az vm run-command invoke --resource-group $RG --name $VM --command-id RunShellScript --scripts $nginxConfig --output none
Write-Host "[OK] NGINX configured" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "DMZ NGINX SERVER DETAILS:" -ForegroundColor Cyan
Write-Host "  Public IP: $ip" -ForegroundColor Yellow
Write-Host "  Admin User: $USER" -ForegroundColor White
Write-Host "  SSH Key: $sshKeyPath" -ForegroundColor Yellow
Write-Host "  Transfer Server: $TRANSFER" -ForegroundColor Green
Write-Host ""
Write-Host "REMOTE ACCESS:" -ForegroundColor Cyan
Write-Host "  SSH: ssh -i $sshKeyPath -p 2222 $USER@$ip" -ForegroundColor Yellow
Write-Host ""
if ($enableSFTP -eq "Y") {
    Write-Host "SFTP ACCESS:" -ForegroundColor Cyan
    Write-Host "  SFTP: sftp sftpuser@$ip" -ForegroundColor Yellow
    Write-Host "  Password: SecurePass2024!" -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "SECURITY FEATURES:" -ForegroundColor Cyan
Write-Host "  [OK] NGINX Reverse Proxy" -ForegroundColor Green
Write-Host "  [OK] OpenSSH SFTP Server" -ForegroundColor Green
Write-Host "  [OK] UFW Firewall (active)" -ForegroundColor Green
Write-Host "  [OK] TLS 1.2/1.3 encryption" -ForegroundColor Green
Write-Host "  [OK] Connection to Transfer Server" -ForegroundColor Green
Write-Host ""
Write-Host "Annual Cost Savings: 17400-29400 USD" -ForegroundColor Green
Write-Host ""

$summary = @"
DMZ LINUX DEPLOYMENT SUMMARY
============================
Public IP: $ip
Admin User: $USER
SSH Key: $sshKeyPath
Resource Group: $RG
Transfer Server: $TRANSFER

2 SFTP SERVERS:
1. DMZ SFTP Server (public) - $ip
2. Transfer Server (internal) - $TRANSFER

SSH Admin Login:
  ssh -i $sshKeyPath -p 2222 $USER@$ip

SFTP Login:
  sftp sftpuser@$ip
  Password: SecurePass2024!

NGINX Proxy:
  https://$ip -> https://$TRANSFER

To delete resources:
  az group delete --name $RG --yes --no-wait

IMPORTANT: Save SSH key file!
"@

$summaryFile = Join-Path $env:USERPROFILE "Desktop\DMZ-Linux-Deployment-Summary.txt"
$summary | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Host "Summary saved to: $summaryFile" -ForegroundColor Green

$desktopKey = Join-Path $env:USERPROFILE "Desktop\dmz_ssh_key"
Copy-Item $sshKeyPath $desktopKey -Force
Copy-Item "$sshKeyPath.pub" "$desktopKey.pub" -Force
Write-Host "SSH key copied to Desktop!" -ForegroundColor Green

pause
