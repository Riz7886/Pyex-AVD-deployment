# Azure Production Scripts Suite

Complete collection of 64+ production-ready Azure automation scripts for enterprise environments.

## Overview

Professional Azure automation suite with complete inventory collection, safety features, and enterprise-grade reporting.

## All Scripts (64+)

### Original 10 Audit Scripts (Full Implementation)
1. **1-RBAC-Audit.ps1** - Complete RBAC and permissions audit
2. **2-NSG-Audit.ps1** - Network Security Group rules audit
3. **3-Encryption-Audit.ps1** - Encryption and security audit
4. **4-Backup-Audit.ps1** - Backup and disaster recovery audit
5. **5-Cost-Tagging-Audit.ps1** - Cost management and tagging audit
6. **6-Policy-Compliance-Audit.ps1** - Azure Policy compliance audit
7. **7-Identity-AAD-Audit.ps1** - Azure AD and identity audit
8. **8-SecurityCenter-Audit.ps1** - Security Center recommendations audit
9. **9-AuditLog-Collection.ps1** - Activity log collection and analysis
10. **RUN-ALL-AUDITS.ps1** - Execute all audits at once

### Audit and Reporting Scripts (11 scripts)
- Azure-Analysis-Report.ps1 - Complete environment analysis
- Complete-Audit-Report.ps1 - Comprehensive security audit
- IAM-Report.ps1 - IAM and permissions report
- IAM-Security-Report.ps1 - IAM security analysis
- Idle-Resource-Report.ps1 - Find idle resources
- Idle-Resource-Report-Extended.ps1 - Detailed idle resource analysis with cost savings
- AD-Security-Assessment.ps1 - Active Directory security assessment
- Analyze-Azure-Environment.ps1 - Complete environment analysis
- Audit-IAM-Security.ps1 - IAM security compliance audit
- Azure-Idle-Compare-Report.ps1 - Compare idle resources across timeframes
- Ultimate-Multi-Subscription-Audit-Report.ps1 - Multi-subscription audit

### Security and Compliance Scripts (15 scripts)
- Azure-Security-Fix-Guide.ps1 - Security remediation guide
- Fix-Azure-Security-Issues.ps1 - Fix identified security issues
- Fix-KeyVault-Security.ps1 - Fix Key Vault security issues
- Fix-RBAC-Issues.ps1 - Fix RBAC permission issues
- Fix-SQL-Security.ps1 - Fix SQL Database security
- Fix-Storage-HTTPS.ps1 - Enforce HTTPS on storage accounts
- Fix-Storage-Security.ps1 - Fix storage account security
- Fix-VM-Diagnostics.ps1 - Enable VM diagnostics
- Execute-Azure-Fixes.ps1 - Execute all recommended fixes
- Safe-Remediation.ps1 - Safe remediation with backups
- Ultimate-AD-Security-Hardening.ps1 - Complete AD security hardening
- Enable-MFA-All-Users.ps1 - Enable MFA for all users
- Auto-Enable-MFA-New-Users.ps1 - Auto-enable MFA for new users
- Enable-DDoS.ps1 - Enable DDoS protection
- Monthly-MFA-Report.ps1 - Monthly MFA compliance report

### Cost Optimization Scripts (6 scripts)
- Cost-Optimization-Idle-Resource.ps1 - Cost optimization through idle resource management
- Find-All-Idle-Resources-Cost-Saving-Extended.ps1 - Extended idle resource cost analysis
- Delete-Idle-Resource.ps1 - Delete specific idle resources
- Auto-Delete-Idle-Resources.ps1 - Automatically delete identified idle resources
- Cleanup-Unused-Resources.ps1 - Clean up unused Azure resources
- Check-Subscription.ps1 - Subscription health check

### Deployment Automation Scripts (7 scripts)
- Deploy-AVD-Production.ps1 - Deploy Azure Virtual Desktop
- Deploy-Azure-Monitor-Alerts.ps1 - Deploy monitoring alerts
- Deploy-Bastion-VM.ps1 - Deploy Bastion for VM access
- Deploy-DataDog-Production.ps1 - Deploy DataDog monitoring
- Deploy-VDI-AVD.ps1 - Deploy VDI infrastructure with AVD
- Complete-Bastion-Setup.ps1 - Complete Azure Bastion deployment
- Migrate-DC-OnPrem-To-Azure.ps1 - Migrate domain controller to Azure

### Scheduled Tasks Scripts (9 scripts)
- Schedule-ADSecurity-Report.ps1 - Schedule AD security report task
- Schedule-Cost-Saving-Report.ps1 - Schedule cost saving report task
- Schedule-IAM-Report.ps1 - Schedule IAM report task
- Schedule-Audit-Report.ps1 - Schedule audit report task
- Schedule-Monitor-Report.ps1 - Schedule monitoring report task
- Schedule-Security-Audit-Report.ps1 - Schedule security audit task
- Master-Install-All-Scheduled-Tasks.ps1 - Install all scheduled tasks
- Send-IAM-Report.ps1 - Email IAM report
- Send-Monitor-Report.ps1 - Email monitoring report

### Device Management Scripts (3 scripts)
- Disable-MDNS-Intune-All-Devices.ps1 - Disable MDNS on all Intune devices
- Disable-NetBIOS-Intune-All-Devices.ps1 - Disable NetBIOS on all Intune devices
- Disable-WPAD-All-Devices.ps1 - Disable WPAD on all devices

### Additional Automation Scripts (3 scripts)
- Rotate-AppConfigure-Keys.ps1 - Rotate application configuration keys
- Azure-Monitor-Solution-Overview.ps1 - Azure Monitor deployment overview
- Check-Subscription.ps1 - Subscription health and configuration check

## Features

### Complete Azure Inventory Collection
Every script collects comprehensive Azure inventory including:
- Subscriptions and regions
- Resource groups
- Virtual machines and disks
- Virtual networks and subnets
- Network interfaces and public IPs
- Load balancers and application gateways
- Front Door profiles
- Storage accounts
- Key vaults
- SQL servers and databases
- App services
- Service principals
- AKS clusters
- Container instances
- Log Analytics workspaces
- Recovery Services vaults
- Managed identities
- **Everything in Azure!**

### Production Safety Features
- **Read-only mode** for all audit and report scripts
- **Confirmation prompts** for all modification scripts
- **WhatIf support** to preview changes
- **Selective operations** - you choose exactly what to modify/delete
- **Comprehensive error handling**
- **Detailed logging** for audit trail

### Professional Reporting
- **HTML reports** with modern, professional design
- **CSV exports** for Excel analysis
- **Cost analysis** with savings identification
- **Summary dashboards** with resource counts
- **Color-coded priorities** (Critical, High, Medium, Low)
- **Detailed findings tables**

## Quick Start

1. **Install Azure PowerShell module:**
`powershell
Install-Module Az -AllowClobber -Scope CurrentUser
`

2. **Run any script:**
`powershell
cd D:\Azure-Production-Scripts

# Run a complete audit
.\Complete-Audit-Report.ps1

# Find idle resources with cost savings
.\Idle-Resource-Report-Extended.ps1

# Get IAM report
.\IAM-Report.ps1

# Run all 10 original audits
.\RUN-ALL-AUDITS.ps1
`

3. **The script will:**
   - Connect to Azure
   - Show all available subscriptions
   - Let you choose which subscription to audit
   - Collect complete inventory
   - Generate HTML and CSV reports
   - Auto-open HTML report in browser

## Safety Examples

### Read-Only Scripts (Audits/Reports)
`powershell
.\Complete-Audit-Report.ps1
# This script is READ-ONLY
# It will NEVER modify your Azure environment
# Only reads and generates reports
`

### Modification Scripts (Fix/Delete)
`powershell
.\Delete-Idle-Resource.ps1
# Shows all idle resources
# You select which ones to delete
# Confirms EACH deletion before executing
`

### WhatIf Mode
`powershell
.\Fix-Storage-HTTPS.ps1 -WhatIf
# Shows what WOULD be changed
# Does NOT actually make changes
# Safe to run anytime
`

## Report Formats

### HTML Reports
- Professional styled reports
- Modern gradient design
- Summary cards with resource counts
- Cost savings identification
- Detailed findings tables
- Color-coded priorities
- Auto-opens in browser

### CSV Reports
- Excel-compatible format
- All data for analysis
- Easy to filter and sort
- Can be imported into Power BI

## Requirements

- PowerShell 5.1 or later
- Az PowerShell module
- Azure subscription access with appropriate permissions

## Directory Structure

`
Azure-Production-Scripts/
├── Reports/              # Generated reports (HTML and CSV)
├── Logs/                 # Execution logs
├── Scheduled-Tasks/      # Task scheduler related files
└── [64+ PowerShell scripts]
`

## Cost Savings

Scripts automatically identify cost savings opportunities:
- Idle virtual machines
- Unattached disks (~/month each)
- Unused public IPs (~/month each)
- Unattached NICs (~/month each)
- Empty resource groups
- Oversized resources

## Notes

- All scripts are production-ready and tested
- No special characters, emojis, or unnecessary formatting
- Professional grade for enterprise environments
- Suitable for MSPs and IT consultants
- Multi-tenant ready with subscription selection
- Complete audit trail with logging
- All modifications require confirmation

## Support

For issues or questions, please create an issue in the GitHub repository.

## License

Created for enterprise Azure automation and deployment.
