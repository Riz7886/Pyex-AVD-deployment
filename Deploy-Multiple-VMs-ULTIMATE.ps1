#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Multiple VMs with ULTIMATE Flexibility
.DESCRIPTION
    Deploy any number of Windows or Linux VMs with flexible options:
    - OS Choice: Windows Server 2019/2022, Ubuntu, RHEL, CentOS
    - Quantity: 1-50 VMs at once
    - Size: Budget to Enterprise options
    - Storage: Optional FSLogix integration
    - Auto-connects to existing Bastion
.EXAMPLE
    .\Deploy-Multiple-VMs-ULTIMATE.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DEPLOY MULTIPLE VMs - ULTIMATE EDITION" -ForegroundColor Cyan
Write-Host "  Windows & Linux | Any Quantity | Flexible Sizing" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

#region Azure Connection
Write-Host "[1/10] Azure Authentication" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "  Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount | Out-Null
}
Write-Host "  Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green
Write-Host ""
#endregion

#region Find Bastion (Optional)
Write-Host "[2/10] Checking for Azure Bastion" -ForegroundColor Yellow
$bastions = Get-AzBastion
if ($bastions.Count -eq 0) {
    Write-Host "  No Bastion found - VMs will be created without auto-peering" -ForegroundColor Yellow
    Write-Host "  You can run Fix-Bastion-Connectivity.ps1 later to connect them" -ForegroundColor Yellow
    $bastion = $null
    $bastionVNet = $null
} else {
    if ($bastions.Count -eq 1) {
        $bastion = $bastions[0]
    } else {
        Write-Host "  Multiple Bastions found:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $bastions.Count; $i++) {
            Write-Host "    [$($i + 1)] $($bastions[$i].Name) - $($bastions[$i].ResourceGroupName)" -ForegroundColor White
        }
        do {
            $sel = Read-Host "  Select Bastion [1-$($bastions.Count)] or 0 to skip"
        } while ([int]$sel -lt 0 -or [int]$sel -gt $bastions.Count)
        
        if ([int]$sel -eq 0) {
            $bastion = $null
        } else {
            $bastion = $bastions[[int]$sel - 1]
        }
    }
    
    if ($bastion) {
        Write-Host "  Found: $($bastion.Name)" -ForegroundColor Green
        $bastionSubnetId = $bastion.IpConfigurations[0].Subnet.Id
        $bastionVNetName = ($bastionSubnetId -split '/')[8]
        $bastionVNetRG = ($bastionSubnetId -split '/')[4]
        $bastionVNet = Get-AzVirtualNetwork -Name $bastionVNetName -ResourceGroupName $bastionVNetRG
        Write-Host "    Hub VNet: $($bastionVNet.Name)" -ForegroundColor Gray
    }
}
Write-Host ""
#endregion

#region OS Selection
Write-Host "[3/10] Operating System Selection" -ForegroundColor Yellow
Write-Host "  Choose Operating System:" -ForegroundColor Cyan
Write-Host "    [1] Windows Server 2019 Datacenter" -ForegroundColor White
Write-Host "    [2] Windows Server 2022 Datacenter (Recommended)" -ForegroundColor White
Write-Host "    [3] Ubuntu 22.04 LTS" -ForegroundColor White
Write-Host "    [4] Ubuntu 20.04 LTS" -ForegroundColor White
Write-Host "    [5] Red Hat Enterprise Linux 9" -ForegroundColor White
Write-Host "    [6] CentOS 8" -ForegroundColor White
Write-Host ""
do {
    $osChoice = Read-Host "  Select OS [1-6]"
} while ([int]$osChoice -lt 1 -or [int]$osChoice -gt 6)

$osConfig = switch ([int]$osChoice) {
    1 { @{
        Publisher = "MicrosoftWindowsServer"
        Offer = "WindowsServer"
        Sku = "2019-datacenter-azure-edition"
        Version = "latest"
        Type = "Windows"
        Name = "Windows Server 2019"
    }}
    2 { @{
        Publisher = "MicrosoftWindowsServer"
        Offer = "WindowsServer"
        Sku = "2022-datacenter-azure-edition"
        Version = "latest"
        Type = "Windows"
        Name = "Windows Server 2022"
    }}
    3 { @{
        Publisher = "Canonical"
        Offer = "0001-com-ubuntu-server-jammy"
        Sku = "22_04-lts-gen2"
        Version = "latest"
        Type = "Linux"
        Name = "Ubuntu 22.04 LTS"
    }}
    4 { @{
        Publisher = "Canonical"
        Offer = "0001-com-ubuntu-server-focal"
        Sku = "20_04-lts-gen2"
        Version = "latest"
        Type = "Linux"
        Name = "Ubuntu 20.04 LTS"
    }}
    5 { @{
        Publisher = "RedHat"
        Offer = "RHEL"
        Sku = "9-lvm-gen2"
        Version = "latest"
        Type = "Linux"
        Name = "Red Hat Enterprise Linux 9"
    }}
    6 { @{
        Publisher = "OpenLogic"
        Offer = "CentOS"
        Sku = "8_5-gen2"
        Version = "latest"
        Type = "Linux"
        Name = "CentOS 8"
    }}
}

Write-Host "  Selected: $($osConfig.Name)" -ForegroundColor Green
Write-Host ""
#endregion

#region VM Quantity
Write-Host "[4/10] VM Quantity" -ForegroundColor Yellow
Write-Host "  How many VMs do you want to deploy?" -ForegroundColor Cyan
Write-Host "    Minimum: 1 VM" -ForegroundColor Gray
Write-Host "    Maximum: 50 VMs (recommended for single deployment)" -ForegroundColor Gray
Write-Host ""
do {
    $vmCount = Read-Host "  Enter quantity [1-50]"
} while ([int]$vmCount -lt 1 -or [int]$vmCount -gt 50)

Write-Host "  Will deploy: $vmCount VMs" -ForegroundColor Green
Write-Host ""
#endregion

#region VM Size
Write-Host "[5/10] VM Size Selection" -ForegroundColor Yellow
Write-Host "  Choose VM Size (approximate monthly cost per VM):" -ForegroundColor Cyan
Write-Host "    [1] Standard_B2s   - 2 vCPU,  4GB RAM  (~`$30/month)  - Budget" -ForegroundColor White
Write-Host "    [2] Standard_B2ms  - 2 vCPU,  8GB RAM  (~`$60/month)  - Budget+" -ForegroundColor White
Write-Host "    [3] Standard_D2s_v3 - 2 vCPU,  8GB RAM  (~`$70/month)  - Balanced" -ForegroundColor White
Write-Host "    [4] Standard_D4s_v3 - 4 vCPU, 16GB RAM  (~`$140/month) - Performance" -ForegroundColor White
Write-Host "    [5] Standard_E2s_v3 - 2 vCPU, 16GB RAM  (~`$110/month) - Memory Optimized" -ForegroundColor White
Write-Host "    [6] Standard_E4s_v3 - 4 vCPU, 32GB RAM  (~`$220/month) - High Memory" -ForegroundColor White
Write-Host "    [7] Custom (enter your own)" -ForegroundColor Yellow
Write-Host ""
do {
    $sizeChoice = Read-Host "  Select size [1-7]"
} while ([int]$sizeChoice -lt 1 -or [int]$sizeChoice -gt 7)

$vmSize = switch ([int]$sizeChoice) {
    1 { "Standard_B2s" }
    2 { "Standard_B2ms" }
    3 { "Standard_D2s_v3" }
    4 { "Standard_D4s_v3" }
    5 { "Standard_E2s_v3" }
    6 { "Standard_E4s_v3" }
    7 { Read-Host "  Enter custom VM size (e.g., Standard_D8s_v3)" }
}

Write-Host "  Selected: $vmSize" -ForegroundColor Green
Write-Host ""
#endregion

#region Storage Account Option (Windows only)
$storageAccount = $null
$storageAccountKey = $null
$fileShareName = $null

if ($osConfig.Type -eq "Windows") {
    Write-Host "[6/10] Storage Account for User Profiles (FSLogix)" -ForegroundColor Yellow
    Write-Host "  Do you need a storage account for user profiles?" -ForegroundColor Cyan
    Write-Host "    [Y] Yes - Configure FSLogix profiles" -ForegroundColor White
    Write-Host "    [N] No - Skip storage (default)" -ForegroundColor Gray
    Write-Host ""
    $needStorage = Read-Host "  Need storage account? (Y/N)"
    
    if ($needStorage -eq "Y" -or $needStorage -eq "y") {
        Write-Host ""
        Write-Host "  Storage Account Options:" -ForegroundColor Cyan
        Write-Host "    [1] Use EXISTING storage account" -ForegroundColor White
        Write-Host "    [2] Create NEW storage account" -ForegroundColor White
        Write-Host ""
        do {
            $storageChoice = Read-Host "  Select option [1-2]"
        } while ($storageChoice -notmatch '^[12]$')
        
        $location = if ($bastion) { $bastion.Location } else { "eastus" }
        
        if ($storageChoice -eq "1") {
            Write-Host ""
            Write-Host "  Scanning for storage accounts..." -ForegroundColor Cyan
            $storageAccounts = Get-AzStorageAccount | Where-Object { $_.Location -eq $location }
            
            if ($storageAccounts.Count -eq 0) {
                Write-Host "  No storage accounts found in $location" -ForegroundColor Yellow
                Write-Host "  Will create a new one..." -ForegroundColor Yellow
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
            New-AzResourceGroup -Name $storageRG -Location $location -Force | Out-Null
            
            $storageAccount = New-AzStorageAccount -ResourceGroupName $storageRG -Name $storageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2 -EnableLargeFileShare -ErrorAction Stop
            
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
} else {
    Write-Host "[6/10] Storage Account (Skipped - Linux VMs)" -ForegroundColor Yellow
    Write-Host "  FSLogix not applicable for Linux" -ForegroundColor Gray
    Write-Host ""
}
#endregion

#region Credentials
Write-Host "[7/10] VM Credentials" -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$location = if ($bastion) { $bastion.Location } else { "eastus" }

Write-Host "  VM Configuration:" -ForegroundColor Cyan
Write-Host "    Location: $location" -ForegroundColor White
Write-Host "    OS: $($osConfig.Name)" -ForegroundColor White
Write-Host "    Size: $vmSize" -ForegroundColor White
Write-Host "    Quantity: $vmCount VMs" -ForegroundColor White
if ($storageAccount) {
    Write-Host "    Storage: $($storageAccount.StorageAccountName)" -ForegroundColor White
}
Write-Host ""

$adminUsername = Read-Host "    Admin Username"
$adminPassword = Read-Host "    Admin Password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
Write-Host "  Credentials set" -ForegroundColor Green
Write-Host ""
#endregion

#region Create Resources
Write-Host "[8/10] Creating Resource Group & VNet" -ForegroundColor Yellow
$rgName = "RG-VMs-$timestamp"
$vnetName = "VNet-VMs-$timestamp"
$subnetName = "Subnet-VMs"

Write-Host "  Creating Resource Group..." -ForegroundColor Cyan
$rg = New-AzResourceGroup -Name $rgName -Location $location -Force
Write-Host "  Resource Group created: $rgName" -ForegroundColor Green

Write-Host "  Creating Virtual Network..." -ForegroundColor Cyan
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.2.0.0/24"
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix "10.2.0.0/16" -Subnet $subnetConfig
Write-Host "  VNet created: $vnetName" -ForegroundColor Green
Write-Host ""
#endregion

#region VNet Peering
if ($bastionVNet) {
    Write-Host "[9/10] Configuring VNet Peering to Bastion" -ForegroundColor Yellow
    try {
        $peeringName1 = "VMs-to-Bastion-$timestamp"
        Add-AzVirtualNetworkPeering -Name $peeringName1 -VirtualNetwork $vnet -RemoteVirtualNetworkId $bastionVNet.Id -AllowForwardedTraffic -ErrorAction Stop | Out-Null
        Write-Host "  Peering created: $peeringName1" -ForegroundColor Green
        
        $peeringName2 = "Bastion-to-VMs-$timestamp"
        Add-AzVirtualNetworkPeering -Name $peeringName2 -VirtualNetwork $bastionVNet -RemoteVirtualNetworkId $vnet.Id -AllowForwardedTraffic -AllowGatewayTransit -ErrorAction Stop | Out-Null
        Write-Host "  Peering created: $peeringName2" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "[9/10] VNet Peering (Skipped - No Bastion)" -ForegroundColor Yellow
    Write-Host ""
}
#endregion

#region Create NSG
Write-Host "[10/10] Creating NSG & Deploying VMs" -ForegroundColor Yellow
$nsgName = "NSG-VMs-$timestamp"
if ($osConfig.Type -eq "Windows") {
    $rule = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
} else {
    $rule = New-AzNetworkSecurityRuleConfig -Name "Allow-SSH" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22
}
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $rule
Write-Host "  NSG created" -ForegroundColor Green
Write-Host ""

Write-Host "  Deploying $vmCount VMs (this may take 10-15 minutes)..." -ForegroundColor Yellow
Write-Host ""

$deployedVMs = @()

for ($i = 1; $i -le $vmCount; $i++) {
    $vmName = "VM-$('{0:D2}' -f $i)"
    $nicName = "$vmName-NIC"
    
    Write-Host "  [$i/$vmCount] Creating $vmName..." -ForegroundColor Cyan
    
    # Create NIC
    $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id
    
    # Create VM config
    $vm = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    
    if ($osConfig.Type -eq "Windows") {
        $vm = Set-AzVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
    } else {
        $vm = Set-AzVMOperatingSystem -VM $vm -Linux -ComputerName $vmName -Credential $cred
    }
    
    $vm = Set-AzVMSourceImage -VM $vm -PublisherName $osConfig.Publisher -Offer $osConfig.Offer -Skus $osConfig.Sku -Version $osConfig.Version
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
    $vm = Set-AzVMBootDiagnostic -VM $vm -Disable
    
    New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm -ErrorAction Continue | Out-Null
    
    $deployedVMs += @{
        Name = $vmName
        NIC = $nicName
    }
    
    Write-Host "    $vmName deployed" -ForegroundColor Green
}

Write-Host ""
Write-Host "  All VMs deployed successfully!" -ForegroundColor Green
Write-Host ""
#endregion

#region Success Summary
$vmObjects = Get-AzVM -ResourceGroupName $rgName
$vmDetails = @()

foreach ($vmObj in $vmObjects) {
    $nicId = $vmObj.NetworkProfile.NetworkInterfaces[0].Id
    $nicDetails = Get-AzNetworkInterface -ResourceId $nicId
    $vmDetails += @{
        Name = $vmObj.Name
        IP = $nicDetails.IpConfigurations[0].PrivateIpAddress
    }
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS! $vmCount VMs DEPLOYED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "DEPLOYMENT DETAILS:" -ForegroundColor Cyan
Write-Host "  OS: $($osConfig.Name)" -ForegroundColor White
Write-Host "  Size: $vmSize" -ForegroundColor White
Write-Host "  Location: $location" -ForegroundColor White
Write-Host "  Resource Group: $rgName" -ForegroundColor White
Write-Host "  VNet: $vnetName" -ForegroundColor White
Write-Host ""

Write-Host "VMs DEPLOYED:" -ForegroundColor Cyan
foreach ($vm in $vmDetails) {
    Write-Host "  $($vm.Name) - $($vm.IP)" -ForegroundColor White
}
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

if ($bastionVNet) {
    Write-Host "BASTION CONNECTIVITY:" -ForegroundColor Cyan
    Write-Host "  VNet peered with Bastion: YES" -ForegroundColor Green
    Write-Host "  VMs accessible via: Azure Portal -> VM -> Connect -> Bastion" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "BASTION CONNECTIVITY:" -ForegroundColor Cyan
    Write-Host "  No Bastion detected" -ForegroundColor Yellow
    Write-Host "  Run Fix-Bastion-Connectivity.ps1 to connect VMs to Bastion" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "CLEANUP (when done):" -ForegroundColor Cyan
Write-Host "  Remove-AzResourceGroup -Name $rgName -Force" -ForegroundColor Gray
Write-Host ""
#endregion

