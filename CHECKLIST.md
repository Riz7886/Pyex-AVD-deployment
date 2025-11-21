# DRIVERS HEALTH - PRE-DEPLOYMENT CHECKLIST

Use this checklist before deploying Azure Front Door to ensure successful deployment.

## Prerequisites Check

- [ ] Azure CLI installed (version 2.50+)
- [ ] Terraform installed (version 1.5.0+)
- [ ] Azure subscription access confirmed
- [ ] Appropriate Azure permissions (Contributor or Owner)
- [ ] PowerShell 7+ (for Windows users)
- [ ] Bash shell (for Linux/macOS users)

## Verify Prerequisites

### Check Azure CLI
```bash
az --version
az login
az account list
```

### Check Terraform
```bash
terraform version
```

### Check Permissions
```bash
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

## Configuration Review

- [ ] Review `terraform.tfvars.example`
- [ ] Determine environment (prod, staging, dev)
- [ ] Confirm resource group name
- [ ] Confirm Front Door name (must be globally unique)
- [ ] Identify backend App Services
- [ ] Review WAF settings (Prevention vs Detection mode)
- [ ] Confirm Log Analytics retention period
- [ ] Review alert thresholds

## Subscription Selection

- [ ] List all available subscriptions
- [ ] Identify correct Drivers Health subscription
- [ ] Note subscription ID for reference
- [ ] Verify subscription has no policy restrictions
- [ ] Check subscription quotas for Front Door

### Check Quotas
```bash
az network front-door show-quota --subscription <sub-id>
```

## Backend Services

- [ ] Identify Drivers Health App Services
- [ ] Verify App Services are running
- [ ] Confirm App Service health endpoints
- [ ] Note App Service hostnames
- [ ] Test backend connectivity

### List App Services
```bash
az webapp list --query "[].{Name:name, HostName:defaultHostName}" -o table
```

## Naming Convention Verification

Confirm all names follow DH (Drivers Health) convention:

- [ ] Resource Group: `rg-drivershealth-{env}`
- [ ] Front Door: `fdh-{env}`
- [ ] Endpoint: `afd-drivershealth-{env}`
- [ ] Origin Group: `dh-origin-group`
- [ ] WAF Policy: `drivershealth{env}wafpolicy`

## Network and Security

- [ ] Review WAF managed rules
- [ ] Confirm rate limiting settings (100 req/min)
- [ ] Review SQL injection protection
- [ ] Verify HTTPS redirect enabled
- [ ] Check bot protection enabled
- [ ] Review custom WAF rules

## Monitoring and Alerts

- [ ] Verify Log Analytics workspace settings
- [ ] Confirm alert email addresses
- [ ] Review alert thresholds:
  - Latency: >1000ms
  - Error rate: >100 5xx errors
  - Origin health: <50% healthy
- [ ] Confirm alert frequencies (1 minute evaluation)

## Tags and Compliance

Review tags for all resources:
- [ ] Company: Pyx Health
- [ ] Service: Drivers Health
- [ ] Environment: {prod/staging/dev}
- [ ] CostCenter: Drivers-Health
- [ ] Compliance: HIPAA
- [ ] ManagedBy: Terraform

## Deployment Steps

### 1. Pre-Deployment Validation
```bash
# Clone or navigate to project
cd azure-frontdoor-terraform

# Review all configuration files
ls -la

# Check for terraform.tfvars
cat terraform.tfvars || echo "Need to run subscription selector"
```

### 2. Subscription Selection
```bash
# Linux/macOS
./select-subscription.sh

# Windows
.\select-subscription.ps1
```

### 3. Review Configuration
```bash
# Review the generated terraform.tfvars
cat terraform.tfvars

# Make any needed adjustments
nano terraform.tfvars  # or use your preferred editor
```

### 4. Initialize Terraform
```bash
terraform init
```

Expected output:
- Providers downloaded successfully
- Backend initialized
- No errors

### 5. Validate Configuration
```bash
terraform validate
```

Expected output:
- Success! The configuration is valid.

### 6. Plan Deployment
```bash
terraform plan -out=tfplan
```

Review the plan for:
- [ ] Correct number of resources (15-20)
- [ ] Correct subscription
- [ ] Correct resource group
- [ ] Correct Front Door name
- [ ] Correct origin configuration
- [ ] WAF policy included
- [ ] Monitoring resources included

### 7. Execute Deployment
```bash
terraform apply tfplan
```

## Post-Deployment Verification

After deployment completes:

### 1. Verify Resources Created
```bash
terraform output
```

Check outputs for:
- [ ] Front Door endpoint URL
- [ ] WAF policy name
- [ ] Log Analytics workspace
- [ ] Origin group details

### 2. Test Front Door Endpoint
```bash
ENDPOINT=$(terraform output -raw endpoint_url)
curl -I $ENDPOINT
```

Expected: HTTP 301 or 200 response

### 3. Verify WAF Protection
```bash
# Test rate limiting (should block after 100 requests)
for i in {1..105}; do curl -s -o /dev/null -w "%{http_code}\n" $ENDPOINT; done
```

Expected: Some 403 responses after threshold

### 4. Check Origin Health
```bash
az afd origin show \
  --resource-group rg-drivershealth-prod \
  --profile-name fdh-prod \
  --origin-group-name dh-origin-group \
  --origin-name <origin-name>
```

Expected: `enabledState: "Enabled"`

### 5. Verify Monitoring
```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
  --resource-group rg-drivershealth-prod \
  --workspace-name law-fdh-prod
```

### 6. Test Alerts
```bash
# List configured alerts
az monitor metrics alert list \
  --resource-group rg-drivershealth-prod \
  -o table
```

Expected: 3 alerts listed

### 7. Review Diagnostic Settings
```bash
# Check diagnostic settings
az monitor diagnostic-settings list \
  --resource $(terraform output -raw frontdoor_id) \
  -o table
```

## Rollback Plan

If deployment fails or issues arise:

### 1. Review Error Messages
```bash
# Check Terraform output for errors
terraform plan

# Review Azure Activity Log
az monitor activity-log list \
  --resource-group rg-drivershealth-prod \
  --max-items 20
```

### 2. Destroy Resources
```bash
terraform destroy
```

### 3. Fix Configuration
- Review `terraform.tfvars`
- Check subscription permissions
- Verify naming conflicts
- Review quota limits

### 4. Retry Deployment
```bash
terraform plan
terraform apply
```

## Documentation

After successful deployment:

- [ ] Save deployment report
- [ ] Document Front Door endpoint URL
- [ ] Share WAF policy details with security team
- [ ] Update DNS records (if using custom domain)
- [ ] Document alert email recipients
- [ ] Schedule monitoring review

## Useful Commands

### Check Front Door Status
```bash
az afd profile show \
  --resource-group rg-drivershealth-prod \
  --profile-name fdh-prod
```

### View Origin Health
```bash
az afd origin list \
  --resource-group rg-drivershealth-prod \
  --profile-name fdh-prod \
  --origin-group-name dh-origin-group
```

### Check WAF Policy
```bash
az afd waf-policy show \
  --resource-group rg-drivershealth-prod \
  --name drivershealthprodwafpolicy
```

### View Logs
```bash
az monitor log-analytics query \
  --workspace law-fdh-prod \
  --analytics-query "AzureDiagnostics | where TimeGenerated > ago(1h)"
```

## Support and Troubleshooting

Contact: ops@pyxhealth.com

Common issues:
1. Subscription not found - Run selector again
2. Name conflict - Change Front Door name
3. Quota exceeded - Request quota increase
4. Backend not detected - Use manual hostname
5. Permissions denied - Verify Azure roles

---

**Ready to deploy? Run:**
```bash
./deploy.sh  # Linux/macOS
.\deploy.ps1  # Windows
```

**Estimated deployment time: 15-20 minutes**
