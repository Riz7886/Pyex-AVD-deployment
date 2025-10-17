#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$PrioritySubscriptionIds = @(
        "7EDFB9F6-940E-47CD-AF4B-04D0B6E6020F",
        "977e4f83-3649-428b-9416-cf9adfe24cec"
    ),
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Reports"
)

$ErrorActionPreference = "Continue"

function Get-AzureData {
    param(
        [string]$Command,
        [switch]$SuppressErrors
    )
    try {
        if ($SuppressErrors) {
            $output = Invoke-Expression "$Command 2>`$null"
        } else {
            $output = Invoke-Expression $Command
        }
        
        if ($LASTEXITCODE -eq 0 -and $output) {
            $data = $output | ConvertFrom-Json
            return $data
        }
        return @()
    } catch {
        if (-not $SuppressErrors) {
            Write-Host "    Warning: $($_.Exception.Message)" -ForegroundColor Gray
        }
        return @()
    }
}

function Get-EstimatedMonthlyCost {
    param(
        [string]$ResourceType,
        [string]$SKU,
        [string]$Size
    )
    
    $cost = 0
    
    switch -Wildcard ($ResourceType) {
        "VM" {
            switch -Wildcard ($SKU) {
                "*D4*" { $cost = 150 }
                "*D2*" { $cost = 75 }
                "*B4*" { $cost = 130 }
                "*B2*" { $cost = 50 }
                "*E*" { $cost = 200 }
                "*F*" { $cost = 100 }
                "*Standard*" { $cost = 80 }
                default { $cost = 60 }
            }
        }
        "Disk" {
            $sizeGB = 128
            if ($Size -match "(\d+)\s*GB") {
                $sizeGB = [int]$Matches[1]
            }
            if ($SKU -match "Premium") { 
                $cost = [math]::Max([math]::Round(($sizeGB * 0.15), 2), 15)
            }
            elseif ($SKU -match "StandardSSD") { 
                $cost = [math]::Max([math]::Round(($sizeGB * 0.08), 2), 8)
            }
            else {
                $cost = [math]::Max([math]::Round(($sizeGB * 0.05), 2), 5)
            }
        }
        "PublicIP" { $cost = 4 }
        "NIC" { $cost = 2 }
        "LoadBalancer" { $cost = 25 }
        "Storage" {
            if ($SKU -match "Premium") { $cost = 15 }
            elseif ($SKU -match "GRS") { $cost = 8 }
            else { $cost = 5 }
        }
        "AppServicePlan" {
            if ($SKU -match "Premium") { $cost = 150 }
            elseif ($SKU -match "Standard") { $cost = 75 }
            else { $cost = 55 }
        }
        "SQL" { $cost = 100 }
        "Resource Group" { $cost = 0 }
        default { $cost = 15 }
    }
    
    return $cost
}

function Test-SubscriptionAccess {
    param([string]$SubscriptionId)
    
    $testCommands = @(
        "az vm list --subscription $SubscriptionId --query '[0]' --output json"
        "az disk list --subscription $SubscriptionId --query '[0]' --output json"
        "az network public-ip list --subscription $SubscriptionId --query '[0]' --output json"
    )
    
    foreach ($cmd in $testCommands) {
        $result = Invoke-Expression "$cmd 2>`$null"
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    
    return $false
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE IDLE RESOURCES SCANNER - SMART PERMISSION DETECTION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Checking Azure CLI Authentication..." -ForegroundColor Yellow
try {
    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or !$currentAccount) {
        Write-Host "Not logged in. Starting Azure login..." -ForegroundColor Yellow
        az login --output none
        $currentAccount = az account show --output json | ConvertFrom-Json
    }
    Write-Host "  Logged in as: $($currentAccount.user.name)" -ForegroundColor Green
    Write-Host "  Current Tenant: $($currentAccount.tenantId)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Azure CLI authentication failed" -ForegroundColor Red
    Write-Host "Please install Azure CLI: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Step 2: Discovering ALL Subscriptions..." -ForegroundColor Yellow
$allSubscriptions = Get-AzureData -Command "az account list --all --output json"

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found" -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($allSubscriptions.Count) subscription(s)" -ForegroundColor Green
Write-Host ""

$enabledSubs = $allSubscriptions | Where-Object { $_.state -eq "Enabled" }
Write-Host "Subscriptions Available:" -ForegroundColor Cyan
foreach ($sub in $enabledSubs) {
    Write-Host "  - $($sub.name)" -ForegroundColor White -NoNewline
    Write-Host " [$($sub.state)]" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 3: Testing Permissions on Each Subscription..." -ForegroundColor Yellow

$accessibleSubscriptions = @()
$blockedSubscriptions = @()

foreach ($sub in $enabledSubs) {
    Write-Host "  Testing: $($sub.name)..." -ForegroundColor Gray -NoNewline
    
    az account set --subscription $sub.id 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host " BLOCKED (Cannot switch context)" -ForegroundColor Red
        $blockedSubscriptions += $sub
        continue
    }
    
    $hasAccess = Test-SubscriptionAccess -SubscriptionId $sub.id
    
    if ($hasAccess) {
        Write-Host " ACCESSIBLE" -ForegroundColor Green
        $accessibleSubscriptions += $sub
    } else {
        Write-Host " NO READ PERMISSION" -ForegroundColor Red
        $blockedSubscriptions += $sub
    }
}

Write-Host ""
Write-Host "Permission Summary:" -ForegroundColor Cyan
Write-Host "  Accessible Subscriptions: $($accessibleSubscriptions.Count)" -ForegroundColor Green
Write-Host "  Blocked Subscriptions: $($blockedSubscriptions.Count)" -ForegroundColor Red

if ($blockedSubscriptions.Count -gt 0) {
    Write-Host ""
    Write-Host "Subscriptions You CANNOT Access:" -ForegroundColor Red
    foreach ($blocked in $blockedSubscriptions) {
        Write-Host "  - $($blocked.name)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "SOLUTION: Ask your Azure admin to grant you 'Reader' role on these subscriptions:" -ForegroundColor Yellow
    Write-Host "  Command for admin: az role assignment create --assignee $($currentAccount.user.name) --role Reader --scope /subscriptions/<SUBSCRIPTION_ID>" -ForegroundColor White
}

if ($accessibleSubscriptions.Count -eq 0) {
    Write-Host ""
    Write-Host "ERROR: You have no read permissions on any subscription!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Required Azure Roles (minimum):" -ForegroundColor Yellow
    Write-Host "  - Reader (subscription level)" -ForegroundColor White
    Write-Host ""
    Write-Host "Your current roles:" -ForegroundColor Yellow
    az role assignment list --assignee $currentAccount.user.name --all --output table
    exit 1
}

Write-Host ""
Write-Host "Step 4: Scanning Accessible Subscriptions..." -ForegroundColor Yellow

$prioritySubscriptions = @()
$otherSubscriptions = @()

foreach ($sub in $accessibleSubscriptions) {
    if ($PrioritySubscriptionIds -contains $sub.id) {
        $prioritySubscriptions += $sub
        Write-Host "  Priority Subscription Found: $($sub.name)" -ForegroundColor Cyan
    } else {
        $otherSubscriptions += $sub
    }
}

if ($prioritySubscriptions.Count -gt 0) {
    Write-Host "  Scanning $($prioritySubscriptions.Count) priority subscription(s) first" -ForegroundColor Yellow
    $subscriptionsToScan = $prioritySubscriptions + $otherSubscriptions
} else {
    Write-Host "  No priority subscriptions found. Scanning all available." -ForegroundColor Yellow
    $subscriptionsToScan = $accessibleSubscriptions
}

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$allIdleResources = @()
$summary = @{
    ScanStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    CurrentUser = $currentAccount.user.name
    TotalSubscriptions = $allSubscriptions.Count
    AccessibleSubscriptions = $accessibleSubscriptions.Count
    BlockedSubscriptions = $blockedSubscriptions.Count
    TotalSubscriptionsScanned = 0
    TotalResourcesScanned = 0
    TotalIdleResources = 0
    TotalMonthlyCost = 0
    TotalAnnualCost = 0
    SubscriptionDetails = @()
    BlockedSubscriptionList = @($blockedSubscriptions | ForEach-Object { $_.name })
}

$totalSubCount = $subscriptionsToScan.Count
$currentSubNum = 0

foreach ($subscription in $subscriptionsToScan) {
    $currentSubNum++
    
    try {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  [$currentSubNum/$totalSubCount] SCANNING: $($subscription.name)" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        
        az account set --subscription $subscription.id 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Cannot set subscription context" -ForegroundColor Red
            continue
        }
        
        $subIdleResources = @()
        $subTotalCost = 0
        $subResourceCount = 0
        
        Write-Host "  [1/7] Checking Virtual Machines..." -ForegroundColor Yellow
        $vms = Get-AzureData -Command "az vm list -d --subscription $($subscription.id) --output json" -SuppressErrors
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
                    Reason = "VM stopped or deallocated"
                    Recommendation = "Delete or restart"
                    Tags = if ($vm.tags) { ($vm.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                }
            }
        }
        Write-Host "    Result: $($vms.Count) total | $vmIdleCount idle" -ForegroundColor $(if($vmIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [2/7] Checking Unattached Disks..." -ForegroundColor Yellow
        $disks = Get-AzureData -Command "az disk list --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $disks.Count
        $diskIdleCount = 0
        
        foreach ($disk in $disks) {
            if ([string]::IsNullOrEmpty($disk.managedBy)) {
                $diskIdleCount++
                $diskSizeGB = $disk.diskSizeGb
                $diskTier = $disk.sku.name
                $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "Disk" -SKU $diskTier -Size "$diskSizeGB GB"
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
                    Reason = "Not attached to any VM"
                    Recommendation = "Delete if not needed"
                    Tags = if ($disk.tags) { ($disk.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                }
            }
        }
        Write-Host "    Result: $($disks.Count) total | $diskIdleCount unattached" -ForegroundColor $(if($diskIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [3/7] Checking Public IP Addresses..." -ForegroundColor Yellow
        $publicIPs = Get-AzureData -Command "az network public-ip list --subscription $($subscription.id) --output json" -SuppressErrors
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
                    Reason = "Not assigned to any resource"
                    Recommendation = "Delete if not needed"
                    Tags = if ($pip.tags) { ($pip.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
                }
            }
        }
        Write-Host "    Result: $($publicIPs.Count) total | $ipIdleCount unassigned" -ForegroundColor $(if($ipIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [4/7] Checking Network Interfaces..." -ForegroundColor Yellow
        $nics = Get-AzureData -Command "az network nic list --subscription $($subscription.id) --output json" -SuppressErrors
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
                    Reason = "Not attached to any VM"
                    Recommendation = "Delete if VM removed"
                    Tags = if ($nic.tags) { ($nic.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " }
                }
            }
        }
        Write-Host "    Result: $($nics.Count) total | $nicIdleCount unattached" -ForegroundColor $(if($nicIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [5/7] Checking Storage Accounts..." -ForegroundColor Yellow
        $storageAccounts = Get-AzureData -Command "az storage account list --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $storageAccounts.Count
        $storageIdleCount = 0
        
        foreach ($storage in $storageAccounts) {
            $containers = Get-AzureData -Command "az storage container list --account-name $($storage.name) --auth-mode login --output json" -SuppressErrors
            
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
                    Status = "Empty"
                    Size = "$($storage.sku.name)"
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Reason = "No containers"
                    Recommendation = "Delete if not needed"
                    Tags = if ($storage.tags) { ($storage.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " }
                }
            }
        }
        Write-Host "    Result: $($storageAccounts.Count) total | $storageIdleCount empty" -ForegroundColor $(if($storageIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [6/7] Checking Load Balancers..." -ForegroundColor Yellow
        $loadBalancers = Get-AzureData -Command "az network lb list --subscription $($subscription.id) --output json" -SuppressErrors
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
                    Status = "No Backend"
                    Size = "$($lb.sku.name) SKU"
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Reason = "No backend resources"
                    Recommendation = "Delete if not needed"
                    Tags = if ($lb.tags) { ($lb.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " }
                }
            }
        }
        Write-Host "    Result: $($loadBalancers.Count) total | $lbIdleCount idle" -ForegroundColor $(if($lbIdleCount -gt 0){"Yellow"}else{"Green"})
        
        Write-Host "  [7/7] Checking Resource Groups..." -ForegroundColor Yellow
        $resourceGroups = Get-AzureData -Command "az group list --subscription $($subscription.id) --output json" -SuppressErrors
        $emptyRGCount = 0
        
        foreach ($rg in $resourceGroups) {
            $resources = Get-AzureData -Command "az resource list --resource-group $($rg.name) --subscription $($subscription.id) --output json" -SuppressErrors
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
                    Recommendation = "Delete empty group"
                    Tags = if ($rg.tags) { ($rg.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " }
                }
            }
        }
        Write-Host "    Result: $($resourceGroups.Count) total | $emptyRGCount empty" -ForegroundColor $(if($emptyRGCount -gt 0){"Yellow"}else{"Green"})
        
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
        
        Write-Host ""
        Write-Host "  SUBSCRIPTION SUMMARY: $($subIdleResources.Count) idle resources | Potential Savings: `$$([math]::Round($subTotalCost, 2))/month" -ForegroundColor $(if($subIdleResources.Count -gt 0){"Yellow"}else{"Green"})
        
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$summary.ScanEndTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ADD THESE 2 LINES FOR PROPER DOLLAR FORMATTING
$monthlySavings = [math]::Round($summary.TotalMonthlyCost, 2)
$annualSavings = [math]::Round($summary.TotalAnnualCost, 2)

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  FINAL REPORT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scan Summary:" -ForegroundColor Yellow
Write-Host "  User: $($summary.CurrentUser)" -ForegroundColor White
Write-Host "  Duration: $($summary.ScanStartTime) to $($summary.ScanEndTime)" -ForegroundColor White
Write-Host "  Total Subscriptions: $($summary.TotalSubscriptions)" -ForegroundColor White
Write-Host "  Accessible: $($summary.AccessibleSubscriptions)" -ForegroundColor Green
Write-Host "  Blocked: $($summary.BlockedSubscriptions)" -ForegroundColor Red
Write-Host "  Scanned: $($summary.TotalSubscriptionsScanned)" -ForegroundColor Green
Write-Host ""
Write-Host "Resource Summary:" -ForegroundColor Yellow
Write-Host "  Total Resources Scanned: $($summary.TotalResourcesScanned)" -ForegroundColor White
Write-Host "  Total Idle Resources: $($summary.TotalIdleResources)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Cost Summary:" -ForegroundColor Yellow
Write-Host "  Monthly Savings: $" -NoNewline -ForegroundColor White
Write-Host "$monthlySavings" -ForegroundColor Green
Write-Host "  Annual Savings: $" -NoNewline -ForegroundColor White  
Write-Host "$annualSavings" -ForegroundColor Green
Write-Host ""

if ($allIdleResources.Count -gt 0) {
    $detailedReportPath = Join-Path $OutputPath "IdleResources-Detailed-$timestamp.csv"
    
    $csvData = $allIdleResources | Select-Object SubscriptionName, SubscriptionId, ResourceType, ResourceName, ResourceGroup, Location, Status, Size, 
        @{Name="EstimatedMonthlyCost";Expression={"`$$($_.EstimatedMonthlyCost)"}}, 
        @{Name="EstimatedAnnualCost";Expression={"`$$($_.EstimatedAnnualCost)"}}, 
        Reason, Recommendation, Tags
    
    $csvData | Export-Csv -Path $detailedReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Detailed Report: $detailedReportPath" -ForegroundColor Green
    
    $summaryReportPath = Join-Path $OutputPath "IdleResources-Summary-$timestamp.json"
    $summary | ConvertTo-Json -Depth 10 | Out-File $summaryReportPath
    Write-Host "Summary Report: $summaryReportPath" -ForegroundColor Green
    
    $htmlReportPath = Join-Path $OutputPath "IdleResources-Report-$timestamp.html"
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Idle Resources Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background-color: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .summary-item { margin: 10px 0; }
        .summary-label { font-weight: bold; display: inline-block; width: 250px; }
        .summary-value { color: #0078d4; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .cost { color: #d13438; font-weight: bold; }
        .warning { color: #ff8c00; }
        .success { color: #107c10; }
        .blocked { background-color: #fff4ce; padding: 10px; border-left: 4px solid #ff8c00; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>Azure Idle Resources Report</h1>
    <p>Generated: $($summary.ScanStartTime)</p>
    
    <div class="summary">
        <h2>Scan Summary</h2>
        <div class="summary-item"><span class="summary-label">User:</span> <span class="summary-value">$($summary.CurrentUser)</span></div>
        <div class="summary-item"><span class="summary-label">Scan Duration:</span> $($summary.ScanStartTime) to $($summary.ScanEndTime)</div>
        <div class="summary-item"><span class="summary-label">Total Subscriptions:</span> $($summary.TotalSubscriptions)</div>
        <div class="summary-item"><span class="summary-label">Accessible Subscriptions:</span> <span class="success">$($summary.AccessibleSubscriptions)</span></div>
        <div class="summary-item"><span class="summary-label">Blocked Subscriptions:</span> <span class="warning">$($summary.BlockedSubscriptions)</span></div>
        <div class="summary-item"><span class="summary-label">Subscriptions Scanned:</span> <span class="success">$($summary.TotalSubscriptionsScanned)</span></div>
    </div>
    
    <div class="summary">
        <h2>Resource Summary</h2>
        <div class="summary-item"><span class="summary-label">Total Resources Scanned:</span> $($summary.TotalResourcesScanned)</div>
        <div class="summary-item"><span class="summary-label">Total Idle Resources Found:</span> <span class="warning">$($summary.TotalIdleResources)</span></div>
    </div>
    
    <div class="summary">
        <h2>Cost Summary</h2>
        <div class="summary-item"><span class="summary-label">Estimated Monthly Savings:</span> <span class="cost">`$monthlySavings</span></div>
        <div class="summary-item"><span class="summary-label">Estimated Annual Savings:</span> <span class="cost">`$annualSavings</span></div>
    </div>
"@
