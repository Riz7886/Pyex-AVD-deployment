#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Standalone Bastion Reporting Server with PyxHealth naming convention
.DESCRIPTION
    100% automated deployment with professional naming: PH{Region}{ResourceType}
    Regions: C=Central, W=West, E=East, USE=USEast, USW=USWest
.EXAMPLE
    .\Deploy-Reporting-Server-Complete.ps1
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region (centralus, eastus, westus, eastus2, westus2)")]
    [ValidateSet("centralus", "eastus", "westus", "eastus2", "westus2", "southcentralus", "northcentralus")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="VM size tier (Budget, Recommended, Enterprise)")]
    [ValidateSet("Budget", "Recommended", "Enterprise")]
    [string]$SizeTier = "Recommended",
    
    [Parameter(HelpMessage="Deploy Azure Files storage")]
    [switch]$IncludeStorage,
    
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
        "southcentralus" = "PHSC"
        "northcentralus" = "PHNC"
        "useast" = "PHUSE"
        "uswest" = "PHUSW"
    }
    return $abbreviations[$Region.ToLower()]
}

function Install-RequiredModules {
    Write-ColorOutput "Checking Azure modules..." "INFO"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network", "Az.Storage")
    
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

# PyxHealth Naming Convention
$namingConfig = @{
    ResourceGroup = "$regionPrefix-RG-Reporting"
    VNet = "$regionPrefix-VNET-Reporting"
    BastionSubnet = "AzureBastionSubnet"  # Azure required name
    VMSubnet = "$regionPrefix-SNET-ReportingVMs"
    Bastion = "$regionPrefix-BAS-Reporting"
    BastionPIP = "$regionPrefix-PIP-Bastion"
    VM = "$regionPrefix-VM-ReportSvr01"
    NIC = "$regionPrefix-NIC-ReportSvr01"
    OSDisk = "$regionPrefix-DISK-ReportSvr01-OS"
    NSG = "$regionPrefix-NSG-Reporting"
    StorageAccount = ($regionPrefix.ToLower() -replace '-','') + "strpt" + (Get-Random -Minimum 1000 -Maximum 9999)
    FileShare = "reports"
}

# VM Size Configuration
$sizeConfig = @{
    Budget = @{
        BastionSKU = "Basic"
        VMSize = "Standard_D2s_v3"
        MonthlyCost = 180
        Description = "2 vCPU, 8GB RAM - Light workloads"
    }
    Recommended = @{
        BastionSKU = "Standard"
        VMSize = "Standard_D4s_v3"
        MonthlyCost = 280
        Description = "4 vCPU, 16GB RAM - Most workloads"
    }
    Enterprise = @{
        BastionSKU = "Standard"
        VMSize = "Standard_E4s_v3"
        MonthlyCost = 360
        Description = "4 vCPU, 32GB RAM - Heavy workloads"
    }
}

$selectedConfig = $sizeConfig[$SizeTier]
#endregion

#region Display Configuration
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   PyxHealth Standalone Bastion Reporting Server Deployment  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "DEPLOYMENT CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  Region: $Location" -ForegroundColor White
Write-Host "  Naming Prefix: $regionPrefix" -ForegroundColor White
Write-Host "  Tier: $SizeTier ($($selectedConfig.Description))" -ForegroundColor White
Write-Host "  Monthly Cost: `$$($selectedConfig.MonthlyCost)" -ForegroundColor Green
Write-Host "  Bastion SKU: $($selectedConfig.BastionSKU)" -ForegroundColor White
Write-Host "  VM Size: $($selectedConfig.VMSize)" -ForegroundColor White
Write-Host ""
Write-Host "RESOURCE NAMES (PyxHealth Convention):" -ForegroundColor Yellow
Write-Host "  Resource Group: $($namingConfig.ResourceGroup)" -ForegroundColor White
Write-Host "  VNet: $($namingConfig.VNet)" -ForegroundColor White
Write-Host "  Bastion: $($namingConfig.Bastion)" -ForegroundColor White
Write-Host "  VM: $($namingConfig.VM)" -ForegroundColor White
Write-Host "  NSG: $($namingConfig.NSG)" -ForegroundColor White
if ($IncludeStorage) {
    Write-Host "  Storage: $($namingConfig.StorageAccount)" -ForegroundColor White
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
    
    # Step 1: Resource Group
    Write-ColorOutput "Creating Resource Group: $($namingConfig.ResourceGroup)" "INFO"
    $rg = Get-AzResourceGroup -Name $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$rg) {
        $rg = New-AzResourceGroup -Name $namingConfig.ResourceGroup -Location $Location -Tag @{
            Environment = "Production"
            Purpose = "Reporting"
            Company = "PyxHealth"
            ManagedBy = "Azure-Automation"
        }
    }
    Write-ColorOutput "Resource Group ready" "SUCCESS"
    
    # Step 2: Virtual Network
    Write-ColorOutput "Creating Virtual Network: $($namingConfig.VNet)" "INFO"
    $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig `
        -Name $namingConfig.BastionSubnet `
        -AddressPrefix "10.10.1.0/26"
    
    $vmSubnetConfig = New-AzVirtualNetworkSubnetConfig `
        -Name $namingConfig.VMSubnet `
        -AddressPrefix "10.10.2.0/24"
    
    $vnet = Get-AzVirtualNetwork -Name $namingConfig.VNet -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$vnet) {
        $vnet = New-AzVirtualNetwork `
            -Name $namingConfig.VNet `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -AddressPrefix "10.10.0.0/16" `
            -Subnet $bastionSubnetConfig, $vmSubnetConfig `
            -Tag @{
                Environment = "Production"
                Purpose = "Reporting"
                Company = "PyxHealth"
            }
    }
    Write-ColorOutput "Virtual Network ready" "SUCCESS"
    
    # Step 3: Network Security Group
    Write-ColorOutput "Creating NSG: $($namingConfig.NSG)" "INFO"
    $nsgRules = @(
        New-AzNetworkSecurityRuleConfig -Name "Allow-RDP-From-Bastion" `
            -Protocol Tcp -Direction Inbound -Priority 100 `
            -SourceAddressPrefix "10.10.1.0/26" -SourcePortRange * `
            -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow,
        
        New-AzNetworkSecurityRuleConfig -Name "Allow-HTTPS-Outbound" `
            -Protocol Tcp -Direction Outbound -Priority 100 `
            -SourceAddressPrefix * -SourcePortRange * `
            -DestinationAddressPrefix Internet -DestinationPortRange 443 -Access Allow,
        
        New-AzNetworkSecurityRuleConfig -Name "Allow-SMTP-Outbound" `
            -Protocol Tcp -Direction Outbound -Priority 110 `
            -SourceAddressPrefix * -SourcePortRange * `
            -DestinationAddressPrefix Internet -DestinationPortRange 25,587 -Access Allow
    )
    
    $nsg = Get-AzNetworkSecurityGroup -Name $namingConfig.NSG -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$nsg) {
        $nsg = New-AzNetworkSecurityGroup `
            -Name $namingConfig.NSG `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -SecurityRules $nsgRules `
            -Tag @{ Purpose = "Reporting-VM-Protection"; Company = "PyxHealth" }
    }
    Write-ColorOutput "NSG configured" "SUCCESS"
    
    # Step 4: Bastion Public IP
    Write-ColorOutput "Creating Bastion Public IP: $($namingConfig.BastionPIP)" "INFO"
    $bastionPIP = Get-AzPublicIpAddress -Name $namingConfig.BastionPIP -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$bastionPIP) {
        $bastionPIP = New-AzPublicIpAddress `
            -Name $namingConfig.BastionPIP `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -AllocationMethod Static `
            -Sku Standard `
            -Tag @{ Purpose = "Bastion-Gateway"; Company = "PyxHealth" }
    }
    Write-ColorOutput "Public IP ready" "SUCCESS"
    
    # Step 5: Azure Bastion
    Write-ColorOutput "Deploying Azure Bastion: $($namingConfig.Bastion) (SKU: $($selectedConfig.BastionSKU))" "INFO"
    Write-ColorOutput "This takes 10-15 minutes..." "WARNING"
    
    $bastionSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $namingConfig.BastionSubnet }
    
    $bastion = Get-AzBastion -Name $namingConfig.Bastion -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$bastion) {
        $bastion = New-AzBastion `
            -Name $namingConfig.Bastion `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -PublicIpAddress $bastionPIP `
            -VirtualNetwork $vnet `
            -Sku $selectedConfig.BastionSKU `
            -Tag @{
                Environment = "Production"
                Purpose = "Secure-Access"
                Company = "PyxHealth"
                SKU = $selectedConfig.BastionSKU
            }
    }
    Write-ColorOutput "Bastion deployed successfully" "SUCCESS"
    
    # Step 6: VM Network Interface
    Write-ColorOutput "Creating Network Interface: $($namingConfig.NIC)" "INFO"
    $vmSubnet = $vnet.Subnets | Where-Object { $_.Name -eq $namingConfig.VMSubnet }
    
    $nic = Get-AzNetworkInterface -Name $namingConfig.NIC -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$nic) {
        $nic = New-AzNetworkInterface `
            -Name $namingConfig.NIC `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -SubnetId $vmSubnet.Id `
            -NetworkSecurityGroupId $nsg.Id `
            -Tag @{ Purpose = "Reporting-Server"; Company = "PyxHealth" }
    }
    Write-ColorOutput "Network Interface ready" "SUCCESS"
    
    # Step 7: Windows Server VM
    Write-ColorOutput "Creating Reporting Server VM: $($namingConfig.VM)" "INFO"
    Write-ColorOutput "VM Size: $($selectedConfig.VMSize)" "INFO"
    
    # Get admin credentials
    Write-Host ""
    Write-Host "Enter VM Administrator Credentials:" -ForegroundColor Yellow
    $adminUsername = Read-Host "Username (default: pyxadmin)"
    if ([string]::IsNullOrWhiteSpace($adminUsername)) { $adminUsername = "pyxadmin" }
    $adminPassword = Read-Host "Password" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
    
    $vm = Get-AzVM -Name $namingConfig.VM -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$vm) {
        $vmConfig = New-AzVMConfig -VMName $namingConfig.VM -VMSize $selectedConfig.VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $namingConfig.VM `
            -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig `
            -PublisherName "MicrosoftWindowsServer" `
            -Offer "WindowsServer" `
            -Skus "2022-datacenter-azure-edition" `
            -Version "latest"
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name $namingConfig.OSDisk `
            -CreateOption FromImage -StorageAccountType Premium_LRS
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        $vm = New-AzVM -ResourceGroupName $namingConfig.ResourceGroup -Location $Location -VM $vmConfig `
            -Tag @{
                Environment = "Production"
                Purpose = "Automated-Reporting"
                Company = "PyxHealth"
                OS = "Windows-Server-2022"
                Role = "Reporting-Server"
            }
    }
    Write-ColorOutput "VM deployed successfully" "SUCCESS"
    
    # Step 8: Optional Storage
    if ($IncludeStorage) {
        Write-ColorOutput "Creating Azure Files Storage: $($namingConfig.StorageAccount)" "INFO"
        $storage = Get-AzStorageAccount -Name $namingConfig.StorageAccount -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
        if (!$storage) {
            $storage = New-AzStorageAccount `
                -Name $namingConfig.StorageAccount `
                -ResourceGroupName $namingConfig.ResourceGroup `
                -Location $Location `
                -SkuName Standard_LRS `
                -Kind StorageV2 `
                -Tag @{ Purpose = "Report-Storage"; Company = "PyxHealth" }
            
            $ctx = $storage.Context
            $share = New-AzStorageShare -Name $namingConfig.FileShare -Context $ctx
            
            Write-ColorOutput "Storage Account created: $($namingConfig.StorageAccount)" "SUCCESS"
        }
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
    Write-Host "  Bastion: $($namingConfig.Bastion)" -ForegroundColor White
    Write-Host "  VM: $($namingConfig.VM)" -ForegroundColor White
    Write-Host "  Monthly Cost: `$$($selectedConfig.MonthlyCost)" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Connect via Azure Portal > $($namingConfig.VM) > Connect > Bastion" -ForegroundColor White
    Write-Host "  2. Install reporting software (Power BI, SSRS, Python)" -ForegroundColor White
    Write-Host "  3. Configure SMTP for email delivery" -ForegroundColor White
    Write-Host "  4. Set up Task Scheduler for automation" -ForegroundColor White
    Write-Host "  5. Configure Azure Backup" -ForegroundColor White
    Write-Host ""
    Write-Host "CONNECTION INFO:" -ForegroundColor Yellow
    Write-Host "  Username: $adminUsername" -ForegroundColor White
    Write-Host "  Connect: Azure Portal > Bastion" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "Deployment completed successfully!" "SUCCESS"
    
} catch {
    Write-ColorOutput "DEPLOYMENT FAILED: $($_.Exception.Message)" "ERROR"
    Write-ColorOutput "Error details: $($_.Exception.ToString())" "ERROR"
    exit 1
}
#endregion
