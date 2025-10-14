# BASTION AUTOMATION

## STEP 1: Deploy Bastion

.\Deploy-Bastion-VM.ps1

## STEP 2: Complete Setup

.\Complete-Bastion-Setup.ps1 -Location eastus -DataDogAPIKey YOUR_KEY -DataDogAppKey YOUR_APP_KEY

Creates 1 Key Vault and 8 Service Principals

## STEP 3: Setup DataDog on Bastion

Login to Bastion VM and run:

cd C:\Scripts
.\Deploy-DataDog-Alerting.ps1 -Mode deploy -KeyVaultName YOUR_VAULT_NAME
.\Deploy-DataDog-Alerting.ps1 -Mode schedule -KeyVaultName YOUR_VAULT_NAME

## Service Principals

- DataDog-Monitor
- Azure-Monitor
- Security-Audit
- Cost-Optimization
- IAM-Audit
- Key-Rotation
- Backup-Verification
- Health-Check

Saves 10K-30K dollars annually
