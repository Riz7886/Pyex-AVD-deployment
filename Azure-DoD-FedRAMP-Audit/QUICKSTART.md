# Quick Start Guide - 5 Minutes to Your First Audit

## Step 1: Install (2 min)
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
Import-Module Az
```

## Step 2: Connect (1 min)
```powershell
Connect-AzAccount
Get-AzContext
```

## Step 3: Run Audit (1 command)
```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions
```

The HTML report will open automatically!

## What You Get

- Executive dashboard with risk levels
- Complete RBAC analysis
- Failed login attempts (90 days)
- Network security issues
- Storage misconfigurations
- VM security gaps
- Key Vault vulnerabilities
- CSV exports for detailed analysis

## Next Steps

1. Review HTML report
2. Address critical findings (24 hours)
3. Fix high severity issues (7 days)
4. Create POAM for tracking
5. Schedule monthly audits
