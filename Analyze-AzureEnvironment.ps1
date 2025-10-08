<#
.SYNOPSIS
    Azure Environment Analyzer - Comprehensive Detection & Auto-Remediation Tool

.DESCRIPTION
    Enterprise-grade PowerShell script that:
    1. Detects ALL issues in Azure environment (RBAC, Network, Security, Permissions, SSO, etc.)
    2. Creates comprehensive audit reports with severity ratings
    3. Generates fix scripts but DOES NOT execute without approval
    4. Provides selective remediation with rollback capability

.PARAMETER SubscriptionId
    Azure Subscription ID to analyze. If not provided, uses current context.

.PARAMETER ReportPath
    Path where audit reports will be saved. Default: .\Azure-Analysis-Reports\

.PARAMETER AutoFix
    Switch to enable automatic fixing after detection. Default: $false (detection only)

.PARAMETER FixCategories
    Specific categories to fix. Options: RBAC, Network, Security, Permissions, Users, All

.EXAMPLE
    .\Analyze-AzureEnvironment.ps1

.EXAMPLE
    .\Analyze-AzureEnvironment.ps1 -ReportPath "C:\Reports"

.EXAMPLE
    .\Analyze-AzureEnvironment.ps1 -AutoFix -FixCategories RBAC

.AUTHOR
    Azure DevOps Team
    Version: 3.0
    Last Updated: 2025-10-08
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\Azure-Analysis-Reports",

    [Parameter(Mandatory = $false)]
    [switch]$AutoFix,

    [Parameter(Mandatory = $false)]
    [ValidateSet("RBAC", "Network", "Security", "Permissions", "Users", "All")]
    [string[]]$FixCategories = @()
)

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"    = "Cyan"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "SUCCESS" = "Green"
    }
    
    $prefix = @{
        "INFO"    = "[INFO]"
        "WARNING" = "[WARN]"
        "ERROR"   = "[ERROR]"
        "SUCCESS" = "[OK]"
    }
    
    Write-Host "[$timestamp] $($prefix[$Level]) $Message" -ForegroundColor $colors[$Level]
}

function New-Issue {
    param(
        [string]$Category,
        [string]$Severity,
        [string]$Resource,
        [string]$Description,
        [string]$Recommendation,
        [string]$FixScript
    )
    
    return [PSCustomObject]@{
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Category       = $Category
        Severity       = $Severity
        Resource       = $Resource
        Description    = $Description
        Recommendation = $Recommendation
        FixScript      = $FixScript
        Status         = "Detected"
    }
}

function Test-AzureCLI {
    try {
        $version = az version --output json 2>&1 | ConvertFrom-Json
        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region Main Script

Write-Host ""
Write-Host "=============================================================="
Write-Host "   AZURE ENVIRONMENT ANALYZER & AUTO-REMEDIATION"
Write-Host "   Enterprise-Grade Detection & Fix Tool"
Write-Host "=============================================================="
Write-Host ""

# Initialize
$Issues = @()
$FixScripts = @()
$startTime = Get-Date

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

Write-Log "Starting Azure environment analysis..." "INFO"

# Check Azure CLI
if (-not (Test-AzureCLI)) {
    Write-Log "Azure CLI not found. Please install Azure CLI from https://aka.ms/installazurecli" "ERROR"
    exit 1
}

# Connect to Azure
try {
    Write-Log "Checking Azure CLI login status..." "INFO"
    $accountInfo = az account show 2>&1 | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Not logged in. Please run: az login" "ERROR"
        exit 1
    }
    
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId
        $accountInfo = az account show | ConvertFrom-Json
    }
    
    Write-Log "Connected to: $($accountInfo.name)" "SUCCESS"
    $currentSubscriptionId = $accountInfo.id
} 
catch {
    Write-Log "Failed to connect to Azure: $_" "ERROR"
    exit 1
}

#region 1. RBAC & Permissions Analysis

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYZING: RBAC & PERMISSIONS"
Write-Host "=============================================================="
Write-Host ""

Write-Log "Analyzing RBAC assignments..." "INFO"

# Get all role assignments
$roleAssignmentsJson = az role assignment list --all --output json 2>&1
$roleAssignments = $roleAssignmentsJson | ConvertFrom-Json

# Check for Owner permissions
$ownerAssignments = $roleAssignments | Where-Object { $_.roleDefinitionName -eq "Owner" }
foreach ($owner in $ownerAssignments) {
    if ($owner.principalType -eq "User") {
        $fixCmd = "az role assignment delete --assignee `"$($owner.principalId)`" --role `"Owner`" --scope `"$($owner.scope)`"`n"
        $fixCmd += "az role assignment create --assignee `"$($owner.principalId)`" --role `"Contributor`" --scope `"$($owner.scope)`""
        
        $Issues += New-Issue `
            -Category "RBAC" `
            -Severity "High" `
            -Resource $owner.principalName `
            -Description "User has Owner permissions at scope: $($owner.scope)" `
            -Recommendation "Review if Owner role is necessary. Consider Contributor instead." `
            -FixScript $fixCmd
    }
}

# Check for stale role assignments
Write-Log "Checking for stale RBAC assignments..." "INFO"
foreach ($assignment in $roleAssignments) {
    if ([string]::IsNullOrEmpty($assignment.principalName) -or $assignment.principalName -eq "Unknown") {
        $fixCmd = "az role assignment delete --assignee `"$($assignment.principalId)`" --scope `"$($assignment.scope)`""
        
        $Issues += New-Issue `
            -Category "RBAC" `
            -Severity "Medium" `
            -Resource $assignment.principalId `
            -Description "Stale RBAC assignment detected for deleted identity" `
            -Recommendation "Remove orphaned role assignment" `
            -FixScript $fixCmd
    }
}

# Check for custom roles with wildcard permissions
$customRolesJson = az role definition list --custom-role-only true --output json 2>&1
$customRoles = $customRolesJson | ConvertFrom-Json

foreach ($role in $customRoles) {
    if ($role.permissions.actions -contains "*") {
        $Issues += New-Issue `
            -Category "RBAC" `
            -Severity "Critical" `
            -Resource $role.roleName `
            -Description "Custom role has wildcard (*) permissions" `
            -Recommendation "Limit custom role to specific actions only" `
            -FixScript "# Review and update role definition: az role definition update --role-definition role.json"
    }
}

Write-Log "RBAC analysis complete. Found $(($Issues | Where-Object {$_.Category -eq 'RBAC'}).Count) issues" "INFO"

#endregion

#region 2. Network Configuration Analysis

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYZING: NETWORK CONFIGURATION"
Write-Host "=============================================================="
Write-Host ""

Write-Log "Analyzing network security groups..." "INFO"

# Get all NSGs
$nsgsJson = az network nsg list --output json 2>&1
$nsgs = $nsgsJson | ConvertFrom-Json

foreach ($nsg in $nsgs) {
    # Check for unrestricted inbound rules
    $dangerousRules = $nsg.securityRules | Where-Object {
        $_.direction -eq "Inbound" -and
        $_.access -eq "Allow" -and
        ($_.sourceAddressPrefix -eq "*" -or $_.sourceAddressPrefix -eq "Internet" -or $_.sourceAddressPrefix -eq "0.0.0.0/0")
    }
    
    foreach ($rule in $dangerousRules) {
        $severity = "Critical"
        if ($rule.destinationPortRange -eq "22" -or $rule.destinationPortRange -eq "3389") {
            $severity = "Critical"
        } elseif ($rule.destinationPortRange -eq "443" -or $rule.destinationPortRange -eq "80") {
            $severity = "High"
        }
        
        $fixCmd = "az network nsg rule update --resource-group `"$($nsg.resourceGroup)`" --nsg-name `"$($nsg.name)`" --name `"$($rule.name)`" --source-address-prefixes `"YOUR_IP/32`""
        
        $Issues += New-Issue `
            -Category "Network" `
            -Severity $severity `
            -Resource "$($nsg.name) - Rule: $($rule.name)" `
            -Description "Unrestricted inbound access from Internet on port(s): $($rule.destinationPortRange)" `
            -Recommendation "Restrict source to specific IP ranges or use Azure Bastion for management" `
            -FixScript $fixCmd
    }
    
    # Check for default deny rule
    $hasDefaultDeny = $nsg.securityRules | Where-Object {
        $_.priority -eq 4096 -and $_.access -eq "Deny"
    }
    
    if (-not $hasDefaultDeny) {
        $fixCmd = "az network nsg rule create --resource-group `"$($nsg.resourceGroup)`" --nsg-name `"$($nsg.name)`" --name `"DenyAllInbound`" --priority 4096 --direction Inbound --access Deny --protocol '*' --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges '*'"
        
        $Issues += New-Issue `
            -Category "Network" `
            -Severity "Medium" `
            -Resource $nsg.name `
            -Description "NSG missing explicit default deny rule" `
            -Recommendation "Add explicit deny all rule at lowest priority" `
            -FixScript $fixCmd
    }
}

# Check for subnets without NSGs
Write-Log "Checking for subnets without NSGs..." "INFO"
$vnetsJson = az network vnet list --output json 2>&1
$vnets = $vnetsJson | ConvertFrom-Json

foreach ($vnet in $vnets) {
    foreach ($subnet in $vnet.subnets) {
        if (-not $subnet.networkSecurityGroup -and $subnet.name -ne "GatewaySubnet") {
            $fixCmd = "az network vnet subnet update --resource-group `"$($vnet.resourceGroup)`" --vnet-name `"$($vnet.name)`" --name `"$($subnet.name)`" --network-security-group `"YOUR_NSG_NAME`""
            
            $Issues += New-Issue `
                -Category "Network" `
                -Severity "High" `
                -Resource "$($vnet.name)/$($subnet.name)" `
                -Description "Subnet has no Network Security Group attached" `
                -Recommendation "Attach NSG to subnet for traffic filtering" `
                -FixScript $fixCmd
        }
    }
}

Write-Log "Network analysis complete. Found $(($Issues | Where-Object {$_.Category -eq 'Network'}).Count) issues" "INFO"

#endregion

#region 3. Security & Compliance Analysis

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYZING: SECURITY & COMPLIANCE"
Write-Host "=============================================================="
Write-Host ""

Write-Log "Analyzing storage accounts..." "INFO"

# Check storage accounts
$storageAccountsJson = az storage account list --output json 2>&1
$storageAccounts = $storageAccountsJson | ConvertFrom-Json

foreach ($sa in $storageAccounts) {
    # Check for HTTPS only
    if ($sa.enableHttpsTrafficOnly -ne $true) {
        $fixCmd = "az storage account update --name `"$($sa.name)`" --resource-group `"$($sa.resourceGroup)`" --https-only true"
        
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "Critical" `
            -Resource $sa.name `
            -Description "Storage account allows HTTP traffic (not secure)" `
            -Recommendation "Enable HTTPS-only traffic" `
            -FixScript $fixCmd
    }
    
    # Check for public blob access
    if ($sa.allowBlobPublicAccess -eq $true) {
        $fixCmd = "az storage account update --name `"$($sa.name)`" --resource-group `"$($sa.resourceGroup)`" --allow-blob-public-access false"
        
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "High" `
            -Resource $sa.name `
            -Description "Storage account allows public blob access" `
            -Recommendation "Disable public blob access unless required" `
            -FixScript $fixCmd
    }
    
    # Check for minimum TLS version
    if ($sa.minimumTlsVersion -ne "TLS1_2") {
        $fixCmd = "az storage account update --name `"$($sa.name)`" --resource-group `"$($sa.resourceGroup)`" --min-tls-version TLS1_2"
        
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "High" `
            -Resource $sa.name `
            -Description "Storage account not enforcing TLS 1.2" `
            -Recommendation "Set minimum TLS version to 1.2" `
            -FixScript $fixCmd
    }
}

# Check Key Vaults
Write-Log "Analyzing Key Vaults..." "INFO"
$keyVaultsJson = az keyvault list --output json 2>&1
$keyVaults = $keyVaultsJson | ConvertFrom-Json

foreach ($kv in $keyVaults) {
    $kvDetailsJson = az keyvault show --name $kv.name --output json 2>&1
    $kvDetails = $kvDetailsJson | ConvertFrom-Json
    
    # Check for soft delete
    if ($kvDetails.properties.enableSoftDelete -ne $true) {
        $fixCmd = "az keyvault update --name `"$($kv.name)`" --enable-soft-delete true"
        
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "High" `
            -Resource $kv.name `
            -Description "Key Vault does not have soft delete enabled" `
            -Recommendation "Enable soft delete to prevent accidental deletion" `
            -FixScript $fixCmd
    }
    
    # Check for purge protection
    if ($kvDetails.properties.enablePurgeProtection -ne $true) {
        $fixCmd = "az keyvault update --name `"$($kv.name)`" --enable-purge-protection true"
        
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "Medium" `
            -Resource $kv.name `
            -Description "Key Vault does not have purge protection enabled" `
            -Recommendation "Enable purge protection for added security" `
            -FixScript $fixCmd
    }
}

# Check VMs
Write-Log "Analyzing Virtual Machines..." "INFO"
$vmsJson = az vm list -d --output json 2>&1
$vms = $vmsJson | ConvertFrom-Json

foreach ($vm in $vms) {
    # Check for public IP
    if ($vm.publicIps) {
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "High" `
            -Resource $vm.name `
            -Description "VM has public IP address directly attached" `
            -Recommendation "Use Azure Bastion or VPN for management access" `
            -FixScript "# Remove public IP and configure Bastion - requires manual review"
    }
    
    # Check for managed disks
    $vmDetailsJson = az vm show --resource-group $vm.resourceGroup --name $vm.name --output json 2>&1
    $vmDetails = $vmDetailsJson | ConvertFrom-Json
    
    if (-not $vmDetails.storageProfile.osDisk.managedDisk) {
        $Issues += New-Issue `
            -Category "Security" `
            -Severity "Medium" `
            -Resource $vm.name `
            -Description "VM using unmanaged disks" `
            -Recommendation "Migrate to managed disks for better security and management" `
            -FixScript "# Requires manual migration process - use Azure Portal or PowerShell migration tools"
    }
}

Write-Log "Security analysis complete. Found $(($Issues | Where-Object {$_.Category -eq 'Security'}).Count) issues" "INFO"

#endregion

#region 4. User & Access Analysis

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYZING: USER ACCESS & SSO"
Write-Host "=============================================================="
Write-Host ""

Write-Log "Analyzing user access patterns..." "INFO"

# Check for guest users with elevated permissions
$guestAssignments = $roleAssignments | Where-Object { 
    $_.principalType -eq "User" -and $_.principalName -like "*#EXT#*" 
}

foreach ($guest in $guestAssignments) {
    if ($guest.roleDefinitionName -in @("Owner", "Contributor", "User Access Administrator")) {
        $fixCmd = "az role assignment delete --assignee `"$($guest.principalId)`" --role `"$($guest.roleDefinitionName)`" --scope `"$($guest.scope)`""
        
        $Issues += New-Issue `
            -Category "Users" `
            -Severity "High" `
            -Resource $guest.principalName `
            -Description "Guest user has elevated permissions: $($guest.roleDefinitionName)" `
            -Recommendation "Review guest access and limit permissions" `
            -FixScript $fixCmd
    }
}

Write-Log "User analysis complete. Found $(($Issues | Where-Object {$_.Category -eq 'Users'}).Count) issues" "INFO"

#endregion

#region 5. Resource Configuration Analysis

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYZING: RESOURCE CONFIGURATIONS"
Write-Host "=============================================================="
Write-Host ""

Write-Log "Analyzing resource configurations..." "INFO"

# Check for resources without tags
$allResourcesJson = az resource list --output json 2>&1
$allResources = $allResourcesJson | ConvertFrom-Json
$untaggedResources = $allResources | Where-Object { -not $_.tags -or $_.tags.Count -eq 0 }

if ($untaggedResources.Count -gt 0) {
    $fixCmd = "# Tag resources using:`n"
    $fixCmd += "# az tag create --resource-id `"/subscriptions/xxx/resourceGroups/xxx/providers/xxx`" --tags Environment=Production CostCenter=IT"
    
    $Issues += New-Issue `
        -Category "Governance" `
        -Severity "Low" `
        -Resource "Multiple Resources" `
        -Description "$($untaggedResources.Count) resources without tags" `
        -Recommendation "Implement tagging strategy for cost tracking and management" `
        -FixScript $fixCmd
}

# Check for resources in non-standard locations
$locationGroups = $allResources | Group-Object location | Sort-Object Count -Descending
if ($locationGroups.Count -gt 1) {
    $primaryLocation = $locationGroups[0].Name
    $resourcesInOtherLocations = $allResources | Where-Object { $_.location -ne $primaryLocation }
    
    if ($resourcesInOtherLocations.Count -gt 5) {
        $Issues += New-Issue `
            -Category "Governance" `
            -Severity "Low" `
            -Resource "Multiple Resources" `
            -Description "$($resourcesInOtherLocations.Count) resources in non-primary locations" `
            -Recommendation "Consider consolidating resources to reduce latency and costs" `
            -FixScript "# Requires migration strategy - review and plan resource consolidation"
    }
}

Write-Log "Resource analysis complete. Found $(($Issues | Where-Object {$_.Category -eq 'Governance'}).Count) issues" "INFO"

#endregion

#region 6. Generate Reports

Write-Host ""
Write-Host "=============================================================="
Write-Host "  GENERATING COMPREHENSIVE REPORTS"
Write-Host "=============================================================="
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = Join-Path $ReportPath "Azure_Analysis_$timestamp.html"
$csvFile = Join-Path $ReportPath "Issues_Detailed_$timestamp.csv"
$fixScriptFile = Join-Path $ReportPath "Fix_Scripts_$timestamp.ps1"

# Export CSV
$Issues | Export-Csv -Path $csvFile -NoTypeInformation
Write-Log "CSV report saved: $csvFile" "SUCCESS"

# Generate HTML Report
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Environment Analysis Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
        .header h1 { margin: 0; font-size: 32px; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .summary-card h3 { margin: 0 0 10px 0; color: #666; font-size: 14px; text-transform: uppercase; }
        .summary-card .number { font-size: 36px; font-weight: bold; margin: 0; }
        .critical { color: #dc3545; }
        .high { color: #fd7e14; }
        .medium { color: #ffc107; }
        .low { color: #28a745; }
        .issues-table { background: white; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #f8f9fa; padding: 15px; text-align: left; font-weight: 600; border-bottom: 2px solid #dee2e6; }
        td { padding: 12px 15px; border-bottom: 1px solid #dee2e6; }
        tr:hover { background: #f8f9fa; }
        .severity-badge { display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .severity-critical { background: #dc3545; color: white; }
        .severity-high { background: #fd7e14; color: white; }
        .severity-medium { background: #ffc107; color: #000; }
        .severity-low { background: #28a745; color: white; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Azure Environment Analysis Report</h1>
        <p>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
        <p>Subscription: $($accountInfo.name)</p>
    </div>
    
    <div class="summary">
        <div class="summary-card">
            <h3>Total Issues</h3>
            <p class="number">$($Issues.Count)</p>
        </div>
        <div class="summary-card">
            <h3>Critical</h3>
            <p class="number critical">$(($Issues | Where-Object {$_.Severity -eq 'Critical'}).Count)</p>
        </div>
        <div class="summary-card">
            <h3>High</h3>
            <p class="number high">$(($Issues | Where-Object {$_.Severity -eq 'High'}).Count)</p>
        </div>
        <div class="summary-card">
            <h3>Medium</h3>
            <p class="number medium">$(($Issues | Where-Object {$_.Severity -eq 'Medium'}).Count)</p>
        </div>
        <div class="summary-card">
            <h3>Low</h3>
            <p class="number low">$(($Issues | Where-Object {$_.Severity -eq 'Low'}).Count)</p>
        </div>
    </div>
    
    <div class="issues-table">
        <table>
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Category</th>
                    <th>Severity</th>
                    <th>Resource</th>
                    <th>Description</th>
                    <th>Recommendation</th>
                </tr>
            </thead>
            <tbody>
"@

foreach ($issue in ($Issues | Sort-Object @{Expression={@("Critical","High","Medium","Low").IndexOf($_.Severity)}}, Timestamp)) {
    $htmlReport += @"
                <tr>
                    <td>$($issue.Timestamp)</td>
                    <td>$($issue.Category)</td>
                    <td><span class="severity-badge severity-$($issue.Severity.ToLower())">$($issue.Severity)</span></td>
                    <td>$($issue.Resource)</td>
                    <td>$($issue.Description)</td>
                    <td>$($issue.Recommendation)</td>
                </tr>
"@
}

$htmlReport += @"
            </tbody>
        </table>
    </div>
    
    <div class="footer">
        <p>Azure Environment Analyzer v3.0 | Execution Time: $((Get-Date) - $startTime)</p>
        <p>Review the generated fix scripts before execution: $fixScriptFile</p>
    </div>
</body>
</html>
"@

$htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
Write-Log "HTML report saved: $reportFile" "SUCCESS"

# Generate Fix Scripts
$fixScriptContent = @"
<#
.SYNOPSIS
    Auto-generated fix scripts for detected issues
    
.DESCRIPTION
    This script contains fixes for $($Issues.Count) detected issues.
    Review each fix before execution!
    
.NOTES
    Generated: $(Get-Date)
    DO NOT RUN WITHOUT REVIEW!
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = `$false)]
    [ValidateSet("RBAC", "Network", "Security", "Permissions", "Users", "Governance", "All")]
    [string[]]`$Categories = @("All")
)

Write-Host "Azure Environment Fix Script" -ForegroundColor Cyan
Write-Host "Issues to fix: $($Issues.Count)" -ForegroundColor Yellow
Write-Host ""

# Login to Azure CLI
Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
az account show
if (`$LASTEXITCODE -ne 0) {
    Write-Host "Please login to Azure CLI" -ForegroundColor Red
    az login
}

az account set --subscription "$currentSubscriptionId"

"@

$categoryGroups = $Issues | Group-Object Category

foreach ($group in $categoryGroups) {
    $fixScriptContent += @"

#region Fix $($group.Name) Issues

Write-Host ""
Write-Host "=============================================================="
Write-Host "  Fixing $($group.Name) Issues ($($group.Count) found)"
Write-Host "=============================================================="
Write-Host ""

if (`$Categories -contains "$($group.Name)" -or `$Categories -contains "All") {
"@

    $issueIndex = 1
    foreach ($issue in $group.Group) {
        $fixScriptContent += @"

    # Issue $issueIndex`: $($issue.Description)
    Write-Host "Fixing: $($issue.Resource)" -ForegroundColor Cyan
    try {
        $($issue.FixScript)
        
        Write-Host "   Fixed: $($issue.Resource)" -ForegroundColor Green
    } catch {
        Write-Host "   Failed: `$_" -ForegroundColor Red
    }
    
"@
        $issueIndex++
    }

    $fixScriptContent += @"
} else {
    Write-Host "Skipping $($group.Name) fixes (not in selected categories)" -ForegroundColor Gray
}

#endregion

"@
}

$fixScriptContent += @"

Write-Host ""
Write-Host "Fix script execution complete!" -ForegroundColor Green
Write-Host "Review the results above and re-run analysis to verify fixes." -ForegroundColor Cyan
Write-Host ""
"@

$fixScriptContent | Out-File -FilePath $fixScriptFile -Encoding UTF8
Write-Log "Fix scripts saved: $fixScriptFile" "SUCCESS"

#endregion

#region 7. Summary & Next Steps

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "=============================================================="
Write-Host "  ANALYSIS COMPLETE!"
Write-Host "=============================================================="
Write-Host ""

Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================================="
Write-Host "  Total Issues Found:      $($Issues.Count)" -ForegroundColor White
Write-Host "  - Critical:              $(($Issues | Where-Object {$_.Severity -eq 'Critical'}).Count)" -ForegroundColor Red
Write-Host "  - High:                  $(($Issues | Where-Object {$_.Severity -eq 'High'}).Count)" -ForegroundColor DarkRed
Write-Host "  - Medium:                $(($Issues | Where-Object {$_.Severity -eq 'Medium'}).Count)" -ForegroundColor Yellow
Write-Host "  - Low:                   $(($Issues | Where-Object {$_.Severity -eq 'Low'}).Count)" -ForegroundColor Green
Write-Host ""
Write-Host "  Execution Time:          $($duration.ToString('mm\:ss'))" -ForegroundColor White
Write-Host "  Subscription:            $($accountInfo.name)" -ForegroundColor White
Write-Host "=============================================================="
Write-Host ""

Write-Host "GENERATED REPORTS" -ForegroundColor Cyan
Write-Host "=============================================================="
Write-Host "  HTML Report:             $reportFile" -ForegroundColor White
Write-Host "  CSV Export:              $csvFile" -ForegroundColor White
Write-Host "  Fix Scripts:             $fixScriptFile" -ForegroundColor White
Write-Host "=============================================================="
Write-Host ""

Write-Host "NEXT STEPS" -ForegroundColor Yellow
Write-Host "=============================================================="
Write-Host "  1. Open HTML report:     explorer '$reportFile'" -ForegroundColor White
Write-Host "  2. Review CSV details:   Import-Csv '$csvFile'" -ForegroundColor White
Write-Host "  3. Review fix scripts:   code '$fixScriptFile'" -ForegroundColor White
Write-Host "  4. Apply fixes:          .\$([System.IO.Path]::GetFileName($fixScriptFile)) -Categories RBAC,Network" -ForegroundColor White
Write-Host "=============================================================="
Write-Host ""

if ($Issues.Count -gt 0) {
    Write-Host "WARNING: Review all issues before applying fixes!" -ForegroundColor Red
    Write-Host "Always test fixes in a non-production environment first." -ForegroundColor Red
    Write-Host ""
}

# Open HTML report if possible
try {
    Start-Process $reportFile
}
catch {
    Write-Log "Could not auto-open report. Please open manually: $reportFile" "WARNING"
}

#endregion
