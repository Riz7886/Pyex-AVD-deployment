#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$ResourceGroup,
  [Parameter(Mandatory=$true)][string]$Location,
  [string]$VNetName = "avd-vnet",
  [string]$SubnetName = "avd-subnet",
  [string]$StorageAccountName = "",
  [string]$KeyVaultName = "",
  [string]$AdminUsername = "avdadmin",
  [securestring]$AdminPassword,
  [ValidateSet("Standard_D4s_v5","Standard_D8s_v5","Standard_D4as_v5","Standard_D8as_v5","Standard_D2s_v5")]
  [string]$VmSize = "Standard_D4s_v5",
  [ValidateSet("Win11-Enterprise-MultiSession","Win11-Pro")]
  [string]$Image = "Win11-Enterprise-MultiSession",
  [int]$VmCount = 10,
  [string]$VmPrefix = "avd-w11",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Ensure-AzModules {
  $mods = "Az.Accounts","Az.Resources","Az.Network","Az.Compute","Az.Storage","Az.KeyVault"
  foreach($m in $mods){ if(!(Get-Module -ListAvailable -Name $m)){ Install-Module $m -Scope CurrentUser -Force -AllowClobber } ; Import-Module $m -ErrorAction SilentlyContinue }
}
Ensure-AzModules

# Login/context
if(-not (Get-AzContext)){ Connect-AzAccount | Out-Null }

# RG
if(-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)){
  New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
}

# VNet/Subnet (10.50.0.0/16 with /24 for AVD)
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if(-not $vnet){
  $sub = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.50.1.0/24"
  $vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix "10.50.0.0/16" -Subnet $sub
}else{
  if(-not ($vnet.Subnets | Where-Object Name -eq $SubnetName)){
    Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.50.1.0/24" -VirtualNetwork $vnet | Set-AzVirtualNetwork | Out-Null
  }
}

# NSG: deny RDP from internet, allow from AzureBastionSubnet only
$nsg = Get-AzNetworkSecurityGroup -Name "$($VNetName)-nsg" -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if(-not $nsg){
  $nsg = New-AzNetworkSecurityGroup -Name "$($VNetName)-nsg" -ResourceGroupName $ResourceGroup -Location $Location
  # Deny RDP from Internet
  $nsg | Add-AzNetworkSecurityRuleConfig -Name "deny-rdp-internet" -Priority 1000 -Direction Inbound -Access Deny -Protocol Tcp -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 | Set-AzNetworkSecurityGroup | Out-Null
  # Allow from AzureBastionSubnet
  $nsg | Add-AzNetworkSecurityRuleConfig -Name "allow-bastion" -Priority 100 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix "AzureBastionSubnet" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 | Set-AzNetworkSecurityGroup | Out-Null
}
# Attach NSG to subnet
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup
$subnet = $vnet.Subnets | Where-Object Name -eq $SubnetName
if($subnet.NetworkSecurityGroup -eq $null -or $subnet.NetworkSecurityGroup.Id -ne $nsg.Id){
  $subnet.NetworkSecurityGroup = $nsg
  Set-AzVirtualNetwork -VirtualNetwork $vnet | Out-Null
}

# Boot diagnostics storage (for consoles/crash dumps)
if([string]::IsNullOrWhiteSpace($StorageAccountName)){
  $StorageAccountName = ("st" + ($ResourceGroup + $Location).ToLower() + "diag") -replace "[^a-z0-9]",""
  $StorageAccountName = $StorageAccountName.Substring(0, [Math]::Min(24, $StorageAccountName.Length))
}
$st = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
if(-not $st){
  $st = New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup -SkuName Standard_LRS -Kind StorageV2 -Location $Location -EnableHttpsTrafficOnly
}

# Key Vault for password (optional)
if(-not $AdminPassword){
  if([string]::IsNullOrWhiteSpace($KeyVaultName)){
    $KeyVaultName = ("kv-" + $ResourceGroup + "-" + $Location).ToLower() -replace "[^a-z0-9-]",""
  }
  $kv = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction SilentlyContinue
  if(-not $kv){
    $kv = New-AzKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroup -Location $Location -Sku Standard
  }
  if(-not (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "avd-admin" -ErrorAction SilentlyContinue)){
    Write-Host "Enter a local admin password for VMs..." -ForegroundColor Yellow
    $pw = Read-Host -AsSecureString "Password"
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "avd-admin" -SecretValue $pw | Out-Null
  }
  $AdminPassword = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "avd-admin").SecretValue
}

# Resolve image reference
switch($Image){
  "Win11-Enterprise-MultiSession" {
    $publisher="microsoftwindowsdesktop"; $offer="windows-11"; $sku="win11-22h2-ent-multisession"
  }
  "Win11-Pro" {
    $publisher="MicrosoftWindowsDesktop"; $offer="windows-11"; $sku="win11-22h2-pro"
  }
}

# VM creation loop
for($i=1; $i -le $VmCount; $i++){
  $vmName = "{0}-{1:D2}" -f $VmPrefix, $i
  if(Get-AzVM -Name $vmName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue){ continue }

  $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $ResourceGroup -Location $Location -SubnetId (Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup).Subnets[0].Id

  $cred = New-Object System.Management.Automation.PSCredential ($AdminUsername, $AdminPassword)

  $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VmSize |
    Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate |
    Set-AzVMSourceImage -PublisherName $publisher -Offer $offer -Skus $sku -Version "latest" |
    Add-AzVMNetworkInterface -Id $nic.Id |
    Set-AzVMBootDiagnostic -Enable -ResourceGroupName $ResourceGroup -StorageAccountName $StorageAccountName

  # OS disk encryption at host and secure boot/TPM (Gen2 images support)
  $vmConfig = Set-AzVMOsDisk -VM $vmConfig -CreateOption FromImage -Cache ReadWrite -StorageAccountType Premium_LRS
  $vmConfig.SecurityProfile = New-Object -TypeName Microsoft.Azure.Management.Compute.Models.SecurityProfile
  $vmConfig.SecurityProfile.SecurityType = "TrustedLaunch"
  $vmConfig.SecurityProfile.UefiSettings = New-Object Microsoft.Azure.Management.Compute.Models.UefiSettings
  $vmConfig.SecurityProfile.UefiSettings.SecureBootEnabled = $true
  $vmConfig.SecurityProfile.UefiSettings.VTpmEnabled = $true

  Write-Host "Creating $vmName ($VmSize, $Image)..." -ForegroundColor Cyan
  New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig -Tag @{Workload="AVD";Owner="IT";Environment="Prod"} | Out-Null

  # Auto-shutdown at 7 PM local
  Set-AzVMAutoShutdown -ResourceGroupName $ResourceGroup -Name $vmName -Time 1900 -TimeZone (Get-TimeZone).Id -Enable
}

Write-Host "All VMs created." -ForegroundColor Green
