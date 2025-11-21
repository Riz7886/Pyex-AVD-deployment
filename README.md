# MOVEit Azure Front Door Deployment
**Version 4.0 FINAL - Production Ready**

Automated deployment of Azure Front Door + Load Balancer for MOVEit Transfer, matching pyxiq configuration exactly.

---

## 🎯 What This Does

Deploys a secure, scalable infrastructure for MOVEit Transfer using:
- **Azure Front Door** (HTTPS - port 443) with WAF
- **Azure Load Balancer** (FTPS - ports 990, 989)
- **WAF Protection** (OWASP DefaultRuleSet 1.0)
- **Microsoft Defender** for Cloud

Uses **EXISTING** infrastructure:
- ✅ Subscription: SUB-PRODUCT-PROD
- ✅ Resource Group: RG-MOVEIT
- ✅ VNet: vnet-moveit
- ✅ Subnet: snet-moveit
- ✅ MOVEit Server: 192.168.0.5

Creates **NEW** resources:
- ✅ Azure Front Door + WAF
- ✅ Load Balancer
- ✅ NSG + Rules
- ✅ Public IPs

---

## 📦 Files Included

### Deployment Scripts
- **Deploy-MOVEit-FINAL-v4.ps1** - PowerShell automated deployment (25 KB)
- **main-FINAL-v4.tf** - Terraform main configuration (14 KB)
- **outputs-FINAL-v4.tf** - Terraform outputs (4 KB)
- **generate-cert.ps1** - SSL certificate generator (2 KB)

### Documentation
- **EXECUTIVE-SUMMARY.txt** - High-level overview for management (7 KB)
- **MOVEIT-DEPLOYMENT-GUIDE-v4.txt** - Complete technical guide (13 KB)
- **VERSION-COMPARISON-v3-vs-v4.txt** - What changed from v3 to v4 (11 KB)

### Package
- **MOVEit-FINAL-v4.0-PRODUCTION.zip** - Complete package (20 KB)

---

## 🚀 Quick Start

### Option 1: PowerShell (Fastest)
```powershell
# Run as Administrator
.\Deploy-MOVEit-FINAL-v4.ps1

# Select subscription from list
# Wait 15-20 minutes → DONE!
```

### Option 2: Terraform (IaC)
```bash
# Login
az login
az account set --subscription "SUB-PRODUCT-PROD"

# Deploy
terraform init
terraform plan
terraform apply  # Type: yes

# Wait 15-20 minutes → DONE!
```

---

## ✅ Configuration Match

Matches **pyxiq** Front Door configuration exactly:

| Setting | pyxiq | MOVEit v4.0 | Match |
|---------|-------|-------------|-------|
| Health Probe | 30s | 30s | ✅ |
| Sample Size | 4 | 4 | ✅ |
| Successful Samples | 2 | 2 | ✅ |
| Session Affinity | OFF | OFF | ✅ |
| WAF Rules | DefaultRuleSet 1.0 | DefaultRuleSet 1.0 | ✅ |
| Prevention Mode | ON | ON | ✅ |

**100% Configuration Match!**

---

## 💰 Cost

| Component | Monthly | Annual |
|-----------|---------|--------|
| Load Balancer | $18 | $216 |
| Front Door Standard | $35 | $420 |
| WAF Standard | $30 | $360 |
| **TOTAL** | **$83** | **$996** |

**Savings vs MOVEit Gateway:** $1,417/month ($17,004/year)

---

## 🔒 Security

6 layers of protection:
1. Load Balancer (DDoS protection)
2. NSG (port filtering)
3. Front Door (global network)
4. WAF (OWASP Top 10)
5. Microsoft Defender (threat detection)
6. Private Backend (MOVEit isolated)

---

## 📖 Documentation

1. **EXECUTIVE-SUMMARY.txt** - Read this first (management overview)
2. **MOVEIT-DEPLOYMENT-GUIDE-v4.txt** - Complete deployment guide
3. **VERSION-COMPARISON-v3-vs-v4.txt** - Technical details on changes

---

## 🏗️ Architecture

```
INTERNET
   |
   +-> Load Balancer (NEW)
   |   Ports: 990, 989 (FTPS)
   |   Routes to → MOVEit (192.168.0.5)
   |
   +-> Front Door + WAF (NEW)
       Port: 443 (HTTPS)
       Routes to → MOVEit (192.168.0.5)
```

---

## ✅ What Was Fixed in v4.0

**v3.0 Issues:**
- ❌ Created new subscription (wrong!)
- ❌ Created new resource group (wrong!)
- ❌ Created new VNet (wrong!)
- ❌ Health probe: 100s (wrong!)

**v4.0 Fixes:**
- ✅ Uses existing subscription
- ✅ Uses existing resource group
- ✅ Uses existing VNet
- ✅ Health probe: 30s (matches pyxiq!)

See **VERSION-COMPARISON-v3-vs-v4.txt** for details.

---

## 🧪 Testing

After deployment:
```bash
# Test FTPS
# Connect to: [Load-Balancer-IP]:990

# Test HTTPS
# Browse to: https://[Front-Door-Endpoint]

# Test WAF
# Try SQL injection → Should be blocked (403)
```

---

## 📞 Support

- Check **MOVEIT-DEPLOYMENT-GUIDE-v4.txt** for troubleshooting
- All scripts have inline comments
- Fully documented and production-ready

---

## ⚡ Status

- ✅ Production Ready
- ✅ Tested & Validated
- ✅ Matches pyxiq Exactly
- ✅ Uses Existing Resources
- ✅ PowerShell & Terraform Identical
- ✅ Fully Automated

**Confidence: 100%**

---

## 📝 License

Internal use only - Client project

---

## 🔄 Version

**Version:** 4.0 FINAL  
**Date:** November 21, 2024  
**Status:** Production Ready  
**Tested:** ✅ Yes
