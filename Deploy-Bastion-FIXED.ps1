#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Azure Bastion with PyxHealth naming
.EXAMPLE
    .\Deploy-Bastion-FIXED.ps1
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region")]
    [ValidateSet("centralus", "eastus", "westus")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="Skip prompts")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

$prefixes = @{ "centralus" = "PHC"; "eastus" = "PHE"; "westus" = "PHW" }
$prefix = $prefixes[$Location]
$rgName = "$prefix-RG-Bastion"
$vnetName = "$prefix-VNET-Hub"
$bastionName = "$prefix-BAS-Hub"

Write-Host ""
Write-Host "=== PyxHealth Bastion Deploy ===" -ForegroundColor Cyan
Write-Host "Region: $Location ($prefix)" -ForegroundColor White
Write-Host ""

if (-not $Force) {
    $c = Read-Host "Deploy? (Y/N)"
    if ($c -ne "Y") { exit 0 }
}

try {
    Write-Log "Installing modules..." "Cyan"
    foreach ($m in @("Az.Accounts", "Az.Resources", "Az.Network")) {
        if (-not (Get-Module $m -ListAvailable)) {
            Install-Module $m -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module $m
    }
    
    Write-Log "Connecting to Azure..." "Cyan"
    if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Connect-AzAccount | Out-Null
    }
    
    Write-Log "Creating Resource Group..." "Cyan"
    if (-not (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $rgName -Location $Location | Out-Null
    }
    
    Write-Log "Creating VNet..." "Cyan"
    $subnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $subnet
    }
    
    Write-Log "Creating Public IP..." "Cyan"
    $pipName = "$prefix-PIP-Bastion"
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static -Sku Standard
    }
    
    Write-Log "Deploying Bastion (10-15 min)..." "Yellow"
    if (-not (Get-AzBastion -Name $bastionName -ResourceGroupName $rgName -ErrorAction SilentlyContinue)) {
        New-AzBastion -Name $bastionName -ResourceGroupName $rgName -PublicIpAddress $pip -VirtualNetwork $vnet -Sku Standard | Out-Null
    }
    
    Write-Host ""
    Write-Host "=== DEPLOYMENT COMPLETE ===" -ForegroundColor Green
    Write-Host "Bastion: $bastionName" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
