#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - Bastion Automation Setup

.DESCRIPTION
    Creates Key Vault and Service Principals for PYX Health Bastion automation
    
.PARAMETER Location
    Azure region

.PARAMETER DataDogAPIKey
    DataDog API Key for PYX Health monitoring

.PARAMETER DataDogAppKey
    DataDog Application Key for PYX Health monitoring

.EXAMPLE
    .\Complete-Bastion-Setup.ps1 -Location "eastus" -DataDogAPIKey "xxx" -DataDogAppKey "yyy"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$DataDogAPIKey,
    
    [Parameter(Mandatory=$true)]
    [string]$DataDogAppKey
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - BASTION AUTOMATION SETUP" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$subscriptionId = az account show --query id -o tsv
$tenantId = az account show --query tenantId -o tsv
$timestamp = Get-Date -Format "yyyyMMddHHmm"

# Professional PYX Health naming conventions
$resourceGroup = "rg-pyxhealth-bastion-prod"
$vaultName = "kv-pyxhealth-$(Get-Random -Minimum 1000 -Maximum 9999)"

Write-Host "Client: PYX Health" -ForegroundColor White
Write-Host "Subscription: $subscriptionId" -ForegroundColor White
Write-Host "Location: $Location" -ForegroundColor White
Write-Host ""

# ============================================================
# STEP 1: CREATE RESOURCE GROUP
# ============================================================

Write-Host "[1/3] Creating PYX Health Resource Group..." -ForegroundColor Yellow

$rgExists = az group exists --name $resourceGroup -o tsv
if ($rgExists -eq "false") {
    az group create `
        --name $resourceGroup `
        --location $Location `
        --tags Client=PyxHealth Environment=Production ManagedBy=Bastion-Automation `
        --output none
    Write-Host "  Created: $resourceGroup" -ForegroundColor Green
} else {
    Write-Host "  Already exists: $resourceGroup" -ForegroundColor Green
}

# ============================================================
# STEP 2: CREATE KEY VAULT
# ============================================================

Write-Host ""
Write-Host "[2/3] Creating PYX Health Key Vault..." -ForegroundColor Yellow

az keyvault create `
    --name $vaultName `
    --resource-group $resourceGroup `
    --location $Location `
    --enable-rbac-authorization false `
    --enabled-for-deployment true `
    --enabled-for-template-deployment true `
    --tags Client=PyxHealth Environment=Production Purpose=Bastion-Automation `
    --output none

Write-Host "  Created: $vaultName" -ForegroundColor Green

# ============================================================
# STEP 3: CREATE 8 SERVICE PRINCIPALS
# ============================================================

Write-Host ""
Write-Host "[3/3] Creating 8 PYX Health Service Principals..." -ForegroundColor Yellow

$servicePrincipals = @{
    "datadog-monitor" = @{
        DisplayName = "sp-pyxhealth-datadog-monitor"
        Role = "Reader"
        Description = "PYX Health DataDog monitoring and alerting"
    }
    "azure-monitor" = @{
        DisplayName = "sp-pyxhealth-azure-monitor"
        Role = "Reader"
        Description = "PYX Health Azure Monitor reporting"
    }
    "security-audit" = @{
        DisplayName = "sp-pyxhealth-security-audit"
        Role = "Security Reader"
        Description = "PYX Health security compliance audits"
    }
    "cost-optimization" = @{
        DisplayName = "sp-pyxhealth-cost-optimization"
        Role = "Cost Management Reader"
        Description = "PYX Health cost analysis and optimization"
    }
    "iam-audit" = @{
        DisplayName = "sp-pyxhealth-iam-audit"
        Role = "Reader"
        Description = "PYX Health identity and access management audits"
    }
    "key-rotation" = @{
        DisplayName = "sp-pyxhealth-key-rotation"
        Role = "Contributor"
        Description = "PYX Health automatic key rotation"
    }
    "backup-verification" = @{
        DisplayName = "sp-pyxhealth-backup-verification"
        Role = "Reader"
        Description = "PYX Health backup validation and verification"
    }
    "health-check" = @{
        DisplayName = "sp-pyxhealth-health-check"
        Role = "Reader"
        Description = "PYX Health system health monitoring"
    }
}

Write-Host ""

foreach ($spKey in $servicePrincipals.Keys) {
    $spConfig = $servicePrincipals[$spKey]
    
    Write-Host "  Creating: $($spConfig.DisplayName)..." -NoNewline
    
    # Create Service Principal
    $sp = az ad sp create-for-rbac `
        --name $spConfig.DisplayName `
        --role $spConfig.Role `
        --scopes "/subscriptions/$subscriptionId" `
        --query "{appId:appId, password:password, tenant:tenant}" -o json | ConvertFrom-Json
    
    # Store credentials in Key Vault with PYX Health naming
    $secretPrefix = "PyxHealth-$($spKey)"
    
    az keyvault secret set `
        --vault-name $vaultName `
        --name "$secretPrefix-AppId" `
        --value $sp.appId `
        --description "$($spConfig.Description)" `
        --tags ServicePrincipal=$($spConfig.DisplayName) Client=PyxHealth `
        --output none
    
    az keyvault secret set `
        --vault-name $vaultName `
        --name "$secretPrefix-Password" `
        --value $sp.password `
        --description "Password for $($spConfig.DisplayName)" `
        --tags ServicePrincipal=$($spConfig.DisplayName) Client=PyxHealth `
        --output none
    
    az keyvault secret set `
        --vault-name $vaultName `
        --name "$secretPrefix-TenantId" `
        --value $sp.tenant `
        --description "Tenant ID for PYX Health" `
        --tags Client=PyxHealth `
        --output none
    
    Write-Host " DONE" -ForegroundColor Green
}

# ============================================================
# STEP 4: STORE DATADOG AND AZURE CREDENTIALS
# ============================================================

Write-Host ""
Write-Host "Storing DataDog credentials and Azure information..." -ForegroundColor Yellow

# Store DataDog keys with PYX Health branding
az keyvault secret set `
    --vault-name $vaultName `
    --name "PyxHealth-DataDog-API-Key" `
    --value $DataDogAPIKey `
    --description "PYX Health DataDog API Key" `
    --tags Client=PyxHealth Service=DataDog `
    --output none

az keyvault secret set `
    --vault-name $vaultName `
    --name "PyxHealth-DataDog-App-Key" `
    --value $DataDogAppKey `
    --description "PYX Health DataDog Application Key" `
    --tags Client=PyxHealth Service=DataDog `
    --output none

# Store Azure subscription info
az keyvault secret set `
    --vault-name $vaultName `
    --name "PyxHealth-Azure-Subscription-ID" `
    --value $subscriptionId `
    --description "PYX Health Azure Subscription ID" `
    --tags Client=PyxHealth `
    --output none

az keyvault secret set `
    --vault-name $vaultName `
    --name "PyxHealth-Azure-Tenant-ID" `
    --value $tenantId `
    --description "PYX Health Azure Tenant ID" `
    --tags Client=PyxHealth `
    --output none

Write-Host "  All credentials stored!" -ForegroundColor Green

# ============================================================
# SUMMARY
# ============================================================

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  PYX HEALTH SETUP COMPLETE" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "CLIENT: PYX Health" -ForegroundColor Cyan
Write-Host "RESOURCE GROUP: $resourceGroup" -ForegroundColor White
Write-Host "KEY VAULT: $vaultName" -ForegroundColor White
Write-Host "SERVICE PRINCIPALS: 8 created" -ForegroundColor White
Write-Host ""
Write-Host "Service Principal Accounts Created:" -ForegroundColor Cyan

foreach ($spKey in $servicePrincipals.Keys) {
    Write-Host "  - $($servicePrincipals[$spKey].DisplayName)" -ForegroundColor White
}

Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Deploy Bastion: .\Deploy-Bastion-VM.ps1" -ForegroundColor White
Write-Host "  2. Setup DataDog on Bastion VM using Key Vault: $vaultName" -ForegroundColor White
Write-Host ""
Write-Host "All credentials securely stored in Key Vault with PYX Health branding" -ForegroundColor Green
Write-Host ""

# Save configuration for next steps
$config = @{
    Client = "PYX Health"
    KeyVaultName = $vaultName
    ResourceGroup = $resourceGroup
    Timestamp = $timestamp
    ServicePrincipals = $servicePrincipals.Keys | ForEach-Object { $servicePrincipals[$_].DisplayName }
}

$config | ConvertTo-Json | Out-File -FilePath "pyxhealth-config.json" -Encoding UTF8
Write-Host "Configuration saved to: pyxhealth-config.json" -ForegroundColor Cyan
Write-Host ""
