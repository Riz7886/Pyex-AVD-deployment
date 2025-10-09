#Requires -Version 5.1

<#
.SYNOPSIS
    Ultimate Multi-Subscription Azure Audit - FIXED VERSION

.DESCRIPTION
    Enterprise-grade READ-ONLY audit script
    - Automatically discovers ALL subscriptions
    - Analyzes every resource in every subscription
    - Generates comprehensive reports per subscription
    - 100% READ-ONLY - Makes ZERO changes
    - FIXED: All JSON parsing errors resolved

.PARAMETER OutputPath
    Path where reports will be saved. Default: .\Complete-Audit-Reports\

.EXAMPLE
    .\Ultimate-Multi-Subscription-Audit.ps1

.NOTES
    Version: 5.1 - FIXED Edition
    100% READ-ONLY - Safe for production
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Complete-Audit-Reports"
)

function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "PROGRESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"     = "Cyan"
        "SUCCESS"  = "Green"
        "WARNING"  = "Yellow"
        "ERROR"    = "Red"
        "PROGRESS" = "Magenta"
    }
    
    Write-Host "[$timestamp] $Message" -ForegroundColor $colors[$Level]
}

function Get-SafeValue {
    param($Value, $Default = "N/A")
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    return $Value
}

function Get-AzureJsonData {
    param(
        [string]$Command
    )
    
    try {
        $output = Invoke-Expression $Command
        if ($LASTEXITCODE -eq 0) {
            return ($output | ConvertFrom-Json)
        }
        return @()
    } catch {
        Write-AuditLog "Error executing: $Command" "WARNING"
        return @()
    }
}

$scriptStartTime = Get-Date
$subscriptionReports = @()

Write-Host ""
Write-Host "================================================================"
Write-Host "  ULTIMATE MULTI-SUBSCRIPTION AZURE AUDIT"
Write-Host "  Complete Environment Analysis - All Subscriptions"
Write-Host "================================================================"
Write-Host ""
Write-Host "  READ-ONLY MODE - No changes will be made" -ForegroundColor Green
Write-Host "  Safe for production environments" -ForegroundColor Green
Write-Host ""
Write-Host "================================================================"
Write-Host ""

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$masterReportPath = Join-Path $OutputPath "Master-Report-$timestamp"
New-Item -ItemType Directory -Path $masterReportPath -Force | Out-Null

Write-AuditLog "Output directory: $masterReportPath" "INFO"
Write-AuditLog "Starting comprehensive audit..." "PROGRESS"

Write-Host ""
Write-Host "================================================================"
Write-Host "  STEP 1: DISCOVERING ALL SUBSCRIPTIONS"
Write-Host "================================================================"
Write-Host ""

Write-AuditLog "Checking Azure CLI login..." "INFO"

try {
    $null = az account show --output json
    if ($LASTEXITCODE -ne 0) {
        Write-AuditLog "Not logged in to Azure CLI" "ERROR"
        Write-Host ""
        Write-Host "Please run: az login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-AuditLog "Azure CLI not available" "ERROR"
    Write-Host "Please install Azure CLI and run: az login" -ForegroundColor Yellow
    exit 1
}

Write-AuditLog "Discovering all accessible subscriptions..." "PROGRESS"

$allSubscriptions = Get-AzureJsonData -Command "az account list --all --output json"

if ($allSubscriptions.Count -eq 0) {
    Write-AuditLog "No subscriptions found" "ERROR"
    exit 1
}

Write-AuditLog "Found $($allSubscriptions.Count) subscriptions" "SUCCESS"
Write-Host ""

foreach ($sub in $allSubscriptions) {
    $status = if ($sub.state -eq "Enabled") { "ACTIVE" } else { $sub.state }
    Write-Host "  - $($sub.name)" -ForegroundColor White -NoNewline
    Write-Host " [$status]" -ForegroundColor $(if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" })
}

Write-Host ""

foreach ($subscription in $allSubscriptions) {
    
    if ($subscription.state -ne "Enabled") {
        Write-AuditLog "Skipping disabled subscription: $($subscription.name)" "WARNING"
        continue
    }

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "  ANALYZING: $($subscription.name)"
    Write-Host "  ID: $($subscription.id)"
    Write-Host "================================================================"
    Write-Host ""

    az account set --subscription $subscription.id | Out-Null
    
    $subData = @{
        SubscriptionName = $subscription.name
        SubscriptionId = $subscription.id
        TenantId = $subscription.tenantId
        State = $subscription.state
        ResourceGroups = @()
        Resources = @()
        IAM = @()
        Policies = @()
        SecurityCenter = @{}
        Networking = @()
        KeyVaults = @()
        LoadBalancers = @()
        FrontDoors = @()
        ServicePrincipals = @()
        Findings = @()
        Statistics = @{
            TotalResourceGroups = 0
            TotalResources = 0
            TotalIAMAssignments = 0
            TotalPolicies = 0
            TotalVNets = 0
            TotalNSGs = 0
            TotalVMs = 0
            TotalStorageAccounts = 0
            TotalKeyVaults = 0
            TotalLoadBalancers = 0
            CriticalFindings = 0
            HighFindings = 0
            MediumFindings = 0
            LowFindings = 0
        }
    }

    Write-AuditLog "Collecting resource groups..." "PROGRESS"
    
    $resourceGroups = Get-AzureJsonData -Command "az group list --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalResourceGroups = $resourceGroups.Count
    Write-AuditLog "Found $($resourceGroups.Count) resource groups" "INFO"
    
    foreach ($rg in $resourceGroups) {
        $rgData = [PSCustomObject]@{
            Name = Get-SafeValue $rg.name
            Location = Get-SafeValue $rg.location
            Tags = if ($rg.tags) { ($rg.tags | ConvertTo-Json -Compress) } else { "None" }
        }
        $subData.ResourceGroups += $rgData
    }
    
    Write-AuditLog "Collecting ALL resources in subscription..." "PROGRESS"
    
    $allResources = Get-AzureJsonData -Command "az resource list --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalResources = $allResources.Count
    Write-AuditLog "Found $($allResources.Count) resources" "INFO"
    
    foreach ($resource in $allResources) {
        $resourceData = [PSCustomObject]@{
            Name = Get-SafeValue $resource.name
            Type = Get-SafeValue $resource.type
            ResourceGroup = Get-SafeValue $resource.resourceGroup
            Location = Get-SafeValue $resource.location
            Tags = if ($resource.tags) { ($resource.tags | ConvertTo-Json -Compress) } else { "None" }
            SKU = Get-SafeValue $resource.sku.name
            Kind = Get-SafeValue $resource.kind
        }
        $subData.Resources += $resourceData
        
        switch -Wildcard ($resource.type) {
            "*virtualMachines" { $subData.Statistics.TotalVMs++ }
            "*storageAccounts" { $subData.Statistics.TotalStorageAccounts++ }
            "*virtualNetworks" { $subData.Statistics.TotalVNets++ }
            "*networkSecurityGroups" { $subData.Statistics.TotalNSGs++ }
            "*vaults" { 
                if ($resource.type -eq "Microsoft.KeyVault/vaults") {
                    $subData.Statistics.TotalKeyVaults++
                }
            }
            "*loadBalancers" { $subData.Statistics.TotalLoadBalancers++ }
        }
    }
    
    $untaggedResources = $allResources | Where-Object { -not $_.tags -or $_.tags.Count -eq 0 }
    if ($untaggedResources.Count -gt 0) {
        $subData.Findings += [PSCustomObject]@{
            Severity = "Low"
            Category = "Governance"
            Resource = "$($untaggedResources.Count) resources"
            Issue = "Resources without tags"
            Recommendation = "Implement tagging strategy for cost tracking"
        }
        $subData.Statistics.LowFindings++
    }
    
    Write-AuditLog "Analyzing IAM and RBAC..." "PROGRESS"
    
    $roleAssignments = Get-AzureJsonData -Command "az role assignment list --all --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalIAMAssignments = $roleAssignments.Count
    Write-AuditLog "Found $($roleAssignments.Count) role assignments" "INFO"
    
    foreach ($assignment in $roleAssignments) {
        $iamData = [PSCustomObject]@{
            PrincipalName = Get-SafeValue $assignment.principalName
            PrincipalType = Get-SafeValue $assignment.principalType
            RoleDefinition = Get-SafeValue $assignment.roleDefinitionName
            Scope = Get-SafeValue $assignment.scope
            PrincipalId = Get-SafeValue $assignment.principalId
        }
        $subData.IAM += $iamData
        
        if ($assignment.roleDefinitionName -eq "Owner") {
            $severity = if ($assignment.principalType -eq "ServicePrincipal") { "Critical" } else { "High" }
            $subData.Findings += [PSCustomObject]@{
                Severity = $severity
                Category = "IAM"
                Resource = Get-SafeValue $assignment.principalName
                Issue = "$($assignment.principalType) has Owner role"
                Recommendation = "Review if Owner role is necessary. Use Contributor instead."
            }
            if ($severity -eq "Critical") { $subData.Statistics.CriticalFindings++ }
            else { $subData.Statistics.HighFindings++ }
        }
        
        if ($assignment.principalType -eq "User" -and $assignment.principalName -like "*#EXT#*") {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "IAM"
                Resource = Get-SafeValue $assignment.principalName
                Issue = "Guest user with elevated access"
                Recommendation = "Review guest user permissions"
            }
            $subData.Statistics.HighFindings++
        }
        
        if ([string]::IsNullOrEmpty($assignment.principalName) -or $assignment.principalName -eq "Unknown") {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Medium"
                Category = "IAM"
                Resource = $assignment.principalId
                Issue = "Orphaned role assignment"
                Recommendation = "Remove stale role assignment"
            }
            $subData.Statistics.MediumFindings++
        }
    }
    
    Write-AuditLog "Collecting Azure Policies..." "PROGRESS"
    
    $policyAssignments = Get-AzureJsonData -Command "az policy assignment list --subscription $($subscription.id) --output json"
    $subData.Statistics.TotalPolicies = $policyAssignments.Count
    Write-AuditLog "Found $($policyAssignments.Count) policy assignments" "INFO"
    
    foreach ($policy in $policyAssignments) {
        $policyData = [PSCustomObject]@{
            Name = Get-SafeValue $policy.name
            DisplayName = Get-SafeValue $policy.displayName
            PolicyDefinitionId = Get-SafeValue $policy.policyDefinitionId
            Scope = Get-SafeValue $policy.scope
        }
        $subData.Policies += $policyData
    }
    
    Write-AuditLog "Checking Defender for Cloud..." "PROGRESS"
    
    $defenderPricing = Get-AzureJsonData -Command "az security pricing list --subscription $($subscription.id) --output json"
    
    $securityTools = @{
        DefenderForServers = "Not Enabled"
        DefenderForStorage = "Not Enabled"
        DefenderForSQL = "Not Enabled"
        DefenderForContainers = "Not Enabled"
    }
    
    foreach ($pricing in $defenderPricing) {
        switch ($pricing.name) {
            "VirtualMachines" { $securityTools.DefenderForServers = $pricing.pricingTier }
            "StorageAccounts" { $securityTools.DefenderForStorage = $pricing.pricingTier }
            "SqlServers" { $securityTools.DefenderForSQL = $pricing.pricingTier }
            "Containers" { $securityTools.DefenderForContainers = $pricing.pricingTier }
        }
    }
    
    $subData.SecurityCenter = $securityTools
    
    Write-AuditLog "Analyzing network configuration..." "PROGRESS"
    
    $vnets = Get-AzureJsonData -Command "az network vnet list --subscription $($subscription.id) --output json"
    
    foreach ($vnet in $vnets) {
        $vnetData = [PSCustomObject]@{
            Name = $vnet.name
            ResourceGroup = $vnet.resourceGroup
            Location = $vnet.location
            AddressSpace = ($vnet.addressSpace.addressPrefixes -join ", ")
            Subnets = $vnet.subnets.Count
        }
        $subData.Networking += $vnetData
        
        foreach ($subnet in $vnet.subnets) {
            if (-not $subnet.networkSecurityGroup -and $subnet.name -ne "GatewaySubnet" -and $subnet.name -ne "AzureFirewallSubnet") {
                $subData.Findings += [PSCustomObject]@{
                    Severity = "High"
                    Category = "Network"
                    Resource = "$($vnet.name)/$($subnet.name)"
                    Issue = "Subnet without Network Security Group"
                    Recommendation = "Attach NSG to subnet"
                }
                $subData.Statistics.HighFindings++
            }
        }
    }
    
    $nsgs = Get-AzureJsonData -Command "az network nsg list --subscription $($subscription.id) --output json"
    
    foreach ($nsg in $nsgs) {
        $dangerousRules = $nsg.securityRules | Where-Object {
            $_.direction -eq "Inbound" -and
            $_.access -eq "Allow" -and
            ($_.sourceAddressPrefix -eq "*" -or $_.sourceAddressPrefix -eq "0.0.0.0/0")
        }
        
        foreach ($rule in $dangerousRules) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Critical"
                Category = "Network"
                Resource = "$($nsg.name) - Rule: $($rule.name)"
                Issue = "Unrestricted inbound from Internet on port $($rule.destinationPortRange)"
                Recommendation = "Restrict source to specific IPs"
            }
            $subData.Statistics.CriticalFindings++
        }
    }
    
    $loadBalancers = Get-AzureJsonData -Command "az network lb list --subscription $($subscription.id) --output json"
    
    foreach ($lb in $loadBalancers) {
        $lbData = [PSCustomObject]@{
            Name = $lb.name
            ResourceGroup = $lb.resourceGroup
            Location = $lb.location
            SKU = $lb.sku.name
        }
        $subData.LoadBalancers += $lbData
    }
    
    Write-AuditLog "Analyzing storage accounts..." "PROGRESS"
    
    $storageAccounts = Get-AzureJsonData -Command "az storage account list --subscription $($subscription.id) --output json"
    
    foreach ($sa in $storageAccounts) {
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Critical"
                Category = "Security"
                Resource = $sa.name
                Issue = "Storage account allows HTTP traffic"
                Recommendation = "Enable HTTPS-only"
            }
            $subData.Statistics.CriticalFindings++
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $sa.name
                Issue = "Storage account allows public blob access"
                Recommendation = "Disable public blob access"
            }
            $subData.Statistics.HighFindings++
        }
    }
    
    Write-AuditLog "Analyzing Key Vaults..." "PROGRESS"
    
    $keyVaults = Get-AzureJsonData -Command "az keyvault list --subscription $($subscription.id) --output json"
    
    foreach ($kv in $keyVaults) {
        $kvData = [PSCustomObject]@{
            Name = $kv.name
            ResourceGroup = $kv.resourceGroup
            Location = $kv.location
            SKU = $kv.properties.sku.name
            EnableSoftDelete = $kv.properties.enableSoftDelete
            EnablePurgeProtection = $kv.properties.enablePurgeProtection
        }
        $subData.KeyVaults += $kvData
        
        if ($kv.properties.enableSoftDelete -ne $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $kv.name
                Issue = "Key Vault soft delete not enabled"
                Recommendation = "Enable soft delete"
            }
            $subData.Statistics.HighFindings++
        }
    }
    
    Write-AuditLog "Analyzing Virtual Machines..." "PROGRESS"
    
    $vms = Get-AzureJsonData -Command "az vm list -d --subscription $($subscription.id) --output json"
    
    foreach ($vm in $vms) {
        if ($vm.publicIps) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $vm.name
                Issue = "VM has public IP address"
                Recommendation = "Use Azure Bastion or VPN"
            }
            $subData.Statistics.HighFindings++
        }
    }
    
    Write-AuditLog "Analyzing Service Principals..." "PROGRESS"
    
    $spAssignments = $roleAssignments | Where-Object { $_.principalType -eq "ServicePrincipal" }
    
    foreach ($sp in $spAssignments) {
        $spData = [PSCustomObject]@{
            Name = Get-SafeValue $sp.principalName
            PrincipalId = $sp.principalId
            Role = $sp.roleDefinitionName
            Scope = $sp.scope
        }
        $subData.ServicePrincipals += $spData
    }
    
    $subscriptionReports += $subData
    
    Write-AuditLog "Completed analysis of $($subscription.name)" "SUCCESS"
    Write-Host "  - Resource Groups: $($subData.Statistics.TotalResourceGroups)" -ForegroundColor White
    Write-Host "  - Resources: $($subData.Statistics.TotalResources)" -ForegroundColor White
    Write-Host "  - IAM Assignments: $($subData.Statistics.TotalIAMAssignments)" -ForegroundColor White
    Write-Host "  - Findings: $($subData.Findings.Count) (C:$($subData.Statistics.CriticalFindings) H:$($subData.Statistics.HighFindings) M:$($subData.Statistics.MediumFindings) L:$($subData.Statistics.LowFindings))" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================"
Write-Host "  GENERATING COMPREHENSIVE REPORTS"
Write-Host "================================================================"
Write-Host ""

Write-AuditLog "Generating master reports..." "PROGRESS"

$totalStats = @{
    TotalSubscriptions = $subscriptionReports.Count
    TotalResourceGroups = ($subscriptionReports | Measure-Object -Property {$_.Statistics.TotalResourceGroups} -Sum).Sum
    TotalResources = ($subscriptionReports | Measure-Object -Property {$_.Statistics.TotalResources} -Sum).Sum
    TotalIAMAssignments = ($subscriptionReports | Measure-Object -Property {$_.Statistics.TotalIAMAssignments} -Sum).Sum
    TotalFindings = ($subscriptionReports | ForEach-Object { $_.Findings.Count } | Measure-Object -Sum).Sum
    CriticalFindings = ($subscriptionReports | Measure-Object -Property {$_.Statistics.CriticalFindings} -Sum).Sum
    HighFindings = ($subscriptionReports | Measure-Object -Property {$_.Statistics.HighFindings} -Sum).Sum
    MediumFindings = ($subscriptionReports | Measure-Object -Property {$_.Statistics.MediumFindings} -Sum).Sum
    LowFindings = ($subscriptionReports | Measure-Object -Property {$_.Statistics.LowFindings} -Sum).Sum
}

foreach ($subReport in $subscriptionReports) {
    $subFolder = Join-Path $masterReportPath $subReport.SubscriptionName.Replace(" ", "_")
    New-Item -ItemType Directory -Path $subFolder -Force | Out-Null
    
    if ($subReport.Resources.Count -gt 0) {
        $subReport.Resources | Export-Csv -Path (Join-Path $subFolder "Resources.csv") -NoTypeInformation
    }
    if ($subReport.IAM.Count -gt 0) {
        $subReport.IAM | Export-Csv -Path (Join-Path $subFolder "IAM.csv") -NoTypeInformation
    }
    if ($subReport.Findings.Count -gt 0) {
        $subReport.Findings | Export-Csv -Path (Join-Path $subFolder "Findings.csv") -NoTypeInformation
    }
    if ($subReport.Policies.Count -gt 0) {
        $subReport.Policies | Export-Csv -Path (Join-Path $subFolder "Policies.csv") -NoTypeInformation
    }
    if ($subReport.Networking.Count -gt 0) {
        $subReport.Networking | Export-Csv -Path (Join-Path $subFolder "Networking.csv") -NoTypeInformation
    }
    if ($subReport.KeyVaults.Count -gt 0) {
        $subReport.KeyVaults | Export-Csv -Path (Join-Path $subFolder "KeyVaults.csv") -NoTypeInformation
    }
    if ($subReport.LoadBalancers.Count -gt 0) {
        $subReport.LoadBalancers | Export-Csv -Path (Join-Path $subFolder "LoadBalancers.csv") -NoTypeInformation
    }
    if ($subReport.ServicePrincipals.Count -gt 0) {
        $subReport.ServicePrincipals | Export-Csv -Path (Join-Path $subFolder "ServicePrincipals.csv") -NoTypeInformation
    }
    
    $subReport.SecurityCenter | ConvertTo-Json | Out-File -FilePath (Join-Path $subFolder "SecurityCenter.json") -Encoding UTF8
    $subReport | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $subFolder "Complete-Data.json") -Encoding UTF8
}

$allFindingsData = @()
foreach ($subReport in $subscriptionReports) {
    foreach ($finding in $subReport.Findings) {
        $allFindingsData += [PSCustomObject]@{
            Subscription = $subReport.SubscriptionName
            Severity = $finding.Severity
            Category = $finding.Category
            Resource = $finding.Resource
            Issue = $finding.Issue
            Recommendation = $finding.Recommendation
        }
    }
}

if ($allFindingsData.Count -gt 0) {
    $allFindingsPath = Join-Path $masterReportPath "All-Findings-Master.csv"
    $allFindingsData | Export-Csv -Path $allFindingsPath -NoTypeInformation
    Write-AuditLog "Master findings CSV saved: $allFindingsPath" "SUCCESS"
}

$readmePath = Join-Path $masterReportPath "README.md"
$readmeContent = @"
# Ultimate Multi-Subscription Azure Audit Report

Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")

## Summary

- Subscriptions Analyzed: $($totalStats.TotalSubscriptions)
- Total Resource Groups: $($totalStats.TotalResourceGroups)
- Total Resources: $($totalStats.TotalResources)
- IAM Assignments: $($totalStats.TotalIAMAssignments)

## Security Findings

- Total Findings: $($totalStats.TotalFindings)
- Critical: $($totalStats.CriticalFindings)
- High: $($totalStats.HighFindings)
- Medium: $($totalStats.MediumFindings)
- Low: $($totalStats.LowFindings)

## Per-Subscription Reports

Each subscription has detailed exports in its own folder with CSV files for:
- Resources
- IAM assignments
- Security findings
- Azure policies
- Network configuration
- Key Vaults
- Load Balancers
- Service Principals

---

**READ-ONLY Audit** - No changes were made to your environment
**Safe for Production** - All operations were read-only
"@

$readmeContent | Out-File -FilePath $readmePath -Encoding UTF8
Write-AuditLog "README saved: $readmePath" "SUCCESS"

$endTime = Get-Date
$duration = $endTime - $scriptStartTime

Write-Host ""
Write-Host "================================================================"
Write-Host "  AUDIT COMPLETE!"
Write-Host "================================================================"
Write-Host ""
Write-Host "MASTER SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================"
Write-Host "  Subscriptions Analyzed:    $($totalStats.TotalSubscriptions)" -ForegroundColor White
Write-Host "  Resource Groups:           $($totalStats.TotalResourceGroups)" -ForegroundColor White
Write-Host "  Total Resources:           $($totalStats.TotalResources)" -ForegroundColor White
Write-Host "  IAM Assignments:           $($totalStats.TotalIAMAssignments)" -ForegroundColor White
Write-Host ""
Write-Host "  Total Findings:            $($totalStats.TotalFindings)" -ForegroundColor Yellow
Write-Host "  - Critical:                $($totalStats.CriticalFindings)" -ForegroundColor Red
Write-Host "  - High:                    $($totalStats.HighFindings)" -ForegroundColor DarkRed
Write-Host "  - Medium:                  $($totalStats.MediumFindings)" -ForegroundColor Yellow
Write-Host "  - Low:                     $($totalStats.LowFindings)" -ForegroundColor Green
Write-Host ""
Write-Host "  Execution Time:            $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "================================================================"
Write-Host ""
Write-Host "Reports saved in: $masterReportPath" -ForegroundColor Green
Write-Host ""
Write-Host "READ-ONLY CONFIRMATION" -ForegroundColor Green
Write-Host "================================================================"
Write-Host "  This script made ZERO changes to your environment" -ForegroundColor Green
Write-Host "  All operations were read-only" -ForegroundColor Green
Write-Host "  Safe for production use" -ForegroundColor Green
Write-Host "================================================================"
Write-Host ""

Write-AuditLog "Audit complete!" "SUCCESS"
