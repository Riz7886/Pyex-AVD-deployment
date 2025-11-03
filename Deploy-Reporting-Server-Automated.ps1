#Requires -Version 5.1
param(
    [string]$Location = "centralus",
    [string]$VMSize = "Standard_D4s_v3"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $colors = @{"INFO"="Cyan"; "SUCCESS"="Green"; "WARNING"="Yellow"; "ERROR"="Red"}
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" -ForegroundColor $colors[$Type]
}

$prefixes = @{"centralus"="PHC"; "eastus"="PHE"; "westus"="PHW"}
$prefix = $prefixes[$Location]
$rgName = "$prefix-RG-Reporting"
$vnetName = "$prefix-VNET-Reporting"
$vmName = "$prefix-VM-ReportSvr01"
$bastionName = "$prefix-BAS-Reporting"

Write-Host ""
Write-Host "PyxHealth Reporting Server Deploy" -ForegroundColor Cyan
Write-Host "Region: $Location ($prefix)" -ForegroundColor White
Write-Host "VM Size: $VMSize" -ForegroundColor White
Write-Host ""

try {
    Write-Log "Installing modules..." "INFO"
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Network")
    foreach ($m in $modules) {
        if (-not (Get-Module -Name $m -ListAvailable)) {
            Install-Module -Name $m -Force -AllowClobber -Scope CurrentUser | Out-Null
        }
        Import-Module $m
    }
    Write-Log "Modules ready" "SUCCESS"
    
    Write-Log "Connecting to Azure..." "INFO"
    if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Connect-AzAccount | Out-Null
    }
    Write-Log "Connected" "SUCCESS"
    
    Write-Log "Creating Resource Group..." "INFO"
    if (-not (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $rgName -Location $Location | Out-Null
    }
    Write-Log "Resource Group ready" "SUCCESS"
    
    Write-Log "Creating VNet..." "INFO"
    $bastionSubnet = New-AzVirtualNetworkSubnetConfig -Name "AzureBastionSubnet" -AddressPrefix "10.0.1.0/26"
    $vmSubnet = New-AzVirtualNetworkSubnetConfig -Name "$prefix-SNET-VMs" -AddressPrefix "10.0.2.0/24"
    
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vnet) {
        $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $bastionSubnet,$vmSubnet
    }
    Write-Log "VNet ready" "SUCCESS"
    
    Write-Log "Creating Public IP..." "INFO"
    $pipName = "$prefix-PIP-Bastion"
    $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $pip) {
        $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static -Sku Standard
    }
    Write-Log "Public IP ready" "SUCCESS"
    
    Write-Log "Deploying Bastion (10-15 min)..." "WARNING"
    $bastion = Get-AzBastion -Name $bastionName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $bastion) {
        $bastion = New-AzBastion -Name $bastionName -ResourceGroupName $rgName -PublicIpAddress $pip -VirtualNetwork $vnet -Sku Standard
    }
    Write-Log "Bastion ready" "SUCCESS"
    
    Write-Host ""
    Write-Host "Enter VM Admin Username (default: pyxadmin):" -ForegroundColor Yellow
    $username = Read-Host
    if ([string]::IsNullOrWhiteSpace($username)) { $username = "pyxadmin" }
    $password = Read-Host "Enter VM Password" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential($username, $password)
    
    Write-Log "Creating VM..." "INFO"
    $nicName = "$prefix-NIC-ReportSvr01"
    $vmSubnetObj = $vnet.Subnets | Where-Object {$_.Name -eq "$prefix-SNET-VMs"}
    
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $nic) {
        $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $vmSubnetObj.Id
    }
    
    $vm = Get-AzVM -Name $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent
        $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest"
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "$prefix-DISK-ReportSvr01-OS" -CreateOption FromImage
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
        
        $vm = New-AzVM -ResourceGroupName $rgName -Location $Location -VM $vmConfig
    }
    Write-Log "VM ready" "SUCCESS"
    
    Write-Host ""
    Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resource Group: $rgName" -ForegroundColor White
    Write-Host "VM: $vmName" -ForegroundColor White
    Write-Host "Bastion: $bastionName" -ForegroundColor White
    Write-Host "Username: $username" -ForegroundColor White
    Write-Host ""
    Write-Host "Connect via: Azure Portal > VM > Bastion" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
