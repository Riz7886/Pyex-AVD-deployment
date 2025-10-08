# Azure DevOps & Security Automation Suite

Professional Azure deployment, security audit, and IAM monitoring scripts.

## Core Scripts

### AVD Deployment
- **Deploy-AVD.ps1** - Deploy complete Azure Virtual Desktop environment
- **Audit-Complete.ps1** - Comprehensive AVD environment audit

### Azure Security Analysis
- **Analyze-AzureEnvironment.ps1** - Detect RBAC, Network, Security issues
- **Execute-AzureFixes.ps1** - Safe remediation with rollback capability

### IAM Security Monitoring
- **IAM-Audit-MINIMAL.ps1** - Identity and Access Management security audit
- **Schedule-IAMAudit.ps1** - Automated bi-weekly audits
- **Send-IAMReport.ps1** - Email reports to stakeholders

## Quick Start

### Deploy AVD
\\\powershell
Connect-AzAccount
.\Deploy-AVD.ps1 -TargetUsers 10 -CompanyName "YourCompany"
\\\

### Run IAM Security Audit
\\\powershell
Connect-AzAccount
.\IAM-Audit-MINIMAL.ps1
\\\

### Analyze Azure Environment
\\\powershell
Connect-AzAccount
.\Analyze-AzureEnvironment.ps1
\\\

## Features

- Professional enterprise-grade scripts
- No company-specific names
- Clean, tested code
- Comprehensive documentation
- Production-ready

## Repository Structure

\\\
/
├── Deploy-AVD.ps1
├── Audit-Complete.ps1
├── Analyze-AzureEnvironment.ps1
├── Execute-AzureFixes.ps1
├── IAM-Audit-MINIMAL.ps1
├── Schedule-IAMAudit.ps1
├── Send-IAMReport.ps1
├── README.md
├── Configuration/
├── Documentation/
└── Scripts/
\\\

## Requirements

- Azure PowerShell
- Azure subscription access
- PowerShell 5.1 or higher

## Installation

\\\powershell
Install-Module -Name Az -Scope CurrentUser
Connect-AzAccount
\\\

## License

Internal use - Professional toolkit

---

Last Updated: 2025-10-08
