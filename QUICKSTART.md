# QUICK START GUIDE - AZURE FRONT DOOR DEPLOYMENT

## 5-MINUTE DEPLOYMENT

### STEP 1: DOWNLOAD FILES
Download all files to: C:\Projects\Terraform-Cloud-Deployments\Pyx-AVD-deployment\DriversHealth-FrontDoor

Required files:
- Deploy-FrontDoor-Complete.ps1
- main.tf
- variables.tf
- outputs.tf
- terraform.tfvars.example

### STEP 2: RUN DEPLOYMENT
Open PowerShell as Administrator:

```powershell
cd C:\Projects\Terraform-Cloud-Deployments\Pyx-AVD-deployment\DriversHealth-FrontDoor
.\Deploy-FrontDoor-Complete.ps1
```

### STEP 3: FOLLOW PROMPTS

1. SUBSCRIPTION SELECTION
   - View all subscriptions with full details
   - Enter number to select
   - Or press ENTER for current
   - Or type NEW to create subscription

2. BACKEND SERVER
   - Select from existing App Services
   - Or enter custom hostname
   - Default: drivershealth.azurewebsites.net

3. ALERT EMAIL
   - Enter email for alerts
   - Default: devops@drivershealth.com

4. CONFIRM DEPLOYMENT
   - Review configuration summary
   - Press ENTER to deploy

### STEP 4: WAIT FOR COMPLETION
- Deployment takes 5-10 minutes
- Progress shown in console
- Front Door URL displayed when complete

### STEP 5: TEST DEPLOYMENT
```powershell
# Test Front Door URL
curl -I https://your-frontdoor-endpoint.azurefd.net

# Or open in browser
start https://your-frontdoor-endpoint.azurefd.net
```

## WHAT GETS DEPLOYED

### Core Infrastructure
- Front Door Premium
- WAF Policy (Prevention Mode)
- Log Analytics (90-day retention)
- Action Group (Email alerts)

### Security Features
- HTTPS Redirect
- Rate Limiting (100 req/min)
- SQL Injection Protection
- Bot Protection
- Certificate Validation

### Monitoring
- Backend Health Alert
- WAF Blocks Alert
- Response Time Alert
- Error Rate Alert

## QUICK VERIFICATION CHECKLIST

1. FRONT DOOR URL WORKS
```powershell
curl -I https://your-endpoint.azurefd.net
```
Expected: HTTP 200 or 301/302 redirect

2. BACKEND HEALTHY
Azure Portal > Front Door > Origins
Expected: Status = Healthy

3. WAF ACTIVE
Azure Portal > Front Door > Security
Expected: Policy = Prevention Mode

4. ALERTS CONFIGURED
Azure Portal > Monitor > Alerts
Expected: 4 alert rules active

5. LOGS FLOWING
Azure Portal > Log Analytics > Logs
Expected: Recent log entries visible

## COMMON FIRST-TIME ISSUES

### Issue 1: Backend Connection Failed
Symptom: Origin shows Unhealthy
Solution:
- Verify backend hostname is correct
- Ensure backend accepts HTTPS
- Check backend is running

### Issue 2: Terraform Not Found
Symptom: Command not recognized
Solution:
```powershell
# Install Terraform
choco install terraform
# Or download from terraform.io
```

### Issue 3: Azure CLI Not Found
Symptom: az command not recognized
Solution:
```powershell
# Install Azure CLI
winget install Microsoft.AzureCLI
# Or download from aka.ms/installazurecli
```

### Issue 4: Permission Denied
Symptom: Authorization failed
Solution:
- Ensure Contributor role on subscription
- Contact Azure administrator

## IMMEDIATE NEXT STEPS

1. BOOKMARK FRONT DOOR URL
Save the URL for testing and monitoring

2. CONFIGURE DNS (OPTIONAL)
Point your domain to Front Door:
```
CNAME: www.yourcompany.com -> frontdoor-endpoint.azurefd.net
```

3. MONITOR ALERTS
Check email for alert test messages

4. REVIEW LOGS
Portal > Log Analytics > law-fdh-prod

5. SHARE URL
Provide Front Door URL to team for testing

## COST AWARENESS

Expected monthly cost: $340-400 USD
- Front Door Premium: $330
- Log Analytics: $10-30
- Data Transfer: Variable

Monitor costs:
Portal > Cost Management > Cost Analysis

## QUICK COMMANDS REFERENCE

### View deployment info
```powershell
terraform output
```

### View resource group
```powershell
az group show --name rg-DriversHealth-prod
```

### View Front Door
```powershell
az afd profile show --profile-name fdh-prod --resource-group rg-DriversHealth-prod
```

### View WAF policy
```powershell
az network front-door waf-policy show --name drivershealthprodwafpolicy --resource-group rg-DriversHealth-prod
```

### View recent logs
```powershell
az monitor log-analytics query --workspace law-fdh-prod --analytics-query "AzureDiagnostics | where Category == 'FrontDoorAccessLog' | order by TimeGenerated desc | take 10"
```

### Update backend
```powershell
# Edit terraform.tfvars
notepad terraform.tfvars

# Apply changes
terraform apply
```

### Destroy all resources
```powershell
terraform destroy
```

## SUPPORT RESOURCES

### Quick Links
- Azure Portal: https://portal.azure.com
- Front Door Docs: https://docs.microsoft.com/azure/frontdoor/
- Terraform Docs: https://registry.terraform.io/providers/hashicorp/azurerm/

### Log Locations
- Access Logs: Portal > Log Analytics > law-fdh-prod
- WAF Logs: Portal > Log Analytics > law-fdh-prod
- Alert History: Portal > Monitor > Alerts

### Configuration Files
- Backend: terraform.tfvars
- Security Rules: main.tf (WAF section)
- Monitoring: main.tf (Alert section)

## CLIENT DEPLOYMENT

To deploy for different client:

1. Edit terraform.tfvars:
```hcl
project_name = "ClientName"
backend_host_name = "client-backend.azurewebsites.net"
alert_email_address = "client-alerts@company.com"
```

2. Run deployment:
```powershell
.\Deploy-FrontDoor-Complete.ps1
```

Resources created with client naming:
- Resource Group: rg-ClientName-prod
- Front Door: fdh-prod
- Endpoint: afd-clientname-prod

## TROUBLESHOOTING ONE-LINERS

### Check if Terraform installed
```powershell
terraform version
```

### Check if Azure CLI installed
```powershell
az version
```

### Login to Azure
```powershell
az login
```

### List subscriptions
```powershell
az account list --output table
```

### Set subscription
```powershell
az account set --subscription "subscription-name"
```

### Verify current subscription
```powershell
az account show
```

### Check resource group
```powershell
az group exists --name rg-DriversHealth-prod
```

### View deployment
```powershell
terraform show
```

### Validate configuration
```powershell
terraform validate
```

### Plan changes
```powershell
terraform plan
```

## SUCCESS INDICATORS

Deployment successful when:
1. Front Door URL returns valid response
2. Backend shows Healthy status
3. WAF policy shows Prevention mode
4. 4 alert rules are active
5. Logs appear in Log Analytics
6. Email test alert received

## TIME ESTIMATES

- File download: 1 minute
- Script execution: 2 minutes
- Azure deployment: 5-10 minutes
- Verification: 2 minutes
- Total: 10-15 minutes

## PRODUCTION READINESS

Before production use:
1. Test Front Door URL thoroughly
2. Verify backend health is stable
3. Review WAF logs for false positives
4. Configure custom domain and DNS
5. Set up backup/disaster recovery plan
6. Document environment-specific settings
7. Train team on monitoring procedures

## MAINTENANCE SCHEDULE

### Daily
- Check alert emails

### Weekly
- Review WAF block logs
- Verify backend health

### Monthly
- Review cost analysis
- Update documentation
- Test disaster recovery

### Quarterly
- Review security policies
- Update WAF rules if needed
- Performance optimization review

## GETTING HELP

If deployment fails:
1. Read error message carefully
2. Check Azure Portal for resource status
3. Review README.md troubleshooting section
4. Check Azure service health
5. Verify subscription permissions
6. Contact Azure support if needed

Common error patterns:
- "401 Unauthorized" = Check Azure login
- "403 Forbidden" = Check subscription permissions
- "Resource not found" = Check resource names
- "Quota exceeded" = Request quota increase
- "Validation failed" = Check configuration syntax

## QUICK WINS

After deployment:
1. Share Front Door URL with team
2. Set up browser bookmark
3. Add to monitoring dashboard
4. Document in runbook
5. Schedule first security review

This completes your 5-minute deployment. For detailed information, see README.md.
