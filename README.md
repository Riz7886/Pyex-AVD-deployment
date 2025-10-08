# health AVD Deployment - Professional Edition

## 📁 Directory Structure
`
health-AVD-Deployment/
├── Deploy-AVD.ps1           # Main deployment script
├── Audit-Complete.ps1       # Comprehensive audit script
├── Configuration/           # Deployment configurations & credentials
├── Audit-Reports/          # Audit reports (HTML + CSV files)
├── Documentation/          # Additional documentation
└── README.md              # This file
`

## 🚀 Quick Start

### 1. Deploy AVD Environment

**Basic Deployment (10 users):**
```powershell
.\Deploy-AVD.ps1 -TargetUsers 10 -CompanyName "Contoso"
```

**Production Deployment (50 users):**
```powershell
.\Deploy-AVD.ps1 -TargetUsers 50 -CompanyName "AcmeCorp" -Environment "prod" -Location "East US"
```

**Parameters:**
- -TargetUsers: Number of users (10, 20, 50, 100+)
- -CompanyName: Your company name (used for resource naming)
- -Environment: prod, dev, uat, or test (default: prod)
- -Location: Azure region (default: East US)

**What it does:**
- Auto-detects best VM size based on quota
- Creates professional resource names
- Deploys VMs, VNet, NSG, Storage, Key Vault
- Sets up AVD Host Pool, Workspace, App Group
- Saves credentials to Configuration/

---

### 2. Run Comprehensive Audit

**Audit All Environments:**
```powershell
.\Audit-Complete.ps1
```

**Custom Output Location:**
```powershell
.\Audit-Complete.ps1 -OutputDirectory "C:\Audits"
```

**What it audits:**
- All subscriptions & tenants
- All environments (prod/dev/uat/test)
- All resources with full details
- VNets, Subnets, NSGs, Route Tables
- Load Balancers, App Gateways
- RBAC permissions
- Security issues & recommendations
- Cost breakdown

**Output:**
- 1 HTML report (opens automatically)
- 15 detailed CSV files
- Security findings report

---

## 📊 Output Files

### After Deployment:
- Configuration/deployment-YYYYMMDD_HHMMSS.json - Credentials & details

### After Audit:
- Audit-Reports/Complete-Audit-YYYYMMDD_HHMMSS.html - Main report
- Audit-Reports/01-All-Resources-*.csv - All resources
- Audit-Reports/02-VMs-*.csv - Virtual machines
- Audit-Reports/03-VNets-*.csv - Virtual networks
- Audit-Reports/04-Subnets-*.csv - Subnets
- Audit-Reports/05-NSGs-*.csv - Network security groups
- Audit-Reports/06-NSG-Rules-*.csv - Security rules
- Audit-Reports/07-Route-Tables-*.csv - Route tables
- Audit-Reports/08-Load-Balancers-*.csv - Load balancers
- Audit-Reports/09-App-Gateways-*.csv - Application gateways
- Audit-Reports/10-Storage-Accounts-*.csv - Storage accounts
- Audit-Reports/11-Key-Vaults-*.csv - Key vaults
- Audit-Reports/12-Public-IPs-*.csv - Public IP addresses
- Audit-Reports/13-RBAC-*.csv - Role assignments
- Audit-Reports/14-Service-Principals-*.csv - Service principals
- Audit-Reports/15-Security-Issues-*.csv - Security findings

---

## 🔧 Prerequisites

- Azure PowerShell Module: Install-Module Az -AllowClobber -Force
- PowerShell 5.1 or later
- Administrator rights
- Active Azure subscription

---

## 💡 Common Scenarios

### Scenario 1: New Client Deployment
```powershell
# Deploy for 25 users
.\Deploy-AVD.ps1 -TargetUsers 25 -CompanyName "ClientCorp" -Environment "prod"

# Then audit the deployment
.\Audit-Complete.ps1
```

### Scenario 2: Audit Existing Environment
```powershell
# Just run the audit (no deployment needed)
.\Audit-Complete.ps1
```

### Scenario 3: Scale Up Deployment
```powershell
# Deploy additional capacity for 50 more users
.\Deploy-AVD.ps1 -TargetUsers 50 -CompanyName "ClientCorp" -Environment "prod"
```

---

## 📝 Notes

- Deployment takes 10-15 minutes per VM
- Audit runs across ALL subscriptions
- All credentials are saved securely in Configuration/
- HTML reports open automatically in your browser
- CSV files can be analyzed in Excel

---

## 🆘 Support

For issues or questions:
1. Check the generated HTML audit report
2. Review CSV files for detailed data
3. Check Configuration/ for deployment details

---

**Last Updated:** 2025-10-07
**Version:** 1.0 Professional Edition
