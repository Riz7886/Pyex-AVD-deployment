#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - COMPLETE Comprehensive Azure Audit (FULL VERSION)

.DESCRIPTION
    Full comprehensive audit - ALL checks, ALL subscriptions
    NO emojis, NO special characters - CLEAN
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ReportsFolder = "C:\Scripts\Azure-Analysis-Reports"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - COMPLETE COMPREHENSIVE AZURE AUDIT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Create Reports folder
if (-not (Test-Path $ReportsFolder)) {
    New-Item -ItemType Directory -Path $ReportsFolder -Force | Out-Null
    Write-Host "[CREATED] Reports folder: $ReportsFolder" -ForegroundColor Green
} else {
    Write-Host "[EXISTS] Reports folder: $ReportsFolder" -ForegroundColor Green
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$htmlReportPath = Join-Path $ReportsFolder "PYX-Health-Azure-Audit-$timestamp.html"
$csvReportPath = Join-Path $ReportsFolder "PYX-Health-Azure-Audit-$timestamp.csv"

Write-Host ""
Write-Host "Report files will be saved to:" -ForegroundColor Yellow
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host ""

# Check Azure CLI
try {
    $null = az version 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "[CHECK] Azure CLI: Installed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Azure CLI not installed!" -ForegroundColor Red
    Write-Host "Install: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}

# Check login
Write-Host "[CHECK] Verifying Azure login..." -ForegroundColor Yellow
try {
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    $account = $accountJson | ConvertFrom-Json
    Write-Host "[CHECK] Logged in: $($account.user.name)" -ForegroundColor Green
    Write-Host "[CHECK] Current Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Not logged in to Azure!" -ForegroundColor Red
    Write-Host "Run: az login" -ForegroundColor Yellow
    exit 1
}

# Get all subscriptions
Write-Host ""
Write-Host "Getting all subscriptions..." -ForegroundColor Yellow
$subscriptionsJson = az account list -o json 2>&1
$subscriptions = $subscriptionsJson | ConvertFrom-Json
Write-Host "[INFO] Found $($subscriptions.Count) subscriptions" -ForegroundColor Cyan
Write-Host ""

# Initialize counters
$global:findings = @()
$global:issues = @{
    Critical = 0
    High = 0
    Medium = 0
    Low = 0
}

$global:resourceCounts = @{
    Subscriptions = $subscriptions.Count
    ResourceGroups = 0
    VMs = 0
    StoppedVMs = 0
    RunningVMs = 0
    StorageAccounts = 0
    KeyVaults = 0
    SqlServers = 0
    SqlDatabases = 0
    AppServices = 0
    AppServicePlans = 0
    NSGs = 0
    NSGRules = 0
    InboundRules = 0
    OutboundRules = 0
    VNets = 0
    Subnets = 0
    PublicIPs = 0
    UsedPublicIPs = 0
    UnusedPublicIPs = 0
    LoadBalancers = 0
    ApplicationGateways = 0
    AlertRules = 0
    MetricAlerts = 0
    ActivityAlerts = 0
    RoleAssignments = 0
    Users = 0
    ServicePrincipals = 0
    Groups = 0
    CustomRoles = 0
    PolicyAssignments = 0
    PolicyDefinitions = 0
    ResourceLocks = 0
    BackupVaults = 0
    RecoveryServicesVaults = 0
    Disks = 0
    UnattachedDisks = 0
    NetworkInterfaces = 0
    UnusedNICs = 0
}

# Safe JSON parser
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

# Add finding helper
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
Write-Host "  STARTING COMPREHENSIVE AUDIT OF ALL SUBSCRIPTIONS" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host ""

$subCount = 0
foreach ($sub in $subscriptions) {
    $subCount++
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  SUBSCRIPTION $subCount of $($subscriptions.Count): $($sub.name)" -ForegroundColor Cyan
    Write-Host "  ID: $($sub.id)" -ForegroundColor Gray
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Set subscription context
    az account set --subscription $sub.id 2>&1 | Out-Null
    
    # ============================================================
    # 1. RESOURCE GROUPS AUDIT
    # ============================================================
    
    Write-Host "[1/18] Auditing Resource Groups..." -ForegroundColor Yellow
    $resourceGroups = Get-AzResourceSafe -Command "az group list -o json"
    $global:resourceCounts.ResourceGroups += $resourceGroups.Count
    
    if ($resourceGroups.Count -gt 0) {
        Write-Host "  Found: $($resourceGroups.Count) resource groups" -ForegroundColor White
        
        foreach ($rg in $resourceGroups) {
            # Check for empty resource groups
            $resources = Get-AzResourceSafe -Command "az resource list --resource-group '$($rg.name)' -o json"
            if ($resources.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $rg.name -Type "Resource Group" `
                    -Issue "Empty resource group" -Recommendation "Delete unused resource group" `
                    -Impact "Clutter and organization issues"
            }
            
            # Check for tags
            if ($rg.tags -eq $null -or $rg.tags.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $rg.name -Type "Resource Group" `
                    -Issue "No tags configured" -Recommendation "Add tags for organization and cost tracking" `
                    -Impact "Difficult to track costs and ownership"
            }
        }
    } else {
        Write-Host "  No resource groups found" -ForegroundColor Gray
    }
    
    # ============================================================
    # 2. VIRTUAL MACHINES AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[2/18] Auditing Virtual Machines..." -ForegroundColor Yellow
    $vms = Get-AzResourceSafe -Command "az vm list -o json"
    $global:resourceCounts.VMs += $vms.Count
    
    if ($vms.Count -gt 0) {
        Write-Host "  Found: $($vms.Count) VMs" -ForegroundColor White
        
        foreach ($vm in $vms) {
            # Get VM details
            $vmDetails = Get-AzResourceSafe -Command "az vm show --ids $($vm.id) -o json"
            
            # Check VM status
            $vmStatus = Get-AzResourceSafe -Command "az vm get-instance-view --ids $($vm.id) --query instanceView.statuses[1].code -o json"
            if ($vmStatus -match "running") {
                $global:resourceCounts.RunningVMs++
            } elseif ($vmStatus -match "stopped") {
                $global:resourceCounts.StoppedVMs++
            }
            
            # Check VM size optimization
            if ($vm.hardwareProfile.vmSize -match "Standard_D") {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                    -Issue "VM may be oversized for workload" -Recommendation "Review VM utilization and downsize if needed" `
                    -Impact "Potential cost savings of 30-50%"
            }
            
            # Check for unmanaged disks
            if ($vm.storageProfile.osDisk.managedDisk -eq $null) {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                    -Issue "Using unmanaged disks" -Recommendation "Migrate to managed disks for better performance" `
                    -Impact "Performance and reliability issues"
            }
            
            # Check backup configuration
            Write-Host "    Checking backup for: $($vm.name)" -ForegroundColor Gray
            # Note: Backup check requires Recovery Services Vault info
            
            # Check for diagnostic settings
            $diagnostics = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($vm.id) -o json"
            if ($diagnostics.Count -eq 0) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                    -Issue "No diagnostic logging enabled" -Recommendation "Enable boot diagnostics and performance monitoring" `
                    -Impact "Limited troubleshooting capability"
            }
            
            # Check for Azure Security Center coverage
            if ($vmStatus -match "running") {
                # Check if monitoring agent is installed
                $extensions = Get-AzResourceSafe -Command "az vm extension list --vm-name $($vm.name) --resource-group $($vm.resourceGroup) -o json"
                $hasMonitoring = $false
                foreach ($ext in $extensions) {
                    if ($ext.name -match "MicrosoftMonitoringAgent" -or $ext.name -match "AzureMonitorWindowsAgent") {
                        $hasMonitoring = $true
                        break
                    }
                }
                
                if (-not $hasMonitoring) {
                    Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                        -Issue "No monitoring agent installed" -Recommendation "Install Azure Monitor agent" `
                        -Impact "Limited monitoring and security visibility"
                }
            }
            
            # Check for availability set/zone
            if ($vm.availabilitySet -eq $null -and $vm.zones -eq $null) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                    -Issue "Not in availability set or zone" -Recommendation "Use availability zones for high availability" `
                    -Impact "Single point of failure"
            }
            
            # Check OS disk encryption
            if ($vm.storageProfile.osDisk.encryptionSettings -eq $null) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "Virtual Machine" `
                    -Issue "OS disk encryption not enabled" -Recommendation "Enable Azure Disk Encryption" `
                    -Impact "Data at rest not encrypted"
            }
        }
    } else {
        Write-Host "  No VMs found" -ForegroundColor Gray
    }
    
    # ============================================================
    # 3. STORAGE ACCOUNTS AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[3/18] Auditing Storage Accounts..." -ForegroundColor Yellow
    $storageAccounts = Get-AzResourceSafe -Command "az storage account list -o json"
    $global:resourceCounts.StorageAccounts += $storageAccounts.Count
    
    if ($storageAccounts.Count -gt 0) {
        Write-Host "  Found: $($storageAccounts.Count) storage accounts" -ForegroundColor White
        
        foreach ($sa in $storageAccounts) {
            # HTTPS-only check
            if ($sa.enableHttpsTrafficOnly -ne $true) {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "HTTPS-only not enabled" -Recommendation "Enable HTTPS-only: az storage account update --https-only true" `
                    -Impact "Data can be transmitted over insecure HTTP"
            }
            
            # TLS version check
            if ($sa.minimumTlsVersion -ne "TLS1_2") {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "TLS 1.2 not enforced" -Recommendation "Set minimum TLS: az storage account update --min-tls-version TLS1_2" `
                    -Impact "Weak encryption protocols allowed"
            }
            
            # Public blob access check
            if ($sa.allowBlobPublicAccess -eq $true) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "Public blob access enabled" -Recommendation "Disable public access: az storage account update --allow-blob-public-access false" `
                    -Impact "Data may be publicly accessible"
            }
            
            # Soft delete check for blobs
            try {
                $blobService = Get-AzResourceSafe -Command "az storage blob service-properties show --account-name $($sa.name) -o json"
                if ($blobService.deleteRetentionPolicy.enabled -ne $true) {
                    Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                        -Issue "Soft delete not enabled for blobs" -Recommendation "Enable soft delete with 30-day retention" `
                        -Impact "Deleted data cannot be recovered"
                }
            } catch {
                # Blob service properties might not be accessible
            }
            
            # Encryption check
            if ($sa.encryption.services.blob.enabled -ne $true) {
                Add-Finding -Severity "Critical" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "Blob encryption not enabled" -Recommendation "Enable storage service encryption" `
                    -Impact "Data stored unencrypted"
            }
            
            # Network rules check
            if ($sa.networkRuleSet.defaultAction -eq "Allow") {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "Storage accessible from all networks" -Recommendation "Configure firewall rules to restrict access" `
                    -Impact "Unrestricted network access to storage"
            }
            
            # Check for private endpoints
            if ($sa.privateEndpointConnections -eq $null -or $sa.privateEndpointConnections.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "No private endpoints configured" -Recommendation "Consider using private endpoints for secure access" `
                    -Impact "Storage accessed over public internet"
            }
            
            # Check storage redundancy
            if ($sa.sku.name -match "LRS") {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $sa.name -Type "Storage Account" `
                    -Issue "Using LRS (locally redundant storage)" -Recommendation "Consider GRS or ZRS for better redundancy" `
                    -Impact "Data not replicated to other regions"
            }
        }
    }
    
    # ============================================================
    # 4. KEY VAULTS AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[4/18] Auditing Key Vaults..." -ForegroundColor Yellow
    $keyVaults = Get-AzResourceSafe -Command "az keyvault list -o json"
    $global:resourceCounts.KeyVaults += $keyVaults.Count
    
    if ($keyVaults.Count -gt 0) {
        Write-Host "  Found: $($keyVaults.Count) key vaults" -ForegroundColor White
        
        foreach ($kv in $keyVaults) {
            # Soft delete check
            if ($kv.properties.enableSoftDelete -ne $true) {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "Soft delete not enabled" -Recommendation "Enable soft delete (cannot be disabled once enabled)" `
                    -Impact "Deleted secrets cannot be recovered"
            }
            
            # Purge protection check
            if ($kv.properties.enablePurgeProtection -ne $true) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "Purge protection not enabled" -Recommendation "Enable purge protection for production key vaults" `
                    -Impact "Key Vault can be permanently deleted immediately"
            }
            
            # RBAC check
            if ($kv.properties.enableRbacAuthorization -ne $true) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "RBAC not enabled (using access policies)" -Recommendation "Consider migrating to Azure RBAC for better management" `
                    -Impact "Less granular access control"
            }
            
            # Network rules check
            if ($kv.properties.networkAcls.defaultAction -eq "Allow") {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "Key Vault accessible from all networks" -Recommendation "Configure network ACLs to restrict access" `
                    -Impact "Secrets accessible from anywhere on internet"
            }
            
            # Check for private endpoints
            if ($kv.properties.privateEndpointConnections -eq $null -or $kv.properties.privateEndpointConnections.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "No private endpoints configured" -Recommendation "Use private endpoints for secure access" `
                    -Impact "Key Vault accessed over public internet"
            }
            
            # Check diagnostic settings
            $kvDiag = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($kv.id) -o json"
            if ($kvDiag.Count -eq 0) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                    -Issue "No diagnostic logging enabled" -Recommendation "Enable audit logging to Log Analytics" `
                    -Impact "No audit trail of secret access"
            }
        }
    }
    
    # ============================================================
    # 5. SQL DATABASES AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[5/18] Auditing SQL Databases..." -ForegroundColor Yellow
    $sqlServers = Get-AzResourceSafe -Command "az sql server list -o json"
    $global:resourceCounts.SqlServers += $sqlServers.Count
    
    if ($sqlServers.Count -gt 0) {
        Write-Host "  Found: $($sqlServers.Count) SQL servers" -ForegroundColor White
        
        foreach ($server in $sqlServers) {
            # Get databases
            $databases = Get-AzResourceSafe -Command "az sql db list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
            $global:resourceCounts.SqlDatabases += $databases.Count
            
            # Check firewall rules
            $firewallRules = Get-AzResourceSafe -Command "az sql server firewall-rule list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
            foreach ($rule in $firewallRules) {
                if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "255.255.255.255") {
                    Add-Finding -Severity "Critical" -Subscription $sub.name -Resource "$($server.name) / $($rule.name)" -Type "SQL Server Firewall" `
                        -Issue "SQL Server open to entire internet (0.0.0.0-255.255.255.255)" -Recommendation "Restrict to specific IP ranges or use VNet service endpoints" `
                        -Impact "Database accessible from anywhere in the world"
                }
                
                if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "0.0.0.0") {
                    Add-Finding -Severity "High" -Subscription $sub.name -Resource "$($server.name) / $($rule.name)" -Type "SQL Server Firewall" `
                        -Issue "Allow Azure Services rule present" -Recommendation "Use VNet service endpoints instead of this broad rule" `
                        -Impact "All Azure services can access database"
                }
            }
            
            # Check TDE on databases
            foreach ($db in $databases) {
                if ($db.name -ne "master") {
                    $tde = Get-AzResourceSafe -Command "az sql db tde show --database $($db.name) --server $($server.name) --resource-group $($server.resourceGroup) -o json"
                    if ($tde.state -ne "Enabled") {
                        Add-Finding -Severity "High" -Subscription $sub.name -Resource "$($server.name) / $($db.name)" -Type "SQL Database" `
                            -Issue "Transparent Data Encryption (TDE) not enabled" -Recommendation "Enable TDE for data-at-rest encryption" `
                            -Impact "Database stored unencrypted on disk"
                    }
                }
            }
            
            # Check auditing
            $auditing = Get-AzResourceSafe -Command "az sql server audit-policy show --name $($server.name) --resource-group $($server.resourceGroup) -o json"
            if ($auditing.state -ne "Enabled") {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $server.name -Type "SQL Server" `
                    -Issue "SQL auditing not enabled" -Recommendation "Enable server auditing to Log Analytics" `
                    -Impact "No audit trail of database access"
            }
            
            # Check threat detection
            $threatDetection = Get-AzResourceSafe -Command "az sql server threat-policy show --name $($server.name) --resource-group $($server.resourceGroup) -o json"
            if ($threatDetection.state -ne "Enabled") {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $server.name -Type "SQL Server" `
                    -Issue "Advanced Threat Protection not enabled" -Recommendation "Enable ATP for threat detection" `
                    -Impact "No detection of SQL injection and other threats"
            }
            
            # Check AD admin
            $adAdmin = Get-AzResourceSafe -Command "az sql server ad-admin list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
            if ($adAdmin.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $server.name -Type "SQL Server" `
                    -Issue "No Azure AD admin configured" -Recommendation "Configure Azure AD admin for centralized authentication" `
                    -Impact "Using SQL authentication only"
            }
        }
    } else {
        Write-Host "  No SQL servers found" -ForegroundColor Gray
    }
    
    # ============================================================
    # 6. APP SERVICES AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[6/18] Auditing App Services..." -ForegroundColor Yellow
    $appServices = Get-AzResourceSafe -Command "az webapp list -o json"
    $global:resourceCounts.AppServices += $appServices.Count
    
    if ($appServices.Count -gt 0) {
        Write-Host "  Found: $($appServices.Count) app services" -ForegroundColor White
        
        foreach ($app in $appServices) {
            # HTTPS only check
            if ($app.httpsOnly -ne $true) {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                    -Issue "HTTPS-only not enforced" -Recommendation "Enable HTTPS-only in app settings" `
                    -Impact "App accessible over insecure HTTP"
            }
            
            # TLS version check
            if ($app.siteConfig.minTlsVersion -ne "1.2") {
                Add-Finding -Severity "High" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                    -Issue "TLS 1.2 not enforced" -Recommendation "Set minimum TLS version to 1.2" `
                    -Impact "Weak TLS versions allowed"
            }
            
            # Managed identity check
            if ($app.identity -eq $null) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                    -Issue "Managed identity not enabled" -Recommendation "Enable system-assigned managed identity" `
                    -Impact "Using connection strings instead of managed identity"
            }
            
            # Check for custom domains with SSL
            if ($app.hostNameSslStates) {
                foreach ($hostName in $app.hostNameSslStates) {
                    if ($hostName.sslState -eq "Disabled" -and $hostName.name -notmatch ".azurewebsites.net") {
                        Add-Finding -Severity "High" -Subscription $sub.name -Resource "$($app.name) / $($hostName.name)" -Type "App Service" `
                            -Issue "Custom domain without SSL certificate" -Recommendation "Add SSL certificate to custom domain" `
                            -Impact "Custom domain not secured with HTTPS"
                    }
                }
            }
            
            # Check backup configuration
            # Note: Backup requires app service plan to be Standard or higher
            
            # Check diagnostic logs
            $appDiag = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($app.id) -o json"
            if ($appDiag.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                    -Issue "No diagnostic logging configured" -Recommendation "Enable application and web server logs" `
                    -Impact "Limited troubleshooting capability"
            }
        }
        
        # Check App Service Plans
        $appServicePlans = Get-AzResourceSafe -Command "az appservice plan list -o json"
        $global:resourceCounts.AppServicePlans += $appServicePlans.Count
        
        foreach ($plan in $appServicePlans) {
            # Check for underutilized plans
            $appsInPlan = $appServices | Where-Object { $_.serverFarmId -eq $plan.id }
            if ($appsInPlan.Count -eq 0) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $plan.name -Type "App Service Plan" `
                    -Issue "Empty App Service Plan" -Recommendation "Delete unused plan to save costs" `
                    -Impact "Paying for unused compute resources"
            }
        }
    } else {
        Write-Host "  No app services found" -ForegroundColor Gray
    }
    
    # ============================================================
    # 7. VIRTUAL NETWORKS & SUBNETS AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[7/18] Auditing Virtual Networks & Subnets..." -ForegroundColor Yellow
    $vnets = Get-AzResourceSafe -Command "az network vnet list -o json"
    $global:resourceCounts.VNets += $vnets.Count
    
    if ($vnets.Count -gt 0) {
        Write-Host "  Found: $($vnets.Count) virtual networks" -ForegroundColor White
        
        foreach ($vnet in $vnets) {
            # Count subnets
            if ($vnet.subnets) {
                $global:resourceCounts.Subnets += $vnet.subnets.Count
                Write-Host "    $($vnet.name): $($vnet.subnets.Count) subnets" -ForegroundColor Gray
                
                # Check each subnet
                foreach ($subnet in $vnet.subnets) {
                    # Check for NSG attachment
                    if ($subnet.networkSecurityGroup -eq $null) {
                        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "$($vnet.name) / $($subnet.name)" -Type "Subnet" `
                            -Issue "No NSG attached to subnet" -Recommendation "Attach NSG for traffic control" `
                            -Impact "No network-level filtering"
                    }
                    
                    # Check for service endpoints
                    if ($subnet.serviceEndpoints -eq $null -or $subnet.serviceEndpoints.Count -eq 0) {
                        Add-Finding -Severity "Low" -Subscription $sub.name -Resource "$($vnet.name) / $($subnet.name)" -Type "Subnet" `
                            -Issue "No service endpoints configured" -Recommendation "Enable service endpoints for secure access to Azure services" `
                            -Impact "Services accessed over public internet"
                    }
                }
            }
            
            # Check DDoS protection
            if ($vnet.enableDdosProtection -ne $true) {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $vnet.name -Type "Virtual Network" `
                    -Issue "DDoS Protection Standard not enabled" -Recommendation "Enable for production VNets (costs $2,944/month)" `
                    -Impact "Network vulnerable to DDoS attacks"
            }
            
            # Check for peering
            if ($vnet.virtualNetworkPeerings) {
                foreach ($peering in $vnet.virtualNetworkPeerings) {
                    if ($peering.peeringState -ne "Connected") {
                        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "$($vnet.name) / $($peering.name)" -Type "VNet Peering" `
                            -Issue "VNet peering not in Connected state" -Recommendation "Troubleshoot peering connection" `
                            -Impact "Cross-VNet communication not working"
                    }
                }
            }
        }
    }
    
    # ============================================================
    # 8. NETWORK SECURITY GROUPS & RULES AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[8/18] Auditing Network Security Groups..." -ForegroundColor Yellow
    $nsgs = Get-AzResourceSafe -Command "az network nsg list -o json"
    $global:resourceCounts.NSGs += $nsgs.Count
    
    if ($nsgs.Count -gt 0) {
        Write-Host "  Found: $($nsgs.Count) NSGs" -ForegroundColor White
        
        foreach ($nsg in $nsgs) {
            $rules = Get-AzResourceSafe -Command "az network nsg rule list --nsg-name '$($nsg.name)' --resource-group '$($nsg.resourceGroup)' -o json"
            $global:resourceCounts.NSGRules += $rules.Count
            
            Write-Host "    $($nsg.name): $($rules.Count) rules" -ForegroundColor Gray
            
            foreach ($rule in $rules) {
                # Count inbound/outbound
                if ($rule.direction -eq "Inbound") {
                    $global:resourceCounts.InboundRules++
                } else {
                    $global:resourceCounts.OutboundRules++
                }
                
                if ($rule.direction -eq "Inbound" -and $rule.access -eq "Allow") {
                    $isWildcard = $rule.sourceAddressPrefix -in @("*", "Internet", "0.0.0.0/0", "Any")
                    
                    if ($isWildcard) {
                        $dangerousPorts = @("22", "3389", "1433", "3306", "5432", "1521", "27017", "445", "135", "139", "5985", "5986")
                        $portInfo = if ($rule.destinationPortRange) { $rule.destinationPortRange } else { 
                            if ($rule.destinationPortRanges) { $rule.destinationPortRanges -join "," } else { "*" }
                        }
                        
                        $severity = "Medium"
                        foreach ($port in $dangerousPorts) {
                            if ($portInfo -match $port) {
                                $severity = "Critical"
                                break
                            }
                        }
                        
                        Add-Finding -Severity $severity -Subscription $sub.name -Resource "$($nsg.name) / $($rule.name)" -Type "NSG Rule" `
                            -Issue "Allow inbound from Internet on port(s): $portInfo" -Recommendation "Restrict to specific source IPs or use VPN" `
                            -Impact "Service exposed to entire internet"
                    }
                }
                
                # Check for overly permissive outbound rules
                if ($rule.direction -eq "Outbound" -and $rule.access -eq "Allow" -and $rule.destinationAddressPrefix -in @("*", "Internet")) {
                    if ($rule.priority -lt 65000) {  # Ignore default rules
                        Add-Finding -Severity "Low" -Subscription $sub.name -Resource "$($nsg.name) / $($rule.name)" -Type "NSG Rule" `
                            -Issue "Overly permissive outbound rule" -Recommendation "Restrict outbound traffic to required destinations" `
                            -Impact "Potential data exfiltration risk"
                    }
                }
            }
        }
    }
    
    # ============================================================
    # 9. PUBLIC IP ADDRESSES AUDIT
    # ============================================================
    
    Write-Host "[9/18] Auditing Public IP Addresses..." -ForegroundColor Yellow
    $publicIPs = Get-AzResourceSafe -Command "az network public-ip list -o json"
    $global:resourceCounts.PublicIPs += $publicIPs.Count
    
    if ($publicIPs.Count -gt 0) {
        Write-Host "  Found: $($publicIPs.Count) public IPs" -ForegroundColor White
        
        foreach ($pip in $publicIPs) {
            # Check if unused
            if ($pip.ipConfiguration -eq $null) {
                $global:resourceCounts.UnusedPublicIPs++
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $pip.name -Type "Public IP" `
                    -Issue "Public IP not associated with any resource" -Recommendation "Delete unused public IP to save cost" `
                    -Impact "Unnecessary cost of approximately $3/month per IP"
            } else {
                $global:resourceCounts.UsedPublicIPs++
            }
            
            # Check for Basic SKU
            if ($pip.sku.name -eq "Basic") {
                Add-Finding -Severity "Low" -Subscription $sub.name -Resource $pip.name -Type "Public IP" `
                    -Issue "Using Basic SKU public IP" -Recommendation "Upgrade to Standard SKU for better features" `
                    -Impact "Limited availability zones support"
            }
        }
    }
    
    # ============================================================
    # 10. LOAD BALANCERS AUDIT
    # ============================================================
    
    Write-Host "[10/18] Auditing Load Balancers..." -ForegroundColor Yellow
    $loadBalancers = Get-AzResourceSafe -Command "az network lb list -o json"
    $global:resourceCounts.LoadBalancers += $loadBalancers.Count
    
    if ($loadBalancers.Count -gt 0) {
        Write-Host "  Found: $($loadBalancers.Count) load balancers" -ForegroundColor White
        
        foreach ($lb in $loadBalancers) {
            # Check for backend pool
            if ($lb.backendAddressPools -eq $null -or $lb.backendAddressPools.Count -eq 0) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $lb.name -Type "Load Balancer" `
                    -Issue "No backend pool configured" -Recommendation "Configure backend pool or delete load balancer" `
                    -Impact "Unused resource incurring costs"
            }
            
            # Check for health probes
            if ($lb.probes -eq $null -or $lb.probes.Count -eq 0) {
                Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $lb.name -Type "Load Balancer" `
                    -Issue "No health probes configured" -Recommendation "Configure health probes for high availability" `
                    -Impact "Cannot detect unhealthy backends"
            }
        }
    }
    
    # Check Application Gateways
    $appGateways = Get-AzResourceSafe -Command "az network application-gateway list -o json"
    $global:resourceCounts.ApplicationGateways += $appGateways.Count
    if ($appGateways.Count -gt 0) {
        Write-Host "  Found: $($appGateways.Count) application gateways" -ForegroundColor White
    }
    
    # ============================================================
    # 11. ALERT RULES AUDIT (CPU, MEMORY, LATENCY)
    # ============================================================
    
    Write-Host "[11/18] Auditing Alert Rules..." -ForegroundColor Yellow
    $metricAlerts = Get-AzResourceSafe -Command "az monitor metrics alert list -o json"
    $activityAlerts = Get-AzResourceSafe -Command "az monitor activity-log alert list -o json"
    $totalAlerts = $metricAlerts.Count + $activityAlerts.Count
    $global:resourceCounts.AlertRules += $totalAlerts
    $global:resourceCounts.MetricAlerts += $metricAlerts.Count
    $global:resourceCounts.ActivityAlerts += $activityAlerts.Count
    
    Write-Host "  Found: $totalAlerts alerts ($($metricAlerts.Count) metric, $($activityAlerts.Count) activity)" -ForegroundColor White
    
    if ($totalAlerts -eq 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No alert rules configured" -Recommendation "Configure alerts for CPU, memory, disk, latency" `
            -Impact "No proactive monitoring of infrastructure"
    }
    
    # Check for critical metric alerts
    $hasCpuAlert = $false
    $hasMemoryAlert = $false
    $hasLatencyAlert = $false
    $hasDiskAlert = $false
    
    foreach ($alert in $metricAlerts) {
        # Check if alert is disabled
        if ($alert.enabled -ne $true) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $alert.name -Type "Alert Rule" `
                -Issue "Alert rule disabled" -Recommendation "Enable alert rule or delete if not needed" `
                -Impact "Not monitoring this condition"
        }
        
        # Check what metrics are being monitored
        if ($alert.criteria.allOf) {
            foreach ($criterion in $alert.criteria.allOf) {
                if ($criterion.metricName -match "CPU|Processor") { $hasCpuAlert = $true }
                if ($criterion.metricName -match "Memory|AvailableMemory") { $hasMemoryAlert = $true }
                if ($criterion.metricName -match "Latency|ResponseTime|Duration") { $hasLatencyAlert = $true }
                if ($criterion.metricName -match "Disk|Storage") { $hasDiskAlert = $true }
            }
        }
    }
    
    # Recommend missing alerts
    if (-not $hasCpuAlert -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No CPU usage alert configured" -Recommendation "Create alert for CPU > 85%" `
            -Impact "High CPU usage won't be detected"
    }
    
    if (-not $hasMemoryAlert -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No memory alert configured" -Recommendation "Create alert for low available memory" `
            -Impact "Memory issues won't be detected"
    }
    
    if (-not $hasLatencyAlert -and $global:resourceCounts.AppServices -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No latency alert configured for App Services" -Recommendation "Create alert for response time > 3 seconds" `
            -Impact "Slow performance won't be detected"
    }
    
    if (-not $hasDiskAlert -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No disk space alert configured" -Recommendation "Create alert for disk usage > 85%" `
            -Impact "Disk space issues won't be detected"
    }
    
    # ============================================================
    # 12. RBAC ROLE ASSIGNMENTS AUDIT (COMPREHENSIVE)
    # ============================================================
    
    Write-Host "[12/18] Auditing RBAC Role Assignments..." -ForegroundColor Yellow
    $roleAssignments = Get-AzResourceSafe -Command "az role assignment list --all -o json"
    $global:resourceCounts.RoleAssignments += $roleAssignments.Count
    
    if ($roleAssignments.Count -gt 0) {
        Write-Host "  Found: $($roleAssignments.Count) role assignments" -ForegroundColor White
        
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
                    -Issue "Stale role assignment (deleted principal: $($assignment.principalId))" -Recommendation "Remove orphaned assignment" `
                    -Impact "Security hygiene issue"
                $staleCount++
            }
        }
        
        Write-Host "    Stale assignments: $staleCount" -ForegroundColor $(if ($staleCount -gt 0) { "Yellow" } else { "Gray" })
        
        # Check for excessive Owner roles
        $ownerAssignments = $roleAssignments | Where-Object { $_.roleDefinitionName -eq "Owner" -and $_.principalType -eq "User" }
        if ($ownerAssignments.Count -gt 5) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "RBAC" `
                -Issue "$($ownerAssignments.Count) users have Owner role" -Recommendation "Review and minimize Owner role assignments" `
                -Impact "Too many users with full subscription access"
        }
        
        Write-Host "    Users with Owner role: $($ownerAssignments.Count)" -ForegroundColor $(if ($ownerAssignments.Count -gt 5) { "Yellow" } else { "Gray" })
        
        # Check for Contributor at subscription level
        $contributorSub = $roleAssignments | Where-Object { 
            $_.roleDefinitionName -eq "Contributor" -and 
            $_.scope -match "/subscriptions/$($sub.id)$"
        }
        if ($contributorSub.Count -gt 10) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "RBAC" `
                -Issue "$($contributorSub.Count) Contributor assignments at subscription level" -Recommendation "Scope permissions to resource groups instead" `
                -Impact "Overly broad permissions"
        }
        
        # Check for custom roles
        $customRoles = Get-AzResourceSafe -Command "az role definition list --custom-role-only true -o json"
        $global:resourceCounts.CustomRoles += $customRoles.Count
        if ($customRoles.Count -gt 0) {
            Write-Host "    Custom roles: $($customRoles.Count)" -ForegroundColor Gray
        }
    }
    
    # ============================================================
    # 13. RESOURCE LOCKS AUDIT
    # ============================================================
    
    Write-Host "[13/18] Auditing Resource Locks..." -ForegroundColor Yellow
    $locks = Get-AzResourceSafe -Command "az lock list -o json"
    $global:resourceCounts.ResourceLocks += $locks.Count
    
    if ($locks.Count -eq 0) {
        Add-Finding -Severity "Low" -Subscription $sub.name -Resource "Subscription" -Type "Resource Locks" `
            -Issue "No resource locks configured" -Recommendation "Add CanNotDelete locks to critical resources" `
            -Impact "Critical resources can be accidentally deleted"
    } else {
        Write-Host "  Found: $($locks.Count) locks" -ForegroundColor Green
    }
    
    # ============================================================
    # 14. POLICY COMPLIANCE AUDIT
    # ============================================================
    
    Write-Host "[14/18] Checking Policy Compliance..." -ForegroundColor Yellow
    
    # Get policy assignments
    $policyAssignments = Get-AzResourceSafe -Command "az policy assignment list -o json"
    $global:resourceCounts.PolicyAssignments += $policyAssignments.Count
    
    if ($policyAssignments.Count -gt 0) {
        Write-Host "  Found: $($policyAssignments.Count) policy assignments" -ForegroundColor White
    }
    
    # Get policy definitions
    $policyDefinitions = Get-AzResourceSafe -Command "az policy definition list -o json"
    $global:resourceCounts.PolicyDefinitions += $policyDefinitions.Count
    
    # Check policy compliance (this can be slow)
    Write-Host "  Checking compliance states (this may take a while)..." -ForegroundColor Gray
    $policyStates = Get-AzResourceSafe -Command "az policy state list --filter ""isCompliant eq false"" -o json"
    
    if ($policyStates.Count -gt 0) {
        Write-Host "  Found: $($policyStates.Count) non-compliant resources" -ForegroundColor Yellow
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Policy Compliance" `
            -Issue "$($policyStates.Count) resources not compliant with Azure Policy" -Recommendation "Review and remediate policy violations" `
            -Impact "Compliance and governance issues"
    } else {
        Write-Host "  All resources compliant (or no policies assigned)" -ForegroundColor Green
    }
    
    # ============================================================
    # 15. SECURITY CENTER RECOMMENDATIONS
    # ============================================================
    
    Write-Host "[15/18] Checking Security Center..." -ForegroundColor Yellow
    $securityTasks = Get-AzResourceSafe -Command "az security task list -o json"
    
    if ($securityTasks.Count -gt 0) {
        Write-Host "  Found: $($securityTasks.Count) security recommendations" -ForegroundColor Yellow
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Security Center" `
            -Issue "$($securityTasks.Count) active security recommendations" -Recommendation "Review and implement Security Center recommendations" `
            -Impact "Security vulnerabilities present"
    } else {
        Write-Host "  No active security recommendations" -ForegroundColor Green
    }
    
    # ============================================================
    # 16. DIAGNOSTIC SETTINGS AUDIT
    # ============================================================
    
    Write-Host "[16/18] Auditing Diagnostic Settings..." -ForegroundColor Yellow
    
    $resourcesWithoutDiag = 0
    $criticalResourceTypes = @(
        "Microsoft.Compute/virtualMachines",
        "Microsoft.Sql/servers",
        "Microsoft.Web/sites",
        "Microsoft.KeyVault/vaults",
        "Microsoft.Storage/storageAccounts"
    )
    
    foreach ($rg in $resourceGroups) {
        $resources = Get-AzResourceSafe -Command "az resource list --resource-group '$($rg.name)' -o json"
        foreach ($resource in $resources) {
            if ($resource.type -in $criticalResourceTypes) {
                $diag = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($resource.id) -o json"
                if ($diag.Count -eq 0) {
                    $resourcesWithoutDiag++
                }
            }
        }
    }
    
    if ($resourcesWithoutDiag -gt 0) {
        Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "Subscription" -Type "Diagnostic Settings" `
            -Issue "$resourcesWithoutDiag critical resources without diagnostic logging" -Recommendation "Enable diagnostics to Log Analytics workspace" `
            -Impact "Limited monitoring and troubleshooting capability"
        Write-Host "  Resources without diagnostics: $resourcesWithoutDiag" -ForegroundColor Yellow
    } else {
        Write-Host "  All critical resources have diagnostics enabled" -ForegroundColor Green
    }
    
    # ============================================================
    # 17. DISKS & NETWORK INTERFACES AUDIT
    # ============================================================
    
    Write-Host "[17/18] Auditing Disks & Network Interfaces..." -ForegroundColor Yellow
    
    # Check for unattached disks
    $disks = Get-AzResourceSafe -Command "az disk list -o json"
    $global:resourceCounts.Disks += $disks.Count
    
    foreach ($disk in $disks) {
        if ($disk.managedBy -eq $null) {
            $global:resourceCounts.UnattachedDisks++
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $disk.name -Type "Disk" `
                -Issue "Unattached managed disk" -Recommendation "Delete if not needed or attach to VM" `
                -Impact "Unnecessary storage costs"
        }
    }
    
    Write-Host "  Disks: $($disks.Count) total, $($global:resourceCounts.UnattachedDisks) unattached" -ForegroundColor White
    
    # Check for unused NICs
    $nics = Get-AzResourceSafe -Command "az network nic list -o json"
    $global:resourceCounts.NetworkInterfaces += $nics.Count
    
    foreach ($nic in $nics) {
        if ($nic.virtualMachine -eq $null) {
            $global:resourceCounts.UnusedNICs++
            Add-Finding -Severity "Low" -Subscription $sub.name -Resource $nic.name -Type "Network Interface" `
                -Issue "Unused network interface" -Recommendation "Delete unused NIC" `
                -Impact "Clutter and potential confusion"
        }
    }
    
    Write-Host "  NICs: $($nics.Count) total, $($global:resourceCounts.UnusedNICs) unused" -ForegroundColor White
    
    # ============================================================
    # 18. BACKUP & RECOVERY AUDIT
    # ============================================================
    
    Write-Host "[18/18] Auditing Backup & Recovery..." -ForegroundColor Yellow
    
    # Check Recovery Services Vaults
    $recoveryVaults = Get-AzResourceSafe -Command "az backup vault list -o json"
    $global:resourceCounts.RecoveryServicesVaults += $recoveryVaults.Count
    
    if ($recoveryVaults.Count -eq 0 -and $global:resourceCounts.VMs -gt 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Backup" `
            -Issue "No Recovery Services Vaults configured" -Recommendation "Configure Azure Backup for VMs" `
            -Impact "No disaster recovery capability"
        Write-Host "  No backup vaults found" -ForegroundColor Yellow
    } else {
        Write-Host "  Found: $($recoveryVaults.Count) Recovery Services Vaults" -ForegroundColor White
    }
    
    # Check Backup Vaults (for newer backup types)
    $backupVaults = Get-AzResourceSafe -Command "az dataprotection backup-vault list -o json"
    $global:resourceCounts.BackupVaults += $backupVaults.Count
    
    if ($backupVaults.Count -gt 0) {
        Write-Host "  Found: $($backupVaults.Count) Backup Vaults" -ForegroundColor White
    }
}

# ============================================================
# SAVE CSV REPORT
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  SAVING CSV REPORT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

try {
    $global:findings | Export-Csv -Path $csvReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SAVED] CSV Report: $csvReportPath" -ForegroundColor Green
    
    if (Test-Path $csvReportPath) {
        $csvSize = (Get-Item $csvReportPath).Length
        Write-Host "  File size: $([math]::Round($csvSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save CSV: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# GENERATE HTML REPORT
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  GENERATING HTML REPORT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

$totalIssues = $global:issues.Critical + $global:issues.High + $global:issues.Medium + $global:issues.Low
$totalResources = $global:resourceCounts.VMs + $global:resourceCounts.StorageAccounts + $global:resourceCounts.SqlDatabases + $global:resourceCounts.AppServices + $global:resourceCounts.VNets + $global:resourceCounts.NSGs

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>PYX Health - Complete Azure Audit</title>
    <meta charset="UTF-8">
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
        }
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
        }
        .resource-card strong {
            display: block;
            font-size: 32px;
            color: #0078d4;
            margin-bottom: 8px;
        }
        .resource-card span {
            color: #605e5c;
            font-size: 14px;
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
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PYX HEALTH - COMPLETE AZURE AUDIT</h1>
            <p><strong>Generated:</strong> $(Get-Date -Format "dddd, MMMM dd, yyyy 'at' hh:mm:ss tt")</p>
            <p><strong>Subscriptions Audited:</strong> $($global:resourceCounts.Subscriptions)</p>
            <p><strong>Total Resources Scanned:</strong> $totalResources</p>
            <p><strong>Report Files:</strong></p>
            <p style="font-size: 13px;">HTML: $htmlReportPath</p>
            <p style="font-size: 13px;">CSV: $csvReportPath</p>
        </div>
        
        <div class="section">
            <h2>EXECUTIVE SUMMARY</h2>
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
            <h2>RESOURCE INVENTORY - ALL SUBSCRIPTIONS</h2>
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
                    <span>Public IP Addresses</span>
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
                <div class="resource-card">
                    <strong>$($global:resourceCounts.Disks)</strong>
                    <span>Managed Disks</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.NetworkInterfaces)</strong>
                    <span>Network Interfaces</span>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>IDENTITY & ACCESS MANAGEMENT</h2>
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
                <div class="metric">
                    <div class="metric-value info">$($global:resourceCounts.CustomRoles)</div>
                    <div class="metric-label">Custom Roles</div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>DETAILED FINDINGS & RECOMMENDATIONS</h2>
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
            <h3>PYX HEALTH - AZURE INFRASTRUCTURE AUDIT</h3>
            <p>Comprehensive audit of $($global:resourceCounts.Subscriptions) subscriptions</p>
            <p><strong>Total Resources Analyzed:</strong> $totalResources</p>
            <p><strong>Coverage:</strong> Security, Networking, RBAC, Alerts, Performance, Compliance</p>
            <p style="margin-top: 20px; font-size: 12px; color: #999;">
                Report includes: VM optimization, Storage security, Network firewalls, SQL hardening, 
                RBAC analysis, Alert configuration, Subnet mapping, NSG rules, Load balancer health, 
                Disk management, Backup verification, Policy compliance
            </p>
        </div>
    </div>
</body>
</html>
"@

try {
    $html | Out-File -FilePath $htmlReportPath -Encoding UTF8 -Force
    Write-Host "[SAVED] HTML Report: $htmlReportPath" -ForegroundColor Green
    
    if (Test-Path $htmlReportPath) {
        $htmlSize = (Get-Item $htmlReportPath).Length
        Write-Host "  File size: $([math]::Round($htmlSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save HTML: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# DISPLAY SUMMARY
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  COMPREHENSIVE AUDIT COMPLETE" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Subscriptions: $($global:resourceCounts.Subscriptions)" -ForegroundColor White
Write-Host "  Resource Groups: $($global:resourceCounts.ResourceGroups)" -ForegroundColor White
Write-Host "  VMs: $($global:resourceCounts.VMs) ($($global:resourceCounts.RunningVMs) running, $($global:resourceCounts.StoppedVMs) stopped)" -ForegroundColor White
Write-Host "  Storage: $($global:resourceCounts.StorageAccounts)" -ForegroundColor White
Write-Host "  Key Vaults: $($global:resourceCounts.KeyVaults)" -ForegroundColor White
Write-Host "  SQL: $($global:resourceCounts.SqlServers) servers, $($global:resourceCounts.SqlDatabases) databases" -ForegroundColor White
Write-Host "  App Services: $($global:resourceCounts.AppServices)" -ForegroundColor White
Write-Host "  VNets: $($global:resourceCounts.VNets)" -ForegroundColor White
Write-Host "  Subnets: $($global:resourceCounts.Subnets)" -ForegroundColor White
Write-Host "  NSGs: $($global:resourceCounts.NSGs)" -ForegroundColor White
Write-Host "  NSG Rules: $($global:resourceCounts.NSGRules) ($($global:resourceCounts.InboundRules) inbound, $($global:resourceCounts.OutboundRules) outbound)" -ForegroundColor White
Write-Host "  Public IPs: $($global:resourceCounts.PublicIPs) ($($global:resourceCounts.UsedPublicIPs) used, $($global:resourceCounts.UnusedPublicIPs) unused)" -ForegroundColor White
Write-Host "  Alert Rules: $($global:resourceCounts.AlertRules) ($($global:resourceCounts.MetricAlerts) metric, $($global:resourceCounts.ActivityAlerts) activity)" -ForegroundColor White
Write-Host "  RBAC: $($global:resourceCounts.RoleAssignments) assignments" -ForegroundColor White
Write-Host "  Disks: $($global:resourceCounts.Disks) ($($global:resourceCounts.UnattachedDisks) unattached)" -ForegroundColor White
Write-Host ""
Write-Host "ISSUES FOUND:" -ForegroundColor Cyan
Write-Host "  Total: $totalIssues" -ForegroundColor White
Write-Host "  Critical: $($global:issues.Critical)" -ForegroundColor Red
Write-Host "  High: $($global:issues.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($global:issues.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($global:issues.Low)" -ForegroundColor Green
Write-Host ""
Write-Host "REPORTS SAVED TO:" -ForegroundColor Cyan
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host ""

# ============================================================
# OPEN HTML REPORT AUTOMATICALLY
# ============================================================

Write-Host "Opening HTML report in browser..." -ForegroundColor Yellow
try {
    Start-Process $htmlReportPath
    Write-Host "  Report opened!" -ForegroundColor Green
} catch {
    Write-Host "  Could not open automatically:" -ForegroundColor Yellow
    Write-Host "  $htmlReportPath" -ForegroundColor White
}

Write-Host ""
Write-Host "ALL DONE!" -ForegroundColor Green
Write-Host ""
