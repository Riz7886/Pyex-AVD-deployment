#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy PyxHealth Reporting Server Infrastructure
.DESCRIPTION
    Deploys Azure Bastion + Windows Server 2022 VM for reporting
    PyxHealth naming: PHC, PHE, PHW
.EXAMPLE
    .\Deploy-Reporting-Server.ps1
#>

param(
    [string]$Location = "centralus",
    [string]$VMSize = "Standard_D4s_v3"
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

$regionMap = @{
    "centralus" = "PHC"
    "eastus" = "PHE"
    "westus" = "PHW"
}

$prefix = $regionMap[$Location]
$rgName = "$prefix-RG-Reporting"
$vnetName = "$prefix-VNET-Reporting"
$vmName = "$prefix-VM-ReportSvr01"
$bastionName = "$prefix-BAS-Reporting"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " PyxHealth Reporting Server Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Region: $Location ($prefix)" -ForegroundColor White
Write-Host "VM Size: $VMSize" -ForegroundColor White
Write-Host "Monthly Cost: ~280 USD" -ForegroundColor Green
Write-Host ""

try {
    Write-Status "Installing Azure modules..." "Cyan"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
    foreach ($m in $modules) {
        if (-not (Get-Module -Name $m -ListAvailable)) {
            Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser | Out-Null
        }
        Import-Module $m -ErrorAction SilentlyContinue
    }
    Write-Status "Modules ready" "Green"
    
    Write-Status "Connecting to Azure..." "Cyan"
    if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Connect-AzAccount | Out-Null
    }
    Write-Status "Connected" "Green"
    
    Write-Status "Creating Resource Group..." "Cyan"
    if (-not (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $rgName -Location $Location | Out-Null
    }
    Write-Status "Resource Group ready" "Green"
    
    Write-Status "Creating Virtual Network..." "Cyan"
    $bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $vmSubnet = New-AzVirtualNetworkSubnetConfig -Name "Subnet-VMs" -AddressPrefix "10.0.2.0/24"
    
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $bastionSubnet,$vmSubnet
    }
    Write-Status "VNet ready" "Green"
    
    Write-Status "Creating Bastion Public IP..." "Cyan"
    $pipName = "$prefix-PIP-Bastion"
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static -Sku Standard
    }
    Write-Status "Public IP ready" "Green"
    
    Write-Status "Deploying Azure Bastion (takes 10-15 minutes)..." "Yellow"
    $bastion = Get-AzBastion -Name $bastionName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $bastion) {
        $bastion = New-AzBastion -Name $bastionName -ResourceGroupName $rgName -PublicIpAddress $pip -VirtualNetwork $vnet -Sku Standard
    }
    Write-Status "Bastion deployed" "Green"
    
    Write-Host ""
    $username = Read-Host "Enter VM Admin Username (default: pyxadmin)"
    if ([string]::IsNullOrWhiteSpace($username)) { $username = "pyxadmin" }
    $password = Read-Host "Enter VM Password" -AsSecureString
    $cred = New-Object PSCredential($username, $password)
    
    Write-Status "Creating VM..." "Cyan"
    $nicName = "$prefix-NIC-ReportSvr01"
    $vmSubnetObj = $vnet.Subnets | Where-Object {$_.Name -eq "Subnet-VMs"}
    
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $vmSubnetObj.Id
    }
    
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$prefix-DISK-OS" -CreateOption FromImage
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        $vm = New-AzVM -ResourceGroupName $rgName -Location $Location -VM $vmConfig
    }
    Write-Status "VM deployed" "Green"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resource Group: $rgName" -ForegroundColor White
    Write-Host "VM Name: $vmName" -ForegroundColor White
    Write-Host "Bastion: $bastionName" -ForegroundColor White
    Write-Host "Username: $username" -ForegroundColor White
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Go to Azure Portal" -ForegroundColor White
    Write-Host "2. Find VM: $vmName" -ForegroundColor White
    Write-Host "3. Click Connect > Bastion" -ForegroundColor White
    Write-Host "4. Run Install-Software.ps1 on the VM" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
