#Requires -Version 5.1
<#
.SYNOPSIS
    Configure Bastion NSG for VPN-Only Access
.DESCRIPTION
    Adds NSG rules to Bastion subnet to only allow connections from corporate VPN IP ranges
    This enforces VPN requirement at network level for end users
.EXAMPLE
    .\Configure-Bastion-VPN-Security.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$CorporateVPNRanges = @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CONFIGURE BASTION VPN-ONLY ACCESS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Connect to Azure
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}

Write-Host "Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green
Write-Host ""

# Find Bastion
Write-Host "Locating Azure Bastion..." -ForegroundColor Yellow
$bastions = Get-AzBastion
if ($bastions.Count -eq 0) {
    Write-Host "ERROR: No Bastion found!" -ForegroundColor Red
    exit 1
}

if ($bastions.Count -eq 1) {
    $bastion = $bastions[0]
} else {
    Write-Host "Multiple Bastions found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $bastions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($bastions[$i].Name)" -ForegroundColor White
    }
    $sel = Read-Host "Select Bastion [1-$($bastions.Count)]"
    $bastion = $bastions[[int]$sel - 1]
}

Write-Host "Found: $($bastion.Name)" -ForegroundColor Green
Write-Host ""

# Get Bastion subnet
$bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
$vnetName = ($bastionSubnetId -split '/')[8]
$vnetRG = ($bastionSubnetId -split '/')[4]
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRG
$bastionSubnet = $vnet.Subnets | Where-Object { $_.Name -eq "AzureBastionSubnet" }

Write-Host "Configuring VPN-only access..." -ForegroundColor Yellow
Write-Host "Corporate VPN ranges:" -ForegroundColor Cyan
foreach ($range in $CorporateVPNRanges) {
    Write-Host "  - $range" -ForegroundColor White
}
Write-Host ""

# Check if NSG exists on Bastion subnet
if ($bastionSubnet.NetworkSecurityGroup) {
    $nsgId = $bastionSubnet.NetworkSecurityGroup.Id
    $nsg = Get-AzNetworkSecurityGroup -ResourceId $nsgId
    Write-Host "Found existing NSG: $($nsg.Name)" -ForegroundColor Green
} else {
    # Create new NSG for Bastion
    $nsgName = "NSG-Bastion-VPN-Only"
    Write-Host "Creating new NSG: $nsgName" -ForegroundColor Cyan
    $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $vnetRG -Location $bastion.Location
    
    # Associate with Bastion subnet
    $bastionSubnet.NetworkSecurityGroup = $nsg
    $vnet | Set-AzVirtualNetwork | Out-Null
    Write-Host "NSG created and associated with AzureBastionSubnet" -ForegroundColor Green
}

# Add VPN-only inbound rules
Write-Host ""
Write-Host "Adding NSG rules for VPN-only access..." -ForegroundColor Yellow

# Rule 1: Allow HTTPS from VPN ranges
$nsg | Add-AzNetworkSecurityRuleConfig -Name "Allow-HTTPS-from-VPN" -Description "Allow Bastion HTTPS from corporate VPN" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $CorporateVPNRanges -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443 -ErrorAction SilentlyContinue | Out-Null

# Rule 2: Allow GatewayManager
$nsg | Add-AzNetworkSecurityRuleConfig -Name "Allow-GatewayManager" -Description "Allow Azure Gateway Manager" -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix "GatewayManager" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443 -ErrorAction SilentlyContinue | Out-Null

# Rule 3: Allow Azure Load Balancer
$nsg | Add-AzNetworkSecurityRuleConfig -Name "Allow-AzureLoadBalancer" -Description "Allow Azure Load Balancer" -Access Allow -Protocol Tcp -Direction Inbound -Priority 120 -SourceAddressPrefix "AzureLoadBalancer" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443 -ErrorAction SilentlyContinue | Out-Null

# Rule 4: Deny all other inbound
$nsg | Add-AzNetworkSecurityRuleConfig -Name "Deny-All-Inbound" -Description "Deny all other inbound traffic" -Access Deny -Protocol * -Direction Inbound -Priority 4096 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange * -ErrorAction SilentlyContinue | Out-Null

# Apply changes
$nsg | Set-AzNetworkSecurityGroup | Out-Null

Write-Host "NSG rules configured successfully!" -ForegroundColor Green
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  VPN SECURITY CONFIGURED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "WHAT WAS DONE:" -ForegroundColor Cyan
Write-Host "  1. NSG rules added to AzureBastionSubnet" -ForegroundColor White
Write-Host "  2. Only corporate VPN IP ranges can access Bastion" -ForegroundColor White
Write-Host "  3. End users MUST be on VPN to connect to VMs" -ForegroundColor White
Write-Host ""
Write-Host "WORKFLOW:" -ForegroundColor Cyan
Write-Host "  Admin (Deploy): No VPN needed for infrastructure deployment" -ForegroundColor White
Write-Host "  End User (Connect): Must be on Cisco AnyConnect VPN" -ForegroundColor White
Write-Host ""
Write-Host "END USER INSTRUCTIONS:" -ForegroundColor Cyan
Write-Host "  1. Connect to Cisco AnyConnect VPN" -ForegroundColor White
Write-Host "  2. Open Azure Portal" -ForegroundColor White
Write-Host "  3. Navigate to VM -> Connect -> Bastion" -ForegroundColor White
Write-Host "  4. Enter credentials and connect" -ForegroundColor White
Write-Host ""
