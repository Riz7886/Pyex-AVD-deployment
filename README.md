# Azure Bastion Deployment Toolkit - ULTIMATE Edition

Enterprise-Grade Azure Bastion Solution with Multi-VNet Support

Version: 2.0  
Last Updated: November 2, 2025  
Status: Production Ready

---

## WHAT'S INCLUDED - 7 SCRIPTS

Core Deployment Scripts:
1. Deploy-Bastion-ULTIMATE.ps1 - Deploy Bastion infrastructure
2. Deploy-2-Windows-VMs-For-Bastion.ps1 - Quick 2 Windows VMs deployment
3. Deploy-Multiple-VMs-ULTIMATE.ps1 - Flexible VM deployment (any OS, any quantity)

Management Scripts:
4. Fix-Bastion-Connectivity.ps1 - Connect existing VMs to Bastion
5. Configure-Bastion-VPN-Security.ps1 - Add VPN security layer

Utility Scripts:
6. Quick-Bastion-Test.ps1 - Fast connectivity verification
7. VPN-Detection-Module.ps1 - VPN detection helper

---

## WHEN TO USE EACH SCRIPT

Scenario 1: Client Has Existing VMs
Step 1: Deploy Bastion in their environment
.\Deploy-Bastion-ULTIMATE.ps1
Choose Mode 1, Select their Resource Group/VNet

Step 2: Connect ALL their VMs
.\Fix-Bastion-Connectivity.ps1
Automatically finds and connects all VMs

Step 3: Add VPN security
.\Configure-Bastion-VPN-Security.ps1
Optional: Enforce VPN requirement for end users

Scenario 2: New Deployment (Testing/Demo)
Step 1: Deploy Bastion
.\Deploy-Bastion-ULTIMATE.ps1
Choose Mode 2, Create new infrastructure

Step 2: Deploy test VMs
.\Deploy-Multiple-VMs-ULTIMATE.ps1
Choose OS, quantity, size, storage options

Step 3: Verify connectivity
.\Quick-Bastion-Test.ps1

Scenario 3: Quick 2 VM Test
Step 1: Deploy Bastion
.\Deploy-Bastion-ULTIMATE.ps1

Step 2: Deploy 2 Windows VMs (faster than ULTIMATE)
.\Deploy-2-Windows-VMs-For-Bastion.ps1
Simple, quick, Windows 2022, B2s size

---

## STEP-BY-STEP DEPLOYMENT GUIDE

PREPARATION:
1. Open PowerShell as Administrator
2. Navigate to scripts folder
   cd D:\Azure-Production-Scripts
3. Verify all scripts are present
   Get-ChildItem -Filter "*.ps1" | Select-Object Name

---

DEPLOYMENT WORKFLOW 1: CLIENT WITH EXISTING VMs

Timeline: 20-30 minutes

Step 1: Deploy Bastion (10-15 min)
.\Deploy-Bastion-ULTIMATE.ps1

You'll be prompted for:
- Azure subscription (if multiple)
- Deployment mode: Choose 1 (Use existing)
- Select client's Resource Group
- Select client's VNet
- Bastion configuration: Standard SKU (recommended)

What it creates:
- Bastion host
- Public IP address
- AzureBastionSubnet (if doesn't exist)

Cost: ~$140/month for Standard SKU

---

Step 2: Connect Existing VMs (2-5 min)
.\Fix-Bastion-Connectivity.ps1

What it does automatically:
- Scans entire subscription for VMs
- Identifies VMs not connected to Bastion
- Creates VNet peering for all unconnected VMs
- Works with both Windows and Linux VMs

Output: Shows list of connected VMs with IPs

---

Step 3: Add VPN Security (Optional - 2 min)
.\Configure-Bastion-VPN-Security.ps1

You'll be prompted for:
- Corporate VPN IP ranges (default: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)

What it does:
- Adds NSG rules to Bastion subnet
- Only allows connections from VPN IP ranges
- Blocks non-VPN access

Security: Enforces VPN requirement for end users

---

Step 4: Verify Everything Works (30 sec)
.\Quick-Bastion-Test.ps1

Output:
- Bastion status
- Connected VMs count
- Direct connection links for each VM

---

Step 5: Connect to VMs

Option A: Azure Portal (Easiest)
1. Portal -> Virtual Machines
2. Click on VM
3. Click "Connect" -> "Connect via Bastion"
4. Enter credentials
5. Windows desktop appears in browser

Option B: Direct Link
Use the links from Quick-Bastion-Test.ps1 output

---

DEPLOYMENT WORKFLOW 2: NEW DEPLOYMENT WITH FLEXIBLE VMs

Timeline: 25-40 minutes

Step 1: Deploy Bastion (10-15 min)
.\Deploy-Bastion-ULTIMATE.ps1

Choose:
- Deployment mode: 2 (Create new)
- Location: eastus (or client preference)
- Bastion SKU: Standard

---

Step 2: Deploy VMs with Full Flexibility (15-25 min)
.\Deploy-Multiple-VMs-ULTIMATE.ps1

You'll choose:

OS Selection:
[1] Windows Server 2019
[2] Windows Server 2022 (Recommended)
[3] Ubuntu 22.04 LTS
[4] Ubuntu 20.04 LTS
[5] Red Hat Enterprise Linux 9
[6] CentOS 8

Quantity:
1-50 VMs (enter number)

VM Size with Cost Estimates:
[1] Standard_B2s - 2 vCPU, 4GB RAM (~$30/month) - Budget
[2] Standard_B2ms - 2 vCPU, 8GB RAM (~$60/month) - Budget+
[3] Standard_D2s_v3 - 2 vCPU, 8GB RAM (~$70/month) - Balanced (Recommended)
[4] Standard_D4s_v3 - 4 vCPU, 16GB RAM (~$140/month) - Performance
[5] Standard_E2s_v3 - 2 vCPU, 16GB RAM (~$110/month) - Memory
[6] Standard_E4s_v3 - 4 vCPU, 32GB RAM (~$220/month) - High Memory
[7] Custom (enter your own)

Storage Account (Windows only):
[Y] Yes - Configure FSLogix user profiles
[N] No - Skip storage

Admin Credentials:
- Enter username
- Enter password

What it creates:
- Resource Group
- VNet with subnet
- NSG with RDP/SSH rules
- VMs (all at once, parallel deployment)
- VNet peering to Bastion
- Optional: Storage account with Azure Files share

---

Step 3: Verify & Connect
.\Quick-Bastion-Test.ps1

Then connect via Portal or direct links.

---

DEPLOYMENT WORKFLOW 3: QUICK 2 VM TEST

Timeline: 15-25 minutes

Best for: Quick testing, demos, proof-of-concept

Step 1: Deploy Bastion (10-15 min)
.\Deploy-Bastion-ULTIMATE.ps1
Choose Mode 2

Step 2: Deploy 2 Windows VMs (10-15 min)
.\Deploy-2-Windows-VMs-For-Bastion.ps1
Prompts:
  Need storage? (Y/N): N (for quick test)
  Admin username: admin123
  Admin password: YourPassword123!

Step 3: Test (30 sec)
.\Quick-Bastion-Test.ps1

Step 4: Connect via Portal

What you get:
- 2 Windows Server 2022 VMs
- Standard_B2s size (~$30/month each)
- Ready to connect via Bastion
- No storage (add later if needed)

---

## VPN SECURITY - HOW IT WORKS

Admin Deployment (No VPN Required):
- Admins can deploy Bastion without VPN
- Admins can deploy VMs without VPN
- Admins can configure infrastructure without VPN

End User Access (VPN Required - Optional):
After deployment, run this to enforce VPN:
.\Configure-Bastion-VPN-Security.ps1

This adds NSG rules that:
- Only allow Bastion access from corporate VPN IPs
- Block all non-VPN access
- Azure enforces at network level

End User Workflow:
1. Connect to Cisco AnyConnect VPN
2. Open Azure Portal
3. Navigate to VM -> Connect -> Bastion
4. Enter credentials -> Connect

---

## COST ESTIMATES

Bastion:
- Basic SKU: ~$110/month (supports 25 connections)
- Standard SKU: ~$140/month (supports 50+ connections, recommended)

VMs (per VM per month):
- B2s: ~$30 (budget)
- B2ms: ~$60 (budget+)
- D2s_v3: ~$70 (balanced)
- D4s_v3: ~$140 (performance)
- E2s_v3: ~$110 (memory)
- E4s_v3: ~$220 (high memory)

Storage (optional):
- Azure Files: ~$0.20/GB/month
- 100GB share: ~$20/month

Example Deployment:
- 1 Bastion (Standard): $140
- 5 VMs (D2s_v3): $350 ($70 x 5)
- 1 Storage (100GB): $20
- Total: ~$510/month

---

## TROUBLESHOOTING

Issue: Script not recognized
WRONG:
Deploy-Bastion-ULTIMATE.ps1

CORRECT:
.\Deploy-Bastion-ULTIMATE.ps1

Always use .\ before script name!

---

Issue: VMs not accessible via Bastion
Solution: Run connectivity fix
.\Fix-Bastion-Connectivity.ps1
This automatically creates VNet peering.

---

Issue: Popup blocker preventing Bastion connection
Solution:
1. Look for popup blocked icon in browser address bar
2. Click it -> Allow popups from portal.azure.com
3. OR: Check "Open in new browser tab" option
4. Try connecting again

---

Issue: "No Bastion found" error
Solution:
Deploy Bastion first:
.\Deploy-Bastion-ULTIMATE.ps1
Then run other scripts.

---

## SCRIPT COMPARISON

Feature                 | Deploy-Bastion | Deploy-2-VMs | Deploy-Multiple-VMs
------------------------|----------------|--------------|---------------------
Deploys Bastion         | YES            | NO           | NO
Deploys VMs             | NO             | YES          | YES
OS Choice               | N/A            | Win 2022 only| Win 2019/2022, Ubuntu, RHEL
VM Quantity             | N/A            | 2 (fixed)    | 1-50 (choose)
VM Size                 | N/A            | B2s (fixed)  | 6 presets + custom
Storage Option          | NO             | YES          | YES
Use Existing Infra      | YES            | NO           | NO

---

## BEST PRACTICES

For Client Deployments:
1. Always use Standard SKU Bastion (supports more connections)
2. Use existing client infrastructure (Mode 1)
3. Run Fix-Bastion-Connectivity.ps1 to connect all VMs
4. Add VPN security if client requires it
5. Test connection before demo to client

For Testing:
1. Use Mode 2 (create new) for isolated testing
2. Start with 1-2 VMs, then scale up
3. Use B2s size for cheapest testing
4. Skip storage for quick tests
5. Delete test resources when done

For Production:
1. Use appropriate VM sizes for workload
2. Enable storage account for user profiles
3. Document VM credentials securely
4. Configure VPN security
5. Monitor costs via Azure Cost Management

---

## QUICK REFERENCE

Deploy Everything (New Environment):
.\Deploy-Bastion-ULTIMATE.ps1           # 10-15 min
.\Deploy-Multiple-VMs-ULTIMATE.ps1      # 15-25 min
.\Quick-Bastion-Test.ps1                # 30 sec

Connect Existing Infrastructure:
.\Deploy-Bastion-ULTIMATE.ps1           # Mode 1
.\Fix-Bastion-Connectivity.ps1          # Auto-connects all
.\Quick-Bastion-Test.ps1                # Verify

Add Security:
.\Configure-Bastion-VPN-Security.ps1    # NSG rules

Quick Test:
.\Deploy-Bastion-ULTIMATE.ps1           # Mode 2
.\Deploy-2-Windows-VMs-For-Bastion.ps1  # Quick 2 VMs

---

## SUPPORT & DOCUMENTATION

Azure Bastion Documentation:
https://docs.microsoft.com/en-us/azure/bastion/

Pricing Calculator:
https://azure.microsoft.com/en-us/pricing/calculator/

Script Repository:
GitHub: https://github.com/Riz7886/Pyex-AVD-deployment

---

## TESTING CHECKLIST

Before deploying at client site:

[ ] All scripts present in folder
[ ] Azure credentials working
[ ] Tested Bastion deployment (Mode 1 & 2)
[ ] Tested VM deployment
[ ] Tested connectivity via Portal
[ ] Verified VNet peering works
[ ] Tested Fix-Bastion-Connectivity.ps1
[ ] Documented client requirements
[ ] Confirmed VM sizes and costs
[ ] Tested VPN security (if required)

---

## CHANGELOG

Version 2.0 (November 2, 2025)
- Added Deploy-Multiple-VMs-ULTIMATE.ps1 (flexible OS, quantity, size)
- Added VPN security option (Configure-Bastion-VPN-Security.ps1)
- Added storage account support for FSLogix profiles
- Removed VPN checks from deployment scripts (admins don't need VPN)
- Added Quick-Bastion-Test.ps1 for fast verification
- Enhanced Fix-Bastion-Connectivity.ps1 for Linux support
- All scripts tested and production-ready

Version 1.0 (October 2025)
- Initial release
- Deploy-Bastion-ULTIMATE.ps1
- Deploy-2-Windows-VMs-For-Bastion.ps1

---

## PRODUCTION READY

All 7 scripts are:
- Tested and working
- Error-free
- In Git repository
- Ready for client deployments
- Fully documented

Go deploy with confidence!
