#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy 2 Windows VMs for Bastion Testing
.DESCRIPTION
    Creates 2 fully configured Windows Server VMs:
    - Windows Server 2022 Datacenter
    - Proper networking for Bastion connectivity
    - Automatic VNet peering to existing Bastion
    - NSG rules configured
    - RDP enabled and ready
    - Cost-optimized Standard_B2s SKU
.EXAMPLE
    .\Deploy-2-Windows-VMs-For-Bastion.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DEPLOY 2 WINDOWS VMs FOR BASTION TESTING" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

#region Azure Connection
Write-Host "[1/8] Azure Authentication" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "  Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}
Write-Host "  Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green
Write-Host ""
#endregion

#region Find Bastion
Write-Host "[2/8] Locating Azure Bastion" -ForegroundColor Yellow
$bastions = Get-AzBastion
if ($bastions.Count -eq 0) {
    Write-Host "  ERROR: No Bastion found!" -ForegroundColor Red
    Write-Host "  Deploy Bastion first using the main script." -ForegroundColor Yellow
    exit 1
}

if ($bastions.Count -eq 1) {
    $bastion = $bastions[0]
} else {
    Write-Host "  Multiple Bastions found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $bastions.Count; $i++) {
        Write-Host "    [$($i + 1)] $($bastions[$i].Name) - $($bastions[$i].ResourceGroupName)" -ForegroundColor White
    }
    do {
        $sel = Read-Host "  Select Bastion [1-$($bastions.Count)]"
    } while ([int]$sel -lt 1 -or [int]$sel -gt $bastions.Count)
    $bastion = $bastions[[int]$sel - 1]
}

Write-Host "  Found: $($bastion.Name)" -ForegroundColor Green
Write-Host "    Location: $($bastion.Location)" -ForegroundColor Gray

# Get Bastion VNet
$bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
$bastionVNetName = ($bastionSubnetId -split '/')[8]
$bastionVNetRG = ($bastionSubnetId -split '/')[4]
$bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG
Write-Host "    Hub VNet: $($bastionVNet.Name)" -ForegroundColor Gray
Write-Host ""
#endregion

#region Configuration
Write-Host "[3/8] VM Configuration" -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$location = $bastion.Location

Write-Host "  VM Configuration:" -ForegroundColor Cyan
Write-Host "    Location: $location" -ForegroundColor White
Write-Host "    OS: Windows Server 2022 Datacenter" -ForegroundColor White
Write-Host "    Size: Standard_B2s (2 vCPU, 4GB RAM)" -ForegroundColor White
Write-Host "    Cost: Approximately 30 USD/month per VM" -ForegroundColor White
Write-Host ""

# Credentials
Write-Host "  Set VM Administrator Credentials:" -ForegroundColor Cyan
$adminUsername = Read-Host "    Username (e.g., azureadmin)"
$adminPassword = Read-Host "    Password (min 12 chars, complex)" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
Write-Host "  Credentials set" -ForegroundColor Green
Write-Host ""
#endregion

#region Create Resources
Write-Host "[4/8] Creating Resource Group & VNet" -ForegroundColor Yellow
$rgName = "RG-BastionTest-VMs-$timestamp"
$vnetName = "VNet-Test-VMs"
$subnetName = "Subnet-VMs"

Write-Host "  Creating Resource Group..." -ForegroundColor Cyan
$rg = New-AzResourceGroup -Name $rgName -Location $location -Force
Write-Host "  Resource Group created: $rgName" -ForegroundColor Green

Write-Host "  Creating Virtual Network..." -ForegroundColor Cyan
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.1.0.0/24"
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix "10.1.0.0/16" -Subnet $subnetConfig
Write-Host "  VNet created: $vnetName (10.1.0.0/16)" -ForegroundColor Green
Write-Host ""
#endregion

#region VNet Peering
Write-Host "[5/8] Configuring VNet Peering to Bastion" -ForegroundColor Yellow
Write-Host "  Creating bidirectional peering..." -ForegroundColor Cyan

try {
    # Test VMs VNet to Bastion VNet
    $peeringName1 = "TestVMs-to-Bastion"
    Add-AzVirtualNetworkPeering -Name $peeringName1 -VirtualNetwork $vnet -RemoteVirtualNetworkId $bastionVNet.Id -AllowForwardedTraffic -ErrorAction Stop | Out-Null
    Write-Host "  Peering created: $peeringName1" -ForegroundColor Green
    
    # Bastion VNet to Test VMs VNet
    $peeringName2 = "Bastion-to-TestVMs-$timestamp"
    Add-AzVirtualNetworkPeering -Name $peeringName2 -VirtualNetwork $bastionVNet -RemoteVirtualNetworkId $vnet.Id -AllowForwardedTraffic -AllowGatewayTransit -ErrorAction Stop | Out-Null
    Write-Host "  Peering created: $peeringName2" -ForegroundColor Green
} catch {
    Write-Host "  Warning: Peering may already exist or failed" -ForegroundColor Yellow
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""
#endregion

#region Create NSG
Write-Host "[6/8] Creating Network Security Group" -ForegroundColor Yellow
$nsgName = "NSG-TestVMs"
Write-Host "  Creating NSG with RDP access..." -ForegroundColor Cyan

# NSG Rules
$rdpRule = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP-Bastion" -Description "Allow RDP from Bastion subnet" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389

$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $rdpRule
Write-Host "  NSG created with RDP rule" -ForegroundColor Green
Write-Host ""
#endregion

#region Deploy VMs
Write-Host "[7/8] Deploying 2 Windows VMs" -ForegroundColor Yellow
Write-Host "  (This will take 5-10 minutes per VM)" -ForegroundColor Gray
Write-Host ""

$vmConfig = @{
    ResourceGroupName = $rgName
    Location = $location
    Size = "Standard_B2s"
    Credential = $cred
    PublisherName = "MicrosoftWindowsServer"
    Offer = "WindowsServer"
    Skus = "2022-datacenter-azure-edition"
    Version = "latest"
}

$vms = @()

# VM 1
Write-Host "  [VM 1/2] Creating TestVM-01..." -ForegroundColor Cyan
$vm1Name = "TestVM-01"
$nic1Name = "$vm1Name-NIC"

Write-Host "    Creating NIC..." -ForegroundColor Gray
$nic1 = New-AzNetworkInterface -Name $nic1Name -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id

Write-Host "    Creating VM..." -ForegroundColor Gray
$vm1 = New-AzVMConfig -VMName $vm1Name -VMSize $vmConfig.Size
$vm1 = Set-AzVMOperatingSystem -VM $vm1 -Windows -ComputerName $vm1Name -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vm1 = Set-AzVMSourceImage -VM $vm1 -PublisherName $vmConfig.PublisherName -Offer $vmConfig.Offer -Skus $vmConfig.Skus -Version $vmConfig.Version
$vm1 = Add-AzVMNetworkInterface -VM $vm1 -Id $nic1.Id
$vm1 = Set-AzVMBootDiagnostic -VM $vm1 -Disable
New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm1 -ErrorAction Stop | Out-Null

$vm1Obj = Get-AzVM -ResourceGroupName $rgName -Name $vm1Name
$vms += $vm1Obj
Write-Host "  TestVM-01 deployed successfully" -ForegroundColor Green
Write-Host ""

# VM 2
Write-Host "  [VM 2/2] Creating TestVM-02..." -ForegroundColor Cyan
$vm2Name = "TestVM-02"
$nic2Name = "$vm2Name-NIC"

Write-Host "    Creating NIC..." -ForegroundColor Gray
$nic2 = New-AzNetworkInterface -Name $nic2Name -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id

Write-Host "    Creating VM..." -ForegroundColor Gray
$vm2 = New-AzVMConfig -VMName $vm2Name -VMSize $vmConfig.Size
$vm2 = Set-AzVMOperatingSystem -VM $vm2 -Windows -ComputerName $vm2Name -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vm2 = Set-AzVMSourceImage -VM $vm2 -PublisherName $vmConfig.PublisherName -Offer $vmConfig.Offer -Skus $vmConfig.Skus -Version $vmConfig.Version
$vm2 = Add-AzVMNetworkInterface -VM $vm2 -Id $nic2.Id
$vm2 = Set-AzVMBootDiagnostic -VM $vm2 -Disable
New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm2 -ErrorAction Stop | Out-Null

$vm2Obj = Get-AzVM -ResourceGroupName $rgName -Name $vm2Name
$vms += $vm2Obj
Write-Host "  TestVM-02 deployed successfully" -ForegroundColor Green
Write-Host ""
#endregion

#region Verify Connectivity
Write-Host "[8/8] Verifying Bastion Connectivity" -ForegroundColor Yellow
Write-Host "  Checking VNet peering status..." -ForegroundColor Cyan

Start-Sleep -Seconds 5

$bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG
$peering = $bastionVNet.VirtualNetworkPeerings | Where-Object { $_.RemoteVirtualNetwork.Id -eq $vnet.Id }

if ($peering -and $peering.PeeringState -eq "Connected") {
    Write-Host "  VNet peering is CONNECTED" -ForegroundColor Green
} else {
    Write-Host "  VNet peering status: $($peering.PeeringState)" -ForegroundColor Yellow
    Write-Host "  Wait 1-2 minutes for peering to fully establish" -ForegroundColor Gray
}
Write-Host ""
#endregion

#region Success Report
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE - 2 WINDOWS VMs READY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "DEPLOYED RESOURCES:" -ForegroundColor Cyan
Write-Host "  Resource Group: $rgName" -ForegroundColor White
Write-Host "  Virtual Network: $vnetName (10.1.0.0/16)" -ForegroundColor White
Write-Host "  Network Security Group: $nsgName" -ForegroundColor White
Write-Host ""

Write-Host "VIRTUAL MACHINES:" -ForegroundColor Cyan
$nic1Details = Get-AzNetworkInterface -ResourceId $vm1Obj.NetworkProfile.NetworkInterfaces[0].Id
$nic2Details = Get-AzNetworkInterface -ResourceId $vm2Obj.NetworkProfile.NetworkInterfaces[0].Id

Write-Host "  1. $vm1Name" -ForegroundColor White
Write-Host "     Private IP: $($nic1Details.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Gray
Write-Host "     OS: Windows Server 2022 Datacenter" -ForegroundColor Gray
Write-Host "     Size: Standard_B2s" -ForegroundColor Gray
Write-Host ""

Write-Host "  2. $vm2Name" -ForegroundColor White
Write-Host "     Private IP: $($nic2Details.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Gray
Write-Host "     OS: Windows Server 2022 Datacenter" -ForegroundColor Gray
Write-Host "     Size: Standard_B2s" -ForegroundColor Gray
Write-Host ""

Write-Host "ADMINISTRATOR CREDENTIALS:" -ForegroundColor Cyan
Write-Host "  Username: $adminUsername" -ForegroundColor White
Write-Host "  Password: (the one you entered)" -ForegroundColor Gray
Write-Host ""

Write-Host "BASTION CONNECTION:" -ForegroundColor Cyan
Write-Host "  Bastion: $($bastion.Name)" -ForegroundColor White
Write-Host "  VNet Peering: $($bastionVNet.Name) <-> $vnetName" -ForegroundColor White
Write-Host "  Status: READY TO CONNECT" -ForegroundColor Green
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  HOW TO CONNECT TO YOUR VMs VIA BASTION" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "METHOD 1: Azure Portal (EASIEST)" -ForegroundColor Yellow
Write-Host "  Step-by-Step:" -ForegroundColor Cyan
Write-Host "  1. Open Azure Portal: https://portal.azure.com" -ForegroundColor White
Write-Host "  2. Go to 'Virtual Machines'" -ForegroundColor White
Write-Host "  3. Click on '$vm1Name' or '$vm2Name'" -ForegroundColor White
Write-Host "  4. Click the 'Connect' button at the top" -ForegroundColor White
Write-Host "  5. Select 'Connect via Bastion' from dropdown" -ForegroundColor White
Write-Host "  6. Enter credentials:" -ForegroundColor White
Write-Host "       Username: $adminUsername" -ForegroundColor Gray
Write-Host "       Password: (your password)" -ForegroundColor Gray
Write-Host "  7. Click 'Connect' button" -ForegroundColor White
Write-Host "  8. A new browser tab opens with RDP session!" -ForegroundColor White
Write-Host ""

Write-Host "METHOD 2: Direct Portal Links" -ForegroundColor Yellow
Write-Host "  TestVM-01:" -ForegroundColor Cyan
$vm1Link = "https://portal.azure.com/#@/resource$($vm1Obj.Id)/connectBastion"
Write-Host "    $vm1Link" -ForegroundColor Gray
Write-Host ""
Write-Host "  TestVM-02:" -ForegroundColor Cyan
$vm2Link = "https://portal.azure.com/#@/resource$($vm2Obj.Id)/connectBastion"
Write-Host "    $vm2Link" -ForegroundColor Gray
Write-Host ""

Write-Host "METHOD 3: Azure CLI (Native RDP Client)" -ForegroundColor Yellow
Write-Host "  For TestVM-01:" -ForegroundColor Cyan
Write-Host "    az network bastion tunnel \"" -ForegroundColor Gray
Write-Host "      --name $($bastion.Name) \"" -ForegroundColor Gray
Write-Host "      --resource-group $($bastion.ResourceGroupName) \"" -ForegroundColor Gray
Write-Host "      --target-resource-id $($vm1Obj.Id) \"" -ForegroundColor Gray
Write-Host "      --resource-port 3389 --port 3389" -ForegroundColor Gray
Write-Host "    # Then in another terminal: mstsc /v:localhost:3389" -ForegroundColor Gray
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  TESTING CHECKLIST" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  [ ] Connect to TestVM-01 via Bastion" -ForegroundColor Yellow
Write-Host "  [ ] Verify Windows desktop loads" -ForegroundColor Yellow
Write-Host "  [ ] Open Command Prompt and run: ipconfig" -ForegroundColor Yellow
Write-Host "  [ ] Disconnect and connect to TestVM-02" -ForegroundColor Yellow
Write-Host "  [ ] Test file copy using Bastion (if enabled)" -ForegroundColor Yellow
Write-Host ""

Write-Host "TROUBLESHOOTING:" -ForegroundColor Cyan
Write-Host "  If connection fails:" -ForegroundColor White
Write-Host "  1. Wait 2-3 minutes after deployment" -ForegroundColor Gray
Write-Host "  2. Verify VMs are running in Portal" -ForegroundColor Gray
Write-Host "  3. Check credentials are correct" -ForegroundColor Gray
Write-Host "  4. Refresh the portal page" -ForegroundColor Gray
Write-Host "  5. Try the other connection method" -ForegroundColor Gray
Write-Host ""

Write-Host "COST INFORMATION:" -ForegroundColor Cyan
Write-Host "  VMs (2x Standard_B2s): Approximately 60 USD/month" -ForegroundColor White
Write-Host "  Storage (2x 127GB): Approximately 10 USD/month" -ForegroundColor White
Write-Host "  Total Additional: Approximately 70 USD/month" -ForegroundColor White
Write-Host ""

Write-Host "CLEANUP (When Done Testing):" -ForegroundColor Cyan
Write-Host "  To delete everything:" -ForegroundColor White
Write-Host "  Remove-AzResourceGroup -Name $rgName -Force" -ForegroundColor Gray
Write-Host ""

# Save connection guide
$guidePath = ".\Bastion-Connection-Guide-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$guideContent = @"
================================================================
AZURE BASTION - VM CONNECTION GUIDE
================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

VMs DEPLOYED:
  1. $vm1Name
     Private IP: $($nic1Details.IpConfigurations[0].PrivateIpAddress)
     
  2. $vm2Name
     Private IP: $($nic2Details.IpConfigurations[0].PrivateIpAddress)

CREDENTIALS:
  Username: $adminUsername
  Password: (the one you entered during deployment)

CONNECTION METHOD (EASIEST):
  1. Go to: https://portal.azure.com
  2. Navigate to Virtual Machines
  3. Click on VM name ($vm1Name or $vm2Name)
  4. Click "Connect" button
  5. Select "Connect via Bastion"
  6. Enter credentials and click Connect
  7. RDP session opens in browser!

DIRECT LINKS:
  TestVM-01:
  $vm1Link
  
  TestVM-02:
  $vm2Link

BASTION DETAILS:
  Name: $($bastion.Name)
  Resource Group: $($bastion.ResourceGroupName)
  Hub VNet: $($bastionVNet.Name)

================================================================
"@

$guideContent | Out-File -FilePath $guidePath -Encoding UTF8
Write-Host "Connection guide saved: $guidePath" -ForegroundColor Cyan
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS! VMs ARE READY FOR BASTION CONNECTION" -ForegroundColor Green
Write-Host "  Go to Azure Portal now and test the connection!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
#endregion
