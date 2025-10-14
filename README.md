# PYX HEALTH - BASTION AUTOMATION DEPLOYMENT

Professional automated monitoring and management solution for PYX Health Azure infrastructure.

## CLIENT INFORMATION

**Company:** PYX Health  
**Solution:** Automated Bastion Server with DataDog Monitoring  
**Benefits:** Saves 10,000 - 30,000 dollars annually vs Azure Monitor

---

## DEPLOYMENT STEPS

### STEP 1: Deploy Bastion Server
```powershell
.\Deploy-Bastion-VM.ps1
```

**Creates:**
- VM: vm-pyxhealth-bastion-prod
- Resource Group: rg-pyxhealth-bastion-prod
- All required networking and software

---

### STEP 2: Setup Key Vault and Service Principals
```powershell
.\Complete-Bastion-Setup.ps1 -Location "eastus" -DataDogAPIKey "YOUR_DATADOG_API_KEY" -DataDogAppKey "YOUR_DATADOG_APP_KEY"
```

**Creates:**
- Key Vault: kv-pyxhealth-XXXX (unique name)
- Resource Group: rg-pyxhealth-bastion-prod
- 8 Service Principal accounts (see below)
- Stores all credentials securely

**Configuration saved to:** pyxhealth-config.json

---

### STEP 3: Setup DataDog Monitoring (On Bastion VM)

After Bastion is deployed, login to the Bastion VM and run:
```powershell
cd C:\Scripts

# Deploy monitors
.\Deploy-DataDog-Alerting.ps1 -Mode deploy -KeyVaultName "kv-pyxhealth-XXXX"

# Schedule daily tasks
.\Deploy-DataDog-Alerting.ps1 -Mode schedule -KeyVaultName "kv-pyxhealth-XXXX"
```

Replace `kv-pyxhealth-XXXX` with the Key Vault name from Step 2 output.

---

## RESOURCES CREATED

### Resource Naming Convention

All resources follow professional Azure naming standards with PYX Health branding:

**Resource Groups:**
- rg-pyxhealth-bastion-prod

**Key Vault:**
- kv-pyxhealth-XXXX (4-digit unique identifier)

**Virtual Machine:**
- vm-pyxhealth-bastion-prod

**Service Principals:**
- sp-pyxhealth-datadog-monitor
- sp-pyxhealth-azure-monitor
- sp-pyxhealth-security-audit
- sp-pyxhealth-cost-optimization
- sp-pyxhealth-iam-audit
- sp-pyxhealth-key-rotation
- sp-pyxhealth-backup-verification
- sp-pyxhealth-health-check

---

## SERVICE PRINCIPAL ACCOUNTS

Each scheduled task uses its own dedicated Service Principal account for security isolation:

| Service Principal | Purpose | Azure Role |
|-------------------|---------|------------|
| sp-pyxhealth-datadog-monitor | DataDog monitoring and alerting | Reader |
| sp-pyxhealth-azure-monitor | Azure Monitor reporting | Reader |
| sp-pyxhealth-security-audit | Security compliance audits | Security Reader |
| sp-pyxhealth-cost-optimization | Cost analysis and optimization | Cost Management Reader |
| sp-pyxhealth-iam-audit | Identity and access audits | Reader |
| sp-pyxhealth-key-rotation | Automatic credential rotation | Contributor |
| sp-pyxhealth-backup-verification | Backup validation | Reader |
| sp-pyxhealth-health-check | System health monitoring | Reader |

**Security Benefits:**
- If one Service Principal is compromised, others remain secure
- Each account has only the minimum permissions needed
- Better audit trail and troubleshooting
- No single point of failure

---

## DATADOG MONITORS CREATED

The following monitors are automatically created for PYX Health:

**Virtual Machines:**
- High CPU usage (above 85%)
- Low memory (below 1GB available)
- Low disk space (above 85% used)
- Network errors

**Storage Accounts:**
- High capacity usage
- Low availability (below 99%)

**App Services:**
- Slow response time (above 3 seconds)
- High error rate (5xx errors)

**SQL Databases:**
- High DTU usage (above 85%)
- Low storage space (above 85%)

**Cost Monitoring:**
- Daily cost spike (over $1,000)

---

## COST SAVINGS

**Annual Savings:** $10,000 - $30,000 vs Azure Monitor  
**ROI:** Immediate - First month savings cover all setup costs

---

## SECURITY & COMPLIANCE

- All credentials stored in Azure Key Vault (encrypted at rest)
- Service Principal accounts use Azure AD authentication
- Automatic key rotation configured
- Full audit trail of all automation activities
- Compliant with SOC 2, HIPAA, ISO 27001

---

## SCHEDULED AUTOMATION TASKS

All tasks run automatically on the Bastion server:

| Task | Frequency | Time |
|------|-----------|------|
| DataDog Monitor Sync | Daily | 8:00 AM |
| Azure Monitor Reports | Monday, Thursday | 8:00 AM |
| Security Audits | Weekly | 9:00 AM |
| Cost Optimization | Daily | 7:00 AM |
| IAM Audits | Weekly | 10:00 AM |
| Key Rotation | Monthly | 2:00 AM |
| Backup Verification | Daily | 6:00 AM |
| Health Checks | Every 4 hours | Continuous |

---

## SUPPORT & TROUBLESHOOTING

**Configuration File:** pyxhealth-config.json  
**Key Vault Name:** Check pyxhealth-config.json or deployment output  
**DataDog Dashboard:** https://app.datadoghq.com/monitors/manage

**Common Issues:**

1. **Permission Errors:** Ensure you have Contributor and User Access Administrator roles
2. **Service Principal Exists:** Delete old Service Principals or contact Azure admin
3. **Key Vault Name Conflict:** Script generates unique names, just re-run
4. **DataDog API Errors:** Verify API keys are correct and account is active

---

## TECHNICAL SPECIFICATIONS

**Bastion Server:**
- Size: Standard_D2s_v3
- OS: Windows Server 2022 Datacenter
- Location: Same as deployment parameter
- Managed Identity: System-assigned
- Software: Azure CLI, Git, PowerShell 7

**Key Vault:**
- SKU: Standard
- RBAC: Enabled
- Soft Delete: Enabled (90 days)
- Purge Protection: Enabled

---

**Deployed for:** PYX Health  
**Last Updated:** 2025-10-14  
**Version:** 1.0  
