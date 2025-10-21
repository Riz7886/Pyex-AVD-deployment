#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$PrioritySubscriptionId = "7EDFB9F6-940E-47CD-AF4B-04D0B6E6020F",
    
    [Parameter(Mandatory=$false)]
    [int]$DaysIdle = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Reports"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE IDLE RESOURCES SCANNER - ENTERPRISE EDITION" -ForegroundColor Cyan
Write-Host "  Multi-Tenant | Cost Analysis | Professional Reports" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

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

Write-Host "Step 2: Discovering Subscriptions and Tenants" -ForegroundColor Yellow
Write-Host ""

$allSubscriptions = @(Get-AzSubscription)

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allSubscriptions.Count) subscription(s) across all accessible tenants" -ForegroundColor Green
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

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Created output directory: $OutputPath" -ForegroundColor Green
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
    ResourceTypeBreakdown = @{}
}

$totalSubCount = $subscriptionsToScan.Count
$currentSubNum = 0

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCANNING RESOURCES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

foreach ($subscription in $subscriptionsToScan) {
    $currentSubNum++
    
    try {
        Write-Host ""
        Write-Host "[$currentSubNum/$totalSubCount] Scanning Subscription: $($subscription.Name)" -ForegroundColor Cyan
        Write-Host "Subscription ID: $($subscription.Id)" -ForegroundColor Gray
        Write-Host "Tenant ID: $($subscription.TenantId)" -ForegroundColor Gray
        Write-Host ""
        
        Set-AzContext -SubscriptionId $subscription.Id -TenantId $subscription.TenantId | Out-Null
        
        $subIdleResources = @()
        $subTotalCost = 0
        $subResourceCount = 0
        
        Write-Host "Checking Virtual Machines..." -ForegroundColor Yellow
        try {
            $vms = Get-AzVM -Status
            $subResourceCount += $vms.Count
            $vmIdleCount = 0
            
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
                        Reason = "VM is stopped or deallocated - consuming storage costs"
                        Recommendation = "Delete VM if no longer needed or restart if required"
                        Tags = ($vm.Tags.Keys | ForEach-Object { "$_=$($vm.Tags[$_])" }) -join "; "
                    }
                }
            }
            Write-Host "  Found: $($vms.Count) VMs | Idle: $vmIdleCount" -ForegroundColor $(if($vmIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking VMs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Unattached Disks..." -ForegroundColor Yellow
        try {
            $disks = Get-AzDisk
            $subResourceCount += $disks.Count
            $diskIdleCount = 0
            
            foreach ($disk in $disks) {
                if ($disk.ManagedBy -eq $null) {
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
                        Reason = "Disk not attached to any VM - wasting storage costs"
                        Recommendation = "Delete if no longer needed or attach to VM"
                        Tags = ($disk.Tags.Keys | ForEach-Object { "$_=$($disk.Tags[$_])" }) -join "; "
                    }
                }
            }
            Write-Host "  Found: $($disks.Count) Disks | Unattached: $diskIdleCount" -ForegroundColor $(if($diskIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Disks: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Public IP Addresses..." -ForegroundColor Yellow
        try {
            $publicIPs = @()
            $ipCount = 0
            $ipIdleCount = 0
            $ipCount = 0
            $ipIdleCount = 0
            $publicIPs = @(Get-AzPublicIpAddress -ErrorAction SilentlyContinue)
            
            if ($publicIPs) {
                $ipCount = $publicIPs.Count
                $subResourceCount += $ipCount
                
                foreach ($ip in $publicIPs) {
                    if ($ip.IpConfiguration -eq $null) {
                        $ipIdleCount++
                        $ipSku = $ip.Sku.Name
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
            }
            Write-Host "  Found: $ipCount Public IPs | Unassigned: $ipIdleCount" -ForegroundColor $(if($ipIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Public IPs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Network Interfaces..." -ForegroundColor Yellow
        try {
            $nics = @()
            $nicCount = 0
            $nicIdleCount = 0
            $nicCount = 0
            $nicIdleCount = 0
            $nics = @(Get-AzNetworkInterface -ErrorAction SilentlyContinue)
            
            if ($nics) {
                $nicCount = $nics.Count
                $subResourceCount += $nicCount
                
                foreach ($nic in $nics) {
                    if ($nic.VirtualMachine -eq $null) {
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
            }
            Write-Host "  Found: $nicCount NICs | Unattached: $nicIdleCount" -ForegroundColor $(if($nicIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking NICs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Storage Accounts..." -ForegroundColor Yellow
        try {
            $storageAccounts = @(Get-AzStorageAccount -ErrorAction SilentlyContinue)
            $storageIdleCount = 0
            
            if ($storageAccounts) {
                $subResourceCount += $storageAccounts.Count
                
                foreach ($storage in $storageAccounts) {
                    $sizeGB = 0
                    $blobCount = 0
                    
                    try {
                        $containers = @(Get-AzStorageContainer -Context $storage.Context -ErrorAction Stop -MaxResults 1 -TimeoutInSeconds 5)
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
                                Size = "0 GB | 0 blobs | $storageTier"
                                EstimatedMonthlyCost = $estimatedCost
                                EstimatedAnnualCost = $estimatedCost * 12
                                Reason = "Storage account is empty"
                                Recommendation = "Delete if not needed - base charge applies"
                                Tags = ($storage.Tags.Keys | ForEach-Object { "$_=$($storage.Tags[$_])" }) -join "; "
                            }
                        }
                    } catch {
                        # Skip storage accounts we cannot access quickly
                    }
                }
            }
            Write-Host "  Found: $($storageAccounts.Count) Storage Accounts | Empty: $storageIdleCount" -ForegroundColor $(if($storageIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Storage: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking App Service Plans..." -ForegroundColor Yellow
        try {
            $appServicePlans = Get-AzAppServicePlan
            $subResourceCount += $appServicePlans.Count
            $aspIdleCount = 0
            
            foreach ($asp in $appServicePlans) {
                $apps = Get-AzWebApp -AppServicePlan $asp -ErrorAction SilentlyContinue
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
                        Reason = "App Service Plan has no apps deployed"
                        Recommendation = "Delete if not needed - significant monthly charge"
                        Tags = ($asp.Tags.Keys | ForEach-Object { "$_=$($asp.Tags[$_])" }) -join "; "
                    }
                }
            }
            Write-Host "  Found: $($appServicePlans.Count) App Service Plans | Empty: $aspIdleCount" -ForegroundColor $(if($aspIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking App Service Plans: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Load Balancers..." -ForegroundColor Yellow
        try {
            $loadBalancers = Get-AzLoadBalancer
            $subResourceCount += $loadBalancers.Count
            $lbIdleCount = 0
            
            foreach ($lb in $loadBalancers) {
                if ($lb.BackendAddressPools.Count -eq 0 -or $lb.BackendAddressPools[0].BackendIpConfigurations.Count -eq 0) {
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
                        Status = "No Backend Pool"
                        Size = "$lbSku SKU"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Load Balancer has no backend resources"
                        Recommendation = "Delete if infrastructure was removed"
                        Tags = ($lb.Tags.Keys | ForEach-Object { "$_=$($lb.Tags[$_])" }) -join "; "
                    }
                }
            }
            Write-Host "  Found: $($loadBalancers.Count) Load Balancers | Idle: $lbIdleCount" -ForegroundColor $(if($lbIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Load Balancers: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking SQL Databases..." -ForegroundColor Yellow
        try {
            $sqlServers = @()
            $sqlIdleCount = 0
            $sqlServers = @(Get-AzSqlServer -ErrorAction SilentlyContinue)
            $sqlIdleCount = 0
            
            if ($sqlServers) {
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
            }
            Write-Host "  Found: $($sqlServers.Count) SQL Servers | Idle Databases: $sqlIdleCount" -ForegroundColor $(if($sqlIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking SQL: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        $allIdleResources += $subIdleResources
        
        if ($subIdleResources.Count -gt 0) {
            $subName = $subscription.Name -replace '[^a-zA-Z0-9]', '_'
            $subCsvPath = Join-Path $OutputPath "IdleResources-$subName-$timestamp.csv"
            
            $csvData = $subIdleResources | Select-Object SubscriptionName, SubscriptionId, TenantId, ResourceType, ResourceName, ResourceGroup, Location, Status, Size, 
                @{Name='MonthlyUSD'; Expression={'USD ' + $_.EstimatedMonthlyCost}},
                @{Name='AnnualUSD'; Expression={'USD ' + $_.EstimatedAnnualCost}},
                Reason, Recommendation, Tags
            
            $csvData | Export-Csv -Path $subCsvPath -NoTypeInformation -Force
            Write-Host "  Subscription CSV: $subCsvPath" -ForegroundColor Magenta
            
            $subHtmlPath = Join-Path $OutputPath "IdleResources-$subName-$timestamp.html"
            $subMonthlyCost = [math]::Round($subTotalCost, 2)
            $subAnnualCost = [math]::Round($subTotalCost * 12, 2)
            
            $subHtml = "<!DOCTYPE html><html><head><title>$($subscription.Name) - Idle Resources</title>"
            $subHtml += "<style>body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}"
            $subHtml += "h1{color:#0078d4}.summary{background-color:#fff;padding:20px;margin:20px 0;border-radius:8px}"
            $subHtml += ".summary-item{margin:10px 0;padding:10px;border-bottom:1px solid #eee}"
            $subHtml += ".summary-label{font-weight:bold;color:#333;display:inline-block;width:250px}"
            $subHtml += ".summary-value{color:#0078d4}.cost{font-size:1.2em;font-weight:bold;color:#107c10}"
            $subHtml += "table{width:100%;border-collapse:collapse;background-color:#fff;margin:20px 0}"
            $subHtml += "th{background-color:#0078d4;color:#fff;padding:12px;text-align:left}"
            $subHtml += "td{padding:10px;border-bottom:1px solid #ddd}"
            $subHtml += "tr:hover{background-color:#f0f0f0}</style></head><body>"
            $subHtml += "<h1>$($subscription.Name) - Idle Resources Report</h1>"
            $subHtml += "<div class='summary'><h2>Subscription Summary</h2>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Subscription Name:</span> <span class='summary-value'>$($subscription.Name)</span></div>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Subscription ID:</span> <span class='summary-value'>$($subscription.Id)</span></div>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Tenant ID:</span> <span class='summary-value'>$($subscription.TenantId)</span></div>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Total Idle Resources:</span> <span class='cost'>$($subIdleResources.Count)</span></div>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Monthly Savings:</span> <span class='cost'>USD $subMonthlyCost</span></div>"
            $subHtml += "<div class='summary-item'><span class='summary-label'>Annual Savings:</span> <span class='cost'>USD $subAnnualCost</span></div></div>"
            $subHtml += "<h2>Idle Resources</h2>"
            $subHtml += "<table><tr><th>Resource Type</th><th>Resource Name</th><th>Resource Group</th><th>Location</th><th>Status</th><th>Size</th><th>Monthly Cost</th><th>Annual Cost</th><th>Reason</th><th>Recommendation</th></tr>"
            
            foreach ($resource in ($subIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
                $monthlyCost = [math]::Round($resource.EstimatedMonthlyCost, 2)
                $annualCost = [math]::Round($resource.EstimatedAnnualCost, 2)
                
                $subHtml += "<tr>"
                $subHtml += "<td>$($resource.ResourceType)</td>"
                $subHtml += "<td>$($resource.ResourceName)</td>"
                $subHtml += "<td>$($resource.ResourceGroup)</td>"
                $subHtml += "<td>$($resource.Location)</td>"
                $subHtml += "<td>$($resource.Status)</td>"
                $subHtml += "<td>$($resource.Size)</td>"
                $subHtml += "<td>USD $monthlyCost</td>"
                $subHtml += "<td>USD $annualCost</td>"
                $subHtml += "<td>$($resource.Reason)</td>"
                $subHtml += "<td>$($resource.Recommendation)</td>"
                $subHtml += "</tr>"
            }
            
            $subHtml += "</table></body></html>"
            [System.IO.File]::WriteAllText($subHtmlPath, $subHtml)
            Write-Host "  Subscription HTML: $subHtmlPath" -ForegroundColor Magenta
            
            Start-Process $subHtmlPath
        }
        
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
        Write-Host "  Subscription Summary: $($subIdleResources.Count) idle resources | Potential Savings: USD $([math]::Round($subTotalCost, 2))/month" -ForegroundColor $(if($subIdleResources.Count -gt 0){"Yellow"}else{"Green"})
        
    } catch {
        Write-Host "  ERROR scanning subscription: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Continuing to next subscription..." -ForegroundColor Yellow
    }
}

$summary.ScanEndTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Executive Summary:" -ForegroundColor Cyan
Write-Host "  Scan Duration: $($summary.ScanStartTime) to $($summary.ScanEndTime)" -ForegroundColor White
Write-Host "  Subscriptions Scanned: $($summary.TotalSubscriptionsScanned)" -ForegroundColor White
Write-Host "  Total Resources Scanned: $($summary.TotalResourcesScanned)" -ForegroundColor White
Write-Host "  Total Idle Resources Found: $($summary.TotalIdleResources)" -ForegroundColor Yellow
Write-Host "  Estimated Monthly Savings: USD $([math]::Round($summary.TotalMonthlyCost, 2))" -ForegroundColor Yellow
Write-Host "  Estimated Annual Savings: USD $([math]::Round($summary.TotalAnnualCost, 2))" -ForegroundColor Yellow
Write-Host ""

if ($allIdleResources.Count -gt 0) {
    $detailedReportPath = Join-Path $OutputPath "IdleResources-AllSubscriptions-$timestamp.csv"
    
    $csvData = $allIdleResources | Select-Object SubscriptionName, SubscriptionId, TenantId, ResourceType, ResourceName, ResourceGroup, Location, Status, Size, 
        @{Name='MonthlyUSD'; Expression={'USD ' + $_.EstimatedMonthlyCost}},
        @{Name='AnnualUSD'; Expression={'USD ' + $_.EstimatedAnnualCost}},
        Reason, Recommendation, Tags
    
    $csvData | Export-Csv -Path $detailedReportPath -NoTypeInformation -Force
    Write-Host "Combined CSV Report: $detailedReportPath" -ForegroundColor Green
    
    $summaryReportPath = Join-Path $OutputPath "IdleResources-Summary-$timestamp.json"
    $summary | ConvertTo-Json -Depth 10 | Out-File $summaryReportPath
    Write-Host "Summary JSON Report: $summaryReportPath" -ForegroundColor Green
    
    $htmlReportPath = Join-Path $OutputPath "IdleResources-AllSubscriptions-$timestamp.html"
    $monthlySavings = [math]::Round($summary.TotalMonthlyCost, 2)
    $annualSavings = [math]::Round($summary.TotalAnnualCost, 2)
    
    $html = "<!DOCTYPE html><html><head><title>Azure Idle Resources Report - All Subscriptions</title>"
    $html += "<style>body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}"
    $html += "h1{color:#0078d4}.summary{background-color:#fff;padding:20px;margin:20px 0;border-radius:8px}"
    $html += ".summary-item{margin:10px 0;padding:10px;border-bottom:1px solid #eee}"
    $html += ".summary-label{font-weight:bold;color:#333;display:inline-block;width:250px}"
    $html += ".summary-value{color:#0078d4}.cost{font-size:1.2em;font-weight:bold;color:#107c10}"
    $html += "table{width:100%;border-collapse:collapse;background-color:#fff;margin:20px 0}"
    $html += "th{background-color:#0078d4;color:#fff;padding:12px;text-align:left}"
    $html += "td{padding:10px;border-bottom:1px solid #ddd}"
    $html += "tr:hover{background-color:#f0f0f0}</style></head><body>"
    $html += "<h1>Azure Idle Resources Report - All Subscriptions</h1>"
    $html += "<div class='summary'><h2>Executive Summary</h2>"
    $html += "<div class='summary-item'><span class='summary-label'>Scan Period:</span> <span class='summary-value'>$($summary.ScanStartTime) to $($summary.ScanEndTime)</span></div>"
    $html += "<div class='summary-item'><span class='summary-label'>Subscriptions Scanned:</span> <span class='summary-value'>$($summary.TotalSubscriptionsScanned)</span></div>"
    $html += "<div class='summary-item'><span class='summary-label'>Total Resources Scanned:</span> <span class='summary-value'>$($summary.TotalResourcesScanned)</span></div>"
    $html += "<div class='summary-item'><span class='summary-label'>Total Idle Resources:</span> <span class='cost'>$($summary.TotalIdleResources)</span></div>"
    $html += "<div class='summary-item'><span class='summary-label'>Monthly Savings Potential:</span> <span class='cost'>USD $monthlySavings</span></div>"
    $html += "<div class='summary-item'><span class='summary-label'>Annual Savings Potential:</span> <span class='cost'>USD $annualSavings</span></div></div>"
    $html += "<h2>Idle Resources Details</h2>"
    $html += "<table><tr><th>Subscription</th><th>Tenant ID</th><th>Resource Type</th><th>Resource Name</th><th>Resource Group</th><th>Location</th><th>Status</th><th>Size</th><th>Monthly Cost</th><th>Annual Cost</th><th>Reason</th><th>Recommendation</th></tr>"
    
    foreach ($resource in ($allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        $monthlyCost = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualCost = [math]::Round($resource.EstimatedAnnualCost, 2)
        
        $html += "<tr>"
        $html += "<td>$($resource.SubscriptionName)</td>"
        $html += "<td>$($resource.TenantId)</td>"
        $html += "<td>$($resource.ResourceType)</td>"
        $html += "<td>$($resource.ResourceName)</td>"
        $html += "<td>$($resource.ResourceGroup)</td>"
        $html += "<td>$($resource.Location)</td>"
        $html += "<td>$($resource.Status)</td>"
        $html += "<td>$($resource.Size)</td>"
        $html += "<td>USD $monthlyCost</td>"
        $html += "<td>USD $annualCost</td>"
        $html += "<td>$($resource.Reason)</td>"
        $html += "<td>$($resource.Recommendation)</td>"
        $html += "</tr>"
    }
    
    $html += "</table>"
    $html += "<div class='summary'><h2>Cost Savings Summary</h2>"
    $html += "<p>Total Idle Resources Found: <strong>$($allIdleResources.Count)</strong></p>"
    $html += "<p>Monthly Cost Savings Potential: <strong>USD $monthlySavings</strong></p>"
    $html += "<p>Annual Cost Savings Potential: <strong>USD $annualSavings</strong></p>"
    $html += "<p><strong>Recommendation:</strong> Review these idle resources and delete unused ones to achieve estimated cost savings.</p></div>"
    $html += "</body></html>"
    
    [System.IO.File]::WriteAllText($htmlReportPath, $html)
    Write-Host "Combined HTML Report: $htmlReportPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 15 Costliest Idle Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 15 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, ResourceGroup, Location, @{Name="Monthly Cost";Expression={"USD $($_.EstimatedMonthlyCost)"}}, Reason, Recommendation -AutoSize
    
    Write-Host ""
    Write-Host "Breakdown by Resource Type:" -ForegroundColor Cyan
    $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="Total Monthly Cost";Expression={"USD $([math]::Round(($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2))"}}, @{Name="Total Annual Cost";Expression={"USD $([math]::Round(($_.Group | Measure-Object -Property EstimatedAnnualCost -Sum).Sum, 2))"}} | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Breakdown by Subscription:" -ForegroundColor Cyan
    $summary.SubscriptionDetails | Sort-Object -Property EstimatedMonthlyCost -Descending | Format-Table -Property SubscriptionName, TenantId, ResourcesScanned, IdleResourcesFound, @{Name="Monthly Cost";Expression={"USD $($_.EstimatedMonthlyCost)"}}, @{Name="Annual Cost";Expression={"USD $($_.EstimatedAnnualCost)"}} -AutoSize
    
} else {
    Write-Host "No idle resources found across all subscriptions" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  SEPARATE FILES CREATED FOR EACH SUBSCRIPTION" -ForegroundColor Green
Write-Host "  Each subscription has its own CSV and HTML report" -ForegroundColor Green
Write-Host "  HTML reports automatically opened in browser" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Scan complete. Review all reports in: $OutputPath" -ForegroundColor Cyan
Write-Host ""

