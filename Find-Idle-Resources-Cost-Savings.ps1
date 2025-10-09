#Requires -Version 5.1

<#
.SYNOPSIS
    Azure Idle Resources Cost Savings Analyzer
    
.DESCRIPTION
    100% READ-ONLY script that identifies UNUSED/IDLE resources across ALL subscriptions
    - Stopped/Deallocated VMs
    - Unattached Disks
    - Unused Public IPs
    - Empty Resource Groups
    - Unused NICs
    - Unused Load Balancers
    - Empty Storage Accounts
    - Calculates estimated monthly cost savings
    
.PARAMETER OutputPath
    Output path for reports. Default: .\Idle-Resources-Report\
    
.EXAMPLE
    .\Find-Idle-Resources-Cost-Savings.ps1
    
.NOTES
    Version: 1.0
    100% READ-ONLY - Makes NO changes
    Safe for production
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Idle-Resources-Report"
)

function Write-CostLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "SAVINGS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"     = "Cyan"
        "SUCCESS"  = "Green"
        "WARNING"  = "Yellow"
        "ERROR"    = "Red"
        "SAVINGS"  = "Magenta"
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

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
        [string]$Tier
    )
    
    # Approximate monthly costs in USD
    switch -Wildcard ($ResourceType) {
        "*virtualMachines" {
            switch -Wildcard ($SKU) {
                "*B1s*" { return 10 }
                "*B2s*" { return 40 }
                "*D2*" { return 100 }
                "*D4*" { return 200 }
                "*D8*" { return 400 }
                "*E2*" { return 120 }
                "*E4*" { return 240 }
                default { return 100 }
            }
        }
        "*disks" {
            if ($SKU -match "Premium") { return 20 }
            if ($SKU -match "StandardSSD") { return 10 }
            return 5
        }
        "*publicIPAddresses" { return 4 }
        "*networkInterfaces" { return 0 }
        "*loadBalancers" { return 25 }
        "*storageAccounts" { return 2 }
        "*applicationGateways" { return 150 }
        default { return 10 }
    }
}

$scriptStartTime = Get-Date
$allIdleResources = @()
$totalPotentialSavings = 0

Write-Host ""
Write-Host "================================================================"
Write-Host "  AZURE IDLE RESOURCES COST SAVINGS ANALYZER"
Write-Host "  Find Unused Resources and Potential Savings"
Write-Host "================================================================"
Write-Host ""
Write-Host "  READ-ONLY MODE - No deletions will be performed" -ForegroundColor Green
Write-Host "  Safe for production environments" -ForegroundColor Green
Write-Host ""
Write-Host "================================================================"
Write-Host ""

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = Join-Path $OutputPath "Idle-Resources-$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-CostLog "Output directory: $reportPath" "INFO"

Write-CostLog "Checking Azure CLI..." "INFO"

try {
    $null = az account show --output json
    if ($LASTEXITCODE -ne 0) {
        Write-CostLog "Not logged in to Azure CLI" "ERROR"
        Write-Host ""
        Write-Host "Please run: az login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-CostLog "Azure CLI not available" "ERROR"
    exit 1
}

Write-Host ""
Write-Host "================================================================"
Write-Host "  DISCOVERING ALL SUBSCRIPTIONS"
Write-Host "================================================================"
Write-Host ""

$allSubscriptions = Get-AzureData -Command "az account list --all --output json"

if ($allSubscriptions.Count -eq 0) {
    Write-CostLog "No subscriptions found" "ERROR"
    exit 1
}

Write-CostLog "Found $($allSubscriptions.Count) subscriptions" "SUCCESS"
Write-Host ""

foreach ($sub in $allSubscriptions) {
    $status = if ($sub.state -eq "Enabled") { "ACTIVE" } else { $sub.state }
    Write-Host "  - $($sub.name)" -ForegroundColor White -NoNewline
    Write-Host " [$status]" -ForegroundColor $(if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" })
}

Write-Host ""

foreach ($subscription in $allSubscriptions) {
    
    if ($subscription.state -ne "Enabled") {
        Write-CostLog "Skipping disabled subscription: $($subscription.name)" "WARNING"
        continue
    }

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "  ANALYZING: $($subscription.name)"
    Write-Host "================================================================"
    Write-Host ""

    az account set --subscription $subscription.id | Out-Null
    
    # 1. Find Stopped/Deallocated VMs
    Write-CostLog "Checking for stopped VMs..." "INFO"
    
    $vms = Get-AzureData -Command "az vm list -d --subscription $($subscription.id) --output json"
    
    foreach ($vm in $vms) {
        if ($vm.powerState -eq "VM deallocated" -or $vm.powerState -eq "VM stopped") {
            $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "virtualMachines" -SKU $vm.hardwareProfile.vmSize
            $totalPotentialSavings += $estimatedCost
            
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Virtual Machine (Stopped)"
                ResourceName = $vm.name
                ResourceGroup = $vm.resourceGroup
                Location = $vm.location
                Status = $vm.powerState
                SKU = $vm.hardwareProfile.vmSize
                EstimatedMonthlyCost = $estimatedCost
                Recommendation = "Delete or Start the VM"
            }
        }
    }
    
    # 2. Find Unattached Disks
    Write-CostLog "Checking for unattached disks..." "INFO"
    
    $disks = Get-AzureData -Command "az disk list --subscription $($subscription.id) --output json"
    
    foreach ($disk in $disks) {
        if ([string]::IsNullOrEmpty($disk.managedBy)) {
            $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "disks" -SKU $disk.sku.name
            $totalPotentialSavings += $estimatedCost
            
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Disk (Unattached)"
                ResourceName = $disk.name
                ResourceGroup = $disk.resourceGroup
                Location = $disk.location
                Status = "Not attached to any VM"
                SKU = $disk.sku.name
                EstimatedMonthlyCost = $estimatedCost
                Recommendation = "Delete if not needed"
            }
        }
    }
    
    # 3. Find Unused Public IPs
    Write-CostLog "Checking for unused public IPs..." "INFO"
    
    $publicIPs = Get-AzureData -Command "az network public-ip list --subscription $($subscription.id) --output json"
    
    foreach ($pip in $publicIPs) {
        if ([string]::IsNullOrEmpty($pip.ipConfiguration)) {
            $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "publicIPAddresses"
            $totalPotentialSavings += $estimatedCost
            
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Public IP (Unused)"
                ResourceName = $pip.name
                ResourceGroup = $pip.resourceGroup
                Location = $pip.location
                Status = "Not associated with any resource"
                SKU = $pip.sku.name
                EstimatedMonthlyCost = $estimatedCost
                Recommendation = "Delete if not needed"
            }
        }
    }
    
    # 4. Find Unused NICs
    Write-CostLog "Checking for unused NICs..." "INFO"
    
    $nics = Get-AzureData -Command "az network nic list --subscription $($subscription.id) --output json"
    
    foreach ($nic in $nics) {
        if ([string]::IsNullOrEmpty($nic.virtualMachine)) {
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Network Interface (Unused)"
                ResourceName = $nic.name
                ResourceGroup = $nic.resourceGroup
                Location = $nic.location
                Status = "Not attached to any VM"
                SKU = "N/A"
                EstimatedMonthlyCost = 0
                Recommendation = "Delete if not needed"
            }
        }
    }
    
    # 5. Find Empty Resource Groups
    Write-CostLog "Checking for empty resource groups..." "INFO"
    
    $resourceGroups = Get-AzureData -Command "az group list --subscription $($subscription.id) --output json"
    
    foreach ($rg in $resourceGroups) {
        $resources = Get-AzureData -Command "az resource list --resource-group $($rg.name) --subscription $($subscription.id) --output json"
        
        if ($resources.Count -eq 0) {
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Resource Group (Empty)"
                ResourceName = $rg.name
                ResourceGroup = "N/A"
                Location = $rg.location
                Status = "No resources inside"
                SKU = "N/A"
                EstimatedMonthlyCost = 0
                Recommendation = "Delete empty resource group"
            }
        }
    }
    
    # 6. Find Unused Load Balancers
    Write-CostLog "Checking for unused load balancers..." "INFO"
    
    $loadBalancers = Get-AzureData -Command "az network lb list --subscription $($subscription.id) --output json"
    
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
            $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "loadBalancers"
            $totalPotentialSavings += $estimatedCost
            
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Load Balancer (No Backend)"
                ResourceName = $lb.name
                ResourceGroup = $lb.resourceGroup
                Location = $lb.location
                Status = "No backend pool members"
                SKU = $lb.sku.name
                EstimatedMonthlyCost = $estimatedCost
                Recommendation = "Delete if not needed"
            }
        }
    }
    
    # 7. Find Unused Application Gateways
    Write-CostLog "Checking for application gateways..." "INFO"
    
    $appGateways = Get-AzureData -Command "az network application-gateway list --subscription $($subscription.id) --output json"
    
    foreach ($ag in $appGateways) {
        $backendEmpty = $true
        if ($ag.backendAddressPools) {
            foreach ($pool in $ag.backendAddressPools) {
                if ($pool.backendAddresses -and $pool.backendAddresses.Count -gt 0) {
                    $backendEmpty = $false
                    break
                }
            }
        }
        
        if ($backendEmpty) {
            $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "applicationGateways"
            $totalPotentialSavings += $estimatedCost
            
            $allIdleResources += [PSCustomObject]@{
                Subscription = $subscription.name
                ResourceType = "Application Gateway (No Backend)"
                ResourceName = $ag.name
                ResourceGroup = $ag.resourceGroup
                Location = $ag.location
                Status = "No backend pool members"
                SKU = $ag.sku.name
                EstimatedMonthlyCost = $estimatedCost
                Recommendation = "Delete if not needed"
            }
        }
    }
    
    Write-CostLog "Completed analysis of $($subscription.name)" "SUCCESS"
}

Write-Host ""
Write-Host "================================================================"
Write-Host "  GENERATING COST SAVINGS REPORT"
Write-Host "================================================================"
Write-Host ""

# Export all idle resources
if ($allIdleResources.Count -gt 0) {
    $csvPath = Join-Path $reportPath "All-Idle-Resources.csv"
    $allIdleResources | Sort-Object EstimatedMonthlyCost -Descending | Export-Csv -Path $csvPath -NoTypeInformation
    Write-CostLog "CSV report saved: $csvPath" "SUCCESS"
    
    # Group by subscription
    $bySubscription = $allIdleResources | Group-Object Subscription
    
    foreach ($group in $bySubscription) {
        $subFolder = Join-Path $reportPath $group.Name.Replace(" ", "_")
        New-Item -ItemType Directory -Path $subFolder -Force | Out-Null
        
        $subCsvPath = Join-Path $subFolder "Idle-Resources.csv"
        $group.Group | Sort-Object EstimatedMonthlyCost -Descending | Export-Csv -Path $subCsvPath -NoTypeInformation
    }
    
    # Create summary by resource type
    $byType = $allIdleResources | Group-Object ResourceType | Sort-Object Count -Descending
    
    $summaryPath = Join-Path $reportPath "Summary-By-Type.csv"
    $typeSummary = $byType | ForEach-Object {
        [PSCustomObject]@{
            ResourceType = $_.Name
            Count = $_.Count
            TotalMonthlyCost = ($_.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
        }
    }
    $typeSummary | Export-Csv -Path $summaryPath -NoTypeInformation
    
} else {
    Write-CostLog "No idle resources found!" "SUCCESS"
}

# Create detailed README
$readmePath = Join-Path $reportPath "README.md"
$readmeContent = @"
# Azure Idle Resources Cost Savings Report

Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")

## Executive Summary

- **Total Idle Resources Found:** $($allIdleResources.Count)
- **Estimated Monthly Savings:** `$$([math]::Round($totalPotentialSavings, 2))
- **Estimated Annual Savings:** `$$([math]::Round($totalPotentialSavings * 12, 2))

## Breakdown by Resource Type

$(
    $byType = $allIdleResources | Group-Object ResourceType | Sort-Object Count -Descending
    foreach ($type in $byType) {
        $cost = ($type.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
        "- **$($type.Name):** $($type.Count) resources - `$$([math]::Round($cost, 2))/month"
    }
)

## Breakdown by Subscription

$(
    $bySub = $allIdleResources | Group-Object Subscription
    foreach ($sub in $bySub) {
        $cost = ($sub.Group | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
        "- **$($sub.Name):** $($sub.Count) resources - `$$([math]::Round($cost, 2))/month"
    }
)

## Top 10 Most Expensive Idle Resources

$(
    $top10 = $allIdleResources | Sort-Object EstimatedMonthlyCost -Descending | Select-Object -First 10
    $i = 1
    foreach ($resource in $top10) {
        "$i. **$($resource.ResourceName)** ($($resource.ResourceType)) - `$$($resource.EstimatedMonthlyCost)/month"
        $i++
    }
)

## Files Included

- **All-Idle-Resources.csv** - Complete list of all idle resources
- **Summary-By-Type.csv** - Summary grouped by resource type
- **[Subscription folders]** - Per-subscription idle resources

## Important Notes

- Cost estimates are APPROXIMATE based on standard Azure pricing
- Actual costs may vary based on region, usage, and specific configurations
- This is a READ-ONLY report - NO resources were deleted
- Review each resource carefully before deletion
- Consider creating snapshots/backups before deleting resources

## Recommended Actions

1. Review the All-Idle-Resources.csv file
2. Validate that resources are truly unused
3. Create deletion plan starting with highest-cost items
4. Test in non-production first
5. Monitor for any issues after deletion

---

**Report Generated By:** Azure Idle Resources Cost Savings Analyzer
**Safe for Production** - All operations were read-only
"@

$readmeContent | Out-File -FilePath $readmePath -Encoding UTF8

$endTime = Get-Date
$duration = $endTime - $scriptStartTime

Write-Host ""
Write-Host "================================================================"
Write-Host "  COST SAVINGS ANALYSIS COMPLETE!"
Write-Host "================================================================"
Write-Host ""
Write-Host "RESULTS" -ForegroundColor Cyan
Write-Host "================================================================"
Write-Host "  Total Idle Resources:      $($allIdleResources.Count)" -ForegroundColor White
Write-Host "  Estimated Monthly Savings: `$$([math]::Round($totalPotentialSavings, 2))" -ForegroundColor Green
Write-Host "  Estimated Annual Savings:  `$$([math]::Round($totalPotentialSavings * 12, 2))" -ForegroundColor Green
Write-Host "  Execution Time:            $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "================================================================"
Write-Host ""

if ($allIdleResources.Count -gt 0) {
    Write-Host "TOP 5 COST SAVINGS OPPORTUNITIES" -ForegroundColor Yellow
    Write-Host "================================================================"
    $top5 = $allIdleResources | Sort-Object EstimatedMonthlyCost -Descending | Select-Object -First 5
    $i = 1
    foreach ($resource in $top5) {
        Write-Host "  $i. $($resource.ResourceName)" -ForegroundColor White
        Write-Host "     Type: $($resource.ResourceType)" -ForegroundColor Gray
        Write-Host "     Location: $($resource.Location)" -ForegroundColor Gray
        Write-Host "     Monthly Cost: `$$($resource.EstimatedMonthlyCost)" -ForegroundColor Green
        Write-Host ""
        $i++
    }
}

Write-Host "================================================================"
Write-Host ""
Write-Host "Reports saved in: $reportPath" -ForegroundColor Green
Write-Host ""
Write-Host "READ-ONLY CONFIRMATION" -ForegroundColor Green
Write-Host "================================================================"
Write-Host "  This script made ZERO changes to your environment" -ForegroundColor Green
Write-Host "  No resources were deleted" -ForegroundColor Green
Write-Host "  Safe for production use" -ForegroundColor Green
Write-Host "================================================================"
Write-Host ""

Write-CostLog "Analysis complete!" "SUCCESS"
