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

function Get-AzureData {
    param([string]$Command)
    try {
        $output = Invoke-Expression $Command
        if ($LASTEXITCODE -eq 0) {
            return ($output | ConvertFrom-Json)
        }
        return @()
    } catch {
        return @()
    }
}

function Get-EstimatedMonthlyCost {
    param(
        [string]$ResourceType,
        [string]$SKU,
        [string]$Size
    )
    
    switch -Wildcard ($ResourceType) {
        "VM" {
            switch -Wildcard ($SKU) {
                "*D4*" { return 150 }
                "*D2*" { return 75 }
                "*B4*" { return 130 }
                "*B2*" { return 50 }
                "*E*" { return 200 }
                "*F*" { return 100 }
                default { return 50 }
            }
        }
        "Disk" {
            if ($SKU -match "Premium") { return 20 }
            if ($SKU -match "StandardSSD") { return 10 }
            return 5
        }
        "PublicIP" { return 4 }
        "NIC" { return 2 }
        "LoadBalancer" { return 25 }
        "Storage" {
            if ($SKU -match "Premium") { return 15 }
            if ($SKU -match "GRS") { return 8 }
            return 5
        }
        "AppServicePlan" {
            if ($SKU -match "Premium") { return 150 }
            if ($SKU -match "Standard") { return 75 }
            return 55
        }
        "SQL" { return 100 }
        default { return 10 }
    }
}

Write-Host ""
Write-Host "AZURE IDLE RESOURCES SCANNER - ENTERPRISE GRADE" -ForegroundColor Cyan
Write-Host "Scanning ALL Accessible Subscriptions" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking Azure CLI..." -ForegroundColor Cyan
try {
    $null = az account show --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not logged in to Azure CLI. Logging in..." -ForegroundColor Yellow
        az login | Out-Null
    }
    Write-Host "Azure CLI authentication successful" -ForegroundColor Green
} catch {
    Write-Host "Azure CLI not available. Installing..." -ForegroundColor Yellow
    Write-Host "Please install Azure CLI from: https://aka.ms/installazurecliwindows" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Retrieving all accessible subscriptions..." -ForegroundColor Yellow

$allSubscriptions = Get-AzureData -Command "az account list --all --output json"

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found. Please check your Azure permissions." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($allSubscriptions.Count) enabled subscription(s)" -ForegroundColor Green
Write-Host ""

foreach ($sub in $allSubscriptions) {
    $status = if ($sub.state -eq "Enabled") { "ACTIVE" } else { $sub.state }
    Write-Host "  - $($sub.name)" -ForegroundColor White -NoNewline
    Write-Host " [$status]" -ForegroundColor $(if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" })
}

if ($PrioritySubscriptionId) {
    $prioritySub = $allSubscriptions | Where-Object { $_.id -eq $PrioritySubscriptionId }
    if ($prioritySub) {
        Write-Host ""
        Write-Host "Priority Subscription: $($prioritySub.name)" -ForegroundColor Yellow
        $subscriptionsToScan = @($prioritySub) + ($allSubscriptions | Where-Object { $_.id -ne $PrioritySubscriptionId -and $_.state -eq "Enabled" })
    } else {
        Write-Host ""
        Write-Host "Priority subscription not found. Scanning all available subscriptions." -ForegroundColor Yellow
        $subscriptionsToScan = $allSubscriptions | Where-Object { $_.state -eq "Enabled" }
    }
} else {
    $subscriptionsToScan = $allSubscriptions | Where-Object { $_.state -eq "Enabled" }
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
    
    if ($subscription.state -ne "Enabled") {
        Write-Host "Skipping disabled subscription: $($subscription.name)" -ForegroundColor Yellow
        continue
    }
    
    try {
        Write-Host ""
        Write-Host "[$currentSubNum/$totalSubCount] Scanning: $($subscription.name)" -ForegroundColor Cyan
        Write-Host "Subscription ID: $($subscription.id)" -ForegroundColor Gray
        
        az account set --subscription $subscription.id 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Cannot switch to subscription. Skipping..." -ForegroundColor Red
            continue
        }
        Write-Host "Context switched successfully" -ForegroundColor Green
        
        $subIdleResources = @()
        $subTotalCost = 0
        $subResourceCount = 0
        
        Write-Host "Checking Virtual Machines..." -ForegroundColor Yellow
        try {
            $vms = Get-AzureData -Command "az vm list -d --subscription $($subscription.id) --output json"
            $subResourceCount += $vms.Count
            $vmIdleCount = 0
            
            foreach ($vm in $vms) {
                if ($vm.powerState -and ($vm.powerState -eq "VM deallocated" -or $vm.powerState -eq "VM stopped")) {
                    $vmIdleCount++
                    $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "VM" -SKU $vm.hardwareProfile.vmSize
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Virtual Machine"
                        ResourceName = $vm.name
                        ResourceGroup = $vm.resourceGroup
                        Location = $vm.location
                        Status = $vm.powerState
                        Size = $vm.hardwareProfile.vmSize
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "VM is stopped or deallocated - consuming storage costs"
                        Recommendation = "Delete VM if no longer needed or restart if required"
                        Tags = if ($vm.tags) { ($vm.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($vms.Count) VMs | Idle: $vmIdleCount" -ForegroundColor $(if($vmIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking VMs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Unattached Disks..." -ForegroundColor Yellow
        try {
            $disks = Get-AzureData -Command "az disk list --subscription $($subscription.id) --output json"
            $subResourceCount += $disks.Count
            $diskIdleCount = 0
            
            foreach ($disk in $disks) {
                if ([string]::IsNullOrEmpty($disk.managedBy)) {
                    $diskIdleCount++
                    $diskSizeGB = $disk.diskSizeGb
                    $diskTier = $disk.sku.name
                    $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "Disk" -SKU $diskTier
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Unattached Disk"
                        ResourceName = $disk.name
                        ResourceGroup = $disk.resourceGroup
                        Location = $disk.location
                        Status = "Unattached"
                        Size = "$diskSizeGB GB - $diskTier"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Disk not attached to any VM - wasting storage costs"
                        Recommendation = "Delete if no longer needed or attach to VM"
                        Tags = if ($disk.tags) { ($disk.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($disks.Count) Disks | Unattached: $diskIdleCount" -ForegroundColor $(if($diskIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Disks: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Public IP Addresses..." -ForegroundColor Yellow
        try {
            $publicIPs = Get-AzureData -Command "az network public-ip list --subscription $($subscription.id) --output json"
            $subResourceCount += $publicIPs.Count
            $ipIdleCount = 0
            
            foreach ($pip in $publicIPs) {
                if ([string]::IsNullOrEmpty($pip.ipConfiguration)) {
                    $ipIdleCount++
                    $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "PublicIP"
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Public IP Address"
                        ResourceName = $pip.name
                        ResourceGroup = $pip.resourceGroup
                        Location = $pip.location
                        Status = "Unassigned"
                        Size = "$($pip.sku.name) SKU"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Public IP not assigned to any resource"
                        Recommendation = "Delete if not needed - incurs monthly charge"
                        Tags = if ($pip.tags) { ($pip.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($publicIPs.Count) Public IPs | Unassigned: $ipIdleCount" -ForegroundColor $(if($ipIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Public IPs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Network Interfaces..." -ForegroundColor Yellow
        try {
            $nics = Get-AzureData -Command "az network nic list --subscription $($subscription.id) --output json"
            $subResourceCount += $nics.Count
            $nicIdleCount = 0
            
            foreach ($nic in $nics) {
                if ([string]::IsNullOrEmpty($nic.virtualMachine)) {
                    $nicIdleCount++
                    $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "NIC"
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Network Interface"
                        ResourceName = $nic.name
                        ResourceGroup = $nic.resourceGroup
                        Location = $nic.location
                        Status = "Unattached"
                        Size = "N/A"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "NIC not attached to any VM"
                        Recommendation = "Delete if VM was removed"
                        Tags = if ($nic.tags) { ($nic.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($nics.Count) NICs | Unattached: $nicIdleCount" -ForegroundColor $(if($nicIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking NICs: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Storage Accounts..." -ForegroundColor Yellow
        try {
            $storageAccounts = Get-AzureData -Command "az storage account list --subscription $($subscription.id) --output json"
            $subResourceCount += $storageAccounts.Count
            $storageIdleCount = 0
            
            foreach ($storage in $storageAccounts) {
                try {
                    $containers = Get-AzureData -Command "az storage container list --account-name $($storage.name) --auth-mode login --output json 2>$null"
                    
                    if ($containers.Count -eq 0) {
                        $storageIdleCount++
                        $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "Storage" -SKU $storage.sku.name
                        $subTotalCost += $estimatedCost
                        
                        $subIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.name
                            SubscriptionId = $subscription.id
                            ResourceType = "Storage Account"
                            ResourceName = $storage.name
                            ResourceGroup = $storage.resourceGroup
                            Location = $storage.location
                            Status = "Empty/No Containers"
                            Size = "$($storage.sku.name)"
                            EstimatedMonthlyCost = $estimatedCost
                            EstimatedAnnualCost = $estimatedCost * 12
                            Reason = "Storage account has no containers or minimal data"
                            Recommendation = "Delete if not needed - base charge applies"
                            Tags = if ($storage.tags) { ($storage.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                        }
                    }
                } catch {
                    Write-Host "  Unable to analyze: $($storage.name)" -ForegroundColor Gray
                }
            }
            Write-Host "  Found: $($storageAccounts.Count) Storage Accounts | Empty: $storageIdleCount" -ForegroundColor $(if($storageIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Storage: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Load Balancers..." -ForegroundColor Yellow
        try {
            $loadBalancers = Get-AzureData -Command "az network lb list --subscription $($subscription.id) --output json"
            $subResourceCount += $loadBalancers.Count
            $lbIdleCount = 0
            
            foreach ($lb in $loadBalancers) {
                $backendEmpty = $true
                if ($lb.backendAddressPools) {
                    foreach ($pool in $lb.backendAddressPools) {
                        if ($pool.backendIPConfigurations -and $pool.backendIPConfigurations.Count -gt 0) {
                            $backendEmpty = $false
                            break
                        }
                    }
                }
                if ($backendEmpty) {
                    $lbIdleCount++
                    $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "LoadBalancer"
                    $subTotalCost += $estimatedCost
                    
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Load Balancer"
                        ResourceName = $lb.name
                        ResourceGroup = $lb.resourceGroup
                        Location = $lb.location
                        Status = "No Backend Pool"
                        Size = "$($lb.sku.name) SKU"
                        EstimatedMonthlyCost = $estimatedCost
                        EstimatedAnnualCost = $estimatedCost * 12
                        Reason = "Load Balancer has no backend resources"
                        Recommendation = "Delete if infrastructure was removed"
                        Tags = if ($lb.tags) { ($lb.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($loadBalancers.Count) Load Balancers | Idle: $lbIdleCount" -ForegroundColor $(if($lbIdleCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Load Balancers: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host "Checking Empty Resource Groups..." -ForegroundColor Yellow
        try {
            $resourceGroups = Get-AzureData -Command "az group list --subscription $($subscription.id) --output json"
            $emptyRGCount = 0
            
            foreach ($rg in $resourceGroups) {
                $resources = Get-AzureData -Command "az resource list --resource-group $($rg.name) --subscription $($subscription.id) --output json"
                if ($resources.Count -eq 0) {
                    $emptyRGCount++
                    $subIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.name
                        SubscriptionId = $subscription.id
                        ResourceType = "Resource Group"
                        ResourceName = $rg.name
                        ResourceGroup = "N/A"
                        Location = $rg.location
                        Status = "Empty"
                        Size = "N/A"
                        EstimatedMonthlyCost = 0
                        EstimatedAnnualCost = 0
                        Reason = "No resources inside"
                        Recommendation = "Delete empty resource group"
                        Tags = if ($rg.tags) { ($rg.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                    }
                }
            }
            Write-Host "  Found: $($resourceGroups.Count) Resource Groups | Empty: $emptyRGCount" -ForegroundColor $(if($emptyRGCount -gt 0){"Yellow"}else{"Green"})
        } catch {
            Write-Host "  Error checking Resource Groups: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        $allIdleResources += $subIdleResources
        
        $summary.TotalSubscriptionsScanned++
        $summary.TotalResourcesScanned += $subResourceCount
        $summary.TotalIdleResources += $subIdleResources.Count
        $summary.TotalMonthlyCost += $subTotalCost
        $summary.TotalAnnualCost += ($subTotalCost * 12)
        
        $summary.SubscriptionDetails += [PSCustomObject]@{
            SubscriptionName = $subscription.name
            SubscriptionId = $subscription.id
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
Write-Host ""
