#Requires -Version 5.1
<#
AVD ULTIMATE ASCII
- ASCII only. No smart quotes, no em-dashes, no Unicode.
- No backtick line continuations; uses splatting to avoid parser issues.
- Keeps your behavior: subscription menu, VM count menu (1-10), VM size menu,
  image/region resolver, quota-aware sizing, RG/VNet/NSG, FSLogix share,
  Host Pool + Desktop App Group + Workspace, optional RBAC.
#>

[CmdletBinding()]
param(
  [switch]$NonInteractiveAll,

  [ValidateSet("centralus","eastus","eastus2","westus","westus2","southcentralus","northcentralus")]
  [string]$Location = "eastus",

  [ValidateRange(1,10)]
  [int]$VmCount = 10,

  [ValidateSet("Win11-Ent-MultiSession-23H2","Win11-Ent-23H2","Win11-Ent-Single-Any")]
  [string]$Image = "Win11-Ent-MultiSession-23H2",

  [ValidateSet("Standard_D2s_v5","Standard_D4s_v5","Standard_D8s_v5","Standard_D2as_v5","Standard_D4as_v5")]
  [string]$VmSize = "Standard_D4s_v5",

  [string]$VmPrefix = "avd-w11",

  [string]$VmLocalAdminUsername = "avdadmin",
  [string]$VmLocalAdminPasswordPlain = "",

  [string]$OnPremCidr = "",
  [string]$UserGroupObjectId = "",

  [switch]$DeployFslogix,

  [switch]$FirstVmThenPrompt,

  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Color {
  param(
    [string]$Msg,
    [ValidateSet("INFO","SUCCESS","WARNING","ERROR")][string]$Type="INFO"
  )
  $c = switch($Type){
    "SUCCESS" { "Green" }
    "ERROR"   { "Red" }
    "WARNING" { "Yellow" }
    default   { "Cyan" }
  }
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $Msg" -ForegroundColor $c
}

function Get-RegionAbbrev {
  param([string]$Region)
  $m = @{
    "centralus"="PHC";"eastus"="PHE";"eastus2"="PHE2";"westus"="PHW";"westus2"="PHW2";"southcentralus"="PHSC";"northcentralus"="PHNC"
  }
  return $m[$Region.ToLower()]
}

function Ensure-Modules {
  try {
    $pg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($pg -and $pg.InstallationPolicy -ne "Trusted") { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted }
  } catch {}
  $mods = @("Az.Accounts","Az.Resources","Az.Network","Az.Compute","Az.Storage","Az.DesktopVirtualization")
  foreach ($m in $mods) {
    if (!(Get-Module -ListAvailable -Name $m)) {
      Write-Color "Installing $m..." "WARNING"
      Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
    }
    Import-Module $m -ErrorAction Stop | Out-Null
  }
  Write-Color "Modules ready" "SUCCESS"
}

function Connect-AzureAuto {
  $ctx = Get-AzContext -ErrorAction SilentlyContinue
  if ($ctx -and $ctx.Account) {
    Write-Color ("Connected as: {0}" -f $ctx.Account.Id) "SUCCESS"
    return
  }
  try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
    Write-Color ("Connected via Managed Identity: {0}" -f $ctx.Account.Id) "SUCCESS"
  } catch {
    throw "No existing Azure context and Managed Identity auth failed. Non-interactive run."
  }
}

function Get-AllEnabledSubscriptions {
  $accum = @()
  $tenants = Get-AzTenant -ErrorAction Stop
  foreach ($t in $tenants) {
    $subs = Get-AzSubscription -TenantId $t.TenantId -ErrorAction SilentlyContinue
    if ($subs) { $accum += ($subs | Where-Object { $_.State -eq "Enabled" }) }
  }
  if (-not $accum) { $accum = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } }
  $accum | Sort-Object -Property Id -Unique
}

function Show-SubscriptionsIndexed {
  param([array]$Subs)
  if (-not $Subs -or $Subs.Count -eq 0) { throw "No enabled subscriptions were found." }
  Write-Color "Enabled subscriptions across ALL tenants:" "INFO"
  for ($i=0; $i -lt $Subs.Count; $i++) {
    $idx = $i + 1
    Write-Host ("[{0}]  {1}  ({2})  Tenant: {3}" -f $idx, $Subs[$i].Name, $Subs[$i].Id, $Subs[$i].TenantId)
  }
  Write-Color ("Total enabled subscriptions: {0}" -f $Subs.Count) "SUCCESS"
}

function Parse-IndexSelection {
  param([string]$Text,[int]$Max)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $sel = ($Text.Trim() -replace '\s','')
  $parts = $sel -split ','
  $idxs = New-Object System.Collections.Generic.List[int]
  foreach ($p in $parts) {
    if ($p -match '^\d+$') {
      $v = [int]$p
      if ($v -ge 1 -and $v -le $Max) { [void]$idxs.Add($v-1) }
    } elseif ($p -match '^\d+-\d+$') {
      $a,$b = $p -split '-'
      $a = [int]$a; $b = [int]$b
      if ($a -gt $b) { $tmp=$a; $a=$b; $b=$tmp }
      for ($z=$a; $z -le $b; $z++) { if ($z -ge 1 -and $z -le $Max) { [void]$idxs.Add($z-1) } }
    }
  }
  $idxs.ToArray() | Sort-Object -Unique
}

function Force-ChooseSubscriptions {
  $all = Get-AllEnabledSubscriptions
  Show-SubscriptionsIndexed -Subs $all
  if ($PSBoundParameters.ContainsKey('NonInteractiveAll') -and $NonInteractiveAll) {
    Write-Color "NonInteractiveAll specified -> using ALL enabled subscriptions." "WARNING"
    return ,$all
  }
  while ($true) {
    $answer = Read-Host "Enter the index/indices to deploy (e.g., 2 or 1,3-5). Required"
    $idx = Parse-IndexSelection -Text $answer -Max $all.Count
    if ($idx.Count -gt 0) {
      $chosen = foreach($j in $idx){ $all[$j] }
      Write-Color ("Selected {0} subscription(s)." -f $chosen.Count) "SUCCESS"
      return ,$chosen
    }
    Write-Color "Invalid or empty selection. Please try again." "ERROR"
  }
}

function New-RandomPassword {
  param([int]$len=28)
  $sets = @((48..57),(65..90),(97..122),(33,35,36,37,38,42,43,45,61,63,64))
  $chars = @()
  foreach ($s in $sets) { $chars += [char]($s | Get-Random) }
  while ($chars.Count -lt $len) { $chars += [char](($sets | Get-Random) | Get-Random) }
  -join ($chars | Sort-Object {Get-Random})
}

function New-CredFromPlain {
  param([string]$User,[string]$PassPlain)
  if ([string]::IsNullOrWhiteSpace($PassPlain)) { $PassPlain = New-RandomPassword 28 }
  $sec = ConvertTo-SecureString -String $PassPlain -AsPlainText -Force
  @{ Cred = (New-Object System.Management.Automation.PSCredential($User,$sec)); Plain = $PassPlain }
}

function Ensure-ResourceGroup {
  param([string]$Name,[string]$Loc)
  $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
  if (-not $rg) {
    $rgParams = @{
      Name = $Name
      Location = $Loc
      Tag = @{Company="PyxHealth";Workload="AVD";Env="Prod"}
    }
    $rg = New-AzResourceGroup @rgParams
  }
  $rg
}

function Ensure-Network {
  param([string]$Rg,[string]$Loc,[string]$VnetName,[string]$SubnetName,[string]$NsgName,[string]$OnPremCidr)

  $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $Rg -ErrorAction SilentlyContinue
  if (-not $vnet) {
    $subCfg = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.61.10.0/24"
    $vnParams = @{
      Name = $VnetName
      ResourceGroupName = $Rg
      Location = $Loc
      AddressPrefix = "10.61.0.0/16"
      Subnet = $subCfg
    }
    $vnet = New-AzVirtualNetwork @vnParams
  } else {
    if (-not ($vnet.Subnets | Where-Object Name -eq $SubnetName)) {
      $null = Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.61.10.0/24" -VirtualNetwork $vnet
      $null = Set-AzVirtualNetwork -VirtualNetwork $vnet
      $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $Rg
    }
  }

  $nsg = Get-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $Rg -ErrorAction SilentlyContinue
  if (-not $nsg) {
    $nsg = New-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $Rg -Location $Loc
    $nsg = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name "deny-rdp-internet" -Priority 1000 -Direction Inbound -Access Deny -Protocol Tcp -SourceAddressPrefix "Internet" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389
    $nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    $nsg = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name "allow-rdp-virtualnetwork" -Priority 200 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix "VirtualNetwork" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389
    $nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    if ($OnPremCidr) {
      $nsg = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name "allow-rdp-onprem" -Priority 210 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix $OnPremCidr -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389
      $nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    }
  } else {
    if ($OnPremCidr -and -not ($nsg.SecurityRules | Where-Object {$_.Name -eq "allow-rdp-onprem"})) {
      $nsg = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name "allow-rdp-onprem" -Priority 210 -Direction Inbound -Access Allow -Protocol Tcp -SourceAddressPrefix $OnPremCidr -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 3389
      $nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg
    }
  }

  $subnet = ($vnet.Subnets | Where-Object Name -eq $SubnetName)
  if (-not $subnet.NetworkSecurityGroup -or $subnet.NetworkSecurityGroup.Id -ne $nsg.Id) {
    $null = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -AddressPrefix $subnet.AddressPrefix -NetworkSecurityGroup $nsg
    $null = Set-AzVirtualNetwork -VirtualNetwork $vnet
  }

  @{ VNet=$vnet; Subnet=($vnet.Subnets | Where-Object Name -eq $SubnetName); Nsg=$nsg }
}

function Ensure-FSLogixStorage {
  param([string]$Rg,[string]$Loc,[string]$SaName,[string]$ShareName)
  Write-Color ("Ensuring Storage + Files (FSLogix): {0} / {1}" -f $SaName,$ShareName) "INFO"
  $st = Get-AzStorageAccount -Name $SaName -ResourceGroupName $Rg -ErrorAction SilentlyContinue
  if (-not $st) {
    $saParams = @{
      ResourceGroupName = $Rg
      Name = $SaName
      Location = $Loc
      SkuName = "Standard_LRS"
      Kind = "StorageV2"
      EnableHttpsTrafficOnly = $true
      MinimumTlsVersion = "TLS1_2"
      AllowBlobPublicAccess = $false
    }
    $st = New-AzStorageAccount @saParams
  }
  $ctx = $st.Context
  $share = Get-AzStorageShare -Name $ShareName -Context $ctx -ErrorAction SilentlyContinue
  if (-not $share) { $null = New-AzStorageShare -Name $ShareName -Context $ctx }
  $key = (Get-AzStorageAccountKey -ResourceGroupName $Rg -Name $SaName | Select-Object -First 1).Value
  $unc = ("\\{0}.file.core.windows.net\{1}" -f $SaName,$ShareName)
  @{ Context=$ctx; ShareUNC=$unc; Key=$key }
}

function Ensure-AVDCore {
  param([string]$Rg,[string]$Loc,[string]$HpName,[string]$DagName,[string]$WsName,[string]$UserGroupObjectId)

  $rp = Get-AzResourceProvider -ProviderNamespace "Microsoft.DesktopVirtualization"
  if ($rp.RegistrationState -ne "Registered") { Register-AzResourceProvider -ProviderNamespace "Microsoft.DesktopVirtualization" | Out-Null }

  $hp = Get-AzWvdHostPool -ResourceGroupName $Rg -Name $HpName -ErrorAction SilentlyContinue
  if (-not $hp) {
    $hp = New-AzWvdHostPool -ResourceGroupName $Rg -Name $HpName -Location $Loc -HostPoolType "Pooled" -LoadBalancerType "DepthFirst" -PreferredAppGroupType "Desktop" -MaxSessionLimit 12
  }
  $dag = Get-AzWvdApplicationGroup -ResourceGroupName $Rg -Name $DagName -ErrorAction SilentlyContinue
  if (-not $dag) {
    $dag = New-AzWvdApplicationGroup -ResourceGroupName $Rg -Name $DagName -Location $Loc -HostPoolArmPath $hp.Id -ApplicationGroupType "Desktop"
  }
  $ws = Get-AzWvdWorkspace -ResourceGroupName $Rg -Name $WsName -ErrorAction SilentlyContinue
  if (-not $ws) { $ws = New-AzWvdWorkspace -ResourceGroupName $Rg -Name $WsName -Location $Loc }

  $refs = (Get-AzWvdWorkspace -ResourceGroupName $Rg -Name $WsName).ApplicationGroupReference
  if (-not $refs -or ($refs -notcontains $dag.Id)) {
    $newRefs = @()
    if ($refs) { $newRefs += $refs }
    $newRefs += $dag.Id
    Update-AzWvdWorkspace -ResourceGroupName $Rg -Name $WsName -ApplicationGroupReference $newRefs | Out-Null
  }

  if ($UserGroupObjectId) {
    try {
      $haveDvu = Get-AzRoleAssignment -ObjectId $UserGroupObjectId -Scope $dag.Id -ErrorAction SilentlyContinue | Where-Object {$_.RoleDefinitionName -eq "Desktop Virtualization User"}
      if (-not $haveDvu) { New-AzRoleAssignment -ObjectId $UserGroupObjectId -RoleDefinitionName "Desktop Virtualization User" -Scope $dag.Id | Out-Null }
      $rgScope = (Get-AzResourceGroup -Name $Rg).ResourceId
      $haveVmLogin = Get-AzRoleAssignment -ObjectId $UserGroupObjectId -Scope $rgScope -ErrorAction SilentlyContinue | Where-Object {$_.RoleDefinitionName -eq "Virtual Machine User Login"}
      if (-not $haveVmLogin) { New-AzRoleAssignment -ObjectId $UserGroupObjectId -RoleDefinitionName "Virtual Machine User Login" -Scope $rgScope | Out-Null }
    } catch { Write-Color ("RBAC assignment warning: {0}" -f $_.Exception.Message) "WARNING" }
  }

  $reg = New-AzWvdRegistrationInfo -HostPoolName $HpName -ResourceGroupName $Rg -ExpirationTime (Get-Date).AddHours(8)
  @{ HostPool=$hp; AppGroup=$dag; Workspace=$ws; Token=$reg.Token }
}

function Get-DesiredImageMap {
  @{
    "Win11-Ent-MultiSession-23H2" = @{ type="avd"; pref=@("24h2","23h2","22h2") }
    "Win11-Ent-23H2"              = @{ type="ent"; pref=@("23h2","22h2") }
    "Win11-Ent-Single-Any"        = @{ type="ent"; pref=@("24h2","23h2","22h2") }
  }
}

function Resolve-RegionAndImage {
  param([string]$PreferredLoc,[string]$Code)
  $intent = (Get-DesiredImageMap)[$Code]
  if (-not $intent) { throw "Unknown image code: $Code" }
  $regionOrder = @($PreferredLoc,"westus","westus2","centralus","eastus2","eastus","southcentralus","northcentralus") | Select-Object -Unique
  $publishers = @("microsoftwindowsdesktop","MicrosoftWindowsDesktop")
  foreach ($loc in $regionOrder) {
    foreach ($pub in $publishers) {
      $offers = Get-AzVMImageOffer -Location $loc -PublisherName $pub -ErrorAction SilentlyContinue
      if (-not $offers) { continue }
      $winOffers = $offers | Where-Object { $_.Offer -match '^windows-?11$' }
      if (-not $winOffers) { continue }
      foreach ($offer in $winOffers) {
        $skus = Get-AzVMImageSku -Location $loc -PublisherName $pub -Offer $offer.Offer -ErrorAction SilentlyContinue
        if (-not $skus) { continue }
        $skuNames = $skus.Skus
        $needAVD = ($intent.type -eq "avd")
        $needENT = ($intent.type -eq "ent")
        $candidates = @()
        foreach ($ver in $intent.pref) {
          if ($needAVD) { $candidates += ($skuNames | Where-Object { $_ -match "$ver.*avd" }) }
          if ($needENT) { $candidates += ($skuNames | Where-Object { $_ -match "$ver.*ent" -and $_ -notmatch 'avd' }) }
        }
        if ($needAVD -and -not $candidates) { $candidates += ($skuNames | Where-Object { $_ -match 'avd' }) }
        if ($needENT -and -not $candidates) { $candidates += ($skuNames | Where-Object { $_ -match 'ent' -and $_ -notmatch 'avd' }) }
        if (-not $candidates -and $skuNames) { $candidates += ($skuNames | Select-Object -First 1) }
        $pick = $candidates | Select-Object -First 1
        if ($pick) {
          Write-Color ("Resolved image: {0}:{1}:{2} in {3}" -f $pub,$offer.Offer,$pick,$loc) "SUCCESS"
          return @{ Publisher=$pub; Offer=$offer.Offer; Sku=$pick; Version="latest"; Location=$loc }
        }
      }
    }
  }
  throw "No Windows 11 image SKUs found in US regions for requested intent."
}

function Get-SizeInfo {
  param([string]$Size)
  switch ($Size) {
    "Standard_D2s_v5"  { return @{ family="standardDSv5Family";  vcpus=2 } }
    "Standard_D4s_v5"  { return @{ family="standardDSv5Family";  vcpus=4 } }
    "Standard_D8s_v5"  { return @{ family="standardDSv5Family";  vcpus=8 } }
    "Standard_D2as_v5" { return @{ family="standardDASv5Family"; vcpus=2 } }
    "Standard_D4as_v5" { return @{ family="standardDASv5Family"; vcpus=4 } }
    "Standard_D2s_v4"  { return @{ family="standardDSv4Family";  vcpus=2 } }
    "Standard_D4s_v4"  { return @{ family="standardDSv4Family";  vcpus=4 } }
    default { throw "Unknown or unsupported VM size: $Size" }
  }
}

function Get-FamilyQuotaRemaining {
  param([string]$Location,[string]$FamilyName)
  $usg = Get-AzVMUsage -Location $Location -ErrorAction SilentlyContinue
  if (-not $usg) { return 0 }
  $row = $usg | Where-Object { $_.Name.Value -ieq ($FamilyName + " Cores") }
  if (-not $row) { return 0 }
  [int]($row.Limit - $row.CurrentValue)
}

function Resolve-SizeAndQuota {
  param([string]$PreferredSize,[int]$RequestedCount,[string]$Location)
  $candidates = @($PreferredSize,"Standard_D4s_v5","Standard_D2s_v5","Standard_D4as_v5","Standard_D2as_v5","Standard_D4s_v4","Standard_D2s_v4") | Select-Object -Unique
  $best = $null
  foreach ($sz in $candidates) {
    try { $info = Get-SizeInfo $sz } catch { continue }
    $remaining = Get-FamilyQuotaRemaining -Location $Location -FamilyName $info.family
    if ($remaining -le 0) { Write-Color ("Quota 0 for {0} in {1}" -f $info.family,$Location) "WARNING"; continue }
    $needed = $info.vcpus * $RequestedCount
    if ($remaining -ge $needed) {
      Write-Color ("Quota OK in {0}: {1} remaining {2} cores -> size {3}, count {4}" -f $Location,$info.family,$remaining,$sz,$RequestedCount) "SUCCESS"
      return @{ size=$sz; count=$RequestedCount; vcpus=$info.vcpus }
    }
    $maxHosts = [math]::Floor($remaining / $info.vcpus)
    if ($maxHosts -gt 0) {
      if (-not $best -or $maxHosts -gt $best.count) { $best = @{ size=$sz; count=$maxHosts; vcpus=$info.vcpus; remain=$remaining } }
    } else {
      Write-Color ("Not enough quota in {0}: {1} remaining {2} for size {3}" -f $Location,$info.family,$remaining,$sz) "WARNING"
    }
  }
  if ($best) {
    Write-Color ("Reducing host count due to quota in {0}: size {1}, count {2}" -f $Location,$best.size,$best.count) "WARNING"
    return $best
  }
  return $null
}

function Resolve-RegionSizeQuota {
  param([string]$PreferredLoc,[string]$ImageCode,[string]$PreferredSize,[int]$RequestedCount)
  $regionOrder = @($PreferredLoc,"westus","westus2","centralus","eastus2","eastus","southcentralus","northcentralus") | Select-Object -Unique
  foreach ($loc in $regionOrder) {
    try { $img = Resolve-RegionAndImage -PreferredLoc $loc -Code $ImageCode } catch { continue }
    $sizePick = Resolve-SizeAndQuota -PreferredSize $PreferredSize -RequestedCount $RequestedCount -Location $img.Location
    if ($sizePick) { return @{ Location=$img.Location; Image=$img; Size=$sizePick.size; Count=$sizePick.count } }
    Write-Color ("No quota for requested families in {0}. Trying next region..." -f $img.Location) "WARNING"
  }
  throw "No region has both image availability and enough VM-family quota."
}

function New-AvdVm {
  param(
    [string]$Rg,[string]$Loc,[Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
    [string]$Name,[string]$VmSize,[pscredential]$AdminCred,[hashtable]$ResolvedImage,[switch]$TrustedLaunch
  )
  $nicParams = @{
    Name = "$Name-nic"
    ResourceGroupName = $Rg
    Location = $Loc
    SubnetId = $Subnet.Id
  }
  $nic = New-AzNetworkInterface @nicParams

  $vm = New-AzVMConfig -VMName $Name -VMSize $VmSize
  $vm = Set-AzVMOperatingSystem -VM $vm -Windows -ComputerName $Name -Credential $AdminCred -ProvisionVMAgent -EnableAutoUpdate
  $vm = Set-AzVMSourceImage -VM $vm -PublisherName $ResolvedImage.Publisher -Offer $ResolvedImage.Offer -Skus $ResolvedImage.Sku -Version $ResolvedImage.Version
  $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id

  if ($TrustedLaunch) {
    $vm = Set-AzVMSecurityProfile -VM $vm -SecurityType "TrustedLaunch"
    $vm = Set-AzVMUefi -VM $vm -EnableVtpm $true -EnableSecureBoot $true
  }

  $vm = Set-AzVMBootDiagnostic -VM $vm -Disable
  $vmParams = @{
    ResourceGroupName = $Rg
    Location = $Loc
    VM = $vm
    Verbose = $false
  }
  New-AzVM @vmParams | Out-Null
}

function Set-AvdAgentAndFslogix {
  param([string]$Rg,[string]$VmName,[string]$RegistrationToken,[switch]$ConfigureFslogix,[string]$FslogixUNC,[string]$StorageKey)

  $script = @"
`$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$temp = 'C:\AvdSetup'
New-Item -ItemType Directory -Path `$temp -Force | Out-Null
`$agentUrl = 'https://aka.ms/AVDAgent'
`$bootUrl  = 'https://aka.ms/AVDVMExtension'
Invoke-WebRequest -Uri `$agentUrl -OutFile "`$temp\AVDAgent.msi"
Invoke-WebRequest -Uri `$bootUrl  -OutFile "`$temp\AVDBootloader.msi"
`$regPath = 'C:\ProgramData\Microsoft\RDInfra'
New-Item -ItemType Directory -Path `$regPath -Force | Out-Null
@{ 'registrationToken' = '$RegistrationToken' } | ConvertTo-Json | Out-File -FilePath "`$regPath\RegistrationInfo.json" -Encoding ASCII -Force
Start-Process msiexec.exe -ArgumentList '/i', "`$temp\AVDAgent.msi", '/quiet', '/norestart' -Wait
Start-Process msiexec.exe -ArgumentList '/i', "`$temp\AVDBootloader.msi", '/quiet', '/norestart' -Wait
if (`$ConfigureFslogix) {
  `$fxUrl = 'https://aka.ms/fslogix-latest'
  Invoke-WebRequest -Uri `$fxUrl -OutFile "`$temp\FSLogix.zip"
  Expand-Archive -Path "`$temp\FSLogix.zip" -DestinationPath "`$temp\fslogix" -Force
  `$fxSetup = Get-ChildItem "`$temp\fslogix" -Recurse -Filter 'FSLogixAppsSetup.exe' | Select-Object -First 1
  if (`$fxSetup) { Start-Process "`$(`$fxSetup.FullName)" -ArgumentList '/install /quiet /norestart' -Wait }
  New-Item -Path 'HKLM:\SOFTWARE\FSLogix' -Name 'Profiles' -Force | Out-Null
  New-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'Enabled' -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'DeleteLocalProfileWhenVHDShouldApply' -PropertyType DWord -Value 1 -Force | Out-Null
  `$v = New-Object System.Collections.Specialized.StringCollection
  `$v.Add('$FslogixUNC') | Out-Null
  `$key = 'HKLM:\SOFTWARE\FSLogix\Profiles'
  `$prop = Get-ItemProperty -Path `$key -Name 'VHDLocations' -ErrorAction SilentlyContinue
  if (-not `$prop) { New-ItemProperty -Path `$key -Name 'VHDLocations' -PropertyType MultiString -Value `$v -Force | Out-Null }
  else { Set-ItemProperty -Path `$key -Name 'VHDLocations' -Value `$v -Force }
  if ('$StorageKey' -and '$FslogixUNC') {
    `$sa = '$FslogixUNC'.Split('\')[2]
    cmdkey /add:`$sa /user:AZURE`$ /pass:'$StorageKey' | Out-Null
  }
}
"@

  $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $settingsJson = @{ "commandToExecute" = "powershell -ExecutionPolicy Bypass -EncodedCommand $b64" } | ConvertTo-Json
  $extParams = @{
    ResourceGroupName = $Rg
    VMName = $VmName
    Name = "avd-join"
    Publisher = "Microsoft.Compute"
    ExtensionType = "CustomScriptExtension"
    TypeHandlerVersion = "1.10"
    SettingString = $settingsJson
  }
  Set-AzVMExtension @extParams | Out-Null
}

# Menus
$VmSizeMenu = @("Standard_D2s_v5","Standard_D4s_v5","Standard_D8s_v5","Standard_D2as_v5","Standard_D4as_v5")

function Force-ChooseVmConfig {
  Write-Host ""
  Write-Color "Host Count Options:" "INFO"
  for ($i=1; $i -le 10; $i++) { Write-Host ("[{0}]  {1} host{2}" -f $i,$i,($(if($i -gt 1){"s"}else{""}))) }
  while ($true) {
    $countAns = Read-Host "Select host count (1-10). Required"
    if (($countAns -match '^\d+$') -and ([int]$countAns -ge 1) -and ([int]$countAns -le 10)) {
      $chosenCount = [int]$countAns
      break
    }
    Write-Color "Invalid selection. Enter a number 1-10." "ERROR"
  }

  Write-Host ""
  Write-Color "VM Size Options:" "INFO"
  for ($i=0; $i -lt $VmSizeMenu.Count; $i++) { Write-Host ("[{0}]  {1}" -f ($i+1), $VmSizeMenu[$i]) }
  while ($true) {
    $sizeAns = Read-Host ("Select VM size (1-{0}). Required" -f $VmSizeMenu.Count)
    if (($sizeAns -match '^\d+$') -and ([int]$sizeAns -ge 1) -and ([int]$sizeAns -le $VmSizeMenu.Count)) {
      $chosenSize = $VmSizeMenu[[int]$sizeAns - 1]
      break
    }
    Write-Color ("Invalid selection. Enter a number 1-{0}." -f $VmSizeMenu.Count) "ERROR"
  }

  Write-Color ("Selected: {0} host(s), size {1}" -f $chosenCount,$chosenSize) "SUCCESS"
  @{ Count=$chosenCount; Size=$chosenSize }
}

function Deploy-ToSubscription {
  param(
    $Sub,[string]$Loc,[int]$Count,[string]$PreferredSize,[string]$Image,[string]$VmPrefix,
    [pscredential]$VmCred,[string]$OnPremCidr,[string]$UserGroupObjectId,[switch]$DeployFslogix,[switch]$FirstVmThenPrompt
  )

  Set-AzContext -SubscriptionId $Sub.Id -Tenant $Sub.TenantId | Out-Null
  Write-Color ("Using subscription: {0} [{1}] (Tenant: {2})" -f $Sub.Name,$Sub.Id,$Sub.TenantId) "SUCCESS"

  $pick = Resolve-RegionSizeQuota -PreferredLoc $Loc -ImageCode $Image -PreferredSize $PreferredSize -RequestedCount $Count
  $Loc = $pick.Location
  $img = $pick.Image
  $sizeFinal = $pick.Size
  $countFinal = $pick.Count

  if ($countFinal -lt $Count) { Write-Color ("Host count reduced due to quota: requested {0} -> deploying {1}" -f $Count,$countFinal) "WARNING" }
  if ($sizeFinal -ne $PreferredSize) { Write-Color ("Size changed due to quota: requested {0} -> using {1}" -f $PreferredSize,$sizeFinal) "WARNING" }

  $abbr = Get-RegionAbbrev -Region $Loc
  if (-not $abbr) { $abbr = "PHE" }
  $rand = Get-Random -Maximum 9999
  $rgName = "$abbr-RG-AVD"
  $vnetName = "$abbr-VNET-AVD"
  $subName = "AVD-Subnet"
  $nsgName = "$abbr-NSG-AVD"
  $saName = ("{0}st{1:d4}prof" -f $abbr.ToLower(),$rand) -replace "[^a-z0-9]",""
  $shareName = "profiles"
  $hpName = "$abbr-HP-Prod"
  $dagName = "$abbr-DAG-Desktop"
  $wsName = "$abbr-WS-AVD"

  $null = Ensure-ResourceGroup -Name $rgName -Loc $Loc
  $net = Ensure-Network -Rg $rgName -Loc $Loc -VnetName $vnetName -SubnetName $subName -NsgName $nsgName -OnPremCidr $OnPremCidr
  $fs = Ensure-FSLogixStorage -Rg $rgName -Loc $Loc -SaName $saName -ShareName $shareName
  Write-Color ("FSLogix Share: {0}" -f $fs.ShareUNC) "SUCCESS"

  $avd = Ensure-AVDCore -Rg $rgName -Loc $Loc -HpName $hpName -DagName $dagName -WsName $wsName -UserGroupObjectId $UserGroupObjectId
  Write-Color ("HostPool: {0} | DAG: {1} | Workspace: {2}" -f $avd.HostPool.Name,$avd.AppGroup.Name,$avd.Workspace.Name) "SUCCESS"

  $toDeploy = $countFinal
  $initial = $toDeploy
  if ($FirstVmThenPrompt -and $toDeploy -gt 1) {
    $toDeploy = 1
    Write-Color "FirstVmThenPrompt: deploying 1 VM first, then will prompt for the rest." "INFO"
  }

  for ($i=1; $i -le $toDeploy; $i++) {
    $vmName = ("{0}{1:00}" -f $VmPrefix,$i)
    Write-Color ("Creating VM {0} in {1} with {2}:{3}:{4} (size {5})" -f $vmName,$Loc,$img.Publisher,$img.Offer,$img.Sku,$sizeFinal) "INFO"
    New-AvdVm -Rg $rgName -Loc $Loc -Subnet $net.Subnet -Name $vmName -VmSize $sizeFinal -AdminCred $VmCred -ResolvedImage $img -TrustedLaunch
    Set-AvdAgentAndFslogix -Rg $rgName -VmName $vmName -RegistrationToken $avd.Token -ConfigureFslogix:$DeployFslogix -FslogixUNC $fs.ShareUNC -StorageKey $fs.Key
  }

  if ($FirstVmThenPrompt -and $initial -gt 1) {
    $remaining = $initial - 1
    $ans = Read-Host ("First VM created. Deploy the remaining {0} host(s) now? (Y/N)" -f $remaining)
    if ($ans -match '^[Yy]$') {
      for ($i=2; $i -le $initial; $i++) {
        $vmName = ("{0}{1:00}" -f $VmPrefix,$i)
        Write-Color ("Creating VM {0} in {1} with {2}:{3}:{4} (size {5})" -f $vmName,$Loc,$img.Publisher,$img.Offer,$img.Sku,$sizeFinal) "INFO"
        New-AvdVm -Rg $rgName -Loc $Loc -Subnet $net.Subnet -Name $vmName -VmSize $sizeFinal -AdminCred $VmCred -ResolvedImage $img -TrustedLaunch
        Set-AvdAgentAndFslogix -Rg $rgName -VmName $vmName -RegistrationToken $avd.Token -ConfigureFslogix:$DeployFslogix -FslogixUNC $fs.ShareUNC -StorageKey $fs.Key
      }
    } else {
      Write-Color "Leaving with a single session host for now." "WARNING"
    }
  }

  Write-Color "Subscription deployment completed." "SUCCESS"
}

try {
  Ensure-Modules
  Connect-AzureAuto

  $credInfo = New-CredFromPlain -User $VmLocalAdminUsername -PassPlain $VmLocalAdminPasswordPlain
  $VmLocalAdminPasswordPlain = $credInfo.Plain
  $vmCred = $credInfo.Cred

  $subs = Force-ChooseSubscriptions

  Write-Host ""
  Write-Color "Host Count Options:" "INFO"
  for ($i=1; $i -le 10; $i++) { Write-Host ("[{0}]  {1} host{2}" -f $i,$i,($(if($i -gt 1){"s"}else{""}))) }
  $chosenCount = $null
  while ($true) {
    $countAns = Read-Host "Select host count (1-10). Required"
    if (($countAns -match '^\d+$') -and ([int]$countAns -ge 1) -and ([int]$countAns -le 10)) { $chosenCount = [int]$countAns; break }
    Write-Color "Invalid selection. Enter a number 1-10." "ERROR"
  }

  Write-Host ""
  Write-Color "VM Size Options:" "INFO"
  for ($i=0; $i -lt $VmSizeMenu.Count; $i++) { Write-Host ("[{0}]  {1}" -f ($i+1), $VmSizeMenu[$i]) }
  $chosenSize = $null
  while ($true) {
    $sizeAns = Read-Host ("Select VM size (1-{0}). Required" -f $VmSizeMenu.Count)
    if (($sizeAns -match '^\d+$') -and ([int]$sizeAns -ge 1) -and ([int]$sizeAns -le $VmSizeMenu.Count)) { $chosenSize = $VmSizeMenu[[int]$sizeAns - 1]; break }
    Write-Color ("Invalid selection. Enter a number 1-{0}." -f $VmSizeMenu.Count) "ERROR"
  }

  foreach ($s in $subs) {
    try {
      Deploy-ToSubscription -Sub $s -Loc $Location -Count $chosenCount -PreferredSize $chosenSize -Image $Image -VmPrefix $VmPrefix -VmCred $vmCred -OnPremCidr $OnPremCidr -UserGroupObjectId $UserGroupObjectId -DeployFslogix:$DeployFslogix -FirstVmThenPrompt:$FirstVmThenPrompt
    } catch {
      Write-Color ("Deployment failed in subscription {0}: {1}" -f $s.Id, $_.Exception.Message) "ERROR"
      if (-not $Force) { throw }
    }
  }

  Write-Color "All selected subscriptions processed." "SUCCESS"
  Write-Host ""
  Write-Host "===== SESSION HOST LOCAL ADMIN CREDENTIALS =====" -ForegroundColor Yellow
  Write-Host ("User: {0}" -f $VmLocalAdminUsername) -ForegroundColor White
  Write-Host ("Pass: {0}" -f $VmLocalAdminPasswordPlain) -ForegroundColor White
  Write-Host "=============================================== " -ForegroundColor Yellow
}
catch {
  Write-Color ("DEPLOYMENT FAILED: {0}" -f $_.Exception.Message) "ERROR"
  Write-Color "If blocked by quota, request increase for Dsv5/Dasv5 or pick a smaller size." "WARNING"
  exit 1
}
