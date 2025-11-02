#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy 2 Windows VMs for Bastion Testing with Optional Storage Account
.DESCRIPTION
    Creates 2 fully configured Windows Server VMs ready for Bastion
    Now includes optional Azure Files storage account for FSLogix user profiles
.EXAMPLE
    .\Deploy-2-Windows-VMs-For-Bastion.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DEPLOY 2 WINDOWS VMs FOR BASTION TESTING" -ForegroundColor Cyan
Write-Host "  With Optional Storage Account for User Profiles" -ForegroundColor Cyan
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
#region Azure Connection
Write-Host "[1/9] Azure Authentication" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "  Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}
Write-Host "  Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green
Write-Host ""
#endregion

#region Find Bastion
Write-Host "[2/9] Locating Azure Bastion" -ForegroundColor Yellow
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

$bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
$bastionVNetName = ($bastionSubnetId -split '/')[8]
$bastionVNetRG = ($bastionSubnetId -split '/')[4]
$bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG
Write-Host "    Hub VNet: $($bastionVNet.Name)" -ForegroundColor Gray
Write-Host ""
#endregion

#region Storage Account Option
Write-Host "[3/9] Storage Account for User Profiles (FSLogix)" -ForegroundColor Yellow
Write-Host "  Do you need a storage account for user profiles?" -ForegroundColor Cyan
Write-Host "    [Y] Yes - I need storage for FSLogix profiles" -ForegroundColor White
Write-Host "    [N] No - Skip storage account (default)" -ForegroundColor Gray
Write-Host ""
$needStorage = Read-Host "  Need storage account? (Y/N)"

$storageAccount = $null
$storageAccountKey = $null
$fileShareName = $null

if ($needStorage -eq "Y" -or $needStorage -eq "y") {
    Write-Host ""
    Write-Host "  Storage Account Options:" -ForegroundColor Cyan
    Write-Host "    [1] Use EXISTING storage account" -ForegroundColor White
    Write-Host "    [2] Create NEW storage account" -ForegroundColor White
    Write-Host ""
    do {
        $storageChoice = Read-Host "  Select option [1-2]"
    } while ($storageChoice -notmatch '^[12]$')
    
    if ($storageChoice -eq "1") {
        Write-Host ""
        Write-Host "  Scanning for storage accounts..." -ForegroundColor Cyan
        $storageAccounts = Get-AzStorageAccount | Where-Object { $_.Location -eq $bastion.Location }
        
        if ($storageAccounts.Count -eq 0) {
            Write-Host "  No storage accounts found in $($bastion.Location)" -ForegroundColor Yellow
            Write-Host "  Will create a new one instead..." -ForegroundColor Yellow
            $storageChoice = "2"
        } else {
            Write-Host "  Available Storage Accounts:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $storageAccounts.Count; $i++) {
                Write-Host "    [$($i + 1)] $($storageAccounts[$i].StorageAccountName) - $($storageAccounts[$i].ResourceGroupName)" -ForegroundColor White
            }
            do {
                $stSel = Read-Host "  Select storage account [1-$($storageAccounts.Count)]"
            } while ([int]$stSel -lt 1 -or [int]$stSel -gt $storageAccounts.Count)
            
            $storageAccount = $storageAccounts[[int]$stSel - 1]
            Write-Host "  Selected: $($storageAccount.StorageAccountName)" -ForegroundColor Green
        }
    }
    
    if ($storageChoice -eq "2") {
        Write-Host ""
        Write-Host "  Creating new storage account..." -ForegroundColor Cyan
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $storageAccountName = "stfslogix$($timestamp)".ToLower() -replace '[^a-z0-9]', ''
        if ($storageAccountName.Length -gt 24) {
            $storageAccountName = $storageAccountName.Substring(0, 24)
        }
        
        $storageRG = "RG-Storage-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        New-AzResourceGroup -Name $storageRG -Location $bastion.Location -Force | Out-Null
        
        $storageAccount = New-AzStorageAccount -ResourceGroupName $storageRG -Name $storageAccountName -Location $bastion.Location -SkuName Standard_LRS -Kind StorageV2 -EnableLargeFileShare -ErrorAction Stop
        
        Write-Host "  Storage account created: $storageAccountName" -ForegroundColor Green
    }
    
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
    
    Write-Host "  Creating Azure File Share..." -ForegroundColor Cyan
    $fileShareName = "profiles"
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageAccountKey
    
    $existingShare = Get-AzStorageShare -Name $fileShareName -Context $storageContext -ErrorAction SilentlyContinue
    if (!$existingShare) {
        New-AzStorageShare -Name $fileShareName -Context $storageContext -QuotaGiB 100 | Out-Null
        Write-Host "  File share created: $fileShareName (100GB)" -ForegroundColor Green
    } else {
        Write-Host "  File share exists: $fileShareName" -ForegroundColor Green
    }
    Write-Host ""
} else {
    Write-Host "  Skipping storage account" -ForegroundColor Yellow
    Write-Host ""
}
#endregion

#region Configuration
Write-Host "[4/9] VM Configuration" -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$location = $bastion.Location

Write-Host "  VM Configuration:" -ForegroundColor Cyan
Write-Host "    Location: $location" -ForegroundColor White
Write-Host "    OS: Windows Server 2022 Datacenter" -ForegroundColor White
Write-Host "    Size: Standard_B2s (2 vCPU, 4GB RAM)" -ForegroundColor White
if ($storageAccount) {
    Write-Host "    Storage: $($storageAccount.StorageAccountName)" -ForegroundColor White
}
Write-Host ""

$adminUsername = Read-Host "    VM Admin Username"
$adminPassword = Read-Host "    VM Admin Password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
Write-Host "  Credentials set" -ForegroundColor Green
Write-Host ""
#endregion

#region Create Resources
Write-Host "[5/9] Creating Resource Group & VNet" -ForegroundColor Yellow
$rgName = "RG-BastionTest-VMs-$timestamp"
$vnetName = "VNet-Test-VMs"
$subnetName = "Subnet-VMs"

Write-Host "  Creating Resource Group..." -ForegroundColor Cyan
$rg = New-AzResourceGroup -Name $rgName -Location $location -Force
Write-Host "  Resource Group created: $rgName" -ForegroundColor Green

Write-Host "  Creating Virtual Network..." -ForegroundColor Cyan
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.1.0.0/24"
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix "10.1.0.0/16" -Subnet $subnetConfig
Write-Host "  VNet created: $vnetName" -ForegroundColor Green
Write-Host ""
#endregion

#region VNet Peering
Write-Host "[6/9] Configuring VNet Peering to Bastion" -ForegroundColor Yellow
try {
    $peeringName1 = "TestVMs-to-Bastion"
    Add-AzVirtualNetworkPeering -Name $peeringName1 -VirtualNetwork $vnet -RemoteVirtualNetworkId $bastionVNet.Id -AllowForwardedTraffic -ErrorAction Stop | Out-Null
    Write-Host "  Peering created: $peeringName1" -ForegroundColor Green
    
    $peeringName2 = "Bastion-to-TestVMs-$timestamp"
    Add-AzVirtualNetworkPeering -Name $peeringName2 -VirtualNetwork $bastionVNet -RemoteVirtualNetworkId $vnet.Id -AllowForwardedTraffic -AllowGatewayTransit -ErrorAction Stop | Out-Null
    Write-Host "  Peering created: $peeringName2" -ForegroundColor Green
} catch {
    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""
#endregion

#region Create NSG
Write-Host "[7/9] Creating Network Security Group" -ForegroundColor Yellow
$nsgName = "NSG-TestVMs"
$rdpRule = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP-Bastion" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $rdpRule
Write-Host "  NSG created" -ForegroundColor Green
Write-Host ""
#endregion

#region Deploy VMs
Write-Host "[8/9] Deploying 2 Windows VMs (10-15 minutes)" -ForegroundColor Yellow

$vm1Name = "TestVM-01"
$nic1Name = "$vm1Name-NIC"
Write-Host "  Creating $vm1Name..." -ForegroundColor Cyan
$nic1 = New-AzNetworkInterface -Name $nic1Name -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id
$vm1 = New-AzVMConfig -VMName $vm1Name -VMSize "Standard_B2s"
$vm1 = Set-AzVMOperatingSystem -VM $vm1 -Windows -ComputerName $vm1Name -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vm1 = Set-AzVMSourceImage -VM $vm1 -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
$vm1 = Add-AzVMNetworkInterface -VM $vm1 -Id $nic1.Id
$vm1 = Set-AzVMBootDiagnostic -VM $vm1 -Disable
New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm1 | Out-Null
Write-Host "  $vm1Name deployed" -ForegroundColor Green

$vm2Name = "TestVM-02"
$nic2Name = "$vm2Name-NIC"
Write-Host "  Creating $vm2Name..." -ForegroundColor Cyan
$nic2 = New-AzNetworkInterface -Name $nic2Name -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id
$vm2 = New-AzVMConfig -VMName $vm2Name -VMSize "Standard_B2s"
$vm2 = Set-AzVMOperatingSystem -VM $vm2 -Windows -ComputerName $vm2Name -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vm2 = Set-AzVMSourceImage -VM $vm2 -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
$vm2 = Add-AzVMNetworkInterface -VM $vm2 -Id $nic2.Id
$vm2 = Set-AzVMBootDiagnostic -VM $vm2 -Disable
New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm2 | Out-Null
Write-Host "  $vm2Name deployed" -ForegroundColor Green
Write-Host ""
#endregion

#region Success
$vm1Obj = Get-AzVM -ResourceGroupName $rgName -Name $vm1Name
$vm2Obj = Get-AzVM -ResourceGroupName $rgName -Name $vm2Name
$nic1Details = Get-AzNetworkInterface -ResourceId $vm1Obj.NetworkProfile.NetworkInterfaces[0].Id
$nic2Details = Get-AzNetworkInterface -ResourceId $vm2Obj.NetworkProfile.NetworkInterfaces[0].Id

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS! 2 VMs DEPLOYED AND READY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "VMs DEPLOYED:" -ForegroundColor Cyan
Write-Host "  1. $vm1Name - $($nic1Details.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor White
Write-Host "  2. $vm2Name - $($nic2Details.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor White
Write-Host ""
Write-Host "CREDENTIALS:" -ForegroundColor Cyan
Write-Host "  Username: $adminUsername" -ForegroundColor White
Write-Host ""

if ($storageAccount) {
    Write-Host "STORAGE CONFIGURATION:" -ForegroundColor Cyan
    Write-Host "  Storage Account: $($storageAccount.StorageAccountName)" -ForegroundColor White
    Write-Host "  File Share: $fileShareName" -ForegroundColor White
    Write-Host "  UNC Path: \\$($storageAccount.StorageAccountName).file.core.windows.net\$fileShareName" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "CONNECTION LINKS:" -ForegroundColor Cyan
Write-Host "  Portal -> Virtual Machines -> Click VM -> Connect -> Bastion" -ForegroundColor White
Write-Host ""
Write-Host "  Direct Links:" -ForegroundColor Yellow
Write-Host "  https://portal.azure.com/#@/resource$($vm1Obj.Id)/connectBastion" -ForegroundColor Gray
Write-Host "  https://portal.azure.com/#@/resource$($vm2Obj.Id)/connectBastion" -ForegroundColor Gray
Write-Host ""
Write-Host "CLEANUP (when done):" -ForegroundColor Cyan
Write-Host "  Remove-AzResourceGroup -Name $rgName -Force" -ForegroundColor Gray
Write-Host ""
#endregion

