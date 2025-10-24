#Requires -Version 5.1
<#
.SYNOPSIS
    Azure DoD and FedRAMP Compliance Audit Script
    
.DESCRIPTION
    Comprehensive security audit script for Azure environments following DoD and FedRAMP compliance requirements.
    Performs read-only analysis across all subscriptions for NIST 800-53 controls, unauthorized access detection,
    RBAC auditing, security misconfigurations, and compliance violations.
    
.NOTES
    Author: Security Audit Team
    Version: 1.0
    Requires: Az PowerShell Module (Az.Accounts, Az.Resources, Az.Security, Az.Monitor, Az.Storage, Az.Network, Az.Compute)
    Permissions: Reader role on all subscriptions being audited
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\AuditReports",
    
    [Parameter(Mandatory=$false)]
    [switch]$AllSubscriptions,
    
    [Parameter(Mandatory=$false)]
    [string[]]$SubscriptionIds,
    
    [Parameter(Mandatory=$false)]
    [int]$ActivityLogDays = 90
)

$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

$AuditStartTime = Get-Date
$ReportTimestamp = $AuditStartTime.ToString("yyyyMMdd_HHmmss")
$OutputPath = Join-Path $OutputPath "DoD_FedRAMP_Audit_$ReportTimestamp"

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    Add-Content -Path (Join-Path $OutputPath "audit_execution.log") -Value $logMessage
}

function Test-AzureModules {
    Write-AuditLog "Checking required Azure PowerShell modules..." -Level Info
    
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Security', 'Az.Monitor', 
                         'Az.Storage', 'Az.Network', 'Az.Compute', 'Az.KeyVault')
    
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-AuditLog "Missing required modules: $($missingModules -join ', ')" -Level Error
        Write-AuditLog "Install missing modules using: Install-Module -Name Az -AllowClobber -Scope CurrentUser" -Level Error
        return $false
    }
    
    Write-AuditLog "All required modules are available" -Level Success
    return $true
}

function Connect-AzureEnvironment {
    Write-AuditLog "Connecting to Azure environment..." -Level Info
    
    try {
        $context = Get-AzContext
        
        if (-not $context) {
            Write-AuditLog "No active Azure context found. Please authenticate..." -Level Warning
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $context = Get-AzContext
        }
        
        Write-AuditLog "Connected to Azure as: $($context.Account.Id)" -Level Success
        Write-AuditLog "Tenant: $($context.Tenant.Id)" -Level Info
        return $true
    }
    catch {
        Write-AuditLog "Failed to connect to Azure: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-AuditSubscriptions {
    Write-AuditLog "Retrieving subscriptions for audit..." -Level Info
    
    try {
        if ($SubscriptionIds -and $SubscriptionIds.Count -gt 0) {
            $subscriptions = @()
            foreach ($subId in $SubscriptionIds) {
                $sub = Get-AzSubscription -SubscriptionId $subId -ErrorAction SilentlyContinue
                if ($sub) {
                    $subscriptions += $sub
                }
            }
        }
        elseif ($AllSubscriptions) {
            $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' }
        }
        else {
            $subscriptions = @(Get-AzContext | Select-Object -ExpandProperty Subscription)
        }
        
        Write-AuditLog "Found $($subscriptions.Count) subscription(s) for audit" -Level Success
        return $subscriptions
    }
    catch {
        Write-AuditLog "Error retrieving subscriptions: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-RBACAssignments {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Auditing RBAC assignments for subscription: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $roleAssignments = Get-AzRoleAssignment -ErrorAction Stop
        
        $rbacData = @()
        
        foreach ($assignment in $roleAssignments) {
            $principalType = $assignment.ObjectType
            $principalName = $assignment.DisplayName
            $principalId = $assignment.ObjectId
            $roleName = $assignment.RoleDefinitionName
            $scope = $assignment.Scope
            
            $isPrivileged = $false
            $riskLevel = "Low"
            
            if ($roleName -match 'Owner|Contributor|Administrator|Global|Security') {
                $isPrivileged = $true
                $riskLevel = "High"
            }
            elseif ($roleName -match 'Write|Delete|Modify') {
                $riskLevel = "Medium"
            }
            
            $rbacData += [PSCustomObject]@{
                SubscriptionId = $SubscriptionId
                SubscriptionName = $SubscriptionName
                PrincipalName = $principalName
                PrincipalId = $principalId
                PrincipalType = $principalType
                RoleDefinitionName = $roleName
                Scope = $scope
                IsPrivileged = $isPrivileged
                RiskLevel = $riskLevel
                AssignedDate = $assignment.CreatedOn
            }
        }
        
        Write-AuditLog "Found $($rbacData.Count) RBAC assignments" -Level Success
        return $rbacData
    }
    catch {
        Write-AuditLog "Error retrieving RBAC assignments: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-SuspiciousActivityLogs {
    param([string]$SubscriptionId, [string]$SubscriptionName, [int]$Days)
    
    Write-AuditLog "Analyzing activity logs for suspicious activities in: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $startTime = (Get-Date).AddDays(-$Days)
        $endTime = Get-Date
        
        $suspiciousActivities = @()
        
        $failedLogins = Get-AzActivityLog -StartTime $startTime -EndTime $endTime -Status Failed `
            -ErrorAction SilentlyContinue | Where-Object { 
                $_.OperationName.Value -match 'Microsoft.Authorization|Microsoft.Resources|Microsoft.Compute|Login|SignIn'
            }
        
        foreach ($activity in $failedLogins) {
            $suspiciousActivities += [PSCustomObject]@{
                SubscriptionId = $SubscriptionId
                SubscriptionName = $SubscriptionName
                Timestamp = $activity.EventTimestamp
                OperationName = $activity.OperationName.LocalizedValue
                Status = $activity.Status.Value
                Caller = $activity.Caller
                ResourceId = $activity.ResourceId
                ResourceType = $activity.ResourceType.Value
                Level = $activity.Level
                CorrelationId = $activity.CorrelationId
                Description = $activity.Properties.statusMessage
                IpAddress = if ($activity.Claims.ipaddr) { $activity.Claims.ipaddr } else { "N/A" }
            }
        }
        
        $privilegedOperations = Get-AzActivityLog -StartTime $startTime -EndTime $endTime `
            -ErrorAction SilentlyContinue | Where-Object { 
                $_.OperationName.Value -match 'roleAssignments/write|roleDefinitions/write|providers/Microsoft.Authorization'
            }
        
        foreach ($activity in $privilegedOperations) {
            $suspiciousActivities += [PSCustomObject]@{
                SubscriptionId = $SubscriptionId
                SubscriptionName = $SubscriptionName
                Timestamp = $activity.EventTimestamp
                OperationName = $activity.OperationName.LocalizedValue
                Status = $activity.Status.Value
                Caller = $activity.Caller
                ResourceId = $activity.ResourceId
                ResourceType = $activity.ResourceType.Value
                Level = $activity.Level
                CorrelationId = $activity.CorrelationId
                Description = "Privileged operation detected"
                IpAddress = if ($activity.Claims.ipaddr) { $activity.Claims.ipaddr } else { "N/A" }
            }
        }
        
        Write-AuditLog "Found $($suspiciousActivities.Count) suspicious activity entries" -Level Success
        return $suspiciousActivities
    }
    catch {
        Write-AuditLog "Error analyzing activity logs: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-SecurityFindings {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Retrieving security findings for: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $securityFindings = @()
        
        $assessments = Get-AzSecurityAssessment -ErrorAction SilentlyContinue
        
        foreach ($assessment in $assessments) {
            if ($assessment.Status.Code -ne 'Healthy') {
                $securityFindings += [PSCustomObject]@{
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    AssessmentName = $assessment.DisplayName
                    Severity = $assessment.Status.Severity
                    Status = $assessment.Status.Code
                    ResourceId = $assessment.ResourceDetails.Id
                    Description = $assessment.Description
                    Remediation = $assessment.Remediation
                    Category = "Security Assessment"
                }
            }
        }
        
        Write-AuditLog "Found $($securityFindings.Count) security findings" -Level Success
        return $securityFindings
    }
    catch {
        Write-AuditLog "Error retrieving security findings: $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Get-NetworkSecurityIssues {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Analyzing network security for: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $networkIssues = @()
        
        $nsgs = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue
        
        foreach ($nsg in $nsgs) {
            foreach ($rule in $nsg.SecurityRules) {
                $isRisky = $false
                $riskReason = ""
                
                if ($rule.Access -eq 'Allow' -and $rule.Direction -eq 'Inbound') {
                    if ($rule.SourceAddressPrefix -eq '*' -or $rule.SourceAddressPrefix -eq 'Internet') {
                        $isRisky = $true
                        $riskReason = "Allows inbound traffic from any source"
                    }
                    
                    if ($rule.DestinationPortRange -match '22|3389|1433|3306|5432|27017') {
                        $isRisky = $true
                        $riskReason += " Exposes sensitive ports (SSH/RDP/Database)"
                    }
                }
                
                if ($isRisky) {
                    $networkIssues += [PSCustomObject]@{
                        SubscriptionId = $SubscriptionId
                        SubscriptionName = $SubscriptionName
                        ResourceName = $nsg.Name
                        ResourceGroup = $nsg.ResourceGroupName
                        Location = $nsg.Location
                        RuleName = $rule.Name
                        Priority = $rule.Priority
                        Direction = $rule.Direction
                        Access = $rule.Access
                        Protocol = $rule.Protocol
                        SourceAddress = $rule.SourceAddressPrefix
                        SourcePort = $rule.SourcePortRange
                        DestinationAddress = $rule.DestinationAddressPrefix
                        DestinationPort = $rule.DestinationPortRange
                        Risk = $riskReason
                        Severity = "High"
                    }
                }
            }
        }
        
        Write-AuditLog "Found $($networkIssues.Count) network security issues" -Level Success
        return $networkIssues
    }
    catch {
        Write-AuditLog "Error analyzing network security: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-StorageSecurityIssues {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Analyzing storage security for: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $storageIssues = @()
        
        $storageAccounts = Get-AzStorageAccount -ErrorAction SilentlyContinue
        
        foreach ($storage in $storageAccounts) {
            $issues = @()
            
            if ($storage.EnableHttpsTrafficOnly -eq $false) {
                $issues += "HTTPS-only traffic not enforced"
            }
            
            if ($storage.AllowBlobPublicAccess -eq $true) {
                $issues += "Public blob access is allowed"
            }
            
            if (-not $storage.Encryption.Services.Blob.Enabled) {
                $issues += "Blob encryption not enabled"
            }
            
            if ($storage.NetworkRuleSet.DefaultAction -eq 'Allow') {
                $issues += "Default network access is Allow (should be Deny)"
            }
            
            if ($issues.Count -gt 0) {
                $storageIssues += [PSCustomObject]@{
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    StorageAccountName = $storage.StorageAccountName
                    ResourceGroup = $storage.ResourceGroupName
                    Location = $storage.Location
                    Sku = $storage.Sku.Name
                    Issues = ($issues -join "; ")
                    Severity = "High"
                    ComplianceControl = "SC-8, SC-13, SC-28 (NIST 800-53)"
                }
            }
        }
        
        Write-AuditLog "Found $($storageIssues.Count) storage security issues" -Level Success
        return $storageIssues
    }
    catch {
        Write-AuditLog "Error analyzing storage security: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-VMSecurityIssues {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Analyzing VM security for: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $vmIssues = @()
        
        $vms = Get-AzVM -ErrorAction SilentlyContinue
        
        foreach ($vm in $vms) {
            $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name `
                -Status -ErrorAction SilentlyContinue
            
            $issues = @()
            
            $hasManagedDisks = $vm.StorageProfile.OsDisk.ManagedDisk -ne $null
            if (-not $hasManagedDisks) {
                $issues += "Not using managed disks"
            }
            
            $extensions = $vm.Extensions
            $hasAntimalware = $extensions | Where-Object { $_.Publisher -match 'Microsoft.Azure.Security' }
            if (-not $hasAntimalware) {
                $issues += "Anti-malware extension not installed"
            }
            
            $hasMonitoring = $extensions | Where-Object { $_.Publisher -match 'Microsoft.EnterpriseCloud.Monitoring' }
            if (-not $hasMonitoring) {
                $issues += "Monitoring agent not installed"
            }
            
            if ($issues.Count -gt 0) {
                $vmIssues += [PSCustomObject]@{
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    VMName = $vm.Name
                    ResourceGroup = $vm.ResourceGroupName
                    Location = $vm.Location
                    OSType = $vm.StorageProfile.OsDisk.OsType
                    VMSize = $vm.HardwareProfile.VmSize
                    PowerState = ($vmDetails.Statuses | Where-Object { $_.Code -match 'PowerState' }).DisplayStatus
                    Issues = ($issues -join "; ")
                    Severity = "Medium"
                    ComplianceControl = "SI-2, SI-3, SI-4 (NIST 800-53)"
                }
            }
        }
        
        Write-AuditLog "Found $($vmIssues.Count) VM security issues" -Level Success
        return $vmIssues
    }
    catch {
        Write-AuditLog "Error analyzing VM security: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Get-KeyVaultSecurityIssues {
    param([string]$SubscriptionId, [string]$SubscriptionName)
    
    Write-AuditLog "Analyzing Key Vault security for: $SubscriptionName" -Level Info
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        $kvIssues = @()
        
        $keyVaults = Get-AzKeyVault -ErrorAction SilentlyContinue
        
        foreach ($kv in $keyVaults) {
            $kvDetails = Get-AzKeyVault -VaultName $kv.VaultName -ErrorAction SilentlyContinue
            
            $issues = @()
            
            if (-not $kvDetails.EnableSoftDelete) {
                $issues += "Soft delete not enabled"
            }
            
            if (-not $kvDetails.EnablePurgeProtection) {
                $issues += "Purge protection not enabled"
            }
            
            if ($kvDetails.NetworkAcls.DefaultAction -eq 'Allow') {
                $issues += "Network default action is Allow (should be Deny)"
            }
            
            if ($issues.Count -gt 0) {
                $kvIssues += [PSCustomObject]@{
                    SubscriptionId = $SubscriptionId
                    SubscriptionName = $SubscriptionName
                    KeyVaultName = $kv.VaultName
                    ResourceGroup = $kv.ResourceGroupName
                    Location = $kv.Location
                    Issues = ($issues -join "; ")
                    Severity = "High"
                    ComplianceControl = "SC-12, SC-13 (NIST 800-53)"
                }
            }
        }
        
        Write-AuditLog "Found $($kvIssues.Count) Key Vault security issues" -Level Success
        return $kvIssues
    }
    catch {
        Write-AuditLog "Error analyzing Key Vault security: $($_.Exception.Message)" -Level Error
        return @()
    }
}

function Export-AuditData {
    param(
        [PSCustomObject[]]$Data,
        [string]$FileName
    )
    
    if ($Data -and $Data.Count -gt 0) {
        $csvPath = Join-Path $OutputPath "$FileName.csv"
        $Data | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-AuditLog "Exported $($Data.Count) records to: $csvPath" -Level Success
    }
}

function New-HTMLReport {
    param(
        [PSCustomObject]$AuditSummary,
        [PSCustomObject[]]$AllFindings
    )
    
    Write-AuditLog "Generating HTML audit report..." -Level Info
    
    $htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DoD FedRAMP Azure Security Audit Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            background-color: #f5f5f5;
            color: #333;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 40px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .header-info-item {
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 5px;
        }
        
        .header-info-item label {
            font-weight: 600;
            display: block;
            margin-bottom: 5px;
            font-size: 0.9em;
            opacity: 0.9;
        }
        
        .header-info-item value {
            font-size: 1.1em;
        }
        
        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #2a5298;
        }
        
        .summary-card.critical {
            border-left-color: #dc3545;
        }
        
        .summary-card.high {
            border-left-color: #ff6b6b;
        }
        
        .summary-card.medium {
            border-left-color: #ffa500;
        }
        
        .summary-card.low {
            border-left-color: #28a745;
        }
        
        .summary-card h3 {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .summary-card .value {
            font-size: 2.5em;
            font-weight: bold;
            color: #2a5298;
        }
        
        .summary-card.critical .value {
            color: #dc3545;
        }
        
        .summary-card.high .value {
            color: #ff6b6b;
        }
        
        .summary-card.medium .value {
            color: #ffa500;
        }
        
        .summary-card.low .value {
            color: #28a745;
        }
        
        .section {
            background: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .section h2 {
            color: #1e3c72;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e0e0e0;
        }
        
        .compliance-status {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .compliance-item {
            padding: 15px;
            background: #f8f9fa;
            border-radius: 5px;
            border-left: 3px solid #28a745;
        }
        
        .compliance-item.non-compliant {
            border-left-color: #dc3545;
        }
        
        .compliance-item h4 {
            font-size: 0.9em;
            color: #666;
            margin-bottom: 5px;
        }
        
        .compliance-item .status {
            font-weight: bold;
            font-size: 1.1em;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
            background: white;
        }
        
        table thead {
            background: #1e3c72;
            color: white;
        }
        
        table th {
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        
        table td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        
        table tbody tr:hover {
            background: #f8f9fa;
        }
        
        .severity-badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .severity-critical {
            background: #dc3545;
            color: white;
        }
        
        .severity-high {
            background: #ff6b6b;
            color: white;
        }
        
        .severity-medium {
            background: #ffa500;
            color: white;
        }
        
        .severity-low {
            background: #28a745;
            color: white;
        }
        
        .alert-box {
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
            border-left: 4px solid;
        }
        
        .alert-box.critical {
            background: #f8d7da;
            border-color: #dc3545;
            color: #721c24;
        }
        
        .alert-box.warning {
            background: #fff3cd;
            border-color: #ffa500;
            color: #856404;
        }
        
        .alert-box.info {
            background: #d1ecf1;
            border-color: #17a2b8;
            color: #0c5460;
        }
        
        .footer {
            text-align: center;
            padding: 30px;
            color: #666;
            font-size: 0.9em;
            margin-top: 40px;
        }
        
        .no-data {
            text-align: center;
            padding: 40px;
            color: #666;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>DoD and FedRAMP Azure Security Audit Report</h1>
            <p>Comprehensive Security Assessment and Compliance Analysis</p>
            <div class="header-info">
                <div class="header-info-item">
                    <label>Report Generated</label>
                    <value>$($AuditSummary.ReportDate)</value>
                </div>
                <div class="header-info-item">
                    <label>Subscriptions Audited</label>
                    <value>$($AuditSummary.SubscriptionsAudited)</value>
                </div>
                <div class="header-info-item">
                    <label>Audit Duration</label>
                    <value>$($AuditSummary.AuditDuration)</value>
                </div>
                <div class="header-info-item">
                    <label>Compliance Framework</label>
                    <value>NIST 800-53 Rev 5</value>
                </div>
            </div>
        </div>
        
        <div class="summary-cards">
            <div class="summary-card critical">
                <h3>Critical Findings</h3>
                <div class="value">$($AuditSummary.CriticalFindings)</div>
            </div>
            <div class="summary-card high">
                <h3>High Severity</h3>
                <div class="value">$($AuditSummary.HighSeverity)</div>
            </div>
            <div class="summary-card medium">
                <h3>Medium Severity</h3>
                <div class="value">$($AuditSummary.MediumSeverity)</div>
            </div>
            <div class="summary-card low">
                <h3>Low Severity</h3>
                <div class="value">$($AuditSummary.LowSeverity)</div>
            </div>
        </div>
        
        <div class="section">
            <h2>Executive Summary</h2>
            <div class="alert-box $($AuditSummary.OverallRiskLevel)">
                <strong>Overall Risk Level: $($AuditSummary.OverallRisk)</strong>
                <p>$($AuditSummary.ExecutiveSummary)</p>
            </div>
            
            <div class="compliance-status">
                <div class="compliance-item">
                    <h4>RBAC Compliance</h4>
                    <div class="status">$($AuditSummary.RBACCompliance)</div>
                </div>
                <div class="compliance-item">
                    <h4>Network Security</h4>
                    <div class="status">$($AuditSummary.NetworkSecurity)</div>
                </div>
                <div class="compliance-item">
                    <h4>Storage Security</h4>
                    <div class="status">$($AuditSummary.StorageSecurity)</div>
                </div>
                <div class="compliance-item">
                    <h4>VM Security</h4>
                    <div class="status">$($AuditSummary.VMSecurity)</div>
                </div>
            </div>
        </div>
        
        <div class="section">
            <h2>Key Compliance Areas - NIST 800-53 Controls</h2>
            <table>
                <thead>
                    <tr>
                        <th>Control Family</th>
                        <th>Control ID</th>
                        <th>Control Name</th>
                        <th>Status</th>
                        <th>Findings</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>Access Control</td>
                        <td>AC-2</td>
                        <td>Account Management</td>
                        <td><span class="severity-badge severity-$($AuditSummary.AC2Status.ToLower())">$($AuditSummary.AC2Status)</span></td>
                        <td>$($AuditSummary.AC2Findings) issues detected</td>
                    </tr>
                    <tr>
                        <td>Access Control</td>
                        <td>AC-3</td>
                        <td>Access Enforcement</td>
                        <td><span class="severity-badge severity-$($AuditSummary.AC3Status.ToLower())">$($AuditSummary.AC3Status)</span></td>
                        <td>$($AuditSummary.AC3Findings) issues detected</td>
                    </tr>
                    <tr>
                        <td>Audit and Accountability</td>
                        <td>AU-2</td>
                        <td>Audit Events</td>
                        <td><span class="severity-badge severity-$($AuditSummary.AU2Status.ToLower())">$($AuditSummary.AU2Status)</span></td>
                        <td>$($AuditSummary.AU2Findings) issues detected</td>
                    </tr>
                    <tr>
                        <td>System and Communications</td>
                        <td>SC-8</td>
                        <td>Transmission Confidentiality</td>
                        <td><span class="severity-badge severity-$($AuditSummary.SC8Status.ToLower())">$($AuditSummary.SC8Status)</span></td>
                        <td>$($AuditSummary.SC8Findings) issues detected</td>
                    </tr>
                    <tr>
                        <td>System and Communications</td>
                        <td>SC-28</td>
                        <td>Protection at Rest</td>
                        <td><span class="severity-badge severity-$($AuditSummary.SC28Status.ToLower())">$($AuditSummary.SC28Status)</span></td>
                        <td>$($AuditSummary.SC28Findings) issues detected</td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>Critical Findings Requiring Immediate Attention</h2>
            $($AuditSummary.CriticalFindingsTable)
        </div>
        
        <div class="section">
            <h2>RBAC and Access Control Analysis</h2>
            <p>Total RBAC assignments analyzed: <strong>$($AuditSummary.TotalRBACAssignments)</strong></p>
            <p>Privileged role assignments: <strong>$($AuditSummary.PrivilegedAssignments)</strong></p>
            $($AuditSummary.RBACTable)
        </div>
        
        <div class="section">
            <h2>Suspicious Activity and Failed Login Attempts</h2>
            <p>Suspicious activities detected: <strong>$($AuditSummary.SuspiciousActivities)</strong></p>
            <p>Analysis period: Last $ActivityLogDays days</p>
            $($AuditSummary.SuspiciousActivityTable)
        </div>
        
        <div class="section">
            <h2>Network Security Issues</h2>
            $($AuditSummary.NetworkIssuesTable)
        </div>
        
        <div class="section">
            <h2>Storage Account Security</h2>
            $($AuditSummary.StorageIssuesTable)
        </div>
        
        <div class="section">
            <h2>Virtual Machine Security</h2>
            $($AuditSummary.VMIssuesTable)
        </div>
        
        <div class="section">
            <h2>Key Vault Security</h2>
            $($AuditSummary.KeyVaultIssuesTable)
        </div>
        
        <div class="section">
            <h2>Recommendations for Compliance</h2>
            <div class="alert-box warning">
                <h3>Priority Actions Required:</h3>
                <ol>
                    <li>Review and remediate all Critical and High severity findings immediately</li>
                    <li>Implement least privilege access controls for all RBAC assignments</li>
                    <li>Enable Azure Security Center Standard tier for enhanced threat detection</li>
                    <li>Ensure all storage accounts enforce HTTPS and encryption at rest</li>
                    <li>Review and restrict network security group rules exposing sensitive ports</li>
                    <li>Enable soft delete and purge protection on all Key Vaults</li>
                    <li>Implement continuous monitoring and alerting for suspicious activities</li>
                    <li>Conduct regular access reviews for privileged accounts</li>
                    <li>Document all findings in Plan of Action and Milestones (POAM)</li>
                    <li>Schedule quarterly security assessments for continuous compliance</li>
                </ol>
            </div>
        </div>
        
        <div class="footer">
            <p>This report was generated automatically for DoD and FedRAMP compliance purposes.</p>
            <p>Report generated on: $($AuditSummary.ReportDate)</p>
            <p>All data is current as of the audit execution time.</p>
            <p><strong>CONFIDENTIAL - FOR OFFICIAL USE ONLY</strong></p>
        </div>
    </div>
</body>
</html>
"@
    
    $htmlPath = Join-Path $OutputPath "DoD_FedRAMP_Audit_Report.html"
    $htmlReport | Out-File -FilePath $htmlPath -Encoding UTF8
    
    Write-AuditLog "HTML report generated: $htmlPath" -Level Success
    return $htmlPath
}

function ConvertTo-HTMLTable {
    param([PSCustomObject[]]$Data, [int]$MaxRows = 100)
    
    if (-not $Data -or $Data.Count -eq 0) {
        return "<div class='no-data'>No data available for this section</div>"
    }
    
    $displayData = $Data | Select-Object -First $MaxRows
    $properties = $displayData[0].PSObject.Properties.Name
    
    $html = "<table><thead><tr>"
    foreach ($prop in $properties) {
        $html += "<th>$prop</th>"
    }
    $html += "</tr></thead><tbody>"
    
    foreach ($row in $displayData) {
        $html += "<tr>"
        foreach ($prop in $properties) {
            $value = $row.$prop
            if ($prop -match 'Severity|Risk') {
                $html += "<td><span class='severity-badge severity-$($value.ToLower())'>$value</span></td>"
            }
            else {
                $html += "<td>$value</td>"
            }
        }
        $html += "</tr>"
    }
    
    $html += "</tbody></table>"
    
    if ($Data.Count -gt $MaxRows) {
        $html += "<p style='margin-top: 10px; font-style: italic;'>Showing $MaxRows of $($Data.Count) total records. See CSV export for complete data.</p>"
    }
    
    return $html
}

Write-AuditLog "========================================" -Level Info
Write-AuditLog "DoD and FedRAMP Azure Security Audit" -Level Info
Write-AuditLog "========================================" -Level Info

if (-not (Test-AzureModules)) {
    Write-AuditLog "Cannot continue without required modules" -Level Error
    exit 1
}

if (-not (Connect-AzureEnvironment)) {
    Write-AuditLog "Cannot continue without Azure connection" -Level Error
    exit 1
}

$subscriptions = Get-AuditSubscriptions

if ($subscriptions.Count -eq 0) {
    Write-AuditLog "No subscriptions found to audit" -Level Error
    exit 1
}

$allRBACData = @()
$allSuspiciousActivities = @()
$allSecurityFindings = @()
$allNetworkIssues = @()
$allStorageIssues = @()
$allVMIssues = @()
$allKeyVaultIssues = @()

foreach ($subscription in $subscriptions) {
    Write-AuditLog "========================================" -Level Info
    Write-AuditLog "Auditing Subscription: $($subscription.Name)" -Level Info
    Write-AuditLog "Subscription ID: $($subscription.Id)" -Level Info
    Write-AuditLog "========================================" -Level Info
    
    $allRBACData += Get-RBACAssignments -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
    $allSuspiciousActivities += Get-SuspiciousActivityLogs -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name -Days $ActivityLogDays
    $allSecurityFindings += Get-SecurityFindings -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
    $allNetworkIssues += Get-NetworkSecurityIssues -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
    $allStorageIssues += Get-StorageSecurityIssues -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
    $allVMIssues += Get-VMSecurityIssues -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
    $allKeyVaultIssues += Get-KeyVaultSecurityIssues -SubscriptionId $subscription.Id -SubscriptionName $subscription.Name
}

Write-AuditLog "========================================" -Level Info
Write-AuditLog "Exporting audit data..." -Level Info
Write-AuditLog "========================================" -Level Info

Export-AuditData -Data $allRBACData -FileName "RBAC_Assignments"
Export-AuditData -Data $allSuspiciousActivities -FileName "Suspicious_Activities"
Export-AuditData -Data $allSecurityFindings -FileName "Security_Findings"
Export-AuditData -Data $allNetworkIssues -FileName "Network_Security_Issues"
Export-AuditData -Data $allStorageIssues -FileName "Storage_Security_Issues"
Export-AuditData -Data $allVMIssues -FileName "VM_Security_Issues"
Export-AuditData -Data $allKeyVaultIssues -FileName "KeyVault_Security_Issues"

$auditEndTime = Get-Date
$auditDuration = $auditEndTime - $AuditStartTime

$criticalFindings = @($allNetworkIssues | Where-Object { $_.Severity -eq 'High' }).Count + 
                    @($allStorageIssues | Where-Object { $_.Severity -eq 'High' }).Count +
                    @($allKeyVaultIssues | Where-Object { $_.Severity -eq 'High' }).Count

$highSeverity = @($allSecurityFindings | Where-Object { $_.Severity -eq 'High' }).Count +
                @($allVMIssues | Where-Object { $_.Severity -match 'High|Medium' }).Count

$mediumSeverity = @($allSecurityFindings | Where-Object { $_.Severity -eq 'Medium' }).Count +
                  @($allRBACData | Where-Object { $_.RiskLevel -eq 'Medium' }).Count

$lowSeverity = @($allSecurityFindings | Where-Object { $_.Severity -eq 'Low' }).Count +
               @($allRBACData | Where-Object { $_.RiskLevel -eq 'Low' }).Count

$overallRisk = if ($criticalFindings -gt 10) { "Critical" }
               elseif ($criticalFindings -gt 5) { "High" }
               elseif ($highSeverity -gt 20) { "High" }
               elseif ($mediumSeverity -gt 30) { "Medium" }
               else { "Low" }

$privilegedRBAC = @($allRBACData | Where-Object { $_.IsPrivileged -eq $true }).Count

$auditSummary = [PSCustomObject]@{
    ReportDate = $auditEndTime.ToString("yyyy-MM-dd HH:mm:ss")
    SubscriptionsAudited = $subscriptions.Count
    AuditDuration = "$([math]::Round($auditDuration.TotalMinutes, 2)) minutes"
    CriticalFindings = $criticalFindings
    HighSeverity = $highSeverity
    MediumSeverity = $mediumSeverity
    LowSeverity = $lowSeverity
    OverallRisk = $overallRisk
    OverallRiskLevel = $overallRisk.ToLower()
    ExecutiveSummary = "Audit completed across $($subscriptions.Count) subscription(s). Total of $($criticalFindings + $highSeverity + $mediumSeverity + $lowSeverity) findings identified requiring attention. Immediate remediation required for $criticalFindings critical issues."
    RBACCompliance = "$($allRBACData.Count) assignments reviewed"
    NetworkSecurity = "$($allNetworkIssues.Count) issues found"
    StorageSecurity = "$($allStorageIssues.Count) issues found"
    VMSecurity = "$($allVMIssues.Count) issues found"
    AC2Status = if ($privilegedRBAC -gt 50) { "High" } elseif ($privilegedRBAC -gt 20) { "Medium" } else { "Low" }
    AC2Findings = $privilegedRBAC
    AC3Status = if (@($allRBACData | Where-Object { $_.RiskLevel -eq 'High' }).Count -gt 10) { "High" } else { "Medium" }
    AC3Findings = @($allRBACData | Where-Object { $_.RiskLevel -eq 'High' }).Count
    AU2Status = if ($allSuspiciousActivities.Count -gt 50) { "High" } elseif ($allSuspiciousActivities.Count -gt 10) { "Medium" } else { "Low" }
    AU2Findings = $allSuspiciousActivities.Count
    SC8Status = if (@($allStorageIssues | Where-Object { $_.Issues -match 'HTTPS' }).Count -gt 0) { "High" } else { "Low" }
    SC8Findings = @($allStorageIssues | Where-Object { $_.Issues -match 'HTTPS' }).Count
    SC28Status = if (@($allStorageIssues | Where-Object { $_.Issues -match 'encryption' }).Count -gt 0) { "High" } else { "Low" }
    SC28Findings = @($allStorageIssues | Where-Object { $_.Issues -match 'encryption' }).Count
    TotalRBACAssignments = $allRBACData.Count
    PrivilegedAssignments = $privilegedRBAC
    SuspiciousActivities = $allSuspiciousActivities.Count
    CriticalFindingsTable = ConvertTo-HTMLTable -Data ($allNetworkIssues + $allStorageIssues + $allKeyVaultIssues | Where-Object { $_.Severity -eq 'High' } | Select-Object -First 50)
    RBACTable = ConvertTo-HTMLTable -Data ($allRBACData | Where-Object { $_.IsPrivileged -eq $true } | Select-Object -First 50)
    SuspiciousActivityTable = ConvertTo-HTMLTable -Data ($allSuspiciousActivities | Select-Object -First 50)
    NetworkIssuesTable = ConvertTo-HTMLTable -Data $allNetworkIssues
    StorageIssuesTable = ConvertTo-HTMLTable -Data $allStorageIssues
    VMIssuesTable = ConvertTo-HTMLTable -Data $allVMIssues
    KeyVaultIssuesTable = ConvertTo-HTMLTable -Data $allKeyVaultIssues
}

$htmlReportPath = New-HTMLReport -AuditSummary $auditSummary -AllFindings ($allRBACData + $allSuspiciousActivities + $allSecurityFindings)

Write-AuditLog "========================================" -Level Success
Write-AuditLog "AUDIT COMPLETED SUCCESSFULLY" -Level Success
Write-AuditLog "========================================" -Level Success
Write-AuditLog "Total Subscriptions Audited: $($subscriptions.Count)" -Level Info
Write-AuditLog "Total Findings: $($criticalFindings + $highSeverity + $mediumSeverity + $lowSeverity)" -Level Info
Write-AuditLog "Critical Findings: $criticalFindings" -Level Info
Write-AuditLog "High Severity: $highSeverity" -Level Info
Write-AuditLog "Medium Severity: $mediumSeverity" -Level Info
Write-AuditLog "Low Severity: $lowSeverity" -Level Info
Write-AuditLog "Overall Risk Level: $overallRisk" -Level Info
Write-AuditLog "Audit Duration: $([math]::Round($auditDuration.TotalMinutes, 2)) minutes" -Level Info
Write-AuditLog "========================================" -Level Success
Write-AuditLog "OUTPUT LOCATION: $OutputPath" -Level Success
Write-AuditLog "HTML Report: $htmlReportPath" -Level Success
Write-AuditLog "========================================" -Level Success

Write-Host ""
Write-Host "Opening HTML report in default browser..." -ForegroundColor Cyan
Start-Process $htmlReportPath
