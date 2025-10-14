#Requires -Version 5.1

param(
    [Parameter(Mandatory=$true)][string]$Location,
    [Parameter(Mandatory=$true)][string]$DataDogAPIKey,
    [Parameter(Mandatory=$true)][string]$DataDogAppKey
)

$ErrorActionPreference = "Stop"
$subscriptionId = az account show --query id -o tsv
$resourceGroup = "rg-bastion-automation"

Write-Host "Creating Key Vault and Service Principals..." -ForegroundColor Yellow

# Create Resource Group
$rgExists = az group exists --name $resourceGroup -o tsv
if ($rgExists -eq "false") {
    az group create --name $resourceGroup --location $Location --output none
}

# Create Key Vault
$vaultName = "kv-bastion-$(Get-Random -Minimum 1000 -Maximum 9999)"
az keyvault create --name $vaultName --resource-group $resourceGroup --location $Location --enable-rbac-authorization false --output none
Write-Host "Created Key Vault: $vaultName" -ForegroundColor Green

# Create 8 Service Principals
$sps = @{"DataDog-Monitor"="Reader";"Azure-Monitor"="Reader";"Security-Audit"="Security Reader";"Cost-Optimization"="Cost Management Reader";"IAM-Audit"="Reader";"Key-Rotation"="Contributor";"Backup-Verification"="Reader";"Health-Check"="Reader"}

foreach ($name in $sps.Keys) {
    Write-Host "Creating $name..." -NoNewline
    $sp = az ad sp create-for-rbac --name "sp-bastion-$name" --role $sps[$name] --scopes "/subscriptions/$subscriptionId" --query "{appId:appId, password:password, tenant:tenant}" -o json | ConvertFrom-Json
    az keyvault secret set --vault-name $vaultName --name "$name-AppId" --value $sp.appId --output none
    az keyvault secret set --vault-name $vaultName --name "$name-Password" --value $sp.password --output none
    az keyvault secret set --vault-name $vaultName --name "$name-TenantId" --value $sp.tenant --output none
    Write-Host " DONE" -ForegroundColor Green
}

# Store DataDog keys
az keyvault secret set --vault-name $vaultName --name "DataDog-API-Key" --value $DataDogAPIKey --output none
az keyvault secret set --vault-name $vaultName --name "DataDog-App-Key" --value $DataDogAppKey --output none
az keyvault secret set --vault-name $vaultName --name "Azure-Subscription-ID" --value $subscriptionId --output none

Write-Host ""
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "Key Vault: $vaultName" -ForegroundColor Cyan
Write-Host "Service Principals: 8 created" -ForegroundColor White
Write-Host ""
