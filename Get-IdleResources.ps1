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
    param([string]$Command, [switch]$SuppressErrors)
    try {
        if ($SuppressErrors) {
            $output = Invoke-Expression "$Command 2>`$null"
        } else {
            $output = Invoke-Expression $Command
        }
        if ($LASTEXITCODE -eq 0 -and $output) {
            return ($output | ConvertFrom-Json)
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
    param([string]$ResourceType, [string]$SKU, [string]$Size)
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
            if ($Size -match "(\d+)\s*GB") { $sizeGB = [int]$Matches[1] }
            if ($SKU -match "Premium") { 
                $cost = [math]::Max([math]::Round(($sizeGB * 0.15), 2), 15)
            } elseif ($SKU -match "StandardSSD") { 
                $cost = [math]::Max([math]::Round(($sizeGB * 0.08), 2), 8)
            } else {
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
        "az disk list --subscription $SubscriptionId --query '[0]' --output json"
    )
    foreach ($cmd in $testCommands) {
        $result = Invoke-Expression "$cmd 2>`$null"
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE IDLE RESOURCES SCANNER" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($ScanAllTenants) {
    Write-Host "Multi-Tenant Mode: Enabled" -ForegroundColor Cyan
    az logout 2>$null | Out-Null
    az login --output table
}

try {
    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or !$currentAccount) {
        az login --output table
        $currentAccount = az account show --output json | ConvertFrom-Json
    }
    Write-Host "Logged in as: $($currentAccount.user.name)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Azure CLI authentication failed" -ForegroundColor Red
    exit 1
}

$allTenants = @()
if ($ScanAllTenants) {
    $currentLogin = az account show --output json 2>$null | ConvertFrom-Json
    $tenantList = az account tenant list --output json 2>$null | ConvertFrom-Json
    if ($tenantList -and $tenantList.Count -gt 0) {
        foreach ($tenant in $tenantList) {
            $displayName = if ($tenant.displayName) { $tenant.displayName } else { "Tenant" }
            $allTenants += @{
                tenantId = $tenant.tenantId
                displayName = $displayName
                defaultDomain = $tenant.defaultDomain
            }
        }
    } else {
        $allTenants += @{
            tenantId = $currentLogin.tenantId
            displayName = "Current Tenant"
            defaultDomain = $currentLogin.user.name.Split('@')[1]
        }
    }
} else {
    $currentLogin = az account show --output json 2>$null | ConvertFrom-Json
    $allTenants += @{
        tenantId = $currentLogin.tenantId
        displayName = "Current Tenant"
        defaultDomain = $currentLogin.user.name.Split('@')[1]
    }
}

$allSubscriptions = @()
foreach ($tenant in $allTenants) {
    az login --tenant $tenant.tenantId --output none 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $tenantSubs = az account list --all --output json 2>$null | ConvertFrom-Json
        if ($tenantSubs) {
            foreach ($sub in $tenantSubs) {
                $sub | Add-Member -NotePropertyName "TenantDisplayName" -NotePropertyValue $tenant.displayName -Force
                $allSubscriptions += $sub
            }
        }
    }
}

if ($allSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No subscriptions found" -ForegroundColor Red
    exit 1
}

$enabledSubs = $allSubscriptions | Where-Object { $_.state -eq "Enabled" }
$accessibleSubscriptions = @()
$blockedSubscriptions = @()

foreach ($sub in $enabledSubs) {
    az account set --subscription $sub.id 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-SubscriptionAccess -SubscriptionId $sub.id)) {
        $accessibleSubscriptions += $sub
    } else {
        $blockedSubscriptions += $sub
    }
}

if ($accessibleSubscriptions.Count -eq 0) {
    Write-Host "ERROR: No accessible subscriptions" -ForegroundColor Red
    exit 1
}

$subscriptionsToScan = $accessibleSubscriptions

if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$allIdleResources = @()
$summary = @{
    ScanStartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    CurrentUser = $currentAccount.user.name
    TotalSubscriptionsScanned = 0
    TotalResourcesScanned = 0
    TotalIdleResources = 0
    TotalMonthlyCost = 0
    TotalAnnualCost = 0
}

foreach ($subscription in $subscriptionsToScan) {
    try {
        Write-Host "Scanning: $($subscription.name)" -ForegroundColor Cyan
        az account set --subscription $subscription.id 2>$null | Out-Null
        
        $subIdleResources = @()
        $subTotalCost = 0
        $subResourceCount = 0
        
        $vms = Get-AzureData -Command "az vm list -d --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $vms.Count
        foreach ($vm in $vms) {
            if ($vm.powerState -and ($vm.powerState -eq "VM deallocated" -or $vm.powerState -eq "VM stopped")) {
                $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "VM" -SKU $vm.hardwareProfile.vmSize
                $subTotalCost += $estimatedCost
                $subIdleResources += [PSCustomObject]@{
                    SubscriptionName = $subscription.name
                    ResourceType = "Virtual Machine"
                    ResourceName = $vm.name
                    ResourceGroup = $vm.resourceGroup
                    Status = $vm.powerState
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Recommendation = "Delete or restart"
                }
            }
        }
        
        $disks = Get-AzureData -Command "az disk list --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $disks.Count
        foreach ($disk in $disks) {
            if ([string]::IsNullOrEmpty($disk.managedBy)) {
                $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "Disk" -SKU $disk.sku.name -Size "$($disk.diskSizeGb) GB"
                $subTotalCost += $estimatedCost
                $subIdleResources += [PSCustomObject]@{
                    SubscriptionName = $subscription.name
                    ResourceType = "Unattached Disk"
                    ResourceName = $disk.name
                    ResourceGroup = $disk.resourceGroup
                    Status = "Unattached"
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Recommendation = "Delete if not needed"
                }
            }
        }
        
        $publicIPs = Get-AzureData -Command "az network public-ip list --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $publicIPs.Count
        foreach ($pip in $publicIPs) {
            if ([string]::IsNullOrEmpty($pip.ipConfiguration)) {
                $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "PublicIP"
                $subTotalCost += $estimatedCost
                $subIdleResources += [PSCustomObject]@{
                    SubscriptionName = $subscription.name
                    ResourceType = "Public IP"
                    ResourceName = $pip.name
                    ResourceGroup = $pip.resourceGroup
                    Status = "Unassigned"
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Recommendation = "Delete if not needed"
                }
            }
        }
        
        $nics = Get-AzureData -Command "az network nic list --subscription $($subscription.id) --output json" -SuppressErrors
        $subResourceCount += $nics.Count
        foreach ($nic in $nics) {
            if ([string]::IsNullOrEmpty($nic.virtualMachine)) {
                $estimatedCost = Get-EstimatedMonthlyCost -ResourceType "NIC"
                $subTotalCost += $estimatedCost
                $subIdleResources += [PSCustomObject]@{
                    SubscriptionName = $subscription.name
                    ResourceType = "Network Interface"
                    ResourceName = $nic.name
                    ResourceGroup = $nic.resourceGroup
                    Status = "Unattached"
                    EstimatedMonthlyCost = $estimatedCost
                    EstimatedAnnualCost = $estimatedCost * 12
                    Recommendation = "Delete if VM removed"
                }
            }
        }
        
        $allIdleResources += $subIdleResources
        $summary.TotalSubscriptionsScanned++
        $summary.TotalResourcesScanned += $subResourceCount
        $summary.TotalIdleResources += $subIdleResources.Count
        $summary.TotalMonthlyCost += $subTotalCost
        $summary.TotalAnnualCost += ($subTotalCost * 12)
        
        Write-Host "  Found: $($subIdleResources.Count) idle resources" -ForegroundColor Yellow
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host "Total Idle Resources: $($summary.TotalIdleResources)" -ForegroundColor Yellow
Write-Host "Monthly Savings: `$$([math]::Round($summary.TotalMonthlyCost, 2))" -ForegroundColor Green
Write-Host "Annual Savings: `$$([math]::Round($summary.TotalAnnualCost, 2))" -ForegroundColor Green
Write-Host ""

if ($allIdleResources.Count -gt 0) {
    $csvPath = Join-Path $OutputPath "IdleResources-$timestamp.csv"
    $csvData = $allIdleResources | Select-Object SubscriptionName, ResourceType, ResourceName, ResourceGroup, Status,
        @{Name='MonthlyUSD'; Expression={'$' + [string]$_.EstimatedMonthlyCost}},
        @{Name='AnnualUSD'; Expression={'$' + [string]$_.EstimatedAnnualCost}},
        Recommendation
    $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Force
    Write-Host "CSV Report: $csvPath" -ForegroundColor Green
    
    $htmlPath = Join-Path $OutputPath "IdleResources-$timestamp.html"
    $monthlyAmount = [math]::Round($summary.TotalMonthlyCost, 2)
    $annualAmount = [math]::Round($summary.TotalAnnualCost, 2)
    $dollarChar = [char]36
    
    $html = "<!DOCTYPE html><html><head><title>Azure Idle Resources</title>"
    $html += "<style>body{font-family:Arial;margin:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px}th{background:#0078d4;color:white}</style>"
    $html += "</head><body><h1>Azure Idle Resources Report</h1>"
    $html += "<p>Generated: " + $summary.ScanStartTime + "</p>"
    $html += "<h2>Summary</h2>"
    $html += "<p>Total Idle Resources: " + $summary.TotalIdleResources + "</p>"
    $html += "<p>Monthly Savings: " + $dollarChar + $monthlyAmount + "</p>"
    $html += "<p>Annual Savings: " + $dollarChar + $annualAmount + "</p>"
    $html += "<h2>Resources</h2><table><tr><th>Subscription</th><th>Type</th><th>Name</th><th>Status</th><th>Monthly</th><th>Annual</th></tr>"
    
    foreach ($resource in $allIdleResources) {
        $monthlyCost = [math]::Round($resource.EstimatedMonthlyCost, 2)
        $annualCost = [math]::Round($resource.EstimatedAnnualCost, 2)
        $html += "<tr><td>" + $resource.SubscriptionName + "</td>"
        $html += "<td>" + $resource.ResourceType + "</td>"
        $html += "<td>" + $resource.ResourceName + "</td>"
        $html += "<td>" + $resource.Status + "</td>"
        $html += "<td>" + $dollarChar + $monthlyCost + "</td>"
        $html += "<td>" + $dollarChar + $annualCost + "</td></tr>"
    }
    
    $html += "</table></body></html>"
    
    [System.IO.File]::WriteAllText($htmlPath, $html)
    Write-Host "HTML Report: $htmlPath" -ForegroundColor Green
    Start-Process $htmlPath
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
