# 🔍 Azure Environment Analyzer & Auto-Remediation Suite

**Enterprise-grade PowerShell toolkit for detecting and fixing Azure environment issues**

---

## 🎯 **What It Does**

This comprehensive solution **automatically detects** and **optionally fixes** issues in your Azure environment:

### **Detection Capabilities:**
- ✅ **RBAC & Permissions** - Overly permissive roles, stale assignments, custom role wildcards
- ✅ **Network Security** - Unrestricted NSG rules, missing NSGs, dangerous port exposure
- ✅ **Security & Compliance** - Unencrypted resources, public access, TLS versions
- ✅ **User Access** - Guest users with elevated permissions, MFA issues
- ✅ **Resource Configuration** - Untagged resources, location sprawl, misconfigurations
- ✅ **SSO & Authentication** - Login issues, authentication problems
- ✅ **Cost Optimization** - Resource inefficiencies, unused resources

### **Key Features:**
- 🛡️ **Safe by Default** - Detects issues but NEVER fixes without approval
- 📊 **Professional Reports** - HTML dashboard + CSV exports
- 🔧 **Selective Remediation** - Fix by category, severity, or individual issue
- 💾 **Automatic Backups** - Configuration backups before every change
- 🔄 **Rollback Capability** - Restore previous configurations if needed
- 🎯 **Dry Run Mode** - Test fixes without making changes

---

## 📦 **What's Included**

### **1. Analyze-AzureEnvironment.ps1**
**Main detection script** - Scans your Azure environment and generates comprehensive reports

### **2. Execute-AzureFixes.ps1**
**Safe fix execution** - Applies remediation with confirmations and backups

### **3. Auto-generated Fix Scripts**
Each analysis run creates a custom fix script tailored to your issues

---

## 🚀 **Quick Start Guide**

### **Prerequisites**

```powershell
# Install Azure PowerShell (if not already installed)
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Connect to Azure
Connect-AzAccount

# Verify connection
Get-AzContext
```

---

### **Step 1: Run Analysis (Detection Only)**

```powershell
# Analyze your environment
.\Analyze-AzureEnvironment.ps1
```

**What happens:**
- ✅ Scans your entire Azure subscription
- ✅ Detects issues across all categories
- ✅ Generates HTML report (opens automatically)
- ✅ Creates CSV export with all details
- ✅ Generates custom fix scripts
- ❌ **DOES NOT make any changes**

**Time:** 2-5 minutes (depending on environment size)

---

### **Step 2: Review Reports**

The script automatically opens an HTML report showing:
- Total issues by severity (Critical, High, Medium, Low)
- Breakdown by category (RBAC, Network, Security, etc.)
- Detailed issue descriptions
- Remediation recommendations

**Reports Location:** `.\Azure-Analysis-Reports\`

```
Azure-Analysis-Reports/
├── Azure_Analysis_20251008_143022.html    ← Interactive dashboard
├── Issues_Detailed_20251008_143022.csv    ← Full details
└── Fix_Scripts_20251008_143022.ps1        ← Custom fixes
```

---

### **Step 3: Fix Issues (Your Choice)**

#### **Option A: Dry Run First (Recommended)**

```powershell
# Simulate fixes without making changes
.\Execute-AzureFixes.ps1 -DryRun
```

#### **Option B: Fix Specific Categories**

```powershell
# Fix only critical RBAC issues (with confirmation)
.\Execute-AzureFixes.ps1 -Categories RBAC -Severity Critical

# Fix critical and high network issues
.\Execute-AzureFixes.ps1 -Categories Network -Severity High

# Fix multiple categories
.\Execute-AzureFixes.ps1 -Categories RBAC,Network,Security -Severity High
```

#### **Option C: Fix All Issues**

```powershell
# Fix everything (with confirmation for each)
.\Execute-AzureFixes.ps1 -Categories All -Severity Low

# Fix everything automatically (USE WITH CAUTION!)
.\Execute-AzureFixes.ps1 -Categories All -AutoApprove
```

---

## 📊 **Understanding the Reports**

### **HTML Dashboard**

**Summary Cards:**
- Total issues count
- Breakdown by severity with color coding
- Quick visual assessment

**Issues Table:**
- Timestamp of detection
- Category (RBAC, Network, Security, etc.)
- Severity badge (Critical → Low)
- Affected resource name
- Detailed description
- Recommended action

### **CSV Export**

Perfect for:
- Filtering and sorting in Excel
- Sharing with team members
- Creating pivot tables
- Tracking remediation progress

---

## 🔧 **Fix Categories Explained**

### **RBAC (Role-Based Access Control)**

**Detects:**
- Users with Owner permissions (should use Contributor)
- Stale role assignments (deleted users still assigned)
- Custom roles with wildcard permissions
- Service principals with excessive permissions

**Example Fixes:**
- Downgrade Owner → Contributor
- Remove orphaned assignments
- Refine custom role permissions

---

### **Network**

**Detects:**
- NSG rules allowing `0.0.0.0/0` (entire internet)
- Open SSH (22) or RDP (3389) ports to internet
- Subnets without NSGs attached
- Missing default deny rules

**Example Fixes:**
- Restrict source IPs to specific ranges
- Attach NSGs to unprotected subnets
- Add default deny rules

---

### **Security**

**Detects:**
- Storage accounts allowing HTTP (not HTTPS only)
- Public blob access enabled
- VMs without disk encryption
- Key Vaults without soft delete
- VMs with public IPs

**Example Fixes:**
- Enable HTTPS-only traffic
- Disable public blob access
- Enable disk encryption
- Enable soft delete on Key Vaults

---

### **Users**

**Detects:**
- Guest users with elevated permissions
- Users without MFA (requires Azure AD Premium)
- Inactive accounts with access

**Example Fixes:**
- Remove excessive guest permissions
- Enforce MFA requirements

---

### **Governance**

**Detects:**
- Resources without tags
- Resources in non-standard regions
- Naming convention violations

**Example Fixes:**
- Apply standard tags
- Document regional resources

---

## 🛡️ **Safety Features**

### **1. Detection First**
- Analysis **NEVER** makes changes automatically
- You review everything before fixing

### **2. Confirmation Required**
- Each fix requires manual approval (unless `-AutoApprove`)
- Option to skip all remaining fixes

### **3. Automatic Backups**
- Configuration backed up before every change
- Stored in `.\Azure-Fix-Backups\`
- Can be used for rollback

### **4. Dry Run Mode**
- Test fixes without making changes
- See what would happen
- Verify your approach

### **5. Selective Fixing**
- Fix by category (RBAC only, Network only, etc.)
- Fix by severity (Critical only, High and above, etc.)
- Skip individual issues

---

## 📋 **Common Usage Patterns**

### **Pattern 1: First-Time Assessment**

```powershell
# 1. Analyze environment
.\Analyze-AzureEnvironment.ps1

# 2. Review HTML report (opens automatically)

# 3. Test fixes (dry run)
.\Execute-AzureFixes.ps1 -DryRun

# 4. Fix critical issues only
.\Execute-AzureFixes.ps1 -Severity Critical

# 5. Re-analyze to verify
.\Analyze-AzureEnvironment.ps1
```

---

### **Pattern 2: Weekly Security Audit**

```powershell
# Monday: Full analysis
.\Analyze-AzureEnvironment.ps1 -ReportPath "C:\Reports\Weekly"

# Tuesday: Fix critical/high security issues
.\Execute-AzureFixes.ps1 -Categories Security -Severity High

# Wednesday: Fix network issues
.\Execute-AzureFixes.ps1 -Categories Network -Severity Medium

# Friday: Verify all fixes
.\Analyze-AzureEnvironment.ps1
```

---

### **Pattern 3: Compliance Preparation**

```powershell
# Full audit before compliance review
.\Analyze-AzureEnvironment.ps1

# Fix all critical and high issues
.\Execute-AzureFixes.ps1 -Categories All -Severity High -AutoApprove

# Generate final report for auditors
.\Analyze-AzureEnvironment.ps1 -ReportPath "C:\ComplianceReports"
```

---

## 🔄 **Rollback Procedures**

If a fix causes issues:

```powershell
# 1. Navigate to backups
cd .\Azure-Fix-Backups

# 2. List available backups
dir | Sort-Object LastWriteTime -Descending

# 3. Review backup file
Get-Content "Backup_RBAC_20251008_143533.json" | ConvertFrom-Json

# 4. Restore configuration manually or use backup data
# Example: Restore role assignment from backup
$backup = Get-Content "Backup_RBAC_*.json" | ConvertFrom-Json
New-AzRoleAssignment -ObjectId $backup.ObjectId -RoleDefinitionName $backup.RoleDefinitionName -Scope $backup.Scope
```

---

## 📈 **Best Practices**

### **✅ DO:**
- Run analysis regularly (weekly recommended)
- Always review reports before fixing
- Test fixes in non-production first
- Use dry run mode for new fix categories
- Keep backup files for 30 days
- Document custom fixes in your team wiki

### **❌ DON'T:**
- Run with `-AutoApprove` in production without review
- Delete backup files immediately
- Fix everything at once in production
- Ignore medium/low severity issues indefinitely
- Skip the dry run on first use

---

## 🔍 **Advanced Usage**

### **Analyze Specific Subscription**

```powershell
.\Analyze-AzureEnvironment.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"
```

### **Custom Report Location**

```powershell
.\Analyze-AzureEnvironment.ps1 -ReportPath "C:\Azure\Reports\Production"
```

### **Automated Remediation (CI/CD)**

```powershell
# In your pipeline (use with caution!)
.\Analyze-AzureEnvironment.ps1
.\Execute-AzureFixes.ps1 -Categories Network -Severity Critical -AutoApprove
.\Analyze-AzureEnvironment.ps1  # Verify fixes
```

---

## 📞 **Troubleshooting**

### **"Module Az not found"**
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
```

### **"Insufficient permissions"**
You need at least **Reader** role to analyze, and **Contributor** role to fix issues.

### **"No issues detected but I know there are problems"**
Some checks require specific Azure AD permissions. Run as a Global Administrator or ensure proper RBAC assignments.

### **"Fix failed with error"**
1. Check the error message
2. Review backup files
3. Verify permissions
4. Try fixing individually instead of batch

---

## 📊 **Issue Severity Guide**

| Severity | Priority | Action Timeframe | Examples |
|----------|----------|------------------|----------|
| **Critical** | P0 | Fix immediately | Open RDP/SSH to internet, wildcard permissions |
| **High** | P1 | Fix within 24-48 hours | No disk encryption, public blob access |
| **Medium** | P2 | Fix within 1 week | Missing NSGs, stale RBAC assignments |
| **Low** | P3 | Fix within 1 month | Missing tags, non-standard regions |

---

## 🎯 **Real-World Example**

### **Scenario:** Found 47 issues in production

```powershell
# Day 1: Analysis
.\Analyze-AzureEnvironment.ps1
# Result: 3 Critical, 12 High, 18 Medium, 14 Low

# Day 1 (continued): Fix critical issues immediately
.\Execute-AzureFixes.ps1 -Severity Critical
# Fixed: 3 NSG rules allowing internet RDP access

# Day 2: Fix high severity security issues
.\Execute-AzureFixes.ps1 -Categories Security -Severity High
# Fixed: 8 storage accounts to HTTPS-only, 4 missing disk encryption

# Day 3: Fix high severity RBAC issues
.\Execute-AzureFixes.ps1 -Categories RBAC -Severity High
# Fixed: 4 users downgraded from Owner to Contributor

# Day 5: Fix medium issues
.\Execute-AzureFixes.ps1 -Severity Medium
# Fixed: 15 orphaned RBAC assignments, 3 NSG attachments

# Day 5 (end of week): Re-analyze
.\Analyze-AzureEnvironment.ps1
# Result: 0 Critical, 0 High, 0 Medium, 14 Low (governance tags)

# Week 2: Address governance issues
.\Execute-AzureFixes.ps1 -Categories Governance
# Fixed: Applied standard tags to all resources
```

**Final Result:** Production environment secured in 1 week! ✅

---

## 📝 **Version History**

### **v2.0** (Current)
- Comprehensive detection across all Azure services
- Safe fix execution with backups
- HTML + CSV reporting
- Dry run mode
- Selective remediation
- Rollback capability

---

## 🤝 **Contributing**

Found a bug or have a feature request?
1. Review the generated reports
2. Check backup files
3. Document the issue
4. Submit feedback to your Azure admin team

---

## ⚖️ **License**

Internal use - Company proprietary

---

## 🎓 **Learn More**

- [Azure Security Best Practices](https://docs.microsoft.com/azure/security/fundamentals/best-practices-and-patterns)
- [Azure RBAC Documentation](https://docs.microsoft.com/azure/role-based-access-control/overview)
- [Azure Network Security](https://docs.microsoft.com/azure/security/fundamentals/network-best-practices)

---

**Questions? Run the analysis and review the reports - they include detailed recommendations for every issue!** 🚀