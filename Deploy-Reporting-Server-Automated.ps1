#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy PyxHealth Reporting Server - 100% Automated
.DESCRIPTION
    Fully automated deployment with PyxHealth naming
    Only prompts: Azure login + VM password (Azure requirement)
.EXAMPLE
    .\Deploy-Reporting-Server-Automated.ps1
    .\Deploy-Reporting-Server-Automated.ps1 -Location eastus
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Azure region")]
    [ValidateSet("centralus", "eastus", "westus", "eastus2", "westus2")]
    [string]$Location = "centralus",
    
    [Parameter(HelpMessage="VM size")]
    [ValidateSet("Standard_D2s_v3", "Standard_D4s_v3", "Standard_E4s_v3")]
    [string]$VMSize = "Standard_D4s_v3"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $colors = @{ "INFO" = "Cyan"; "SUCCESS" = "Green"; "WARNING" = "Yellow"; "ERROR" = "Red" }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $colors[$Type]
}

$prefixes = @{ "centralus" = "PHC"; "eastus" = "PHE"; "westus" = "PHW"; "eastus2" = "PHE2"; "westus2" = "PHW2" }
$prefix = $prefixes[$Location]

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PyxHealth Reporting Server - Automated Deploy    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Region: $Location ($prefix)" -ForegroundColor White
Write-Host "  VM Size: $VMSize" -ForegroundColor White
Write-Host "  Monthly Cost: ~`$280" -ForegroundColor Green
Write-Host ""

try {
    Write-Log "Installing Azure modules..." "INFO"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
    foreach ($m in $modules) {
        if (-not (Get-Module -Name $m -ListAvailable)) {
            Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser -Repository PSGallery | Out-Null
        }
        Import-Module $m -ErrorAction SilentlyContinue
    }
    Write-Log "Modules ready" "SUCCESS"
    
    Write-Log "Connecting to Azure..." "INFO"
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Connect-AzAccount | Out-Null
        $ctx = Get-AzContext
    }
    Write-Log "Connected as: $($ctx.Account.Id)" "SUCCESS"
    
    $subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    if ($subs.Count -gt 1) {
        Write-Host "`nMultiple subscriptions found:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $subs.Count; $i++) {
            Write-Host "  [$($i+1)] $($subs[$i].Name)" -ForegroundColor White
        }
        $sel = Read-Host "`nSelect subscription (1-$($subs.Count))"
        Set-AzContext -SubscriptionId $subs[[int]$sel - 1].Id | Out-Null
    }
    
    $rgName = "$prefix-RG-Reporting"
    $vnetName = "$prefix-VNET-Reporting"
    $vmName = "$prefix-VM-ReportSvr01"
    $bastionName = "$prefix-BAS-Reporting"
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Starting Deployment" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Creating Resource Group: $rgName" "INFO"
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    if (-not $rg) {
        $rg = New-AzResourceGroup -Name $rgName -Location $Location -Tag @{ Company = "PyxHealth"; Purpose = "Reporting" }
    }
    Write-Log "Resource Group ready" "SUCCESS"
    
    Write-Log "Creating Virtual Network: $vnetName" "INFO"
    $bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $vmSubnet = New-AzVirtualNetworkSubnetConfig -Name "$prefix-SNET-ReportingVMs" -AddressPrefix "10.0.2.0/24"
    
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location `
            -AddressPrefix "10.0.0.0/16" -Subnet $bastionSubnet,$vmSubnet `
            -Tag @{ Company = "PyxHealth"; Purpose = "Reporting-Network" }
    }
    Write-Log "VNet ready" "SUCCESS"
    
    Write-Log "Creating Bastion Public IP..." "INFO"
    $pipName = "$prefix-PIP-Bastion"
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $Location `
            -AllocationMethod Static -Sku Standard -Tag @{ Company = "PyxHealth" }
    }
    Write-Log "Public IP ready" "SUCCESS"
    
    Write-Log "Deploying Azure Bastion (10-15 minutes)..." "WARNING"
    $bastion = Get-AzBastion -Name $bastionName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $bastion) {
        $bastion = New-AzBastion -Name $bastionName -ResourceGroupName $rgName `
            -PublicIpAddress $pip -VirtualNetwork $vnet -Sku Standard `
            -Tag @{ Company = "PyxHealth"; Purpose = "Secure-Access" }
    }
    Write-Log "Bastion deployed" "SUCCESS"
    
    Write-Host ""
    Write-Host "Enter VM Administrator Credentials:" -ForegroundColor Yellow
    Write-Host "(Username default: pyxadmin)" -ForegroundColor Gray
    $username = Read-Host "Username"
    if ([string]::IsNullOrWhiteSpace($username)) { $username = "pyxadmin" }
    $password = Read-Host "Password" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential($username, $password)
    
    Write-Log "Creating VM: $vmName" "INFO"
    $nicName = "$prefix-NIC-ReportSvr01"
    $vmSubnetObj = $vnet.Subnets | Where-Object { $_.Name -eq "$prefix-SNET-ReportingVMs" }
    
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location `
            -SubnetId $vmSubnetObj.Id -Tag @{ Company = "PyxHealth" }
    }
    
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" `
            -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$prefix-DISK-ReportSvr01-OS" -CreateOption FromImage -StorageAccountType Premium_LRS
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        $vm = New-AzVM -ResourceGroupName $rgName -Location $Location -VM $vmConfig `
            -Tag @{ Company = "PyxHealth"; Purpose = "Reporting-Server"; OS = "Windows-Server-2022" }
    }
    Write-Log "VM deployed" "SUCCESS"
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║         DEPLOYMENT COMPLETED SUCCESSFULLY          ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "DEPLOYMENT SUMMARY:" -ForegroundColor Yellow
    Write-Host "  Resource Group: $rgName" -ForegroundColor White
    Write-Host "  VM: $vmName" -ForegroundColor White
    Write-Host "  Bastion: $bastionName" -ForegroundColor White
    Write-Host "  Username: $username" -ForegroundColor White
    Write-Host "  Monthly Cost: ~`$280" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Go to Azure Portal" -ForegroundColor White
    Write-Host "  2. Find VM: $vmName" -ForegroundColor White
    Write-Host "  3. Click Connect > Bastion" -ForegroundColor White
    Write-Host "  4. Enter credentials and connect" -ForegroundColor White
    Write-Host "  5. Run: Install-Reporting-Software-Automated.ps1" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
