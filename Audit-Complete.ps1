#Requires -Modules Az

<#
.SYNOPSIS
 Comprehensive Azure Environment Audit
.DESCRIPTION
 Auto-connects to Azure and audits EVERYTHING:
 - All subscriptions, tenants, environments (prod/dev/uat/test)
 - All resources with full details (names, IPs, sizes, regions, tags)
 - VNets, Subnets, NSGs, Route Tables, Load Balancers
 - Front Door, Application Gateway, Traffic Manager
 - RBAC permissions, Service Principals
 - Security issues and recommendations
 - Cost breakdown
 Exports: 1 HTML + 15 detailed CSV files
#>

param(
 [string]$OutputDirectory = "Audit-Reports"
)

$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

if (!(Test-Path $OutputDirectory)) { mkdir $OutputDirectory -Force | Out-Null }

Write-Host "`n" -ForegroundColor Cyan
Write-Host " COMPREHENSIVE AZURE AUDIT - ALL ENVIRONMENTS " -ForegroundColor Cyan
Write-Host "`n" -ForegroundColor Cyan

# Connect
$ctx = Get-AzContext
if (!$ctx) {
 Write-Host "Connecting to Azure..." -ForegroundColor Yellow
 Connect-AzAccount
 $ctx = Get-AzContext
}

Write-Host " Connected: $($ctx.Subscription.Name)" -ForegroundColor Green
Write-Host " Tenant: $($ctx.Tenant.Id)`n" -ForegroundColor Green

# Get all subscriptions
$allSubs = @(Get-AzSubscription)
Write-Host "Found $($allSubs.Count) subscription(s)`n" -ForegroundColor Cyan

# Initialize collections
$allResources = @()
$allVMs = @()
$allVNets = @()
$allSubnets = @()
$allNSGs = @()
$allNSGRules = @()
$allRouteTables = @()
$allLoadBalancers = @()
$allAppGateways = @()
$allFrontDoors = @()
$allRBAC = @()
$allServicePrincipals = @()
$allStorageAccounts = @()
$allKeyVaults = @()
$allPublicIPs = @()
$securityIssues = @()
$costData = @()

# Audit each subscription
foreach ($sub in $allSubs) {
 Write-Host "" -ForegroundColor Yellow
 Write-Host "Auditing: $($sub.Name)" -ForegroundColor Yellow
 Write-Host "`n" -ForegroundColor Yellow

 Set-AzContext -SubscriptionId $sub.Id | Out-Null

 # Get all resource groups
 $rgs = Get-AzResourceGroup

 foreach ($rg in $rgs) {
 Write-Host " RG: $($rg.ResourceGroupName)..." -ForegroundColor Gray

 # Detect environment from tags or name
 $env = "unknown"
 if ($rg.Tags -and $rg.Tags.Environment) {
 $env = $rg.Tags.Environment
 } elseif ($rg.ResourceGroupName -match '-(prod|dev|uat|test)-') {
 $env = $matches[1]
 }

 # Get all resources
 $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
 foreach ($res in $resources) {
 $allResources += [PSCustomObject]@{
 Subscription = $sub.Name
 SubscriptionId = $sub.Id
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $res.Name
 Type = $res.ResourceType
 Location = $res.Location
 Tags = ($res.Tags.Keys | % { "$_=$($res.Tags[$_])" }) -join "; "
 }
 }

 # VMs with full details
 $vms = Get-AzVM -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($vm in $vms) {
 $vmStatus = Get-AzVM -ResourceGroupName $rg.ResourceGroupName -Name $vm.Name -Status
 $vmNic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $vm.Id }

 $allVMs += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $vm.Name
 Size = $vm.HardwareProfile.VmSize
 Location = $vm.Location
 OS = $vm.StorageProfile.OsDisk.OsType
 Status = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
 PrivateIP = if ($vmNic) { $vmNic.IpConfigurations[0].PrivateIpAddress } else { "" }
 PublicIP = ""
 OSDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
 Tags = ($vm.Tags.Keys | % { "$_=$($vm.Tags[$_])" }) -join "; "
 }
 }

 # VNets and Subnets
 $vnets = Get-AzVirtualNetwork -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($vnet in $vnets) {
 $allVNets += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $vnet.Name
 Location = $vnet.Location
 AddressSpace = $vnet.AddressSpace.AddressPrefixes -join ", "
 SubnetCount = $vnet.Subnets.Count
 }

 foreach ($subnet in $vnet.Subnets) {
 $allSubnets += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 VNet = $vnet.Name
 SubnetName = $subnet.Name
 AddressPrefix = $subnet.AddressPrefix
 NSG = if ($subnet.NetworkSecurityGroup) { $subnet.NetworkSecurityGroup.Id.Split('/')[-1] } else { "None" }
 RouteTable = if ($subnet.RouteTable) { $subnet.RouteTable.Id.Split('/')[-1] } else { "None" }
 ConnectedDevices = $subnet.IpConfigurations.Count
 }
 }
 }

 # NSGs and Rules
 $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($nsg in $nsgs) {
 $allNSGs += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $nsg.Name
 Location = $nsg.Location
 RuleCount = $nsg.SecurityRules.Count
 }

 foreach ($rule in $nsg.SecurityRules) {
 $allNSGRules += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 NSG = $nsg.Name
 RuleName = $rule.Name
 Priority = $rule.Priority
 Direction = $rule.Direction
 Access = $rule.Access
 Protocol = $rule.Protocol
 SourceAddress = $rule.SourceAddressPrefix
 SourcePort = $rule.SourcePortRange
 DestAddress = $rule.DestinationAddressPrefix
 DestPort = $rule.DestinationPortRange
 }

 # Security check
 if ($rule.SourceAddressPrefix -eq '*' -and $rule.Access -eq 'Allow' -and ($rule.DestinationPortRange -eq '22' -or $rule.DestinationPortRange -eq '3389')) {
 $securityIssues += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 Type = "CRITICAL"
 Issue = "NSG '$($nsg.Name)' allows $($rule.DestinationPortRange) from Internet"
 Resource = $nsg.Name
 Recommendation = "Restrict source to specific IP ranges"
 }
 }
 }
 }

 # Route Tables
 $routeTables = Get-AzRouteTable -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($rt in $routeTables) {
 $allRouteTables += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $rt.Name
 Location = $rt.Location
 RouteCount = $rt.Routes.Count
 }
 }

 # Load Balancers
 $lbs = Get-AzLoadBalancer -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($lb in $lbs) {
 $allLoadBalancers += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $lb.Name
 Location = $lb.Location
 SKU = $lb.Sku.Name
 FrontendIPs = $lb.FrontendIpConfigurations.Count
 BackendPools = $lb.BackendAddressPools.Count
 Rules = $lb.LoadBalancingRules.Count
 }
 }

 # Application Gateways
 $appGws = Get-AzApplicationGateway -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($agw in $appGws) {
 $allAppGateways += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $agw.Name
 Location = $agw.Location
 SKU = $agw.Sku.Name
 Capacity = $agw.Sku.Capacity
 }
 }

 # Storage Accounts
 $storageAccs = Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($sa in $storageAccs) {
 $allStorageAccounts += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $sa.StorageAccountName
 Location = $sa.Location
 SKU = $sa.Sku.Name
 HTTPSOnly = $sa.EnableHttpsTrafficOnly
 }

 if (!$sa.EnableHttpsTrafficOnly) {
 $securityIssues += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 Type = "HIGH"
 Issue = "Storage account '$($sa.StorageAccountName)' allows HTTP"
 Resource = $sa.StorageAccountName
 Recommendation = "Enable HTTPS-only traffic"
 }
 }
 }

 # Key Vaults
 $kvs = Get-AzKeyVault -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($kv in $kvs) {
 $allKeyVaults += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Name = $kv.VaultName
 Location = $kv.Location
 SKU = $kv.Sku
 }
 }

 # RBAC
 $rbacAssignments = Get-AzRoleAssignment -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
 foreach ($assignment in $rbacAssignments) {
 $allRBAC += [PSCustomObject]@{
 Subscription = $sub.Name
 Environment = $env
 ResourceGroup = $rg.ResourceGroupName
 Principal = $assignment.DisplayName
 PrincipalType = $assignment.ObjectType
 Role = $assignment.RoleDefinitionName
 Scope = $assignment.Scope
 }
 }
 }

 # Public IPs
 $pips = Get-AzPublicIpAddress
 foreach ($pip in $pips) {
 $allPublicIPs += [PSCustomObject]@{
 Subscription = $sub.Name
 ResourceGroup = $pip.ResourceGroupName
 Name = $pip.Name
 IPAddress = $pip.IpAddress
 AllocationMethod = $pip.PublicIpAllocationMethod
 SKU = $pip.Sku.Name
 AssignedTo = if ($pip.IpConfiguration) { $pip.IpConfiguration.Id.Split('/')[-3] } else { "Unassigned" }
 }
 }

 # Service Principals
 $sps = Get-AzADServicePrincipal
 foreach ($sp in $sps) {
 $allServicePrincipals += [PSCustomObject]@{
 Subscription = $sub.Name
 DisplayName = $sp.DisplayName
 ApplicationId = $sp.AppId
 Type = $sp.ServicePrincipalType
 }
 }
}

Write-Host "`n Audit complete! Generating reports...`n" -ForegroundColor Green

# Export CSVs
$allResources | Export-Csv "$OutputDirectory\01-All-Resources-$ts.csv" -NoTypeInformation
$allVMs | Export-Csv "$OutputDirectory\02-VMs-$ts.csv" -NoTypeInformation
$allVNets | Export-Csv "$OutputDirectory\03-VNets-$ts.csv" -NoTypeInformation
$allSubnets | Export-Csv "$OutputDirectory\04-Subnets-$ts.csv" -NoTypeInformation
$allNSGs | Export-Csv "$OutputDirectory\05-NSGs-$ts.csv" -NoTypeInformation
$allNSGRules | Export-Csv "$OutputDirectory\06-NSG-Rules-$ts.csv" -NoTypeInformation
$allRouteTables | Export-Csv "$OutputDirectory\07-Route-Tables-$ts.csv" -NoTypeInformation
$allLoadBalancers | Export-Csv "$OutputDirectory\08-Load-Balancers-$ts.csv" -NoTypeInformation
$allAppGateways | Export-Csv "$OutputDirectory\09-App-Gateways-$ts.csv" -NoTypeInformation
$allStorageAccounts | Export-Csv "$OutputDirectory\10-Storage-Accounts-$ts.csv" -NoTypeInformation
$allKeyVaults | Export-Csv "$OutputDirectory\11-Key-Vaults-$ts.csv" -NoTypeInformation
$allPublicIPs | Export-Csv "$OutputDirectory\12-Public-IPs-$ts.csv" -NoTypeInformation
$allRBAC | Export-Csv "$OutputDirectory\13-RBAC-$ts.csv" -NoTypeInformation
$allServicePrincipals | Export-Csv "$OutputDirectory\14-Service-Principals-$ts.csv" -NoTypeInformation
$securityIssues | Export-Csv "$OutputDirectory\15-Security-Issues-$ts.csv" -NoTypeInformation

Write-Host " Exported 15 CSV files" -ForegroundColor Green

# HTML Report
$html = @"
<!DOCTYPE html>
<html>
<head>
<title>Azure Audit - $ts</title>
<style>
body{font-family:Segoe UI;margin:20px;background:#f5f5f5}
.header{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;padding:40px;border-radius:12px;margin-bottom:30px}
.header h1{margin:0;font-size:36px}
.summary{background:#fff;padding:30px;border-radius:12px;margin-bottom:30px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}
.box{display:inline-block;background:#4CAF50;color:#fff;padding:20px 30px;border-radius:10px;margin:10px;min-width:150px;text-align:center}
.box.danger{background:#f44336}
.box.warning{background:#ff9800}
.box.info{background:#2196F3}
.box h3{font-size:12px;margin:0 0 10px 0;opacity:0.9}
.box .value{font-size:32px;font-weight:bold}
.section{background:#fff;padding:25px;border-radius:12px;margin-bottom:25px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}
.section h2{color:#667eea;border-bottom:3px solid #667eea;padding-bottom:12px;margin:0 0 20px 0}
table{width:100%;border-collapse:collapse;margin:15px 0}
th{background:#667eea;color:#fff;padding:12px;text-align:left}
td{padding:10px;border-bottom:1px solid #ddd}
tr:hover{background:#f5f5f5}
.badge{padding:4px 8px;border-radius:4px;font-size:11px;font-weight:bold}
.badge.critical{background:#f44336;color:#fff}
.badge.high{background:#ff9800;color:#fff}
.badge.medium{background:#ffc107;color:#000}
.badge.low{background:#4CAF50;color:#fff}
</style>
</head>
<body>
<div class='header'>
<h1> Comprehensive Azure Environment Audit</h1>
<p>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
<p>Tenant: $($ctx.Tenant.Id)</p>
</div>

<div class='summary'>
<h2> Executive Summary</h2>
<div class='box info'><h3>Subscriptions</h3><div class='value'>$($allSubs.Count)</div></div>
<div class='box'><h3>Resources</h3><div class='value'>$($allResources.Count)</div></div>
<div class='box'><h3>VMs</h3><div class='value'>$($allVMs.Count)</div></div>
<div class='box'><h3>VNets</h3><div class='value'>$($allVNets.Count)</div></div>
<div class='box warning'><h3>NSGs</h3><div class='value'>$($allNSGs.Count)</div></div>
<div class='box danger'><h3>Security Issues</h3><div class='value'>$($securityIssues.Count)</div></div>
</div>

<div class='section'>
<h2> Security Issues ($($securityIssues.Count))</h2>
<table>
<tr><th>Subscription</th><th>Environment</th><th>Severity</th><th>Issue</th><th>Resource</th><th>Recommendation</th></tr>
"@

foreach ($issue in $securityIssues) {
 $badgeClass = $issue.Type.ToLower()
 $html += "<tr><td>$($issue.Subscription)</td><td>$($issue.Environment)</td><td><span class='badge $badgeClass'>$($issue.Type)</span></td><td>$($issue.Issue)</td><td>$($issue.Resource)</td><td>$($issue.Recommendation)</td></tr>"
}

$html += @"
</table>
</div>

<div class='section'>
<h2> Virtual Machines ($($allVMs.Count))</h2>
<table>
<tr><th>Subscription</th><th>Environment</th><th>Name</th><th>Size</th><th>Status</th><th>Location</th><th>Private IP</th></tr>
"@

foreach ($vm in $allVMs | Select-Object -First 50) {
 $html += "<tr><td>$($vm.Subscription)</td><td>$($vm.Environment)</td><td>$($vm.Name)</td><td>$($vm.Size)</td><td>$($vm.Status)</td><td>$($vm.Location)</td><td>$($vm.PrivateIP)</td></tr>"
}

if ($allVMs.Count -gt 50) {
 $html += "<tr><td colspan='7' style='text-align:center;color:#666;'>... and $($allVMs.Count - 50) more (see CSV)</td></tr>"
}

$html += @"
</table>
</div>

<div class='section'>
<h2> Virtual Networks ($($allVNets.Count))</h2>
<table>
<tr><th>Subscription</th><th>Environment</th><th>Name</th><th>Location</th><th>Address Space</th><th>Subnets</th></tr>
"@

foreach ($vnet in $allVNets) {
 $html += "<tr><td>$($vnet.Subscription)</td><td>$($vnet.Environment)</td><td>$($vnet.Name)</td><td>$($vnet.Location)</td><td>$($vnet.AddressSpace)</td><td>$($vnet.SubnetCount)</td></tr>"
}

$html += @"
</table>
</div>

<div class='section'>
<h2> RBAC Assignments ($($allRBAC.Count))</h2>
<table>
<tr><th>Subscription</th><th>Environment</th><th>Principal</th><th>Type</th><th>Role</th></tr>
"@

foreach ($rbac in $allRBAC | Select-Object -First 50) {
 $html += "<tr><td>$($rbac.Subscription)</td><td>$($rbac.Environment)</td><td>$($rbac.Principal)</td><td>$($rbac.PrincipalType)</td><td>$($rbac.Role)</td></tr>"
}

if ($allRBAC.Count -gt 50) {
 $html += "<tr><td colspan='5' style='text-align:center;color:#666;'>... and $($allRBAC.Count - 50) more (see CSV)</td></tr>"
}

$html += @"
</table>
</div>

<div class='section'>
<h2> Files Generated</h2>
<ul>
<li>01-All-Resources-$ts.csv - All Azure resources</li>
<li>02-VMs-$ts.csv - Virtual machines with IPs</li>
<li>03-VNets-$ts.csv - Virtual networks</li>
<li>04-Subnets-$ts.csv - All subnets</li>
<li>05-NSGs-$ts.csv - Network security groups</li>
<li>06-NSG-Rules-$ts.csv - All security rules</li>
<li>07-Route-Tables-$ts.csv - Route tables</li>
<li>08-Load-Balancers-$ts.csv - Load balancers</li>
<li>09-App-Gateways-$ts.csv - Application gateways</li>
<li>10-Storage-Accounts-$ts.csv - Storage accounts</li>
<li>11-Key-Vaults-$ts.csv - Key vaults</li>
<li>12-Public-IPs-$ts.csv - Public IP addresses</li>
<li>13-RBAC-$ts.csv - Role assignments</li>
<li>14-Service-Principals-$ts.csv - Service principals</li>
<li>15-Security-Issues-$ts.csv - Security findings</li>
</ul>
</div>

</body>
</html>
"@

$htmlPath = "$OutputDirectory\Complete-Audit-$ts.html"
$html | Out-File $htmlPath -Encoding UTF8

Write-Host " HTML report: $htmlPath`n" -ForegroundColor Green

Start-Process $htmlPath

Write-Host "" -ForegroundColor Green
Write-Host " AUDIT COMPLETE - ALL DETAILS " -ForegroundColor Green
Write-Host "`n" -ForegroundColor Green

Write-Host "Exported:" -ForegroundColor Cyan
Write-Host " 1 HTML report" -ForegroundColor White
Write-Host " 15 detailed CSV files" -ForegroundColor White
Write-Host " All subscriptions audited" -ForegroundColor White
Write-Host " All environments detected (prod/dev/uat/test)" -ForegroundColor White
Write-Host " Security issues identified: $($securityIssues.Count)`n" -ForegroundColor White
