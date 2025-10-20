#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$TestMode = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\Logs"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Red
Write-Host "  AZURE IDLE RESOURCES DELETION TOOL" -ForegroundColor Red
Write-Host "  DANGER: THIS SCRIPT DELETES RESOURCES PERMANENTLY!" -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""

if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $LogPath "DeletionLog-$timestamp.txt"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message -ForegroundColor White }
    }
}

Write-Log "Deletion script started" "INFO"
Write-Host ""

Write-Host "Step 1: Azure Authentication" -ForegroundColor Yellow
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Log "Authenticated as: $($context.Account.Id)" "SUCCESS"
Write-Host ""

Write-Host "Step 2: Discovering Subscriptions" -ForegroundColor Yellow
$allSubscriptions = @(Get-AzSubscription)

if ($allSubscriptions.Count -eq 0) {
    Write-Log "ERROR: No subscriptions found!" "ERROR"
    exit 1
}

Write-Host "Found $($allSubscriptions.Count) subscription(s)" -ForegroundColor Green
Write-Host ""

$tenantGroups = $allSubscriptions | Group-Object -Property TenantId
foreach ($tenantGroup in $tenantGroups) {
    Write-Host "Tenant: $($tenantGroup.Name)" -ForegroundColor Yellow
    foreach ($sub in $tenantGroup.Group) {
        Write-Host "  - $($sub.Name)" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "Subscription Selection:" -ForegroundColor Yellow
Write-Host "  [1] Delete idle resources in ALL subscriptions" -ForegroundColor White
Write-Host "  [2] Select specific subscriptions" -ForegroundColor White
Write-Host ""
$choice = Read-Host "Enter your choice (1 or 2)"

if ($choice -eq "2") {
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $allSubscriptions.Count; $i++) {
        $sub = $allSubscriptions[$i]
        Write-Host "  [$($i+1)] $($sub.Name)" -ForegroundColor White
    }
    Write-Host ""
    $selections = Read-Host "Enter subscription numbers separated by commas (e.g., 1,3)"
    
    $selectedIndices = $selections -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
    $subscriptionsToProcess = @()
    foreach ($idx in $selectedIndices) {
        if ($idx -ge 0 -and $idx -lt $allSubscriptions.Count) {
            $subscriptionsToProcess += $allSubscriptions[$idx]
        }
    }
} else {
    $subscriptionsToProcess = $allSubscriptions
}

Write-Log "Will process $($subscriptionsToProcess.Count) subscription(s)" "INFO"
Write-Host ""

$allIdleResources = @()
$deletionQueue = @()

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCANNING FOR IDLE RESOURCES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

foreach ($subscription in $subscriptionsToProcess) {
    try {
        Write-Host ""
        Write-Host "Scanning Subscription: $($subscription.Name)" -ForegroundColor Cyan
        Write-Log "Scanning subscription: $($subscription.Name)" "INFO"
        
        Set-AzContext -SubscriptionId $subscription.Id -TenantId $subscription.TenantId | Out-Null
        
        Write-Host "  Checking Virtual Machines..." -ForegroundColor Yellow
        try {
            $vms = Get-AzVM -Status
            foreach ($vm in $vms) {
                if ($vm.PowerState -eq "VM deallocated" -or $vm.PowerState -eq "VM stopped") {
                    $allIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Virtual Machine"
                        ResourceName = $vm.Name
                        ResourceGroup = $vm.ResourceGroupName
                        Location = $vm.Location
                        Status = $vm.PowerState
                        ResourceId = $vm.Id
                        EstimatedMonthlyCost = 150
                    }
                }
            }
        } catch {
            Write-Log "Error checking VMs in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking Unattached Disks..." -ForegroundColor Yellow
        try {
            $disks = Get-AzDisk
            foreach ($disk in $disks) {
                if ($disk.ManagedBy -eq $null) {
                    $allIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Unattached Disk"
                        ResourceName = $disk.Name
                        ResourceGroup = $disk.ResourceGroupName
                        Location = $disk.Location
                        Status = "Unattached"
                        ResourceId = $disk.Id
                        EstimatedMonthlyCost = [math]::Round(($disk.DiskSizeGB * 0.1), 2)
                    }
                }
            }
        } catch {
            Write-Log "Error checking Disks in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking Public IP Addresses..." -ForegroundColor Yellow
        try {
            $publicIPs = @(Get-AzPublicIpAddress -ErrorAction SilentlyContinue)
            if ($publicIPs -and $publicIPs.Count -gt 0) {
                foreach ($ip in $publicIPs) {
                    if ($ip.IpConfiguration -eq $null) {
                        $allIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
                            TenantId = $subscription.TenantId
                            ResourceType = "Public IP Address"
                            ResourceName = $ip.Name
                            ResourceGroup = $ip.ResourceGroupName
                            Location = $ip.Location
                            Status = "Unassigned"
                            ResourceId = $ip.Id
                            EstimatedMonthlyCost = 3
                        }
                    }
                }
            }
        } catch {
            Write-Log "Error checking Public IPs in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking Network Interfaces..." -ForegroundColor Yellow
        try {
            $nics = Get-AzNetworkInterface
            foreach ($nic in $nics) {
                if ($nic.VirtualMachine -eq $null) {
                    $allIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Network Interface"
                        ResourceName = $nic.Name
                        ResourceGroup = $nic.ResourceGroupName
                        Location = $nic.Location
                        Status = "Unattached"
                        ResourceId = $nic.Id
                        EstimatedMonthlyCost = 2
                    }
                }
            }
        } catch {
            Write-Log "Error checking NICs in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking Storage Accounts..." -ForegroundColor Yellow
        try {
            $storageAccounts = Get-AzStorageAccount
            foreach ($storage in $storageAccounts) {
                try {
                    $ctx = $storage.Context
                    $containers = @(Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue)
                    $totalSize = 0
                    $blobCount = 0
                    
                    if ($containers -and $containers.Count -gt 0) {
                        foreach ($container in $containers) {
                            $blobs = @(Get-AzStorageBlob -Container $container.Name -Context $ctx -ErrorAction SilentlyContinue)
                            if ($blobs) {
                                $blobCount += $blobs.Count
                                foreach ($blob in $blobs) {
                                    if ($blob.Length) {
                                        $totalSize += $blob.Length
                                    }
                                }
                            }
                        }
                    }
                    
                    $sizeGB = [math]::Round($totalSize / 1GB, 2)
                    
                    if ($sizeGB -lt 0.1 -and $blobCount -lt 5) {
                        $allIdleResources += [PSCustomObject]@{
                            SubscriptionName = $subscription.Name
                            SubscriptionId = $subscription.Id
                            TenantId = $subscription.TenantId
                            ResourceType = "Storage Account"
                            ResourceName = $storage.StorageAccountName
                            ResourceGroup = $storage.ResourceGroupName
                            Location = $storage.Location
                            Status = "Empty/Minimal"
                            ResourceId = $storage.Id
                            EstimatedMonthlyCost = 5
                        }
                    }
                } catch {
                    Write-Host "  Unable to analyze: $($storage.StorageAccountName)" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Log "Error checking Storage in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking App Service Plans..." -ForegroundColor Yellow
        try {
            $appServicePlans = Get-AzAppServicePlan
            foreach ($asp in $appServicePlans) {
                $apps = Get-AzWebApp -AppServicePlan $asp -ErrorAction SilentlyContinue
                if ($apps.Count -eq 0) {
                    $allIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "App Service Plan"
                        ResourceName = $asp.Name
                        ResourceGroup = $asp.ResourceGroup
                        Location = $asp.Location
                        Status = "Empty"
                        ResourceId = $asp.Id
                        EstimatedMonthlyCost = 75
                    }
                }
            }
        } catch {
            Write-Log "Error checking App Service Plans in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking Load Balancers..." -ForegroundColor Yellow
        try {
            $loadBalancers = Get-AzLoadBalancer
            foreach ($lb in $loadBalancers) {
                if ($lb.BackendAddressPools.Count -eq 0 -or $lb.BackendAddressPools[0].BackendIpConfigurations.Count -eq 0) {
                    $allIdleResources += [PSCustomObject]@{
                        SubscriptionName = $subscription.Name
                        SubscriptionId = $subscription.Id
                        TenantId = $subscription.TenantId
                        ResourceType = "Load Balancer"
                        ResourceName = $lb.Name
                        ResourceGroup = $lb.ResourceGroupName
                        Location = $lb.Location
                        Status = "No Backend"
                        ResourceId = $lb.Id
                        EstimatedMonthlyCost = 20
                    }
                }
            }
        } catch {
            Write-Log "Error checking Load Balancers in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
        Write-Host "  Checking SQL Databases..." -ForegroundColor Yellow
        try {
            $sqlServers = @(Get-AzSqlServer -ErrorAction SilentlyContinue)
            if ($sqlServers -and $sqlServers.Count -gt 0) {
                foreach ($sqlServer in $sqlServers) {
                    $databases = @(Get-AzSqlDatabase -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne "master" })
                    if ($databases -and $databases.Count -gt 0) {
                        foreach ($db in $databases) {
                            if ($db.Status -eq "Paused" -or $db.CurrentServiceObjectiveName -like "*DW*") {
                                $allIdleResources += [PSCustomObject]@{
                                    SubscriptionName = $subscription.Name
                                    SubscriptionId = $subscription.Id
                                    TenantId = $subscription.TenantId
                                    ResourceType = "SQL Database"
                                    ResourceName = "$($sqlServer.ServerName)/$($db.DatabaseName)"
                                    ResourceGroup = $sqlServer.ResourceGroupName
                                    Location = $sqlServer.Location
                                    Status = $db.Status
                                    ResourceId = $db.ResourceId
                                    EstimatedMonthlyCost = 100
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Log "Error checking SQL in $($subscription.Name): $($_.Exception.Message)" "ERROR"
        }
        
    } catch {
        Write-Log "ERROR scanning subscription $($subscription.Name): $($_.Exception.Message)" "ERROR"
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($allIdleResources.Count -eq 0) {
    Write-Log "No idle resources found across all subscriptions!" "SUCCESS"
    Write-Host ""
    exit 0
}

$totalCost = ($allIdleResources | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
Write-Host "Total Idle Resources Found: $($allIdleResources.Count)" -ForegroundColor Yellow
Write-Host "Estimated Monthly Savings: USD $([math]::Round($totalCost, 2))" -ForegroundColor Yellow
Write-Host ""

Write-Host "Idle Resources by Type:" -ForegroundColor Cyan
$allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count | Format-Table -AutoSize
Write-Host ""

Write-Host "Idle Resources by Subscription:" -ForegroundColor Cyan
$allIdleResources | Group-Object -Property SubscriptionName | Select-Object Name, Count | Format-Table -AutoSize
Write-Host ""

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  TEST MODE: DELETE ONE RESOURCE" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "Before deleting all resources, let's test with ONE resource first." -ForegroundColor Yellow
Write-Host ""

$testResource = $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 1

Write-Host "Test Resource Selected:" -ForegroundColor Cyan
Write-Host "  Subscription: $($testResource.SubscriptionName)" -ForegroundColor White
Write-Host "  Resource Type: $($testResource.ResourceType)" -ForegroundColor White
Write-Host "  Resource Name: $($testResource.ResourceName)" -ForegroundColor White
Write-Host "  Resource Group: $($testResource.ResourceGroup)" -ForegroundColor White
Write-Host "  Location: $($testResource.Location)" -ForegroundColor White
Write-Host "  Monthly Cost: USD $($testResource.EstimatedMonthlyCost)" -ForegroundColor White
Write-Host ""
Write-Host "This is the highest-cost idle resource." -ForegroundColor Yellow
Write-Host ""

$confirmTest = Read-Host "Do you want to DELETE this test resource? (Type 'YES' to confirm)"

if ($confirmTest -ne "YES") {
    Write-Log "Test deletion cancelled by user" "WARNING"
    Write-Host "Test cancelled. No resources deleted." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Deleting test resource..." -ForegroundColor Yellow
Write-Log "Starting test deletion: $($testResource.ResourceType) - $($testResource.ResourceName)" "INFO"

try {
    Set-AzContext -SubscriptionId $testResource.SubscriptionId -TenantId $testResource.TenantId | Out-Null
    
    $deleteSuccess = $false
    
    switch ($testResource.ResourceType) {
        "Virtual Machine" {
            Remove-AzVM -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "Unattached Disk" {
            Remove-AzDisk -ResourceGroupName $testResource.ResourceGroup -DiskName $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "Public IP Address" {
            Remove-AzPublicIpAddress -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "Network Interface" {
            Remove-AzNetworkInterface -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "Storage Account" {
            Remove-AzStorageAccount -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "App Service Plan" {
            Remove-AzAppServicePlan -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "Load Balancer" {
            Remove-AzLoadBalancer -ResourceGroupName $testResource.ResourceGroup -Name $testResource.ResourceName -Force
            $deleteSuccess = $true
        }
        "SQL Database" {
            $parts = $testResource.ResourceName -split '/'
            $serverName = $parts[0]
            $dbName = $parts[1]
            Remove-AzSqlDatabase -ResourceGroupName $testResource.ResourceGroup -ServerName $serverName -DatabaseName $dbName -Force
            $deleteSuccess = $true
        }
    }
    
    if ($deleteSuccess) {
        Write-Log "SUCCESS: Deleted test resource: $($testResource.ResourceName)" "SUCCESS"
        Write-Host ""
        Write-Host "✓ Test deletion successful!" -ForegroundColor Green
        Write-Host ""
    }
    
} catch {
    Write-Log "ERROR deleting test resource: $($_.Exception.Message)" "ERROR"
    Write-Host ""
    Write-Host "Test deletion failed. Check logs for details." -ForegroundColor Red
    Write-Host ""
    exit 1
}

$remainingResources = $allIdleResources | Where-Object { $_.ResourceId -ne $testResource.ResourceId }

if ($remainingResources.Count -eq 0) {
    Write-Host "No more idle resources to delete." -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  DELETE ALL REMAINING IDLE RESOURCES" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "Remaining Idle Resources: $($remainingResources.Count)" -ForegroundColor Yellow
Write-Host "Estimated Monthly Savings: USD $([math]::Round(($remainingResources | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2))" -ForegroundColor Yellow
Write-Host ""
Write-Host "THIS WILL DELETE ALL IDLE RESOURCES IN ALL SELECTED SUBSCRIPTIONS!" -ForegroundColor Red
Write-Host ""

$confirmAll = Read-Host "Do you want to DELETE ALL remaining idle resources? (Type 'DELETE ALL' to confirm)"

if ($confirmAll -ne "DELETE ALL") {
    Write-Log "Bulk deletion cancelled by user" "WARNING"
    Write-Host "Deletion cancelled. Only the test resource was deleted." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Starting bulk deletion..." -ForegroundColor Red
Write-Log "Starting bulk deletion of $($remainingResources.Count) resources" "INFO"

$successCount = 0
$failCount = 0

foreach ($resource in $remainingResources) {
    try {
        Set-AzContext -SubscriptionId $resource.SubscriptionId -TenantId $resource.TenantId | Out-Null
        
        Write-Host "Deleting: $($resource.ResourceType) - $($resource.ResourceName)" -ForegroundColor Yellow
        
        switch ($resource.ResourceType) {
            "Virtual Machine" {
                Remove-AzVM -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "Unattached Disk" {
                Remove-AzDisk -ResourceGroupName $resource.ResourceGroup -DiskName $resource.ResourceName -Force
            }
            "Public IP Address" {
                Remove-AzPublicIpAddress -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "Network Interface" {
                Remove-AzNetworkInterface -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "Storage Account" {
                Remove-AzStorageAccount -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "App Service Plan" {
                Remove-AzAppServicePlan -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "Load Balancer" {
                Remove-AzLoadBalancer -ResourceGroupName $resource.ResourceGroup -Name $resource.ResourceName -Force
            }
            "SQL Database" {
                $parts = $resource.ResourceName -split '/'
                $serverName = $parts[0]
                $dbName = $parts[1]
                Remove-AzSqlDatabase -ResourceGroupName $resource.ResourceGroup -ServerName $serverName -DatabaseName $dbName -Force
            }
        }
        
        Write-Log "SUCCESS: Deleted $($resource.ResourceType) - $($resource.ResourceName)" "SUCCESS"
        $successCount++
        
    } catch {
        Write-Log "ERROR deleting $($resource.ResourceType) - $($resource.ResourceName): $($_.Exception.Message)" "ERROR"
        $failCount++
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  DELETION COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total Resources Processed: $($allIdleResources.Count)" -ForegroundColor White
Write-Host "  Successfully Deleted: $($successCount + 1)" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor Red
Write-Host "  Estimated Monthly Savings: USD $([math]::Round($totalCost, 2))" -ForegroundColor Yellow
Write-Host ""
Write-Host "Detailed log saved to: $logFile" -ForegroundColor Cyan
Write-Host ""
Write-Log "Deletion script completed. Success: $($successCount + 1), Failed: $failCount" "INFO"