# PYX Health - Deploy Bastion VM

## PURPOSE
Deploys the Bastion automation server for PYX Health

## SCRIPT
```powershell
.\Deploy-Bastion-VM.ps1
```

## WHAT IT CREATES
- VM: vm-pyxhealth-bastion-prod
- Resource Group: rg-pyxhealth-bastion-prod
- Virtual Network and subnet
- Network Security Group
- Public IP address
- Software: Azure CLI, Git, PowerShell 7

## VM SIZE
Standard_D2s_v3 (2 vCPUs, 8 GB RAM)

## TIME
30-45 minutes

## PREREQUISITES
- Azure CLI installed
- Logged in: az login
- Contributor role on subscription

## SAFE
Yes - Creates new resources only

## COST
Approximately \-100/month for VM

## JIRA
Attach this document to: Story - Deploy Bastion Server
