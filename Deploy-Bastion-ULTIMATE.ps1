#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Azure Bastion with PyxHealth naming convention
.DESCRIPTION
    100% automated Azure Bastion deployment with Standard SKU
    PyxHealth naming: PH{Region}{ResourceType}
.EXAMPLE
    .\Deploy-Bastion-ULTIMATE.ps1
    .\Deploy-Bastion-ULTIMATE.ps1 -Location eastus -BastionSKU Basic -Force
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region")]
    [ValidateSet("centralus", "eastus", "westus", "eastus2", "westus2")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="Bastion SKU")]
    [ValidateSet("Basic", "Standard")]
    [string]$BastionSKU = "Standard",
    
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
    $modules = @("Az.Accounts", "Az.Resources", "Az.Network")
    
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
    BastionSubnet = "AzureBastionSubnet"
    Bastion = "$regionPrefix-BAS-Hub"
    BastionPIP = "$regionPrefix-PIP-Bastion"
}

$costEstimate = @{
    Basic = 140
    Standard = 140
}
#endregion

#region Display Configuration
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         PyxHealth Azure Bastion Deployment (ULTIMATE)       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "DEPLOYMENT CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  Region: $Location" -ForegroundColor White
Write-Host "  Naming Prefix: $regionPrefix" -ForegroundColor White
Write-Host "  Bastion SKU: $BastionSKU" -ForegroundColor White
Write-Host "  Monthly Cost: `$$($costEstimate[$BastionSKU])" -ForegroundColor Green
Write-Host ""
Write-Host "RESOURCE NAMES (PyxHealth Convention):" -ForegroundColor Yellow
Write-Host "  Resource Group: $($namingConfig.ResourceGroup)" -ForegroundColor White
Write-Host "  VNet: $($namingConfig.VNet)" -ForegroundColor White
Write-Host "  Bastion: $($namingConfig.Bastion)" -ForegroundColor White
Write-Host "  Public IP: $($namingConfig.BastionPIP)" -ForegroundColor White
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
            Purpose = "Bastion"
            Company = "PyxHealth"
        }
    }
    Write-ColorOutput "Resource Group ready" "SUCCESS"
    
    # Step 2: Virtual Network
    Write-ColorOutput "Creating Virtual Network: $($namingConfig.VNet)" "INFO"
    $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig `
        -Name $namingConfig.BastionSubnet `
        -AddressPrefix "10.0.1.0/26"
    
    $vnet = Get-AzVirtualNetwork -Name $namingConfig.VNet -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$vnet) {
        $vnet = New-AzVirtualNetwork `
            -Name $namingConfig.VNet `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -AddressPrefix "10.0.0.0/16" `
            -Subnet $bastionSubnetConfig `
            -Tag @{ Purpose = "Hub-Network"; Company = "PyxHealth" }
    }
    Write-ColorOutput "Virtual Network ready" "SUCCESS"
    
    # Step 3: Public IP
    Write-ColorOutput "Creating Bastion Public IP: $($namingConfig.BastionPIP)" "INFO"
    $pip = Get-AzPublicIpAddress -Name $namingConfig.BastionPIP -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$pip) {
        $pip = New-AzPublicIpAddress `
            -Name $namingConfig.BastionPIP `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -Location $Location `
            -AllocationMethod Static `
            -Sku Standard `
            -Tag @{ Purpose = "Bastion-Gateway"; Company = "PyxHealth" }
    }
    Write-ColorOutput "Public IP ready" "SUCCESS"
    
    # Step 4: Azure Bastion
    Write-ColorOutput "Deploying Azure Bastion: $($namingConfig.Bastion)" "INFO"
    Write-ColorOutput "This takes 10-15 minutes..." "WARNING"
    
    $bastion = Get-AzBastion -Name $namingConfig.Bastion -ResourceGroupName $namingConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (!$bastion) {
        $bastion = New-AzBastion `
            -Name $namingConfig.Bastion `
            -ResourceGroupName $namingConfig.ResourceGroup `
            -PublicIpAddress $pip `
            -VirtualNetwork $vnet `
            -Sku $BastionSKU `
            -Tag @{
                Environment = "Production"
                Purpose = "Secure-Access"
                Company = "PyxHealth"
                SKU = $BastionSKU
            }
    }
    Write-ColorOutput "Bastion deployed successfully" "SUCCESS"
    
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
    Write-Host "  SKU: $BastionSKU" -ForegroundColor White
    Write-Host "  Monthly Cost: `$$($costEstimate[$BastionSKU])" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Deploy VMs to connect via Bastion" -ForegroundColor White
    Write-Host "  2. Use Deploy-2-Windows-VMs-For-Bastion.ps1" -ForegroundColor White
    Write-Host "  3. Or use Deploy-Multiple-VMs-ULTIMATE.ps1" -ForegroundColor White
    Write-Host ""
    
    Write-ColorOutput "Deployment completed successfully!" "SUCCESS"
    
} catch {
    Write-ColorOutput "DEPLOYMENT FAILED: $($_.Exception.Message)" "ERROR"
    exit 1
}
#endregion

