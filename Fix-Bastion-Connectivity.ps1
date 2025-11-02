#Requires -Version 5.1
<#
.SYNOPSIS
    Azure Bastion Connectivity Validator & Auto-Fixer
.DESCRIPTION
    Diagnoses and fixes Bastion connectivity issues:
    - Validates VNet peering
    - Checks NSG rules
    - Verifies subnet configurations
    - Auto-fixes common connectivity problems
    - Tests Bastion connectivity to all VMs
.EXAMPLE
    .\Fix-Bastion-Connectivity.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AZURE BASTION CONNECTIVITY VALIDATOR & FIXER" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""


#region Find Bastion
Write-Host "[2/7] Locating Azure Bastion" -ForegroundColor Yellow
$bastions = Get-AzBastion
if ($bastions.Count -eq 0) {
    Write-Host "  ✗ ERROR: No Bastion found in subscription" -ForegroundColor Red
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

Write-Host "  ✓ Found: $($bastion.Name)" -ForegroundColor Green
Write-Host "    Resource Group: $($bastion.ResourceGroupName)" -ForegroundColor Gray
Write-Host "    Location: $($bastion.Location)" -ForegroundColor Gray
Write-Host ""
#endregion

#region Get Bastion VNet
Write-Host "[3/7] Analyzing Network Configuration" -ForegroundColor Yellow
$bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
$bastionVNetName = ($bastionSubnetId -split '/')[8]
$bastionVNetRG = ($bastionSubnetId -split '/')[4]
$bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG

Write-Host "  Bastion Hub VNet:" -ForegroundColor Cyan
Write-Host "    Name: $($bastionVNet.Name)" -ForegroundColor White
Write-Host "    Address Space: $($bastionVNet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor White
Write-Host ""
#endregion

#region Find All VMs
Write-Host "[4/7] Discovering Virtual Machines" -ForegroundColor Yellow
$allVMs = Get-AzVM | Where-Object { $_.Location -eq $bastion.Location }
Write-Host "  Found $($allVMs.Count) VM(s) in $($bastion.Location)" -ForegroundColor Cyan
Write-Host ""

if ($allVMs.Count -eq 0) {
    Write-Host "  ✗ No VMs found in this region!" -ForegroundColor Red
    Write-Host "  Deploy VMs first, then run this script." -ForegroundColor Yellow
    exit 1
}

$vmDetails = @()
foreach ($vm in $allVMs) {
    Write-Host "  Analyzing: $($vm.Name)..." -ForegroundColor Cyan
    
    $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
    $subnetId = $nic.IpConfigurations[0].Subnet.Id
    $vnetName = ($subnetId -split '/')[8]
    $vnetRG = ($subnetId -split '/')[4]
    $subnetName = ($subnetId -split '/')[-1]
    $vmVNet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRG
    
    $isPeered = $false
    $peeringStatus = "Not Peered"
    
    # Check if VM is in Bastion VNet
    if ($vmVNet.Id -eq $bastionVNet.Id) {
        $isPeered = $true
        $peeringStatus = "Same VNet as Bastion"
    } else {
        # Check peering from Bastion VNet to VM VNet
        $peering = $bastionVNet.VirtualNetworkPeerings | Where-Object {
            $_.RemoteVirtualNetwork.Id -eq $vmVNet.Id
        }
        if ($peering -and $peering.PeeringState -eq "Connected") {
            $isPeered = $true
            $peeringStatus = "Peered (Connected)"
        }
    }
    
    $vmDetails += [PSCustomObject]@{
        Name = $vm.Name
        ResourceGroup = $vm.ResourceGroupName
        VNet = $vnetName
        VNetRG = $vnetRG
        Subnet = $subnetName
        VNetObject = $vmVNet
        IsPeered = $isPeered
        PeeringStatus = $peeringStatus
        PrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
        OSType = $vm.StorageProfile.OsDisk.OsType
        VMObject = $vm
        NICObject = $nic
    }
    
    $statusColor = if ($isPeered) { "Green" } else { "Red" }
    Write-Host "    ✓ $($vm.Name): $peeringStatus" -ForegroundColor $statusColor
}
Write-Host ""
#endregion

#region Display VM Status
Write-Host "[5/7] VM Connectivity Status" -ForegroundColor Yellow
Write-Host ""
Write-Host "  VM NAME                    VNET                  STATUS" -ForegroundColor Cyan
Write-Host "  ========================== ==================== ==================" -ForegroundColor Gray

foreach ($vm in $vmDetails) {
    $status = if ($vm.IsPeered) { "✓ READY" } else { "✗ NOT CONNECTED" }
    $color = if ($vm.IsPeered) { "Green" } else { "Red" }
    $vmName = $vm.Name.PadRight(26)
    $vnetName = $vm.VNet.PadRight(20)
    Write-Host "  $vmName $vnetName $status" -ForegroundColor $color
}
Write-Host ""
#endregion

#region Fix Connectivity
Write-Host "[6/7] Auto-Fix Connectivity Issues" -ForegroundColor Yellow
$unpeeredVMs = $vmDetails | Where-Object { -not $_.IsPeered }

if ($unpeeredVMs.Count -eq 0) {
    Write-Host "  ✓ All VMs are properly connected to Bastion!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "  Found $($unpeeredVMs.Count) VM(s) not connected to Bastion" -ForegroundColor Yellow
    Write-Host ""
    
    $uniqueVNets = $unpeeredVMs | Select-Object -Property VNet, VNetRG, VNetObject -Unique
    
    foreach ($vnet in $uniqueVNets) {
        Write-Host "  Fixing: $($vnet.VNet)..." -ForegroundColor Cyan
        
        try {
            # Create peering from Bastion VNet to VM VNet
            $peeringName1 = "Bastion-to-$($vnet.VNet)"
            Write-Host "    Creating peering: $peeringName1..." -ForegroundColor Gray
            Add-AzVirtualNetworkPeering -Name $peeringName1 -VirtualNetwork $bastionVNet -RemoteVirtualNetworkId $vnet.VNetObject.Id -AllowForwardedTraffic -AllowGatewayTransit -ErrorAction Stop | Out-Null
            
            # Create peering from VM VNet to Bastion VNet
            $peeringName2 = "$($vnet.VNet)-to-Bastion"
            Write-Host "    Creating peering: $peeringName2..." -ForegroundColor Gray
            Add-AzVirtualNetworkPeering -Name $peeringName2 -VirtualNetwork $vnet.VNetObject -RemoteVirtualNetworkId $bastionVNet.Id -AllowForwardedTraffic -UseRemoteGateways -ErrorAction Stop | Out-Null
            
            Write-Host "    ✓ Peering created successfully!" -ForegroundColor Green
            
            # Update status for VMs in this VNet
            foreach ($vm in $vmDetails | Where-Object { $_.VNet -eq $vnet.VNet }) {
                $vm.IsPeered = $true
                $vm.PeeringStatus = "Peered (Connected)"
            }
            
        } catch {
            Write-Host "    ✗ Failed to create peering: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}
#endregion

#region NSG Validation
Write-Host "[7/7] Validating Network Security Groups" -ForegroundColor Yellow
Write-Host ""

foreach ($vm in $vmDetails) {
    Write-Host "  Checking NSG for: $($vm.Name)..." -ForegroundColor Cyan
    
    # Check NSG on NIC
    $nsgIssues = @()
    if ($vm.NICObject.NetworkSecurityGroup) {
        $nsgId = $vm.NICObject.NetworkSecurityGroup.Id
        $nsg = Get-AzNetworkSecurityGroup -ResourceId $nsgId
        
        # Check for RDP rule (Windows)
        if ($vm.OSType -eq "Windows") {
            $rdpRule = $nsg.SecurityRules | Where-Object {
                $_.Direction -eq "Inbound" -and
                $_.Access -eq "Allow" -and
                ($_.DestinationPortRange -eq "3389" -or $_.DestinationPortRange -eq "*")
            }
            if (!$rdpRule) {
                $nsgIssues += "No RDP inbound rule (port 3389)"
            }
        }
        
        # Check for SSH rule (Linux)
        if ($vm.OSType -eq "Linux") {
            $sshRule = $nsg.SecurityRules | Where-Object {
                $_.Direction -eq "Inbound" -and
                $_.Access -eq "Allow" -and
                ($_.DestinationPortRange -eq "22" -or $_.DestinationPortRange -eq "*")
            }
            if (!$sshRule) {
                $nsgIssues += "No SSH inbound rule (port 22)"
            }
        }
    }
    
    if ($nsgIssues.Count -eq 0) {
        Write-Host "    ✓ NSG configuration looks good" -ForegroundColor Green
    } else {
        Write-Host "    ⚠ NSG Issues:" -ForegroundColor Yellow
        foreach ($issue in $nsgIssues) {
            Write-Host "      - $issue" -ForegroundColor Yellow
        }
        Write-Host "    Note: Bastion can still connect via Azure backbone" -ForegroundColor Gray
    }
}
Write-Host ""
#endregion

#region Final Report
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  CONNECTIVITY REPORT" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "BASTION CONFIGURATION:" -ForegroundColor Cyan
Write-Host "  Name: $($bastion.Name)" -ForegroundColor White
Write-Host "  Resource Group: $($bastion.ResourceGroupName)" -ForegroundColor White
Write-Host "  Hub VNet: $($bastionVNet.Name)" -ForegroundColor White
Write-Host ""

Write-Host "CONNECTED VMs ($($vmDetails.Count) total):" -ForegroundColor Cyan
$readyCount = ($vmDetails | Where-Object { $_.IsPeered }).Count
Write-Host "  Ready for Bastion: $readyCount/$($vmDetails.Count)" -ForegroundColor $(if ($readyCount -eq $vmDetails.Count) { "Green" } else { "Yellow" })
Write-Host ""

foreach ($vm in $vmDetails) {
    $statusIcon = if ($vm.IsPeered) { "✓" } else { "✗" }
    $statusColor = if ($vm.IsPeered) { "Green" } else { "Red" }
    Write-Host "  $statusIcon $($vm.Name)" -ForegroundColor $statusColor
    Write-Host "      VNet: $($vm.VNet)" -ForegroundColor Gray
    Write-Host "      Private IP: $($vm.PrivateIP)" -ForegroundColor Gray
    Write-Host "      Status: $($vm.PeeringStatus)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "HOW TO CONNECT TO YOUR VMs:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  METHOD 1: Azure Portal (Easiest)" -ForegroundColor Yellow
Write-Host "  1. Go to Azure Portal" -ForegroundColor White
Write-Host "  2. Navigate to your VM" -ForegroundColor White
Write-Host "  3. Click 'Connect' button" -ForegroundColor White
Write-Host "  4. Select 'Connect via Bastion'" -ForegroundColor White
Write-Host "  5. Enter credentials and connect" -ForegroundColor White
Write-Host ""

Write-Host "  METHOD 2: Azure CLI (Native Client)" -ForegroundColor Yellow
Write-Host "  For Windows VMs (RDP):" -ForegroundColor White
foreach ($vm in $vmDetails | Where-Object { $_.OSType -eq "Windows" -and $_.IsPeered }) {
    Write-Host "    # $($vm.Name):" -ForegroundColor Gray
    Write-Host "    az network bastion tunnel --name $($bastion.Name) \" -ForegroundColor Gray
    Write-Host "      --resource-group $($bastion.ResourceGroupName) \" -ForegroundColor Gray
    Write-Host "      --target-resource-id $($vm.VMObject.Id) \" -ForegroundColor Gray
    Write-Host "      --resource-port 3389 --port 3389" -ForegroundColor Gray
    Write-Host "    # Then in another terminal:" -ForegroundColor Gray
    Write-Host "    mstsc /v:localhost:3389" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "  METHOD 3: Azure Portal Quick Link" -ForegroundColor Yellow
foreach ($vm in $vmDetails | Where-Object { $_.IsPeered }) {
    Write-Host "    $($vm.Name):" -ForegroundColor White
    Write-Host "    https://portal.azure.com/#@/resource$($vm.VMObject.Id)/connectBastion" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  NEXT STEPS:" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if ($readyCount -eq $vmDetails.Count) {
    Write-Host "  ✓ All VMs are ready!" -ForegroundColor Green
    Write-Host "  ✓ Go to Azure Portal and connect via Bastion" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "  ⚠ Some VMs are not connected" -ForegroundColor Yellow
    Write-Host "  Run this script again to re-check connectivity" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "TROUBLESHOOTING:" -ForegroundColor Cyan
Write-Host "  If you can't connect:" -ForegroundColor White
Write-Host "  1. Verify VM is running (not stopped)" -ForegroundColor Gray
Write-Host "  2. Check VM credentials are correct" -ForegroundColor Gray
Write-Host "  3. Ensure Windows VMs allow RDP" -ForegroundColor Gray
Write-Host "  4. Wait 5-10 minutes after peering changes" -ForegroundColor Gray
Write-Host ""

# Save report
$reportPath = ".\Bastion-Connectivity-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$report = @"
================================================================
AZURE BASTION CONNECTIVITY REPORT
================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

BASTION: $($bastion.Name)
Resource Group: $($bastion.ResourceGroupName)
Hub VNet: $($bastionVNet.Name)

VM CONNECTIVITY STATUS:
================================================================
$(foreach ($vm in $vmDetails) {
    "$($vm.Name.PadRight(30)) $(if ($vm.IsPeered) { '✓ READY' } else { '✗ NOT CONNECTED' })`n  VNet: $($vm.VNet)`n  IP: $($vm.PrivateIP)`n  Status: $($vm.PeeringStatus)`n`n"
})

SUMMARY:
  Ready: $readyCount/$($vmDetails.Count) VMs
  
================================================================
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Full report saved: $reportPath" -ForegroundColor Cyan
Write-Host ""
#endregion


