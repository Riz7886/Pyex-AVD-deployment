# Azure Multi-Subscription Cost Analysis
# Generates separate HTML and CSV reports for each of the 13 subscriptions
# Author: Automated Script
# Date: 2025-10-30

param(
    [string]$OutputPath = "C:\Scripts\Reports\CostAnalysis",
    [switch]$OpenReports
)

# Create output directory
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "=== Azure Multi-Subscription Cost Analysis ===" -ForegroundColor Cyan
Write-Host "Output Directory: $OutputPath" -ForegroundColor Gray
Write-Host ""

# Define all 13 subscriptions
$subscriptions = @(
    @{Name="Production"; ID="prod-subscription-id"},
    @{Name="Development"; ID="dev-subscription-id"},
    @{Name="Staging"; ID="staging-subscription-id"},
    @{Name="Testing"; ID="test-subscription-id"},
    @{Name="DR-Primary"; ID="dr-primary-id"},
    @{Name="DR-Secondary"; ID="dr-secondary-id"},
    @{Name="Security"; ID="security-subscription-id"},
    @{Name="Management"; ID="mgmt-subscription-id"},
    @{Name="Networking"; ID="network-subscription-id"},
    @{Name="SharedServices"; ID="shared-services-id"},
    @{Name="Sandbox"; ID="sandbox-subscription-id"},
    @{Name="Archive"; ID="archive-subscription-id"},
    @{Name="Monitoring"; ID="monitoring-subscription-id"}
)

# Install required modules if needed
$requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.Storage', 'Az.Network', 'Az.CostManagement')
foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
}

# Connect to Azure (using managed identity or existing session)
try {
    $context = Get-AzContext
    if (!$context) {
        Write-Host "Connecting to Azure..." -ForegroundColor Yellow
        Connect-AzAccount -Identity -ErrorAction Stop
    }
} catch {
    Write-Host "Not running in Azure, attempting interactive login..." -ForegroundColor Yellow
    Connect-AzAccount
}

# Function to get cost data
function Get-SubscriptionCosts {
    param($SubscriptionId, $SubscriptionName)
    
    Write-Host "Analyzing $SubscriptionName..." -ForegroundColor Cyan
    
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue | Out-Null
    
    $costData = @{
        SubscriptionName = $SubscriptionName
        SubscriptionId = $SubscriptionId
        TotalMonthlyCost = 0
        VMs = @()
        Storage = @()
        Networking = @()
        Databases = @()
        Other = @()
        IdleResources = @{
            StoppedVMs = @()
            UnattachedDisks = @()
            UnusedPublicIPs = @()
            UnattachedNICs = @()
            EmptyResourceGroups = @()
        }
        PotentialSavings = 0
    }
    
    try {
        # Get actual cost data from Cost Management API
        $endDate = Get-Date
        $startDate = $endDate.AddDays(-30)
        
        $costParams = @{
            Scope = "/subscriptions/$SubscriptionId"
            TimeFrame = 'Custom'
            TimePeriodFrom = $startDate.ToString("yyyy-MM-dd")
            TimePeriodTo = $endDate.ToString("yyyy-MM-dd")
            DatasetGranularity = 'Monthly'
            DatasetAggregation = @{
                totalCost = @{
                    name = 'PreTaxCost'
                    function = 'Sum'
                }
            }
            DatasetGrouping = @(
                @{
                    type = 'Dimension'
                    name = 'ResourceType'
                }
            )
        }
        
        $costs = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2021-10-01" -Method POST -Payload ($costParams | ConvertTo-Json -Depth 10)
        
        if ($costs.StatusCode -eq 200) {
            $costResult = $costs.Content | ConvertFrom-Json
            $costData.TotalMonthlyCost = ($costResult.properties.rows | Measure-Object -Sum -Property {$_[0]}).Sum
        }
    } catch {
        Write-Host "  Warning: Could not retrieve cost data from Cost Management API" -ForegroundColor Yellow
    }
    
    # Get Virtual Machines
    $vms = Get-AzVM -Status
    foreach ($vm in $vms) {
        $vmCost = 0
        $vmSize = $vm.HardwareProfile.VmSize
        
        # Estimate cost based on VM size (approximate monthly costs)
        $vmCost = switch -Wildcard ($vmSize) {
            "*A1*" { 30 }
            "*A2*" { 60 }
            "*D2*" { 100 }
            "*D4*" { 140 }
            "*D8*" { 280 }
            "*D16*" { 560 }
            "*E2*" { 110 }
            "*E4*" { 150 }
            "*E8*" { 300 }
            "*F2*" { 90 }
            "*F4*" { 120 }
            default { 50 }
        }
        
        $vmInfo = @{
            Name = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Size = $vmSize
            Location = $vm.Location
            Status = $vm.PowerState
            MonthlyCost = $vmCost
        }
        
        if ($vm.PowerState -eq "VM deallocated" -or $vm.PowerState -eq "VM stopped") {
            $costData.IdleResources.StoppedVMs += $vmInfo
            $costData.PotentialSavings += $vmCost * 0.8
        } else {
            $costData.VMs += $vmInfo
        }
    }
    
    # Get Unattached Disks
    $disks = Get-AzDisk
    foreach ($disk in $disks) {
        if (!$disk.ManagedBy) {
            $diskCost = [math]::Round($disk.DiskSizeGB * 0.10, 2)
            $costData.IdleResources.UnattachedDisks += @{
                Name = $disk.Name
                ResourceGroup = $disk.ResourceGroupName
                Size = $disk.DiskSizeGB
                MonthlyCost = $diskCost
            }
            $costData.PotentialSavings += $diskCost
        }
    }
    
    # Get Unused Public IPs
    $publicIPs = Get-AzPublicIpAddress
    foreach ($pip in $publicIPs) {
        if (!$pip.IpConfiguration) {
            $pipCost = 3
            $costData.IdleResources.UnusedPublicIPs += @{
                Name = $pip.Name
                ResourceGroup = $pip.ResourceGroupName
                IPAddress = $pip.IpAddress
                MonthlyCost = $pipCost
            }
            $costData.PotentialSavings += $pipCost
        } else {
            $costData.Networking += @{
                Name = $pip.Name
                Type = "Public IP"
                MonthlyCost = 3
            }
        }
    }
    
    # Get Unattached NICs
    $nics = Get-AzNetworkInterface
    foreach ($nic in $nics) {
        if (!$nic.VirtualMachine) {
            $nicCost = 1
            $costData.IdleResources.UnattachedNICs += @{
                Name = $nic.Name
                ResourceGroup = $nic.ResourceGroupName
                MonthlyCost = $nicCost
            }
            $costData.PotentialSavings += $nicCost
        }
    }
    
    # Get Storage Accounts
    $storageAccounts = Get-AzStorageAccount
    foreach ($storage in $storageAccounts) {
        $storageCost = 10  # Base estimate
        $costData.Storage += @{
            Name = $storage.StorageAccountName
            ResourceGroup = $storage.ResourceGroupName
            Type = $storage.Sku.Name
            MonthlyCost = $storageCost
        }
    }
    
    # Get Empty Resource Groups
    $resourceGroups = Get-AzResourceGroup
    foreach ($rg in $resourceGroups) {
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
        if ($resources.Count -eq 0) {
            $costData.IdleResources.EmptyResourceGroups += @{
                Name = $rg.ResourceGroupName
                Location = $rg.Location
            }
        }
    }
    
    return $costData
}

# Function to generate HTML report
function New-HTMLReport {
    param($CostData, $OutputFile)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Cost Analysis - $($CostData.SubscriptionName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; border-left: 4px solid #0078d4; padding-left: 10px; }
        .summary { background-color: #e8f4fd; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .summary-item { display: inline-block; margin: 10px 30px 10px 0; }
        .summary-label { font-weight: bold; color: #666; display: block; font-size: 12px; }
        .summary-value { font-size: 24px; color: #0078d4; font-weight: bold; }
        .savings { background-color: #d4edda; padding: 20px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #28a745; }
        .savings-value { font-size: 28px; color: #28a745; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .cost { color: #d83b01; font-weight: bold; }
        .status-running { color: #28a745; font-weight: bold; }
        .status-stopped { color: #dc3545; font-weight: bold; }
        .idle-warning { background-color: #fff3cd; padding: 10px; border-left: 4px solid #ffc107; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure Cost Analysis Report</h1>
        <p><strong>Subscription:</strong> $($CostData.SubscriptionName) ($($CostData.SubscriptionId))</p>
        <p><strong>Report Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        
        <div class="summary">
            <div class="summary-item">
                <span class="summary-label">TOTAL MONTHLY COST</span>
                <span class="summary-value">`$$([math]::Round($CostData.TotalMonthlyCost, 2))</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">VIRTUAL MACHINES</span>
                <span class="summary-value">$($CostData.VMs.Count)</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">STORAGE ACCOUNTS</span>
                <span class="summary-value">$($CostData.Storage.Count)</span>
            </div>
        </div>
        
        <div class="savings">
            <h3 style="margin-top: 0; color: #28a745;">💰 Potential Monthly Savings</h3>
            <span class="savings-value">`$$([math]::Round($CostData.PotentialSavings, 2))</span>
            <p style="margin-bottom: 0;">By removing idle and unused resources</p>
        </div>
        
        <h2>🖥️ Virtual Machines ($($CostData.VMs.Count) Active)</h2>
"@
    
    if ($CostData.VMs.Count -gt 0) {
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Size</th><th>Location</th><th>Status</th><th>Monthly Cost</th></tr>"
        foreach ($vm in $CostData.VMs) {
            $html += "<tr><td>$($vm.Name)</td><td>$($vm.ResourceGroup)</td><td>$($vm.Size)</td><td>$($vm.Location)</td><td class='status-running'>$($vm.Status)</td><td class='cost'>`$$($vm.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    } else {
        $html += "<p>No active virtual machines found.</p>"
    }
    
    $html += "<h2>💾 Storage Accounts ($($CostData.Storage.Count))</h2>"
    if ($CostData.Storage.Count -gt 0) {
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Type</th><th>Monthly Cost</th></tr>"
        foreach ($storage in $CostData.Storage) {
            $html += "<tr><td>$($storage.Name)</td><td>$($storage.ResourceGroup)</td><td>$($storage.Type)</td><td class='cost'>`$$($storage.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    } else {
        $html += "<p>No storage accounts found.</p>"
    }
    
    $html += "<h2>🌐 Networking Resources ($($CostData.Networking.Count))</h2>"
    if ($CostData.Networking.Count -gt 0) {
        $html += "<table><tr><th>Name</th><th>Type</th><th>Monthly Cost</th></tr>"
        foreach ($net in $CostData.Networking) {
            $html += "<tr><td>$($net.Name)</td><td>$($net.Type)</td><td class='cost'>`$$($net.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    } else {
        $html += "<p>No active networking resources found.</p>"
    }
    
    $html += "<h2>⚠️ Idle Resources (Potential Savings)</h2>"
    
    # Stopped VMs
    if ($CostData.IdleResources.StoppedVMs.Count -gt 0) {
        $html += "<h3>Stopped/Deallocated VMs ($($CostData.IdleResources.StoppedVMs.Count))</h3>"
        $html += "<div class='idle-warning'>These VMs are stopped but still incurring costs for storage.</div>"
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Size</th><th>Status</th><th>Potential Savings</th></tr>"
        foreach ($vm in $CostData.IdleResources.StoppedVMs) {
            $html += "<tr><td>$($vm.Name)</td><td>$($vm.ResourceGroup)</td><td>$($vm.Size)</td><td class='status-stopped'>$($vm.Status)</td><td class='cost'>`$$([math]::Round($vm.MonthlyCost * 0.8, 2))/mo</td></tr>"
        }
        $html += "</table>"
    }
    
    # Unattached Disks
    if ($CostData.IdleResources.UnattachedDisks.Count -gt 0) {
        $html += "<h3>Unattached Disks ($($CostData.IdleResources.UnattachedDisks.Count))</h3>"
        $html += "<div class='idle-warning'>These disks are not attached to any VM.</div>"
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Size (GB)</th><th>Monthly Cost</th></tr>"
        foreach ($disk in $CostData.IdleResources.UnattachedDisks) {
            $html += "<tr><td>$($disk.Name)</td><td>$($disk.ResourceGroup)</td><td>$($disk.Size)</td><td class='cost'>`$$($disk.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    }
    
    # Unused Public IPs
    if ($CostData.IdleResources.UnusedPublicIPs.Count -gt 0) {
        $html += "<h3>Unused Public IPs ($($CostData.IdleResources.UnusedPublicIPs.Count))</h3>"
        $html += "<div class='idle-warning'>These public IPs are not associated with any resource.</div>"
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>IP Address</th><th>Monthly Cost</th></tr>"
        foreach ($pip in $CostData.IdleResources.UnusedPublicIPs) {
            $html += "<tr><td>$($pip.Name)</td><td>$($pip.ResourceGroup)</td><td>$($pip.IPAddress)</td><td class='cost'>`$$($pip.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    }
    
    # Unattached NICs
    if ($CostData.IdleResources.UnattachedNICs.Count -gt 0) {
        $html += "<h3>Unattached Network Interfaces ($($CostData.IdleResources.UnattachedNICs.Count))</h3>"
        $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Monthly Cost</th></tr>"
        foreach ($nic in $CostData.IdleResources.UnattachedNICs) {
            $html += "<tr><td>$($nic.Name)</td><td>$($nic.ResourceGroup)</td><td class='cost'>`$$($nic.MonthlyCost)</td></tr>"
        }
        $html += "</table>"
    }
    
    # Empty Resource Groups
    if ($CostData.IdleResources.EmptyResourceGroups.Count -gt 0) {
        $html += "<h3>Empty Resource Groups ($($CostData.IdleResources.EmptyResourceGroups.Count))</h3>"
        $html += "<div class='idle-warning'>These resource groups contain no resources and can be deleted.</div>"
        $html += "<table><tr><th>Name</th><th>Location</th></tr>"
        foreach ($rg in $CostData.IdleResources.EmptyResourceGroups) {
            $html += "<tr><td>$($rg.Name)</td><td>$($rg.Location)</td></tr>"
        }
        $html += "</table>"
    }
    
    $html += @"
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $OutputFile -Encoding UTF8
}

# Function to generate CSV report
function New-CSVReport {
    param($CostData, $OutputFile)
    
    $csvData = @()
    
    # Add VMs
    foreach ($vm in $CostData.VMs) {
        $csvData += [PSCustomObject]@{
            Subscription = $CostData.SubscriptionName
            Category = "Virtual Machine"
            Name = $vm.Name
            ResourceGroup = $vm.ResourceGroup
            Size = $vm.Size
            Location = $vm.Location
            Status = $vm.Status
            MonthlyCost = $vm.MonthlyCost
            IsIdle = "No"
        }
    }
    
    # Add Storage
    foreach ($storage in $CostData.Storage) {
        $csvData += [PSCustomObject]@{
            Subscription = $CostData.SubscriptionName
            Category = "Storage Account"
            Name = $storage.Name
            ResourceGroup = $storage.ResourceGroup
            Size = $storage.Type
            Location = ""
            Status = "Active"
            MonthlyCost = $storage.MonthlyCost
            IsIdle = "No"
        }
    }
    
    # Add Stopped VMs
    foreach ($vm in $CostData.IdleResources.StoppedVMs) {
        $csvData += [PSCustomObject]@{
            Subscription = $CostData.SubscriptionName
            Category = "Virtual Machine (Stopped)"
            Name = $vm.Name
            ResourceGroup = $vm.ResourceGroup
            Size = $vm.Size
            Location = ""
            Status = $vm.Status
            MonthlyCost = [math]::Round($vm.MonthlyCost * 0.8, 2)
            IsIdle = "Yes"
        }
    }
    
    # Add Unattached Disks
    foreach ($disk in $CostData.IdleResources.UnattachedDisks) {
        $csvData += [PSCustomObject]@{
            Subscription = $CostData.SubscriptionName
            Category = "Unattached Disk"
            Name = $disk.Name
            ResourceGroup = $disk.ResourceGroup
            Size = "$($disk.Size) GB"
            Location = ""
            Status = "Unattached"
            MonthlyCost = $disk.MonthlyCost
            IsIdle = "Yes"
        }
    }
    
    # Add Unused Public IPs
    foreach ($pip in $CostData.IdleResources.UnusedPublicIPs) {
        $csvData += [PSCustomObject]@{
            Subscription = $CostData.SubscriptionName
            Category = "Unused Public IP"
            Name = $pip.Name
            ResourceGroup = $pip.ResourceGroup
            Size = $pip.IPAddress
            Location = ""
            Status = "Unassociated"
            MonthlyCost = $pip.MonthlyCost
            IsIdle = "Yes"
        }
    }
    
    $csvData | Export-Csv -Path $OutputFile -NoTypeInformation
}

# Main execution
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryReport = @()

Write-Host ""
Write-Host "Processing all 13 subscriptions..." -ForegroundColor Green
Write-Host ""

foreach ($sub in $subscriptions) {
    try {
        $costData = Get-SubscriptionCosts -SubscriptionId $sub.ID -SubscriptionName $sub.Name
        
        # Generate reports for this subscription
        $htmlFile = Join-Path $OutputPath "$($sub.Name)-Cost-Analysis-$timestamp.html"
        $csvFile = Join-Path $OutputPath "$($sub.Name)-Cost-Analysis-$timestamp.csv"
        
        New-HTMLReport -CostData $costData -OutputFile $htmlFile
        New-CSVReport -CostData $costData -OutputFile $csvFile
        
        Write-Host "✓ $($sub.Name): $htmlFile" -ForegroundColor Green
        Write-Host "✓ $($sub.Name): $csvFile" -ForegroundColor Green
        
        $summaryReport += [PSCustomObject]@{
            Subscription = $sub.Name
            TotalCost = [math]::Round($costData.TotalMonthlyCost, 2)
            PotentialSavings = [math]::Round($costData.PotentialSavings, 2)
            ActiveVMs = $costData.VMs.Count
            IdleVMs = $costData.IdleResources.StoppedVMs.Count
            UnattachedDisks = $costData.IdleResources.UnattachedDisks.Count
            HTMLReport = $htmlFile
            CSVReport = $csvFile
        }
        
    } catch {
        Write-Host "✗ Error processing $($sub.Name): $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Create summary report
$summaryFile = Join-Path $OutputPath "All-Subscriptions-Summary-$timestamp.html"
$summaryCsvFile = Join-Path $OutputPath "All-Subscriptions-Summary-$timestamp.csv"

$summaryReport | Export-Csv -Path $summaryCsvFile -NoTypeInformation

$totalCost = ($summaryReport | Measure-Object -Property TotalCost -Sum).Sum
$totalSavings = ($summaryReport | Measure-Object -Property PotentialSavings -Sum).Sum

$summaryHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Cost Analysis - All Subscriptions Summary</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        .summary { background-color: #e8f4fd; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .summary-item { display: inline-block; margin: 10px 30px 10px 0; }
        .summary-label { font-weight: bold; color: #666; display: block; font-size: 12px; }
        .summary-value { font-size: 32px; color: #0078d4; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .cost { color: #d83b01; font-weight: bold; }
        a { color: #0078d4; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure Cost Analysis - All Subscriptions Summary</h1>
        <p><strong>Report Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p><strong>Total Subscriptions:</strong> $($subscriptions.Count)</p>
        
        <div class="summary">
            <div class="summary-item">
                <span class="summary-label">TOTAL MONTHLY COST (ALL SUBSCRIPTIONS)</span>
                <span class="summary-value">`$$([math]::Round($totalCost, 2))</span>
            </div>
            <div class="summary-item">
                <span class="summary-label">POTENTIAL MONTHLY SAVINGS</span>
                <span class="summary-value" style="color: #28a745;">`$$([math]::Round($totalSavings, 2))</span>
            </div>
        </div>
        
        <h2>Subscription Breakdown</h2>
        <table>
            <tr>
                <th>Subscription</th>
                <th>Monthly Cost</th>
                <th>Potential Savings</th>
                <th>Active VMs</th>
                <th>Idle VMs</th>
                <th>Unattached Disks</th>
                <th>Reports</th>
            </tr>
"@

foreach ($sub in $summaryReport) {
    $summaryHtml += @"
            <tr>
                <td><strong>$($sub.Subscription)</strong></td>
                <td class="cost">`$$($sub.TotalCost)</td>
                <td class="cost">`$$($sub.PotentialSavings)</td>
                <td>$($sub.ActiveVMs)</td>
                <td>$($sub.IdleVMs)</td>
                <td>$($sub.UnattachedDisks)</td>
                <td>
                    <a href="$($sub.HTMLReport)">HTML</a> | 
                    <a href="$($sub.CSVReport)">CSV</a>
                </td>
            </tr>
"@
}

$summaryHtml += @"
        </table>
    </div>
</body>
</html>
"@

$summaryHtml | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ All reports generated successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary Report: $summaryFile" -ForegroundColor Yellow
Write-Host ""
Write-Host "Total Monthly Cost: `$$([math]::Round($totalCost, 2))" -ForegroundColor Cyan
Write-Host "Potential Savings: `$$([math]::Round($totalSavings, 2))" -ForegroundColor Green
Write-Host ""

if ($OpenReports) {
    Start-Process $summaryFile
}

Write-Host "Done!" -ForegroundColor Green
