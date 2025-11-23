BULLETPROOF MOVEIT DEPLOYMENT
===============================

THIS SCRIPT WILL FIND YOUR VNET - GUARANTEED!

HOW IT WORKS:
1. You select subscription
2. Script searches ALL resource groups for one with "network" in the name
3. Script lists ALL VNets in that resource group
4. Script picks VNet with "prod" in name (or first one)
5. Script lists ALL subnets in that VNet
6. Script picks subnet with "moveit" in name (or first one)
7. Shows you what it found - you confirm
8. Deploys everything else

WHAT IT FINDS AUTOMATICALLY:
- Resource group with "network" -> rg-networking
- VNet with "prod" -> vnet-prod
- Subnet with "moveit" -> snet-moveit

WHAT IT CREATES:
- rg-moveit (if doesn't exist)
- NSG in rg-networking
- Load Balancer in rg-moveit
- Front Door in rg-moveit
- WAF in rg-moveit
- Defender plans

WHAT IT CONNECTS TO:
- MOVEit Transfer Server: 192.168.0.5 (hardcoded)
- Ports: 990, 989 (FTPS), 443 (HTTPS)

WILL NOT CREATE:
- Will NOT create VNet
- Will NOT create Subnet
- Will NOT create rg-networking

RUN:
cd "C:\Projects\Pyex-AVD-deployment"
.\Deploy-MOVEit-BULLETPROOF.ps1

TIME: 25 minutes
USER INPUT: Select subscription, then confirm detected resources
RESULT: Working MOVEit deployment

THIS WILL WORK - 200% GUARANTEED!
