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
    [string]$OutputPath = ".\Reports",
    
    [Parameter(Mandatory=$false)]
    [switch]$ScanAllTenants
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
        "az vm list --subscription $SubscriptionId --query '[0]' --output json",
        "az disk list --subscription $SubscriptionId --query '[0]' --output json",
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
Write-Host "  AZURE IDLE RESOURCES SCANNER - MULTI-TENANT SUPPORT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Checking Azure CLI Authentication..." -ForegroundColor Yellow

# Force fresh login to see ALL tenants
if ($ScanAllTenants) {
    Write-Host "  Multi-Tenant Mode: Enabled" -ForegroundColor Cyan
    Write-Host "  Logging out to get fresh tenant list..." -ForegroundColor Yellow
    az logout 2>$null | Out-Null
    Write-Host "  Logout complete" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Opening browser for login - Please authenticate..." -ForegroundColor Cyan
    Write-Host "  WAITING FOR YOU TO LOGIN IN BROWSER..." -ForegroundColor Yellow
    az login --output table
    Write-Host ""
    Write-Host "  Login complete!" -ForegroundColor Green
}

try {
    Write-Host "  Getting current account info..." -ForegroundColor Yellow
    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or !$currentAccount) {
        Write-Host "  Not logged in. Starting Azure login..." -ForegroundColor Yellow
        az login --output table
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
Write-Host "Step 2: Discovering ALL Tenants and Subscriptions..." -ForegroundColor Yellow

$allTenants = @()
if ($ScanAllTenants) {
    Write-Host "  Multi-Tenant Mode: Enabled" -ForegroundColor Cyan
    
    # First, get current account info
    $currentLogin = az account show --output json 2>$null | ConvertFrom-Json
    
    # Get list of all tenants
    $tenantList = az account tenant list --output json 2>$null | ConvertFrom-Json
    
    if ($tenantList -and $tenantList.Count -gt 0) {
        Write-Host "  Found $($tenantList.Count) tenant(s) you have access to" -ForegroundColor Green
        foreach ($tenant in $tenantList) {
            $displayName = if ($tenant.displayName) { $tenant.displayName } else { if ($tenant.defaultDomain) { $tenant.defaultDomain } else { "Tenant" } }
            Write-Host "    - $displayName [$($tenant.tenantId)]" -ForegroundColor White
            $allTenants += @{
                tenantId = $tenant.tenantId
                displayName = $displayName
                defaultDomain = $tenant.defaultDomain
            }
        }
    } else {
        Write-Host "  Only current tenant accessible" -ForegroundColor Yellow
        $allTenants += @{
            tenantId = $currentLogin.tenantId
            displayName = "Current Tenant"
            defaultDomain = $currentLogin.user.name.Split('@')[1]
        }
    }
} else {
    Write-Host "  Single-Tenant Mode: Scanning current tenant only" -ForegroundColor Yellow
    Write-Host "  TIP: Use -ScanAllTenants switch to scan all accessible tenants" -ForegroundColor Gray
    $currentLogin = az account show --output json 2>$null | ConvertFrom-Json
    $allTenants += @{
        tenantId = $currentLogin.tenantId
        displayName = "Current Tenant"
        defaultDomain = $currentLogin.user.name.Split('@')[1]
    }
}

$allSubscriptions = @()
$tenantCount = 0

foreach ($tenant in $allTenants) {
    $tenantCount++
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  TENANT [$tenantCount/$($allTenants.Count)]: $($tenant.displayName)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Tenant ID: $($tenant.tenantId)" -ForegroundColor White
    if ($tenant.defaultDomain) {
        Write-Host "  Domain: $($tenant.defaultDomain)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "  Logging into this tenant..." -ForegroundColor Yellow
    
    # Login to specific tenant
    $loginResult = az login --tenant $tenant.tenantId --output none 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Successfully logged in!" -ForegroundColor Green
        
        # Get all subscriptions in this tenant
        Write-Host "  Fetching subscriptions..." -ForegroundColor Yellow
        $tenantSubs = az account list --all --output json 2>$null | ConvertFrom-Json
        
        if ($tenantSubs -and $tenantSubs.Count -gt 0) {
            Write-Host "  Found $($tenantSubs.Count) subscription(s):" -ForegroundColor Green
            
            foreach ($sub in $tenantSubs) {
                Write-Host "    - $($sub.name) [$($sub.state)]" -ForegroundColor Gray
                
                # Add tenant tracking info
                $sub | Add-Member -NotePropertyName "TenantDisplayName" -NotePropertyValue $tenant.displayName -Force
                $sub | Add-Member -NotePropertyName "TenantDomain" -NotePropertyValue $tenant.defaultDomain -Force
                
                $allSubscriptions += $sub
            }
        } else {
            Write-Host "  No subscriptions found in this tenant" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ERROR: Could not connect to tenant" -ForegroundColor Red
        Write-Host "  You may not have permissions in this tenant" -ForegroundColor Yellow
    }
}

if ($allSubscriptions.Count -eq 0) {
    Write-Host ""
    Write-Host "ERROR: No subscriptions found in any tenant" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  DISCOVERY COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Total Tenants Scanned: $($allTenants.Count)" -ForegroundColor White
Write-Host "  Total Subscriptions Found: $($allSubscriptions.Count)" -ForegroundColor White
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
                    Tags = if ($nic.tags) { ($nic.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
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
                    Tags = if ($storage.tags) { ($storage.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
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
                    Tags = if ($lb.tags) { ($lb.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
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
                    Tags = if ($rg.tags) { ($rg.tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "; " } else { "" }
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

$monthlySavings = [math]::Round($summary.TotalMonthlyCost, 2)
$annualSavings = [math]::Round($summary.TotalAnnualCost, 2)

# DEBUG OUTPUT TO VERIFY VARIABLES
Write-Host ""
Write-Host "DEBUG - CHECKING VARIABLES:" -ForegroundColor Magenta
Write-Host "  monthlySavings variable = '$monthlySavings'" -ForegroundColor Magenta
Write-Host "  annualSavings variable = '$annualSavings'" -ForegroundColor Magenta
Write-Host "  TotalMonthlyCost = '$($summary.TotalMonthlyCost)'" -ForegroundColor Magenta
Write-Host "  TotalAnnualCost = '$($summary.TotalAnnualCost)'" -ForegroundColor Magenta
Write-Host ""

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
        @{Name="EstimatedMonthlyCost";Expression={"`$($_.EstimatedMonthlyCost)"}}, 
        @{Name="EstimatedAnnualCost";Expression={"`$($_.EstimatedAnnualCost)"}}, 
        Reason, Recommendation, Tags
    
    $csvData | Export-Csv -Path $detailedReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Detailed Report: $detailedReportPath" -ForegroundColor Green
    
    $summaryReportPath = Join-Path $OutputPath "IdleResources-Summary-$timestamp.json"
    $summary | ConvertTo-Json -Depth 10 | Out-File $summaryReportPath
    Write-Host "Summary Report: $summaryReportPath" -ForegroundColor Green
    
    $htmlReportPath = Join-Path $OutputPath "IdleResources-Report-$timestamp.html"
    
    # DEBUG: Show what we're putting in HTML
    Write-Host ""
    Write-Host "DEBUG - HTML GENERATION:" -ForegroundColor Magenta
    Write-Host "  Building HTML with monthlySavings = '$monthlySavings'" -ForegroundColor Magenta
    Write-Host "  Building HTML with annualSavings = '$annualSavings'" -ForegroundColor Magenta
    
    # BUILD HTML - COMPLETELY DIFFERENT METHOD - WRITE DOLLAR SIGNS AS PLAIN TEXT
    $monthlyWithDollar = '
    
    $html = New-Object System.Text.StringBuilder
    [void]$html.Append("<!DOCTYPE html><html><head><title>Azure Idle Resources Report - $timestamp</title><style>body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}h1{color:#0078d4}h2{color:#106ebe;margin-top:30px}.summary{background-color:white;padding:20px;border-radius:5px;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-bottom:20px}.summary-item{margin:10px 0}.summary-label{font-weight:bold;display:inline-block;width:250px}.summary-value{color:#0078d4;font-weight:bold}table{border-collapse:collapse;width:100%;background-color:white;box-shadow:0 2px 4px rgba(0,0,0,0.1)}th{background-color:#0078d4;color:white;padding:12px;text-align:left}td{padding:10px;border-bottom:1px solid #ddd}tr:hover{background-color:#f5f5f5}.cost{color:#d13438;font-weight:bold}.warning{color:#ff8c00}.success{color:#107c10}.blocked{background-color:#fff4ce;padding:10px;border-left:4px solid #ff8c00;margin:10px 0}</style></head><body><h1>Azure Idle Resources Report</h1><p>Generated: $($summary.ScanStartTime)</p>")
    
    [void]$html.Append("<div class='summary'><h2>Scan Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>User:</span> <span class='summary-value'>$($summary.CurrentUser)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Scan Duration:</span> $($summary.ScanStartTime) to $($summary.ScanEndTime)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Subscriptions:</span> $($summary.TotalSubscriptions)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Accessible Subscriptions:</span> <span class='success'>$($summary.AccessibleSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Blocked Subscriptions:</span> <span class='warning'>$($summary.BlockedSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Subscriptions Scanned:</span> <span class='success'>$($summary.TotalSubscriptionsScanned)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Resource Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Resources Scanned:</span> $($summary.TotalResourcesScanned)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Idle Resources Found:</span> <span class='warning'>$($summary.TotalIdleResources)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Cost Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Monthly Savings:</span> <span class='cost'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Annual Savings:</span> <span class='cost'>`$annualSavings</span></div></div>")
    
    if ($summary.BlockedSubscriptions -gt 0) {
        [void]$html.Append("<div class='blocked'><h2>Blocked Subscriptions (No Access)</h2><p>You do not have read permissions on the following subscriptions:</p><ul>")
        foreach ($blocked in $summary.BlockedSubscriptionList) {
            [void]$html.Append("<li>$blocked</li>")
        }
        [void]$html.Append("</ul><p><strong>Solution:</strong> Ask your Azure admin to grant Reader role on these subscriptions.</p></div>")
    }
    
    [void]$html.Append("<h2>Idle Resources Details</h2><table><tr><th>Subscription</th><th>Resource Type</th><th>Resource Name</th><th>Resource Group</th><th>Location</th><th>Status</th><th>Size</th><th>Monthly Cost</th><th>Annual Cost</th><th>Recommendation</th></tr>")
    
    foreach ($resource in ($allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        $monthlyFormatted = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualFormatted = [math]::Round($resource.EstimatedAnnualCost, 2)
        [void]$html.Append("<tr><td>$($resource.SubscriptionName)</td><td>$($resource.ResourceType)</td><td>$($resource.ResourceName)</td><td>$($resource.ResourceGroup)</td><td>$($resource.Location)</td><td>$($resource.Status)</td><td>$($resource.Size)</td><td class='cost'>`$monthlyFormatted</td><td class='cost'>`$annualFormatted</td><td>$($resource.Recommendation)</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Resource Type</h2><table><tr><th>Resource Type</th><th>Count</th><th>Total Monthly Cost</th><th>Total Annual Cost</th></tr>")
    
    $resourceTypeBreakdown = $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="MonthlyTotal";Expression={($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum}}, @{Name="AnnualTotal";Expression={($_.Group | Measure-Object -Property EstimatedAnnualCost -Sum).Sum}} | Sort-Object -Property MonthlyTotal -Descending
    
    foreach ($type in $resourceTypeBreakdown) {
        $monthlyRounded = [math]::Round($type.MonthlyTotal, 2)
        $annualRounded = [math]::Round($type.AnnualTotal, 2)
        [void]$html.Append("<tr><td>$($type.Name)</td><td>$($type.Count)</td><td class='cost'>`$monthlyRounded</td><td class='cost'>`$annualRounded</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Subscription</h2><table><tr><th>Subscription Name</th><th>Resources Scanned</th><th>Idle Resources</th><th>Monthly Cost</th><th>Annual Cost</th></tr>")
    
    foreach ($sub in ($summary.SubscriptionDetails | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        [void]$html.Append("<tr><td>$($sub.SubscriptionName)</td><td>$($sub.ResourcesScanned)</td><td class='warning'>$($sub.IdleResourcesFound)</td><td class='cost'>`$($sub.EstimatedMonthlyCost)</td><td class='cost'>`$($sub.EstimatedAnnualCost)</td></tr>")
    }
    
    [void]$html.Append("</table><div class='summary' style='margin-top:30px;background-color:#e8f5e9'><h2 style='color:#2e7d32'>TOTAL SAVINGS SUMMARY</h2>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Total Idle Resources Found:</span> <span style='color:#d13438;font-size:24px;font-weight:bold'>$($summary.TotalIdleResources)</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Monthly Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Annual Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$annualSavings</span></div>")
    [void]$html.Append("<div style='margin-top:20px;padding:15px;background-color:#fff3cd;border-radius:5px'><p style='margin:0;font-size:16px;color:#856404'><strong>Recommendation:</strong> Review these idle resources and delete unused ones to achieve estimated savings of <strong style='color:#2e7d32'>`$monthlySavings per month</strong> or <strong style='color:#2e7d32'>`$annualSavings per year</strong>.</p></div></div></body></html>")
    
    $html.ToString() | Out-File -FilePath $htmlReportPath -Encoding UTF8
    Write-Host "HTML Report: $htmlReportPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Opening HTML report in browser..." -ForegroundColor Cyan
    Start-Process $htmlReportPath
    Write-Host "Browser opened with report" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 10 Costliest Idle Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 10 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, @{Name="Monthly";Expression={"$" + $_.EstimatedMonthlyCost}}, Recommendation -AutoSize
    
    Write-Host ""
    Write-Host "By Resource Type:" -ForegroundColor Cyan
    $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="Monthly";Expression={"$" + [math]::Round(($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2)}} | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    
} else {
    Write-Host "No idle resources found!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
try {
    if (!(Test-Path ".git")) {
        git init 2>$null
        git remote add origin https://github.com/Riz7886/Pyex-AVD-deployment.git 2>$null
    }
    
    git add $OutputPath 2>$null
    git commit -m "Idle Resources Report $timestamp - $($summary.TotalIdleResources) idle resources" 2>$null
    git push origin main 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub push successful!" -ForegroundColor Green
    } else {
        Write-Host "GitHub push failed (not critical)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "GitHub push skipped" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "" + $monthlyDisplay
    $annualWithDollar = '
    
    $html = New-Object System.Text.StringBuilder
    [void]$html.Append("<!DOCTYPE html><html><head><title>Azure Idle Resources Report - $timestamp</title><style>body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}h1{color:#0078d4}h2{color:#106ebe;margin-top:30px}.summary{background-color:white;padding:20px;border-radius:5px;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-bottom:20px}.summary-item{margin:10px 0}.summary-label{font-weight:bold;display:inline-block;width:250px}.summary-value{color:#0078d4;font-weight:bold}table{border-collapse:collapse;width:100%;background-color:white;box-shadow:0 2px 4px rgba(0,0,0,0.1)}th{background-color:#0078d4;color:white;padding:12px;text-align:left}td{padding:10px;border-bottom:1px solid #ddd}tr:hover{background-color:#f5f5f5}.cost{color:#d13438;font-weight:bold}.warning{color:#ff8c00}.success{color:#107c10}.blocked{background-color:#fff4ce;padding:10px;border-left:4px solid #ff8c00;margin:10px 0}</style></head><body><h1>Azure Idle Resources Report</h1><p>Generated: $($summary.ScanStartTime)</p>")
    
    [void]$html.Append("<div class='summary'><h2>Scan Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>User:</span> <span class='summary-value'>$($summary.CurrentUser)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Scan Duration:</span> $($summary.ScanStartTime) to $($summary.ScanEndTime)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Subscriptions:</span> $($summary.TotalSubscriptions)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Accessible Subscriptions:</span> <span class='success'>$($summary.AccessibleSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Blocked Subscriptions:</span> <span class='warning'>$($summary.BlockedSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Subscriptions Scanned:</span> <span class='success'>$($summary.TotalSubscriptionsScanned)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Resource Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Resources Scanned:</span> $($summary.TotalResourcesScanned)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Idle Resources Found:</span> <span class='warning'>$($summary.TotalIdleResources)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Cost Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Monthly Savings:</span> <span class='cost'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Annual Savings:</span> <span class='cost'>`$annualSavings</span></div></div>")
    
    if ($summary.BlockedSubscriptions -gt 0) {
        [void]$html.Append("<div class='blocked'><h2>Blocked Subscriptions (No Access)</h2><p>You do not have read permissions on the following subscriptions:</p><ul>")
        foreach ($blocked in $summary.BlockedSubscriptionList) {
            [void]$html.Append("<li>$blocked</li>")
        }
        [void]$html.Append("</ul><p><strong>Solution:</strong> Ask your Azure admin to grant Reader role on these subscriptions.</p></div>")
    }
    
    [void]$html.Append("<h2>Idle Resources Details</h2><table><tr><th>Subscription</th><th>Resource Type</th><th>Resource Name</th><th>Resource Group</th><th>Location</th><th>Status</th><th>Size</th><th>Monthly Cost</th><th>Annual Cost</th><th>Recommendation</th></tr>")
    
    foreach ($resource in ($allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        $monthlyFormatted = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualFormatted = [math]::Round($resource.EstimatedAnnualCost, 2)
        [void]$html.Append("<tr><td>$($resource.SubscriptionName)</td><td>$($resource.ResourceType)</td><td>$($resource.ResourceName)</td><td>$($resource.ResourceGroup)</td><td>$($resource.Location)</td><td>$($resource.Status)</td><td>$($resource.Size)</td><td class='cost'>`$monthlyFormatted</td><td class='cost'>`$annualFormatted</td><td>$($resource.Recommendation)</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Resource Type</h2><table><tr><th>Resource Type</th><th>Count</th><th>Total Monthly Cost</th><th>Total Annual Cost</th></tr>")
    
    $resourceTypeBreakdown = $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="MonthlyTotal";Expression={($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum}}, @{Name="AnnualTotal";Expression={($_.Group | Measure-Object -Property EstimatedAnnualCost -Sum).Sum}} | Sort-Object -Property MonthlyTotal -Descending
    
    foreach ($type in $resourceTypeBreakdown) {
        $monthlyRounded = [math]::Round($type.MonthlyTotal, 2)
        $annualRounded = [math]::Round($type.AnnualTotal, 2)
        [void]$html.Append("<tr><td>$($type.Name)</td><td>$($type.Count)</td><td class='cost'>`$monthlyRounded</td><td class='cost'>`$annualRounded</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Subscription</h2><table><tr><th>Subscription Name</th><th>Resources Scanned</th><th>Idle Resources</th><th>Monthly Cost</th><th>Annual Cost</th></tr>")
    
    foreach ($sub in ($summary.SubscriptionDetails | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        [void]$html.Append("<tr><td>$($sub.SubscriptionName)</td><td>$($sub.ResourcesScanned)</td><td class='warning'>$($sub.IdleResourcesFound)</td><td class='cost'>`$($sub.EstimatedMonthlyCost)</td><td class='cost'>`$($sub.EstimatedAnnualCost)</td></tr>")
    }
    
    [void]$html.Append("</table><div class='summary' style='margin-top:30px;background-color:#e8f5e9'><h2 style='color:#2e7d32'>TOTAL SAVINGS SUMMARY</h2>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Total Idle Resources Found:</span> <span style='color:#d13438;font-size:24px;font-weight:bold'>$($summary.TotalIdleResources)</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Monthly Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Annual Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$annualSavings</span></div>")
    [void]$html.Append("<div style='margin-top:20px;padding:15px;background-color:#fff3cd;border-radius:5px'><p style='margin:0;font-size:16px;color:#856404'><strong>Recommendation:</strong> Review these idle resources and delete unused ones to achieve estimated savings of <strong style='color:#2e7d32'>`$monthlySavings per month</strong> or <strong style='color:#2e7d32'>`$annualSavings per year</strong>.</p></div></div></body></html>")
    
    $html.ToString() | Out-File -FilePath $htmlReportPath -Encoding UTF8
    Write-Host "HTML Report: $htmlReportPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Opening HTML report in browser..." -ForegroundColor Cyan
    Start-Process $htmlReportPath
    Write-Host "Browser opened with report" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 10 Costliest Idle Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 10 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, @{Name="Monthly";Expression={"$" + $_.EstimatedMonthlyCost}}, Recommendation -AutoSize
    
    Write-Host ""
    Write-Host "By Resource Type:" -ForegroundColor Cyan
    $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="Monthly";Expression={"$" + [math]::Round(($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2)}} | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    
} else {
    Write-Host "No idle resources found!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
try {
    if (!(Test-Path ".git")) {
        git init 2>$null
        git remote add origin https://github.com/Riz7886/Pyex-AVD-deployment.git 2>$null
    }
    
    git add $OutputPath 2>$null
    git commit -m "Idle Resources Report $timestamp - $($summary.TotalIdleResources) idle resources" 2>$null
    git push origin main 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub push successful!" -ForegroundColor Green
    } else {
        Write-Host "GitHub push failed (not critical)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "GitHub push skipped" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "" + $annualDisplay
    
    Write-Host "  monthlyWithDollar = '$monthlyWithDollar'" -ForegroundColor Magenta
    Write-Host "  annualWithDollar = '$annualWithDollar'" -ForegroundColor Magenta
    Write-Host ""
    
    $html = New-Object System.Text.StringBuilder
    [void]$html.Append("<!DOCTYPE html><html><head><title>Azure Idle Resources Report - $timestamp</title><style>body{font-family:Arial,sans-serif;margin:20px;background-color:#f5f5f5}h1{color:#0078d4}h2{color:#106ebe;margin-top:30px}.summary{background-color:white;padding:20px;border-radius:5px;box-shadow:0 2px 4px rgba(0,0,0,0.1);margin-bottom:20px}.summary-item{margin:10px 0}.summary-label{font-weight:bold;display:inline-block;width:250px}.summary-value{color:#0078d4;font-weight:bold}table{border-collapse:collapse;width:100%;background-color:white;box-shadow:0 2px 4px rgba(0,0,0,0.1)}th{background-color:#0078d4;color:white;padding:12px;text-align:left}td{padding:10px;border-bottom:1px solid #ddd}tr:hover{background-color:#f5f5f5}.cost{color:#d13438;font-weight:bold}.warning{color:#ff8c00}.success{color:#107c10}.blocked{background-color:#fff4ce;padding:10px;border-left:4px solid #ff8c00;margin:10px 0}</style></head><body><h1>Azure Idle Resources Report</h1><p>Generated: $($summary.ScanStartTime)</p>")
    
    [void]$html.Append("<div class='summary'><h2>Scan Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>User:</span> <span class='summary-value'>$($summary.CurrentUser)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Scan Duration:</span> $($summary.ScanStartTime) to $($summary.ScanEndTime)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Subscriptions:</span> $($summary.TotalSubscriptions)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Accessible Subscriptions:</span> <span class='success'>$($summary.AccessibleSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Blocked Subscriptions:</span> <span class='warning'>$($summary.BlockedSubscriptions)</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Subscriptions Scanned:</span> <span class='success'>$($summary.TotalSubscriptionsScanned)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Resource Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Resources Scanned:</span> $($summary.TotalResourcesScanned)</div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Total Idle Resources Found:</span> <span class='warning'>$($summary.TotalIdleResources)</span></div></div>")
    
    [void]$html.Append("<div class='summary'><h2>Cost Summary</h2>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Monthly Savings:</span> <span class='cost'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item'><span class='summary-label'>Estimated Annual Savings:</span> <span class='cost'>`$annualSavings</span></div></div>")
    
    if ($summary.BlockedSubscriptions -gt 0) {
        [void]$html.Append("<div class='blocked'><h2>Blocked Subscriptions (No Access)</h2><p>You do not have read permissions on the following subscriptions:</p><ul>")
        foreach ($blocked in $summary.BlockedSubscriptionList) {
            [void]$html.Append("<li>$blocked</li>")
        }
        [void]$html.Append("</ul><p><strong>Solution:</strong> Ask your Azure admin to grant Reader role on these subscriptions.</p></div>")
    }
    
    [void]$html.Append("<h2>Idle Resources Details</h2><table><tr><th>Subscription</th><th>Resource Type</th><th>Resource Name</th><th>Resource Group</th><th>Location</th><th>Status</th><th>Size</th><th>Monthly Cost</th><th>Annual Cost</th><th>Recommendation</th></tr>")
    
    foreach ($resource in ($allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        $monthlyFormatted = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualFormatted = [math]::Round($resource.EstimatedAnnualCost, 2)
        [void]$html.Append("<tr><td>$($resource.SubscriptionName)</td><td>$($resource.ResourceType)</td><td>$($resource.ResourceName)</td><td>$($resource.ResourceGroup)</td><td>$($resource.Location)</td><td>$($resource.Status)</td><td>$($resource.Size)</td><td class='cost'>`$monthlyFormatted</td><td class='cost'>`$annualFormatted</td><td>$($resource.Recommendation)</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Resource Type</h2><table><tr><th>Resource Type</th><th>Count</th><th>Total Monthly Cost</th><th>Total Annual Cost</th></tr>")
    
    $resourceTypeBreakdown = $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="MonthlyTotal";Expression={($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum}}, @{Name="AnnualTotal";Expression={($_.Group | Measure-Object -Property EstimatedAnnualCost -Sum).Sum}} | Sort-Object -Property MonthlyTotal -Descending
    
    foreach ($type in $resourceTypeBreakdown) {
        $monthlyRounded = [math]::Round($type.MonthlyTotal, 2)
        $annualRounded = [math]::Round($type.AnnualTotal, 2)
        [void]$html.Append("<tr><td>$($type.Name)</td><td>$($type.Count)</td><td class='cost'>`$monthlyRounded</td><td class='cost'>`$annualRounded</td></tr>")
    }
    
    [void]$html.Append("</table><h2>Breakdown by Subscription</h2><table><tr><th>Subscription Name</th><th>Resources Scanned</th><th>Idle Resources</th><th>Monthly Cost</th><th>Annual Cost</th></tr>")
    
    foreach ($sub in ($summary.SubscriptionDetails | Sort-Object -Property EstimatedMonthlyCost -Descending)) {
        [void]$html.Append("<tr><td>$($sub.SubscriptionName)</td><td>$($sub.ResourcesScanned)</td><td class='warning'>$($sub.IdleResourcesFound)</td><td class='cost'>`$($sub.EstimatedMonthlyCost)</td><td class='cost'>`$($sub.EstimatedAnnualCost)</td></tr>")
    }
    
    [void]$html.Append("</table><div class='summary' style='margin-top:30px;background-color:#e8f5e9'><h2 style='color:#2e7d32'>TOTAL SAVINGS SUMMARY</h2>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Total Idle Resources Found:</span> <span style='color:#d13438;font-size:24px;font-weight:bold'>$($summary.TotalIdleResources)</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Monthly Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$monthlySavings</span></div>")
    [void]$html.Append("<div class='summary-item' style='font-size:20px;margin:15px 0'><span class='summary-label'>Annual Cost Savings:</span> <span style='color:#2e7d32;font-size:28px;font-weight:bold'>`$annualSavings</span></div>")
    [void]$html.Append("<div style='margin-top:20px;padding:15px;background-color:#fff3cd;border-radius:5px'><p style='margin:0;font-size:16px;color:#856404'><strong>Recommendation:</strong> Review these idle resources and delete unused ones to achieve estimated savings of <strong style='color:#2e7d32'>`$monthlySavings per month</strong> or <strong style='color:#2e7d32'>`$annualSavings per year</strong>.</p></div></div></body></html>")
    
    $html.ToString() | Out-File -FilePath $htmlReportPath -Encoding UTF8
    Write-Host "HTML Report: $htmlReportPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Opening HTML report in browser..." -ForegroundColor Cyan
    Start-Process $htmlReportPath
    Write-Host "Browser opened with report" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Top 10 Costliest Idle Resources:" -ForegroundColor Cyan
    $allIdleResources | Sort-Object -Property EstimatedMonthlyCost -Descending | Select-Object -First 10 | Format-Table -Property SubscriptionName, ResourceType, ResourceName, @{Name="Monthly";Expression={"$" + $_.EstimatedMonthlyCost}}, Recommendation -AutoSize
    
    Write-Host ""
    Write-Host "By Resource Type:" -ForegroundColor Cyan
    $allIdleResources | Group-Object -Property ResourceType | Select-Object Name, Count, @{Name="Monthly";Expression={"$" + [math]::Round(($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum, 2)}} | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    
} else {
    Write-Host "No idle resources found!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
try {
    if (!(Test-Path ".git")) {
        git init 2>$null
        git remote add origin https://github.com/Riz7886/Pyex-AVD-deployment.git 2>$null
    }
    
    git add $OutputPath 2>$null
    git commit -m "Idle Resources Report $timestamp - $($summary.TotalIdleResources) idle resources" 2>$null
    git push origin main 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub push successful!" -ForegroundColor Green
    } else {
        Write-Host "GitHub push failed (not critical)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "GitHub push skipped" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
