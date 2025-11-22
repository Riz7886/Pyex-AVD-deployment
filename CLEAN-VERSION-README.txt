============================================
MOVEIT DEPLOYMENT - CLEAN VERSION
NO SPECIAL CHARACTERS
FIXED LINE ENDINGS
============================================

WHAT WAS FIXED:
- Removed all checkmarks and special characters
- Fixed Windows line endings (CRLF)
- Pure ASCII only
- No unicode characters

HARDCODED VALUES:
- Resource Group: rg-moveit
- VNet: vnet-prod
- Subnet: snet-moveit
- MOVEit IP: 192.168.0.5

RUN COMMAND:
cd "C:\Projects\Pyex-AVD-deployment"
.\Deploy-MOVEit-PRODUCTION-CLEAN.ps1

WHAT IT DOES:
1. Checks Azure CLI
2. Checks login
3. Shows subscriptions - YOU SELECT ONE
4. Verifies rg-moveit exists
5. Verifies vnet-prod exists
6. Verifies snet-moveit exists
7. Creates NSG (ports 990, 989, 443)
8. Creates Load Balancer (FTPS)
9. Creates WAF Policy (pyxiq config)
10. Creates Front Door (HTTPS)
11. Enables Microsoft Defender
12. Shows FTPS IP and HTTPS URL
13. DONE

TIME: 25 minutes

WHAT IT DEPLOYS:
- Load Balancer for FTPS (ports 990, 989)
- Front Door for HTTPS (port 443)
- WAF with DefaultRuleSet 1.0 (117+ rules)
- Bot Manager
- NSG with 3 rules
- Microsoft Defender (3 plans)

CONNECTS TO:
- MOVEit Transfer Server: 192.168.0.5
- In VNet: vnet-prod
- In Subnet: snet-moveit

USERS CAN:
- Upload files via FTPS
- Download files via FTPS
- Access web via HTTPS
- Files up to 500 MB

COST:
- Load Balancer: $18/month
- Front Door: $35/month
- WAF: $30/month
- TOTAL: $83/month

SAVINGS: $1,417/month vs MOVEit Gateway

IF SCRIPT WONT RUN:
Set-ExecutionPolicy Bypass -Scope Process
.\Deploy-MOVEit-PRODUCTION-CLEAN.ps1

DONE!
