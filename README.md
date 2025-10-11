# PYEX Azure Automation Suite

Complete automation for Azure.

## Quick Start

Deploy Bastion VM:
```powershell
$password = ConvertTo-SecureString 'Pass123!' -AsPlainText -Force
.\Deploy-Bastion-VM.ps1 -ResourceGroupName 'RG-Bastion' -Location 'eastus' -VMName 'Bastion-VM' -AdminUsername 'admin' -AdminPassword $password
```n
## Scripts
1. Deploy-Bastion-VM.ps1 - Main deployment
2. Ultimate-Multi-Subscription-Audit.ps1 - Security audit
3. Azure-Monitor-Multi-Sub.ps1 - Monitoring
4. Cost-Optimization-Multi-Sub.ps1 - Cost analysis
5. Enable-MFA-All-Users.ps1 - MFA setup
6. Monthly-MFA-Report.ps1 - MFA reports
7. Auto-Enable-MFA-New-Users.ps1 - New user checks

## Scheduled Tasks
- Azure Monitor: Mon/Thu 8AM
- Cost Optimization: Mon/Thu 9AM
- Security Audit: Tue/Fri 8AM
- AD Security: Tue/Fri 9AM

## MFA Setup (on Bastion VM)
```powershell
cd C:\PYEX-Automation\Scripts
.\Enable-MFA-All-Users.ps1
```n
## Reports
Location: C:\PYEX-Automation\Reports\

