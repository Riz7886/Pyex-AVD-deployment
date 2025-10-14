#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - COMPLETE Azure Environment Audit (ENHANCED)

.DESCRIPTION
    Comprehensive audit with alerts, performance, networking, RBAC, everything
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\PYX-Health-Complete-Azure-Audit.html"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - COMPLETE AZURE ENVIRONMENT AUDIT" -ForegroundColor Cyan
Write-Host "  Including: Alerts, Performance, Networking, RBAC, Security" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI
try {
    $null = az version 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "[CHECK] Azure CLI: Installed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Azure CLI not installed!" -ForegroundColor Red
    exit 1
}

# Check login
Write-Host "[CHECK] Verifying Azure login..." -ForegroundColor Yellow
try {
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    $account = $accountJson | ConvertFrom-Json
    Write-Host "[CHECK] Logged in: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Not logged in!" -ForegroundColor Red
    exit 1
}

# Get all subscriptions
Write-Host ""
Write-Host "Getting all subscriptions..." -ForegroundColor Yellow
$subscriptionsJson = az account list -o json 2>&1
$subscriptions = $subscriptionsJson | ConvertFrom-Json
Write-Host "[INFO] Found $($subscriptions.Count) subscriptions" -ForegroundColor Cyan

# Initialize
$global:findings = @()
$global:issues = @{ Critical = 0; High = 0; Medium = 0; Low = 0 }
$global:resourceCounts = @{
    Subscriptions = $subscriptions.Count
    ResourceGroups = 0
    VMs = 0
    StorageAccounts = 0
    KeyVaults = 0
    SqlServers = 0
    SqlDatabases = 0
    AppServices = 0
    NSGs = 0
    NSGRules = 0
    VNets = 0
    Subnets = 0
    PublicIPs = 0
    LoadBalancers = 0
    AlertRules = 0
    RoleAssignments = 0
    Users = 0
    ServicePrincipals = 0
    Groups = 0
}

# Safe parser
function Get-AzResourceSafe {
    param([string]$Command)
    try {
        $output = Invoke-Expression "$Command 2>&1"
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            return @()
        }
        return ($output | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return @()
    }
}

# Add finding
function Add-Finding {
    param(
        [string]$Severity,
        [string]$Subscription,
        [string]$Resource,
        [string]$Type,
        [string]$Issue,
        [string]$Recommendation,
        [string]$Impact
    )
    
    $global:findings += [PSCustomObject]@{
        Severity = $Severity
        Subscription = $Subscription
        Resource = $Resource
        Type = $Type
        Issue = $Issue
        Recommendation = $Recommendation
        Impact = $Impact
    }
    $global:issues[$Severity]++
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host "  STARTING COMPREHENSIVE AUDIT" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow

$subCount = 0
foreach ($sub in $subscriptions) {
    $subCount++
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  SUBSCRIPTION $subCount/$($subscriptions.Count): $($sub.name)" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    
    az account set --subscription $sub.id 2>&1 | Out-Null
    
    # ============================================================
    # 1. RESOURCE GROUPS
    # ============================================================
    
    Write-Host "[1/18] Resource Groups..." -ForegroundColor Yellow
    $resourceGroups = Get-AzResourceSafe -Command "az group list -o json"
    $global:resourceCounts.ResourceGroups += $resourceGroups.Count
    Write-Host "  Found: $($resourceGroups.Count)" -ForegroundColor White
    
    foreach ($rg in $resourceGroups) {
        $resources = Get-AzResourceSafe -Command "az resource list --resource-group '$($rg.name)' -o json"
        if ($resources.Count -eq 0) {
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $rg.name -Type "Resource Group" `
                -Issue "Empty resource group" -Recommendation "Delete if not needed" -Impact "Clutter"
        }
    }
    
    # ============================================================
    # 2. VIRTUAL MACHINES
    # ============================================================
    
    Write-Host "[2/18] Virtual Machines..." -ForegroundColor Yellow
    $vms = Get-AzResourceSafe -Command "az vm list -o json"
    $global:resourceCounts.VMs += $vms.Count
    Write-Host "  Found: $($vms.Count)" -ForegroundColor White
    
    foreach ($vm in $vms) {
        # Check size optimization
        if ($vm.hardwareProfile.vmSize -match "Standard_D") {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "VM may be oversized" -Recommendation "Review utilization and downsize" -Impact "Cost savings 30-50%"
        }
        
        # Check managed disks
        if ($vm.storageProfile.osDisk.managedDisk -eq $null) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "Unmanaged disks" -Recommendation "Migrate to managed disks" -Impact "Performance issues"
        }
        
        # Check diagnostics
        $diagnostics = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($vm.id) -o json"
        if ($diagnostics.Count -eq 0) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "No diagnostic logging" -Recommendation "Enable boot diagnostics" -Impact "Limited troubleshooting"
        }
    }
    
    # ============================================================
    # 3. STORAGE ACCOUNTS
    # ============================================================
    
    Write-Host "[3/18] Storage Accounts..." -ForegroundColor Yellow
    $storageAccounts = Get-AzResourceSafe -Command "az storage account list -o json"
    $global:resourceCounts.StorageAccounts += $storageAccounts.Count
    Write-Host "  Found: $($storageAccounts.Count)" -ForegroundColor White
    
    foreach ($sa in $storageAccounts) {
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "HTTPS-only not enabled" -Recommendation "az storage account update --https-only true" -Impact "Insecure transmission"
        }
        
        if ($sa.minimumTlsVersion -ne "TLS1_2") {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "TLS 1.2 not enforced" -Recommendation "Set minimum TLS to 1.2" -Impact "Weak encryption"
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "Public blob access enabled" -Recommendation "Disable public access" -Impact "Data exposure risk"
        }
        
        if ($sa.encryption.services.blob.enabled -ne $true) {
            Add-Finding -Severity "Critical" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "Blob encryption not enabled" -Recommendation "Enable encryption" -Impact "Unencrypted data"
        }
        
        # Check firewall rules
        if ($sa.networkRuleSet.defaultAction -eq "Allow") {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "Storage accessible from all networks" -Recommendation "Configure firewall rules" -Impact "Unrestricted access"
        }
    }
    
    # ============================================================
    # 4. KEY VAULTS
    # ============================================================
    
    Write-Host "[4/18] Key Vaults..." -ForegroundColor Yellow
    $keyVaults = Get-AzResourceSafe -Command "az keyvault list -o json"
    $global:resourceCounts.KeyVaults += $keyVaults.Count
    Write-Host "  Found: $($keyVaults.Count)" -ForegroundColor White
    
    foreach ($kv in $keyVaults) {
        if ($kv.properties.enableSoftDelete -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                -Issue "Soft delete not enabled" -Recommendation "Enable soft delete" -Impact "Cannot recover deleted secrets"
        }
        
        if ($kv.properties.enablePurgeProtection -ne $true) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                -Issue "Purge protection not enabled" -Recommendation "Enable purge protection" -Impact "Can be permanently deleted"
        }
        
        if ($kv.properties.networkAcls.defaultAction -eq "Allow") {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                -Issue "Key Vault accessible from all networks" -Recommendation "Configure network restrictions" -Impact "Unrestricted access"
        }
    }
    
    # ============================================================
    # 5. SQL SERVERS & DATABASES
    # ============================================================
    
    Write-Host "[5/18] SQL Servers & Databases..." -ForegroundColor Yellow
    $sqlServers = Get-AzResourceSafe -Command "az sql server list -o json"
    $global:resourceCounts.SqlServers += $sqlServers.Count
    Write-Host "  Found: $($sqlServers.Count) servers" -ForegroundColor White
    
    foreach ($server in $sqlServers) {
        # Get databases
        $databases = Get-AzResourceSafe -Command "az sql db list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
        $global:resourceCounts.SqlDatabases += $databases.Count
        
        # Check firewall rules
        $firewallRules = Get-AzResourceSafe -Command "az sql server firewall-rule list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
        foreach ($rule in $firewallRules) {
            if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "255.255.255.255") {
                Add-Finding -Severity "Critical" -Subscription $sub.name -Resource "$($server.name)/$($rule.name)" -Type "SQL Firewall" `
                    -Issue "SQL open to entire internet" -Recommendation "Restrict to specific IPs" -Impact "Database exposed to attacks"
            }
            
            if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "0.0.0.0") {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource "$($server.name)/$($rule.name)" -Type "SQL Firewall" `
                    -Issue "Allow Azure services rule present" -Recommendation "Use VNet service endpoints instead" -Impact "Broad access"
            }
        }
        
        # Check TDE on databases
        foreach ($db in $databases) {
            if ($db.name -ne "master") {
                $tde = Get-AzResourceSafe -Command "az sql db tde show --database $($db.name) --server $($server.name) --resource-group $($server.resourceGroup) -o json"
                if ($tde.state -ne "Enabled") {
                    Add-Finding -Severity "High" -Subscription $sub.name -Resource "$($server.name)/$($db.name)" -Type "SQL Database" `
                        -Issue "TDE not enabled" -Recommendation "Enable Transparent Data Encryption" -Impact "Unencrypted at rest"
                }
            }
        }
        
        # Check auditing
        $auditing = Get-AzResourceSafe -Command "az sql server audit-policy show --name $($server.name) --resource-group $($server.resourceGroup) -o json"
        if ($auditing.state -ne "Enabled") {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $server.name -Type "SQL Server" `
                -Issue "SQL auditing not enabled" -Recommendation "Enable auditing to Log Analytics" -Impact "No audit trail"
        }
    }
    
    # ============================================================
    # 6. APP SERVICES
    # ============================================================
    
    Write-Host "[6/18] App Services..." -ForegroundColor Yellow
    $appServices = Get-AzResourceSafe -Command "az webapp list -o json"
    $global:resourceCounts.AppServices += $appServices.Count
    Write-Host "  Found: $($appServices.Count)" -ForegroundColor White
    
    foreach ($app in $appServices) {
        if ($app.httpsOnly -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                -Issue "HTTPS-only not enforced" -Recommendation "Enable HTTPS-only" -Impact "Insecure connections allowed"
        }
        
        if ($app.siteConfig.minTlsVersion -ne "1.2") {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                -Issue "TLS 1.2 not enforced" -Recommendation "Set minTlsVersion to 1.2" -Impact "Weak TLS allowed"
        }
        
        if ($app.identity -eq $null) {
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                -Issue "Managed identity not enabled" -Recommendation "Enable managed identity" -Impact "Using connection strings"
        }
    }
    
    # ============================================================
    # 7. VIRTUAL NETWORKS & SUBNETS
    # ============================================================
    
    Write-Host "[7/18] Virtual Networks & Subnets..." -ForegroundColor Yellow
    $vnets = Get-AzResourceSafe -Command "az network vnet list -o json"
    $global:resourceCounts.VNets += $vnets.Count
    Write-Host "  Found: $($vnets.Count) VNets" -ForegroundColor White
    
    foreach ($vnet in $vnets) {
        # Count subnets
        if ($vnet.subnets) {
            $global:resourceCounts.Subnets += $vnet.subnets.Count
            Write-Host "    $($vnet.name): $($vnet.subnets.Count) subnets" -ForegroundColor Gray
            
            # Check each subnet
            foreach ($subnet in $vnet.subnets) {
                if ($subnet.networkSecurityGroup -eq $null) {
                    Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "$($vnet.name)/$($subnet.name)" -Type "Subnet" `
                        -Issue "No NSG attached" -Recommendation "Attach NSG for traffic control" -Impact "No network filtering"
                }
            }
        }
        
        # Check DDoS protection
        if ($vnet.enableDdosProtection -ne $true) {
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $vnet.name -Type "VNet" `
                -Issue "DDoS Protection not enabled" -Recommendation "Enable for production VNets" -Impact "Vulnerable to DDoS"
        }
    }
    
    # ============================================================
    # 8. NETWORK SECURITY GROUPS & RULES
    # ============================================================
    
    Write-Host "[8/18] Network Security Groups..." -ForegroundColor Yellow
    $nsgs = Get-AzResourceSafe -Command "az network nsg list -o json"
    $global:resourceCounts.NSGs += $nsgs.Count
    Write-Host "  Found: $($nsgs.Count) NSGs" -ForegroundColor White
    
    foreach ($nsg in $nsgs) {
        $rules = Get-AzResourceSafe -Command "az network nsg rule list --nsg-name '$($nsg.name)' --resource-group '$($nsg.resourceGroup)' -o json"
        $global:resourceCounts.NSGRules += $rules.Count
        Write-Host "    $($nsg.name): $($rules.Count) rules" -ForegroundColor Gray
        
        foreach ($rule in $rules) {
            if ($rule.direction -eq "Inbound" -and $rule.access -eq "Allow") {
                $isWildcard = $rule.sourceAddressPrefix -in @("*", "Internet", "0.0.0.0/0", "Any")
                
                if ($isWildcard) {
                    $dangerousPorts = @("22", "3389", "1433", "3306", "5432", "1521", "27017", "445", "135", "139")
                    $portInfo = if ($rule.destinationPortRange) { $rule.destinationPortRange } else { $rule.destinationPortRanges -join "," }
                    
                    $severity = "Medium"
                    foreach ($port in $dangerousPorts) {
                        if ($portInfo -match $port) {
                            $severity = "Critical"
                            break
                        }
                    }
                    
                    Add-Finding -Severity $severity -Subscription $sub.name -Resource "$($nsg.name)/$($rule.name)" -Type "NSG Rule" `
                        -Issue "Allow from Internet on port $portInfo" -Recommendation "Restrict to specific source IPs or VPN" -Impact "Service exposed to internet"
                }
            }
        }
    }
    
    # ============================================================
    # 9. PUBLIC IP ADDRESSES
    # ============================================================
    
    Write-Host "[9/18] Public IP Addresses..." -ForegroundColor Yellow
    $publicIPs = Get-AzResourceSafe -Command "az network public-ip list -o json"
    $global:resourceCounts.PublicIPs += $publicIPs.Count
    Write-Host "  Found: $($publicIPs.Count)" -ForegroundColor White
    
    foreach ($pip in $publicIPs) {
        if ($pip.ipConfiguration -eq $null) {
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $pip.name -Type "Public IP" `
                -Issue "Unused public IP" -Recommendation "Delete to save cost" -Impact "Wasted $3/month"
        }
    }
    
    # ============================================================
    # 10. LOAD BALANCERS
    # ============================================================
    
    Write-Host "[10/18] Load Balancers..." -ForegroundColor Yellow
    $loadBalancers = Get-AzResourceSafe -Command "az network lb list -o json"
    $global:resourceCounts.LoadBalancers += $loadBalancers.Count
    Write-Host "  Found: $($loadBalancers.Count)" -ForegroundColor White
    
    foreach ($lb in $loadBalancers) {
        if ($lb.backendAddressPools.Count -eq 0) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $lb.name -Type "Load Balancer" `
                -Issue "No backend pool configured" -Recommendation "Configure backend or delete" -Impact "Unused resource"
        }
    }
    
    # ============================================================
    # 11. ALERT RULES (CPU, MEMORY, LATENCY)
    # ============================================================
    
    Write-Host "[11/18] Alert Rules..." -ForegroundColor Yellow
    $metricAlerts = Get-AzResourceSafe -Command "az monitor metrics alert list -o json"
    $activityAlerts = Get-AzResourceSafe -Command "az monitor activity-log alert list -o json"
    $totalAlerts = $metricAlerts.Count + $activityAlerts.Count
    $global:resourceCounts.AlertRules += $totalAlerts
    Write-Host "  Found: $totalAlerts alerts ($($metricAlerts.Count) metric, $($activityAlerts.Count) activity)" -ForegroundColor White
    
    if ($totalAlerts -eq 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No alert rules configured" -Recommendation "Configure alerts for CPU, memory, disk, latency" -Impact "No proactive monitoring"
    }
    
    # Check for critical metric alerts
    $hasCpuAlert = $false
    $hasMemoryAlert = $false
    $hasLatencyAlert = $false
    
    foreach ($alert in $metricAlerts) {
        if ($alert.enabled -ne $true) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $alert.name -Type "Alert Rule" `
                -Issue "Alert rule disabled" -Recommendation "Enable or delete" -Impact "Not monitoring"
        }
        
        if ($alert.criteria.allOf) {
            foreach ($criterion in $alert.criteria.allOf) {
                if ($criterion.metricName -match "CPU") { $hasCpuAlert = $true }
                if ($criterion.metricName -match "Memory") { $hasMemoryAlert = $true }
                if ($criterion.metricName -match "Latency|Response") { $hasLatencyAlert = $true }
            }
        }
    }
    
    if (-not $hasCpuAlert -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No CPU alert configured" -Recommendation "Create CPU > 85% alert" -Impact "High CPU won't be detected"
    }
    
    if (-not $hasMemoryAlert -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No memory alert configured" -Recommendation "Create low memory alert" -Impact "Memory issues won't be detected"
    }
    
    if (-not $hasLatencyAlert -and $global:resourceCounts.AppServices -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No latency alert configured" -Recommendation "Create response time > 3s alert" -Impact "Slow performance won't be detected"
    }
    
    # ============================================================
    # 12. RBAC ROLE ASSIGNMENTS
    # ============================================================
    
    Write-Host "[12/18] RBAC Role Assignments..." -ForegroundColor Yellow
    $roleAssignments = Get-AzResourceSafe -Command "az role assignment list --all -o json"
    $global:resourceCounts.RoleAssignments += $roleAssignments.Count
    Write-Host "  Found: $($roleAssignments.Count) assignments" -ForegroundColor White
    
    # Count by principal type
    $userCount = ($roleAssignments | Where-Object { $_.principalType -eq "User" }).Count
    $spCount = ($roleAssignments | Where-Object { $_.principalType -eq "ServicePrincipal" }).Count
    $groupCount = ($roleAssignments | Where-Object { $_.principalType -eq "Group" }).Count
    
    $global:resourceCounts.Users += $userCount
    $global:resourceCounts.ServicePrincipals += $spCount
    $global:resourceCounts.Groups += $groupCount
    
    Write-Host "    Users: $userCount | Service Principals: $spCount | Groups: $groupCount" -ForegroundColor Gray
    
    # Check for stale assignments
    $staleCount = 0
    foreach ($assignment in $roleAssignments) {
        if ([string]::IsNullOrEmpty($assignment.principalName)) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $assignment.roleDefinitionName -Type "RBAC" `
                -Issue "Stale assignment (deleted principal)" -Recommendation "Remove orphaned assignment" -Impact "Security hygiene"
            $staleCount++
        }
    }
    
    # Check for excessive Owner roles
    $ownerAssignments = $roleAssignments | Where-Object { $_.roleDefinitionName -eq "Owner" -and $_.principalType -eq "User" }
    if ($ownerAssignments.Count -gt 5) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "RBAC" `
            -Issue "$($ownerAssignments.Count) users with Owner role" -Recommendation "Minimize Owner role assignments" -Impact "Too many admins"
    }
    
    # Check for Contributor at subscription level
    $contributorSub = $roleAssignments | Where-Object { 
        $_.roleDefinitionName -eq "Contributor" -and 
        $_.scope -match "/subscriptions/$($sub.id)$"
    }
    if ($contributorSub.Count -gt 10) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "RBAC" `
            -Issue "$($contributorSub.Count) Contributor assignments at subscription level" -Recommendation "Scope to resource groups" -Impact "Broad permissions"
    }
    
    # ============================================================
    # 13. RESOURCE LOCKS
    # ============================================================
    
    Write-Host "[13/18] Resource Locks..." -ForegroundColor Yellow
    $locks = Get-AzResourceSafe -Command "az lock list -o json"
    
    if ($locks.Count -eq 0) {
        Add-Finding -Severity "Low" -Subscription $sub.name -Resource "Subscription" -Type "Locks" `
            -Issue "No resource locks" -Recommendation "Add CanNotDelete locks to critical resources" -Impact "Accidental deletion risk"
    } else {
        Write-Host "  Found: $($locks.Count) locks" -ForegroundColor Green
    }
    
    # ============================================================
    # 14. POLICY COMPLIANCE
    # ============================================================
    
    Write-Host "[14/18] Policy Compliance..." -ForegroundColor Yellow
    $policyStates = Get-AzResourceSafe -Command "az policy state list --filter ""isCompliant eq false"" -o json"
    
    if ($policyStates.Count -gt 0) {
        Write-Host "  Found: $($policyStates.Count) non-compliant resources" -ForegroundColor Yellow
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Policy" `
            -Issue "$($policyStates.Count) policy violations" -Recommendation "Review and remediate" -Impact "Compliance issues"
    } else {
        Write-Host "  All compliant" -ForegroundColor Green
    }
    
    # ============================================================
    # 15. SECURITY CENTER
    # ============================================================
    
    Write-Host "[15/18] Security Center..." -ForegroundColor Yellow
    $securityTasks = Get-AzResourceSafe -Command "az security task list -o json"
    
    if ($securityTasks.Count -gt 0) {
        Write-Host "  Found: $($securityTasks.Count) recommendations" -ForegroundColor Yellow
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Security" `
            -Issue "$($securityTasks.Count) security recommendations" -Recommendation "Review in Security Center" -Impact "Vulnerabilities present"
    }
    
    # ============================================================
    # 16. DIAGNOSTIC SETTINGS
    # ============================================================
    
    Write-Host "[16/18] Diagnostic Settings..." -ForegroundColor Yellow
    # Check key resources for diagnostic settings
    $resourcesWithoutDiag = 0
    
    foreach ($rg in $resourceGroups) {
        $resources = Get-AzResourceSafe -Command "az resource list --resource-group '$($rg.name)' -o json"
        foreach ($resource in $resources) {
            if ($resource.type -in @("Microsoft.Compute/virtualMachines", "Microsoft.Sql/servers", "Microsoft.Web/sites")) {
                $diag = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($resource.id) -o json"
                if ($diag.Count -eq 0) {
                    $resourcesWithoutDiag++
                }
            }
        }
    }
    
    if ($resourcesWithoutDiag -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Diagnostics" `
            -Issue "$resourcesWithoutDiag resources without diagnostic logging" -Recommendation "Enable diagnostics to Log Analytics" -Impact "Limited monitoring"
    }
    
    # ============================================================
    # 17. COST OPTIMIZATION
    # ============================================================
    
    Write-Host "[17/18] Cost Optimization..." -ForegroundColor Yellow
    
    # Check for stopped VMs still incurring costs
    foreach ($vm in $vms) {
        $vmStatus = Get-AzResourceSafe -Command "az vm get-instance-view --ids $($vm.id) --query instanceView.statuses[1].code -o json"
        if ($vmStatus -match "stopped") {
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "VM stopped but not deallocated" -Recommendation "Deallocate VM to stop costs" -Impact "Still paying for compute"
        }
    }
    
    # ============================================================
    # 18. BACKUP STATUS
    # ============================================================
    
    Write-Host "[18/18] Backup Status..." -ForegroundColor Yellow
    $vaultsJson = Get-AzResourceSafe -Command "az backup vault list -o json"
    $vaults = if ($vaultsJson) { $vaultsJson } else { @() }
    
    if ($vaults.Count -eq 0 -and $vms.Count -gt 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Backup" `
            -Issue "No backup vaults configured" -Recommendation "Configure Azure Backup for VMs" -Impact "No disaster recovery"
    }
}

# ============================================================
# GENERATE COMPREHENSIVE HTML REPORT
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  GENERATING COMPREHENSIVE REPORT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

$totalIssues = $global:issues.Critical + $global:issues.High + $global:issues.Medium + $global:issues.Low

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PYX Health - Complete Azure Audit</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f2f5; padding: 20px; }
        
        .header {
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.15);
            margin-bottom: 30px;
        }
        .header h1 { font-size: 36px; margin-bottom: 15px; }
        .header p { font-size: 16px; opacity: 0.95; margin: 5px 0; }
        
        .container { max-width: 1400px; margin: 0 auto; }
        
        .section {
            background: white;
            padding: 30px;
            margin-bottom: 25px;
            border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }
        .section h2 {
            color: #323130;
            font-size: 24px;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #0078d4;
        }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 20px;
            margin: 25px 0;
        }
        .metric {
            background: linear-gradient(135deg, #ffffff 0%, #f8f9fa 100%);
            padding: 25px;
            border-radius: 10px;
            text-align: center;
            border: 2px solid #e1dfdd;
            transition: transform 0.2s;
        }
        .metric:hover { transform: translateY(-5px); }
        .metric-value {
            font-size: 48px;
            font-weight: bold;
            margin-bottom: 8px;
        }
        .metric-label {
            font-size: 13px;
            color: #605e5c;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 600;
        }
        
        .critical { color: #d13438; }
        .high { color: #ff8c00; }
        .medium { color: #ffb900; }
        .low { color: #107c10; }
        .info { color: #0078d4; }
        
        .resource-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .resource-card {
            background: linear-gradient(135deg, #f8f9fa 0%, #e1dfdd 100%);
            padding: 20px;
            border-radius: 10px;
            border-left: 5px solid #0078d4;
            transition: all 0.3s;
        }
        .resource-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
        }
        .resource-card strong {
            display: block;
            font-size: 32px;
            color: #0078d4;
            margin-bottom: 8px;
            font-weight: 700;
        }
        .resource-card span {
            color: #605e5c;
            font-size: 14px;
            font-weight: 500;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        thead {
            background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
            color: white;
        }
        th {
            padding: 16px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        td {
            padding: 14px 16px;
            border-bottom: 1px solid #edebe9;
            font-size: 14px;
        }
        tr:hover { background: #f8f9fa; }
        
        .badge {
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 11px;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            display: inline-block;
        }
        .badge-critical { background: #fde7e9; color: #d13438; }
        .badge-high { background: #fff4ce; color: #ca5010; }
        .badge-medium { background: #fff9e6; color: #c19c00; }
        .badge-low { background: #dff6dd; color: #107c10; }
        
        .footer {
            text-align: center;
            color: #605e5c;
            margin-top: 50px;
            padding: 30px;
            background: white;
            border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }
        .footer h3 { color: #0078d4; margin-bottom: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏥 PYX HEALTH - COMPLETE AZURE ENVIRONMENT AUDIT</h1>
            <p><strong>Report Generated:</strong> $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' hh:mm:ss tt")</p>
            <p><strong>Subscriptions Audited:</strong> $($global:resourceCounts.Subscriptions)</p>
            <p><strong>Comprehensive Analysis:</strong> Security, Performance, Networking, RBAC, Alerts, Compliance</p>
        </div>
        
        <div class="section">
            <h2>📊 EXECUTIVE SUMMARY</h2>
            <div class="metrics">
                <div class="metric">
                    <div class="metric-value">$totalIssues</div>
                    <div class="metric-label">Total Issues</div>
                </div>
                <div class="metric">
                    <div class="metric-value critical">$($global:issues.Critical)</div>
                    <div class="metric-label">Critical</div>
                </div>
                <div class="metric">
                    <div class="metric-value high">$($global:issues.High)</div>
                    <div class="metric-label">High</div>
                </div>
                <div class="metric">
                    <div class="metric-value medium">$($global:issues.Medium)</div>
                    <div class="metric-label">Medium</div>
                </div>
                <div class="metric">
                    <div class="metric-value low">$($global:issues.Low)</div>
                    <div class="metric-label">Low</div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>🔧 RESOURCE INVENTORY - ALL SUBSCRIPTIONS</h2>
            <div class="resource-grid">
                <div class="resource-card">
                    <strong>$($global:resourceCounts.Subscriptions)</strong>
                    <span>Subscriptions</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.ResourceGroups)</strong>
                    <span>Resource Groups</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.VMs)</strong>
                    <span>Virtual Machines</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.StorageAccounts)</strong>
                    <span>Storage Accounts</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.KeyVaults)</strong>
                    <span>Key Vaults</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.SqlServers)</strong>
                    <span>SQL Servers</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.SqlDatabases)</strong>
                    <span>SQL Databases</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.AppServices)</strong>
                    <span>App Services</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.VNets)</strong>
                    <span>Virtual Networks</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.Subnets)</strong>
                    <span>Subnets</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.NSGs)</strong>
                    <span>Network Security Groups</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.NSGRules)</strong>
                    <span>NSG Rules</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.PublicIPs)</strong>
                    <span>Public IPs</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.LoadBalancers)</strong>
                    <span>Load Balancers</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.AlertRules)</strong>
                    <span>Alert Rules</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.RoleAssignments)</strong>
                    <span>RBAC Assignments</span>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>👥 IDENTITY & ACCESS</h2>
            <div class="metrics">
                <div class="metric">
                    <div class="metric-value info">$($global:resourceCounts.Users)</div>
                    <div class="metric-label">User Assignments</div>
                </div>
                <div class="metric">
                    <div class="metric-value info">$($global:resourceCounts.ServicePrincipals)</div>
                    <div class="metric-label">Service Principals</div>
                </div>
                <div class="metric">
                    <div class="metric-value info">$($global:resourceCounts.Groups)</div>
                    <div class="metric-label">Group Assignments</div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>🔍 DETAILED FINDINGS & RECOMMENDATIONS</h2>
            <table>
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Subscription</th>
                        <th>Resource</th>
                        <th>Type</th>
                        <th>Issue</th>
                        <th>Recommendation</th>
                        <th>Impact</th>
                    </tr>
                </thead>
                <tbody>
"@

$sortedFindings = $global:findings | Sort-Object @{Expression={
    switch ($_.Severity) {
        "Critical" { 1 }
        "High" { 2 }
        "Medium" { 3 }
        "Low" { 4 }
    }
}}

foreach ($finding in $sortedFindings) {
    $badgeClass = "badge-" + $finding.Severity.ToLower()
    $html += @"
                    <tr>
                        <td><span class="badge $badgeClass">$($finding.Severity)</span></td>
                        <td>$($finding.Subscription)</td>
                        <td><strong>$($finding.Resource)</strong></td>
                        <td>$($finding.Type)</td>
                        <td>$($finding.Issue)</td>
                        <td>$($finding.Recommendation)</td>
                        <td>$($finding.Impact)</td>
                    </tr>
"@
}

$html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <h3>🏥 PYX HEALTH - AZURE INFRASTRUCTURE AUDIT</h3>
            <p>Comprehensive audit of $($global:resourceCounts.Subscriptions) subscriptions</p>
            <p><strong>Total Resources Analyzed:</strong> $(
                $global:resourceCounts.VMs + 
                $global:resourceCounts.StorageAccounts + 
                $global:resourceCounts.SqlDatabases + 
                $global:resourceCounts.AppServices + 
                $global:resourceCounts.VNets + 
                $global:resourceCounts.NSGs
            )</p>
            <p><strong>Coverage:</strong> Security, Networking, RBAC, Alerts, Performance, Compliance</p>
            <p style="margin-top: 20px; font-size: 12px; color: #999;">
                Report includes: VM optimization, Storage security, Network firewalls, SQL hardening, 
                RBAC analysis, Alert configuration, Subnet mapping, NSG rules, Load balancer health
            </p>
        </div>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  ✅ COMPREHENSIVE AUDIT COMPLETE" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 SUMMARY:" -ForegroundColor Cyan
Write-Host "  Subscriptions: $($global:resourceCounts.Subscriptions)" -ForegroundColor White
Write-Host "  Resource Groups: $($global:resourceCounts.ResourceGroups)" -ForegroundColor White
Write-Host "  VMs: $($global:resourceCounts.VMs)" -ForegroundColor White
Write-Host "  Storage Accounts: $($global:resourceCounts.StorageAccounts)" -ForegroundColor White
Write-Host "  VNets: $($global:resourceCounts.VNets)" -ForegroundColor White
Write-Host "  Subnets: $($global:resourceCounts.Subnets)" -ForegroundColor White
Write-Host "  NSGs: $($global:resourceCounts.NSGs)" -ForegroundColor White
Write-Host "  NSG Rules: $($global:resourceCounts.NSGRules)" -ForegroundColor White
Write-Host "  Alert Rules: $($global:resourceCounts.AlertRules)" -ForegroundColor White
Write-Host "  RBAC Assignments: $($global:resourceCounts.RoleAssignments)" -ForegroundColor White
Write-Host ""
Write-Host "🔍 ISSUES FOUND:" -ForegroundColor Cyan
Write-Host "  Total: $totalIssues" -ForegroundColor White
Write-Host "  Critical: $($global:issues.Critical)" -ForegroundColor Red
Write-Host "  High: $($global:issues.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($global:issues.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($global:issues.Low)" -ForegroundColor Green
Write-Host ""
Write-Host "📄 REPORT SAVED:" -ForegroundColor Cyan
Write-Host "  $OutputPath" -ForegroundColor White
Write-Host ""
Write-Host "🚀 Open in browser to impress your client!" -ForegroundColor Green
Write-Host ""
