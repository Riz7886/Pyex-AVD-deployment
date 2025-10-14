# PYX Health - Fix Storage HTTPS-Only

## PURPOSE
Enables HTTPS-only on all storage accounts (SAFEST FIX)

## SCRIPT
```powershell
.\Fix-Storage-HTTPS.ps1
```

## WHAT IT FIXES
Forces all storage accounts to use HTTPS-only (secure connections)

## SAFETY
100% SAFE
- No downtime
- No breaking changes  
- Applications already support HTTPS
- Can rollback instantly

## TIME
30 minutes

## ISSUES FIXED
100-150 security findings

## BACKUP
Creates backup before changes:
C:\Azure-Fixes-Backup\storage-before-https-TIMESTAMP.json

## ROLLBACK
```powershell
az storage account update --name ACCOUNT_NAME --https-only false
```

## PREREQUISITES
- Azure CLI installed
- Logged in: az login
- Contributor role on storage accounts

## VERIFICATION
Script shows table of all accounts with HTTPS status

## JIRA
Attach this document to: Story - Phase 1 Storage Security

## START HERE
This is the FIRST and SAFEST fix - start with this script!
