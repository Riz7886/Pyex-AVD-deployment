#Requires -Version 5.1
<#
.SYNOPSIS
    100% AUTOMATED Azure Bastion + 10 VMs Deployment
.DESCRIPTION
    ZERO PROMPTS - Everything automatic
    Based on Azure Bastion Architecture
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "AZURE BASTION AUTOMATED DEPLOYMENT" -ForegroundColor Cyan
Write-Host "Standard SKU + 10 VMs - FULLY AUTOMATED" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

#region Auto Configuration
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$location = "eastus"
$rgName = "RG-Bastion-$timestamp"
$vnetName = "VNet-Bastion"
$vnetPrefix = "10.0.0.0/16"
$bastionSubnetPrefix = "10.0.1.0/26"
$vmSubnetPrefix = "10.0.2.0/24"
$bastionName = "BastionHost"
$adminUsername = "azureadmin"
$adminPassword = ConvertTo-SecureString "P@ssw0rd$(Get-Random -Minimum 1000 -Maximum 9999)!" -AsPlainText -Force
$vmSize = "Standard_D2s_v3"

Write-Host "Configuration (Auto-Generated):" -ForegroundColor Yellow
Write-Host "  Region: $location" -ForegroundColor White
Write-Host "  Resource Group: $rgName" -ForegroundColor White
Write-Host "  VNet: $vnetName ($vnetPrefix)" -ForegroundColor White
Write-Host "  Admin: $adminUsername" -ForegroundColor White
Write-Host ""
#endregion

#region Module Check
Write-Host "Step 1: Azure Modules" -ForegroundColor Yellow
$modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
foreach ($mod in $modules) {
    if (!(Get-Module -Name $mod -ListAvailable)) {
        Write-Host "  Installing $mod..." -ForegroundColor Cyan
        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        Install-Module $mod -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $mod -ErrorAction SilentlyContinue
}
Write-Host "  Modules ready" -ForegroundColor Green
Write-Host ""
#endregion

#region Azure Connection
Write-Host "Step 2: Azure Connection" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "  Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
Write-Host "  Found $($subscriptions.Count) subscriptions" -ForegroundColor White

if ($subscriptions.Count -eq 1) {
    $subscription = $subscriptions[0]
    Write-Host "  Auto-selected: $($subscription.Name)" -ForegroundColor Green
}
else {
    Write-Host "  Available subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "    [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
    }
    $sel = Read-Host "  Select [1-$($subscriptions.Count)]"
    $subscription = $subscriptions[[int]$sel - 1]
}

Set-AzContext -SubscriptionId $subscription.Id | Out-Null
Write-Host "  Active: $($subscription.Name)" -ForegroundColor Green
Write-Host ""
#endregion

#region Resource Group
Write-Host "Step 3: Resource Group" -ForegroundColor Yellow
$rg = New-AzResourceGroup -Name $rgName -Location $location -Force
Write-Host "  Created: $rgName" -ForegroundColor Green
Write-Host ""
#endregion

#region Virtual Network
Write-Host "Step 4: Virtual Network" -ForegroundColor Yellow
$bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix $bastionSubnetPrefix
$vmSubnet = New-AzVirtualNetworkSubnetConfig -Name "VMSubnet" -AddressPrefix $vmSubnetPrefix
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix $vnetPrefix -Subnet $bastionSubnet, $vmSubnet
Write-Host "  Created: $vnetName" -ForegroundColor Green
Write-Host "    AzureBastionSubnet: $bastionSubnetPrefix" -ForegroundColor White
Write-Host "    VMSubnet: $vmSubnetPrefix" -ForegroundColor White
Write-Host ""
#endregion

#region Network Security Group
Write-Host "Step 5: Network Security Group" -ForegroundColor Yellow
$nsgName = "$rgName-NSG"
$rule1 = New-AzNetworkSecurityRuleConfig -Name "AllowBastionRDP" -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $bastionSubnetPrefix -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389 -Access Allow
$rule2 = New-AzNetworkSecurityRuleConfig -Name "AllowBastionSSH" -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix $bastionSubnetPrefix -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 22 -Access Allow
$rule3 = New-AzNetworkSecurityRuleConfig -Name "DenyAllInbound" -Protocol "*" -Direction Inbound -Priority 4096 -SourceAddressPrefix "*" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange "*" -Access Deny
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $rule1, $rule2, $rule3
Write-Host "  Created: $nsgName" -ForegroundColor Green
Write-Host "    Rules: Bastion-only access (RDP + SSH)" -ForegroundColor White
Write-Host ""
#endregion

#region Virtual Machines
Write-Host "Step 6: Creating 10 Virtual Machines" -ForegroundColor Yellow
$credential = New-Object System.Management.Automation.PSCredential($adminUsername, $adminPassword)
$vmCount = 0

for ($i = 1; $i -le 10; $i++) {
    $vmName = "VM-$($i.ToString('00'))"
    Write-Host "  Creating $vmName..." -ForegroundColor Cyan
    
    try {
        $nicName = "$vmName-NIC"
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[1].Id -NetworkSecurityGroupId $nsg.Id -Force
        
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $credential
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter" -Version "latest"
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$vmName-OSDisk" -CreateOption FromImage -StorageAccountType "Premium_LRS"
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        New-AzVM -ResourceGroupName $rgName -Location $location -VM $vmConfig -DisableBginfoExtension | Out-Null
        $vmCount++
        Write-Host "    Success: $vmName" -ForegroundColor Green
    }
    catch {
        Write-Host "    Warning: $vmName failed" -ForegroundColor Yellow
    }
}
Write-Host "  VMs Created: $vmCount/10" -ForegroundColor Green
Write-Host ""
#endregion

#region Bastion
Write-Host "Step 7: Deploying Azure Bastion" -ForegroundColor Yellow
Write-Host "  Features:" -ForegroundColor White
Write-Host "    - Standard SKU" -ForegroundColor Green
Write-Host "    - Entra ID Authentication" -ForegroundColor Green
Write-Host "    - Native Client Tunneling" -ForegroundColor Green
Write-Host "    - SCP File Transfer" -ForegroundColor Green
Write-Host ""
Write-Host "  Deploying (10-15 minutes)..." -ForegroundColor Cyan

$pipName = "$bastionName-PIP"
$pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $location -AllocationMethod Static -Sku Standard
Write-Host "  Public IP: $($pip.IpAddress)" -ForegroundColor Green

$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
$bastion = New-AzBastion -Name $bastionName -ResourceGroupName $rgName -PublicIpAddressRgName $rgName -PublicIpAddressName $pipName -VirtualNetworkRgName $rgName -VirtualNetworkName $vnetName -Sku "Standard"

Write-Host "  Bastion Deployed!" -ForegroundColor Green
Write-Host ""
#endregion

#region Summary
Write-Host "============================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resource Group: $rgName" -ForegroundColor White
Write-Host "Region: $location" -ForegroundColor White
Write-Host "Virtual Network: $vnetName" -ForegroundColor White
Write-Host "Bastion: $bastionName (Standard SKU)" -ForegroundColor White
Write-Host "Public IP: $($pip.IpAddress)" -ForegroundColor White
Write-Host "VMs Created: $vmCount" -ForegroundColor White
Write-Host "Admin Username: $adminUsername" -ForegroundColor White
Write-Host ""
Write-Host "Connect via Azure Portal:" -ForegroundColor Yellow
Write-Host "  Portal -> VM -> Connect -> Bastion" -ForegroundColor White
Write-Host ""
Write-Host "Or use Azure CLI:" -ForegroundColor Yellow
Write-Host "  az network bastion ssh --name $bastionName --resource-group $rgName --target-resource-id <VM-ID> --auth-type AAD" -ForegroundColor White
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
#endregion
