# Complete Front Door Deployment Guide

## Overview

This is PURE Terraform code that deploys Azure Front Door with backends. No PowerShell required - just Terraform!

### What This Deploys (ONLY THESE)

✅ **Front Door Profile** - Entry point  
✅ **Front Door Endpoint** - Public URL  
✅ **Origin Group** - Backend pool  
✅ **Origin** - Backend server  
✅ **Route** - Traffic routing  
✅ **WAF Policy** - Security rules  
✅ **Security Policy** - WAF enforcement  
✅ **Log Analytics** - Monitoring  
✅ **Diagnostic Settings** - Logs  
✅ **Metric Alerts** - 3 alerts  

❌ **NO AKS**  
❌ **NO VMs**  
❌ **NO Storage**  
❌ **NO App Services**  

## File Structure

```
Pyx-AVD-deployment/
└── DriversHealth-FrontDoor/
    ├── main.tf                    # Front Door resources (325 lines)
    ├── variables.tf               # Configuration (195 lines)
    ├── outputs.tf                 # Deployment results (150 lines)
    ├── terraform.tfvars.example   # Example config (80 lines)
    ├── terraform.tfvars           # Your config (YOU CREATE THIS)
    ├── .gitignore                 # Git ignore rules
    ├── README.md                  # Full documentation
    └── QUICKSTART.md              # 5-minute guide
```

## Prerequisites

1. **Azure CLI**
   ```bash
   # Install
   # Windows: https://aka.ms/installazurecliwindows
   # macOS: brew install azure-cli
   # Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Login
   az login
   ```

2. **Terraform**
   ```bash
   # Install
   # Windows: choco install terraform
   # macOS: brew install terraform
   # Linux: wget https://releases.hashicorp.com/terraform/1.6.5/terraform_1.6.5_linux_amd64.zip
   
   # Verify
   terraform version
   ```

3. **Backend Host Name** - Your application server
   - Example: `drivershealth.azurewebsites.net`

## Deployment Steps

### 1. Select Azure Subscription

```bash
# List all subscriptions
az account list --output table

# Select subscription
az account set --subscription "DriversHealth-Production"

# Verify
az account show
```

### 2. Create Configuration File

```bash
# Copy example
cp terraform.tfvars.example terraform.tfvars

# Edit with your settings
nano terraform.tfvars
```

**Minimum Required Configuration:**

```hcl
# terraform.tfvars
backend_host_name = "drivershealth.azurewebsites.net"
```

**Full Configuration Options:**

```hcl
# Required
backend_host_name = "drivershealth.azurewebsites.net"

# Optional - Project Settings
project_name = "DriversHealth"
environment  = "prod"
location     = "East US"

# Optional - Security Settings
enable_https_only = true
enable_waf        = true
waf_mode          = "Prevention"

# Optional - Monitoring
enable_custom_rules = false

# Optional - Custom Names (uses DH convention by default)
# resource_group_name = "rg-drivershealth-prod"
# frontdoor_name     = "fdh-prod"
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy
terraform apply
```

Type `yes` when prompted.

### 4. Get Results

After 3-5 minutes, Terraform outputs:

```
Outputs:

frontdoor_url = "https://afd-drivershealth-prod-xxxxx.azurefd.net"

deployment_summary = <<EOT
========================================
Front Door Deployment Complete!
========================================

Front Door URL: https://afd-drivershealth-prod-xxxxx.azurefd.net
Resource Group: rg-drivershealth-prod

Resources Created:
- Front Door Profile: fdh-prod
- Endpoint: afd-drivershealth-prod
- Origin Group: dh-origin-group
- Origin: dh-origin
- WAF Policy: drivershealthprodwafpolicy
- Security Policy: dh-security-policy
- Log Analytics: law-fdh-prod
- Monitoring Alerts: 3 configured

Security Features:
- HTTPS Redirect: Enabled
- WAF Mode: Prevention
- Microsoft Default Rule Set: 2.1
- Bot Manager Rule Set: 1.0
- Rate Limiting: 100 requests/minute
- SQL Injection Protection: Enabled
- XSS Protection: Enabled

Next Steps:
1. Test Front Door URL
2. Configure DNS
3. Monitor in Azure Portal
========================================
EOT
```

## Subscription Detection

The code automatically detects all available subscriptions:

```bash
# View detected subscriptions
terraform plan

# Output shows:
# subscription_info = {
#   "subscription_id" = "xxx-xxx-xxx"
#   "subscription_name" = "DriversHealth-Production"
# }
#
# available_subscriptions = {
#   "xxx-xxx-xxx" = "DriversHealth-Production"
#   "yyy-yyy-yyy" = "DriversHealth-Development"
#   "zzz-zzz-zzz" = "PyxHealth-Production"
# }
```

To deploy to different subscription:

```bash
az account set --subscription "PyxHealth-Production"
terraform apply
```

## Naming Convention

Uses Drivers Health (DH) naming convention automatically:

| Resource | Naming Convention | Example |
|----------|-------------------|---------|
| Resource Group | `rg-{project}-{env}` | `rg-drivershealth-prod` |
| Front Door | `fdh-{env}` | `fdh-prod` |
| Endpoint | `afd-{project}-{env}` | `afd-drivershealth-prod` |
| Origin Group | `dh-origin-group` | `dh-origin-group` |
| Origin | `dh-origin` | `dh-origin` |
| Route | `dh-route` | `dh-route` |
| WAF Policy | `{project}{env}wafpolicy` | `drivershealthprodwafpolicy` |
| Security Policy | `dh-security-policy` | `dh-security-policy` |
| Log Analytics | `law-fdh-{env}` | `law-fdh-prod` |
| Rule Set | `dh-rules` | `dh-rules` |

### Change Project Name

For Pyx Health:

```hcl
# terraform.tfvars
project_name = "PyxHealth"
backend_host_name = "pyxhealth.azurewebsites.net"
```

Results in:
- Resource Group: `rg-pyxhealth-prod`
- Front Door: `fdh-prod`
- Endpoint: `afd-pyxhealth-prod`
- WAF Policy: `pyxhealthprodwafpolicy`

## Security Features

### WAF Policy

Automatically configured with:

1. **Microsoft Default Rule Set 2.1**
   - OWASP ModSecurity Core Rule Set
   - Protection against OWASP Top 10
   - 50+ security rules

2. **Bot Manager Rule Set 1.0**
   - Good bot detection
   - Bad bot blocking
   - Unknown bot detection

3. **Rate Limiting**
   - 100 requests per minute
   - Per-client IP
   - Automatic blocking

4. **SQL Injection Protection**
   - Blocks: `union`, `select`, `insert`, `drop`, `delete`, `exec`, `script`
   - Case-insensitive matching
   - Query string inspection

5. **XSS Protection**
   - Blocks: `<script`, `javascript:`, `onerror=`, `onload=`
   - Case-insensitive matching
   - Query string inspection

### HTTPS Configuration

- **HTTP to HTTPS Redirect**: Automatic
- **Certificate Validation**: Enforced
- **Forwarding Protocol**: HTTPS Only
- **Supported Protocols**: HTTP and HTTPS

### Monitoring

1. **Log Analytics Workspace**
   - 90-day retention
   - All Front Door logs
   - All WAF logs

2. **Diagnostic Settings**
   - FrontDoorAccessLog
   - FrontDoorHealthProbeLog
   - FrontDoorWebApplicationFirewallLog
   - AllMetrics

3. **Metric Alerts**
   - Backend health below 50%
   - WAF blocks over 100 requests
   - Response time over 1000ms

## Multiple Environment Deployments

### Test Environment

```bash
# terraform.tfvars
environment = "dev"
backend_host_name = "drivershealth-dev.azurewebsites.net"

terraform apply
```

Creates:
- Resource Group: `rg-drivershealth-dev`
- Front Door: `fdh-dev`
- Endpoint: `afd-drivershealth-dev`

### Production Environment

```bash
# terraform.tfvars
environment = "prod"
backend_host_name = "drivershealth.azurewebsites.net"

terraform apply
```

Creates:
- Resource Group: `rg-drivershealth-prod`
- Front Door: `fdh-prod`
- Endpoint: `afd-drivershealth-prod`

### Same Subscription, Different Environments

Both can exist in the same subscription! Terraform manages them separately.

## Verification

### Test Front Door

```bash
# Get URL
terraform output frontdoor_url

# Test with curl
curl -I https://afd-drivershealth-prod-xxxxx.azurefd.net

# Should return:
# HTTP/2 200
# x-azure-ref: ...
# x-cache: TCP_HIT
```

### Check Azure Portal

1. Go to Azure Portal
2. Search for "Front Door"
3. Click `fdh-prod`
4. Check:
   - **Endpoints**: Public URL active
   - **Origins**: Backend healthy
   - **Security**: WAF enabled
   - **Monitoring**: Metrics flowing

### Check Logs

```bash
# In Azure Portal
1. Go to Log Analytics workspace: law-fdh-prod
2. Click "Logs"
3. Run query:

AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| order by TimeGenerated desc
| take 100
```

## Troubleshooting

### Backend Unhealthy

**Symptoms**: Origin shows "Unhealthy" in Portal

**Solutions**:
1. Verify backend is running
2. Check health probe path returns 200 OK
3. Verify HTTPS certificate is valid
4. Check backend allows Front Door IP ranges
5. Review health probe logs

```bash
# Check health probe logs
# In Azure Portal > Log Analytics > Logs:
AzureDiagnostics
| where Category == "FrontDoorHealthProbeLog"
| order by TimeGenerated desc
```

### Front Door Not Accessible

**Symptoms**: Cannot reach Front Door URL

**Solutions**:
1. Wait 5-10 minutes for propagation
2. Check all resources created successfully
3. Verify endpoint is enabled
4. Check route is configured
5. Review access logs

```bash
# Verify all resources
terraform show

# Check specific resource
terraform state show azurerm_cdn_frontdoor_endpoint.main
```

### WAF Blocking Traffic

**Symptoms**: Legitimate requests getting 403

**Solutions**:
1. Check WAF logs for blocked requests
2. Identify which rule is blocking
3. Either:
   - Fix request to comply
   - Create exception rule
   - Set WAF to Detection mode temporarily

```hcl
# terraform.tfvars
waf_mode = "Detection"  # Logs but doesn't block
```

### Terraform Errors

**Symptoms**: `terraform apply` fails

**Solutions**:

```bash
# Refresh state
terraform refresh

# Validate configuration
terraform validate

# Reinitialize
rm -rf .terraform .terraform.lock.hcl
terraform init

# Check Azure provider
az account show

# Verbose logging
export TF_LOG=DEBUG
terraform apply
```

## Git Sync

### Clean Up Old Code

Run the Git sync script to safely remove old Front Door code:

```bash
# Windows
.\git-sync-frontdoor.ps1

# Linux/macOS
chmod +x cleanup-and-sync-frontdoor.sh
./cleanup-and-sync-frontdoor.sh
```

This will:
1. Backup old Front Door code
2. Remove old Front Door files
3. Stage new code
4. Commit changes
5. Optionally push to remote

### Manual Git Operations

```bash
# Add new files
git add Pyx-AVD-deployment/DriversHealth-FrontDoor/

# Commit
git commit -m "Add Front Door Terraform deployment"

# Push
git push
```

## Cost Estimate

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| Front Door Premium | $330 |
| Log Analytics | $10-30 |
| Data Transfer | Variable |
| **Total** | **~$340-400** |

### Cost Optimization

1. **Use Standard SKU** (if Premium features not needed)
   - Cost: ~$35/month (90% savings)
   - Lose: WAF, private link, advanced routing

2. **Reduce Log Retention**
   ```hcl
   # variables.tf
   retention_in_days = 30  # Default is 90
   ```

3. **Disable Custom Rules** (if not needed)
   ```hcl
   # terraform.tfvars
   enable_custom_rules = false
   ```

## Updates

### Change Backend

```hcl
# terraform.tfvars
backend_host_name = "newbackend.azurewebsites.net"
```

```bash
terraform apply
```

### Change WAF Mode

```hcl
# terraform.tfvars
waf_mode = "Detection"  # or "Prevention"
```

```bash
terraform apply
```

### Add Custom Tags

```hcl
# terraform.tfvars
tags = {
  CostCenter = "IT"
  Owner      = "Infrastructure Team"
  Compliance = "HIPAA"
}
```

```bash
terraform apply
```

## Destroy

To remove all resources:

```bash
terraform destroy
```

Type `yes` to confirm.

**WARNING**: This deletes EVERYTHING! Backup configuration first.

## Support

For issues:
1. Check Azure Portal resource status
2. Review Terraform output
3. Check Log Analytics logs
4. Review this guide

## Quick Reference

```bash
# Login
az login

# Select subscription
az account set --subscription "name"

# Initialize
terraform init

# Preview
terraform plan

# Deploy
terraform apply

# Show outputs
terraform output

# Destroy
terraform destroy
```

## Success Checklist

✅ Azure CLI installed and logged in  
✅ Terraform installed  
✅ Subscription selected  
✅ terraform.tfvars created with backend_host_name  
✅ terraform init completed  
✅ terraform apply successful  
✅ Front Door URL accessible  
✅ Backend health check passing  
✅ WAF enabled and blocking test attacks  
✅ Logs flowing to Log Analytics  
✅ Code committed to Git  

---

**You now have a production-ready Azure Front Door deployment!**
