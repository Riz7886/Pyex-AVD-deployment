# START HERE - DRIVERS HEALTH AZURE FRONT DOOR DEPLOYMENT

## What You Have

A **complete, production-ready Terraform package** to deploy Azure Front Door Premium for Drivers Health with:

- **Auto subscription detection** - Lists all subscriptions, lets you choose
- **Auto backend discovery** - Finds Drivers Health App Services automatically
- **DH naming convention** - All resources follow Drivers Health naming
- **Full security** - WAF, bot protection, rate limiting, HTTPS
- **Complete monitoring** - Log Analytics, alerts, diagnostics
- **Zero manual config** - One command deployment

## Quick Start (3 Steps)

### Linux / macOS
```bash
cd azure-frontdoor-terraform
chmod +x *.sh
./deploy.sh
```

### Windows
```powershell
cd azure-frontdoor-terraform
.\deploy.ps1
```

That's it! The script will:
1. Check prerequisites (Azure CLI, Terraform)
2. Let you select which subscription to deploy to
3. Initialize Terraform and install providers
4. Show you what will be created
5. Ask for confirmation
6. Deploy everything (~15 minutes)
7. Show you the Front Door URL

## What Gets Created

Your Drivers Health deployment will include:

```
Resource Group: rg-drivershealth-prod
Front Door: fdh-prod (Premium tier)
Endpoint: afd-drivershealth-prod.azurefd.net
Origin Group: dh-origin-group
WAF Policy: drivershealthprodwafpolicy (Prevention mode)
Log Analytics: law-fdh-prod
Alerts: 3 metric alerts configured
```

All with **complete security and monitoring!**

## Files in This Package

### Must Read
- **QUICKSTART.md** - Fastest way to deploy (read this first!)
- **README.md** - Complete documentation
- **CHECKLIST.md** - Pre-deployment verification

### Terraform Files (Ready to Deploy)
- **versions.tf** - Provider configuration
- **variables.tf** - All settings (with defaults)
- **data.tf** - Subscription and backend detection
- **main.tf** - Front Door resources
- **waf.tf** - Security policy
- **monitoring.tf** - Diagnostics and alerts
- **outputs.tf** - Deployment results

### Automation Scripts
- **deploy.sh** - Linux/macOS automated deployment
- **deploy.ps1** - Windows automated deployment
- **select-subscription.sh** - Linux/macOS subscription selector
- **select-subscription.ps1** - Windows subscription selector

### Configuration
- **terraform.tfvars.example** - Example configuration (copy to customize)

## Prerequisites

Before deploying, you need:

1. **Azure CLI** installed - [Download here](https://docs.microsoft.com/cli/azure/install-azure-cli)
2. **Terraform** installed (>= 1.5.0) - [Download here](https://www.terraform.io/downloads)
3. **Azure subscription** with Contributor or Owner role
4. **PowerShell 7+** (Windows only)

Check if you have them:
```bash
az --version
terraform version
```

If missing, install them before proceeding.

## First Deployment

### Super Simple Method (Recommended)
```bash
./deploy.sh  # Linux/macOS
.\deploy.ps1  # Windows
```

Just follow the prompts!

### Manual Method (More Control)
```bash
# Step 1: Select subscription
./select-subscription.sh  # Creates terraform.tfvars

# Step 2: Review configuration
cat terraform.tfvars

# Step 3: Deploy
terraform init
terraform plan
terraform apply
```

## After Deployment

You'll get output like this:

```
================================================================
DRIVERS HEALTH FRONT DOOR DEPLOYED SUCCESSFULLY!
================================================================

Service: Drivers Health
Front Door Name: fdh-prod
Endpoint: afd-drivershealth-prod-xxxxx.azurefd.net

Access URL: https://afd-drivershealth-prod-xxxxx.azurefd.net

WAF Policy: drivershealthprodwafpolicy
Mode: Prevention

Origin Group: dh-origin-group
Backend Count: 1

Log Analytics: law-fdh-prod

Managed Identity: System-Assigned

================================================================
```

**Test your Front Door:**
```bash
curl https://afd-drivershealth-prod-xxxxx.azurefd.net
```

## Customization

Want to customize before deploying?

### 1. Select Subscription
```bash
./select-subscription.sh  # This creates terraform.tfvars
```

### 2. Edit Configuration
```bash
nano terraform.tfvars  # or use your favorite editor
```

Common customizations:
```hcl
environment = "staging"          # Change environment
frontdoor_name = "fdh-staging"   # Change name
waf_mode = "Detection"           # Change WAF mode (testing)
manual_backend_hostname = "your-app.azurewebsites.net"  # Manual backend
```

### 3. Deploy with Custom Settings
```bash
terraform init
terraform plan
terraform apply
```

## Multiple Environments

Deploy to staging and production:

**Production:**
```bash
./deploy.sh  # Select prod subscription, use default config
```

**Staging:**
```bash
# Edit terraform.tfvars
environment = "staging"
resource_group_name = "rg-drivershealth-staging"
frontdoor_name = "fdh-staging"
endpoint_name = "afd-drivershealth-staging"

# Deploy
terraform apply
```

## Troubleshooting

### "No backends detected"
**Solution:** Specify manual backend in `terraform.tfvars`:
```hcl
auto_detect_backends = false
manual_backend_hostname = "your-app.azurewebsites.net"
```

### "Name already exists"
**Solution:** Change Front Door name to something unique:
```hcl
frontdoor_name = "fdh-prod-v2"
```

### "Subscription not found"
**Solution:** Run subscription selector again:
```bash
./select-subscription.sh
```

### "Permission denied"
**Solution:** Verify you have Contributor or Owner role:
```bash
az role assignment list --assignee $(az account show --query user.name -o tsv)
```

## Documentation Reference

- **QUICKSTART.md** - 3-step deployment guide
- **README.md** - Complete documentation with all options
- **CHECKLIST.md** - Pre-deployment verification steps
- **PACKAGE_SUMMARY.md** - What's in this package

## Security Features

Your Front Door includes:
- ✅ WAF with Microsoft Default Rule Set 2.1
- ✅ Bot Manager Rule Set 1.0
- ✅ Rate limiting (100 req/min)
- ✅ SQL injection protection
- ✅ HTTPS enforcement
- ✅ Certificate validation
- ✅ DDoS protection (native)

## Monitoring Features

Your deployment includes:
- ✅ Log Analytics workspace (90-day retention)
- ✅ Access logs
- ✅ Health probe logs
- ✅ WAF logs
- ✅ Metrics
- ✅ 3 pre-configured alerts:
  - High latency (>1000ms)
  - High error rate (>100 5xx)
  - Origin health (<50%)

## Cost Estimate

**Azure Front Door Premium:**
- Base: ~$330/month
- Data transfer: $0.075-0.15/GB
- Total: ~$330-400/month for typical workload

## Next Steps

1. **Read QUICKSTART.md** for fastest deployment
2. **Or run** `./deploy.sh` right now!
3. **Test** your Front Door after deployment
4. **Review** monitoring in Azure Portal
5. **Configure** custom domain (optional)

## Support

Questions or issues?
- Check **CHECKLIST.md** for verification steps
- Review **README.md** for detailed docs
- Contact: ops@pyxhealth.com

## Quick Commands Reference

```bash
# Select subscription
./select-subscription.sh

# Deploy (automated)
./deploy.sh

# Deploy (manual)
terraform init
terraform plan
terraform apply

# View outputs
terraform output

# Get endpoint URL
terraform output endpoint_url

# Destroy everything
terraform destroy
```

---

## Ready to Deploy?

**Linux/macOS:**
```bash
./deploy.sh
```

**Windows:**
```powershell
.\deploy.ps1
```

**That's it! Your Drivers Health Front Door will be ready in 15 minutes! 🚀**

---

*Drivers Health (DH) Naming Convention*  
*Pyx Health - Drivers Health Platform*  
*Deployed with Terraform*
