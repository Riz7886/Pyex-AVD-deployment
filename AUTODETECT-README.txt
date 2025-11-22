============================================
AUTO-DETECT VERSION - FINDS YOUR VNET
============================================

HOW IT WORKS:

1. Looks for rg-moveit
2. Finds ANY VNet in rg-moveit (vnet-prod, vnet-moveit, whatever you have)
3. Finds ANY Subnet in that VNet
4. Uses those automatically
5. Creates everything else

NO HARDCODED VNET NAMES!
NO HARDCODED SUBNET NAMES!
FINDS WHATEVER YOU HAVE!

RUN:
cd "C:\Projects\Pyex-AVD-deployment"
.\Deploy-MOVEit-AUTODETECT-FINAL.ps1

SELECT SUBSCRIPTION - THEN WAIT 25 MINUTES - DONE!

WHAT IT DEPLOYS:
- NSG (ports 990, 989, 443)
- Load Balancer (FTPS)
- Front Door (HTTPS)
- WAF Policy (pyxiq config)
- Microsoft Defender

CONNECTS TO:
- MOVEit IP: 192.168.0.5

USERS CAN:
- Upload/download via FTPS
- Upload/download via HTTPS
- Files up to 500 MB

COST: $83/month

IF IT WONT RUN:
Set-ExecutionPolicy Bypass -Scope Process
.\Deploy-MOVEit-AUTODETECT-FINAL.ps1

DONE!
