
#Requires -Version 5.1
#Requires -RunAsAdministrator

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
Write-Host "AZURE IDLE RESOURCES SCANNER - ENTERPRISE GRADE" -ForegroundColor Cyan
Write-Host "Scanning ALL Accessible Subscriptions" -ForegroundColor Cyan
Write-Host ""

Write-Host "Authenticating with Azure..." -ForegroundColor Cyan
try {
    $context = Get-AzContext
    if (!$context) {
        Write-Host "No active Azure session found. Connecting..." -ForegroundColor Yellow
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Host "Authentication successful" -ForegroundColor Green
    Write-Host "Logged in as: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "Authentication failed. Please connect to Azure..." -ForegroundColor Red
    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}

Write-Host ""
Write-Host "Retrieving all accessible subscriptions..." -ForegroundColor Yellow

$allSubscriptions = @()
try {
    $allSubscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
} catch {
    Write-Host "Error retrieving subscriptions. Trying current context only..." -ForegroundColor Yellow
    $currentSub = Get-AzContext
    if ($currentSub) {
        $allSubscriptions = @([PSCustomObject]@{
            Name = $currentSub.Subscription.Name
            Id = $currentSub.Subscription.Id
            State = "Enabled"
        })
    }
}

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found. Please check your Azure permissions." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allSubscriptions.Count) enabled subscription(s)" -ForegroundColor Green
Write-Host ""

if ($PrioritySubscriptionId) {
    $prioritySub = $allSubscriptions | Where-Object { $_.Id -eq $PrioritySubscriptionId }
    if ($prioritySub) {
        Write-Host "Priority Subscription: $($prioritySub.Name)" -ForegroundColor Yellow
        $subscriptionsToScan = @($prioritySub) + ($allSubscriptions | Where-Object { $_.Id -ne $PrioritySubscriptionId })
    } else {
        Write-Host "Priority subscription not found. Scanning all available subscriptions." -ForegroundColor Yellow
        $subscriptionsToScan = $allSubscriptions
    }
} else {
    $subscriptionsToScan = $allSubscriptions
}

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
}

$totalSubCount = $subscriptionsToScan.Count
$currentSubNum = 0

foreach ($subscription in $subscriptionsToScan) {
    $currentSubNum++
    
    try {
        Write-Host ""
        Write-Host "[$currentSubNum/$totalSubCount] Scanning: $($subscription.Name)" -ForegroundColor Cyan
        Write-Host "Subscription ID: $($subscription.Id)" -ForegroundColor Gray
        
        try {
            Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
            Write-Host "Context switched successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Cannot switch to subscription. Skipping..." -ForegroundColor Red
            Write-Host "Error Details: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
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
                        Tags = if ($vm.Tags) { ($vm.Tags.Keys | ForEach-Object { "$_=$($vm.Tags[$_])" }) -join "; " } else { "" }
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
                        Tags = if ($disk.Tags) { ($disk.Tags.Keys | ForEach-Object { "$_=$($disk.Tags[$_])" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($disks.Count) Disks | Unattached: $diskIdleCount" -ForegroundColor $(if($diskIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Disks: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Public IP Addresses..." -ForegroundColor Yellow
        try {
            $publicIPs = Get-AzPublicIpAddress
            $subResourceCount += $publicIPs.Count
            $ipIdleCount = 0
            
            foreach ($ip in $publicIPs) {
                if ($ip.IpConfiguration -eq $null) {
                    $ipIdleCount++
                    $ipSku = $ip.Sku.Name
                    $estimatedCost = if ($ipSku -eq "Standard") { 4 } else { 3 }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
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
                        Tags = if ($ip.Tags) { ($ip.Tags.Keys | ForEach-Object { "$_=$($ip.Tags[$_])" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($publicIPs.Count) Public IPs | Unassigned: $ipIdleCount" -ForegroundColor $(if($ipIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Public IPs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Network Interfaces..." -ForegroundColor Yellow
        try {
            $nics = Get-AzNetworkInterface
            $subResourceCount += $nics.Count
            $nicIdleCount = 0
            
            foreach ($nic in $nics) {
                if ($nic.VirtualMachine -eq $null) {
                    $nicIdleCount++
                    $estimatedCost = 2
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
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
                        Tags = if ($nic.Tags) { ($nic.Tags.Keys | ForEach-Object { "$_=$($nic.Tags[$_])" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($nics.Count) NICs | Unattached: $nicIdleCount" -ForegroundColor $(if($nicIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking NICs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Storage Accounts..." -ForegroundColor Yellow
        try {
            $storageAccounts = Get-AzStorageAccount
            $subResourceCount += $storageAccounts.Count
            $storageIdleCount = 0
            
            foreach ($storage in $storageAccounts) {
                try {
                    $ctx = $storage.Context
                    $containers = Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue
                    $totalSize = 0
                    $blobCount = 0
                    
                    foreach ($container in $containers) {
                        $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx -ErrorAction SilentlyContinue
                        $blobCount += $blobs.Count
                        foreach ($blob in $blobs) {
                            $totalSize += $blob.Length
                        }
                    }
                    
                    $sizeGB = [math]::Round($totalSize / 1GB, 2)
                    
                    if ($sizeGB -lt 0.1 -and $blobCount -lt 5) {
                        $storageIdleCount++
                        $storageTier = $storage.Sku.Name
                        $estimatedCost = switch ($storageTier) {
                            "Premium_LRS" { 15 }
                            "Standard_GRS" { 8 }
                            default { 5 }
                        }
                        $subTotalCost += $estimatedCost
                        
                        $subIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
                            ResourceType = "Storage Account"
                            ResourceName = $storage.StorageAccountName
                            ResourceGroup = $storage.ResourceGroupName
                            Location = $storage.Location
                            Status = "Empty/Minimal Data"
                            Size = "$sizeGB GB | $blobCount blobs | $storageTier"
                            EstimatedMonthlyCost = $estimatedCost
                            EstimatedAnnualCost = $estimatedCost * 12
                            Reason = "Storage account empty or has minimal data"
                            Recommendation = "Delete if not needed - base charge applies"
                            Tags = if ($storage.Tags) { ($storage.Tags.Keys | ForEach-Object { "$_=$($storage.Tags[$_])" }) -join "; " } else { "" }
                        }
                    }
                } catch {
                    Write-Host "  Unable to analyze: $($storage.StorageAccountName)" -ForegroundColor Gray
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
                        Tags = if ($asp.Tags) { ($asp.Tags.Keys | ForEach-Object { "$_=$($asp.Tags[$_])" }) -join "; " } else { "" }
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
                if ($lb.BackendAddressPools.Count -eq 0 -or ($lb.BackendAddressPools[0].BackendIpConfigurations -and $lb.BackendAddressPools[0].BackendIpConfigurations.Count -eq 0)) {
                    $lbIdleCount++
                    $lbSku = $lb.Sku.Name
                    $estimatedCost = if ($lbSku -eq "Standard") { 25 } else { 18 }
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
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
                        Tags = if ($lb.Tags) { ($lb.Tags.Keys | ForEach-Object { "$_=$($lb.Tags[$_])" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($loadBalancers.Count) Load Balancers | Idle: $lbIdleCount" -ForegroundColor $(if($lbIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Load Balancers: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking SQL Databases..." -ForegroundColor Yellow
        try {
            $sqlServers = Get-AzSqlServer
            $subResourceCount += $sqlServers.Count
            $sqlIdleCount = 0
            
            foreach ($sqlServer in $sqlServers) {
                $databases = Get-AzSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName | Where-Object { $_.DatabaseName -ne "master" }
                foreach ($db in $databases) {
                    if ($db.Status -eq "Paused" -or $db.CurrentServiceObjectiveName -like "*DW*") {
                        $sqlIdleCount++
                        $estimatedCost = 100
                        $subTotalCost += $estimatedCost
                        
                        $subIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
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
                            Tags = if ($db.Tags) { ($db.Tags.Keys | ForEach-Object { "$_=$($db.Tags[$_])" }) -join "; " } else { "" }
                        }
                    }
                }
            }
            Write-Host "  Found: $($sqlServers.Count) SQL Servers | Idle Databases: $sqlIdleCount" -ForegroundColor $(if($sqlIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking SQL: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        $allIdleResources += $subIdleResources
        
        $summary.TotalSubscriptionsScanned++
        $summary.TotalResourcesScanned += $subResourceCount
        $summary.TotalIdleResources += $subIdleResources.Count
        $summary.TotalMonthlyCost += $subTotalCost
        $summary.TotalAnnualCost += ($subTotalCost * 12)
        
        $summary.SubscriptionDetails += [PSCustomObject]@{
            SubscriptionName = $subscription.Name
            SubscriptionId = $subscription.Id
            ResourcesScanned = $subResourceCount
            IdleResourcesFound = $subIdleResources.Count
            EstimatedMonthlyCost = [math]::Round($subTotalCost, 2)
            EstimatedAnnualCost = [math]::Round($subTotalCost * 12, 2)
        }
        
        Write-Host "  Subscription Total: $($subIdleResources.Count) idle resources | Est Cost: `$$([math]::Round($subTotalCost, 2))/month" -ForegroundColor $(if($subIdleResources.Count -gt 0){"Yellow"}else{"Green"})
        
    } catch {
        Write-Host "  ERROR scanning subscription: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Continuing to next subscription..." -ForegroundColor Yellow
    }
}

$summary.ScanEndTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Scan Duration: $($summary.ScanStartTime) to $($summary.ScanEndTime)" -ForegroundColor White
Write-Host "  Subscriptions Scanned: $($summary.TotalSubscriptionsScanned)" -ForegroundColor White
Write-Host "  Total Resources Scanned: $($summary.TotalResourcesScanned)" -ForegroundColor White
Write-Host "  Total Idle Resources Found: $($summary.TotalIdleResources)" -ForegroundColor Yellow
Write-Host "  Estimated Monthly Savings: `$$([math]::Round($summary.TotalMonthlyCost, 2))" -ForegroundColor Yellow
Write-Host "  Estimated Annual Savings: `$$([math]::Round($summary.TotalAnnualCost, 2))" -ForegroundColor Yellow
Write-Host ""

if ($allIdleResources.Count -gt 0) {
    $detailedReportPath = Join-Path $OutputPath "IdleResources-Detailed-$timestamp.csv"
    $allIdleResources | Export-Csv -Path $detailedReportPath -NoTypeInformation
    Write-Host "Detailed CSV Report: $detailedReportPath" -ForegroundColor Green
    
    $summaryReportPath = Join-Path $OutputPath "IdleResources-Summary-$timestamp.json"
    $summary | ConvertTo-Json -Depth 10 | Out-File $summaryReportPath
    Write-Host "Summary JSON Report: $summaryReportPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 15 Costliest Idle Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 15 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, ResourceGroup, Location, @{Name="Monthly Cost";Expression={"`$$($_.EstimatedMonthlyCost)"}}, Reason -AutoSize
    
    Write-Host ""
    Write-Host "Breakdown by Resource Type:" -ForegroundColor Cyan
    $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="Total Monthly Cost";Expression={"`$$([math]::Round(($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2))"}}, @{Name="Total Annual Cost";Expression={"`$$([math]::Round(($_.Group | Measure-Object -Property EstimatedAnnualCost -Sum).Sum, 2))"}} | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Breakdown by Subscription:" -ForegroundColor Cyan
    $summary.SubscriptionDetails | Sort-Object -Property EstimatedMonthlyCost -Descending | Format-Table -Property SubscriptionName, ResourcesScanned, IdleResourcesFound, @{Name="Monthly Cost";Expression={"`$$($_.EstimatedMonthlyCost)"}}, @{Name="Annual Cost";Expression={"`$$($_.EstimatedAnnualCost)"}} -AutoSize
    
} else {
    Write-Host "No idle resources found across all subscriptions" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pushing reports to GitHub..." -ForegroundColor Cyan
try {
    if (!(Test-Path ".git")) {
        git init
        git remote add origin https://github.com/Riz7886/Pyex-AVD-deployment.git
    }
    
    git add $OutputPath
    $commitMsg = "Idle Resources Report $timestamp - $($summary.TotalIdleResources) resources - Save `$$([math]::Round($summary.TotalMonthlyCost, 2))/month"
    git commit -m $commitMsg
    git push origin main
    
    Write-Host "GitHub push successful" -ForegroundColor Green
    Write-Host "Repository: https://github.com/Riz7886/Pyex-AVD-deployment.git" -ForegroundColor White
} catch {
    Write-Host "GitHub push failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Manual push: git add $OutputPath && git commit -m 'Idle resources report' && git push origin main" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Scan complete. Review detailed reports in: $OutputPath" -ForegroundColor Cyan
Write-Host ""
