# PYX Health - Deploy DataDog Alerting

## PURPOSE
Sets up DataDog monitors and scheduled tasks on Bastion VM

## SCRIPT
Run on the Bastion VM:
```powershell
cd C:\Scripts

# Deploy monitors
.\Deploy-DataDog-Alerting.ps1 -Mode deploy -KeyVaultName "kv-pyxhealth-XXXX"

# Schedule tasks
.\Deploy-DataDog-Alerting.ps1 -Mode schedule -KeyVaultName "kv-pyxhealth-XXXX"
```

## WHAT IT CREATES
- 10+ DataDog monitors (CPU, memory, disk, network, etc.)
- 8 scheduled tasks (one per Service Principal)
- Windows Task Scheduler jobs for automation

## MONITORS CREATED
- VM CPU Usage (>85%)
- VM Memory Low (<1GB)
- VM Disk Space (>85%)
- Storage Account Capacity
- App Service Response Time
- SQL Database DTU
- Network Errors
- Daily Cost Spike

## TIME
20 minutes

## PREREQUISITES
- Bastion VM deployed
- Key Vault created with Service Principals
- DataDog account active

## SAFE
Yes - Only creates monitors and tasks

## COST SAVINGS
\,000 - \,000 annually vs Azure Monitor

## JIRA
Attach this document to: Story - DataDog Monitor Deployment
