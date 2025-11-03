#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy multiple VMs with options - PyxHealth naming
.DESCRIPTION
    Deploy 1-20 Windows or Linux VMs with PyxHealth naming convention
    Advanced options for OS, size, and configuration
.EXAMPLE
    .\Deploy-Multiple-VMs-ULTIMATE.ps1
    .\Deploy-Multiple-VMs-ULTIMATE.ps1 -VMCount 5 -OSType Windows -VMSize Standard_D4s_v3 -Force
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region")]
    [ValidateSet("centralus", "eastus", "westus", "eastus2", "westus2")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="Number of VMs")]
    [ValidateRange(1, 20)]
    [int]$VMCount = 2,
    
    [Parameter(HelpMessage="OS type")]
    [ValidateSet("Windows", "Linux")]
    [string]$OSType = "Windows",
    
    [Parameter(HelpMessage="VM size")]
    [ValidateSet("Standard_D2s_v3", "Standard_D4s_v3", "Standard_E4s_v3", "Standard_B2ms")]
    [string]$VMSize = "Standard_D2s_v3",
    
    [Parameter(HelpMessage="VM purpose/role")]
    [string]$VMPurpose = "GeneralPurpose",
    
    [Parameter(HelpMessage="Skip confirmation prompts")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

#region Functions
function Write-ColorOutput {
    param([string]$Message, [string]$Type = "INFO")
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Get-RegionAbbreviation {
    param([string]$Region)
    $abbreviations = @{
        "centralus" = "PHC"
        "eastus" = "PHE"
        "westus" = "PHW"
        "eastus2" = "PHE2"
        "westus2" = "PHW2"
    }
    return $abbreviations[$Region.ToLower()]
}

function Install-RequiredModules {
    Write-ColorOutput "Checking Azure modules..." "INFO"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
    
    foreach ($module in $modules) {
        if (!(Get-Module -Name $module -ListAvailable)) {
            Write-ColorOutput "Installing $module..." "WARNING"
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
        }
        Import-Module $module -ErrorAction SilentlyContinue
    }
    Write-ColorOutput "All modules ready" "SUCCESS"
}

function Connect-AzureAccount {
    Write-ColorOutput "Connecting to Azure..." "INFO"
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $context = Get-AzContext
        }
        Write-ColorOutput "Connected as: $($context.Account.Id)" "SUCCESS"
        
        $subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
        if ($subs.Count -gt 1) {
            Write-Host "`nAvailable Subscriptions:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $subs.Count; $i++) {
                Write-Host "  [$($i+1)] $($subs[$i].Name)" -ForegroundColor White
            }
            $selection = Read-Host "`nSelect subscription (1-$($subs.Count))"
            $selectedSub = $subs[[int]$selection - 1]
            Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
            Write-ColorOutput "Using subscription: $($selectedSub.Name)" "SUCCESS"
        }
        
        return $true
    } catch {
        Write-ColorOutput "Azure connection failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
#endregion

#region Configuration
$regionPrefix = Get-RegionAbbreviation -Region $Location

$namingConfig = @{
    ResourceGroup = "$regionPrefix-RG-Bastion"
    VNet = "$regionPrefix-VNET-Hub"
    VMSubnet = "$regionPrefix-SNET-VMs"
    NSG = "$regionPrefix-NSG-VMs"
}

$osConfig = @{
    Windows = @{
        Publisher = "MicrosoftWindowsServer"
        Offer = "WindowsServer"
        Sku = "2022-datacenter-azure-edition"
        Prefix = "Win"
    }
    Linux = @{
        Publisher = "Canonical"
        Offer = "0001-com-ubuntu-server-jammy"
        Sku = "22_04-lts-gen2"
        Prefix = "Lnx"
    }
}

$selectedOS = $osConfig[$OSType]
#endregion

#region Display Configuration
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        PyxHealth Multiple VM Deployment (ULTIMATE)          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "DEPLOYMENT CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  Region: $Location" -ForegroundColor White
Write-Host "  Naming Prefix: $regionPrefix" -ForegroundColor White
Write-Host "  OS Type: $OSType" -ForegroundColor White
Write-Host "  VM Size: $VMSize" -ForegroundColor White
Write-Host "  VM Count: $VMCount" -ForegroundColor White
Write-Host "  Purpose: $VMPurpose" -ForegroundColor White
Write-Host ""
Write-Host "RESOURCE NAMES (PyxHealth Convention):" -ForegroundColor Yellow
Write-Host "  Resource Group: $($namingConfig.ResourceGroup)" -ForegroundColor White
Write-Host "  VNet: $($namingConfig.VNet)" -ForegroundColor White
Write-Host "  Subnet: $($namingConfig.VMSubnet)" -ForegroundColor White
Write-Host "  NSG: $($namingConfig.NSG)" -ForegroundColor White
Write-Host ""
Write-Host "VMs TO BE DEPLOYED:" -ForegroundColor Yellow
for ($i = 1; $i -le $VMCount; $i++) {
    Write-Host "  $regionPrefix-VM-$($selectedOS.Prefix)$($i.ToString('00'))" -ForegroundColor White
}
Write-Host ""

if (!$Force) {
    $confirm = Read-Host "Proceed with deployment? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-ColorOutput "Deployment cancelled" "WARNING"
        exit 0
    }
}
#endregion

#region Main Deployment
try {
    Install-RequiredModules
    
    if (!(Connect-AzureAccount)) {
        throw "Azure connection failed"
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  STARTING DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Get existing resources
    Write-ColorOutput "Checking existing resources..." "INFO"
    $rg = Get-AzResourceGroup -Name $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$rg) {
        Write-ColorOutput "Creating Resource Group: $($namingConfig.ResourceGroup)" "INFO"
        $rg = New-AzResourceGroup -Name $namingConfig.ResourceGroup -Location $Location -Tag @{
            Environment = "Production"
            Company = "PyxHealth"
        }
    }
    
    $vnet = Get-AzVirtualNetwork -Name $namingConfig.VNet -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$vnet) {
        Write-ColorOutput "Creating Virtual Network: $($namingConfig.VNet)" "INFO"
        $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $namingConfig.VMSubnet -AddressPrefix "10.0.2.0/24"
        $vnet = New-AzVirtualNetwork `
            -Name $namingConfig.VNet `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -AddressPrefix "10.0.0.0/16" `
            -Subnet $subnetConfig `
            -Tag @{ Purpose = "VM-Network"; Company = "PyxHealth" }
    }
    
    $vmSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $namingConfig.VMSubnet }
    if (!$vmSubnet) {
        $vnet | Add-AzVirtualNetworkSubnetConfig -Name $namingConfig.VMSubnet -AddressPrefix "10.0.2.0/24" | Set-AzVirtualNetwork | Out-Null
        $vnet = Get-AzVirtualNetwork -Name $namingConfig.VNet -ResourceGroupName $namingConfig.ResourceGroup
        $vmSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $namingConfig.VMSubnet }
    }
    Write-ColorOutput "Resources ready" "SUCCESS"
    
    # Create NSG
    Write-ColorOutput "Configuring NSG: $($namingConfig.NSG)" "INFO"
    $nsgRules = @()
    if ($OSType -eq "Windows") {
        $nsgRules += New-AzNetworkSecurityRuleConfig -Name "Allow-RDP" `
            -Protocol Tcp -Direction Inbound -Priority 100 `
            -SourceAddressPrefix "10.0.1.0/26" -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
    } else {
        $nsgRules += New-AzNetworkSecurityRuleConfig -Name "Allow-SSH" `
            -Protocol Tcp -Direction Inbound -Priority 100 `
            -SourceAddressPrefix "10.0.1.0/26" -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
    }
    
    $nsg = Get-AzNetworkSecurityGroup -Name $namingConfig.NSG -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$nsg) {
        $nsg = New-AzNetworkSecurityGroup `
            -Name $namingConfig.NSG `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -SecurityRules $nsgRules `
            -Tag @{ Purpose = "VM-Protection"; Company = "PyxHealth" }
    }
    Write-ColorOutput "NSG configured" "SUCCESS"
    
    # Get admin credentials
    Write-Host ""
    Write-Host "Enter VM Administrator Credentials:" -ForegroundColor Yellow
    $adminUsername = Read-Host "Username (default: pyxadmin)"
    if ([string]::IsNullOrWhiteSpace($adminUsername)) { $adminUsername = "pyxadmin" }
    $adminPassword = Read-Host "Password" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
    
    # Deploy VMs
    $deployedVMs = @()
    for ($i = 1; $i -le $VMCount; $i++) {
        $vmNumber = $i.ToString('00')
        $vmName = "$regionPrefix-VM-$($selectedOS.Prefix)$vmNumber"
        $nicName = "$regionPrefix-NIC-$($selectedOS.Prefix)$vmNumber"
        $osDiskName = "$regionPrefix-DISK-$($selectedOS.Prefix)$vmNumber-OS"
        
        Write-ColorOutput "Deploying VM $i of $VMCount : $vmName" "INFO"
        
        # Create NIC
        $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
        if (!$nic) {
            $nic = New-AzNetworkInterface `
                -Name $nicName `
                -ResourceGroupName $namingConfig.ResourceGroup `
                -Location $Location `
                -SubnetId $vmSubnet.Id `
                -NetworkSecurityGroupId $nsg.Id `
                -Tag @{ Purpose = "VM-Network"; Company = "PyxHealth" }
        }
        
        # Create VM
        $vm = Get-AzVM -Name $vmName -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
        if (!$vm) {
            $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
            
            if ($OSType -eq "Windows") {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName `
                    -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
            } else {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $vmName `
                    -Credential $cred -DisablePasswordAuthentication:$false
            }
            
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig `
                -PublisherName $selectedOS.Publisher `
                -Offer $selectedOS.Offer `
                -Skus $selectedOS.Sku `
                -Version "latest"
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name $osDiskName `
                -CreateOption FromImage -StorageAccountType Premium_LRS
            $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
            $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
            
            $vm = New-AzVM -ResourceGroupName $namingConfig.ResourceGroup -Location $Location -VM $vmConfig `
                -Tag @{
                    Environment = "Production"
                    Purpose = $VMPurpose
                    Company = "PyxHealth"
                    OS = $OSType
                }
            
            $deployedVMs += $vmName
        }
        Write-ColorOutput "VM $vmName deployed successfully" "SUCCESS"
    }
    
    # Deployment Summary
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              DEPLOYMENT COMPLETED SUCCESSFULLY               ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "DEPLOYMENT SUMMARY:" -ForegroundColor Yellow
    Write-Host "  Resource Group: $($namingConfig.ResourceGroup)" -ForegroundColor White
    Write-Host "  Region: $Location" -ForegroundColor White
    Write-Host "  OS Type: $OSType" -ForegroundColor White
    Write-Host "  VMs Deployed: $($deployedVMs.Count)" -ForegroundColor White
    Write-Host "  VM Size: $VMSize" -ForegroundColor White
    Write-Host "  Purpose: $VMPurpose" -ForegroundColor White
    Write-Host ""
    Write-Host "VMs DEPLOYED:" -ForegroundColor Yellow
    foreach ($vmName in $deployedVMs) {
        Write-Host "  $vmName" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "CONNECTION INFO:" -ForegroundColor Yellow
    Write-Host "  Username: $adminUsername" -ForegroundColor White
    if ($OSType -eq "Windows") {
        Write-Host "  Connect: Azure Portal > Bastion (RDP)" -ForegroundColor White
    } else {
        Write-Host "  Connect: Azure Portal > Bastion (SSH)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-ColorOutput "Deployment completed successfully!" "SUCCESS"
    
} catch {
    Write-ColorOutput "DEPLOYMENT FAILED: $($_.Exception.Message)" "ERROR"
    exit 1
}
#endregion
