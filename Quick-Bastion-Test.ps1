#Requires -Version 5.1
<#
.SYNOPSIS
    Quick Bastion Connectivity Test
.DESCRIPTION
    Fast check to verify Bastion is ready to connect to your VMs
    - Shows Bastion status
    - Lists all connectable VMs
    - Provides direct connection links
    - Takes < 30 seconds to run
.EXAMPLE
    .\Quick-Bastion-Test.ps1
#>


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
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  QUICK BASTION CONNECTIVITY TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Connect to Azure
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "⚠ Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}

Write-Host "✓ Azure: $((Get-AzContext).Account.Id)" -ForegroundColor Green
Write-Host ""

# Find Bastion
Write-Host "🔍 Scanning for Bastion..." -ForegroundColor Cyan
$bastions = Get-AzBastion
if ($bastions.Count -eq 0) {
    Write-Host "✗ ERROR: No Bastion found!" -ForegroundColor Red
    Write-Host "  Deploy Bastion first using Deploy-Bastion-ULTIMATE.ps1" -ForegroundColor Yellow
    exit 1
}

$bastion = $bastions[0]
if ($bastions.Count -gt 1) {
    Write-Host "⚠ Multiple Bastions found, using: $($bastion.Name)" -ForegroundColor Yellow
}

Write-Host "✓ Bastion: $($bastion.Name)" -ForegroundColor Green
Write-Host ""

# Get Bastion VNet
$bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
$bastionVNetName = ($bastionSubnetId -split '/')[8]
$bastionVNetRG = ($bastionSubnetId -split '/')[4]
$bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG

# Find VMs
Write-Host "🔍 Scanning for VMs..." -ForegroundColor Cyan
$allVMs = Get-AzVM | Where-Object { $_.Location -eq $bastion.Location }

if ($allVMs.Count -eq 0) {
    Write-Host "✗ No VMs found in region: $($bastion.Location)" -ForegroundColor Red
    Write-Host "  Deploy VMs using Deploy-2-Windows-VMs-For-Bastion.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Found $($allVMs.Count) VM(s)" -ForegroundColor Green
Write-Host ""

# Check connectivity
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CONNECTIVITY STATUS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$readyVMs = @()
$notReadyVMs = @()

foreach ($vm in $allVMs) {
    $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
    $subnetId = $nic.IpConfigurations[0].Subnet.Id
    $vnetName = ($subnetId -split '/')[8]
    $vnetRG = ($subnetId -split '/')[4]
    $vmVNet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRG
    
    $isReady = $false
    
    # Same VNet as Bastion?
    if ($vmVNet.Id -eq $bastionVNet.Id) {
        $isReady = $true
        $status = "Same VNet"
    }
    # Peered to Bastion?
    else {
        $peering = $bastionVNet.VirtualNetworkPeerings | Where-Object {
            $_.RemoteVirtualNetwork.Id -eq $vmVNet.Id
        }
        if ($peering -and $peering.PeeringState -eq "Connected") {
            $isReady = $true
            $status = "Peered"
        } else {
            $status = "NOT Connected"
        }
    }
    
    $vmInfo = [PSCustomObject]@{
        Name = $vm.Name
        ResourceGroup = $vm.ResourceGroupName
        VNet = $vnetName
        PrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
        OSType = $vm.StorageProfile.OsDisk.OsType
        Status = $status
        IsReady = $isReady
        VMId = $vm.Id
    }
    
    if ($isReady) {
        $readyVMs += $vmInfo
    } else {
        $notReadyVMs += $vmInfo
    }
    
    $icon = if ($isReady) { "✓" } else { "✗" }
    $color = if ($isReady) { "Green" } else { "Red" }
    Write-Host "  $icon $($vm.Name) - $status" -ForegroundColor $color
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ready to connect: $($readyVMs.Count)/$($allVMs.Count)" -ForegroundColor $(if ($readyVMs.Count -eq $allVMs.Count) { "Green" } else { "Yellow" })
Write-Host ""

if ($notReadyVMs.Count -gt 0) {
    Write-Host "⚠ NOT READY VMs:" -ForegroundColor Yellow
    foreach ($vm in $notReadyVMs) {
        Write-Host "  - $($vm.Name) (needs VNet peering)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "💡 FIX: Run .\Fix-Bastion-Connectivity.ps1" -ForegroundColor Cyan
    Write-Host ""
}

if ($readyVMs.Count -gt 0) {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  READY TO CONNECT - VMs Available" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    
    foreach ($vm in $readyVMs) {
        Write-Host "📌 $($vm.Name)" -ForegroundColor Cyan
        Write-Host "   Private IP: $($vm.PrivateIP)" -ForegroundColor Gray
        Write-Host "   OS Type: $($vm.OSType)" -ForegroundColor Gray
        Write-Host "   Portal Link:" -ForegroundColor White
        Write-Host "   https://portal.azure.com/#@/resource$($vm.VMId)/connectBastion" -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  HOW TO CONNECT" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. Click any Portal Link above (easiest)" -ForegroundColor White
    Write-Host "  OR" -ForegroundColor Gray
    Write-Host "  2. Go to: https://portal.azure.com" -ForegroundColor White
    Write-Host "  3. Navigate to Virtual Machines" -ForegroundColor White
    Write-Host "  4. Click on VM name" -ForegroundColor White
    Write-Host "  5. Click 'Connect' → 'Connect via Bastion'" -ForegroundColor White
    Write-Host "  6. Enter your credentials and click Connect" -ForegroundColor White
    Write-Host ""
    Write-Host "🎉 You're all set! Click a link and test the connection!" -ForegroundColor Green
} else {
    Write-Host "⚠ No VMs are ready to connect via Bastion" -ForegroundColor Yellow
    Write-Host "   Run: .\Fix-Bastion-Connectivity.ps1 to fix peering" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

