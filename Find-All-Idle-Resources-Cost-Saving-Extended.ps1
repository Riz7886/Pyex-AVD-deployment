#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ReportPath = ".\Reports",
    [string]$OutputFormat = "Both",
    [switch]$WhatIf,
    [switch]$ReadOnly,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

#region Auto-Install Az Modules
function Install-AzModulesIfNeeded {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Storage", "Az.Network", "Az.Monitor", "Az.KeyVault", "Az.Sql")
    
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "Installing required Azure modules..." -ForegroundColor Yellow
        Write-Host "Modules needed: $($missingModules -join ', ')" -ForegroundColor Cyan
        
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            Install-Module Az -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "Azure modules installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to install Azure modules" -ForegroundColor Red
            Write-Host "Please run manually: Install-Module Az -Force -AllowClobber -Scope CurrentUser" -ForegroundColor Yellow
            exit 1
        }
    }
    
    foreach ($module in $requiredModules) {
        Import-Module $module -ErrorAction SilentlyContinue
    }
}

Install-AzModulesIfNeeded
#endregion

#region Logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $logMessage -ForegroundColor $color
    
    $logDir = ".\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = "$logDir\$($MyInvocation.ScriptName -replace '\.ps1$','')-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}
#endregion

#region Azure Connection
function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Log "Connected to Azure as: $((Get-AzContext).Account.Id)" "SUCCESS"
    } catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    try {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    } catch {
        Write-Log "Failed to get subscriptions: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    if ($subscriptions.Count -eq 0) {
        Write-Log "No enabled subscriptions found" "ERROR"
        return $null
    }
    
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
        Write-Host "      ID: $($subscriptions[$i].Id)" -ForegroundColor Gray
        Write-Host ""
    }
    
    do {
        Write-Host "Select subscription (1-$($subscriptions.Count)) or Q to quit: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        if ($selection -eq 'Q' -or $selection -eq 'q') { return $null }
        $selectedIndex = [int]$selection - 1
    } while ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count)
    
    $selectedSub = $subscriptions[$selectedIndex]
    Set-AzContext -SubscriptionId $selectedSub.Id -ErrorAction Stop | Out-Null

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
    [string]$OutputFormat = "Both",
    [switch]$WhatIf,
    [switch]$ReadOnly,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

#region Auto-Install Az Modules
function Install-AzModulesIfNeeded {
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Storage", "Az.Network", "Az.Monitor", "Az.KeyVault", "Az.Sql")
    
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "Installing required Azure modules..." -ForegroundColor Yellow
        Write-Host "Modules needed: $($missingModules -join ', ')" -ForegroundColor Cyan
        
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            Install-Module Az -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Host "Azure modules installed successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to install Azure modules" -ForegroundColor Red
            Write-Host "Please run manually: Install-Module Az -Force -AllowClobber -Scope CurrentUser" -ForegroundColor Yellow
            exit 1
        }
    }
    
    foreach ($module in $requiredModules) {
        Import-Module $module -ErrorAction SilentlyContinue
    }
}

Install-AzModulesIfNeeded
#endregion

#region Logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
    Write-Host $logMessage -ForegroundColor $color
    
    $logDir = ".\Logs"
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = "$logDir\$($MyInvocation.ScriptName -replace '\.ps1$','')-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}
#endregion

#region Azure Connection
function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Log "Connected to Azure as: $((Get-AzContext).Account.Id)" "SUCCESS"
    } catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    try {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    } catch {
        Write-Log "Failed to get subscriptions: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    if ($subscriptions.Count -eq 0) {
        Write-Log "No enabled subscriptions found" "ERROR"
        return $null
    }
    
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "  [$($i + 1)] $($subscriptions[$i].Name)" -ForegroundColor White
        Write-Host "      ID: $($subscriptions[$i].Id)" -ForegroundColor Gray
        Write-Host ""
    }
    
    do {
        Write-Host "Select subscription (1-$($subscriptions.Count)) or Q to quit: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        if ($selection -eq 'Q' -or $selection -eq 'q') { return $null }
        $selectedIndex = [int]$selection - 1
    } while ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count)
    
    $selectedSub = $subscriptions[$selectedIndex]
    Set-AzContext -SubscriptionId $selectedSub.Id -ErrorAction Stop | Out-Null
    Write-Log "Active subscription: $($selectedSub.Name)" "SUCCESS"
    Write-Host ""
    
    return $selectedSub
}
#endregion

#region Complete Inventory
function Get-CompleteAzureInventory {
    param([object]$Subscription)
    
    Write-Log "Collecting complete Azure inventory..."
    
    $inventory = @{
        Subscription = $Subscription
        CollectionTime = Get-Date
        Summary = @{}
        Resources = @{}
    }
    
    try {
        Write-Host "  Collecting Resource Groups..." -ForegroundColor Cyan
        $inventory.Resources.ResourceGroups = Get-AzResourceGroup
        $inventory.Summary.ResourceGroups = $inventory.Resources.ResourceGroups.Count
        
        Write-Host "  Collecting Virtual Machines..." -ForegroundColor Cyan
        $inventory.Resources.VirtualMachines = Get-AzVM
        $inventory.Summary.VirtualMachines = $inventory.Resources.VirtualMachines.Count
        
        Write-Host "  Collecting Disks..." -ForegroundColor Cyan
        $inventory.Resources.Disks = Get-AzDisk
        $inventory.Summary.Disks = $inventory.Resources.Disks.Count
        
        Write-Host "  Collecting Network Interfaces..." -ForegroundColor Cyan
        $inventory.Resources.NetworkInterfaces = Get-AzNetworkInterface
        $inventory.Summary.NetworkInterfaces = $inventory.Resources.NetworkInterfaces.Count
        
        Write-Host "  Collecting Virtual Networks..." -ForegroundColor Cyan
        $inventory.Resources.VirtualNetworks = Get-AzVirtualNetwork
        $inventory.Summary.VirtualNetworks = $inventory.Resources.VirtualNetworks.Count
        
        Write-Host "  Collecting Subnets..." -ForegroundColor Cyan
        $subnets = $inventory.Resources.VirtualNetworks | ForEach-Object { $_.Subnets }
        $inventory.Resources.Subnets = $subnets
        $inventory.Summary.Subnets = $subnets.Count
        
        Write-Host "  Collecting Public IPs..." -ForegroundColor Cyan
        $inventory.Resources.PublicIPs = Get-AzPublicIpAddress
        $inventory.Summary.PublicIPs = $inventory.Resources.PublicIPs.Count
        
        Write-Host "  Collecting Load Balancers..." -ForegroundColor Cyan
        $inventory.Resources.LoadBalancers = Get-AzLoadBalancer
        $inventory.Summary.LoadBalancers = $inventory.Resources.LoadBalancers.Count
        
        Write-Host "  Collecting NSGs..." -ForegroundColor Cyan
        $inventory.Resources.NetworkSecurityGroups = Get-AzNetworkSecurityGroup
        $inventory.Summary.NetworkSecurityGroups = $inventory.Resources.NetworkSecurityGroups.Count
        
        Write-Host "  Collecting Storage Accounts..." -ForegroundColor Cyan
        $inventory.Resources.StorageAccounts = Get-AzStorageAccount
        $inventory.Summary.StorageAccounts = $inventory.Resources.StorageAccounts.Count
        
        Write-Host "  Collecting Key Vaults..." -ForegroundColor Cyan
        $inventory.Resources.KeyVaults = Get-AzKeyVault
        $inventory.Summary.KeyVaults = $inventory.Resources.KeyVaults.Count
        
        Write-Host "  Collecting SQL Servers..." -ForegroundColor Cyan
        $inventory.Resources.SQLServers = Get-AzSqlServer
        $inventory.Summary.SQLServers = $inventory.Resources.SQLServers.Count
        
        Write-Host "  Collecting App Services..." -ForegroundColor Cyan
        $inventory.Resources.AppServices = Get-AzWebApp
        $inventory.Summary.AppServices = $inventory.Resources.AppServices.Count
        
        Write-Host "  Collecting Service Principals..." -ForegroundColor Cyan
        try {
            $inventory.Resources.ServicePrincipals = Get-AzADServicePrincipal
            $inventory.Summary.ServicePrincipals = $inventory.Resources.ServicePrincipals.Count
        } catch {
            $inventory.Summary.ServicePrincipals = 0
        }
        
        Write-Log "Inventory collection complete - $($inventory.Summary.Keys.Count) resource types" "SUCCESS"
    } catch {
        Write-Log "Error during inventory: $($_.Exception.Message)" "ERROR"
    }
    
    return $inventory
}
#endregion

#region Cost Analysis
function Get-CostAnalysis {
    param([object]$Subscription)
    
    $costAnalysis = @{
        SubscriptionName = $Subscription.Name
        PotentialSavings = @{}
    }
    
    try {
        $vms = Get-AzVM
        $idleVMs = @()
        foreach ($vm in $vms) {
            $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
            $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -match "PowerState" }).DisplayStatus
            if ($powerState -match "stopped|deallocated") { $idleVMs += $vm }
        }
        
        $disks = Get-AzDisk
        $unattachedDisks = $disks | Where-Object { $_.ManagedBy -eq $null }
        
        $nics = Get-AzNetworkInterface
        $unattachedNICs = $nics | Where-Object { $_.VirtualMachine -eq $null }
        
        $publicIPs = Get-AzPublicIpAddress
        $unusedPublicIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
        
        $costAnalysis.PotentialSavings = @{
            IdleVMs = $idleVMs.Count
            UnattachedDisks = $unattachedDisks.Count
            UnattachedNICs = $unattachedNICs.Count
            UnusedPublicIPs = $unusedPublicIPs.Count
            EstimatedMonthlySavings = ($unattachedDisks.Count * 5) + ($unusedPublicIPs.Count * 3)
        }
    } catch {
        Write-Log "Error during cost analysis: $($_.Exception.Message)" "WARNING"
    }
    
    return $costAnalysis
}
#endregion

#region Safe Operations
function Invoke-SafeOperation {
    param(
        [string]$OperationName,
        [scriptblock]$Operation,
        [string]$ResourceName,
        [string]$ResourceType
    )
    
    if ($ReadOnly) {
        Write-Log "READ-ONLY: Would execute $OperationName on $ResourceName" "WARNING"
        return @{ Success = $false; Message = "READ-ONLY MODE"; Executed = $false }
    }
    
    if ($WhatIf) {
        Write-Log "WHATIF: Would execute $OperationName on $ResourceName" "WARNING"
        return @{ Success = $false; Message = "WHATIF MODE"; Executed = $false }
    }
    
    if (!$Force) {
        Write-Host ""
        Write-Host "CONFIRMATION REQUIRED:" -ForegroundColor Yellow
        Write-Host "Operation: $OperationName" -ForegroundColor White
        Write-Host "Resource: $ResourceName ($ResourceType)" -ForegroundColor Cyan
        do { $response = Read-Host "Proceed? (Y/N)" } while ($response -notmatch '^[YyNn]$')
        if ($response -notmatch '^[Yy]$') {
            Write-Log "Operation cancelled by user" "WARNING"
            return @{ Success = $false; Message = "Cancelled"; Executed = $false }
        }
    }
    
    try {
        Write-Log "Executing $OperationName..."
        $result = & $Operation
        Write-Log "$OperationName completed successfully" "SUCCESS"
        return @{ Success = $true; Message = "Success"; Executed = $true; Result = $result }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @{ Success = $false; Message = $_.Exception.Message; Executed = $true; Error = $_ }
    }
}

function Select-ResourcesForOperation {
    param([array]$Resources, [string]$ResourceType, [string]$OperationType)
    
    if ($Resources.Count -eq 0) {
        Write-Log "No $ResourceType resources found" "WARNING"
        return @()
    }
    
    Write-Host ""
    Write-Host "$ResourceType Selection for $OperationType" -ForegroundColor Cyan
    Write-Host "Found $($Resources.Count) resource(s)" -ForegroundColor White
    Write-Host ""
    
    for ($i = 0; $i -lt $Resources.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Resources[$i].Name)" -ForegroundColor White
        if ($Resources[$i].ResourceGroupName) {
            Write-Host "      Resource Group: $($Resources[$i].ResourceGroupName)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "Enter numbers (e.g., 1,3,5), ALL, or NONE: " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host
    
    if ($selection -eq 'NONE' -or $selection -eq 'Q') { return @() }
    if ($selection -eq 'ALL') { return $Resources }
    
    $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
    $selected = $indices | Where-Object { $_ -ge 0 -and $_ -lt $Resources.Count } | ForEach-Object { $Resources[$_] }
    
    return $selected
}
#endregion

#region Reporting
function Export-ComprehensiveReport {
    param(
        [object]$Inventory,
        [object]$CostAnalysis,
        [array]$DetailedFindings,
        [string]$ReportName,
        [string]$Format = "Both"
    )
    
    if (!(Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $subName = $Inventory.Subscription.Name -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$subName-$timestamp"
    
    $csvPath = "$ReportPath\$baseFileName.csv"
    $htmlPath = "$ReportPath\$baseFileName.html"
    
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        if ($DetailedFindings.Count -gt 0) {
            $DetailedFindings | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "CSV: $csvPath" "SUCCESS"
        }
    }
    
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        $html = @"
<!DOCTYPE html>
<html><head><title>$ReportName</title><meta charset="UTF-8"><style>
body{font-family:'Segoe UI',sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2);overflow:hidden}
.header{background:linear-gradient(135deg,#0078d4 0%,#00bcf2 100%);color:#fff;padding:30px}
.header h1{font-size:32px;margin:0 0 20px 0}
.header-info{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px}
.header-info-item{background:rgba(255,255,255,0.2);padding:10px 15px;border-radius:5px}
.content{padding:30px}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}
.summary-card{background:linear-gradient(135deg,#f5f7fa 0%,#c3cfe2 100%);padding:20px;border-radius:10px;border-left:4px solid #0078d4}
.summary-card h3{color:#0078d4;font-size:14px;text-transform:uppercase;margin:0 0 10px 0}
.summary-card .number{font-size:36px;font-weight:bold;color:#333}
table{width:100%;border-collapse:collapse;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-top:20px}
th{background:#0078d4;color:#fff;padding:12px;text-align:left}
td{padding:10px 12px;border-bottom:1px solid #e0e0e0}
tr:hover{background:#f5f5f5}
.critical{color:#d13438;font-weight:bold}
.high{color:#ff8c00;font-weight:bold}
.medium{color:#f7b731}
.low{color:#107c10}
.cost-savings{background:#fff4e6;border:2px solid #ff8c00;border-radius:10px;padding:20px;margin:20px 0}
.footer{background:#f5f5f5;padding:20px;text-align:center;color:#666}
</style></head><body><div class="container">
<div class="header"><h1>$ReportName</h1><div class="header-info">
<div class="header-info-item"><strong>Subscription:</strong><br>$($Inventory.Subscription.Name)</div>
<div class="header-info-item"><strong>Generated:</strong><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="header-info-item"><strong>Total Records:</strong><br>$($DetailedFindings.Count)</div>
</div></div><div class="content"><div class="summary">
"@
        
        foreach ($key in $Inventory.Summary.Keys | Sort-Object) {
            $html += "<div class='summary-card'><h3>$key</h3><div class='number'>$($Inventory.Summary[$key])</div></div>"
        }
        
        if ($CostAnalysis -and $CostAnalysis.PotentialSavings) {
            $savings = $CostAnalysis.PotentialSavings
            $html += @"
</div><div class='cost-savings'><h3>Potential Cost Savings</h3><table>
<tr><th>Resource Type</th><th>Count</th><th>Est. Monthly Savings</th></tr>
<tr><td>Idle VMs</td><td>$($savings.IdleVMs)</td><td>Review to save compute costs</td></tr>
<tr><td>Unattached Disks</td><td>$($savings.UnattachedDisks)</td><td>`$$($savings.UnattachedDisks * 5)</td></tr>
<tr><td>Unused Public IPs</td><td>$($savings.UnusedPublicIPs)</td><td>`$$($savings.UnusedPublicIPs * 3)</td></tr>
<tr><td>Unattached NICs</td><td>$($savings.UnattachedNICs)</td><td>Minimal</td></tr>
<tr style='background:#fff4e6;font-weight:bold'><td colspan='2'>Total Est. Savings:</td><td>`$$($savings.EstimatedMonthlySavings)/month</td></tr>
</table></div>
"@
        } else {
            $html += "</div>"
        }
        
        if ($DetailedFindings.Count -gt 0) {
            $html += "<h2>Detailed Findings</h2><table><tr>"
            $DetailedFindings[0].PSObject.Properties.Name | ForEach-Object { $html += "<th>$_</th>" }
            $html += "</tr>"
            
            foreach ($finding in $DetailedFindings) {
                $html += "<tr>"
                $finding.PSObject.Properties | ForEach-Object {
                    $value = if ($_.Value) { $_.Value } else { "" }
                    $class = ""
                    if ($_.Name -match "Severity|Priority|Risk") {
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
<p>Professional Azure automation and reporting</p></div></div></body></html>
"@
        
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Log "HTML: $htmlPath" "SUCCESS"
        Start-Process $htmlPath
    }
    
    return @{ CSV = $csvPath; HTML = $htmlPath; RecordCount = $DetailedFindings.Count }
}
#endregion

$subscription = Connect-AzureWithSubscription
if (!$subscription) { exit 1 }
$inventory = Get-CompleteAzureInventory -Subscription $subscription
$costAnalysis = Get-CostAnalysis -Subscription $subscription
$findings = @()
$findings += [PSCustomObject]@{
    Status = "Complete"
    Message = "Script executed successfully"
    Subscription = $subscription.Name
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}
Export-ComprehensiveReport -Inventory $inventory -CostAnalysis $costAnalysis -DetailedFindings $findings -ReportName "Find-All-Idle-Resources-Cost-Saving-Extended" -Format $OutputFormat
" -ForegroundColor Yellow
}
# ========================================
    Write-Log "Active subscription: $($selectedSub.Name)" "SUCCESS"
    Write-Host ""
    
    return $selectedSub
}
#endregion

#region Complete Inventory
function Get-CompleteAzureInventory {
    param([object]$Subscription)
    
    Write-Log "Collecting complete Azure inventory..."
    
    $inventory = @{
        Subscription = $Subscription
        CollectionTime = Get-Date
        Summary = @{}
        Resources = @{}
    }
    
    try {
        Write-Host "  Collecting Resource Groups..." -ForegroundColor Cyan
        $inventory.Resources.ResourceGroups = Get-AzResourceGroup
        $inventory.Summary.ResourceGroups = $inventory.Resources.ResourceGroups.Count
        
        Write-Host "  Collecting Virtual Machines..." -ForegroundColor Cyan
        $inventory.Resources.VirtualMachines = Get-AzVM
        $inventory.Summary.VirtualMachines = $inventory.Resources.VirtualMachines.Count
        
        Write-Host "  Collecting Disks..." -ForegroundColor Cyan
        $inventory.Resources.Disks = Get-AzDisk
        $inventory.Summary.Disks = $inventory.Resources.Disks.Count
        
        Write-Host "  Collecting Network Interfaces..." -ForegroundColor Cyan
        $inventory.Resources.NetworkInterfaces = Get-AzNetworkInterface
        $inventory.Summary.NetworkInterfaces = $inventory.Resources.NetworkInterfaces.Count
        
        Write-Host "  Collecting Virtual Networks..." -ForegroundColor Cyan
        $inventory.Resources.VirtualNetworks = Get-AzVirtualNetwork
        $inventory.Summary.VirtualNetworks = $inventory.Resources.VirtualNetworks.Count
        
        Write-Host "  Collecting Subnets..." -ForegroundColor Cyan
        $subnets = $inventory.Resources.VirtualNetworks | ForEach-Object { $_.Subnets }
        $inventory.Resources.Subnets = $subnets
        $inventory.Summary.Subnets = $subnets.Count
        
        Write-Host "  Collecting Public IPs..." -ForegroundColor Cyan
        $inventory.Resources.PublicIPs = Get-AzPublicIpAddress
        $inventory.Summary.PublicIPs = $inventory.Resources.PublicIPs.Count
        
        Write-Host "  Collecting Load Balancers..." -ForegroundColor Cyan
        $inventory.Resources.LoadBalancers = Get-AzLoadBalancer
        $inventory.Summary.LoadBalancers = $inventory.Resources.LoadBalancers.Count
        
        Write-Host "  Collecting NSGs..." -ForegroundColor Cyan
        $inventory.Resources.NetworkSecurityGroups = Get-AzNetworkSecurityGroup
        $inventory.Summary.NetworkSecurityGroups = $inventory.Resources.NetworkSecurityGroups.Count
        
        Write-Host "  Collecting Storage Accounts..." -ForegroundColor Cyan
        $inventory.Resources.StorageAccounts = Get-AzStorageAccount
        $inventory.Summary.StorageAccounts = $inventory.Resources.StorageAccounts.Count
        
        Write-Host "  Collecting Key Vaults..." -ForegroundColor Cyan
        $inventory.Resources.KeyVaults = Get-AzKeyVault
        $inventory.Summary.KeyVaults = $inventory.Resources.KeyVaults.Count
        
        Write-Host "  Collecting SQL Servers..." -ForegroundColor Cyan
        $inventory.Resources.SQLServers = Get-AzSqlServer
        $inventory.Summary.SQLServers = $inventory.Resources.SQLServers.Count
        
        Write-Host "  Collecting App Services..." -ForegroundColor Cyan
        $inventory.Resources.AppServices = Get-AzWebApp
        $inventory.Summary.AppServices = $inventory.Resources.AppServices.Count
        
        Write-Host "  Collecting Service Principals..." -ForegroundColor Cyan
        try {
            $inventory.Resources.ServicePrincipals = Get-AzADServicePrincipal
            $inventory.Summary.ServicePrincipals = $inventory.Resources.ServicePrincipals.Count
        } catch {
            $inventory.Summary.ServicePrincipals = 0
        }
        
        Write-Log "Inventory collection complete - $($inventory.Summary.Keys.Count) resource types" "SUCCESS"
    } catch {
        Write-Log "Error during inventory: $($_.Exception.Message)" "ERROR"
    }
    
    return $inventory
}
#endregion

#region Cost Analysis
function Get-CostAnalysis {
    param([object]$Subscription)
    
    $costAnalysis = @{
        SubscriptionName = $Subscription.Name
        PotentialSavings = @{}
    }
    
    try {
        $vms = Get-AzVM
        $idleVMs = @()
        foreach ($vm in $vms) {
            $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
            $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -match "PowerState" }).DisplayStatus
            if ($powerState -match "stopped|deallocated") { $idleVMs += $vm }
        }
        
        $disks = Get-AzDisk
        $unattachedDisks = $disks | Where-Object { $_.ManagedBy -eq $null }
        
        $nics = Get-AzNetworkInterface
        $unattachedNICs = $nics | Where-Object { $_.VirtualMachine -eq $null }
        
        $publicIPs = Get-AzPublicIpAddress
        $unusedPublicIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
        
        $costAnalysis.PotentialSavings = @{
            IdleVMs = $idleVMs.Count
            UnattachedDisks = $unattachedDisks.Count
            UnattachedNICs = $unattachedNICs.Count
            UnusedPublicIPs = $unusedPublicIPs.Count
            EstimatedMonthlySavings = ($unattachedDisks.Count * 5) + ($unusedPublicIPs.Count * 3)
        }
    } catch {
        Write-Log "Error during cost analysis: $($_.Exception.Message)" "WARNING"
    }
    
    return $costAnalysis
}
#endregion

#region Safe Operations
function Invoke-SafeOperation {
    param(
        [string]$OperationName,
        [scriptblock]$Operation,
        [string]$ResourceName,
        [string]$ResourceType
    )
    
    if ($ReadOnly) {
        Write-Log "READ-ONLY: Would execute $OperationName on $ResourceName" "WARNING"
        return @{ Success = $false; Message = "READ-ONLY MODE"; Executed = $false }
    }
    
    if ($WhatIf) {
        Write-Log "WHATIF: Would execute $OperationName on $ResourceName" "WARNING"
        return @{ Success = $false; Message = "WHATIF MODE"; Executed = $false }
    }
    
    if (!$Force) {
        Write-Host ""
        Write-Host "CONFIRMATION REQUIRED:" -ForegroundColor Yellow
        Write-Host "Operation: $OperationName" -ForegroundColor White
        Write-Host "Resource: $ResourceName ($ResourceType)" -ForegroundColor Cyan
        do { $response = Read-Host "Proceed? (Y/N)" } while ($response -notmatch '^[YyNn]$')
        if ($response -notmatch '^[Yy]$') {
            Write-Log "Operation cancelled by user" "WARNING"
            return @{ Success = $false; Message = "Cancelled"; Executed = $false }
        }
    }
    
    try {
        Write-Log "Executing $OperationName..."
        $result = & $Operation
        Write-Log "$OperationName completed successfully" "SUCCESS"
        return @{ Success = $true; Message = "Success"; Executed = $true; Result = $result }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @{ Success = $false; Message = $_.Exception.Message; Executed = $true; Error = $_ }
    }
}

function Select-ResourcesForOperation {
    param([array]$Resources, [string]$ResourceType, [string]$OperationType)
    
    if ($Resources.Count -eq 0) {
        Write-Log "No $ResourceType resources found" "WARNING"
        return @()
    }
    
    Write-Host ""
    Write-Host "$ResourceType Selection for $OperationType" -ForegroundColor Cyan
    Write-Host "Found $($Resources.Count) resource(s)" -ForegroundColor White
    Write-Host ""
    
    for ($i = 0; $i -lt $Resources.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Resources[$i].Name)" -ForegroundColor White
        if ($Resources[$i].ResourceGroupName) {
            Write-Host "      Resource Group: $($Resources[$i].ResourceGroupName)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "Enter numbers (e.g., 1,3,5), ALL, or NONE: " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host
    
    if ($selection -eq 'NONE' -or $selection -eq 'Q') { return @() }
    if ($selection -eq 'ALL') { return $Resources }
    
    $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
    $selected = $indices | Where-Object { $_ -ge 0 -and $_ -lt $Resources.Count } | ForEach-Object { $Resources[$_] }
    
    return $selected
}
#endregion

#region Reporting
function Export-ComprehensiveReport {
    param(
        [object]$Inventory,
        [object]$CostAnalysis,
        [array]$DetailedFindings,
        [string]$ReportName,
        [string]$Format = "Both"
    )
    
    if (!(Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $subName = $Inventory.Subscription.Name -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$subName-$timestamp"
    
    $csvPath = "$ReportPath\$baseFileName.csv"
    $htmlPath = "$ReportPath\$baseFileName.html"
    
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        if ($DetailedFindings.Count -gt 0) {
            $DetailedFindings | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "CSV: $csvPath" "SUCCESS"
        }
    }
    
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        $html = @"
<!DOCTYPE html>
<html><head><title>$ReportName</title><meta charset="UTF-8"><style>
body{font-family:'Segoe UI',sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2);overflow:hidden}
.header{background:linear-gradient(135deg,#0078d4 0%,#00bcf2 100%);color:#fff;padding:30px}
.header h1{font-size:32px;margin:0 0 20px 0}
.header-info{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px}
.header-info-item{background:rgba(255,255,255,0.2);padding:10px 15px;border-radius:5px}
.content{padding:30px}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-bottom:30px}
.summary-card{background:linear-gradient(135deg,#f5f7fa 0%,#c3cfe2 100%);padding:20px;border-radius:10px;border-left:4px solid #0078d4}
.summary-card h3{color:#0078d4;font-size:14px;text-transform:uppercase;margin:0 0 10px 0}
.summary-card .number{font-size:36px;font-weight:bold;color:#333}
table{width:100%;border-collapse:collapse;background:#fff;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-top:20px}
th{background:#0078d4;color:#fff;padding:12px;text-align:left}
td{padding:10px 12px;border-bottom:1px solid #e0e0e0}
tr:hover{background:#f5f5f5}
.critical{color:#d13438;font-weight:bold}
.high{color:#ff8c00;font-weight:bold}
.medium{color:#f7b731}
.low{color:#107c10}
.cost-savings{background:#fff4e6;border:2px solid #ff8c00;border-radius:10px;padding:20px;margin:20px 0}
.footer{background:#f5f5f5;padding:20px;text-align:center;color:#666}
</style></head><body><div class="container">
<div class="header"><h1>$ReportName</h1><div class="header-info">
<div class="header-info-item"><strong>Subscription:</strong><br>$($Inventory.Subscription.Name)</div>
<div class="header-info-item"><strong>Generated:</strong><br>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="header-info-item"><strong>Total Records:</strong><br>$($DetailedFindings.Count)</div>
</div></div><div class="content"><div class="summary">
"@
        
        foreach ($key in $Inventory.Summary.Keys | Sort-Object) {
            $html += "<div class='summary-card'><h3>$key</h3><div class='number'>$($Inventory.Summary[$key])</div></div>"
        }
        
        if ($CostAnalysis -and $CostAnalysis.PotentialSavings) {
            $savings = $CostAnalysis.PotentialSavings
            $html += @"
</div><div class='cost-savings'><h3>Potential Cost Savings</h3><table>
<tr><th>Resource Type</th><th>Count</th><th>Est. Monthly Savings</th></tr>
<tr><td>Idle VMs</td><td>$($savings.IdleVMs)</td><td>Review to save compute costs</td></tr>
<tr><td>Unattached Disks</td><td>$($savings.UnattachedDisks)</td><td>`$$($savings.UnattachedDisks * 5)</td></tr>
<tr><td>Unused Public IPs</td><td>$($savings.UnusedPublicIPs)</td><td>`$$($savings.UnusedPublicIPs * 3)</td></tr>
<tr><td>Unattached NICs</td><td>$($savings.UnattachedNICs)</td><td>Minimal</td></tr>
<tr style='background:#fff4e6;font-weight:bold'><td colspan='2'>Total Est. Savings:</td><td>`$$($savings.EstimatedMonthlySavings)/month</td></tr>
</table></div>
"@
        } else {
            $html += "</div>"
        }
        
        if ($DetailedFindings.Count -gt 0) {
            $html += "<h2>Detailed Findings</h2><table><tr>"
            $DetailedFindings[0].PSObject.Properties.Name | ForEach-Object { $html += "<th>$_</th>" }
            $html += "</tr>"
            
            foreach ($finding in $DetailedFindings) {
                $html += "<tr>"
                $finding.PSObject.Properties | ForEach-Object {
                    $value = if ($_.Value) { $_.Value } else { "" }
                    $class = ""
                    if ($_.Name -match "Severity|Priority|Risk") {
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
<p>Professional Azure automation and reporting</p></div></div></body></html>
"@
        
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Log "HTML: $htmlPath" "SUCCESS"
        Start-Process $htmlPath
    }
    
    return @{ CSV = $csvPath; HTML = $htmlPath; RecordCount = $DetailedFindings.Count }
}
#endregion

$subscription = Connect-AzureWithSubscription
if (!$subscription) { exit 1 }
$inventory = Get-CompleteAzureInventory -Subscription $subscription
$costAnalysis = Get-CostAnalysis -Subscription $subscription
$findings = @()
$findings += [PSCustomObject]@{
    Status = "Complete"
    Message = "Script executed successfully"
    Subscription = $subscription.Name
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}
Export-ComprehensiveReport -Inventory $inventory -CostAnalysis $costAnalysis -DetailedFindings $findings -ReportName "Find-All-Idle-Resources-Cost-Saving-Extended" -Format $OutputFormat

