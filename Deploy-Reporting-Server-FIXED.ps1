#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Standalone Bastion Reporting Server with PyxHealth naming
.DESCRIPTION
    100% automated deployment with PyxHealth naming convention
.EXAMPLE
    .\Deploy-Reporting-Server-FIXED.ps1
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region")]
    [ValidateSet("centralus", "eastus", "westus")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="VM size")]
    [ValidateSet("Standard_D2s_v3", "Standard_D4s_v3", "Standard_E4s_v3")]
    [string]$VMSize = "Standard_D4s_v3",
    
    [Parameter(HelpMessage="Skip prompts")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Get-RegionPrefix {
    param([string]$Region)
    $map = @{
        "centralus" = "PHC"
        "eastus" = "PHE"
        "westus" = "PHW"
    }
    return $map[$Region]
}

$regionPrefix = Get-RegionPrefix -Region $Location
$rgName = "$regionPrefix-RG-Reporting"
$vnetName = "$regionPrefix-VNET-Reporting"
$vmName = "$regionPrefix-VM-ReportSvr01"
$bastionName = "$regionPrefix-BAS-Reporting"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  PyxHealth Reporting Server Deploy" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Region: $Location" -ForegroundColor White
Write-Host "Prefix: $regionPrefix" -ForegroundColor White
Write-Host "VM: $vmName" -ForegroundColor White
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "Deploy? (Y/N)"
    if ($confirm -ne "Y") {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit 0
    }
}

try {
    Write-ColorOutput "Installing modules..." "Cyan"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
    foreach ($m in $modules) {
        if (-not (Get-Module -Name $m -ListAvailable)) {
            Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module $m
    }
    
    Write-ColorOutput "Connecting to Azure..." "Cyan"
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    
    Write-ColorOutput "Creating Resource Group..." "Cyan"
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    if (-not $rg) {
        $rg = New-AzResourceGroup -Name $rgName -Location $Location
    }
    
    Write-ColorOutput "Creating VNet..." "Cyan"
    $bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $vmSubnet = New-AzVirtualNetworkSubnetConfig -Name "$regionPrefix-SNET-VMs" -AddressPrefix "10.0.2.0/24"
    
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $bastionSubnet,$vmSubnet
    }
    
    Write-ColorOutput "Creating Bastion Public IP..." "Cyan"
    $pipName = "$regionPrefix-PIP-Bastion"
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static -Sku Standard
    }
    
    Write-ColorOutput "Deploying Bastion (10-15 min)..." "Yellow"
    $bastion = Get-AzBastion -Name $bastionName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $bastion) {
        $bastion = New-AzBastion -Name $bastionName -ResourceGroupName $rgName -PublicIpAddress $pip -VirtualNetwork $vnet -Sku Standard
    }
    
    Write-ColorOutput "Creating VM credentials..." "Cyan"
    Write-Host "Enter VM Admin Username:" -ForegroundColor Yellow
    $username = Read-Host
    Write-Host "Enter VM Admin Password:" -ForegroundColor Yellow
    $password = Read-Host -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential($username, $password)
    
    Write-ColorOutput "Creating VM..." "Cyan"
    $nicName = "$regionPrefix-NIC-ReportSvr01"
    $vmSubnetObj = $vnet.Subnets | Where-Object { $_.Name -eq "$regionPrefix-SNET-VMs" }
    
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $vmSubnetObj.Id
    }
    
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$regionPrefix-DISK-ReportSvr01-OS" -CreateOption FromImage
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        $vm = New-AzVM -ResourceGroupName $rgName -Location $Location -VM $vmConfig
    }
    
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resource Group: $rgName" -ForegroundColor White
    Write-Host "VM: $vmName" -ForegroundColor White
    Write-Host "Bastion: $bastionName" -ForegroundColor White
    Write-Host ""
    Write-Host "Connect via Azure Portal > Bastion" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
