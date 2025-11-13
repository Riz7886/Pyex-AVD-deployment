# QUICK REFERENCE - AZURE FRONT DOOR COMMANDS

## 🚀 ONE-COMMAND DEPLOYMENT

```powershell
# Run as Administrator
.\Deploy-AzureFrontDoor-Complete.ps1
```

---

## 📋 PRE-DEPLOYMENT CHECKLIST

```powershell
# 1. Check Azure CLI installed
az --version

# 2. Check PowerShell modules
Get-Module -ListAvailable Az.*

# 3. Install missing modules
Install-Module -Name Az.Accounts, Az.FrontDoor, Az.Resources, Az.Monitor, Az.Network -Force

# 4. Login to Azure
Connect-AzAccount

# 5. Check subscriptions
Get-AzSubscription

# 6. Set correct subscription
Set-AzContext -SubscriptionName "sub-corp-prod-001"
```

---

## ✅ POST-DEPLOYMENT VERIFICATION

```powershell
# Check Front Door exists
Get-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod"

# Check Front Door status
(Get-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod").Properties.ProvisioningState

# List all Front Doors
Get-AzFrontDoor -ResourceGroupName "Production"

# Check WAF Policy
Get-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy"

# Test endpoint (PowerShell)
Invoke-WebRequest -Uri "https://afd-identity-prod-e2agzc2beucane2-z02.azurefd.net" -Method HEAD

# Test endpoint (curl)
curl -I https://afd-identity-prod-e2agzc2beucane2-z02.azurefd.net
```

---

## 📊 MONITORING COMMANDS

```powershell
# View diagnostic settings
Get-AzDiagnosticSetting -ResourceId "/subscriptions/{sub-id}/resourceGroups/Production/providers/Microsoft.Cdn/profiles/fdp-prod"

# View alerts
Get-AzMetricAlertRuleV2 -ResourceGroupName "Production"

# View logs (requires Log Analytics)
Get-AzOperationalInsightsWorkspace -ResourceGroupName "Production"

# Check Front Door metrics
Get-AzMetric -ResourceId "/subscriptions/{sub-id}/resourceGroups/Production/providers/Microsoft.Cdn/profiles/fdp-prod" -MetricName "TotalLatency"
```

---

## 🔒 SECURITY COMMANDS

```powershell
# Check managed identity
$fd = Get-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod"
$fd.Identity

# View WAF rules
$waf = Get-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy"
$waf.ManagedRules

# Check resource locks
Get-AzResourceLock -ResourceGroupName "Production"

# View security policies
az afd security-policy list --profile-name fdp-prod --resource-group Production
```

---

## 🔧 CONFIGURATION COMMANDS

```powershell
# List endpoints
az afd endpoint list --profile-name fdp-prod --resource-group Production

# List origin groups
az afd origin-group list --profile-name fdp-prod --resource-group Production

# List origins
az afd origin list --profile-name fdp-prod --origin-group-name prod-origin-group --resource-group Production

# List routes
az afd route list --profile-name fdp-prod --endpoint-name afd-identity-prod --resource-group Production

# View custom domains
az afd custom-domain list --profile-name fdp-prod --resource-group Production
```

---

## 📈 HEALTH CHECK COMMANDS

```powershell
# Check origin health
az afd origin show --profile-name fdp-prod --origin-group-name prod-origin-group --origin-name appcsvc-pyx-identity-productazurewebsites-net --resource-group Production

# View health probe settings
az afd origin-group show --profile-name fdp-prod --origin-group-name prod-origin-group --resource-group Production

# Test origin directly
Test-NetConnection -ComputerName appcsvc-pyx-identity-prod.azurewebsites.net -Port 443
```

---

## 🗑️ CLEANUP COMMANDS (USE WITH CAUTION!)

```powershell
# Remove entire Front Door (NOT RECOMMENDED FOR PRODUCTION!)
Remove-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod" -Force

# Remove WAF policy
Remove-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy" -Force

# Remove resource lock
Remove-AzResourceLock -ResourceGroupName "Production" -LockName "fdp-prod-lock" -Force

# Remove entire resource group (DANGER!)
Remove-AzResourceGroup -Name "Production" -Force
```

---

## 🔄 UPDATE COMMANDS

```powershell
# Update Front Door tags
Update-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod" -Tag @{Environment="Production"; UpdatedBy="Admin"}

# Update WAF policy mode
Update-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy" -Mode "Detection"

# Update origin weight
az afd origin update --profile-name fdp-prod --origin-group-name prod-origin-group --origin-name appcsvc-pyx-identity-productazurewebsites-net --resource-group Production --weight 500

# Enable/disable endpoint
az afd endpoint update --profile-name fdp-prod --endpoint-name afd-identity-prod --resource-group Production --enabled-state Enabled
```

---

## 📤 EXPORT COMMANDS

```powershell
# Export Front Door configuration
$fd = Get-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod"
$fd | ConvertTo-Json -Depth 10 | Out-File "FrontDoor-Config.json"

# Export WAF policy
$waf = Get-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy"
$waf | ConvertTo-Json -Depth 10 | Out-File "WAF-Policy.json"

# Export via Azure CLI
az afd profile show --profile-name fdp-prod --resource-group Production > FrontDoor-Export.json

# Export ARM template
Export-AzResourceGroup -ResourceGroupName "Production" -Resource "/subscriptions/{sub-id}/resourceGroups/Production/providers/Microsoft.Cdn/profiles/fdp-prod" -Path ".\FrontDoor-Template.json"
```

---

## 🔍 TROUBLESHOOTING COMMANDS

```powershell
# View activity log
Get-AzLog -ResourceGroupName "Production" -MaxRecord 20

# View Front Door operations
Get-AzLog -ResourceProvider "Microsoft.Cdn" -StartTime (Get-Date).AddDays(-1)

# Check provisioning state
$fd = Get-AzFrontDoor -ResourceGroupName "Production" -Name "fdp-prod"
$fd.Properties.ProvisioningState

# View detailed error
$error[0] | Format-List * -Force

# Test DNS resolution
Resolve-DnsName afd-identity-prod-e2agzc2beucane2-z02.azurefd.net

# Test SSL certificate
openssl s_client -connect afd-identity-prod-e2agzc2beucane2-z02.azurefd.net:443 -servername afd-identity-prod-e2agzc2beucane2-z02.azurefd.net
```

---

## 📊 REPORTING COMMANDS

```powershell
# Get Front Door report
az afd profile list --resource-group Production --output table

# Get traffic statistics
az afd profile usage list --profile-name fdp-prod --resource-group Production

# View WAF statistics
$waf = Get-AzFrontDoorWafPolicy -ResourceGroupName "Production" -Name "identityprodfwafpolicy"
$waf | Select-Object Name, PolicyMode, PolicyEnabledState

# Export metrics to CSV
Get-AzMetric -ResourceId "/subscriptions/{sub-id}/resourceGroups/Production/providers/Microsoft.Cdn/profiles/fdp-prod" -MetricName "TotalLatency" -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date) -TimeGrain 01:00:00 | Export-Csv "Metrics.csv"
```

---

## 🎯 USEFUL ALIASES

```powershell
# Create helpful aliases
Set-Alias -Name "Get-FD" -Value "Get-AzFrontDoor"
Set-Alias -Name "Get-WAF" -Value "Get-AzFrontDoorWafPolicy"

# Use them
Get-FD -ResourceGroupName "Production" -Name "fdp-prod"
Get-WAF -ResourceGroupName "Production" -Name "identityprodfwafpolicy"
```

---

## 📝 COMMON SCENARIOS

### Scenario 1: Add new origin
```powershell
az afd origin create \
    --resource-group Production \
    --profile-name fdp-prod \
    --origin-group-name prod-origin-group \
    --origin-name new-backend \
    --host-name newbackend.azurewebsites.net \
    --priority 1 \
    --weight 1000 \
    --enabled-state Enabled
```

### Scenario 2: Update health probe
```powershell
az afd origin-group update \
    --resource-group Production \
    --profile-name fdp-prod \
    --origin-group-name prod-origin-group \
    --probe-interval-in-seconds 60 \
    --probe-path "/health"
```

### Scenario 3: Add custom domain
```powershell
az afd custom-domain create \
    --resource-group Production \
    --profile-name fdp-prod \
    --custom-domain-name custom-domain-name \
    --host-name www.example.com \
    --minimum-tls-version TLS12
```

---

## 🌐 USEFUL URLS

- Azure Portal: https://portal.azure.com
- Front Door Docs: https://aka.ms/afd-docs
- WAF Docs: https://aka.ms/waf-docs
- Pricing: https://azure.microsoft.com/pricing/details/frontdoor/

---

## 💡 TIPS & TRICKS

1. **Always use -WhatIf** for destructive operations
2. **Tag all resources** for better cost management
3. **Enable diagnostic logs** from day 1
4. **Set up alerts** before issues occur
5. **Test in non-prod** environment first
6. **Document all changes** in change log
7. **Review WAF logs** regularly
8. **Monitor latency** and error rates
9. **Keep backups** of configurations
10. **Use managed identities** instead of keys

---

© 2025 Pyx Health - Quick Reference Guide
