#Requires -Version 5.1
# BRAND NEW CLEAN SCRIPT - Built from scratch with bulletproof error handling

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$PrioritySubscriptionId = "7EDFB9F6-940E-47CD-AF4B-04D0B6E6020F",
    
    [Parameter(Mandatory=$false)]
    [int]$DaysIdle = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Reports"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE IDLE RESOURCES SCANNER - CLEAN VERSION" -ForegroundColor Cyan
Write-Host "  Multi-Tenant | Cost Analysis | Professional Reports" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Azure Authentication
Write-Host "Step 1: Azure Authentication" -ForegroundColor Yellow
Write-Host ""

$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Host "Successfully authenticated as: $($context.Account.Id)" -ForegroundColor Green
Write-Host ""

# Step 2: Discover Subscriptions
Write-Host "Step 2: Discovering Subscriptions and Tenants" -ForegroundColor Yellow
Write-Host ""

$allSubscriptions = @(Get-AzSubscription)

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allSubscriptions.Count) subscription(s)" -ForegroundColor Green
Write-Host ""

$tenantGroups = $allSubscriptions | Group-Object -Property TenantId
Write-Host "Available Tenants: $($tenantGroups.Count)" -ForegroundColor Cyan
foreach ($tenantGroup in $tenantGroups) {
    Write-Host ""
    Write-Host "Tenant: $($tenantGroup.Name)" -ForegroundColor Yellow
    foreach ($sub in $tenantGroup.Group) {
        Write-Host "  - $($sub.Name) [$($sub.State)]" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "Subscription Scanning Options:" -ForegroundColor Yellow
Write-Host "  [1] Scan ALL subscriptions (Recommended)" -ForegroundColor White
Write-Host "  [2] Select specific subscriptions" -ForegroundColor White
Write-Host ""
$choice = Read-Host "Enter your choice (1 or 2)"

if ($choice -eq "2") {
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $allSubscriptions.Count; $i++) {
        $sub = $allSubscriptions[$i]
        Write-Host "  [$($i+1)] $($sub.Name) (Tenant: $($sub.TenantId))" -ForegroundColor White
    }
    Write-Host ""
    $selections = Read-Host "Enter subscription numbers separated by commas (e.g., 1,3,5)"
    
    $selectedIndices = $selections -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
    $subscriptionsToScan = @()
    foreach ($idx in $selectedIndices) {
        if ($idx -ge 0 -and $idx -lt $allSubscriptions.Count) {
            $subscriptionsToScan += $allSubscriptions[$idx]
        }
    }
} else {
    $subscriptionsToScan = $allSubscriptions
}

Write-Host ""
Write-Host "Will scan $($subscriptionsToScan.Count) subscription(s)" -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2

# Create output directory
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$allIdleResources = @()
$summary = @{
    ScanStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TotalSubscriptionsScanned = 0
    TotalResourcesScanned = 0
    TotalIdleResources = 0
    TotalMonthlyCost = 0
    TotalAnnualCost = 0
    SubscriptionDetails = @()
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCANNING RESOURCES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$currentSubNum = 0
foreach ($subscription in $subscriptionsToScan) {
    $currentSubNum++
    
    try {
        Write-Host ""
        Write-Host "[$currentSubNum/$($subscriptionsToScan.Count)] Scanning: $($subscription.Name)" -ForegroundColor Cyan
        Write-Host "Subscription ID: $($subscription.Id)" -ForegroundColor Gray
        Write-Host ""
        
        Set-AzContext -SubscriptionId $subscription.Id -TenantId $subscription.TenantId -ErrorAction Stop | Out-Null
        
        $subIdleResources = @()
        $subTotalCost = 0
        $subResourceCount = 0
        
        # ========== VIRTUAL MACHINES ==========
        Write-Host "Checking Virtual Machines..." -ForegroundColor Yellow
        $vmIdleCount = 0
        try {
            $vms = @(Get-AzVM -Status -ErrorAction Stop)
            $subResourceCount += $vms.Count
            
            foreach ($vm in $vms) {
                if ($vm.PowerState -eq "VM deallocated" -or $vm.PowerState -eq "VM stopped") {
                    $vmIdleCount++
                    $vmSize = $vm.HardwareProfile.VmSize
                    $estimatedCost = switch -Wildcard ($vmSize) {
                        "Standard_D4*" { 150 }
                        "Standard_D2*" { 75 }
                        "Standard_B4*" { 130 }
                        "Standard_B2*" { 50 }
                        "Standard_E*" { 200 }
                        "Standard_F*" { 100 }
                        default { 50 }
                    }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Virtual Machine"
                        ResourceName = $vm.Name
                        ResourceGroup = $vm.ResourceGroupName
                        Location = $vm.Location
                        Status = $vm.PowerState
                        Size = $vmSize
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "VM is stopped or deallocated"
                        Recommendation = "Delete VM if no longer needed or restart if required"
                        Tags = ($vm.Tags.Keys | ForEach-Object { "$_=$($vm.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($vms.Count) VMs | Idle: $vmIdleCount" -ForegroundColor $(if($vmIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== UNATTACHED DISKS ==========
        Write-Host "Checking Unattached Disks..." -ForegroundColor Yellow
        $diskIdleCount = 0
        try {
            $disks = @(Get-AzDisk -ErrorAction Stop)
            $subResourceCount += $disks.Count
            
            foreach ($disk in $disks) {
                if ($null -eq $disk.ManagedBy -or $disk.ManagedBy -eq "") {
                    $diskIdleCount++
                    $diskSizeGB = $disk.DiskSizeGB
                    $diskTier = $disk.Sku.Name
                    $estimatedCost = switch ($diskTier) {
                        "Premium_LRS" { [math]::Round(($diskSizeGB * 0.15), 2) }
                        "StandardSSD_LRS" { [math]::Round(($diskSizeGB * 0.08), 2) }
                        default { [math]::Round(($diskSizeGB * 0.05), 2) }
                    }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Unattached Disk"
                        ResourceName = $disk.Name
                        ResourceGroup = $disk.ResourceGroupName
                        Location = $disk.Location
                        Status = "Unattached"
                        Size = "$diskSizeGB GB - $diskTier"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Disk not attached to any VM"
                        Recommendation = "Delete if no longer needed"
                        Tags = ($disk.Tags.Keys | ForEach-Object { "$_=$($disk.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($disks.Count) Disks | Unattached: $diskIdleCount" -ForegroundColor $(if($diskIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== PUBLIC IP ADDRESSES ==========
        Write-Host "Checking Public IP Addresses..." -ForegroundColor Yellow
        $publicIPs = @()
        $ipCount = 0
        $ipIdleCount = 0
        try {
            $publicIPs = @(Get-AzPublicIpAddress -ErrorAction Stop)
            $ipCount = $publicIPs.Count
            $subResourceCount += $ipCount
            
            foreach ($ip in $publicIPs) {
                if ($null -eq $ip.IpConfiguration -or $ip.IpConfiguration -eq "") {
                    $ipIdleCount++
                    $ipSku = if ($ip.Sku.Name) { $ip.Sku.Name } else { "Basic" }
                    $estimatedCost = if ($ipSku -eq "Standard") { 4 } else { 3 }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Public IP Address"
                        ResourceName = $ip.Name
                        ResourceGroup = $ip.ResourceGroupName
                        Location = $ip.Location
                        Status = "Unassigned"
                        Size = "$ipSku SKU"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Public IP not assigned to any resource"
                        Recommendation = "Delete if not needed - incurs monthly charge"
                        Tags = ($ip.Tags.Keys | ForEach-Object { "$_=$($ip.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $ipCount Public IPs | Unassigned: $ipIdleCount" -ForegroundColor $(if($ipIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== NETWORK INTERFACES ==========
        Write-Host "Checking Network Interfaces..." -ForegroundColor Yellow
        $nics = @()
        $nicCount = 0
        $nicIdleCount = 0
        try {
            $nics = @(Get-AzNetworkInterface -ErrorAction Stop)
            $nicCount = $nics.Count
            $subResourceCount += $nicCount
            
            foreach ($nic in $nics) {
                if ($null -eq $nic.VirtualMachine -or $nic.VirtualMachine -eq "") {
                    $nicIdleCount++
                    $estimatedCost = 2
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Network Interface"
                        ResourceName = $nic.Name
                        ResourceGroup = $nic.ResourceGroupName
                        Location = $nic.Location
                        Status = "Unattached"
                        Size = "N/A"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "NIC not attached to any VM"
                        Recommendation = "Delete if VM was removed"
                        Tags = ($nic.Tags.Keys | ForEach-Object { "$_=$($nic.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $nicCount NICs | Unattached: $nicIdleCount" -ForegroundColor $(if($nicIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== STORAGE ACCOUNTS ==========
        Write-Host "Checking Storage Accounts..." -ForegroundColor Yellow
        $storageIdleCount = 0
        try {
            $storageAccounts = @(Get-AzStorageAccount -ErrorAction Stop)
            $subResourceCount += $storageAccounts.Count
            
            foreach ($storage in $storageAccounts) {
                try {
                    $containers = @(Get-AzStorageContainer -Context $storage.Context -ErrorAction Stop -MaxClientTimeout 5)
                    if ($containers.Count -eq 0) {
                        $storageIdleCount++
                        $storageTier = $storage.Sku.Name
                        $estimatedCost = 5
                        $subTotalCost += $estimatedCost
                        
                        $subIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
                            TenantId = $subscription.TenantId
                            ResourceType = "Storage Account"
                            ResourceName = $storage.StorageAccountName
                            ResourceGroup = $storage.ResourceGroupName
                            Location = $storage.Location
                            Status = "Empty"
                            Size = "0 GB | $storageTier"
                            EstimatedMonthlyCost = $estimatedCost
                            EstimatedAnnualCost = $estimatedCost * 12
                            Reason = "Storage account is empty"
                            Recommendation = "Delete if not needed"
                            Tags = ($storage.Tags.Keys | ForEach-Object { "$_=$($storage.Tags[$_])" }) -join "; "
                        }
                    }
                } catch {
                    # Skip inaccessible storage
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($storageAccounts.Count) Storage Accounts | Empty: $storageIdleCount" -ForegroundColor $(if($storageIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== APP SERVICE PLANS ==========
        Write-Host "Checking App Service Plans..." -ForegroundColor Yellow
        $aspIdleCount = 0
        try {
            $appServicePlans = @(Get-AzAppServicePlan -ErrorAction Stop)
            $subResourceCount += $appServicePlans.Count
            
            foreach ($asp in $appServicePlans) {
                $apps = @(Get-AzWebApp -AppServicePlan $asp -ErrorAction SilentlyContinue)
                if ($apps.Count -eq 0) {
                    $aspIdleCount++
                    $aspTier = $asp.Sku.Tier
                    $estimatedCost = switch ($aspTier) {
                        "Premium" { 150 }
                        "PremiumV2" { 200 }
                        "PremiumV3" { 250 }
                        "Standard" { 75 }
                        default { 55 }
                    }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "App Service Plan"
                        ResourceName = $asp.Name
                        ResourceGroup = $asp.ResourceGroup
                        Location = $asp.Location
                        Status = "Empty"
                        Size = "$aspTier | $($asp.Sku.Name)"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "No apps deployed"
                        Recommendation = "Delete if not needed"
                        Tags = ($asp.Tags.Keys | ForEach-Object { "$_=$($asp.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($appServicePlans.Count) App Service Plans | Empty: $aspIdleCount" -ForegroundColor $(if($aspIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== LOAD BALANCERS ==========
        Write-Host "Checking Load Balancers..." -ForegroundColor Yellow
        $lbIdleCount = 0
        try {
            $loadBalancers = @(Get-AzLoadBalancer -ErrorAction Stop)
            $subResourceCount += $loadBalancers.Count
            
            foreach ($lb in $loadBalancers) {
                $hasBackend = $false
                if ($lb.BackendAddressPools.Count -gt 0) {
                    if ($lb.BackendAddressPools[0].BackendIpConfigurations.Count -gt 0) {
                        $hasBackend = $true
                    }
                }
                
                if (-not $hasBackend) {
                    $lbIdleCount++
                    $lbSku = $lb.Sku.Name
                    $estimatedCost = if ($lbSku -eq "Standard") { 25 } else { 18 }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Load Balancer"
                        ResourceName = $lb.Name
                        ResourceGroup = $lb.ResourceGroupName
                        Location = $lb.Location
                        Status = "No Backend"
                        Size = "$lbSku SKU"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "No backend resources"
                        Recommendation = "Delete if not needed"
                        Tags = ($lb.Tags.Keys | ForEach-Object { "$_=$($lb.Tags[$_])" }) -join "; "
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($loadBalancers.Count) Load Balancers | Idle: $lbIdleCount" -ForegroundColor $(if($lbIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # ========== SQL DATABASES ==========
        Write-Host "Checking SQL Databases..." -ForegroundColor Yellow
        $sqlServers = @()
        $sqlIdleCount = 0
        try {
            $sqlServers = @(Get-AzSqlServer -ErrorAction Stop)
            $subResourceCount += $sqlServers.Count
            
            foreach ($sqlServer in $sqlServers) {
                $databases = @(Get-AzSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne "master" })
                
                foreach ($db in $databases) {
                    if ($db.Status -eq "Paused" -or $db.CurrentServiceObjectiveName -like "*DW*") {
                        $sqlIdleCount++
                        $estimatedCost = 100
                        $subTotalCost += $estimatedCost
                        
                        $subIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
                            TenantId = $subscription.TenantId
                            ResourceType = "SQL Database"
                            ResourceName = "$($sqlServer.ServerName)/$($db.DatabaseName)"
                            ResourceGroup = $sqlServer.ResourceGroupName
                            Location = $sqlServer.Location
                            Status = $db.Status
                            Size = $db.CurrentServiceObjectiveName
                            EstimatedMonthlyCost = $estimatedCost
                            EstimatedAnnualCost = $estimatedCost * 12
                            Reason = "Database is paused or idle"
                            Recommendation = "Delete if no longer needed"
                            Tags = ($db.Tags.Keys | ForEach-Object { "$_=$($db.Tags[$_])" }) -join "; "
                        }
                    }
                }
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "  Found: $($sqlServers.Count) SQL Servers | Idle Databases: $sqlIdleCount" -ForegroundColor $(if($sqlIdleCount -gt 0){"Yellow"}else{"Green"})
        
        # Add to global collection
        $allIdleResources += $subIdleResources
        
        # ========== CREATE SUBSCRIPTION REPORTS ==========
        if ($subIdleResources.Count -gt 0) {
            $subName = $subscription.Name -replace '[^a-zA-Z0-9]', '_'
            
            # CSV Report
            $subCsvPath = Join-Path $OutputPath "IdleResources-$subName-$timestamp.csv"
            $csvData = $subIdleResources | Select-Object SubscriptionName, SubscriptionId, TenantId, ResourceType, ResourceName, ResourceGroup, Location, Status, Size,
                @{Name='MonthlyUSD'; Expression={'USD ' + $_.EstimatedMonthlyCost}},
                @{Name='AnnualUSD'; Expression={'USD ' + $_.EstimatedAnnualCost}},
                Reason, Recommendation, Tags
            
            $csvData | Export-Csv -Path $subCsvPath -NoTypeInformation -Force
            Write-Host "  CSV: $subCsvPath" -ForegroundColor Magenta
            
            # HTML Report
            $subHtmlPath = Join-Path $OutputPath "IdleResources-$subName-$timestamp.html"
            $subMonthlyCost = [math]::Round($subTotalCost, 2)
            $subAnnualCost = [math]::Round($subTotalCost * 12, 2)
            
            $subHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>$($subscription.Name) - Idle Resources</title>
    <style>
        body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}
        h1{color:#0078d4}
        .summary{background-color:#fff;padding:20px;margin:20px 0;border-radius:8px}
        .summary-item{margin:10px 0;padding:10px;border-bottom:1px solid #eee}
        .summary-label{font-weight:bold;color:#333;display:inline-block;width:250px}
        .summary-value{color:#0078d4}
        .cost{font-size:1.2em;font-weight:bold;color:#107c10}
        table{width:100%;border-collapse:collapse;background-color:#fff;margin:20px 0}
        th{background-color:#0078d4;color:#fff;padding:12px;text-align:left}
        td{padding:10px;border-bottom:1px solid #ddd}
        tr:hover{background-color:#f0f0f0}
    </style>
</head>
<body>
    <h1>$($subscription.Name) - Idle Resources Report</h1>
    <div class='summary'>
        <h2>Subscription Summary</h2>
        <div class='summary-item'><span class='summary-label'>Subscription:</span> <span class='summary-value'>$($subscription.Name)</span></div>
        <div class='summary-item'><span class='summary-label'>Subscription ID:</span> <span class='summary-value'>$($subscription.Id)</span></div>
        <div class='summary-item'><span class='summary-label'>Total Idle Resources:</span> <span class='cost'>$($subIdleResources.Count)</span></div>
        <div class='summary-item'><span class='summary-label'>Monthly Savings:</span> <span class='cost'>USD $subMonthlyCost</span></div>
        <div class='summary-item'><span class='summary-label'>Annual Savings:</span> <span class='cost'>USD $subAnnualCost</span></div>
    </div>
    <h2>Idle Resources</h2>
    <table>
        <tr>
            <th>Type</th>
            <th>Name</th>
            <th>Resource Group</th>
            <th>Location</th>
            <th>Status</th>
            <th>Size</th>
            <th>Monthly Cost</th>
            <th>Annual Cost</th>
            <th>Reason</th>
            <th>Recommendation</th>
        </tr>
"@
            foreach ($resource in ($subIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
                $monthlyCost = [math]::Round($resource.EstimatedMonthlyCost, 2)
                $annualCost = [math]::Round($resource.EstimatedAnnualCost, 2)
                
                $subHtml += @"
        <tr>
            <td>$($resource.ResourceType)</td>
            <td>$($resource.ResourceName)</td>
            <td>$($resource.ResourceGroup)</td>
            <td>$($resource.Location)</td>
            <td>$($resource.Status)</td>
            <td>$($resource.Size)</td>
            <td>USD $monthlyCost</td>
            <td>USD $annualCost</td>
            <td>$($resource.Reason)</td>
            <td>$($resource.Recommendation)</td>
        </tr>
"@
            }
            
            $subHtml += @"
    </table>
</body>
</html>
"@
            
            [System.IO.File]::WriteAllText($subHtmlPath, $subHtml)
            Write-Host "  HTML: $subHtmlPath" -ForegroundColor Magenta
            Start-Process $subHtmlPath
        }
        
        # Update summary
        $summary.TotalSubscriptionsScanned++
        $summary.TotalResourcesScanned += $subResourceCount
        $summary.TotalIdleResources += $subIdleResources.Count
        $summary.TotalMonthlyCost += $subTotalCost
        $summary.TotalAnnualCost += ($subTotalCost * 12)
        
        $summary.SubscriptionDetails += [PSCustomObject]@{
            SubscriptionName = $subscription.Name
            SubscriptionId = $subscription.Id
            TenantId = $subscription.TenantId
            ResourcesScanned = $subResourceCount
            IdleResourcesFound = $subIdleResources.Count
            EstimatedMonthlyCost = [math]::Round($subTotalCost, 2)
            EstimatedAnnualCost = [math]::Round($subTotalCost * 12, 2)
        }
        
        Write-Host ""
        Write-Host "  Summary: $($subIdleResources.Count) idle resources | USD $([math]::Round($subTotalCost, 2))/month" -ForegroundColor $(if($subIdleResources.Count -gt 0){"Yellow"}else{"Green"})
        
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Continuing..." -ForegroundColor Yellow
    }
}

$summary.ScanEndTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ========== FINAL SUMMARY ==========
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Idle Resources: $($summary.TotalIdleResources)" -ForegroundColor Yellow
Write-Host "Monthly Savings: USD $([math]::Round($summary.TotalMonthlyCost, 2))" -ForegroundColor Yellow
Write-Host "Annual Savings: USD $([math]::Round($summary.TotalAnnualCost, 2))" -ForegroundColor Yellow
Write-Host ""

# ========== COMBINED REPORTS ==========
if ($allIdleResources.Count -gt 0) {
    # Combined CSV
    $combinedCsvPath = Join-Path $OutputPath "IdleResources-AllSubscriptions-$timestamp.csv"
    $csvData = $allIdleResources | Select-Object SubscriptionName, SubscriptionId, TenantId, ResourceType, ResourceName, ResourceGroup, Location, Status, Size,
        @{Name='MonthlyUSD'; Expression={'USD ' + $_.EstimatedMonthlyCost}},
        @{Name='AnnualUSD'; Expression={'USD ' + $_.EstimatedAnnualCost}},
        Reason, Recommendation, Tags
    
    $csvData | Export-Csv -Path $combinedCsvPath -NoTypeInformation -Force
    Write-Host "Combined CSV: $combinedCsvPath" -ForegroundColor Green
    
    # Combined HTML
    $combinedHtmlPath = Join-Path $OutputPath "IdleResources-AllSubscriptions-$timestamp.html"
    $monthlySavings = [math]::Round($summary.TotalMonthlyCost, 2)
    $annualSavings = [math]::Round($summary.TotalAnnualCost, 2)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>All Subscriptions - Idle Resources</title>
    <style>
        body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}
        h1{color:#0078d4}
        .summary{background-color:#fff;padding:20px;margin:20px 0;border-radius:8px}
        .summary-item{margin:10px 0;padding:10px;border-bottom:1px solid #eee}
        .summary-label{font-weight:bold;color:#333;display:inline-block;width:250px}
        .summary-value{color:#0078d4}
        .cost{font-size:1.2em;font-weight:bold;color:#107c10}
        table{width:100%;border-collapse:collapse;background-color:#fff;margin:20px 0}
        th{background-color:#0078d4;color:#fff;padding:12px;text-align:left}
        td{padding:10px;border-bottom:1px solid #ddd}
        tr:hover{background-color:#f0f0f0}
    </style>
</head>
<body>
    <h1>All Subscriptions - Idle Resources Report</h1>
    <div class='summary'>
        <h2>Executive Summary</h2>
        <div class='summary-item'><span class='summary-label'>Total Idle Resources:</span> <span class='cost'>$($summary.TotalIdleResources)</span></div>
        <div class='summary-item'><span class='summary-label'>Monthly Savings:</span> <span class='cost'>USD $monthlySavings</span></div>
        <div class='summary-item'><span class='summary-label'>Annual Savings:</span> <span class='cost'>USD $annualSavings</span></div>
    </div>
    <h2>All Idle Resources</h2>
    <table>
        <tr>
            <th>Subscription</th>
            <th>Type</th>
            <th>Name</th>
            <th>Resource Group</th>
            <th>Location</th>
            <th>Monthly Cost</th>
            <th>Annual Cost</th>
            <th>Recommendation</th>
        </tr>
"@
    
    foreach ($resource in ($allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        $monthlyCost = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualCost = [math]::Round($resource.EstimatedAnnualCost, 2)
        
        $html += @"
        <tr>
            <td>$($resource.SubscriptionName)</td>
            <td>$($resource.ResourceType)</td>
            <td>$($resource.ResourceName)</td>
            <td>$($resource.ResourceGroup)</td>
            <td>$($resource.Location)</td>
            <td>USD $monthlyCost</td>
            <td>USD $annualCost</td>
            <td>$($resource.Recommendation)</td>
        </tr>
"@
    }
    
    $html += @"
    </table>
</body>
</html>
"@
    
    [System.IO.File]::WriteAllText($combinedHtmlPath, $html)
    Write-Host "Combined HTML: $combinedHtmlPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 15 Costliest Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 15 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, @{Name="Monthly";Expression={"USD $($_.EstimatedMonthlyCost)"}}, Recommendation -AutoSize
}

Write-Host ""
Write-Host "Scan complete!" -ForegroundColor Green
Write-Host ""