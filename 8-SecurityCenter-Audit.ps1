#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ReportPath = ".\Reports",
    [string]$OutputFormat = "Both"
)

$ErrorActionPreference = "Continue"

function Install-AzModulesIfNeeded {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Storage", "Az.Network", "Az.Monitor", "Az.KeyVault", "Az.Sql", "Az.Security")
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ListAvailable)) { $missingModules += $module }
    }
    if ($missingModules.Count -gt 0) {
        Write-Host "Installing Azure modules..." -ForegroundColor Yellow
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            Install-Module Az -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "Modules installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to install modules" -ForegroundColor Red
            exit 1
        }
    }
    foreach ($module in $requiredModules) { Import-Module $module -ErrorAction SilentlyContinue }
}

Install-AzModulesIfNeeded

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) { Connect-AzAccount -ErrorAction Stop | Out-Null }
        Write-Log "Connected as: $((Get-AzContext).Account.Id)" "SUCCESS"
    } catch {
        Write-Log "Failed to connect: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    if ($subscriptions.Count -eq 0) {
        Write-Log "No subscriptions found" "ERROR"
        return $null
    }
    
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
        Write-Host "      ID: $($subscriptions[$i].Id)" -ForegroundColor Gray
    }
    
    do {
        Write-Host "Select (1-$($subscriptions.Count)) or Q: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        if ($selection -eq 'Q') { return $null }
        $selectedIndex = [int]$selection - 1
    } while ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count)
    
    $selectedSub = $subscriptions[$selectedIndex]
    Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null

# ========================================
# COST ANALYSIS WITH FULL DETAILS
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
$currentContext = Get-AzContext
$subscriptionName = $currentContext.Subscription.Name
$subscriptionId = $currentContext.Subscription.Id
Write-Host "COST ANALYSIS - $subscriptionName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$costData = @{SubscriptionName=$subscriptionName;SubscriptionId=$subscriptionId;TotalMonthlyCost=0;LiveCost=0;IdleCost=0;CostByRegion=@{};LiveVMs=@();StoppedVMs=@();UnattachedDisks=@();UnusedIPs=@()}
try {
    Write-Host "Analyzing costs for subscription: $subscriptionName" -ForegroundColor Yellow
    Write-Host "  Analyzing Virtual Machines..." -ForegroundColor Gray
    $vms = Get-AzVM -Status
    foreach ($vm in $vms) {
        $vmSize = $vm.HardwareProfile.VmSize
        $vmRegion = $vm.Location
        $cost = switch -Wildcard ($vmSize) {
            "*A1*"{30};"*A2*"{60};"*A4*"{120};"*D2*"{100};"*D4*"{140};"*D8*"{280};"*D16*"{560};"*D32*"{1120}
            "*E2*"{110};"*E4*"{150};"*E8*"{300};"*E16*"{600};"*E32*"{1200};"*F2*"{90};"*F4*"{120};"*F8*"{240};"*F16*"{480}
            "*B1*"{8};"*B2*"{30};"*B4*"{60};default{50}
        }
        if ($vm.PowerState -match "deallocated|stopped") {
            $costData.StoppedVMs += @{Name=$vm.Name;ResourceGroup=$vm.ResourceGroupName;Region=$vmRegion;Size=$vmSize;Cost=$cost}
            $costData.IdleCost += $cost
        } else {
            $costData.LiveVMs += @{Name=$vm.Name;ResourceGroup=$vm.ResourceGroupName;Region=$vmRegion;Size=$vmSize;Cost=$cost}
            $costData.LiveCost += $cost
            if (!$costData.CostByRegion.ContainsKey($vmRegion)) {$costData.CostByRegion[$vmRegion]=0}
            $costData.CostByRegion[$vmRegion] += $cost
        }
    }
    Write-Host "  Analyzing Unattached Disks..." -ForegroundColor Gray
    $disks = Get-AzDisk
    foreach ($disk in $disks) {
        if (!$disk.ManagedBy) {
            $diskCost = [math]::Round($disk.DiskSizeGB * 0.10, 2)
            $costData.UnattachedDisks += @{Name=$disk.Name;ResourceGroup=$disk.ResourceGroupName;Region=$disk.Location;Size=$disk.DiskSizeGB;Cost=$diskCost}
            $costData.IdleCost += $diskCost
        }
    }
    Write-Host "  Analyzing Public IP Addresses..." -ForegroundColor Gray
    $pips = Get-AzPublicIpAddress
    foreach ($pip in $pips) {
        if (!$pip.IpConfiguration) {
            $costData.UnusedIPs += @{Name=$pip.Name;ResourceGroup=$pip.ResourceGroupName;Region=$pip.Location;IPAddress=$pip.IpAddress;Cost=3}
            $costData.IdleCost += 3
        }
    }
    $costData.TotalMonthlyCost = $costData.LiveCost + $costData.IdleCost
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "COST SUMMARY - $subscriptionName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Subscription ID: $subscriptionId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "LIVE RESOURCES:" -ForegroundColor Green
    Write-Host "  VMs Running: $($costData.LiveVMs.Count)" -ForegroundColor White
    Write-Host "  Live Cost: `$([math]::Round($costData.LiveCost, 2))/month" -ForegroundColor Green
    Write-Host ""
    Write-Host "IDLE RESOURCES:" -ForegroundColor Yellow
    Write-Host "  Stopped VMs: $($costData.StoppedVMs.Count)" -ForegroundColor White
    Write-Host "  Unattached Disks: $($costData.UnattachedDisks.Count)" -ForegroundColor White
    Write-Host "  Unused Public IPs: $($costData.UnusedIPs.Count)" -ForegroundColor White
    Write-Host "  Idle Cost: `$([math]::Round($costData.IdleCost, 2))/month" -ForegroundColor Yellow
    Write-Host ""
    if ($costData.CostByRegion.Count -gt 0) {
        Write-Host "COST BY REGION:" -ForegroundColor Cyan
        foreach ($region in $costData.CostByRegion.Keys | Sort-Object) {
            Write-Host "  $region : `$([math]::Round($costData.CostByRegion[$region], 2))/month" -ForegroundColor White
        }
        Write-Host ""
    }
    Write-Host "TOTAL MONTHLY COST: `$([math]::Round($costData.TotalMonthlyCost, 2))" -ForegroundColor Cyan
    Write-Host "POTENTIAL SAVINGS: `$([math]::Round($costData.IdleCost, 2))/month" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    $global:AzureCostData = $costData
} catch {
    Write-Host "Warning: Could not complete cost analysis - #Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ReportPath = ".\Reports",
    [string]$OutputFormat = "Both"
)

$ErrorActionPreference = "Continue"

function Install-AzModulesIfNeeded {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Storage", "Az.Network", "Az.Monitor", "Az.KeyVault", "Az.Sql", "Az.Security")
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ListAvailable)) { $missingModules += $module }
    }
    if ($missingModules.Count -gt 0) {
        Write-Host "Installing Azure modules..." -ForegroundColor Yellow
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            Install-Module Az -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "Modules installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to install modules" -ForegroundColor Red
            exit 1
        }
    }
    foreach ($module in $requiredModules) { Import-Module $module -ErrorAction SilentlyContinue }
}

Install-AzModulesIfNeeded

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) { Connect-AzAccount -ErrorAction Stop | Out-Null }
        Write-Log "Connected as: $((Get-AzContext).Account.Id)" "SUCCESS"
    } catch {
        Write-Log "Failed to connect: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    if ($subscriptions.Count -eq 0) {
        Write-Log "No subscriptions found" "ERROR"
        return $null
    }
    
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
        Write-Host "      ID: $($subscriptions[$i].Id)" -ForegroundColor Gray
    }
    
    do {
        Write-Host "Select (1-$($subscriptions.Count)) or Q: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        if ($selection -eq 'Q') { return $null }
        $selectedIndex = [int]$selection - 1
    } while ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count)
    
    $selectedSub = $subscriptions[$selectedIndex]
    Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
    Write-Log "Active: $($selectedSub.Name)" "SUCCESS"
    Write-Host ""
    return $selectedSub
}

function Get-CompleteInventory {
    param([object]$Subscription)
    Write-Log "Collecting complete inventory..."
    $inventory = @{ Subscription = $Subscription; CollectionTime = Get-Date; Summary = @{}; Resources = @{} }
    
    Write-Host "  Resource Groups..." -ForegroundColor Cyan
    $inventory.Resources.ResourceGroups = Get-AzResourceGroup
    $inventory.Summary.ResourceGroups = $inventory.Resources.ResourceGroups.Count
    
    Write-Host "  Virtual Machines..." -ForegroundColor Cyan
    $inventory.Resources.VMs = Get-AzVM
    $inventory.Summary.VMs = $inventory.Resources.VMs.Count
    
    Write-Host "  Disks..." -ForegroundColor Cyan
    $inventory.Resources.Disks = Get-AzDisk
    $inventory.Summary.Disks = $inventory.Resources.Disks.Count
    
    Write-Host "  Network Interfaces..." -ForegroundColor Cyan
    $inventory.Resources.NICs = Get-AzNetworkInterface
    $inventory.Summary.NICs = $inventory.Resources.NICs.Count
    
    Write-Host "  Virtual Networks..." -ForegroundColor Cyan
    $inventory.Resources.VNets = Get-AzVirtualNetwork
    $inventory.Summary.VNets = $inventory.Resources.VNets.Count
    
    Write-Host "  Subnets..." -ForegroundColor Cyan
    $subnets = $inventory.Resources.VNets | ForEach-Object { $_.Subnets }
    $inventory.Resources.Subnets = $subnets
    $inventory.Summary.Subnets = $subnets.Count
    
    Write-Host "  Public IPs..." -ForegroundColor Cyan
    $inventory.Resources.PublicIPs = Get-AzPublicIpAddress
    $inventory.Summary.PublicIPs = $inventory.Resources.PublicIPs.Count
    
    Write-Host "  Load Balancers..." -ForegroundColor Cyan
    $inventory.Resources.LoadBalancers = Get-AzLoadBalancer
    $inventory.Summary.LoadBalancers = $inventory.Resources.LoadBalancers.Count
    
    Write-Host "  NSGs..." -ForegroundColor Cyan
    $inventory.Resources.NSGs = Get-AzNetworkSecurityGroup
    $inventory.Summary.NSGs = $inventory.Resources.NSGs.Count
    
    Write-Host "  Storage Accounts..." -ForegroundColor Cyan
    $inventory.Resources.StorageAccounts = Get-AzStorageAccount
    $inventory.Summary.StorageAccounts = $inventory.Resources.StorageAccounts.Count
    
    Write-Host "  Key Vaults..." -ForegroundColor Cyan
    $inventory.Resources.KeyVaults = Get-AzKeyVault
    $inventory.Summary.KeyVaults = $inventory.Resources.KeyVaults.Count
    
    Write-Host "  SQL Servers..." -ForegroundColor Cyan
    $inventory.Resources.SQLServers = Get-AzSqlServer
    $inventory.Summary.SQLServers = $inventory.Resources.SQLServers.Count
    
    Write-Host "  App Services..." -ForegroundColor Cyan
    $inventory.Resources.AppServices = Get-AzWebApp
    $inventory.Summary.AppServices = $inventory.Resources.AppServices.Count
    
    Write-Host "  Service Principals..." -ForegroundColor Cyan
    try {
        $inventory.Resources.ServicePrincipals = Get-AzADServicePrincipal
        $inventory.Summary.ServicePrincipals = $inventory.Resources.ServicePrincipals.Count
    } catch {
        $inventory.Summary.ServicePrincipals = 0
    }
    
    Write-Log "Inventory complete - $($inventory.Summary.Keys.Count) types" "SUCCESS"
    return $inventory
}

function Get-IdleResources {
    param([object]$Subscription)
    Write-Log "Detecting idle resources..."
    $idle = @{ IdleVMs = @(); UnattachedDisks = @(); UnattachedNICs = @(); UnusedPublicIPs = @() }
    
    $vms = Get-AzVM
    foreach ($vm in $vms) {
        $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -match "PowerState" }).DisplayStatus
        if ($powerState -match "stopped|deallocated") { $idle.IdleVMs += $vm }
    }
    
    $disks = Get-AzDisk
    $idle.UnattachedDisks = $disks | Where-Object { $_.ManagedBy -eq $null }
    
    $nics = Get-AzNetworkInterface
    $idle.UnattachedNICs = $nics | Where-Object { $_.VirtualMachine -eq $null }
    
    $publicIPs = Get-AzPublicIpAddress
    $idle.UnusedPublicIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
    
    $totalSavings = ($idle.UnattachedDisks.Count * 5) + ($idle.UnusedPublicIPs.Count * 3)
    Write-Log "Idle resources: $($idle.IdleVMs.Count) VMs, $($idle.UnattachedDisks.Count) disks, $($idle.UnattachedNICs.Count) NICs, $($idle.UnusedPublicIPs.Count) IPs - Est. savings: `$$totalSavings/mo" "SUCCESS"
    
    return $idle
}

function Export-Report {
    param([object]$Inventory, [object]$IdleResources, [array]$Findings, [string]$ReportName, [string]$Format = "Both")
    
    if (!(Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $subName = $Inventory.Subscription.Name -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$subName-$timestamp"
    
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        $csvPath = "$ReportPath\$baseFileName.csv"
        if ($Findings.Count -gt 0) {
            $Findings | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "CSV: $csvPath" "SUCCESS"
        }
    }
    
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        $htmlPath = "$ReportPath\$baseFileName.html"
        $html = @"
<!DOCTYPE html>
<html><head><title>$ReportName - $($Inventory.Subscription.Name)</title><meta charset="UTF-8"><style>
body{font-family:'Segoe UI',sans-serif;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
.header{background:linear-gradient(135deg,#0078d4,#00bcf2);color:#fff;padding:30px}
.header h1{font-size:32px;margin:0 0 10px}
.header-info{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin-top:20px}
.header-info-item{background:rgba(255,255,255,0.2);padding:10px 15px;border-radius:5px}
.content{padding:30px}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}
.summary-card{background:linear-gradient(135deg,#f5f7fa,#c3cfe2);padding:20px;border-radius:10px;border-left:4px solid #0078d4}
.summary-card h3{color:#0078d4;font-size:14px;text-transform:uppercase;margin:0 0 10px}
.summary-card .number{font-size:36px;font-weight:bold;color:#333}
table{width:100%;border-collapse:collapse;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-top:20px}
th{background:#0078d4;color:#fff;padding:12px;text-align:left}
td{padding:10px 12px;border-bottom:1px solid #e0e0e0}
tr:hover{background:#f5f5f5}
.critical{color:#d13438;font-weight:bold}
.high{color:#ff8c00;font-weight:bold}
.medium{color:#f7b731}
.low{color:#107c10}
.idle-section{background:#fff4e6;border:2px solid #ff8c00;border-radius:10px;padding:20px;margin:20px 0}
.idle-section h3{color:#ff8c00;margin-bottom:15px}
.footer{background:#f5f5f5;padding:20px;text-align:center;color:#666}
</style></head><body><div class="container">
<div class="header"><h1>$ReportName</h1><div class="header-info">
<div class="header-info-item"><strong>Subscription:</strong><br>$($Inventory.Subscription.Name)</div>
<div class="header-info-item"><strong>Subscription ID:</strong><br>$($Inventory.Subscription.Id)</div>
<div class="header-info-item"><strong>Generated:</strong><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="header-info-item"><strong>Total Findings:</strong><br>$($Findings.Count)</div>
</div></div><div class="content"><div class="summary">
"@
        
        foreach ($key in $Inventory.Summary.Keys | Sort-Object) {
            $html += "<div class='summary-card'><h3>$key</h3><div class='number'>$($Inventory.Summary[$key])</div></div>"
        }
        $html += "</div>"
        
        if ($IdleResources) {
            $totalSavings = ($IdleResources.UnattachedDisks.Count * 5) + ($IdleResources.UnusedPublicIPs.Count * 3)
            $html += @"
<div class='idle-section'><h3>Idle Resources Detected - Cost Savings Opportunity</h3><table>
<tr><th>Resource Type</th><th>Count</th><th>Est. Monthly Savings</th></tr>
<tr><td>Idle/Stopped VMs</td><td>$($IdleResources.IdleVMs.Count)</td><td>Review for compute cost savings</td></tr>
<tr><td>Unattached Disks</td><td>$($IdleResources.UnattachedDisks.Count)</td><td>`$$($IdleResources.UnattachedDisks.Count * 5)/month</td></tr>
<tr><td>Unattached NICs</td><td>$($IdleResources.UnattachedNICs.Count)</td><td>`$$($IdleResources.UnattachedNICs.Count)/month</td></tr>
<tr><td>Unused Public IPs</td><td>$($IdleResources.UnusedPublicIPs.Count)</td><td>`$$($IdleResources.UnusedPublicIPs.Count * 3)/month</td></tr>
<tr style='background:#fff4e6;font-weight:bold'><td colspan='2'>Total Est. Savings:</td><td>`$$totalSavings/month</td></tr>
</table></div>
"@
        }
        
        if ($Findings.Count -gt 0) {
            $html += "<h2>Detailed Findings</h2><table><tr>"
            $Findings[0].PSObject.Properties.Name | ForEach-Object { $html += "<th>$_</th>" }
            $html += "</tr>"
            foreach ($finding in $Findings) {
                $html += "<tr>"
                $finding.PSObject.Properties | ForEach-Object {
                    $value = if ($_.Value) { $_.Value } else { "" }
                    $class = ""
                    if ($_.Name -match "Severity|Priority|Risk|Level") {
                        $class = switch ($value) {
                            "Critical" { " class='critical'" }
                            "High" { " class='high'" }
                            "Medium" { " class='medium'" }
                            "Low" { " class='low'" }
                            default { "" }
                        }
                    }
                    $html += "<td$class>$value</td>"
                }
                $html += "</tr>"
            }
            $html += "</table>"
        }
        
        $html += @"
</div><div class='footer'><p><strong>Azure Production Scripts Suite</strong></p>
<p>Professional Azure audit and compliance reporting</p>
<p>This report is READ-ONLY - No changes were made to your environment</p></div></div></body></html>
"@
        
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Log "HTML: $htmlPath" "SUCCESS"
        Start-Process $htmlPath
    }
}

$sub = Connect-AzureWithSubscription
if (!$sub) { exit 1 }
$inventory = Get-CompleteInventory -Subscription $sub
$idle = Get-IdleResources -Subscription $sub
$findings = @()

Write-Log "Auditing Security Center recommendations..."

try {
    $securityTasks = Get-AzSecurityTask
    
    foreach ($task in $securityTasks) {
        $severity = switch ($task.Properties.severity) {
            "High" { "High" }
            "Medium" { "Medium" }
            "Low" { "Low" }
            default { "Medium" }
        }
        
        $findings += [PSCustomObject]@{
            RecommendationName = $task.Properties.securityTaskParameters.name
            Description = $task.Properties.securityTaskParameters.description
            ResourceName = $task.Properties.securityTaskParameters.resourceId.Split('/')[-1]
            State = $task.Properties.state
            Severity = $severity
            Issue = $task.Properties.securityTaskParameters.name
            Subscription = $sub.Name
        }
    }
} catch {
    Write-Log "Unable to retrieve Security Center tasks - may need Defender for Cloud enabled" "WARNING"
    $findings += [PSCustomObject]@{
        RecommendationName = "Security Center Status"
        Description = "Unable to retrieve security recommendations"
        ResourceName = "Subscription"
        State = "Unknown"
        Severity = "Medium"
        Issue = "Security Center/Defender for Cloud may not be enabled"
        Subscription = $sub.Name
    }
}

Write-Log "Found $($findings.Count) security findings" "SUCCESS"
Export-Report -Inventory $inventory -IdleResources $idle -Findings $findings -ReportName "8-SecurityCenter-Audit" -Format $OutputFormat
" -ForegroundColor Yellow
}
# ========================================
    Write-Log "Active: $($selectedSub.Name)" "SUCCESS"
    Write-Host ""
    return $selectedSub
}

function Get-CompleteInventory {
    param([object]$Subscription)
    Write-Log "Collecting complete inventory..."
    $inventory = @{ Subscription = $Subscription; CollectionTime = Get-Date; Summary = @{}; Resources = @{} }
    
    Write-Host "  Resource Groups..." -ForegroundColor Cyan
    $inventory.Resources.ResourceGroups = Get-AzResourceGroup
    $inventory.Summary.ResourceGroups = $inventory.Resources.ResourceGroups.Count
    
    Write-Host "  Virtual Machines..." -ForegroundColor Cyan
    $inventory.Resources.VMs = Get-AzVM
    $inventory.Summary.VMs = $inventory.Resources.VMs.Count
    
    Write-Host "  Disks..." -ForegroundColor Cyan
    $inventory.Resources.Disks = Get-AzDisk
    $inventory.Summary.Disks = $inventory.Resources.Disks.Count
    
    Write-Host "  Network Interfaces..." -ForegroundColor Cyan
    $inventory.Resources.NICs = Get-AzNetworkInterface
    $inventory.Summary.NICs = $inventory.Resources.NICs.Count
    
    Write-Host "  Virtual Networks..." -ForegroundColor Cyan
    $inventory.Resources.VNets = Get-AzVirtualNetwork
    $inventory.Summary.VNets = $inventory.Resources.VNets.Count
    
    Write-Host "  Subnets..." -ForegroundColor Cyan
    $subnets = $inventory.Resources.VNets | ForEach-Object { $_.Subnets }
    $inventory.Resources.Subnets = $subnets
    $inventory.Summary.Subnets = $subnets.Count
    
    Write-Host "  Public IPs..." -ForegroundColor Cyan
    $inventory.Resources.PublicIPs = Get-AzPublicIpAddress
    $inventory.Summary.PublicIPs = $inventory.Resources.PublicIPs.Count
    
    Write-Host "  Load Balancers..." -ForegroundColor Cyan
    $inventory.Resources.LoadBalancers = Get-AzLoadBalancer
    $inventory.Summary.LoadBalancers = $inventory.Resources.LoadBalancers.Count
    
    Write-Host "  NSGs..." -ForegroundColor Cyan
    $inventory.Resources.NSGs = Get-AzNetworkSecurityGroup
    $inventory.Summary.NSGs = $inventory.Resources.NSGs.Count
    
    Write-Host "  Storage Accounts..." -ForegroundColor Cyan
    $inventory.Resources.StorageAccounts = Get-AzStorageAccount
    $inventory.Summary.StorageAccounts = $inventory.Resources.StorageAccounts.Count
    
    Write-Host "  Key Vaults..." -ForegroundColor Cyan
    $inventory.Resources.KeyVaults = Get-AzKeyVault
    $inventory.Summary.KeyVaults = $inventory.Resources.KeyVaults.Count
    
    Write-Host "  SQL Servers..." -ForegroundColor Cyan
    $inventory.Resources.SQLServers = Get-AzSqlServer
    $inventory.Summary.SQLServers = $inventory.Resources.SQLServers.Count
    
    Write-Host "  App Services..." -ForegroundColor Cyan
    $inventory.Resources.AppServices = Get-AzWebApp
    $inventory.Summary.AppServices = $inventory.Resources.AppServices.Count
    
    Write-Host "  Service Principals..." -ForegroundColor Cyan
    try {
        $inventory.Resources.ServicePrincipals = Get-AzADServicePrincipal
        $inventory.Summary.ServicePrincipals = $inventory.Resources.ServicePrincipals.Count
    } catch {
        $inventory.Summary.ServicePrincipals = 0
    }
    
    Write-Log "Inventory complete - $($inventory.Summary.Keys.Count) types" "SUCCESS"
    return $inventory
}

function Get-IdleResources {
    param([object]$Subscription)
    Write-Log "Detecting idle resources..."
    $idle = @{ IdleVMs = @(); UnattachedDisks = @(); UnattachedNICs = @(); UnusedPublicIPs = @() }
    
    $vms = Get-AzVM
    foreach ($vm in $vms) {
        $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -match "PowerState" }).DisplayStatus
        if ($powerState -match "stopped|deallocated") { $idle.IdleVMs += $vm }
    }
    
    $disks = Get-AzDisk
    $idle.UnattachedDisks = $disks | Where-Object { $_.ManagedBy -eq $null }
    
    $nics = Get-AzNetworkInterface
    $idle.UnattachedNICs = $nics | Where-Object { $_.VirtualMachine -eq $null }
    
    $publicIPs = Get-AzPublicIpAddress
    $idle.UnusedPublicIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
    
    $totalSavings = ($idle.UnattachedDisks.Count * 5) + ($idle.UnusedPublicIPs.Count * 3)
    Write-Log "Idle resources: $($idle.IdleVMs.Count) VMs, $($idle.UnattachedDisks.Count) disks, $($idle.UnattachedNICs.Count) NICs, $($idle.UnusedPublicIPs.Count) IPs - Est. savings: `$$totalSavings/mo" "SUCCESS"
    
    return $idle
}

function Export-Report {
    param([object]$Inventory, [object]$IdleResources, [array]$Findings, [string]$ReportName, [string]$Format = "Both")
    
    if (!(Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $subName = $Inventory.Subscription.Name -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$subName-$timestamp"
    
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        $csvPath = "$ReportPath\$baseFileName.csv"
        if ($Findings.Count -gt 0) {
            $Findings | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "CSV: $csvPath" "SUCCESS"
        }
    }
    
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        $htmlPath = "$ReportPath\$baseFileName.html"
        $html = @"
<!DOCTYPE html>
<html><head><title>$ReportName - $($Inventory.Subscription.Name)</title><meta charset="UTF-8"><style>
body{font-family:'Segoe UI',sans-serif;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
.header{background:linear-gradient(135deg,#0078d4,#00bcf2);color:#fff;padding:30px}
.header h1{font-size:32px;margin:0 0 10px}
.header-info{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin-top:20px}
.header-info-item{background:rgba(255,255,255,0.2);padding:10px 15px;border-radius:5px}
.content{padding:30px}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}
.summary-card{background:linear-gradient(135deg,#f5f7fa,#c3cfe2);padding:20px;border-radius:10px;border-left:4px solid #0078d4}
.summary-card h3{color:#0078d4;font-size:14px;text-transform:uppercase;margin:0 0 10px}
.summary-card .number{font-size:36px;font-weight:bold;color:#333}
table{width:100%;border-collapse:collapse;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-top:20px}
th{background:#0078d4;color:#fff;padding:12px;text-align:left}
td{padding:10px 12px;border-bottom:1px solid #e0e0e0}
tr:hover{background:#f5f5f5}
.critical{color:#d13438;font-weight:bold}
.high{color:#ff8c00;font-weight:bold}
.medium{color:#f7b731}
.low{color:#107c10}
.idle-section{background:#fff4e6;border:2px solid #ff8c00;border-radius:10px;padding:20px;margin:20px 0}
.idle-section h3{color:#ff8c00;margin-bottom:15px}
.footer{background:#f5f5f5;padding:20px;text-align:center;color:#666}
</style></head><body><div class="container">
<div class="header"><h1>$ReportName</h1><div class="header-info">
<div class="header-info-item"><strong>Subscription:</strong><br>$($Inventory.Subscription.Name)</div>
<div class="header-info-item"><strong>Subscription ID:</strong><br>$($Inventory.Subscription.Id)</div>
<div class="header-info-item"><strong>Generated:</strong><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="header-info-item"><strong>Total Findings:</strong><br>$($Findings.Count)</div>
</div></div><div class="content"><div class="summary">
"@
        
        foreach ($key in $Inventory.Summary.Keys | Sort-Object) {
            $html += "<div class='summary-card'><h3>$key</h3><div class='number'>$($Inventory.Summary[$key])</div></div>"
        }
        $html += "</div>"
        
        if ($IdleResources) {
            $totalSavings = ($IdleResources.UnattachedDisks.Count * 5) + ($IdleResources.UnusedPublicIPs.Count * 3)
            $html += @"
<div class='idle-section'><h3>Idle Resources Detected - Cost Savings Opportunity</h3><table>
<tr><th>Resource Type</th><th>Count</th><th>Est. Monthly Savings</th></tr>
<tr><td>Idle/Stopped VMs</td><td>$($IdleResources.IdleVMs.Count)</td><td>Review for compute cost savings</td></tr>
<tr><td>Unattached Disks</td><td>$($IdleResources.UnattachedDisks.Count)</td><td>`$$($IdleResources.UnattachedDisks.Count * 5)/month</td></tr>
<tr><td>Unattached NICs</td><td>$($IdleResources.UnattachedNICs.Count)</td><td>`$$($IdleResources.UnattachedNICs.Count)/month</td></tr>
<tr><td>Unused Public IPs</td><td>$($IdleResources.UnusedPublicIPs.Count)</td><td>`$$($IdleResources.UnusedPublicIPs.Count * 3)/month</td></tr>
<tr style='background:#fff4e6;font-weight:bold'><td colspan='2'>Total Est. Savings:</td><td>`$$totalSavings/month</td></tr>
</table></div>
"@
        }
        
        if ($Findings.Count -gt 0) {
            $html += "<h2>Detailed Findings</h2><table><tr>"
            $Findings[0].PSObject.Properties.Name | ForEach-Object { $html += "<th>$_</th>" }
            $html += "</tr>"
            foreach ($finding in $Findings) {
                $html += "<tr>"
                $finding.PSObject.Properties | ForEach-Object {
                    $value = if ($_.Value) { $_.Value } else { "" }
                    $class = ""
                    if ($_.Name -match "Severity|Priority|Risk|Level") {
                        $class = switch ($value) {
                            "Critical" { " class='critical'" }
                            "High" { " class='high'" }
                            "Medium" { " class='medium'" }
                            "Low" { " class='low'" }
                            default { "" }
                        }
                    }
                    $html += "<td$class>$value</td>"
                }
                $html += "</tr>"
            }
            $html += "</table>"
        }
        
        $html += @"
</div><div class='footer'><p><strong>Azure Production Scripts Suite</strong></p>
<p>Professional Azure audit and compliance reporting</p>
<p>This report is READ-ONLY - No changes were made to your environment</p></div></div></body></html>
"@
        
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Log "HTML: $htmlPath" "SUCCESS"
        Start-Process $htmlPath
    }
}

$sub = Connect-AzureWithSubscription
if (!$sub) { exit 1 }
$inventory = Get-CompleteInventory -Subscription $sub
$idle = Get-IdleResources -Subscription $sub
$findings = @()

Write-Log "Auditing Security Center recommendations..."

try {
    $securityTasks = Get-AzSecurityTask
    
    foreach ($task in $securityTasks) {
        $severity = switch ($task.Properties.severity) {
            "High" { "High" }
            "Medium" { "Medium" }
            "Low" { "Low" }
            default { "Medium" }
        }
        
        $findings += [PSCustomObject]@{
            RecommendationName = $task.Properties.securityTaskParameters.name
            Description = $task.Properties.securityTaskParameters.description
            ResourceName = $task.Properties.securityTaskParameters.resourceId.Split('/')[-1]
            State = $task.Properties.state
            Severity = $severity
            Issue = $task.Properties.securityTaskParameters.name
            Subscription = $sub.Name
        }
    }
} catch {
    Write-Log "Unable to retrieve Security Center tasks - may need Defender for Cloud enabled" "WARNING"
    $findings += [PSCustomObject]@{
        RecommendationName = "Security Center Status"
        Description = "Unable to retrieve security recommendations"
        ResourceName = "Subscription"
        State = "Unknown"
        Severity = "Medium"
        Issue = "Security Center/Defender for Cloud may not be enabled"
        Subscription = $sub.Name
    }
}

Write-Log "Found $($findings.Count) security findings" "SUCCESS"
Export-Report -Inventory $inventory -IdleResources $idle -Findings $findings -ReportName "8-SecurityCenter-Audit" -Format $OutputFormat

