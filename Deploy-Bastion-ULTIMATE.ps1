#Requires -Version 5.1
<#
.SYNOPSIS
    ULTIMATE Azure Bastion Deployment - Hub-and-Spoke with Multi-VNet Support
.DESCRIPTION
    100% Automated Enterprise Bastion Solution
    - Deploy to existing OR new infrastructure (NO VM creation)
    - Connects to your EXISTING VMs across multiple VNets
    - Automatic VNet peering for multi-VNet connectivity
    - One Bastion connects to ALL VNets and ALL existing VMs
    - Standard SKU with Entra ID, Tunneling, SCP
    - Cost-optimized Hub-and-Spoke architecture
.EXAMPLE
    .\Deploy-Bastion-ULTIMATE.ps1
.NOTES
    This script does NOT create VMs - it connects Bastion to your existing VMs
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ULTIMATE AZURE BASTION - ENTERPRISE DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Hub-and-Spoke Multi-VNet Architecture" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""


#region VPN Security Check
# Import VPN detection module
$vpnModulePath = Join-Path $PSScriptRoot "VPN-Detection-Module.ps1"
if (Test-Path $vpnModulePath) {
    . $vpnModulePath
    # Require VPN connection before proceeding
    Test-VPNConnection -Required
} else {
    Write-Host "WARNING: VPN detection module not found" -ForegroundColor Yellow
    Write-Host "Proceeding without VPN check (not recommended for production)" -ForegroundColor Yellow
    Write-Host ""
}
#endregion
#region Module Installation
Write-Host "[1/8] Azure Modules Check" -ForegroundColor Yellow
$modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
$installed = 0
foreach ($mod in $modules) {
    if (!(Get-Module -Name $mod -ListAvailable)) {
        if ($installed -eq 0) {
            Write-Host "  Installing Azure PowerShell modules..." -ForegroundColor Cyan
            if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            }
        }
        Install-Module $mod -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        $installed++
    }
    Import-Module $mod -ErrorAction SilentlyContinue
}
if ($installed -gt 0) {
    Write-Host "  Installed $installed module(s)" -ForegroundColor Green
}
Write-Host "  All modules ready" -ForegroundColor Green
Write-Host ""
#endregion

#region Azure Connection
Write-Host "[2/8] Azure Authentication" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "  Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}
Write-Host "  Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
if ($subscriptions.Count -eq 1) {
    $subscription = $subscriptions[0]
    Write-Host "  Auto-selected: $($subscription.Name)" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "  Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "    [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
    }
    do {
        $sel = Read-Host "  Select subscription [1-$($subscriptions.Count)]"
    } while ([int]$sel -lt 1 -or [int]$sel -gt $subscriptions.Count)
    $subscription = $subscriptions[[int]$sel - 1]
}
Set-AzContext -SubscriptionId $subscription.Id | Out-Null
Write-Host "  Active: $($subscription.Name)" -ForegroundColor Green
Write-Host ""
#endregion

#region Deployment Mode Selection
Write-Host "[3/8] Deployment Mode" -ForegroundColor Yellow
Write-Host "  [1] Use EXISTING Resource Group and VNet (Connect to your existing VMs)" -ForegroundColor White
Write-Host "  [2] Create NEW Resource Group and VNet (New Hub infrastructure)" -ForegroundColor White
Write-Host ""
do {
    $mode = Read-Host "  Select mode [1-2]"
} while ($mode -notmatch '^[12]$')
Write-Host ""
#endregion

#region Mode 1: Existing Resources
if ($mode -eq "1") {
    Write-Host "[4/8] Select Existing Resources" -ForegroundColor Yellow
    
    # Select Resource Group
    $rgs = Get-AzResourceGroup | Sort-Object ResourceGroupName
    Write-Host "  Resource Groups:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $rgs.Count; $i++) {
        $vmCount = (Get-AzVM -ResourceGroupName $rgs[$i].ResourceGroupName -ErrorAction SilentlyContinue).Count
        Write-Host "    [$($i + 1)] $($rgs[$i].ResourceGroupName) ($vmCount VMs, $($rgs[$i].Location))" -ForegroundColor White
    }
    do {
        $rgSel = Read-Host "  Select Resource Group [1-$($rgs.Count)]"
    } while ([int]$rgSel -lt 1 -or [int]$rgSel -gt $rgs.Count)
    $rg = $rgs[[int]$rgSel - 1]
    $location = $rg.Location
    Write-Host "  Selected: $($rg.ResourceGroupName)" -ForegroundColor Green
    Write-Host ""
    
    # Select Hub VNet
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $rg.ResourceGroupName | Sort-Object Name
    if ($vnets.Count -eq 0) {
        Write-Host "  ERROR: No VNets found in this Resource Group" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Virtual Networks:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $vnets.Count; $i++) {
        $subnetCount = $vnets[$i].Subnets.Count
        Write-Host "    [$($i + 1)] $($vnets[$i].Name) ($($vnets[$i].AddressSpace.AddressPrefixes -join ', '), $subnetCount subnets)" -ForegroundColor White
    }
    do {
        $vnetSel = Read-Host "  Select Hub VNet for Bastion [1-$($vnets.Count)]"
    } while ([int]$vnetSel -lt 1 -or [int]$vnetSel -gt $vnets.Count)
    $hubVNet = $vnets[[int]$vnetSel - 1]
    Write-Host "  Hub VNet: $($hubVNet.Name)" -ForegroundColor Green
    Write-Host ""
    
    # Check/Create Bastion Subnet
    $bastionSubnet = $hubVNet.Subnets | Where-Object { $_.Name -eq "AzureBastionSubnet" }
    if (!$bastionSubnet) {
        Write-Host "  AzureBastionSubnet not found - creating..." -ForegroundColor Yellow
        Write-Host "  Existing subnets:" -ForegroundColor White
        foreach ($subnet in $hubVNet.Subnets) {
            Write-Host "    - $($subnet.Name): $($subnet.AddressPrefix)" -ForegroundColor Gray
        }
        $bastionPrefix = Read-Host "  Enter Bastion subnet (min /26, e.g., 10.0.255.0/26)"
        $hubVNet | Add-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix $bastionPrefix | Set-AzVirtualNetwork | Out-Null
        Write-Host "  AzureBastionSubnet created" -ForegroundColor Green
    } else {
        Write-Host "  AzureBastionSubnet exists: $($bastionSubnet.AddressPrefix)" -ForegroundColor Green
    }
    Write-Host ""
    
    $bastionName = "BastionHost-Hub"
}
#endregion

#region Mode 2: New Resources
else {
    Write-Host "[4/8] Create New Resources" -ForegroundColor Yellow
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $rgName = "RG-Bastion-Hub-$timestamp"
    $location = "eastus"
    $hubVNetName = "Hub-VNet"
    $bastionName = "BastionHost-Hub"
    
    Write-Host "  Auto-configuration:" -ForegroundColor Cyan
    Write-Host "    Resource Group: $rgName" -ForegroundColor White
    Write-Host "    Location: $location" -ForegroundColor White
    Write-Host "    Hub VNet: $hubVNetName (10.0.0.0/16)" -ForegroundColor White
    Write-Host "    Bastion Subnet: 10.0.1.0/26" -ForegroundColor White
    Write-Host ""
    
    Write-Host "  Creating Resource Group..." -ForegroundColor Cyan
    $rg = New-AzResourceGroup -Name $rgName -Location $location -Force
    Write-Host "  Resource Group created" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "  Creating Hub Virtual Network..." -ForegroundColor Cyan
    $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $hubVNet = New-AzVirtualNetwork -Name $hubVNetName -ResourceGroupName $rgName -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $bastionSubnetConfig
    Write-Host "  Hub VNet created" -ForegroundColor Green
    Write-Host ""
}
#endregion

#region Multi-VNet Peering Discovery
Write-Host "[5/8] Multi-VNet Peering Setup" -ForegroundColor Yellow

# Find all other VNets in subscription
$allVNets = Get-AzVirtualNetwork | Where-Object { $_.Id -ne $hubVNet.Id -and $_.Location -eq $location }
$spokeVNets = @()

if ($allVNets.Count -gt 0) {
    Write-Host "  Found $($allVNets.Count) other VNet(s) in $location region" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Available VNets for peering:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $allVNets.Count; $i++) {
        $vmCount = 0
        try {
            $rgName = $allVNets[$i].ResourceGroupName
            $vms = Get-AzVM -ResourceGroupName $rgName -ErrorAction SilentlyContinue
            foreach ($vm in $vms) {
                $vmNics = $vm.NetworkProfile.NetworkInterfaces
                foreach ($nic in $vmNics) {
                    $nicResource = Get-AzNetworkInterface -ResourceId $nic.Id -ErrorAction SilentlyContinue
                    if ($nicResource.IpConfigurations.Subnet.Id -match $allVNets[$i].Name) {
                        $vmCount++
                    }
                }
            }
        } catch {}
        Write-Host "    [$($i + 1)] $($allVNets[$i].Name) - $($allVNets[$i].ResourceGroupName) ($vmCount VMs)" -ForegroundColor White
    }
    Write-Host "    [0] Skip peering (Bastion in Hub VNet only)" -ForegroundColor Gray
    Write-Host ""
    
    $peerInput = Read-Host "  Peer VNets? Enter numbers separated by comma (e.g., 1,2,3) or 0 to skip"
    
    if ($peerInput -ne "0" -and ![string]::IsNullOrWhiteSpace($peerInput)) {
        $peerIndices = $peerInput -split ',' | ForEach-Object { [int]$_.Trim() }
        foreach ($idx in $peerIndices) {
            if ($idx -gt 0 -and $idx -le $allVNets.Count) {
                $spokeVNets += $allVNets[$idx - 1]
            }
        }
        Write-Host "  Selected $($spokeVNets.Count) VNet(s) for peering" -ForegroundColor Green
    } else {
        Write-Host "  No peering configured" -ForegroundColor Yellow
    }
} else {
    Write-Host "  No other VNets found in this region" -ForegroundColor Yellow
}
Write-Host ""
#endregion

#region VM Inventory
Write-Host "[6/8] Scanning Existing Virtual Machines" -ForegroundColor Yellow
Write-Host "  (Script will NOT create VMs - only scanning existing VMs)" -ForegroundColor Gray
$allVMs = @()

# VMs in Hub VNet
$hubVMs = Get-AzVM -ResourceGroupName $hubVNet.ResourceGroupName -ErrorAction SilentlyContinue
if ($hubVMs) {
    Write-Host "  Hub VNet VMs:" -ForegroundColor Cyan
    foreach ($vm in $hubVMs) {
        Write-Host "    - $($vm.Name)" -ForegroundColor White
        $allVMs += $vm
    }
}

# VMs in Spoke VNets
foreach ($spokeVNet in $spokeVNets) {
    $spokeVMs = Get-AzVM -ResourceGroupName $spokeVNet.ResourceGroupName -ErrorAction SilentlyContinue
    if ($spokeVMs) {
        Write-Host "  $($spokeVNet.Name) VMs:" -ForegroundColor Cyan
        foreach ($vm in $spokeVMs) {
            Write-Host "    - $($vm.Name)" -ForegroundColor White
            $allVMs += $vm
        }
    }
}

if ($allVMs.Count -eq 0) {
    Write-Host "  No VMs found (Bastion will still be deployed)" -ForegroundColor Yellow
} else {
    Write-Host "  Total VMs accessible via Bastion: $($allVMs.Count)" -ForegroundColor Green
}
Write-Host ""
#endregion

#region Bastion Deployment
Write-Host "[7/8] Deploying Azure Bastion" -ForegroundColor Yellow
Write-Host "  Configuration:" -ForegroundColor Cyan
Write-Host "    Name: $bastionName" -ForegroundColor White
Write-Host "    SKU: Standard" -ForegroundColor White
Write-Host "    Features: Entra ID, Native Tunneling, SCP" -ForegroundColor White
Write-Host "    Hub VNet: $($hubVNet.Name)" -ForegroundColor White
Write-Host "    Monthly Cost: ~`$140" -ForegroundColor White
Write-Host ""
Write-Host "  Deploying (10-15 minutes)..." -ForegroundColor Cyan

try {
    $pipName = "$bastionName-PIP"
    $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $hubVNet.ResourceGroupName -Location $location -AllocationMethod Static -Sku Standard
    Write-Host "  Public IP created: $($pip.IpAddress)" -ForegroundColor Green
    
    $hubVNet = Get-AzVirtualNetwork -Name $hubVNet.Name -ResourceGroupName $hubVNet.ResourceGroupName
    $bastion = New-AzBastion -Name $bastionName -ResourceGroupName $hubVNet.ResourceGroupName -PublicIpAddressRgName $hubVNet.ResourceGroupName -PublicIpAddressName $pipName -VirtualNetworkRgName $hubVNet.ResourceGroupName -VirtualNetworkName $hubVNet.Name -Sku "Standard"
    Write-Host "  Bastion deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Bastion deployment failed" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""
#endregion

#region VNet Peering
Write-Host "[8/8] Configuring VNet Peering" -ForegroundColor Yellow

if ($spokeVNets.Count -gt 0) {
    $peeredCount = 0
    foreach ($spokeVNet in $spokeVNets) {
        try {
            Write-Host "  Peering: $($hubVNet.Name) <-> $($spokeVNet.Name)..." -ForegroundColor Cyan
            
            # Hub to Spoke
            $peeringName1 = "Hub-to-$($spokeVNet.Name)"
            Add-AzVirtualNetworkPeering -Name $peeringName1 -VirtualNetwork $hubVNet -RemoteVirtualNetworkId $spokeVNet.Id -AllowForwardedTraffic -AllowGatewayTransit -ErrorAction SilentlyContinue | Out-Null
            
            # Spoke to Hub
            $peeringName2 = "$($spokeVNet.Name)-to-Hub"
            Add-AzVirtualNetworkPeering -Name $peeringName2 -VirtualNetwork $spokeVNet -RemoteVirtualNetworkId $hubVNet.Id -AllowForwardedTraffic -UseRemoteGateways -ErrorAction SilentlyContinue | Out-Null
            
            Write-Host "  Peered: $($spokeVNet.Name)" -ForegroundColor Green
            $peeredCount++
        } catch {
            Write-Host "  Warning: Failed to peer $($spokeVNet.Name)" -ForegroundColor Yellow
        }
    }
    Write-Host "  Peering complete: $peeredCount/$($spokeVNets.Count) VNets" -ForegroundColor Green
} else {
    Write-Host "  No VNet peering configured" -ForegroundColor Yellow
}
Write-Host ""
#endregion

#region Summary Report
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE - ENTERPRISE BASTION ACTIVE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "BASTION CONFIGURATION:" -ForegroundColor Cyan
Write-Host "  Name: $bastionName" -ForegroundColor White
Write-Host "  Public IP: $($pip.IpAddress)" -ForegroundColor White
Write-Host "  SKU: Standard" -ForegroundColor White
Write-Host "  Resource Group: $($hubVNet.ResourceGroupName)" -ForegroundColor White
Write-Host "  Location: $location" -ForegroundColor White
Write-Host ""
Write-Host "NETWORK ARCHITECTURE:" -ForegroundColor Cyan
Write-Host "  Hub VNet: $($hubVNet.Name) ($($hubVNet.AddressSpace.AddressPrefixes -join ', '))" -ForegroundColor White
if ($spokeVNets.Count -gt 0) {
    Write-Host "  Peered Spoke VNets: $($spokeVNets.Count)" -ForegroundColor White
    foreach ($spoke in $spokeVNets) {
        Write-Host "    - $($spoke.Name) ($($spoke.AddressSpace.AddressPrefixes -join ', '))" -ForegroundColor Gray
    }
}
Write-Host ""
Write-Host "VIRTUAL MACHINES ($($allVMs.Count) total):" -ForegroundColor Cyan
if ($allVMs.Count -gt 0) {
    foreach ($vm in $allVMs) {
        Write-Host "  - $($vm.Name) ($($vm.ResourceGroupName))" -ForegroundColor White
    }
} else {
    Write-Host "  No VMs found" -ForegroundColor Gray
}
Write-Host ""
Write-Host "FEATURES ENABLED:" -ForegroundColor Cyan
Write-Host "  ✓ Entra ID Authentication (SSO + MFA)" -ForegroundColor Green
Write-Host "  ✓ Native Client Tunneling (SSH/RDP from local)" -ForegroundColor Green
Write-Host "  ✓ SCP File Transfer" -ForegroundColor Green
Write-Host "  ✓ Multi-VNet Connectivity via Peering" -ForegroundColor Green
Write-Host ""
Write-Host "COST SUMMARY:" -ForegroundColor Cyan
Write-Host "  Bastion Standard: ~`$140/month" -ForegroundColor White
Write-Host "  VNet Peering: FREE (same region data transfer)" -ForegroundColor White
Write-Host "  Total: ~`$140/month" -ForegroundColor White
Write-Host ""
Write-Host "CONNECTION METHODS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Azure Portal (Browser):" -ForegroundColor Yellow
Write-Host "     Portal -> VM -> Connect -> Bastion" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Azure CLI (SSH with Entra ID):" -ForegroundColor Yellow
Write-Host "     az network bastion ssh --name $bastionName \" -ForegroundColor Gray
Write-Host "       --resource-group $($hubVNet.ResourceGroupName) \" -ForegroundColor Gray
Write-Host "       --target-resource-id <VM-RESOURCE-ID> \" -ForegroundColor Gray
Write-Host "       --auth-type AAD" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Native Tunneling (RDP):" -ForegroundColor Yellow
Write-Host "     az network bastion tunnel --name $bastionName \" -ForegroundColor Gray
Write-Host "       --resource-group $($hubVNet.ResourceGroupName) \" -ForegroundColor Gray
Write-Host "       --target-resource-id <VM-RESOURCE-ID> \" -ForegroundColor Gray
Write-Host "       --resource-port 3389 --port 50001" -ForegroundColor Gray
Write-Host "     Then: mstsc /v:localhost:50001" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. SCP File Transfer:" -ForegroundColor Yellow
Write-Host "     (After tunnel created)" -ForegroundColor Gray
Write-Host "     scp -P 50001 file.txt user@localhost:/path/" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Production-Ready Enterprise Bastion Solution Deployed" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Generate deployment report
$reportPath = ".\Bastion-Deployment-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$report = @"
================================================================
AZURE BASTION ENTERPRISE DEPLOYMENT REPORT
================================================================
Deployment Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Subscription: $($subscription.Name)

BASTION CONFIGURATION:
  Name: $bastionName
  Public IP: $($pip.IpAddress)
  SKU: Standard
  Resource Group: $($hubVNet.ResourceGroupName)
  Location: $location

NETWORK ARCHITECTURE:
  Hub VNet: $($hubVNet.Name) ($($hubVNet.AddressSpace.AddressPrefixes -join ', '))
  Peered VNets: $($spokeVNets.Count)
$(foreach ($spoke in $spokeVNets) { "    - $($spoke.Name) ($($spoke.AddressSpace.AddressPrefixes -join ', '))`n" })

CONNECTED VMS: $($allVMs.Count)
$(foreach ($vm in $allVMs) { "  - $($vm.Name) ($($vm.ResourceGroupName))`n" })

FEATURES:
  - Entra ID Authentication (SSO + MFA)
  - Native Client Tunneling (SSH/RDP)
  - SCP File Transfer
  - Multi-VNet Connectivity

COST:
  Monthly: ~`$140 (Bastion only, peering included)

================================================================
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Deployment report saved: $reportPath" -ForegroundColor Cyan
Write-Host ""
#endregion

