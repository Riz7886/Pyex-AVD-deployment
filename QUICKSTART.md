# Quick Start Guide - Azure DoD and FedRAMP Audit Script

## 5-Minute Setup and Execution

### Step 1: Install Prerequisites (2 minutes)

Open PowerShell as Administrator and run:

```powershell
# Install Azure PowerShell modules
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force

# Import the modules
Import-Module Az
```

### Step 2: Authenticate to Azure (1 minute)

```powershell
# Connect to your Azure environment
Connect-AzAccount

# Verify connection
Get-AzContext

# Optional: Switch to specific subscription
Set-AzContext -SubscriptionId "your-subscription-id"
```

### Step 3: Run the Audit (2 minutes)

```powershell
# Navigate to script directory
cd C:\Path\To\Script

# Run audit on current subscription
.\Azure-DoD-FedRAMP-Audit.ps1

# OR run on all subscriptions
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions

# OR run on specific subscriptions
.\Azure-DoD-FedRAMP-Audit.ps1 -SubscriptionIds "sub-1", "sub-2"
```

The script will:
1. Validate required modules
2. Connect to Azure
3. Enumerate subscriptions
4. Perform comprehensive security audit
5. Generate HTML report and CSV exports
6. Automatically open the report in your browser

## What You Get

After execution, you will have:

- **Professional HTML Report** with:
  - Executive dashboard
  - Risk assessment
  - NIST 800-53 control status
  - Critical findings
  - Detailed security analysis
  - Actionable recommendations

- **CSV Data Files** for:
  - RBAC assignments
  - Suspicious activities
  - Security findings
  - Network issues
  - Storage issues
  - VM security
  - Key Vault security

- **Execution Log** with full audit trail

## Common Usage Scenarios

### Scenario 1: Pre-Assessment Audit
```powershell
# Run comprehensive audit before compliance assessment
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions -ActivityLogDays 90
```

### Scenario 2: Monthly Compliance Check
```powershell
# Regular monthly audit
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions -OutputPath "C:\ComplianceReports\$(Get-Date -Format 'yyyy-MM')"
```

### Scenario 3: Incident Investigation
```powershell
# Extended activity log review after security incident
.\Azure-DoD-FedRAMP-Audit.ps1 -ActivityLogDays 180
```

### Scenario 4: Specific Subscription Audit
```powershell
# Audit production subscription only
$prodSubId = "12345678-1234-1234-1234-123456789012"
.\Azure-DoD-FedRAMP-Audit.ps1 -SubscriptionIds $prodSubId
```

## Understanding the Report

### Executive Summary Section
- **Critical Findings**: Requires immediate action within 24 hours
- **High Severity**: Address within 7 days
- **Medium Severity**: Remediate within 30 days
- **Low Severity**: Address within 90 days

### NIST 800-53 Control Status
Color-coded status for each control family:
- **Red**: Critical issues, non-compliant
- **Orange**: High issues, partial compliance
- **Yellow**: Medium issues, mostly compliant
- **Green**: Low/no issues, compliant

### Priority Actions
Focus on these areas first:
1. Review all critical and high severity findings
2. Check for unauthorized access attempts
3. Validate RBAC privileged assignments
4. Address network security exposures
5. Fix storage encryption issues

## Troubleshooting Quick Fixes

### Issue: "Module not found"
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
```

### Issue: "Access denied"
```powershell
# Verify you have Reader role
Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id
```

### Issue: "No subscriptions found"
```powershell
# List available subscriptions
Get-AzSubscription
# Set context to specific subscription
Set-AzContext -SubscriptionId "your-sub-id"
```

### Issue: Script execution policy
```powershell
# Allow script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Next Steps After Audit

1. **Review the HTML Report**
   - Open automatically after execution
   - Review executive summary
   - Identify critical findings

2. **Export Findings**
   - Share CSV files with security team
   - Import into ticketing system
   - Track remediation progress

3. **Create POAM**
   - Document all findings
   - Assign owners
   - Set remediation dates
   - Track closure

4. **Implement Remediations**
   - Address critical issues first
   - Follow recommendations
   - Verify fixes
   - Re-run audit

5. **Schedule Regular Audits**
   - Monthly for production
   - Quarterly for non-production
   - After major changes
   - Before assessments

## Best Practices

### Before Running
- Ensure you have appropriate permissions
- Verify network connectivity to Azure
- Check available disk space for reports
- Close other intensive applications

### During Execution
- Do not interrupt the script
- Monitor for error messages
- Note any warnings
- Be patient with large environments

### After Completion
- Review findings immediately
- Share with stakeholders
- Archive reports securely
- Plan remediation activities

## Example: Complete Audit Workflow

```powershell
# Step 1: Prepare environment
Install-Module -Name Az -AllowClobber -Force
Import-Module Az

# Step 2: Connect to Azure
Connect-AzAccount
Get-AzSubscription

# Step 3: Create output directory
$outputDir = "C:\AuditReports\$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $outputDir -Force

# Step 4: Run comprehensive audit
.\Azure-DoD-FedRAMP-Audit.ps1 `
    -AllSubscriptions `
    -OutputPath $outputDir `
    -ActivityLogDays 90 `
    -Verbose

# Step 5: Review results
# HTML report opens automatically
# Review CSV files in output directory

# Step 6: Share findings
Get-ChildItem $outputDir | Format-Table Name, Length, LastWriteTime
```

## Getting Help

### Check Execution Log
```powershell
# View execution log
Get-Content ".\AuditReports\*\audit_execution.log" -Tail 50
```

### Verbose Output
```powershell
# Run with detailed logging
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions -Verbose
```

### Module Information
```powershell
# Check installed module versions
Get-InstalledModule -Name Az*
```

## Security Notes

- Script is READ-ONLY - no changes made to your environment
- Reports contain sensitive data - handle appropriately
- Use secure workstation for audit activities
- Follow your organization's data handling procedures
- Encrypt and protect audit reports
- Restrict access to audit results

## Support

For issues or questions:
1. Check the README.md for detailed documentation
2. Review execution logs for error details
3. Verify prerequisites are met
4. Consult your security team
5. Contact your compliance officer

---

**Ready to audit?** Simply run:
```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions
```

Your comprehensive DoD and FedRAMP compliance report will be ready in minutes!
