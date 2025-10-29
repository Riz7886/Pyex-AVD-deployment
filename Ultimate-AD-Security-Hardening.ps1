#Requires -Version 5.1
<#
.SYNOPSIS
    Production-Grade Azure Automation Script
.DESCRIPTION
    Professional Azure script with complete inventory, safety features, and reporting
.PARAMETER WhatIf
    Preview changes without executing
.PARAMETER ReadOnly
    Force read-only mode (no changes)
.PARAMETER Confirm
    Prompt before each change
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ReportPath = ".\Reports",
    [string]$OutputFormat = "Both",
    [switch]$WhatIf,
    [switch]$ReadOnly,
    [switch]$Confirm = $true
)

$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

#region Logging Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","CRITICAL")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "CRITICAL" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    
    $logDir = ".\Logs"
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $scriptName = Split-Path $PSCommandPath -Leaf
    $logFile = "$logDir\$($scriptName -replace '\.ps1$','')-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}
#endregion

#region Prerequisites Check
function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Compute", "Az.Storage", "Az.Network", "Az.Monitor")
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (!(Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "Missing required modules: $($missingModules -join ', ')" "ERROR"
        Write-Host ""
        Write-Host "Install with:" -ForegroundColor Yellow
        Write-Host "Install-Module Az -AllowClobber -Scope CurrentUser -Force" -ForegroundColor Cyan
        return $false
    }
    
    Write-Log "All prerequisites met" "SUCCESS"
    return $true
}
#endregion

#region Azure Connection
function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Write-Log "Initiating Azure login..."
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        $currentAccount = (Get-AzContext).Account.Id
        Write-Log "Connected as: $currentAccount" "SUCCESS"
    } catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    Write-Log "Discovering subscriptions..."
    try {
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    } catch {
        Write-Log "Failed to retrieve subscriptions: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    if ($subscriptions.Count -eq 0) {
        Write-Log "No enabled subscriptions found" "ERROR"
        return $null
    }
    
    Write-Log "Found $($subscriptions.Count) enabled subscription(s)" "SUCCESS"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Available Azure Subscriptions" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        Write-Host "  [$($i + 1)] $($sub.Name)" -ForegroundColor White
        Write-Host "      Subscription ID: $($sub.Id)" -ForegroundColor Gray
        Write-Host "      Tenant ID: $($sub.TenantId)" -ForegroundColor Gray
        Write-Host "      State: $($sub.State)" -ForegroundColor Green
        Write-Host ""
    }
    
    do {
        Write-Host "Select subscription number (1-$($subscriptions.Count)) or Q to quit: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
        
        if ($selection -eq 'Q' -or $selection -eq 'q') {
            Write-Log "User cancelled subscription selection" "WARNING"
            return $null
        }
        
        $selectedIndex = $null
        if ([int]::TryParse($selection, [ref]$selectedIndex)) {
            $selectedIndex = $selectedIndex - 1
        }
    } while ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count)
    
    $selectedSub = $subscriptions[$selectedIndex]
    
    try {
        Set-AzContext -SubscriptionId $selectedSub.Id -ErrorAction Stop | Out-Null
        Write-Log "Active subscription: $($selectedSub.Name)" "SUCCESS"
    } catch {
        Write-Log "Failed to set subscription context: $($_.Exception.Message)" "ERROR"
        return $null
    }
    
    Write-Host ""
    return $selectedSub
}
#endregion

#region Complete Azure Inventory Collection
function Get-CompleteAzureInventory {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Subscription
    )
    
    Write-Log "Collecting complete Azure inventory for subscription: $($Subscription.Name)" "INFO"
    
    $inventory = @{
        Subscription = $Subscription
        CollectionTime = Get-Date
        Summary = @{}
        Resources = @{}
    }
    
    try {
        # Get all resource groups
        Write-Log "Collecting Resource Groups..." "INFO"
        $resourceGroups = Get-AzResourceGroup
        $inventory.Resources.ResourceGroups = $resourceGroups
        $inventory.Summary.ResourceGroups = $resourceGroups.Count
        
        # Get all locations/regions used
        Write-Log "Identifying Regions..." "INFO"
        $locations = $resourceGroups | Select-Object -ExpandProperty Location -Unique | Sort-Object
        $inventory.Resources.Regions = $locations
        $inventory.Summary.Regions = $locations.Count
        
        # Virtual Machines
        Write-Log "Collecting Virtual Machines..." "INFO"
        $vms = Get-AzVM
        $inventory.Resources.VirtualMachines = $vms
        $inventory.Summary.VirtualMachines = $vms.Count
        
        # Disks
        Write-Log "Collecting Disks..." "INFO"
        $disks = Get-AzDisk
        $inventory.Resources.Disks = $disks
        $inventory.Summary.Disks = $disks.Count
        
        # Network Interfaces
        Write-Log "Collecting Network Interfaces..." "INFO"
        $nics = Get-AzNetworkInterface
        $inventory.Resources.NetworkInterfaces = $nics
        $inventory.Summary.NetworkInterfaces = $nics.Count
        
        # Virtual Networks
        Write-Log "Collecting Virtual Networks..." "INFO"
        $vnets = Get-AzVirtualNetwork
        $inventory.Resources.VirtualNetworks = $vnets
        $inventory.Summary.VirtualNetworks = $vnets.Count
        
        # Subnets
        Write-Log "Collecting Subnets..." "INFO"
        $subnets = $vnets | ForEach-Object { $_.Subnets }
        $inventory.Resources.Subnets = $subnets
        $inventory.Summary.Subnets = $subnets.Count
        
        # Public IP Addresses
        Write-Log "Collecting Public IP Addresses..." "INFO"
        $publicIPs = Get-AzPublicIpAddress
        $inventory.Resources.PublicIPs = $publicIPs
        $inventory.Summary.PublicIPs = $publicIPs.Count
        
        # Load Balancers
        Write-Log "Collecting Load Balancers..." "INFO"
        $loadBalancers = Get-AzLoadBalancer
        $inventory.Resources.LoadBalancers = $loadBalancers
        $inventory.Summary.LoadBalancers = $loadBalancers.Count
        
        # Application Gateways
        Write-Log "Collecting Application Gateways..." "INFO"
        $appGateways = Get-AzApplicationGateway
        $inventory.Resources.ApplicationGateways = $appGateways
        $inventory.Summary.ApplicationGateways = $appGateways.Count
        
        # Network Security Groups
        Write-Log "Collecting Network Security Groups..." "INFO"
        $nsgs = Get-AzNetworkSecurityGroup
        $inventory.Resources.NetworkSecurityGroups = $nsgs
        $inventory.Summary.NetworkSecurityGroups = $nsgs.Count
        
        # Storage Accounts
        Write-Log "Collecting Storage Accounts..." "INFO"
        $storageAccounts = Get-AzStorageAccount
        $inventory.Resources.StorageAccounts = $storageAccounts
        $inventory.Summary.StorageAccounts = $storageAccounts.Count
        
        # Key Vaults
        Write-Log "Collecting Key Vaults..." "INFO"
        $keyVaults = Get-AzKeyVault
        $inventory.Resources.KeyVaults = $keyVaults
        $inventory.Summary.KeyVaults = $keyVaults.Count
        
        # SQL Servers and Databases
        Write-Log "Collecting SQL Servers and Databases..." "INFO"
        $sqlServers = Get-AzSqlServer
        $inventory.Resources.SQLServers = $sqlServers
        $inventory.Summary.SQLServers = $sqlServers.Count
        
        $sqlDatabases = $sqlServers | ForEach-Object {
            Get-AzSqlDatabase -ServerName $_.ServerName -ResourceGroupName $_.ResourceGroupName |
                Where-Object { $_.DatabaseName -ne "master" }
        }
        $inventory.Resources.SQLDatabases = $sqlDatabases
        $inventory.Summary.SQLDatabases = $sqlDatabases.Count
        
        # App Services
        Write-Log "Collecting App Services..." "INFO"
        $appServices = Get-AzWebApp
        $inventory.Resources.AppServices = $appServices
        $inventory.Summary.AppServices = $appServices.Count
        
        # Service Principals (App Registrations)
        Write-Log "Collecting Service Principals..." "INFO"
        try {
            $servicePrincipals = Get-AzADServicePrincipal
            $inventory.Resources.ServicePrincipals = $servicePrincipals
            $inventory.Summary.ServicePrincipals = $servicePrincipals.Count
        } catch {
            Write-Log "Unable to collect Service Principals: $($_.Exception.Message)" "WARNING"
            $inventory.Summary.ServicePrincipals = 0
        }
        
        # Azure Kubernetes Service
        Write-Log "Collecting AKS Clusters..." "INFO"
        $aksClusters = Get-AzAksCluster
        $inventory.Resources.AKSClusters = $aksClusters
        $inventory.Summary.AKSClusters = $aksClusters.Count
        
        # Container Instances
        Write-Log "Collecting Container Instances..." "INFO"
        $containerInstances = Get-AzContainerGroup
        $inventory.Resources.ContainerInstances = $containerInstances
        $inventory.Summary.ContainerInstances = $containerInstances.Count
        
        # Azure Front Door
        Write-Log "Collecting Front Door Profiles..." "INFO"
        try {
            $frontDoors = Get-AzFrontDoor
            $inventory.Resources.FrontDoors = $frontDoors
            $inventory.Summary.FrontDoors = $frontDoors.Count
        } catch {
            Write-Log "Unable to collect Front Door: $($_.Exception.Message)" "WARNING"
            $inventory.Summary.FrontDoors = 0
        }
        
        # Log Analytics Workspaces
        Write-Log "Collecting Log Analytics Workspaces..." "INFO"
        $logWorkspaces = Get-AzOperationalInsightsWorkspace
        $inventory.Resources.LogAnalyticsWorkspaces = $logWorkspaces
        $inventory.Summary.LogAnalyticsWorkspaces = $logWorkspaces.Count
        
        # Recovery Services Vaults
        Write-Log "Collecting Recovery Services Vaults..." "INFO"
        $recoveryVaults = Get-AzRecoveryServicesVault
        $inventory.Resources.RecoveryServicesVaults = $recoveryVaults
        $inventory.Summary.RecoveryServicesVaults = $recoveryVaults.Count
        
        # Managed Identities
        Write-Log "Collecting Managed Identities..." "INFO"
        try {
            $managedIdentities = Get-AzUserAssignedIdentity
            $inventory.Resources.ManagedIdentities = $managedIdentities
            $inventory.Summary.ManagedIdentities = $managedIdentities.Count
        } catch {
            $inventory.Summary.ManagedIdentities = 0
        }
        
        Write-Log "Inventory collection complete" "SUCCESS"
        Write-Log "Total resource types collected: $($inventory.Summary.Keys.Count)" "SUCCESS"
        
    } catch {
        Write-Log "Error during inventory collection: $($_.Exception.Message)" "ERROR"
    }
    
    return $inventory
}
#endregion

#region Cost Analysis
function Get-ResourceCostAnalysis {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Subscription
    )
    
    Write-Log "Analyzing costs..." "INFO"
    
    $costAnalysis = @{
        SubscriptionName = $Subscription.Name
        AnalysisDate = Get-Date
        EstimatedMonthlyCosts = @{}
        PotentialSavings = @{}
    }
    
    try {
        # Get idle resources for cost savings
        $vms = Get-AzVM
        $idleVMs = @()
        
        foreach ($vm in $vms) {
            $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
            $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -match "PowerState" }).DisplayStatus
            
            if ($powerState -eq "VM deallocated" -or $powerState -eq "VM stopped") {
                $idleVMs += $vm
            }
        }
        
        # Unattached disks
        $disks = Get-AzDisk
        $unattachedDisks = $disks | Where-Object { $_.ManagedBy -eq $null }
        
        # Unattached NICs
        $nics = Get-AzNetworkInterface
        $unattachedNICs = $nics | Where-Object { $_.VirtualMachine -eq $null }
        
        # Unused Public IPs
        $publicIPs = Get-AzPublicIpAddress
        $unusedPublicIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
        
        $costAnalysis.PotentialSavings = @{
            IdleVMs = $idleVMs.Count
            UnattachedDisks = $unattachedDisks.Count
            UnattachedNICs = $unattachedNICs.Count
            UnusedPublicIPs = $unusedPublicIPs.Count
            EstimatedMonthlySavings = ($unattachedDisks.Count * 5) + ($unusedPublicIPs.Count * 3) + ($unattachedNICs.Count * 1)
        }
        
        Write-Log "Cost analysis complete" "SUCCESS"
        
    } catch {
        Write-Log "Error during cost analysis: $($_.Exception.Message)" "WARNING"
    }
    
    return $costAnalysis
}
#endregion

#region Safe Operations Framework
function Invoke-SafeOperation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OperationName,
        [Parameter(Mandatory=$true)]
        [scriptblock]$Operation,
        [string]$ResourceName,
        [string]$ResourceType,
        [string]$Impact = "High"
    )
    
    if ($ReadOnly) {
        Write-Log "READ-ONLY MODE: Would execute $OperationName on $ResourceType '$ResourceName'" "WARNING"
        return @{
            Success = $false
            Message = "READ-ONLY MODE - No changes made"
            Executed = $false
        }
    }
    
    if ($WhatIf) {
        Write-Log "WHATIF: Would execute $OperationName on $ResourceType '$ResourceName'" "WARNING"
        return @{
            Success = $false
            Message = "WHATIF MODE - No changes made"
            Executed = $false
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  CONFIRMATION REQUIRED" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Operation: $OperationName" -ForegroundColor White
    Write-Host "Resource Type: $ResourceType" -ForegroundColor White
    Write-Host "Resource Name: $ResourceName" -ForegroundColor Cyan
    Write-Host "Impact Level: $Impact" -ForegroundColor $(if($Impact -eq "High"){"Red"}else{"Yellow"})
    Write-Host ""
    
    do {
        Write-Host "Proceed with this operation? (Y/N): " -ForegroundColor Yellow -NoNewline
        $response = Read-Host
    } while ($response -notmatch '^[YyNn]$')
    
    if ($response -notmatch '^[Yy]$') {
        Write-Log "Operation cancelled by user" "WARNING"
        return @{
            Success = $false
            Message = "Cancelled by user"
            Executed = $false
        }
    }
    
    try {
        Write-Log "Executing $OperationName on $ResourceName..." "INFO"
        $result = & $Operation
        Write-Log "$OperationName completed successfully" "SUCCESS"
        return @{
            Success = $true
            Message = "Operation completed successfully"
            Executed = $true
            Result = $result
        }
    } catch {
        Write-Log "Error during $OperationName: $($_.Exception.Message)" "ERROR"
        return @{
            Success = $false
            Message = $_.Exception.Message
            Executed = $true
            Error = $_
        }
    }
}

function Select-ResourcesForOperation {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Resources,
        [Parameter(Mandatory=$true)]
        [string]$ResourceType,
        [Parameter(Mandatory=$true)]
        [string]$OperationType
    )
    
    if ($Resources.Count -eq 0) {
        Write-Log "No $ResourceType resources found" "WARNING"
        return @()
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $ResourceType Selection for $OperationType" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Found $($Resources.Count) $ResourceType resource(s)" -ForegroundColor White
    Write-Host ""
    
    for ($i = 0; $i -lt $Resources.Count; $i++) {
        $resource = $Resources[$i]
        Write-Host "  [$($i + 1)] $($resource.Name)" -ForegroundColor White
        if ($resource.ResourceGroupName) {
            Write-Host "      Resource Group: $($resource.ResourceGroupName)" -ForegroundColor Gray
        }
        if ($resource.Location) {
            Write-Host "      Location: $($resource.Location)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  - Enter numbers separated by commas (e.g., 1,3,5)" -ForegroundColor White
    Write-Host "  - Enter 'ALL' to select all resources" -ForegroundColor White
    Write-Host "  - Enter 'NONE' or 'Q' to skip" -ForegroundColor White
    Write-Host ""
    
    $selection = Read-Host "Selection"
    
    if ($selection -eq 'NONE' -or $selection -eq 'Q' -or $selection -eq 'q') {
        Write-Log "No resources selected" "INFO"
        return @()
    }
    
    if ($selection -eq 'ALL') {
        Write-Log "All $($Resources.Count) resources selected" "INFO"
        return $Resources
    }
    
    $indices = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 }
    $selectedResources = $indices | Where-Object { $_ -ge 0 -and $_ -lt $Resources.Count } | ForEach-Object { $Resources[$_] }
    
    Write-Log "Selected $($selectedResources.Count) resource(s)" "INFO"
    return $selectedResources
}
#endregion

#region Advanced Reporting
function Export-ComprehensiveReport {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Inventory,
        [object]$CostAnalysis,
        [array]$DetailedFindings,
        [Parameter(Mandatory=$true)]
        [string]$ReportName,
        [string]$Format = "Both"
    )
    
    if (!(Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $subName = $Inventory.Subscription.Name -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$subName-$timestamp"
    
    $csvPath = "$ReportPath\$baseFileName.csv"
    $htmlPath = "$ReportPath\$baseFileName.html"
    
    # Export CSV
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        try {
            if ($DetailedFindings.Count -gt 0) {
                $DetailedFindings | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Log "CSV report saved: $csvPath" "SUCCESS"
            }
        } catch {
            Write-Log "Error exporting CSV: $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Export HTML
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        try {
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$ReportName - $($Inventory.Subscription.Name)</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #0078d4 0%, #00bcf2 100%);
            color: white;
            padding: 30px;
        }
        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
        }
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .header-info-item {
            background: rgba(255,255,255,0.2);
            padding: 10px 15px;
            border-radius: 5px;
        }
        .content { padding: 30px; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #0078d4;
        }
        .summary-card h3 {
            color: #0078d4;
            font-size: 14px;
            text-transform: uppercase;
            margin-bottom: 10px;
        }
        .summary-card .number {
            font-size: 36px;
            font-weight: bold;
            color: #333;
        }
        .section {
            margin-bottom: 30px;
        }
        .section h2 {
            color: #0078d4;
            border-bottom: 2px solid #0078d4;
            padding-bottom: 10px;
            margin-bottom: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        th {
            background: #0078d4;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        tr:hover {
            background: #f5f5f5;
        }
        .critical { color: #d13438; font-weight: bold; }
        .high { color: #ff8c00; font-weight: bold; }
        .medium { color: #f7b731; }
        .low { color: #107c10; }
        .footer {
            background: #f5f5f5;
            padding: 20px;
            text-align: center;
            color: #666;
            border-top: 1px solid #e0e0e0;
        }
        .cost-savings {
            background: #fff4e6;
            border: 2px solid #ff8c00;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
        }
        .cost-savings h3 {
            color: #ff8c00;
            margin-bottom: 15px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$ReportName</h1>
            <div class="header-info">
                <div class="header-info-item">
                    <strong>Subscription:</strong><br>$($Inventory.Subscription.Name)
                </div>
                <div class="header-info-item">
                    <strong>Subscription ID:</strong><br>$($Inventory.Subscription.Id)
                </div>
                <div class="header-info-item">
                    <strong>Report Generated:</strong><br>$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                </div>
                <div class="header-info-item">
                    <strong>Total Resources:</strong><br>$($DetailedFindings.Count)
                </div>
            </div>
        </div>
        
        <div class="content">
            <div class="summary">
"@
            
            # Add summary cards
            foreach ($key in $Inventory.Summary.Keys | Sort-Object) {
                $value = $Inventory.Summary[$key]
                $html += @"
                <div class="summary-card">
                    <h3>$key</h3>
                    <div class="number">$value</div>
                </div>
"@
            }
            
            $html += "</div>"
            
            # Add cost savings section if applicable
            if ($CostAnalysis -and $CostAnalysis.PotentialSavings) {
                $savings = $CostAnalysis.PotentialSavings
                $html += @"
            <div class="cost-savings">
                <h3>Potential Cost Savings Identified</h3>
                <table>
                    <tr>
                        <th>Resource Type</th>
                        <th>Count</th>
                        <th>Estimated Monthly Savings</th>
                    </tr>
                    <tr>
                        <td>Idle Virtual Machines</td>
                        <td>$($savings.IdleVMs)</td>
                        <td>Review and deallocate to save compute costs</td>
                    </tr>
                    <tr>
                        <td>Unattached Disks</td>
                        <td>$($savings.UnattachedDisks)</td>
                        <td>Approximately `$$($savings.UnattachedDisks * 5)/month</td>
                    </tr>
                    <tr>
                        <td>Unused Public IPs</td>
                        <td>$($savings.UnusedPublicIPs)</td>
                        <td>Approximately `$$($savings.UnusedPublicIPs * 3)/month</td>
                    </tr>
                    <tr>
                        <td>Unattached NICs</td>
                        <td>$($savings.UnattachedNICs)</td>
                        <td>Minimal cost but good housekeeping</td>
                    </tr>
                    <tr style="background: #fff4e6; font-weight: bold;">
                        <td colspan="2">Total Estimated Monthly Savings:</td>
                        <td>`$$($savings.EstimatedMonthlySavings)</td>
                    </tr>
                </table>
            </div>
"@
            }
            
            # Add detailed findings table
            if ($DetailedFindings.Count -gt 0) {
                $html += @"
            <div class="section">
                <h2>Detailed Findings</h2>
                <table>
                    <tr>
"@
                
                $DetailedFindings[0].PSObject.Properties.Name | ForEach-Object {
                    $html += "                        <th>$_</th>`n"
                }
                
                $html += "                    </tr>`n"
                
                foreach ($finding in $DetailedFindings) {
                    $html += "                    <tr>`n"
                    $finding.PSObject.Properties | ForEach-Object {
                        $value = if ($_.Value) { $_.Value } else { "" }
                        $class = ""
                        
                        if ($_.Name -match "Severity|Priority|Risk|Impact") {
                            $class = switch ($value) {
                                "Critical" { " class='critical'" }
                                "High" { " class='high'" }
                                "Medium" { " class='medium'" }
                                "Low" { " class='low'" }
                                default { "" }
                            }
                        }
                        
                        $html += "                        <td$class>$value</td>`n"
                    }
                    $html += "                    </tr>`n"
                }
                
                $html += "                </table>`n"
                $html += "            </div>`n"
            }
            
            $html += @"
        </div>
        
        <div class="footer">
            <p><strong>Azure Production Scripts Suite</strong></p>
            <p>Professional-grade Azure automation and reporting</p>
            <p>This report is READ-ONLY. No changes were made to your Azure environment.</p>
        </div>
    </div>
</body>
</html>
"@
            
            $html | Out-File -FilePath $htmlPath -Encoding UTF8
            Write-Log "HTML report saved: $htmlPath" "SUCCESS"
            
            Start-Process $htmlPath
            
        } catch {
            Write-Log "Error exporting HTML: $($_.Exception.Message)" "ERROR"
        }
    }
    
    return @{
        CSV = $csvPath
        HTML = $htmlPath
        RecordCount = $DetailedFindings.Count
    }
}
#endregion

$subscription = Connect-AzureWithSubscription
if (!$subscription) { exit 1 }

$inventory = Get-CompleteAzureInventory -Subscription $subscription
$costAnalysis = Get-ResourceCostAnalysis -Subscription $subscription

# Placeholder implementation - replace with actual logic
$findings = @()
$findings += [PSCustomObject]@{
    Note = "Script framework ready - specific implementation needed"
    Subscription = $subscription.Name
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

Export-ComprehensiveReport -Inventory $inventory -CostAnalysis $costAnalysis -DetailedFindings $findings -ReportName "Ultimate-AD-Security-Hardening" -Format $OutputFormat
