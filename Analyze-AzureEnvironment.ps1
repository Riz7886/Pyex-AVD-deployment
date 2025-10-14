#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - Complete Azure Audit (CLEAN - NO EMOJIS)

.DESCRIPTION
    Saves HTML and CSV reports to D:\PYEX-AVD-Deployment\Reports\
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ReportsFolder = "D:\PYEX-AVD-Deployment\Reports"
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - COMPLETE AZURE AUDIT" -ForegroundColor Cyan
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
    Write-Host "[CHECK] Azure CLI: OK" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Azure CLI not installed!" -ForegroundColor Red
    exit 1
}

# Check login
Write-Host "[CHECK] Azure login..." -ForegroundColor Yellow
try {
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    $account = $accountJson | ConvertFrom-Json
    Write-Host "[CHECK] Logged in: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Not logged in!" -ForegroundColor Red
    exit 1
}

# Get subscriptions
Write-Host ""
Write-Host "Getting subscriptions..." -ForegroundColor Yellow
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
Write-Host "  STARTING AUDIT" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow

$subCount = 0
foreach ($sub in $subscriptions) {
    $subCount++
    
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  SUBSCRIPTION $subCount/$($subscriptions.Count): $($sub.name)" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    
    az account set --subscription $sub.id 2>&1 | Out-Null
    
    # Resource Groups
    Write-Host "[1/15] Resource Groups..." -ForegroundColor Yellow
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
    
    # Virtual Machines
    Write-Host "[2/15] Virtual Machines..." -ForegroundColor Yellow
    $vms = Get-AzResourceSafe -Command "az vm list -o json"
    $global:resourceCounts.VMs += $vms.Count
    Write-Host "  Found: $($vms.Count)" -ForegroundColor White
    
    foreach ($vm in $vms) {
        if ($vm.hardwareProfile.vmSize -match "Standard_D") {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "VM may be oversized" -Recommendation "Review and downsize" -Impact "Cost savings 30-50%"
        }
        
        $diagnostics = Get-AzResourceSafe -Command "az monitor diagnostic-settings list --resource $($vm.id) -o json"
        if ($diagnostics.Count -eq 0) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $vm.name -Type "VM" `
                -Issue "No diagnostic logging" -Recommendation "Enable diagnostics" -Impact "Limited troubleshooting"
        }
    }
    
    # Storage Accounts
    Write-Host "[3/15] Storage Accounts..." -ForegroundColor Yellow
    $storageAccounts = Get-AzResourceSafe -Command "az storage account list -o json"
    $global:resourceCounts.StorageAccounts += $storageAccounts.Count
    Write-Host "  Found: $($storageAccounts.Count)" -ForegroundColor White
    
    foreach ($sa in $storageAccounts) {
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "HTTPS-only not enabled" -Recommendation "Enable HTTPS-only" -Impact "Insecure transmission"
        }
        
        if ($sa.minimumTlsVersion -ne "TLS1_2") {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "TLS 1.2 not enforced" -Recommendation "Set minimum TLS to 1.2" -Impact "Weak encryption"
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $sa.name -Type "Storage" `
                -Issue "Public blob access enabled" -Recommendation "Disable public access" -Impact "Data exposure"
        }
    }
    
    # Key Vaults
    Write-Host "[4/15] Key Vaults..." -ForegroundColor Yellow
    $keyVaults = Get-AzResourceSafe -Command "az keyvault list -o json"
    $global:resourceCounts.KeyVaults += $keyVaults.Count
    Write-Host "  Found: $($keyVaults.Count)" -ForegroundColor White
    
    foreach ($kv in $keyVaults) {
        if ($kv.properties.enableSoftDelete -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $kv.name -Type "Key Vault" `
                -Issue "Soft delete not enabled" -Recommendation "Enable soft delete" -Impact "Cannot recover secrets"
        }
    }
    
    # SQL
    Write-Host "[5/15] SQL Servers..." -ForegroundColor Yellow
    $sqlServers = Get-AzResourceSafe -Command "az sql server list -o json"
    $global:resourceCounts.SqlServers += $sqlServers.Count
    Write-Host "  Found: $($sqlServers.Count)" -ForegroundColor White
    
    foreach ($server in $sqlServers) {
        $databases = Get-AzResourceSafe -Command "az sql db list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
        $global:resourceCounts.SqlDatabases += $databases.Count
        
        $firewallRules = Get-AzResourceSafe -Command "az sql server firewall-rule list --server $($server.name) --resource-group $($server.resourceGroup) -o json"
        foreach ($rule in $firewallRules) {
            if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "255.255.255.255") {
                Add-Finding -Severity "Critical" -Subscription $sub.name -Resource "$($server.name)/$($rule.name)" -Type "SQL Firewall" `
                    -Issue "SQL open to internet" -Recommendation "Restrict to specific IPs" -Impact "Database exposed"
            }
        }
    }
    
    # App Services
    Write-Host "[6/15] App Services..." -ForegroundColor Yellow
    $appServices = Get-AzResourceSafe -Command "az webapp list -o json"
    $global:resourceCounts.AppServices += $appServices.Count
    Write-Host "  Found: $($appServices.Count)" -ForegroundColor White
    
    foreach ($app in $appServices) {
        if ($app.httpsOnly -ne $true) {
            Add-Finding -Severity "High" -Subscription $sub.name -Resource $app.name -Type "App Service" `
                -Issue "HTTPS-only not enforced" -Recommendation "Enable HTTPS-only" -Impact "Insecure"
        }
    }
    
    # VNets & Subnets
    Write-Host "[7/15] Virtual Networks..." -ForegroundColor Yellow
    $vnets = Get-AzResourceSafe -Command "az network vnet list -o json"
    $global:resourceCounts.VNets += $vnets.Count
    Write-Host "  Found: $($vnets.Count) VNets" -ForegroundColor White
    
    foreach ($vnet in $vnets) {
        if ($vnet.subnets) {
            $global:resourceCounts.Subnets += $vnet.subnets.Count
            
            foreach ($subnet in $vnet.subnets) {
                if ($subnet.networkSecurityGroup -eq $null) {
                    Add-Finding -Severity "Medium" -Subscription $sub.name -Resource "$($vnet.name)/$($subnet.name)" -Type "Subnet" `
                        -Issue "No NSG attached" -Recommendation "Attach NSG" -Impact "No network filtering"
                }
            }
        }
    }
    
    # NSGs
    Write-Host "[8/15] Network Security Groups..." -ForegroundColor Yellow
    $nsgs = Get-AzResourceSafe -Command "az network nsg list -o json"
    $global:resourceCounts.NSGs += $nsgs.Count
    Write-Host "  Found: $($nsgs.Count) NSGs" -ForegroundColor White
    
    foreach ($nsg in $nsgs) {
        $rules = Get-AzResourceSafe -Command "az network nsg rule list --nsg-name '$($nsg.name)' --resource-group '$($nsg.resourceGroup)' -o json"
        $global:resourceCounts.NSGRules += $rules.Count
        
        foreach ($rule in $rules) {
            if ($rule.direction -eq "Inbound" -and $rule.access -eq "Allow") {
                $isWildcard = $rule.sourceAddressPrefix -in @("*", "Internet", "0.0.0.0/0")
                
                if ($isWildcard) {
                    $dangerousPorts = @("22", "3389", "1433", "3306", "5432")
                    $portInfo = if ($rule.destinationPortRange) { $rule.destinationPortRange } else { "multiple" }
                    
                    $severity = "Medium"
                    foreach ($port in $dangerousPorts) {
                        if ($portInfo -match $port) {
                            $severity = "Critical"
                            break
                        }
                    }
                    
                    Add-Finding -Severity $severity -Subscription $sub.name -Resource "$($nsg.name)/$($rule.name)" -Type "NSG Rule" `
                        -Issue "Allow from Internet on port $portInfo" -Recommendation "Restrict source IPs" -Impact "Exposed to internet"
                }
            }
        }
    }
    
    # Public IPs
    Write-Host "[9/15] Public IPs..." -ForegroundColor Yellow
    $publicIPs = Get-AzResourceSafe -Command "az network public-ip list -o json"
    $global:resourceCounts.PublicIPs += $publicIPs.Count
    Write-Host "  Found: $($publicIPs.Count)" -ForegroundColor White
    
    # Load Balancers
    Write-Host "[10/15] Load Balancers..." -ForegroundColor Yellow
    $loadBalancers = Get-AzResourceSafe -Command "az network lb list -o json"
    $global:resourceCounts.LoadBalancers += $loadBalancers.Count
    Write-Host "  Found: $($loadBalancers.Count)" -ForegroundColor White
    
    # Alerts
    Write-Host "[11/15] Alert Rules..." -ForegroundColor Yellow
    $metricAlerts = Get-AzResourceSafe -Command "az monitor metrics alert list -o json"
    $activityAlerts = Get-AzResourceSafe -Command "az monitor activity-log alert list -o json"
    $totalAlerts = $metricAlerts.Count + $activityAlerts.Count
    $global:resourceCounts.AlertRules += $totalAlerts
    Write-Host "  Found: $totalAlerts" -ForegroundColor White
    
    if ($totalAlerts -eq 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Alerts" `
            -Issue "No alerts configured" -Recommendation "Configure CPU, memory, disk alerts" -Impact "No monitoring"
    }
    
    # RBAC
    Write-Host "[12/15] RBAC..." -ForegroundColor Yellow
    $roleAssignments = Get-AzResourceSafe -Command "az role assignment list --all -o json"
    $global:resourceCounts.RoleAssignments += $roleAssignments.Count
    Write-Host "  Found: $($roleAssignments.Count)" -ForegroundColor White
    
    $userCount = ($roleAssignments | Where-Object { $_.principalType -eq "User" }).Count
    $spCount = ($roleAssignments | Where-Object { $_.principalType -eq "ServicePrincipal" }).Count
    $groupCount = ($roleAssignments | Where-Object { $_.principalType -eq "Group" }).Count
    
    $global:resourceCounts.Users += $userCount
    $global:resourceCounts.ServicePrincipals += $spCount
    $global:resourceCounts.Groups += $groupCount
    
    foreach ($assignment in $roleAssignments) {
        if ([string]::IsNullOrEmpty($assignment.principalName)) {
            Add-Finding -Severity "Medium" -Subscription $sub.name -Resource $assignment.roleDefinitionName -Type "RBAC" `
                -Issue "Stale assignment" -Recommendation "Remove orphaned" -Impact "Security hygiene"
        }
    }
    
    # Locks
    Write-Host "[13/15] Locks..." -ForegroundColor Yellow
    $locks = Get-AzResourceSafe -Command "az lock list -o json"
    if ($locks.Count -eq 0) {
        Add-Finding -Severity "Low" -Subscription $sub.name -Resource "Subscription" -Type "Locks" `
            -Issue "No locks" -Recommendation "Add CanNotDelete locks" -Impact "Deletion risk"
    }
    
    # Policy - SKIP
    Write-Host "[14/15] Policy Compliance... SKIPPED (too slow)" -ForegroundColor Gray
    
    # Security Center
    Write-Host "[15/15] Security Center..." -ForegroundColor Yellow
    $securityTasks = Get-AzResourceSafe -Command "az security task list -o json"
    if ($securityTasks.Count -gt 0) {
        Add-Finding -Severity "High" -Subscription $sub.name -Resource "Subscription" -Type "Security" `
            -Issue "$($securityTasks.Count) security recommendations" -Recommendation "Review Security Center" -Impact "Vulnerabilities"
    }
}

# Save CSV
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  SAVING CSV REPORT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

try {
    $global:findings | Export-Csv -Path $csvReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SAVED] CSV: $csvReportPath" -ForegroundColor Green
    
    if (Test-Path $csvReportPath) {
        $csvSize = (Get-Item $csvReportPath).Length
        Write-Host "  Size: $([math]::Round($csvSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save CSV: $($_.Exception.Message)" -ForegroundColor Red
}

# Generate HTML
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  GENERATING HTML REPORT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

$totalIssues = $global:issues.Critical + $global:issues.High + $global:issues.Medium + $global:issues.Low

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
            <p><strong>Subscriptions:</strong> $($global:resourceCounts.Subscriptions)</p>
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
            <h2>RESOURCE INVENTORY</h2>
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
                    <strong>$($global:resourceCounts.VNets)</strong>
                    <span>Virtual Networks</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.Subnets)</strong>
                    <span>Subnets</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.NSGs)</strong>
                    <span>NSGs</span>
                </div>
                <div class="resource-card">
                    <strong>$($global:resourceCounts.NSGRules)</strong>
                    <span>NSG Rules</span>
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
            <h2>DETAILED FINDINGS</h2>
            <table>
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Subscription</th>
                        <th>Resource</th>
                        <th>Type</th>
                        <th>Issue</th>
                        <th>Recommendation</th>
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
                    </tr>
"@
}

$html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <h3>PYX HEALTH - AZURE AUDIT</h3>
            <p>Comprehensive audit of $($global:resourceCounts.Subscriptions) subscriptions</p>
            <p>Total Resources: $(
                $global:resourceCounts.VMs + 
                $global:resourceCounts.StorageAccounts + 
                $global:resourceCounts.VNets + 
                $global:resourceCounts.NSGs
            )</p>
        </div>
    </div>
</body>
</html>
"@

# Save HTML
try {
    $html | Out-File -FilePath $htmlReportPath -Encoding UTF8 -Force
    Write-Host "[SAVED] HTML: $htmlReportPath" -ForegroundColor Green
    
    if (Test-Path $htmlReportPath) {
        $htmlSize = (Get-Item $htmlReportPath).Length
        Write-Host "  Size: $([math]::Round($htmlSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save HTML: $($_.Exception.Message)" -ForegroundColor Red
}

# Display Summary
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Subscriptions: $($global:resourceCounts.Subscriptions)" -ForegroundColor White
Write-Host "  Resource Groups: $($global:resourceCounts.ResourceGroups)" -ForegroundColor White
Write-Host "  VMs: $($global:resourceCounts.VMs)" -ForegroundColor White
Write-Host "  Storage: $($global:resourceCounts.StorageAccounts)" -ForegroundColor White
Write-Host "  VNets: $($global:resourceCounts.VNets)" -ForegroundColor White
Write-Host "  Subnets: $($global:resourceCounts.Subnets)" -ForegroundColor White
Write-Host "  NSGs: $($global:resourceCounts.NSGs)" -ForegroundColor White
Write-Host "  NSG Rules: $($global:resourceCounts.NSGRules)" -ForegroundColor White
Write-Host ""
Write-Host "ISSUES:" -ForegroundColor Cyan
Write-Host "  Total: $totalIssues" -ForegroundColor White
Write-Host "  Critical: $($global:issues.Critical)" -ForegroundColor Red
Write-Host "  High: $($global:issues.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($global:issues.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($global:issues.Low)" -ForegroundColor Green
Write-Host ""
Write-Host "REPORTS SAVED:" -ForegroundColor Cyan
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host ""

# Open HTML
Write-Host "Opening HTML report..." -ForegroundColor Yellow
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
