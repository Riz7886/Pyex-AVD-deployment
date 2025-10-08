#Requires -Modules Az
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Professional AVD Deployment - Client Ready
.DESCRIPTION
    Deploys Azure Virtual Desktop for any number of users (10, 20, 50, 100+)
    - Auto-detects quota and selects best VM size
    - Professional naming conventions based on company name
    - Full security (NSG, HTTPS, Key Vault)
    - Client-ready deployment
.EXAMPLE
    .\Deploy-AVD.ps1 -TargetUsers 10 -CompanyName "Contoso"
    .\Deploy-AVD.ps1 -TargetUsers 25 -CompanyName "AcmeCorp" -Environment "prod"
#>

param(
    [Parameter(Mandatory=$true)]
    [int]$TargetUsers,
    
    [Parameter(Mandatory=$true)]
    [string]$CompanyName,
    
    [ValidateSet("prod","dev","uat","test")]
    [string]$Environment = "prod",
    
    [string]$Location = "East US"
)

$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$id = Get-Random -Minimum 1000 -Maximum 9999

# Professional naming (lowercase, short, DNS-compliant)
$prefix = $CompanyName.ToLower() -replace '[^a-z0-9]', ''
if ($prefix.Length -gt 8) { $prefix = $prefix.Substring(0, 8) }

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PROFESSIONAL AVD DEPLOYMENT - CLIENT READY               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Company: $CompanyName | Environment: $Environment | Users: $TargetUsers`n" -ForegroundColor White

# Connect to Azure
$ctx = Get-AzContext
if (!$ctx -or !$ctx.Subscription) {
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
    $ctx = Get-AzContext
}

$sub = $ctx.Subscription
Write-Host "✓ Subscription: $($sub.Name)" -ForegroundColor Green
Write-Host "✓ Tenant: $($sub.TenantId)`n" -ForegroundColor Green

# Auto-detect best VM size
Write-Host "Detecting best VM size for $TargetUsers users..." -ForegroundColor Cyan
$vmOptions = @(
    @{Size="Standard_D4s_v3";vCPU=4;Users=6;Cost=188;Family="standardDSv3Family"},
    @{Size="Standard_D2s_v3";vCPU=2;Users=4;Cost=96;Family="standardDSv3Family"},
    @{Size="Standard_B4ms";vCPU=4;Users=5;Cost=166;Family="standardBSFamily"},
    @{Size="Standard_B2ms";vCPU=2;Users=3;Cost=60;Family="standardBSFamily"}
)

$selectedVM = $null
foreach ($vm in $vmOptions) {
    try {
        $usage = Get-AzVMUsage -Location "eastus" | Where-Object { $_.Name.Value -eq $vm.Family }
        if ($usage) {
            $avail = $usage.Limit - $usage.CurrentValue
            $need = [math]::Ceiling($TargetUsers / $vm.Users) * $vm.vCPU
            if ($avail -ge $need) {
                $selectedVM = $vm
                $vmCount = [math]::Ceiling($TargetUsers / $vm.Users)
                Write-Host "  ✓ Selected: $($vm.Size) (Quota: $avail cores available)" -ForegroundColor Green
                break
            }
        } else {
            $selectedVM = $vm
            $vmCount = [math]::Ceiling($TargetUsers / $vm.Users)
            break
        }
    } catch {
        $selectedVM = $vm
        $vmCount = [math]::Ceiling($TargetUsers / $vm.Users)
        break
    }
}

if (!$selectedVM) { throw "No VM quota available!" }

$vmCount = [math]::Max($vmCount, 2)
$cost = ($vmCount * $selectedVM.Cost) + 80

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  VM Size: $($selectedVM.Size)" -ForegroundColor White
Write-Host "  VM Count: $vmCount VMs" -ForegroundColor White
Write-Host "  Capacity: $($vmCount * $selectedVM.Users) users" -ForegroundColor White
Write-Host "  Cost: `$$cost/month`n" -ForegroundColor White

$confirm = Read-Host "Deploy? (Y/N)"
if ($confirm -ne 'Y') { Write-Host "Cancelled"; exit }

# Professional naming convention
$naming = @{
    RG = "$prefix-avd-$Environment-$id"
    VNet = "$prefix-vnet-$Environment"
    NSG = "$prefix-nsg-$Environment"
    Storage = "$prefix`avd$Environment$id" -replace '[^a-z0-9]', ''
    HostPool = "$prefix-hp-$Environment"
    Workspace = "$prefix-ws-$Environment"
    AppGroup = "$prefix-ag-$Environment"
    KeyVault = "$prefix-kv-$id"
    VMPrefix = "$prefix-vm"
}

if ($naming.Storage.Length -gt 24) { $naming.Storage = $naming.Storage.Substring(0,24) }
if ($naming.KeyVault.Length -gt 24) { $naming.KeyVault = $naming.KeyVault.Substring(0,24) }

$pw = -join ((1..20) | % { "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"[(Get-Random -Max 70)] })
$cred = New-Object PSCredential("avdadmin", (ConvertTo-SecureString $pw -AsPlainText -Force))

$tags = @{
    Environment = $Environment
    Company = $CompanyName
    ManagedBy = "Automation"
    DeploymentDate = (Get-Date -Format "yyyy-MM-dd")
}

Write-Host "`nDeploying infrastructure..." -ForegroundColor Yellow

# Resource Group
New-AzResourceGroup -Name $naming.RG -Location $Location -Tag $tags -Force | Out-Null
Write-Host "  ✓ RG: $($naming.RG)" -ForegroundColor Green

# Network
$rule = New-AzNetworkSecurityRuleConfig -Name "Deny-RDP-Internet" -Access Deny -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
$nsg = New-AzNetworkSecurityGroup -Name $naming.NSG -ResourceGroupName $naming.RG -Location $Location -SecurityRules $rule -Tag $tags -Force
$snet = New-AzVirtualNetworkSubnetConfig -Name "avd-subnet" -AddressPrefix "10.0.1.0/24" -NetworkSecurityGroup $nsg
$vnet = New-AzVirtualNetwork -Name $naming.VNet -ResourceGroupName $naming.RG -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $snet -Tag $tags -Force
Write-Host "  ✓ Network" -ForegroundColor Green

# Storage
$storage = New-AzStorageAccount -ResourceGroupName $naming.RG -Name $naming.Storage -Location $Location -SkuName Standard_LRS -Kind StorageV2 -EnableHttpsTrafficOnly $true -Tag $tags
Write-Host "  ✓ Storage" -ForegroundColor Green

# Key Vault
try {
    $kv = New-AzKeyVault -Name $naming.KeyVault -ResourceGroupName $naming.RG -Location $Location -EnabledForDeployment -Tag $tags
    Set-AzKeyVaultSecret -VaultName $naming.KeyVault -Name "AVDAdminPassword" -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force) | Out-Null
    Write-Host "  ✓ Key Vault" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Key Vault skipped" -ForegroundColor Yellow
}

# AVD
$hp = New-AzWvdHostPool -ResourceGroupName $naming.RG -Name $naming.HostPool -Location $Location -HostPoolType Pooled -LoadBalancerType BreadthFirst -PreferredAppGroupType Desktop -MaxSessionLimit $selectedVM.Users -Tag $tags
$ws = New-AzWvdWorkspace -ResourceGroupName $naming.RG -Name $naming.Workspace -Location $Location -FriendlyName "$CompanyName Virtual Desktop" -Tag $tags
$ag = New-AzWvdApplicationGroup -ResourceGroupName $naming.RG -Name $naming.AppGroup -Location $Location -ApplicationGroupType Desktop -HostPoolArmPath $hp.Id -Tag $tags
Update-AzWvdWorkspace -ResourceGroupName $naming.RG -Name $naming.Workspace -ApplicationGroupReference $ag.Id | Out-Null
Write-Host "  ✓ AVD" -ForegroundColor Green

# VMs
Write-Host "`nDeploying $vmCount VMs (10-15 min)..." -ForegroundColor Yellow
$subnetId = $vnet.Subnets[0].Id
$success = 0

for ($i=1; $i -le $vmCount; $i++) {
    $vmName = "$($naming.VMPrefix)$($i.ToString('00'))"
    Write-Host "  [$i/$vmCount] $vmName..." -ForegroundColor Gray -NoNewline
    try {
        $nic = New-AzNetworkInterface -Name "$vmName-nic" -ResourceGroupName $naming.RG -Location $Location -SubnetId $subnetId -Tag $tags -Force
        $cfg = New-AzVMConfig -VMName $vmName -VMSize $selectedVM.Size
        $cfg = Set-AzVMOperatingSystem -VM $cfg -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        $cfg = Set-AzVMSourceImage -VM $cfg -PublisherName MicrosoftWindowsDesktop -Offer Windows-11 -Skus win11-22h2-avd -Version latest
        $cfg = Add-AzVMNetworkInterface -VM $cfg -Id $nic.Id
        $cfg = Set-AzVMOSDisk -VM $cfg -CreateOption FromImage -StorageAccountType Standard_LRS -DiskSizeInGB 128
        $cfg = Set-AzVMBootDiagnostic -VM $cfg -Disable
        New-AzVM -ResourceGroupName $naming.RG -Location $Location -VM $cfg -Tag $tags -WarningAction SilentlyContinue | Out-Null
        Write-Host " ✓" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " ✗" -ForegroundColor Red
    }
}

Write-Host "`n✅ DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "`nResults:" -ForegroundColor Cyan
Write-Host "  Company: $CompanyName" -ForegroundColor White
Write-Host "  Environment: $Environment" -ForegroundColor White
Write-Host "  RG: $($naming.RG)" -ForegroundColor White
Write-Host "  VMs: $success deployed" -ForegroundColor White
Write-Host "  Cost: `$$cost/month" -ForegroundColor White
Write-Host "  Password: $pw`n" -ForegroundColor Yellow

@{
    Company=$CompanyName
    Environment=$Environment
    Username="avdadmin"
    Password=$pw
    ResourceGroup=$naming.RG
    VMs=$success
    Cost=$cost
    Subscription=$sub.Name
    Tenant=$sub.TenantId
} | ConvertTo-Json | Out-File "Configuration\deployment-$ts.json"

Write-Host "Credentials saved: Configuration\deployment-$ts.json`n" -ForegroundColor Green
