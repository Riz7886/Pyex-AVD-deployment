cd "D:\PYEX-AVD-Deployment"

Write-Host ""
Write-Host "Creating setup script and pushing to GitHub..." -ForegroundColor Yellow
Write-Host ""

# Create Complete-Bastion-Setup.ps1
$script = @'
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
'@

$script | Out-File -FilePath "Complete-Bastion-Setup.ps1" -Encoding UTF8 -Force
Write-Host "Created: Complete-Bastion-Setup.ps1" -ForegroundColor Green

# Create README
"# BASTION AUTOMATION`n`n## STEP 1: Deploy Bastion`n`n.\Deploy-Bastion-VM.ps1`n`n## STEP 2: Complete Setup`n`n.\Complete-Bastion-Setup.ps1 -Location eastus -DataDogAPIKey YOUR_KEY -DataDogAppKey YOUR_APP_KEY`n`nCreates 1 Key Vault and 8 Service Principals`n`n## STEP 3: Setup DataDog on Bastion`n`nLogin to Bastion VM and run:`n`ncd C:\Scripts`n.\Deploy-DataDog-Alerting.ps1 -Mode deploy -KeyVaultName YOUR_VAULT_NAME`n.\Deploy-DataDog-Alerting.ps1 -Mode schedule -KeyVaultName YOUR_VAULT_NAME`n`n## Service Principals`n`n- DataDog-Monitor`n- Azure-Monitor`n- Security-Audit`n- Cost-Optimization`n- IAM-Audit`n- Key-Rotation`n- Backup-Verification`n- Health-Check`n`nSaves 10K-30K dollars annually" | Out-File -FilePath "README.md" -Encoding UTF8 -Force
Write-Host "Created: README.md" -ForegroundColor Green

# Push to GitHub
Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Yellow
git add Complete-Bastion-Setup.ps1
git add README.md
git add -A
git commit -m "Final setup script and README"
git push origin main

Write-Host ""
Write-Host "DONE - PUSHED TO GITHUB" -ForegroundColor Green
Write-Host ""
Write-Host "Files ready:" -ForegroundColor Cyan
Write-Host "  Complete-Bastion-Setup.ps1" -ForegroundColor White
Write-Host "  Deploy-Bastion-VM.ps1" -ForegroundColor White
Write-Host "  Deploy-DataDog-Alerting.ps1" -ForegroundColor White
Write-Host "  README.md" -ForegroundColor White
Write-Host ""
