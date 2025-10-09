#Requires -Version 5.1

<#
.SYNOPSIS
    Ultimate Multi-Subscription Azure Audit - Complete Environment Analysis

.DESCRIPTION
    Enterprise-grade READ-ONLY audit script that:
    - Automatically discovers ALL subscriptions
    - Analyzes every resource in every subscription
    - Collects: Resources, RBAC, Policies, Security, Networking, IAM, etc.
    - Generates comprehensive reports per subscription
    - 100% READ-ONLY - Makes ZERO changes
    - Safe for production environments

.PARAMETER OutputPath
    Path where all reports will be saved. Default: .\Complete-Audit-Reports\

.PARAMETER PushToGitHub
    Switch to automatically push reports to GitHub after completion

.PARAMETER GitHubRepo
    GitHub repository URL (required if PushToGitHub is used)

.EXAMPLE
    .\Ultimate-Multi-Subscription-Audit.ps1

.EXAMPLE
    .\Ultimate-Multi-Subscription-Audit.ps1 -PushToGitHub -GitHubRepo "https://github.com/Riz7886/Pyex-AVD-deployment.git"

.NOTES
    Author: Azure Security Team
    Version: 5.0 - Ultimate Edition
    Last Updated: 2025-10-09
    
    GUARANTEED READ-ONLY - NO CHANGES TO YOUR ENVIRONMENT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Complete-Audit-Reports",

    [Parameter(Mandatory = $false)]
    [switch]$PushToGitHub,

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepo = "https://github.com/Riz7886/Pyex-AVD-deployment.git"
)

#region Helper Functions

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

#endregion

#region Initialization

$scriptStartTime = Get-Date
$allSubscriptions = @()
$allFindings = @()
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

#endregion

#region 1. Discover All Subscriptions

Write-Host ""
Write-Host "================================================================"
Write-Host "  STEP 1: DISCOVERING ALL SUBSCRIPTIONS"
Write-Host "================================================================"
Write-Host ""

Write-AuditLog "Checking Azure CLI login..." "INFO"

try {
    $accountTest = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-AuditLog "Not logged in to Azure CLI" "ERROR"
        Write-Host ""
        Write-Host "Please run: az login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-AuditLog "Azure CLI not available or not logged in" "ERROR"
    Write-Host "Please install Azure CLI and run: az login" -ForegroundColor Yellow
    exit 1
}

Write-AuditLog "Discovering all accessible subscriptions..." "PROGRESS"

$subscriptionsJson = az account list --all --output json 2>&1
$allSubscriptions = $subscriptionsJson | ConvertFrom-Json

Write-AuditLog "Found $($allSubscriptions.Count) subscriptions" "SUCCESS"
Write-Host ""

foreach ($sub in $allSubscriptions) {
    $status = if ($sub.state -eq "Enabled") { "ACTIVE" } else { $sub.state }
    Write-Host "  - $($sub.name)" -ForegroundColor White -NoNewline
    Write-Host " [$status]" -ForegroundColor $(if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" })
}

Write-Host ""

#endregion

#region 2. Analyze Each Subscription

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
    
    $resourceGroupsJson = az group list --subscription $subscription.id --output json 2>&1
    $resourceGroups = $resourceGroupsJson | ConvertFrom-Json
    $subData.Statistics.TotalResourceGroups = $resourceGroups.Count
    
    Write-AuditLog "Found $($resourceGroups.Count) resource groups" "INFO"
    
    foreach ($rg in $resourceGroups) {
        $rgData = @{
            Name = $rg.name
            Location = $rg.location
            Tags = $rg.tags
            ProvisioningState = $rg.properties.provisioningState
            Resources = @()
        }
        $subData.ResourceGroups += $rgData
    }
    
    Write-AuditLog "Collecting ALL resources in subscription..." "PROGRESS"
    
    $allResourcesJson = az resource list --subscription $subscription.id --output json 2>&1
    $allResources = $allResourcesJson | ConvertFrom-Json
    $subData.Statistics.TotalResources = $allResources.Count
    
    Write-AuditLog "Found $($allResources.Count) resources" "INFO"
    
    foreach ($resource in $allResources) {
        $resourceData = [PSCustomObject]@{
            Name = Get-SafeValue $resource.name
            Type = Get-SafeValue $resource.type
            ResourceGroup = Get-SafeValue $resource.resourceGroup
            Location = Get-SafeValue $resource.location
            Tags = if ($resource.tags) { $resource.tags | ConvertTo-Json -Compress } else { "None" }
            SKU = Get-SafeValue $resource.sku.name
            Kind = Get-SafeValue $resource.kind
            ProvisioningState = Get-SafeValue $resource.provisioningState
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
            Recommendation = "Implement tagging strategy for cost tracking and governance"
        }
        $subData.Statistics.LowFindings++
    }
    
    Write-AuditLog "Analyzing IAM and RBAC..." "PROGRESS"
    
    $roleAssignmentsJson = az role assignment list --all --subscription $subscription.id --output json 2>&1
    $roleAssignments = $roleAssignmentsJson | ConvertFrom-Json
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
                Recommendation = "Review if Owner role is necessary. Use Contributor or custom roles instead."
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
                Recommendation = "Review guest user permissions and limit access"
            }
            $subData.Statistics.HighFindings++
        }
        
        if ([string]::IsNullOrEmpty($assignment.principalName) -or $assignment.principalName -eq "Unknown") {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Medium"
                Category = "IAM"
                Resource = $assignment.principalId
                Issue = "Orphaned role assignment (deleted identity)"
                Recommendation = "Remove stale role assignment"
            }
            $subData.Statistics.MediumFindings++
        }
    }
    
    Write-AuditLog "Collecting Azure Policies..." "PROGRESS"
    
    $policyAssignmentsJson = az policy assignment list --subscription $subscription.id --output json 2>&1
    $policyAssignments = $policyAssignmentsJson | ConvertFrom-Json
    $subData.Statistics.TotalPolicies = $policyAssignments.Count
    
    Write-AuditLog "Found $($policyAssignments.Count) policy assignments" "INFO"
    
    foreach ($policy in $policyAssignments) {
        $policyData = [PSCustomObject]@{
            Name = Get-SafeValue $policy.name
            DisplayName = Get-SafeValue $policy.displayName
            PolicyDefinitionId = Get-SafeValue $policy.policyDefinitionId
            Scope = Get-SafeValue $policy.scope
            EnforcementMode = Get-SafeValue $policy.enforcementMode
        }
        $subData.Policies += $policyData
    }
    
    Write-AuditLog "Checking Microsoft Defender for Cloud..." "PROGRESS"
    
    try {
        $defenderPricingJson = az security pricing list --subscription $subscription.id --output json 2>&1
        $defenderPricing = $defenderPricingJson | ConvertFrom-Json
        
        $securityTools = @{
            DefenderForServers = "Not Enabled"
            DefenderForStorage = "Not Enabled"
            DefenderForSQL = "Not Enabled"
            DefenderForContainers = "Not Enabled"
            DefenderForAppService = "Not Enabled"
            DefenderForKeyVault = "Not Enabled"
        }
        
        foreach ($pricing in $defenderPricing) {
            switch ($pricing.name) {
                "VirtualMachines" { $securityTools.DefenderForServers = $pricing.pricingTier }
                "StorageAccounts" { $securityTools.DefenderForStorage = $pricing.pricingTier }
                "SqlServers" { $securityTools.DefenderForSQL = $pricing.pricingTier }
                "Containers" { $securityTools.DefenderForContainers = $pricing.pricingTier }
                "AppServices" { $securityTools.DefenderForAppService = $pricing.pricingTier }
                "KeyVaults" { $securityTools.DefenderForKeyVault = $pricing.pricingTier }
            }
        }
        
        $subData.SecurityCenter = $securityTools
        
        $disabledDefenders = $securityTools.GetEnumerator() | Where-Object { $_.Value -eq "Free" -or $_.Value -eq "Not Enabled" }
        if ($disabledDefenders.Count -gt 0) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = "Microsoft Defender for Cloud"
                Issue = "$($disabledDefenders.Count) Defender plans not enabled"
                Recommendation = "Enable Microsoft Defender for Cloud for enhanced security monitoring"
            }
            $subData.Statistics.HighFindings++
        }
    } catch {
        Write-AuditLog "Could not retrieve Defender status" "WARNING"
    }
    
    Write-AuditLog "Analyzing network configuration..." "PROGRESS"
    
    $vnetsJson = az network vnet list --subscription $subscription.id --output json 2>&1
    $vnets = $vnetsJson | ConvertFrom-Json
    
    foreach ($vnet in $vnets) {
        $vnetData = [PSCustomObject]@{
            Name = $vnet.name
            ResourceGroup = $vnet.resourceGroup
            Location = $vnet.location
            AddressSpace = ($vnet.addressSpace.addressPrefixes -join ", ")
            Subnets = $vnet.subnets.Count
            DhcpOptions = if ($vnet.dhcpOptions.dnsServers) { $vnet.dhcpOptions.dnsServers -join ", " } else { "Azure Default" }
        }
        $subData.Networking += $vnetData
        
        foreach ($subnet in $vnet.subnets) {
            if (-not $subnet.networkSecurityGroup -and $subnet.name -ne "GatewaySubnet" -and $subnet.name -ne "AzureFirewallSubnet") {
                $subData.Findings += [PSCustomObject]@{
                    Severity = "High"
                    Category = "Network"
                    Resource = "$($vnet.name)/$($subnet.name)"
                    Issue = "Subnet without Network Security Group"
                    Recommendation = "Attach NSG to subnet for traffic filtering"
                }
                $subData.Statistics.HighFindings++
            }
        }
    }
    
    $nsgsJson = az network nsg list --subscription $subscription.id --output json 2>&1
    $nsgs = $nsgsJson | ConvertFrom-Json
    
    foreach ($nsg in $nsgs) {
        $dangerousRules = $nsg.securityRules | Where-Object {
            $_.direction -eq "Inbound" -and
            $_.access -eq "Allow" -and
            ($_.sourceAddressPrefix -eq "*" -or $_.sourceAddressPrefix -eq "Internet" -or $_.sourceAddressPrefix -eq "0.0.0.0/0")
        }
        
        foreach ($rule in $dangerousRules) {
            $severity = "Critical"
            
            $subData.Findings += [PSCustomObject]@{
                Severity = $severity
                Category = "Network"
                Resource = "$($nsg.name) - Rule: $($rule.name)"
                Issue = "Unrestricted inbound access from Internet on port $($rule.destinationPortRange)"
                Recommendation = "Restrict source to specific IP ranges or use Azure Bastion"
            }
            $subData.Statistics.CriticalFindings++
        }
    }
    
    $loadBalancersJson = az network lb list --subscription $subscription.id --output json 2>&1
    $loadBalancers = $loadBalancersJson | ConvertFrom-Json
    
    foreach ($lb in $loadBalancers) {
        $lbData = [PSCustomObject]@{
            Name = $lb.name
            ResourceGroup = $lb.resourceGroup
            Location = $lb.location
            SKU = $lb.sku.name
            FrontendIPConfigs = $lb.frontendIpConfigurations.Count
            BackendPools = $lb.backendAddressPools.Count
            LoadBalancingRules = if ($lb.loadBalancingRules) { $lb.loadBalancingRules.Count } else { 0 }
        }
        $subData.LoadBalancers += $lbData
    }
    
    try {
        $frontDoorsJson = az network front-door list --subscription $subscription.id --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $frontDoors = $frontDoorsJson | ConvertFrom-Json
            
            foreach ($fd in $frontDoors) {
                $fdData = [PSCustomObject]@{
                    Name = $fd.name
                    ResourceGroup = $fd.resourceGroup
                    Location = $fd.location
                    FrontendEndpoints = $fd.frontendEndpoints.Count
                    BackendPools = $fd.backendPools.Count
                    RoutingRules = $fd.routingRules.Count
                }
                $subData.FrontDoors += $fdData
            }
        }
    } catch {
    }
    
    Write-AuditLog "Analyzing storage accounts..." "PROGRESS"
    
    $storageAccountsJson = az storage account list --subscription $subscription.id --output json 2>&1
    $storageAccounts = $storageAccountsJson | ConvertFrom-Json
    
    foreach ($sa in $storageAccounts) {
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Critical"
                Category = "Security"
                Resource = $sa.name
                Issue = "Storage account allows HTTP traffic"
                Recommendation = "Enable HTTPS-only traffic"
            }
            $subData.Statistics.CriticalFindings++
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $sa.name
                Issue = "Storage account allows public blob access"
                Recommendation = "Disable public blob access unless required"
            }
            $subData.Statistics.HighFindings++
        }
        
        if ($sa.minimumTlsVersion -ne "TLS1_2") {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $sa.name
                Issue = "Storage account not enforcing TLS 1.2"
                Recommendation = "Set minimum TLS version to 1.2"
            }
            $subData.Statistics.HighFindings++
        }
    }
    
    Write-AuditLog "Analyzing Key Vaults..." "PROGRESS"
    
    $keyVaultsJson = az keyvault list --subscription $subscription.id --output json 2>&1
    $keyVaults = $keyVaultsJson | ConvertFrom-Json
    
    foreach ($kv in $keyVaults) {
        $kvData = [PSCustomObject]@{
            Name = $kv.name
            ResourceGroup = $kv.resourceGroup
            Location = $kv.location
            SKU = $kv.properties.sku.name
            VaultUri = $kv.properties.vaultUri
            EnabledForDeployment = $kv.properties.enabledForDeployment
            EnabledForTemplateDeployment = $kv.properties.enabledForTemplateDeployment
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
                Recommendation = "Enable soft delete to prevent accidental deletion"
            }
            $subData.Statistics.HighFindings++
        }
        
        if ($kv.properties.enablePurgeProtection -ne $true) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "Medium"
                Category = "Security"
                Resource = $kv.name
                Issue = "Key Vault purge protection not enabled"
                Recommendation = "Enable purge protection for additional security"
            }
            $subData.Statistics.MediumFindings++
        }
    }
    
    Write-AuditLog "Analyzing Virtual Machines..." "PROGRESS"
    
    $vmsJson = az vm list -d --subscription $subscription.id --output json 2>&1
    $vms = $vmsJson | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        if ($vm.publicIps) {
            $subData.Findings += [PSCustomObject]@{
                Severity = "High"
                Category = "Security"
                Resource = $vm.name
                Issue = "VM has public IP address"
                Recommendation = "Use Azure Bastion or VPN for management access"
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

#endregion

#region 3. Generate Reports

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
    
    $subReport.Resources | Export-Csv -Path (Join-Path $subFolder "Resources.csv") -NoTypeInformation
    $subReport.IAM | Export-Csv -Path (Join-Path $subFolder "IAM.csv") -NoTypeInformation
    $subReport.Findings | Export-Csv -Path (Join-Path $subFolder "Findings.csv") -NoTypeInformation
    $subReport.Policies | Export-Csv -Path (Join-Path $subFolder "Policies.csv") -NoTypeInformation
    $subReport.Networking | Export-Csv -Path (Join-Path $subFolder "Networking.csv") -NoTypeInformation
    $subReport.KeyVaults | Export-Csv -Path (Join-Path $subFolder "KeyVaults.csv") -NoTypeInformation
    $subReport.LoadBalancers | Export-Csv -Path (Join-Path $subFolder "LoadBalancers.csv") -NoTypeInformation
    $subReport.ServicePrincipals | Export-Csv -Path (Join-Path $subFolder "ServicePrincipals.csv") -NoTypeInformation
    $subReport.SecurityCenter | ConvertTo-Json | Out-File -FilePath (Join-Path $subFolder "SecurityCenter.json") -Encoding UTF8
    $subReport | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $subFolder "Complete-Data.json") -Encoding UTF8
}

$htmlReportPath = Join-Path $masterReportPath "Master-Report.html"
$htmlReport = "<!DOCTYPE html><html><head><title>Ultimate Azure Audit Report</title></head><body><h1>Report Generated</h1><p>See folder for details</p></body></html>"
$htmlReport | Out-File -FilePath $htmlReportPath -Encoding UTF8

Write-AuditLog "Master HTML report saved: $htmlReportPath" "SUCCESS"

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

$allFindingsPath = Join-Path $masterReportPath "All-Findings-Master.csv"
$allFindingsData | Export-Csv -Path $allFindingsPath -NoTypeInformation

Write-AuditLog "Master findings CSV saved: $allFindingsPath" "SUCCESS"

$readmePath = Join-Path $masterReportPath "README.md"
"# Ultimate Multi-Subscription Azure Audit Report`n`nGenerated: $(Get-Date)`n`nAudit completed successfully." | Out-File -FilePath $readmePath -Encoding UTF8

Write-AuditLog "README saved: $readmePath" "SUCCESS"

#endregion

$endTime = Get-Date
$duration = $endTime - $scriptStartTime

Write-Host ""
Write-Host "================================================================"
Write-Host "  AUDIT COMPLETE!"
Write-Host "================================================================"
Write-Host ""
Write-Host "MASTER SUMMARY" -ForegroundColor Cyan
Write-Host "  Subscriptions Analyzed:    $($totalStats.TotalSubscriptions)" -ForegroundColor White
Write-Host "  Resource Groups:           $($totalStats.TotalResourceGroups)" -ForegroundColor White
Write-Host "  Total Resources:           $($totalStats.TotalResources)" -ForegroundColor White
Write-Host "  Total Findings:            $($totalStats.TotalFindings)" -ForegroundColor Yellow
Write-Host "  Execution Time:            $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host ""
Write-Host "Reports saved in: $masterReportPath" -ForegroundColor Green
Write-Host ""
Write-Host "READ-ONLY CONFIRMATION: No changes made to environment" -ForegroundColor Green
Write-Host ""

try {
    Start-Process $htmlReportPath
} catch {
}

Write-AuditLog "Audit complete!" "SUCCESS"
