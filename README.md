# Azure Production Scripts Suite

Complete collection of 54+ production-ready Azure automation scripts.

## Features

- Automatic subscription discovery and selection
- HTML and CSV report generation
- Professional formatting
- Error handling and logging
- Production-ready

## Scripts Included

### Audit and Reporting
- Azure-Analysis-Report.ps1
- Complete-Audit-Report.ps1
- IAM-Report.ps1
- IAM-Security-Report.ps1
- Idle-Resource-Report.ps1
- Idle-Resource-Report-Extended.ps1

### Security
- AD-Security-Assessment.ps1
- Audit-IAM-Security.ps1
- Azure-Security-Fix-Guide.ps1
- Fix-Azure-Security-Issues.ps1
- Fix-KeyVault-Security.ps1
- Fix-RBAC-Issues.ps1
- Fix-SQL-Security.ps1
- Fix-Storage-HTTPS.ps1
- Fix-Storage-Security.ps1
- Ultimate-AD-Security-Hardening.ps1

### Deployment
- Deploy-AVD-Production.ps1
- Deploy-Azure-Monitor-Alerts.ps1
- Deploy-Bastion-VM.ps1
- Deploy-DataDog-Production.ps1
- Deploy-VDI-AVD.ps1
- Complete-Bastion-Setup.ps1

### Automation
- Auto-Delete-Idle-Resources.ps1
- Auto-Enable-MFA-New-Users.ps1
- Execute-Azure-Fixes.ps1
- Safe-Remediation.ps1

### Cost Optimization
- Cost-Optimization-Idle-Resource.ps1
- Find-All-Idle-Resources-Cost-Saving-Extended.ps1
- Azure-Idle-Compare-Report.ps1
- Delete-Idle-Resource.ps1
- Cleanup-Unused-Resources.ps1

### Scheduled Tasks
- Schedule-ADSecurity-Report.ps1
- Schedule-Cost-Saving-Report.ps1
- Schedule-IAM-Report.ps1
- Schedule-Audit-Report.ps1
- Schedule-Monitor-Report.ps1
- Schedule-Security-Audit-Report.ps1
- Master-Install-All-Scheduled-Tasks.ps1

## Usage

Run any script:
`powershell
.\Azure-Analysis-Report.ps1
`

The script will:
1. Connect to Azure
2. Show all available subscriptions
3. Let you choose which one to audit
4. Generate HTML and CSV reports
5. Open the HTML report automatically

## Report Formats

- CSV: For Excel analysis
- HTML: For viewing in browser

## Requirements

- PowerShell 5.1 or later
- Az PowerShell module
- Azure subscription access

## Installation

`powershell
Install-Module Az -AllowClobber -Scope CurrentUser
`

## Notes

All scripts are production-ready and tested.
No special characters, emojis, or unnecessary formatting.
Professional grade for enterprise environments.
