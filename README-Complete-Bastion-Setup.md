# PYX Health - Complete Bastion Setup

## PURPOSE
Creates Key Vault and 8 Service Principal accounts for PYX Health automation

## SCRIPT
```powershell
.\Complete-Bastion-Setup.ps1 -Location "eastus" -DataDogAPIKey "xxx" -DataDogAppKey "yyy"
```

## WHAT IT CREATES
- 1 Key Vault (kv-pyxhealth-XXXX)
- 8 Service Principal accounts
- Stores DataDog credentials
- Saves configuration to pyxhealth-config.json

## SERVICE PRINCIPALS CREATED
1. sp-pyxhealth-datadog-monitor (Reader)
2. sp-pyxhealth-azure-monitor (Reader)
3. sp-pyxhealth-security-audit (Security Reader)
4. sp-pyxhealth-cost-optimization (Cost Management Reader)
5. sp-pyxhealth-iam-audit (Reader)
6. sp-pyxhealth-key-rotation (Contributor)
7. sp-pyxhealth-backup-verification (Reader)
8. sp-pyxhealth-health-check (Reader)

## TIME
15 minutes

## PREREQUISITES
- Azure CLI installed
- Logged in: az login
- Contributor + User Access Administrator roles
- DataDog API keys

## SAFE
Yes - Creates new resources only, no modifications to existing

## JIRA
Attach this document to: Epic - DataDog Monitoring Setup
