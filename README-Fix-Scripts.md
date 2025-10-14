# PYX HEALTH - AZURE FIX SCRIPTS

## OVERVIEW

These scripts fix specific security and configuration issues found in the Azure audit.

## SCRIPTS

### 1. Fix-NSG-Internet-Access.ps1
**Fixes:** Ports 3389, 443, 990, 9855 exposed to Internet
**What it does:** Restricts NSG rules to specific IP address
**Usage:**
```powershell
.\Fix-NSG-Internet-Access.ps1 -SourceIP "YOUR_PUBLIC_IP"
```
**Safe:** Yes - Changes are reversible

---

### 2. Fix-Storage-Security.ps1
**Fixes:** Storage accessible from all networks, public blob access
**What it does:**
- Configures storage account firewalls (deny all)
- Disables public blob access
**Usage:**
```powershell
.\Fix-Storage-Security.ps1
```
**Safe:** Yes - May need to add trusted IPs after

---

### 3. Fix-KeyVault-Security.ps1
**Fixes:** Soft delete not enabled, purge protection not enabled
**What it does:**
- Enables soft delete (90 days)
- Enables purge protection
**Usage:**
```powershell
.\Fix-KeyVault-Security.ps1
```
**Safe:** Yes - Changes are PERMANENT (cannot be reversed)

---

### 4. Fix-SQL-Security.ps1
**Fixes:** Allow Azure Services rule, auditing not enabled
**What it does:**
- Removes "Allow Azure Services" firewall rule
- Enables SQL auditing
**Usage:**
```powershell
.\Fix-SQL-Security.ps1
```
**Safe:** Mostly - May need to configure VNet service endpoints

---

### 5. Fix-RBAC-Issues.ps1
**Fixes:** Stale assignments, excessive Owner roles
**What it does:**
- Removes stale role assignments
- Reports users with Owner role
**Usage:**
```powershell
.\Fix-RBAC-Issues.ps1
```
**Safe:** Yes - Only removes deleted principals

---

### 6. Fix-Disabled-Alerts.ps1
**Fixes:** Disabled alert rules
**What it does:** Enables all disabled metric alert rules
**Usage:**
```powershell
.\Fix-Disabled-Alerts.ps1
```
**Safe:** Yes - Just enables existing alerts

---

### 7. Fix-VM-Diagnostics.ps1
**Fixes:** No diagnostic logging on VMs
**What it does:** Enables boot diagnostics
**Usage:**
```powershell
.\Fix-VM-Diagnostics.ps1
```
**Safe:** Yes - No production impact

---

### 8. Enable-DDoS-Protection.ps1
**Fixes:** DDoS protection not enabled
**What it does:** Reports VNets without DDoS protection
**Usage:**
```powershell
.\Enable-DDoS-Protection.ps1
```
**Safe:** Yes - Report only (DDoS costs ,944/month)

---

### 9. Cleanup-Unused-Resources.ps1
**Fixes:** Empty resource groups, unused public IPs
**What it does:**
- Deletes empty resource groups
- Deletes unused public IPs
**Usage:**
```powershell
.\Cleanup-Unused-Resources.ps1
```
**Safe:** Mostly - Reviews before deleting

---

## RECOMMENDED ORDER

**SAFEST FIRST:**
1. Fix-VM-Diagnostics.ps1 (zero risk)
2. Fix-Disabled-Alerts.ps1 (zero risk)
3. Fix-Storage-Security.ps1 (low risk)
4. Fix-KeyVault-Security.ps1 (low risk, permanent)
5. Fix-RBAC-Issues.ps1 (low risk)
6. Cleanup-Unused-Resources.ps1 (low risk)
7. Fix-SQL-Security.ps1 (medium risk - test first)
8. Fix-NSG-Internet-Access.ps1 (high risk - test first)

**DO NOT RUN IN PRODUCTION WITHOUT TESTING:**
- Fix-NSG-Internet-Access.ps1 (may break connectivity)
- Fix-SQL-Security.ps1 (may break database access)
- Fix-Storage-Security.ps1 (may break storage access)

---

## ISSUES NOT FIXED BY SCRIPTS

These require manual review:

**Security Center (508 recommendations):** Review in Azure Portal
**Policy Violations (721 issues):** Review in Azure Policy
**VM Oversizing:** Review utilization and downsize manually
**Excessive Owner Roles:** Review and reassign manually

---

## BACKUP LOCATIONS

All scripts create backups before making changes:
```
C:\Azure-Fixes-Backup\NSG-Rules\
C:\Azure-Fixes-Backup\Storage\
```

---

## SUPPORT

For questions or issues, check the backup files and rollback if needed.
All changes are logged during execution.

---

**Last Updated:** 2025-10-14
**Client:** PYX Health
**Version:** 1.0
