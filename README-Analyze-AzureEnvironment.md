# PYX Health - Analyze Azure Environment

## PURPOSE
Scans Azure subscription for security issues and generates HTML report

## SCRIPT
```powershell
.\Analyze-AzureEnvironment.ps1
```

## WHAT IT DOES
Scans for:
- Storage account security issues
- Key Vault configuration issues  
- Network Security Group rules
- RBAC permission issues
- Resource locks

## OUTPUT
HTML report: Azure-Security-Report.html

## TIME
5-10 minutes

## PREREQUISITES
- Azure CLI installed
- Logged in: az login
- Reader role minimum (Security Reader recommended)

## SAFE
100% SAFE - Read-only, no changes made

## TYPICAL FINDINGS
- 100-150 storage account issues
- 20-30 Key Vault issues
- 150-200 NSG rule issues
- 50-100 RBAC issues

## JIRA
Attach this document to: Story - Phase 6 Verification
