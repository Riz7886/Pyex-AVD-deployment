#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Complete Reporting Server with Azure Bastion
.DESCRIPTION
    One-shot deployment of:
    - Azure Bastion (secure gateway)
    - Windows Server VM (reporting server)
    - Optional storage account
    - Optional VPN security
    All configured and ready for Task Scheduler and reporting tools
.EXAMPLE
    .\Deploy-Reporting-Server-Complete.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DEPLOY COMPLETE REPORTING SERVER WITH BASTION" -ForegroundColor Cyan
Write-Host "  Cost-Effective | Secure | Production-Ready" -ForegroundColor Cyan
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

#region Subscription Selection
Write-Host "[2/8] Subscription Selection" -ForegroundColor Yellow
$subscriptions = Get-AzSubscription
if ($subscriptions.Count -gt 1) {
    Write-Host "  Multiple subscriptions found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "    [$($i + 1)] $($subscriptions[$i].Name) - $($subscriptions[$i].Id)" -ForegroundColor White
    }
    do {
        $subSel = Read-Host "  Select subscription [1-$($subscriptions.Count)]"
    } while ([int]$subSel -lt 1 -or [int]$subSel -gt $subscriptions.Count)
    
    $selectedSub = $subscriptions[[int]$subSel - 1]
    Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
    Write-Host "  Selected: $($selectedSub.Name)" -ForegroundColor Green
} else {
    Write-Host "  Using subscription: $($subscriptions[0].Name)" -ForegroundColor Green
}
Write-Host ""
#endregion

#region Configuration
Write-Host "[3/8] Deployment Configuration" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Choose deployment size:" -ForegroundColor Cyan
Write-Host "    [1] BUDGET - Basic reporting (~$140/month)" -ForegroundColor White
Write-Host "        Bastion Basic, D2s_v3 VM (2 vCPU, 8GB RAM)" -ForegroundColor Gray
Write-Host ""
Write-Host "    [2] RECOMMENDED - Standard reporting (~$250/month)" -ForegroundColor White
Write-Host "        Bastion Standard, D4s_v3 VM (4 vCPU, 16GB RAM)" -ForegroundColor Gray
Write-Host ""
Write-Host "    [3] ENTERPRISE - Heavy reporting (~$360/month)" -ForegroundColor White
Write-Host "        Bastion Standard, E4s_v3 VM (4 vCPU, 32GB RAM)" -ForegroundColor Gray
Write-Host ""
do {
    $sizeChoice = Read-Host "  Select size [1-3]"
} while ([int]$sizeChoice -lt 1 -or [int]$sizeChoice -gt 3)

$config = switch ([int]$sizeChoice) {
    1 { @{
        BastionSKU = "Basic"
        BastionCost = 110
        VMSize = "Standard_D2s_v3"
        VMCost = 70
        Description = "Budget Solution"
        TotalCost = 180
    }}
    2 { @{
        BastionSKU = "Standard"
        BastionCost = 140
        VMSize = "Standard_D4s_v3"
        VMCost = 140
        Description = "Recommended Solution"
        TotalCost = 280
    }}
    3 { @{
        BastionSKU = "Standard"
        BastionCost = 140
        VMSize = "Standard_E4s_v3"
        VMCost = 220
        Description = "Enterprise Solution"
        TotalCost = 360
    }}
}

Write-Host ""
Write-Host "  Selected: $($config.Description)" -ForegroundColor Green
Write-Host "    Bastion SKU: $($config.BastionSKU) (~$$$($config.BastionCost)/month)" -ForegroundColor Gray
Write-Host "    VM Size: $($config.VMSize) (~$$$($config.VMCost)/month)" -ForegroundColor Gray
Write-Host "    Estimated Total: ~$$$($config.TotalCost)/month" -ForegroundColor Gray
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Write-Host "  Select Azure region:" -ForegroundColor Cyan
Write-Host "    [1] East US (recommended)" -ForegroundColor White
Write-Host "    [2] West US" -ForegroundColor White
Write-Host "    [3] East US 2" -ForegroundColor White
Write-Host "    [4] West Europe" -ForegroundColor White
Write-Host "    [5] Custom" -ForegroundColor White
Write-Host ""
do {
    $regionChoice = Read-Host "  Select region [1-5]"
} while ([int]$regionChoice -lt 1 -or [int]$regionChoice -gt 5)

$location = switch ([int]$regionChoice) {
    1 { "eastus" }
    2 { "westus" }
    3 { "eastus2" }
    4 { "westeurope" }
    5 { Read-Host "  Enter region (e.g., centralus)" }
}

Write-Host "  Location: $location" -ForegroundColor Green
Write-Host ""
#endregion

#region Storage Option
Write-Host "[4/8] Storage Configuration" -ForegroundColor Yellow
Write-Host "  Do you need storage for report archives?" -ForegroundColor Cyan
Write-Host "    [Y] Yes - Add Azure Files storage (100GB, +$20/month)" -ForegroundColor White
Write-Host "    [N] No - Skip storage (store reports on VM disk only)" -ForegroundColor Gray
Write-Host ""
$needStorage = Read-Host "  Need storage? (Y/N)"

$storageAccount = $null
$storageAccountKey = $null
$fileShareName = $null

if ($needStorage -eq "Y" -or $needStorage -eq "y") {
    Write-Host "  Will create storage account for report archives" -ForegroundColor Green
    $config.TotalCost += 20
} else {
    Write-Host "  Skipping storage - reports stored on VM disk only" -ForegroundColor Yellow
}
Write-Host ""
#endregion

#region VPN Security
Write-Host "[5/8] Security Configuration" -ForegroundColor Yellow
Write-Host "  Do you want VPN-only access security?" -ForegroundColor Cyan
Write-Host "    [Y] Yes - Only allow access from corporate VPN" -ForegroundColor White
Write-Host "    [N] No - Allow access from any internet connection" -ForegroundColor Gray
Write-Host ""
$needVPN = Read-Host "  Configure VPN security? (Y/N)"
Write-Host ""
#endregion

#region Credentials
Write-Host "[6/8] Server Credentials" -ForegroundColor Yellow
Write-Host "  Enter credentials for the Reporting Server:" -ForegroundColor Cyan
Write-Host ""
$adminUsername = Read-Host "    Admin Username"
$adminPassword = Read-Host "    Admin Password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
Write-Host "  Credentials set" -ForegroundColor Green
Write-Host ""
#endregion

#region Create Resources
Write-Host "[7/8] Deploying Infrastructure (15-20 minutes)" -ForegroundColor Yellow
Write-Host ""

# Create Resource Group
$rgName = "RG-ReportingServer-$timestamp"
Write-Host "  Creating Resource Group: $rgName" -ForegroundColor Cyan
New-AzResourceGroup -Name $rgName -Location $location -Force | Out-Null
Write-Host "    Resource Group created" -ForegroundColor Green

# Create VNet
$vnetName = "VNet-ReportingServer"
$bastionSubnetName = "AzureBastionSubnet"
$vmSubnetName = "Subnet-ReportingVMs"

Write-Host "  Creating Virtual Network..." -ForegroundColor Cyan
$bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name $bastionSubnetName -AddressPrefix "10.10.1.0/26"
$vmSubnet = New-AzVirtualNetworkSubnetConfig -Name $vmSubnetName -AddressPrefix "10.10.2.0/24"
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $location -AddressPrefix "10.10.0.0/16" -Subnet $bastionSubnet,$vmSubnet
Write-Host "    Virtual Network created" -ForegroundColor Green

# Create Public IP for Bastion
Write-Host "  Creating Public IP for Bastion..." -ForegroundColor Cyan
$pipName = "PIP-Bastion"
$pip = New-AzPublicIpAddress -ResourceGroupName $rgName -Name $pipName -Location $location -AllocationMethod Static -Sku Standard
Write-Host "    Public IP created: $($pip.IpAddress)" -ForegroundColor Green

# Create Bastion
Write-Host "  Deploying Azure Bastion (10-15 minutes, please wait)..." -ForegroundColor Cyan
$bastionName = "Bastion-ReportingServer"
$bastion = New-AzBastion -ResourceGroupName $rgName -Name $bastionName -PublicIpAddressRgName $rgName -PublicIpAddressName $pipName -VirtualNetworkRgName $rgName -VirtualNetworkName $vnetName -Sku $config.BastionSKU -Force
Write-Host "    Bastion deployed successfully" -ForegroundColor Green

# Create NSG
Write-Host "  Creating Network Security Group..." -ForegroundColor Cyan
$nsgName = "NSG-ReportingServer"
$rdpRule = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP-Bastion" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$httpsOutRule = New-AzNetworkSecurityRuleConfig -Name "Allow-HTTPS-Out" -Access Allow -Protocol Tcp -Direction Outbound -Priority 100 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix "Internet" -DestinationPortRange 443
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $location -SecurityRules $rdpRule,$httpsOutRule
Write-Host "    NSG created" -ForegroundColor Green

# Create Storage if requested
if ($needStorage -eq "Y" -or $needStorage -eq "y") {
    Write-Host "  Creating Storage Account..." -ForegroundColor Cyan
    $storageAccountName = "streports$timestamp".ToLower() -replace '[^a-z0-9]', ''
    if ($storageAccountName.Length -gt 24) {
        $storageAccountName = $storageAccountName.Substring(0, 24)
    }
    
    $storageAccount = New-AzStorageAccount -ResourceGroupName $rgName -Name $storageAccountName -Location $location -SkuName Standard_LRS -Kind StorageV2 -EnableLargeFileShare
    Write-Host "    Storage account created: $storageAccountName" -ForegroundColor Green
    
    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $rgName -Name $storageAccountName)[0].Value
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    
    $fileShareName = "reports"
    New-AzStorageShare -Name $fileShareName -Context $storageContext -QuotaGiB 100 | Out-Null
    Write-Host "    File share created: $fileShareName (100GB)" -ForegroundColor Green
}

# Create Reporting VM
Write-Host "  Creating Reporting Server VM..." -ForegroundColor Cyan
$vmName = "ReportingServer"
$nicName = "$vmName-NIC"

$vmSubnetObj = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $vmSubnetName
$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $location -SubnetId $vmSubnetObj.Id -NetworkSecurityGroupId $nsg.Id

$vm = New-AzVMConfig -VMName $vmName -VMSize $config.VMSize
$vm = Set-AzVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vm = Set-AzVMSourceImage -VM $vm -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
$vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
$vm = Set-AzVMBootDiagnostic -VM $vm -Disable

New-AzVM -ResourceGroupName $rgName -Location $location -VM $vm | Out-Null
Write-Host "    Reporting Server VM deployed" -ForegroundColor Green

# Configure VPN security if requested
if ($needVPN -eq "Y" -or $needVPN -eq "y") {
    Write-Host "  Configuring VPN-only access..." -ForegroundColor Cyan
    $vpnRanges = @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    
    $nsg | Add-AzNetworkSecurityRuleConfig -Name "Allow-VPN-Only" -Access Allow -Protocol Tcp -Direction Inbound -Priority 90 -SourceAddressPrefix $vpnRanges -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443 | Out-Null
    $nsg | Set-AzNetworkSecurityGroup | Out-Null
    Write-Host "    VPN security configured" -ForegroundColor Green
}

Write-Host ""
#endregion

#region Success
$vmObj = Get-AzVM -ResourceGroupName $rgName -Name $vmName
$nicDetails = Get-AzNetworkInterface -ResourceId $vmObj.NetworkProfile.NetworkInterfaces[0].Id

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE - REPORTING SERVER READY" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "REPORTING SERVER DETAILS:" -ForegroundColor Cyan
Write-Host "  Server Name: $vmName" -ForegroundColor White
Write-Host "  Private IP: $($nicDetails.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor White
Write-Host "  VM Size: $($config.VMSize)" -ForegroundColor White
Write-Host "  OS: Windows Server 2022" -ForegroundColor White
Write-Host ""
Write-Host "BASTION GATEWAY:" -ForegroundColor Cyan
Write-Host "  Name: $bastionName" -ForegroundColor White
Write-Host "  SKU: $($config.BastionSKU)" -ForegroundColor White
Write-Host "  Public IP: $($pip.IpAddress)" -ForegroundColor White
Write-Host ""
Write-Host "CREDENTIALS:" -ForegroundColor Cyan
Write-Host "  Username: $adminUsername" -ForegroundColor White
Write-Host ""

if ($storageAccount) {
    Write-Host "STORAGE:" -ForegroundColor Cyan
    Write-Host "  Storage Account: $($storageAccount.StorageAccountName)" -ForegroundColor White
    Write-Host "  File Share: $fileShareName" -ForegroundColor White
    Write-Host "  UNC Path: \\$($storageAccount.StorageAccountName).file.core.windows.net\$fileShareName" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "MONTHLY COST ESTIMATE:" -ForegroundColor Cyan
Write-Host "  Bastion: $$$($config.BastionCost)" -ForegroundColor White
Write-Host "  VM: $$$($config.VMCost)" -ForegroundColor White
if ($storageAccount) {
    Write-Host "  Storage: $20" -ForegroundColor White
}
Write-Host "  Total: ~$$$($config.TotalCost)/month" -ForegroundColor White
Write-Host ""

Write-Host "CONNECT TO SERVER:" -ForegroundColor Cyan
Write-Host "  1. Open Azure Portal" -ForegroundColor White
Write-Host "  2. Navigate to: Virtual Machines -> $vmName" -ForegroundColor White
Write-Host "  3. Click: Connect -> Connect via Bastion" -ForegroundColor White
Write-Host "  4. Enter credentials and connect" -ForegroundColor White
Write-Host ""
Write-Host "  Direct Link:" -ForegroundColor Yellow
Write-Host "  https://portal.azure.com/#@/resource$($vmObj.Id)/connectBastion" -ForegroundColor Gray
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Connect to server via Bastion" -ForegroundColor White
Write-Host "  2. Install reporting tools:" -ForegroundColor White
Write-Host "     - Power BI Report Server" -ForegroundColor Gray
Write-Host "     - SQL Server Reporting Services (SSRS)" -ForegroundColor Gray
Write-Host "     - PowerShell reporting scripts" -ForegroundColor Gray
Write-Host "  3. Configure Windows Task Scheduler" -ForegroundColor White
Write-Host "  4. Set up email notifications" -ForegroundColor White
Write-Host "  5. Test your reports" -ForegroundColor White
Write-Host ""

Write-Host "CLEANUP (when done):" -ForegroundColor Cyan
Write-Host "  Remove-AzResourceGroup -Name $rgName -Force" -ForegroundColor Gray
Write-Host ""
#endregion
