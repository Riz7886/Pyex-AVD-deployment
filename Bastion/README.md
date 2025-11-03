# Azure DoD and FedRAMP Compliance Audit Script

## Overview

This PowerShell script provides a comprehensive, automated security audit for Azure environments aligned with DoD (Department of Defense) and FedRAMP (Federal Risk and Authorization Management Program) compliance requirements. The script implements NIST 800-53 Rev 5 control validation and generates professional audit reports suitable for compliance assessments.

## Features

### Security Audit Capabilities

1. **RBAC Analysis**
   - Complete role assignment enumeration
   - Privileged access identification
   - Risk-based role assessment
   - Group membership expansion
   - Scope and permission analysis

2. **Unauthorized Access Detection**
   - Failed login attempt tracking
   - Suspicious activity pattern detection
   - Privileged operation monitoring
   - IP address tracking
   - Temporal analysis over configurable periods

3. **Network Security Assessment**
   - Network Security Group (NSG) rule analysis
   - Risky inbound rule detection
   - Sensitive port exposure identification
   - Internet-facing resource detection
   - Security rule priority analysis

4. **Storage Security Compliance**
   - HTTPS enforcement validation
   - Public access configuration review
   - Encryption at rest verification
   - Network access control assessment
   - Secure transfer requirement validation

5. **Virtual Machine Security**
   - Managed disk usage verification
   - Anti-malware extension validation
   - Monitoring agent deployment checks
   - Security baseline compliance
   - Patch management assessment

6. **Key Vault Security**
   - Soft delete configuration
   - Purge protection validation
   - Network access control review
   - Access policy analysis
   - Secret management compliance

7. **Azure Security Center Integration**
   - Security assessment findings
   - Vulnerability identification
   - Compliance posture evaluation
   - Remediation recommendations

## NIST 800-53 Control Coverage

The script validates compliance with the following NIST 800-53 Rev 5 control families:

### Access Control (AC)
- **AC-2**: Account Management - Audits all user accounts and role assignments
- **AC-3**: Access Enforcement - Validates RBAC policies and enforcement
- **AC-6**: Least Privilege - Identifies excessive permissions

### Audit and Accountability (AU)
- **AU-2**: Audit Events - Validates logging configuration
- **AU-6**: Audit Review, Analysis, and Reporting - Provides comprehensive audit reports
- **AU-12**: Audit Generation - Verifies audit log collection

### System and Communications Protection (SC)
- **SC-8**: Transmission Confidentiality and Integrity - Validates HTTPS enforcement
- **SC-12**: Cryptographic Key Establishment - Reviews Key Vault security
- **SC-13**: Cryptographic Protection - Validates encryption at rest and in transit
- **SC-28**: Protection of Information at Rest - Checks storage encryption

### System and Information Integrity (SI)
- **SI-2**: Flaw Remediation - Checks patch management
- **SI-3**: Malicious Code Protection - Validates anti-malware deployment
- **SI-4**: Information System Monitoring - Reviews monitoring agent deployment

## Prerequisites

### Required Permissions

- **Reader** role on all Azure subscriptions to be audited
- **Security Reader** role for Azure Security Center access (recommended)
- Azure AD read permissions for user and group enumeration

### Required PowerShell Modules

```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser
```

The script requires the following Az modules:
- Az.Accounts
- Az.Resources
- Az.Security
- Az.Monitor
- Az.Storage
- Az.Network
- Az.Compute
- Az.KeyVault

## Installation

1. Download the script:
```powershell
# Save the script to your local system
Save-Item -Path "Azure-DoD-FedRAMP-Audit.ps1" -Destination "C:\AzureAudit\"
```

2. Verify script integrity:
```powershell
# Check script signature if provided
Get-AuthenticodeSignature -FilePath "Azure-DoD-FedRAMP-Audit.ps1"
```

3. Install required modules:
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
```

## Usage

### Basic Usage - Audit Current Subscription

```powershell
.\Azure-DoD-FedRAMP-Audit.ps1
```

### Audit All Accessible Subscriptions

```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -AllSubscriptions
```

### Audit Specific Subscriptions

```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -SubscriptionIds "sub-id-1", "sub-id-2"
```

### Custom Output Location

```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -OutputPath "C:\AuditReports" -AllSubscriptions
```

### Extended Activity Log Analysis

```powershell
.\Azure-DoD-FedRAMP-Audit.ps1 -ActivityLogDays 180 -AllSubscriptions
```

### Complete Example

```powershell
# Authenticate to Azure
Connect-AzAccount

# Run comprehensive audit
.\Azure-DoD-FedRAMP-Audit.ps1 `
    -AllSubscriptions `
    -OutputPath "C:\ComplianceAudits\$(Get-Date -Format 'yyyy-MM')" `
    -ActivityLogDays 90 `
    -Verbose
```

## Output Files

The script generates the following outputs in timestamped directories:

### HTML Report
- **DoD_FedRAMP_Audit_Report.html** - Professional, interactive audit report with:
  - Executive summary dashboard
  - NIST 800-53 control status
  - Critical findings requiring immediate attention
  - Detailed security analysis by category
  - Compliance recommendations
  - Visual risk indicators

### CSV Data Exports
- **RBAC_Assignments.csv** - Complete RBAC role assignment data
- **Suspicious_Activities.csv** - Detected suspicious activities and failed logins
- **Security_Findings.csv** - Azure Security Center findings
- **Network_Security_Issues.csv** - Network security misconfigurations
- **Storage_Security_Issues.csv** - Storage account security issues
- **VM_Security_Issues.csv** - Virtual machine security findings
- **KeyVault_Security_Issues.csv** - Key Vault security concerns

### Execution Log
- **audit_execution.log** - Detailed execution log with timestamps

## Report Sections

### 1. Executive Summary
- Overall risk assessment
- High-level statistics
- Compliance posture overview
- Priority findings

### 2. NIST 800-53 Control Status
- Control family compliance
- Individual control findings
- Remediation requirements
- Risk ratings

### 3. Critical Findings
- Immediate action items
- High-severity security issues
- Compliance violations
- Breach indicators

### 4. RBAC and Access Control
- All role assignments
- Privileged access analysis
- Excessive permission identification
- Orphaned accounts

### 5. Suspicious Activities
- Failed login attempts
- Unusual access patterns
- Privileged operations
- Geographic anomalies

### 6. Infrastructure Security
- Network security issues
- Storage misconfigurations
- VM security gaps
- Key Vault vulnerabilities

### 7. Recommendations
- Prioritized remediation steps
- Best practice guidance
- Compliance roadmap
- Continuous monitoring suggestions

## Compliance Mapping

### FedRAMP Requirements

| FedRAMP Control | Script Validation | Output Section |
|----------------|-------------------|----------------|
| AC-2 Account Management | RBAC assignment audit | RBAC Analysis |
| AC-6 Least Privilege | Privilege escalation check | RBAC Analysis |
| AU-2 Audit Events | Activity log analysis | Suspicious Activities |
| SC-8 Transmission Protection | HTTPS enforcement | Storage Security |
| SC-28 Protection at Rest | Encryption validation | Storage Security |
| SI-2 Flaw Remediation | Update status check | VM Security |
| SI-3 Malicious Code Protection | Anti-malware check | VM Security |

### DoD Security Requirements Guide (SRG)

The script addresses DoD SRG requirements including:
- Access control and authentication
- Audit and accountability
- Security assessment and authorization
- System and communications protection
- System and information integrity

## Best Practices

### Running the Audit

1. **Schedule Regular Audits**
   - Monthly for active environments
   - Quarterly for stable environments
   - Before and after major changes
   - Prior to compliance assessments

2. **Review Findings Promptly**
   - Address critical findings within 24 hours
   - High severity within 7 days
   - Medium severity within 30 days
   - Low severity within 90 days

3. **Document Remediation**
   - Create Plan of Action and Milestones (POAM)
   - Track remediation progress
   - Document risk acceptance decisions
   - Update security documentation

4. **Maintain Audit Trail**
   - Preserve all audit reports
   - Version control audit scripts
   - Document environmental changes
   - Track compliance trends

### Security Considerations

1. **Read-Only Operations**
   - Script performs NO modifications
   - Safe to run in production
   - No service disruption
   - No configuration changes

2. **Credential Security**
   - Use service principal with minimum permissions
   - Implement MFA for interactive authentication
   - Store credentials securely
   - Rotate access credentials regularly

3. **Data Handling**
   - Reports contain sensitive information
   - Encrypt report storage
   - Restrict access to audit results
   - Follow data retention policies

## Troubleshooting

### Common Issues

#### Module Not Found
```powershell
# Solution: Install required modules
Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
Import-Module Az
```

#### Access Denied
```powershell
# Solution: Verify permissions
Get-AzRoleAssignment -SignInName (Get-AzContext).Account.Id
# Should show Reader role on subscriptions
```

#### Activity Log Empty
```powershell
# Solution: Check diagnostic settings
# Activity logs may not be available if diagnostic settings are not configured
# Configure Azure Monitor to collect activity logs
```

#### Slow Performance
```powershell
# Solution: Reduce scope or increase timeout
.\Azure-DoD-FedRAMP-Audit.ps1 -SubscriptionIds "specific-sub" -ActivityLogDays 30
```

## Integration

### Automated Scheduling

#### Using Azure Automation

```powershell
# Create Azure Automation Runbook
# Upload script as runbook
# Schedule recurring execution
# Configure output to Log Analytics
```

#### Using Task Scheduler

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-File "C:\AuditScripts\Azure-DoD-FedRAMP-Audit.ps1" -AllSubscriptions'
$trigger = New-ScheduledTaskTrigger -Weekly -At 6am -DaysOfWeek Monday
Register-ScheduledTask -TaskName "Azure Security Audit" -Action $action -Trigger $trigger
```

### CI/CD Pipeline Integration

```yaml
# Azure DevOps Pipeline Example
steps:
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'ServiceConnection'
    ScriptType: 'FilePath'
    ScriptPath: '$(System.DefaultWorkingDirectory)/Azure-DoD-FedRAMP-Audit.ps1'
    ScriptArguments: '-AllSubscriptions -OutputPath $(Build.ArtifactStagingDirectory)'
    azurePowerShellVersion: 'LatestVersion'
```

## Support and Contribution

### Reporting Issues
- Document error messages
- Provide PowerShell version
- Include Azure module versions
- Describe expected vs actual behavior

### Enhancement Requests
- Describe desired functionality
- Explain compliance requirement
- Provide use case examples
- Reference relevant standards

## Disclaimer

This script is provided as-is for security audit and compliance assessment purposes. It performs read-only operations and does not modify any Azure resources. Users are responsible for:

- Validating script output
- Implementing recommended remediations
- Maintaining compliance
- Following organizational policies
- Securing audit reports

The script assists with but does not guarantee compliance with DoD or FedRAMP requirements. Professional security assessments should be conducted by qualified personnel.

## License

This script is provided for use in DoD and FedRAMP compliance auditing activities. Redistribution and modification are permitted for internal use. Attribution is appreciated but not required.

## Version History

### Version 1.0
- Initial release
- NIST 800-53 Rev 5 control validation
- RBAC comprehensive analysis
- Activity log suspicious event detection
- Network, storage, VM, and Key Vault security checks
- Professional HTML report generation
- CSV data export
- Multi-subscription support

## Contact

For questions, issues, or enhancement requests related to DoD and FedRAMP compliance auditing, please consult your organization's security team or compliance officer.

---

**CONFIDENTIAL - FOR OFFICIAL USE ONLY**

This audit script and its outputs contain sensitive security information and should be handled according to your organization's data classification and handling procedures.
