v4.0 FIXED - WORKS NOW

WHAT WAS WRONG:
v4.0 had: VNetName = "vnet-moveit"
You have: vnet-prod

WHAT I FIXED:
Changed: VNetName = "vnet-prod"
Changed: ResourceGroup = "rg-moveit"

THATS IT! NOTHING ELSE CHANGED!

RUN:
cd "C:\Projects\Pyex-AVD-deployment"
.\Deploy-MOVEit-FINAL-FIXED.ps1

1. Select subscription
2. Wait 25 minutes
3. DONE

HARDCODED VALUES:
ResourceGroup = "rg-moveit"
VNetName = "vnet-prod"
SubnetName = "snet-moveit"
MOVEitPrivateIP = "192.168.0.5"

WILL WORK NOW!
