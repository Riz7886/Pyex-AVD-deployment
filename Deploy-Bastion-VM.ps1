#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Deploy PYEX Bastion VM - Fully Automated
.DESCRIPTION
    Creates Bastion VM with complete automation including Service Principal and GitHub clone
.PARAMETER ResourceGroupName
    Resource group name
.PARAMETER Location
    Azure region
.PARAMETER VMName
    VM name
.PARAMETER AdminUsername
    Admin username
.PARAMETER AdminPassword
    Admin password (secure string)
.EXAMPLE
    $pw = ConvertTo-SecureString "Pass123!" -AsPlainText -Force
    .\Deploy-Bastion-VM.ps1 -ResourceGroupName "RG-Bastion" -Location "eastus" -VMName "Bastion-VM" -AdminUsername "admin" -AdminPassword $pw
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$Location,
    [Parameter(Mandatory=$true)][string]$VMName,
    [Parameter(Mandatory=$false)][string]$VMSize = "Standard_D4s_v3",
    [Parameter(Mandatory=$true)][string]$AdminUsername,
    [Parameter(Mandatory=$true)][SecureString]$AdminPassword,
    [Parameter(Mandatory=$false)][string]$ServicePrincipalName = "SP-PYEX-Automation"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "============================================"
Write-Host "  BASTION VM DEPLOYMENT"
Write-Host "============================================"
Write-Host ""

Write-Log "Checking Azure CLI"
az version --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Azure CLI not found" }

$account = az account show --output json | ConvertFrom-Json
Write-Log "Authenticated as: $($account.user.name)" "SUCCESS"

$subscriptions = az account list --output json | ConvertFrom-Json
Write-Log "Found $($subscriptions.Count) subscriptions" "SUCCESS"

Write-Host ""
Write-Host "STEP 1: Resource Group" -ForegroundColor Yellow
if ((az group exists --name $ResourceGroupName) -eq "false") {
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Log "Created" "SUCCESS"
} else {
    Write-Log "Already exists" "WARNING"
}

Write-Host ""
Write-Host "STEP 2: Virtual Network" -ForegroundColor Yellow
az network vnet create --resource-group $ResourceGroupName --name "VNet-Bastion" --address-prefix 10.0.0.0/16 --subnet-name "Subnet-Bastion" --subnet-prefix 10.0.1.0/24 --location $Location --output none
Write-Log "VNet created" "SUCCESS"

Write-Host ""
Write-Host "STEP 3: Network Security Group" -ForegroundColor Yellow
az network nsg create --resource-group $ResourceGroupName --name "NSG-Bastion" --location $Location --output none
az network nsg rule create --resource-group $ResourceGroupName --nsg-name "NSG-Bastion" --name "AllowRDP" --priority 100 --destination-port-ranges 3389 --access Allow --protocol Tcp --output none
az network nsg rule create --resource-group $ResourceGroupName --nsg-name "NSG-Bastion" --name "AllowHTTPS" --priority 110 --destination-port-ranges 443 --access Allow --protocol Tcp --output none
az network vnet subnet update --resource-group $ResourceGroupName --vnet-name "VNet-Bastion" --name "Subnet-Bastion" --network-security-group "NSG-Bastion" --output none
Write-Log "NSG configured" "SUCCESS"

Write-Host ""
Write-Host "STEP 4: Service Principal" -ForegroundColor Yellow
$spExists = az ad sp list --display-name $ServicePrincipalName --output json | ConvertFrom-Json
if ($spExists.Count -gt 0) {
    $spAppId = $spExists[0].appId
    Write-Log "Already exists" "WARNING"
} else {
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --output json | ConvertFrom-Json
    $spAppId = $sp.appId
    Write-Host "App ID: $spAppId" -ForegroundColor Green
    Write-Host "Password: $($sp.password)" -ForegroundColor Green
    Write-Host "SAVE THESE!" -ForegroundColor Yellow
    Start-Sleep -Seconds 20
}

foreach ($sub in $subscriptions) {
    az role assignment create --assignee $spAppId --role "Reader" --scope "/subscriptions/$($sub.id)" --output none 2>$null
}
Write-Log "Reader access granted to all subscriptions" "SUCCESS"

Write-Host ""
Write-Host "STEP 5: Create VM (5-10 minutes)" -ForegroundColor Yellow
$plainPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
az vm create --resource-group $ResourceGroupName --name $VMName --image "Win2022Datacenter" --size $VMSize --admin-username $AdminUsername --admin-password $plainPw --vnet-name "VNet-Bastion" --subnet "Subnet-Bastion" --nsg "NSG-Bastion" --public-ip-sku Standard --location $Location --output none
Write-Log "VM created" "SUCCESS"

Write-Host ""
Write-Host "STEP 6: Install Azure CLI on VM" -ForegroundColor Yellow
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts "Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile C:\AzureCLI.msi; Start-Process msiexec.exe -ArgumentList '/I','C:\AzureCLI.msi','/quiet' -Wait; Remove-Item C:\AzureCLI.msi" --output none 2>$null
Write-Log "Azure CLI installed" "SUCCESS"

Write-Host ""
Write-Host "STEP 7: Setup Directories" -ForegroundColor Yellow
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts "New-Item -Path 'C:\PYEX-Automation\Scripts','C:\PYEX-Automation\Reports','C:\PYEX-Automation\Logs' -ItemType Directory -Force; Set-ExecutionPolicy RemoteSigned -Force" --output none 2>$null
Write-Log "Directories created" "SUCCESS"

Write-Host ""
Write-Host "STEP 8: Install Git and Clone Repo" -ForegroundColor Yellow
$gitCmd = "Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe -OutFile C:\Git.exe; Start-Process C:\Git.exe -ArgumentList '/VERYSILENT' -Wait; Remove-Item C:\Git.exe; & 'C:\Program Files\Git\bin\git.exe' clone https://github.com/Riz7886/Pyex-AVD-deployment.git C:\PYEX-Automation\Scripts"
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts $gitCmd --output none 2>$null
Write-Log "GitHub repo cloned" "SUCCESS"

$vmInfo = az vm show --resource-group $ResourceGroupName --name $VMName --show-details --output json | ConvertFrom-Json
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "VM IP: $($vmInfo.publicIps)" -ForegroundColor White
Write-Host "Username: $AdminUsername" -ForegroundColor White
Write-Host "Scripts: C:\PYEX-Automation\Scripts" -ForegroundColor White
Write-Host ""
Write-Host "RDP: mstsc /v:$($vmInfo.publicIps)" -ForegroundColor Cyan
Write-Host "Then run: .\MASTER-Install-All-Scheduled-Tasks.ps1" -ForegroundColor Cyan
Write-Host ""
