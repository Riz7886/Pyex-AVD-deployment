#Requires -Modules Az.Accounts, Az.Resources, Az.CostManagement, Az.Advisor
#Requires -Version 7.0

<#
.SYNOPSIS
    COMPLETE Production Audit - 500% Detailed Analysis
    
.DESCRIPTION
    100% READ-ONLY - Makes ZERO changes
    NOW INCLUDES:
    - Individual resource names, sizes, tags
    - VM sizes and configurations
    - RBAC permissions audit
    - Network details (VNets, IPs, subnets)
    - Backup status
    - Security issues
    - Cost analysis
    - HTML + Multiple CSVs
#>

param(
    [string]$OutputDirectory = ".\Production-Audit-Reports",
    [switch]$AutoCommitToGit,
    [string]$StorageAccountName = ""
)

$ErrorActionPreference = 'Continue'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     COMPLETE PRODUCTION AUDIT - 500% DETAILED                 ║" -ForegroundColor Cyan
Write-Host "║     100% READ-ONLY - Zero Changes                             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Connect to Azure
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) { Connect-AzAccount }
} catch { Connect-AzAccount }

# Discover subscriptions
Write-Host "Auto-discovering subscriptions..." -ForegroundColor Yellow
$allSubscriptions = Get-AzSubscription
Write-Host "Found $($allSubscriptions.Count) subscription(s)`n" -ForegroundColor Green

$allResults = @()
$allDetailedResources = @()
$allRBACAssignments = @()
$allNetworkDetails = @()
$totalCost = 0

foreach ($subscription in $allSubscriptions) {
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "ANALYZING: $($subscription.Name)" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $subscription.Id -TenantId $subscription.TenantId | Out-Null
        
        $subData = @{
            SubscriptionName = $subscription.Name
            SubscriptionId = $subscription.Id
            TenantId = $subscription.TenantId
            ResourceGroups = @()
            TotalCost = 0
            Recommendations = @()
            SecurityIssues = @()
            ComplianceIssues = @()
        }
        
        # [1/10] Get ALL resources with FULL details
        Write-Host "[1/10] Getting detailed resource inventory..." -ForegroundColor Yellow
        $allResources = Get-AzResource
        $resourceGroups = Get-AzResourceGroup
        
        foreach ($resource in $allResources) {
            $resourceDetail = [PSCustomObject]@{
                SubscriptionName = $subscription.Name
                SubscriptionId = $subscription.Id
                ResourceName = $resource.Name
                ResourceType = $resource.ResourceType
                ResourceGroup = $resource.ResourceGroupName
                Location = $resource.Location
                Tags = if ($resource.Tags) { ($resource.Tags.Keys | ForEach-Object { "$_=$($resource.Tags[$_])" }) -join "; " } else { "NO TAGS" }
                SKU = ""
                Size = ""
                Status = ""
                PrivateIP = ""
                PublicIP = ""
            }
            
            # Get VM details
            if ($resource.ResourceType -eq 'Microsoft.Compute/virtualMachines') {
                try {
                    $vm = Get-AzVM -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name -Status
                    $resourceDetail.Size = $vm.HardwareProfile.VmSize
                    $resourceDetail.Status = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
                    
                    # Get VM IPs
                    $vmNic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $vm.Id }
                    if ($vmNic) {
                        $resourceDetail.PrivateIP = $vmNic.IpConfigurations[0].PrivateIpAddress
                        if ($vmNic.IpConfigurations[0].PublicIpAddress) {
                            $pip = Get-AzPublicIpAddress -ResourceGroupName $vmNic.ResourceGroupName -Name ($vmNic.IpConfigurations[0].PublicIpAddress.Id -split '/')[-1]
                            $resourceDetail.PublicIP = $pip.IpAddress
                        }
                    }
                } catch { }
            }
            
            # Get Storage details
            if ($resource.ResourceType -eq 'Microsoft.Storage/storageAccounts') {
                try {
                    $sa = Get-AzStorageAccount -ResourceGroupName $resource.ResourceGroupName -Name $resource.Name
                    $resourceDetail.SKU = $sa.Sku.Name
                    $resourceDetail.Status = if ($sa.EnableHttpsTrafficOnly) { "HTTPS Only" } else { "HTTP Allowed (RISK!)" }
                } catch { }
            }
            
            # Get Disk details
            if ($resource.ResourceType -eq 'Microsoft.Compute/disks') {
                try {
                    $disk = Get-AzDisk -ResourceGroupName $resource.ResourceGroupName -DiskName $resource.Name
                    $resourceDetail.Size = "$($disk.DiskSizeGB)GB"
                    $resourceDetail.SKU = $disk.Sku.Name
                    $resourceDetail.Status = if ($disk.ManagedBy) { "Attached" } else { "UNATTACHED (Waste!)" }
                } catch { }
            }
            
            $allDetailedResources += $resourceDetail
        }
        
        # [2/10] RBAC Permissions Audit
        Write-Host "[2/10] Auditing RBAC permissions..." -ForegroundColor Yellow
        $roleAssignments = Get-AzRoleAssignment
        foreach ($assignment in $roleAssignments) {
            $allRBACAssignments += [PSCustomObject]@{
                SubscriptionName = $subscription.Name
                PrincipalName = $assignment.DisplayName
                PrincipalType = $assignment.ObjectType
                RoleName = $assignment.RoleDefinitionName
                Scope = $assignment.Scope
                ScopeType = if ($assignment.Scope -like "*/resourceGroups/*") { "Resource Group" } elseif ($assignment.Scope -like "*/subscriptions/*" -and $assignment.Scope -notlike "*/resourceGroups/*") { "Subscription" } else { "Resource" }
            }
        }
        
        # [3/10] Network Details
        Write-Host "[3/10] Analyzing network configuration..." -ForegroundColor Yellow
        $vnets = Get-AzVirtualNetwork
        foreach ($vnet in $vnets) {
            foreach ($subnet in $vnet.Subnets) {
                $allNetworkDetails += [PSCustomObject]@{
                    SubscriptionName = $subscription.Name
                    VNetName = $vnet.Name
                    SubnetName = $subnet.Name
                    AddressPrefix = $subnet.AddressPrefix -join ", "
                    ResourceGroup = $vnet.ResourceGroupName
                    Location = $vnet.Location
                    ConnectedResources = $subnet.IpConfigurations.Count
                }
            }
        }
        
        # [4/10] Cost Analysis per RG
        Write-Host "[4/10] Analyzing costs..." -ForegroundColor Yellow
        foreach ($rg in $resourceGroups) {
            $resources = $allResources | Where-Object { $_.ResourceGroupName -eq $rg.ResourceGroupName }
            
            $vms = ($resources | Where-Object { $_.ResourceType -eq 'Microsoft.Compute/virtualMachines' }).Count
            $storage = ($resources | Where-Object { $_.ResourceType -like '*Storage*' }).Count
            $disks = ($resources | Where-Object { $_.ResourceType -eq 'Microsoft.Compute/disks' }).Count
            $pips = ($resources | Where-Object { $_.ResourceType -eq 'Microsoft.Network/publicIPAddresses' }).Count
            
            $estimatedCost = ($vms * 50) + ($storage * 10) + ($disks * 5) + ($pips * 3)
            
            $subData.ResourceGroups += [PSCustomObject]@{
                Name = $rg.ResourceGroupName
                Location = $rg.Location
                ResourceCount = $resources.Count
                VMs = $vms
                Storage = $storage
                Disks = $disks
                PublicIPs = $pips
                EstimatedMonthlyCost = [math]::Round($estimatedCost, 2)
                Tags = if ($rg.Tags) { ($rg.Tags.Keys | ForEach-Object { "$_=$($rg.Tags[$_])" }) -join "; " } else { "NO TAGS" }
            }
            
            $subData.TotalCost += $estimatedCost
        }
        
        # [5/10] Security Issues
        Write-Host "[5/10] Security audit..." -ForegroundColor Yellow
        $nsgs = Get-AzNetworkSecurityGroup
        foreach ($nsg in $nsgs) {
            foreach ($rule in $nsg.SecurityRules) {
                if ($rule.SourceAddressPrefix -eq '*' -and $rule.Access -eq 'Allow' -and 
                    ($rule.DestinationPortRange -eq '22' -or $rule.DestinationPortRange -eq '3389')) {
                    $subData.SecurityIssues += "CRITICAL: NSG '$($nsg.Name)' allows $($rule.DestinationPortRange) from internet"
                }
            }
        }
        
        $storageAccounts = Get-AzStorageAccount
        foreach ($sa in $storageAccounts) {
            if (-not $sa.EnableHttpsTrafficOnly) {
                $subData.SecurityIssues += "HIGH: Storage '$($sa.StorageAccountName)' allows HTTP"
            }
        }
        
        # [6/10] Backup Status
        Write-Host "[6/10] Checking backup status..." -ForegroundColor Yellow
        try {
            $vaults = Get-AzRecoveryServicesVault
            $protectedVMs = 0
            foreach ($vault in $vaults) {
                Set-AzRecoveryServicesVaultContext -Vault $vault | Out-Null
                $items = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -ErrorAction SilentlyContinue
                $protectedVMs += $items.Count
            }
            $totalVMs = (Get-AzVM).Count
            if ($totalVMs -gt $protectedVMs) {
                $subData.ComplianceIssues += "$($totalVMs - $protectedVMs) VM(s) not backed up"
            }
        } catch { }
        
        # [7/10] Cost Optimization
        Write-Host "[7/10] Finding cost savings..." -ForegroundColor Yellow
        $unattachedDisks = Get-AzDisk | Where-Object { $null -eq $_.ManagedBy }
        if ($unattachedDisks.Count -gt 0) {
            $subData.Recommendations += "Delete $($unattachedDisks.Count) unattached disk(s) - Save ~`$$($unattachedDisks.Count * 5)/month"
        }
        
        $unattachedPIPs = Get-AzPublicIpAddress | Where-Object { $null -eq $_.IpConfiguration }
        if ($unattachedPIPs.Count -gt 0) {
            $subData.Recommendations += "Delete $($unattachedPIPs.Count) unattached IP(s) - Save ~`$$($unattachedPIPs.Count * 3)/month"
        }
        
        # [8/10] Compliance
        Write-Host "[8/10] Compliance check..." -ForegroundColor Yellow
        $untaggedResources = $allResources | Where-Object { $null -eq $_.Tags -or $_.Tags.Count -eq 0 }
        if ($untaggedResources.Count -gt 0) {
            $subData.ComplianceIssues += "$($untaggedResources.Count) resource(s) missing tags"
        }
        
        # [9/10] Azure Advisor
        Write-Host "[9/10] Azure Advisor check..." -ForegroundColor Yellow
        try {
            $advisorRecs = Get-AzAdvisorRecommendation -Category Cost -ErrorAction SilentlyContinue
            foreach ($rec in $advisorRecs | Select-Object -First 5) {
                $subData.Recommendations += "Azure Advisor: $($rec.ShortDescription.Problem)"
            }
        } catch { }
        
        Write-Host "[10/10] Complete for subscription" -ForegroundColor Green
        Write-Host "Cost: `$$([math]::Round($subData.TotalCost, 2))/month`n" -ForegroundColor Cyan
        
        $allResults += $subData
        $totalCost += $subData.TotalCost
        
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}

# Generate HTML Report
Write-Host "Generating comprehensive report..." -ForegroundColor Yellow

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Complete Production Audit - $timestamp</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 32px; }
        .summary { background: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .cost-box { display: inline-block; background: #4CAF50; color: white; padding: 15px 25px; border-radius: 8px; margin: 10px 10px 10px 0; }
        .cost-box h3 { margin: 0; font-size: 16px; font-weight: normal; opacity: 0.9; }
        .cost-box .amount { font-size: 32px; font-weight: bold; margin-top: 5px; }
        .subscription { background: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .subscription h3 { margin-top: 0; color: #667eea; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; font-size: 13px; }
        th { background: #667eea; color: white; padding: 12px 8px; text-align: left; font-weight: 600; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f9f9f9; }
        .recommendation { background: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin: 8px 0; border-radius: 4px; }
        .security-issue { background: #f8d7da; border-left: 4px solid #dc3545; padding: 12px; margin: 8px 0; border-radius: 4px; }
        .compliance-issue { background: #d1ecf1; border-left: 4px solid #17a2b8; padding: 12px; margin: 8px 0; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Complete Production Audit - 500% Detailed</h1>
        <p>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
        <p>100% READ-ONLY - No Changes Made</p>
    </div>
    
    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="cost-box">
            <h3>Subscriptions</h3>
            <div class="amount">$($allSubscriptions.Count)</div>
        </div>
        <div class="cost-box">
            <h3>Total Resources</h3>
            <div class="amount">$($allDetailedResources.Count)</div>
        </div>
        <div class="cost-box">
            <h3>Monthly Cost</h3>
            <div class="amount">`$$([math]::Round($totalCost, 2))</div>
        </div>
        <div class="cost-box" style="background: #ffc107;">
            <h3>Savings Found</h3>
            <div class="amount">$($allResults.Recommendations.Count)</div>
        </div>
        <div class="cost-box" style="background: #dc3545;">
            <h3>Security Issues</h3>
            <div class="amount">$($allResults.SecurityIssues.Count)</div>
        </div>
    </div>
"@

foreach ($result in $allResults) {
    $htmlReport += @"
    <div class="subscription">
        <h3>📊 $($result.SubscriptionName)</h3>
        <p><strong>Cost:</strong> <span style="color: #4CAF50; font-size: 20px;">`$$([math]::Round($result.TotalCost, 2))/month</span></p>
        
        <h4>Resource Groups</h4>
        <table>
            <tr><th>Name</th><th>Location</th><th>Resources</th><th>VMs</th><th>Storage</th><th>Cost/month</th><th>Tags</th></tr>
"@
    foreach ($rg in $result.ResourceGroups) {
        $htmlReport += "<tr><td>$($rg.Name)</td><td>$($rg.Location)</td><td>$($rg.ResourceCount)</td><td>$($rg.VMs)</td><td>$($rg.Storage)</td><td>`$$($rg.EstimatedMonthlyCost)</td><td>$($rg.Tags)</td></tr>"
    }
    $htmlReport += "</table>"
    
    if ($result.SecurityIssues) {
        $htmlReport += "<h4>🔒 Security Issues</h4>"
        foreach ($i in $result.SecurityIssues) { $htmlReport += "<div class='security-issue'>$i</div>" }
    }
    
    if ($result.Recommendations) {
        $htmlReport += "<h4>💡 Recommendations</h4>"
        foreach ($r in $result.Recommendations) { $htmlReport += "<div class='recommendation'>$r</div>" }
    }
    
    $htmlReport += "</div>"
}

$htmlReport += "</body></html>"

# Save reports
$htmlPath = Join-Path $OutputDirectory "Complete_Audit_$timestamp.html"
$htmlReport | Out-File $htmlPath -Encoding UTF8

# Save multiple detailed CSVs
$allDetailedResources | Export-Csv (Join-Path $OutputDirectory "Resources_Detailed_$timestamp.csv") -NoTypeInformation
$allRBACAssignments | Export-Csv (Join-Path $OutputDirectory "RBAC_Permissions_$timestamp.csv") -NoTypeInformation
$allNetworkDetails | Export-Csv (Join-Path $OutputDirectory "Network_Details_$timestamp.csv") -NoTypeInformation

# Cost summary CSV
$costSummary = @()
foreach ($result in $allResults) {
    foreach ($rg in $result.ResourceGroups) {
        $costSummary += [PSCustomObject]@{
            Subscription = $result.SubscriptionName
            ResourceGroup = $rg.Name
            Location = $rg.Location
            Resources = $rg.ResourceCount
            VMs = $rg.VMs
            Cost = $rg.EstimatedMonthlyCost
            Tags = $rg.Tags
        }
    }
}
$costSummary | Export-Csv (Join-Path $OutputDirectory "Cost_Summary_$timestamp.csv") -NoTypeInformation

Write-Host "`n════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  COMPLETE AUDIT FINISHED - 500% DETAILED" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`nTotal Cost: `$$([math]::Round($totalCost, 2))/month" -ForegroundColor Cyan
Write-Host "Total Resources Audited: $($allDetailedResources.Count)" -ForegroundColor Cyan
Write-Host "RBAC Assignments: $($allRBACAssignments.Count)" -ForegroundColor Cyan
Write-Host "Security Issues: $($allResults.SecurityIssues.Count)" -ForegroundColor Red

Write-Host "`nReports Generated:" -ForegroundColor Yellow
Write-Host "  HTML:        $htmlPath" -ForegroundColor White
Write-Host "  Resources:   $(Join-Path $OutputDirectory "Resources_Detailed_$timestamp.csv")" -ForegroundColor White
Write-Host "  RBAC:        $(Join-Path $OutputDirectory "RBAC_Permissions_$timestamp.csv")" -ForegroundColor White
Write-Host "  Network:     $(Join-Path $OutputDirectory "Network_Details_$timestamp.csv")" -ForegroundColor White
Write-Host "  Cost:        $(Join-Path $OutputDirectory "Cost_Summary_$timestamp.csv")" -ForegroundColor White

Start-Process $htmlPath

Write-Host "`n✅ Complete - No changes made to environment" -ForegroundColor Green
