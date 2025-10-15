#Requires -Version 5.1

<#
.SYNOPSIS
    PYX Health - Azure Audit - SAVES TO C:\Scripts\Azure-Analysis-Reports
#>

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - AZURE AUDIT" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# HARDCODED PATH - YOUR WORK LAPTOP
$ReportsFolder = "C:\Scripts\Azure-Analysis-Reports"

Write-Host "Reports will save to: $ReportsFolder" -ForegroundColor Yellow

# Create folder if it doesn't exist
if (-not (Test-Path $ReportsFolder)) {
    Write-Host "Creating folder..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ReportsFolder -Force | Out-Null
    Write-Host "  Created: $ReportsFolder" -ForegroundColor Green
} else {
    Write-Host "  Folder exists: $ReportsFolder" -ForegroundColor Green
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$htmlReportPath = "$ReportsFolder\Azure-Audit-$timestamp.html"
$csvReportPath = "$ReportsFolder\Azure-Audit-$timestamp.csv"

Write-Host ""
Write-Host "Files will be:" -ForegroundColor Yellow
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host ""

# Check Azure CLI
Write-Host "Checking Azure CLI..." -ForegroundColor Yellow
try {
    $null = az version 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "  Azure CLI: OK" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Azure CLI not installed!" -ForegroundColor Red
    exit 1
}

# Check login
Write-Host "Checking login..." -ForegroundColor Yellow
try {
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    $account = $accountJson | ConvertFrom-Json
    Write-Host "  Logged in: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Not logged in!" -ForegroundColor Red
    Write-Host "  Run: az login" -ForegroundColor Yellow
    exit 1
}

# Get subscriptions
Write-Host ""
Write-Host "Getting subscriptions..." -ForegroundColor Yellow
$subsJson = az account list 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to get subscriptions!" -ForegroundColor Red
    exit 1
}

$subscriptions = $subsJson | ConvertFrom-Json
Write-Host "Found: $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

# Initialize
$global:findings = @()
$global:issues = @{ Critical = 0; High = 0; Medium = 0; Low = 0 }
$global:counts = @{
    Subscriptions = $subscriptions.Count
    ResourceGroups = 0
    VMs = 0
    Storage = 0
    KeyVaults = 0
    SqlServers = 0
    SqlDatabases = 0
    AppServices = 0
    VNets = 0
    Subnets = 0
    NSGs = 0
    NSGRules = 0
    PublicIPs = 0
    LoadBalancers = 0
    Alerts = 0
    RBAC = 0
}

function Add-Finding {
    param($Severity, $Subscription, $Resource, $Type, $Issue, $Recommendation, $Impact)
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

Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host "  STARTING AUDIT" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host ""

$subNum = 0
foreach ($sub in $subscriptions) {
    $subNum++
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  SUBSCRIPTION $subNum/$($subscriptions.Count): $($sub.name)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    az account set --subscription $sub.id 2>&1 | Out-Null
    
    # Resource Groups
    Write-Host "[1/12] Resource Groups..." -ForegroundColor Yellow
    $rgJson = az group list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rgJson)) {
        $rgs = $rgJson | ConvertFrom-Json
        $global:counts.ResourceGroups += $rgs.Count
        Write-Host "  Found: $($rgs.Count)" -ForegroundColor Green
        
        foreach ($rg in $rgs) {
            $resJson = az resource list --resource-group $rg.name 2>&1
            if ($LASTEXITCODE -eq 0) {
                $resources = $resJson | ConvertFrom-Json
                if ($resources.Count -eq 0) {
                    Add-Finding "Low" $sub.name $rg.name "Resource Group" "Empty resource group" "Delete if not needed" "Clutter"
                }
            }
        }
    }
    
    # VMs
    Write-Host "[2/12] Virtual Machines..." -ForegroundColor Yellow
    $vmJson = az vm list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($vmJson)) {
        $vms = $vmJson | ConvertFrom-Json
        $global:counts.VMs += $vms.Count
        Write-Host "  Found: $($vms.Count)" -ForegroundColor Green
        
        foreach ($vm in $vms) {
            if ($vm.hardwareProfile.vmSize -match "Standard_D") {
                Add-Finding "Medium" $sub.name $vm.name "VM" "VM may be oversized" "Review and downsize" "Cost savings"
            }
            
            $diagJson = az monitor diagnostic-settings list --resource $vm.id 2>&1
            if ($LASTEXITCODE -eq 0) {
                $diags = $diagJson | ConvertFrom-Json
                if ($diags.Count -eq 0) {
                    Add-Finding "Medium" $sub.name $vm.name "VM" "No diagnostic logging" "Enable diagnostics" "Limited troubleshooting"
                }
            }
        }
    }
    
    # Storage
    Write-Host "[3/12] Storage Accounts..." -ForegroundColor Yellow
    $storageJson = az storage account list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($storageJson)) {
        $storage = $storageJson | ConvertFrom-Json
        $global:counts.Storage += $storage.Count
        Write-Host "  Found: $($storage.Count)" -ForegroundColor Green
        
        foreach ($sa in $storage) {
            if ($sa.enableHttpsTrafficOnly -ne $true) {
                Add-Finding "High" $sub.name $sa.name "Storage" "HTTPS-only not enabled" "Enable HTTPS-only" "Insecure"
            }
            if ($sa.minimumTlsVersion -ne "TLS1_2") {
                Add-Finding "High" $sub.name $sa.name "Storage" "TLS 1.2 not enforced" "Set TLS 1.2" "Weak encryption"
            }
            if ($sa.allowBlobPublicAccess -eq $true) {
                Add-Finding "Medium" $sub.name $sa.name "Storage" "Public blob access enabled" "Disable public access" "Data exposure"
            }
            if ($sa.networkRuleSet.defaultAction -eq "Allow") {
                Add-Finding "High" $sub.name $sa.name "Storage" "Storage accessible from all networks" "Configure firewall" "Unrestricted access"
            }
        }
    }
    
    # Key Vaults
    Write-Host "[4/12] Key Vaults..." -ForegroundColor Yellow
    $kvJson = az keyvault list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($kvJson)) {
        $kvs = $kvJson | ConvertFrom-Json
        $global:counts.KeyVaults += $kvs.Count
        Write-Host "  Found: $($kvs.Count)" -ForegroundColor Green
        
        foreach ($kv in $kvs) {
            if ($kv.properties.enableSoftDelete -ne $true) {
                Add-Finding "High" $sub.name $kv.name "Key Vault" "Soft delete not enabled" "Enable soft delete" "Cannot recover secrets"
            }
            if ($kv.properties.enablePurgeProtection -ne $true) {
                Add-Finding "Medium" $sub.name $kv.name "Key Vault" "Purge protection not enabled" "Enable purge protection" "Can be deleted"
            }
            if ($kv.properties.networkAcls.defaultAction -eq "Allow") {
                Add-Finding "High" $sub.name $kv.name "Key Vault" "Accessible from all networks" "Configure network restrictions" "Unrestricted access"
            }
        }
    }
    
    # SQL
    Write-Host "[5/12] SQL Servers..." -ForegroundColor Yellow
    $sqlJson = az sql server list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($sqlJson)) {
        $sqls = $sqlJson | ConvertFrom-Json
        $global:counts.SqlServers += $sqls.Count
        Write-Host "  Found: $($sqls.Count)" -ForegroundColor Green
        
        foreach ($sql in $sqls) {
            $dbJson = az sql db list --server $sql.name --resource-group $sql.resourceGroup 2>&1
            if ($LASTEXITCODE -eq 0) {
                $dbs = $dbJson | ConvertFrom-Json
                $global:counts.SqlDatabases += $dbs.Count
            }
            
            $fwJson = az sql server firewall-rule list --server $sql.name --resource-group $sql.resourceGroup 2>&1
            if ($LASTEXITCODE -eq 0) {
                $rules = $fwJson | ConvertFrom-Json
                foreach ($rule in $rules) {
                    if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "255.255.255.255") {
                        Add-Finding "Critical" $sub.name "$($sql.name)/$($rule.name)" "SQL Firewall" "SQL open to internet" "Restrict IPs" "Database exposed"
                    }
                    if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "0.0.0.0") {
                        Add-Finding "High" $sub.name "$($sql.name)/$($rule.name)" "SQL Firewall" "Allow Azure Services rule" "Use VNet endpoints" "Broad access"
                    }
                }
            }
            
            $auditJson = az sql server audit-policy show --name $sql.name --resource-group $sql.resourceGroup 2>&1
            if ($LASTEXITCODE -eq 0) {
                $audit = $auditJson | ConvertFrom-Json
                if ($audit.state -ne "Enabled") {
                    Add-Finding "Medium" $sub.name $sql.name "SQL Server" "Auditing not enabled" "Enable auditing" "No audit trail"
                }
            }
        }
    }
    
    # App Services
    Write-Host "[6/12] App Services..." -ForegroundColor Yellow
    $appJson = az webapp list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($appJson)) {
        $apps = $appJson | ConvertFrom-Json
        $global:counts.AppServices += $apps.Count
        Write-Host "  Found: $($apps.Count)" -ForegroundColor Green
        
        foreach ($app in $apps) {
            if ($app.httpsOnly -ne $true) {
                Add-Finding "High" $sub.name $app.name "App Service" "HTTPS-only not enforced" "Enable HTTPS-only" "Insecure"
            }
            if ($app.siteConfig.minTlsVersion -ne "1.2") {
                Add-Finding "High" $sub.name $app.name "App Service" "TLS 1.2 not enforced" "Set TLS 1.2" "Weak TLS"
            }
        }
    }
    
    # VNets
    Write-Host "[7/12] Virtual Networks..." -ForegroundColor Yellow
    $vnetJson = az network vnet list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($vnetJson)) {
        $vnets = $vnetJson | ConvertFrom-Json
        $global:counts.VNets += $vnets.Count
        Write-Host "  Found: $($vnets.Count)" -ForegroundColor Green
        
        foreach ($vnet in $vnets) {
            if ($vnet.subnets) {
                $global:counts.Subnets += $vnet.subnets.Count
                foreach ($subnet in $vnet.subnets) {
                    if ($subnet.networkSecurityGroup -eq $null) {
                        Add-Finding "Medium" $sub.name "$($vnet.name)/$($subnet.name)" "Subnet" "No NSG attached" "Attach NSG" "No filtering"
                    }
                }
            }
            if ($vnet.enableDdosProtection -ne $true) {
                Add-Finding "Low" $sub.name $vnet.name "VNet" "DDoS protection not enabled" "Enable DDoS" "Vulnerable"
            }
        }
    }
    
    # NSGs
    Write-Host "[8/12] Network Security Groups..." -ForegroundColor Yellow
    $nsgJson = az network nsg list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($nsgJson)) {
        $nsgs = $nsgJson | ConvertFrom-Json
        $global:counts.NSGs += $nsgs.Count
        Write-Host "  Found: $($nsgs.Count)" -ForegroundColor Green
        
        foreach ($nsg in $nsgs) {
            $rulesJson = az network nsg rule list --nsg-name $nsg.name --resource-group $nsg.resourceGroup 2>&1
            if ($LASTEXITCODE -eq 0) {
                $rules = $rulesJson | ConvertFrom-Json
                $global:counts.NSGRules += $rules.Count
                
                foreach ($rule in $rules) {
                    if ($rule.direction -eq "Inbound" -and $rule.access -eq "Allow" -and $rule.sourceAddressPrefix -in @("*", "Internet", "0.0.0.0/0")) {
                        $port = if ($rule.destinationPortRange) { $rule.destinationPortRange } else { "multiple" }
                        $severity = if ($port -in @("22", "3389", "1433", "3306", "5432")) { "Critical" } else { "Medium" }
                        Add-Finding $severity $sub.name "$($nsg.name)/$($rule.name)" "NSG Rule" "Allow from Internet on port $port" "Restrict IPs" "Exposed"
                    }
                }
            }
        }
    }
    
    # Public IPs
    Write-Host "[9/12] Public IPs..." -ForegroundColor Yellow
    $pipJson = az network public-ip list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pipJson)) {
        $pips = $pipJson | ConvertFrom-Json
        $global:counts.PublicIPs += $pips.Count
        Write-Host "  Found: $($pips.Count)" -ForegroundColor Green
        
        foreach ($pip in $pips) {
            if ($pip.ipConfiguration -eq $null) {
                Add-Finding "Low" $sub.name $pip.name "Public IP" "Unused public IP" "Delete" "Wasted cost"
            }
        }
    }
    
    # Load Balancers
    Write-Host "[10/12] Load Balancers..." -ForegroundColor Yellow
    $lbJson = az network lb list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($lbJson)) {
        $lbs = $lbJson | ConvertFrom-Json
        $global:counts.LoadBalancers += $lbs.Count
        Write-Host "  Found: $($lbs.Count)" -ForegroundColor Green
    }
    
    # Alerts
    Write-Host "[11/12] Alert Rules..." -ForegroundColor Yellow
    $alertJson = az monitor metrics alert list 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($alertJson)) {
        $alerts = $alertJson | ConvertFrom-Json
        $global:counts.Alerts += $alerts.Count
        Write-Host "  Found: $($alerts.Count)" -ForegroundColor Green
        
        if ($alerts.Count -eq 0) {
            Add-Finding "High" $sub.name "Subscription" "Alerts" "No alerts configured" "Configure alerts" "No monitoring"
        }
        
        foreach ($alert in $alerts) {
            if ($alert.enabled -ne $true) {
                Add-Finding "Medium" $sub.name $alert.name "Alert" "Alert disabled" "Enable or delete" "Not monitoring"
            }
        }
    }
    
    # RBAC
    Write-Host "[12/12] RBAC..." -ForegroundColor Yellow
    $rbacJson = az role assignment list --all 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($rbacJson)) {
        $rbac = $rbacJson | ConvertFrom-Json
        $global:counts.RBAC += $rbac.Count
        Write-Host "  Found: $($rbac.Count)" -ForegroundColor Green
        
        foreach ($assignment in $rbac) {
            if ([string]::IsNullOrEmpty($assignment.principalName)) {
                Add-Finding "Medium" $sub.name $assignment.roleDefinitionName "RBAC" "Stale assignment" "Remove orphaned" "Security hygiene"
            }
        }
        
        $owners = $rbac | Where-Object { $_.roleDefinitionName -eq "Owner" -and $_.principalType -eq "User" }
        if ($owners.Count -gt 5) {
            Add-Finding "High" $sub.name "Subscription" "RBAC" "$($owners.Count) users with Owner role" "Minimize" "Too many admins"
        }
    }
}

# SAVE CSV
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  SAVING REPORTS" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Saving CSV..." -ForegroundColor Yellow
try {
    $global:findings | Export-Csv -Path $csvReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "  CSV SAVED: $csvReportPath" -ForegroundColor Green
    
    if (Test-Path $csvReportPath) {
        $csvSize = (Get-Item $csvReportPath).Length
        Write-Host "  Size: $([math]::Round($csvSize/1KB, 2)) KB" -ForegroundColor White
        Write-Host "  Findings: $($global:findings.Count)" -ForegroundColor White
    } else {
        Write-Host "  ERROR: CSV file not found after save!" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# GENERATE HTML
Write-Host ""
Write-Host "Generating HTML..." -ForegroundColor Yellow

$totalIssues = $global:issues.Critical + $global:issues.High + $global:issues.Medium + $global:issues.Low

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>PYX Health - Azure Audit</title>
<meta charset="UTF-8">
<style>
body { font-family: Arial; padding: 20px; background: #f5f5f5; }
.header { background: #0078d4; color: white; padding: 30px; border-radius: 8px; margin-bottom: 20px; }
.header h1 { margin: 0 0 10px 0; }
.section { background: white; padding: 20px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
.section h2 { color: #0078d4; margin-top: 0; }
.boxes { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
.box { background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #0078d4; }
.box-value { font-size: 36px; font-weight: bold; color: #0078d4; margin-bottom: 5px; }
.box-label { font-size: 13px; color: #666; text-transform: uppercase; }
.metric { display: inline-block; margin: 10px 20px; text-align: center; }
.metric-value { font-size: 42px; font-weight: bold; }
.critical { color: #d13438; }
.high { color: #ff8c00; }
.medium { color: #ffb900; }
.low { color: #107c10; }
table { width: 100%; border-collapse: collapse; margin-top: 15px; }
th { background: #0078d4; color: white; padding: 12px; text-align: left; }
td { padding: 10px; border-bottom: 1px solid #ddd; }
.badge { padding: 5px 10px; border-radius: 12px; font-size: 11px; font-weight: bold; }
.badge-critical { background: #fde7e9; color: #d13438; }
.badge-high { background: #fff4ce; color: #ca5010; }
.badge-medium { background: #fff9e6; color: #c19c00; }
.badge-low { background: #dff6dd; color: #107c10; }
</style>
</head>
<body>
<div class="header">
<h1>PYX HEALTH - AZURE AUDIT</h1>
<p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p>Subscriptions: $($global:counts.Subscriptions)</p>
<p>Reports saved to: $ReportsFolder</p>
</div>

<div class="section">
<h2>EXECUTIVE SUMMARY</h2>
<div class="metric">
<div class="metric-value">$totalIssues</div>
<div>Total Issues</div>
</div>
<div class="metric">
<div class="metric-value critical">$($global:issues.Critical)</div>
<div>Critical</div>
</div>
<div class="metric">
<div class="metric-value high">$($global:issues.High)</div>
<div>High</div>
</div>
<div class="metric">
<div class="metric-value medium">$($global:issues.Medium)</div>
<div>Medium</div>
</div>
<div class="metric">
<div class="metric-value low">$($global:issues.Low)</div>
<div>Low</div>
</div>
</div>

<div class="section">
<h2>RESOURCE INVENTORY</h2>
<div class="boxes">
<div class="box">
<div class="box-value">$($global:counts.Subscriptions)</div>
<div class="box-label">Subscriptions</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.ResourceGroups)</div>
<div class="box-label">Resource Groups</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.VMs)</div>
<div class="box-label">Virtual Machines</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.Storage)</div>
<div class="box-label">Storage Accounts</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.KeyVaults)</div>
<div class="box-label">Key Vaults</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.SqlServers)</div>
<div class="box-label">SQL Servers</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.SqlDatabases)</div>
<div class="box-label">SQL Databases</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.AppServices)</div>
<div class="box-label">App Services</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.VNets)</div>
<div class="box-label">Virtual Networks</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.Subnets)</div>
<div class="box-label">Subnets</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.NSGs)</div>
<div class="box-label">Network Security Groups</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.NSGRules)</div>
<div class="box-label">NSG Rules</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.PublicIPs)</div>
<div class="box-label">Public IPs</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.LoadBalancers)</div>
<div class="box-label">Load Balancers</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.Alerts)</div>
<div class="box-label">Alert Rules</div>
</div>
<div class="box">
<div class="box-value">$($global:counts.RBAC)</div>
<div class="box-label">RBAC Assignments</div>
</div>
</div>
</div>

<div class="section">
<h2>FINDINGS</h2>
<table>
<tr>
<th>Severity</th>
<th>Subscription</th>
<th>Resource</th>
<th>Type</th>
<th>Issue</th>
<th>Recommendation</th>
</tr>
"@

foreach ($f in ($global:findings | Sort-Object @{Expression={switch($_.Severity){"Critical"{1}"High"{2}"Medium"{3}"Low"{4}}}})) {
    $badge = "badge-" + $f.Severity.ToLower()
    $html += "<tr><td><span class='badge $badge'>$($f.Severity)</span></td><td>$($f.Subscription)</td><td>$($f.Resource)</td><td>$($f.Type)</td><td>$($f.Issue)</td><td>$($f.Recommendation)</td></tr>"
}

$html += "</table></div></body></html>"

try {
    $html | Out-File -FilePath $htmlReportPath -Encoding UTF8 -Force
    Write-Host "  HTML SAVED: $htmlReportPath" -ForegroundColor Green
    
    if (Test-Path $htmlReportPath) {
        $htmlSize = (Get-Item $htmlReportPath).Length
        Write-Host "  Size: $([math]::Round($htmlSize/1KB, 2)) KB" -ForegroundColor White
    } else {
        Write-Host "  ERROR: HTML file not found after save!" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# SUMMARY
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "RESOURCES:" -ForegroundColor Cyan
Write-Host "  Subscriptions: $($global:counts.Subscriptions)" -ForegroundColor White
Write-Host "  Resource Groups: $($global:counts.ResourceGroups)" -ForegroundColor White
Write-Host "  VMs: $($global:counts.VMs)" -ForegroundColor White
Write-Host "  Storage: $($global:counts.Storage)" -ForegroundColor White
Write-Host "  Key Vaults: $($global:counts.KeyVaults)" -ForegroundColor White
Write-Host "  SQL Servers: $($global:counts.SqlServers)" -ForegroundColor White
Write-Host "  SQL Databases: $($global:counts.SqlDatabases)" -ForegroundColor White
Write-Host "  VNets: $($global:counts.VNets)" -ForegroundColor White
Write-Host "  Subnets: $($global:counts.Subnets)" -ForegroundColor White
Write-Host "  NSGs: $($global:counts.NSGs)" -ForegroundColor White
Write-Host "  NSG Rules: $($global:counts.NSGRules)" -ForegroundColor White
Write-Host "  Public IPs: $($global:counts.PublicIPs)" -ForegroundColor White
Write-Host "  Alerts: $($global:counts.Alerts)" -ForegroundColor White
Write-Host ""
Write-Host "ISSUES:" -ForegroundColor Cyan
Write-Host "  Total: $totalIssues" -ForegroundColor White
Write-Host "  Critical: $($global:issues.Critical)" -ForegroundColor Red
Write-Host "  High: $($global:issues.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($global:issues.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($global:issues.Low)" -ForegroundColor Green
Write-Host ""
Write-Host "FILES SAVED:" -ForegroundColor Cyan
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host ""

# OPEN HTML
Write-Host "Opening HTML report..." -ForegroundColor Yellow
try {
    Start-Process $htmlReportPath
    Write-Host "  HTML opened in browser!" -ForegroundColor Green
} catch {
    Write-Host "  Could not open automatically. Open manually:" -ForegroundColor Yellow
    Write-Host "  $htmlReportPath" -ForegroundColor White
}

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host ""
