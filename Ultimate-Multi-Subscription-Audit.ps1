#Requires -Version 5.1

<#
.SYNOPSIS
    Ultimate Multi-Subscription Azure Security and Compliance Audit
.DESCRIPTION
    Comprehensive security audit across ALL Azure subscriptions
    Checks: Network Security, Storage, SQL, VMs, IAM, Compliance
    Generates detailed CSV reports for each subscription
.PARAMETER OutputPath
    Path where reports will be saved
.EXAMPLE
    .\Ultimate-Multi-Subscription-Audit.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\Reports"
)

$ErrorActionPreference = "Continue"

function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "CRITICAL")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
        "CRITICAL" = "Magenta"
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

$script:totalFindings = 0
$script:criticalFindings = 0
$script:highFindings = 0
$script:mediumFindings = 0
$script:lowFindings = 0
$script:allFindings = @()
$script:resourceInventory = @()

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  ULTIMATE MULTI-SUBSCRIPTION SECURITY AUDIT" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "READ-ONLY MODE - No changes will be made" -ForegroundColor Green
Write-Host ""

Write-AuditLog "Checking Azure CLI..." "INFO"

try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-AuditLog "Azure CLI ready" "SUCCESS"
} catch {
    Write-AuditLog "Azure CLI not found" "ERROR"
    throw "Azure CLI required"
}

Write-AuditLog "Getting subscriptions..." "INFO"
$subscriptions = az account list --output json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    Write-AuditLog "No subscriptions found" "ERROR"
    throw "Run: az login"
}

Write-Host ""
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

if (!(Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $OutputPath "Multi-Sub-Audit-$timestamp"
New-Item -Path $reportPath -ItemType Directory -Force | Out-Null

function Add-Finding {
    param(
        [string]$Subscription,
        [string]$ResourceGroup,
        [string]$ResourceName,
        [string]$ResourceType,
        [string]$Category,
        [string]$Severity,
        [string]$Finding,
        [string]$Recommendation,
        [string]$Impact
    )
    
    $script:totalFindings++
    
    switch ($Severity) {
        "CRITICAL" { $script:criticalFindings++ }
        "HIGH" { $script:highFindings++ }
        "MEDIUM" { $script:mediumFindings++ }
        "LOW" { $script:lowFindings++ }
    }
    
    $script:allFindings += [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Subscription = $Subscription
        ResourceGroup = $ResourceGroup
        ResourceName = $ResourceName
        ResourceType = $ResourceType
        Category = $Category
        Severity = $Severity
        Finding = $Finding
        Recommendation = $Recommendation
        Impact = $Impact
    }
}

function Add-Resource {
    param(
        [string]$Subscription,
        [string]$ResourceGroup,
        [string]$ResourceName,
        [string]$ResourceType,
        [string]$Location,
        [string]$Status
    )
    
    $script:resourceInventory += [PSCustomObject]@{
        Subscription = $Subscription
        ResourceGroup = $ResourceGroup
        ResourceName = $ResourceName
        ResourceType = $ResourceType
        Location = $Location
        Status = $Status
    }
}

function Test-NetworkSecurityGroup {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking NSGs..." "INFO"
    
    $nsgs = az network nsg list --output json 2>$null | ConvertFrom-Json
    
    foreach ($nsg in $nsgs) {
        Add-Resource -Subscription $Sub -ResourceGroup $nsg.resourceGroup -ResourceName $nsg.name -ResourceType "NSG" -Location $nsg.location -Status "Active"
        
        $rules = az network nsg rule list --nsg-name $nsg.name --resource-group $nsg.resourceGroup --output json 2>$null | ConvertFrom-Json
        
        foreach ($rule in $rules) {
            if ($rule.access -eq "Allow" -and $rule.sourceAddressPrefix -eq "*" -and $rule.destinationPortRange -match "(22|3389|1433|3306)") {
                Add-Finding -Subscription $Sub -ResourceGroup $nsg.resourceGroup -ResourceName $nsg.name -ResourceType "NSG" -Category "Network" -Severity "CRITICAL" -Finding "Allows ANY source to critical port $($rule.destinationPortRange)" -Recommendation "Restrict source IPs" -Impact "Unauthorized access risk"
            }
            
            if ($rule.access -eq "Allow" -and $rule.destinationPortRange -eq "*") {
                Add-Finding -Subscription $Sub -ResourceGroup $nsg.resourceGroup -ResourceName $nsg.name -ResourceType "NSG" -Category "Network" -Severity "HIGH" -Finding "Allows ALL ports" -Recommendation "Restrict ports" -Impact "Increased attack surface"
            }
        }
    }
}

function Test-StorageAccounts {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking Storage..." "INFO"
    
    $storage = az storage account list --output json 2>$null | ConvertFrom-Json
    
    foreach ($sa in $storage) {
        Add-Resource -Subscription $Sub -ResourceGroup $sa.resourceGroup -ResourceName $sa.name -ResourceType "Storage" -Location $sa.location -Status $sa.provisioningState
        
        if ($sa.enableHttpsTrafficOnly -ne $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $sa.resourceGroup -ResourceName $sa.name -ResourceType "Storage" -Category "Encryption" -Severity "HIGH" -Finding "HTTPS not enforced" -Recommendation "Enable HTTPS only" -Impact "Data may be unencrypted"
        }
        
        if ($sa.allowBlobPublicAccess -eq $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $sa.resourceGroup -ResourceName $sa.name -ResourceType "Storage" -Category "Access" -Severity "MEDIUM" -Finding "Public blob access enabled" -Recommendation "Disable public access" -Impact "Data exposure risk"
        }
        
        if ($sa.networkRuleSet.defaultAction -eq "Allow") {
            Add-Finding -Subscription $Sub -ResourceGroup $sa.resourceGroup -ResourceName $sa.name -ResourceType "Storage" -Category "Network" -Severity "HIGH" -Finding "Allows all networks" -Recommendation "Configure network rules" -Impact "Unrestricted access"
        }
    }
}

function Test-SQLDatabases {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking SQL..." "INFO"
    
    $servers = az sql server list --output json 2>$null | ConvertFrom-Json
    
    foreach ($srv in $servers) {
        Add-Resource -Subscription $Sub -ResourceGroup $srv.resourceGroup -ResourceName $srv.name -ResourceType "SQL Server" -Location $srv.location -Status $srv.state
        
        $fw = az sql server firewall-rule list --server $srv.name --resource-group $srv.resourceGroup --output json 2>$null | ConvertFrom-Json
        
        foreach ($rule in $fw) {
            if ($rule.startIpAddress -eq "0.0.0.0" -and $rule.endIpAddress -eq "255.255.255.255") {
                Add-Finding -Subscription $Sub -ResourceGroup $srv.resourceGroup -ResourceName $srv.name -ResourceType "SQL" -Category "Network" -Severity "CRITICAL" -Finding "Allows ALL IPs" -Recommendation "Restrict firewall" -Impact "Database exposed to internet"
            }
        }
        
        $audit = az sql server audit-policy show --server $srv.name --resource-group $srv.resourceGroup --output json 2>$null | ConvertFrom-Json
        if ($audit.state -ne "Enabled") {
            Add-Finding -Subscription $Sub -ResourceGroup $srv.resourceGroup -ResourceName $srv.name -ResourceType "SQL" -Category "Auditing" -Severity "HIGH" -Finding "Auditing not enabled" -Recommendation "Enable auditing" -Impact "Cannot track access"
        }
        
        $dbs = az sql db list --server $srv.name --resource-group $srv.resourceGroup --output json 2>$null | ConvertFrom-Json
        
        foreach ($db in $dbs) {
            if ($db.name -ne "master") {
                Add-Resource -Subscription $Sub -ResourceGroup $srv.resourceGroup -ResourceName $db.name -ResourceType "SQL DB" -Location $db.location -Status $db.status
                
                $tde = az sql db tde show --database $db.name --server $srv.name --resource-group $srv.resourceGroup --output json 2>$null | ConvertFrom-Json
                if ($tde.status -ne "Enabled") {
                    Add-Finding -Subscription $Sub -ResourceGroup $srv.resourceGroup -ResourceName $db.name -ResourceType "SQL DB" -Category "Encryption" -Severity "HIGH" -Finding "TDE not enabled" -Recommendation "Enable TDE" -Impact "Data not encrypted at rest"
                }
            }
        }
    }
}

function Test-VirtualMachines {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking VMs..." "INFO"
    
    $vms = az vm list --output json 2>$null | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        $vmDetails = az vm show --ids $vm.id --output json 2>$null | ConvertFrom-Json
        
        Add-Resource -Subscription $Sub -ResourceGroup $vm.resourceGroup -ResourceName $vm.name -ResourceType "VM" -Location $vm.location -Status $vmDetails.provisioningState
        
        if ($vmDetails.storageProfile.osDisk.encryptionSettings.enabled -ne $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $vm.resourceGroup -ResourceName $vm.name -ResourceType "VM" -Category "Encryption" -Severity "HIGH" -Finding "Disk encryption not enabled" -Recommendation "Enable Azure Disk Encryption" -Impact "Data not encrypted"
        }
        
        $exts = az vm extension list --vm-name $vm.name --resource-group $vm.resourceGroup --output json 2>$null | ConvertFrom-Json
        $hasAM = $exts | Where-Object { $_.name -like "*Antimalware*" }
        
        if (!$hasAM) {
            Add-Finding -Subscription $Sub -ResourceGroup $vm.resourceGroup -ResourceName $vm.name -ResourceType "VM" -Category "Security" -Severity "MEDIUM" -Finding "No antimalware detected" -Recommendation "Install antimalware" -Impact "No malware protection"
        }
        
        $nics = $vmDetails.networkProfile.networkInterfaces
        foreach ($nic in $nics) {
            $nicDetails = az network nic show --ids $nic.id --output json 2>$null | ConvertFrom-Json
            if (!$nicDetails.networkSecurityGroup) {
                Add-Finding -Subscription $Sub -ResourceGroup $vm.resourceGroup -ResourceName $vm.name -ResourceType "VM" -Category "Network" -Severity "HIGH" -Finding "No NSG on NIC" -Recommendation "Attach NSG" -Impact "Unfiltered network access"
            }
        }
    }
}

function Test-KeyVaults {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking Key Vaults..." "INFO"
    
    $kvs = az keyvault list --output json 2>$null | ConvertFrom-Json
    
    foreach ($kv in $kvs) {
        $kvDetails = az keyvault show --name $kv.name --output json 2>$null | ConvertFrom-Json
        
        Add-Resource -Subscription $Sub -ResourceGroup $kv.resourceGroup -ResourceName $kv.name -ResourceType "Key Vault" -Location $kv.location -Status "Active"
        
        if ($kvDetails.properties.enableSoftDelete -ne $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $kv.resourceGroup -ResourceName $kv.name -ResourceType "KeyVault" -Category "Protection" -Severity "HIGH" -Finding "Soft delete not enabled" -Recommendation "Enable soft delete" -Impact "Secrets can be deleted permanently"
        }
        
        if ($kvDetails.properties.enablePurgeProtection -ne $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $kv.resourceGroup -ResourceName $kv.name -ResourceType "KeyVault" -Category "Protection" -Severity "MEDIUM" -Finding "Purge protection not enabled" -Recommendation "Enable purge protection" -Impact "Deleted secrets can be purged"
        }
        
        if ($kvDetails.properties.networkAcls.defaultAction -eq "Allow") {
            Add-Finding -Subscription $Sub -ResourceGroup $kv.resourceGroup -ResourceName $kv.name -ResourceType "KeyVault" -Category "Network" -Severity "HIGH" -Finding "Accessible from all networks" -Recommendation "Configure network ACLs" -Impact "Unrestricted access to secrets"
        }
    }
}

function Test-IAM {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking IAM..." "INFO"
    
    $roles = az role assignment list --all --output json 2>$null | ConvertFrom-Json
    
    $owners = $roles | Where-Object { $_.roleDefinitionName -eq "Owner" }
    foreach ($owner in $owners) {
        if ($owner.scope -like "/subscriptions/*" -and $owner.scope -notlike "*/resourceGroups/*") {
            Add-Finding -Subscription $Sub -ResourceGroup "N/A" -ResourceName $owner.principalName -ResourceType "IAM" -Category "Access" -Severity "HIGH" -Finding "Owner at subscription level" -Recommendation "Use least privilege" -Impact "Excessive permissions"
        }
    }
    
    $contribs = $roles | Where-Object { $_.roleDefinitionName -eq "Contributor" }
    foreach ($contrib in $contribs) {
        if ($contrib.scope -like "/subscriptions/*" -and $contrib.scope -notlike "*/resourceGroups/*") {
            Add-Finding -Subscription $Sub -ResourceGroup "N/A" -ResourceName $contrib.principalName -ResourceType "IAM" -Category "Access" -Severity "MEDIUM" -Finding "Contributor at subscription level" -Recommendation "Narrow scope" -Impact "Broad permissions"
        }
    }
}

function Test-PublicIPs {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking Public IPs..." "INFO"
    
    $pips = az network public-ip list --output json 2>$null | ConvertFrom-Json
    
    foreach ($pip in $pips) {
        Add-Resource -Subscription $Sub -ResourceGroup $pip.resourceGroup -ResourceName $pip.name -ResourceType "Public IP" -Location $pip.location -Status $pip.provisioningState
        
        if (!$pip.ipConfiguration) {
            Add-Finding -Subscription $Sub -ResourceGroup $pip.resourceGroup -ResourceName $pip.name -ResourceType "PublicIP" -Category "Cost" -Severity "LOW" -Finding "Unused public IP" -Recommendation "Delete if not needed" -Impact "Unnecessary cost"
        }
    }
}

function Test-AppServices {
    param([string]$Sub, [string]$SubId)
    
    Write-AuditLog "Checking App Services..." "INFO"
    
    $apps = az webapp list --output json 2>$null | ConvertFrom-Json
    
    foreach ($app in $apps) {
        Add-Resource -Subscription $Sub -ResourceGroup $app.resourceGroup -ResourceName $app.name -ResourceType "App Service" -Location $app.location -Status $app.state
        
        $config = az webapp config show --name $app.name --resource-group $app.resourceGroup --output json 2>$null | ConvertFrom-Json
        
        if ($config.minTlsVersion -ne "1.2") {
            Add-Finding -Subscription $Sub -ResourceGroup $app.resourceGroup -ResourceName $app.name -ResourceType "AppService" -Category "Security" -Severity "HIGH" -Finding "TLS 1.2 not enforced" -Recommendation "Set min TLS to 1.2" -Impact "Protocol downgrade risk"
        }
        
        if ($app.httpsOnly -ne $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $app.resourceGroup -ResourceName $app.name -ResourceType "AppService" -Category "Security" -Severity "HIGH" -Finding "HTTPS not enforced" -Recommendation "Enable HTTPS only" -Impact "Unencrypted traffic"
        }
        
        if ($config.remoteDebuggingEnabled -eq $true) {
            Add-Finding -Subscription $Sub -ResourceGroup $app.resourceGroup -ResourceName $app.name -ResourceType "AppService" -Category "Security" -Severity "MEDIUM" -Finding "Remote debugging enabled" -Recommendation "Disable debugging" -Impact "Security risk"
        }
    }
}

$startTime = Get-Date
$counter = 0

foreach ($sub in $subscriptions) {
    $counter++
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  [$counter/$($subscriptions.Count)] $($sub.name)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    
    az account set --subscription $sub.id
    
    $subPath = Join-Path $reportPath $sub.name.Replace(" ", "_")
    New-Item -Path $subPath -ItemType Directory -Force | Out-Null
    
    Test-NetworkSecurityGroup -Sub $sub.name -SubId $sub.id
    Test-StorageAccounts -Sub $sub.name -SubId $sub.id
    Test-SQLDatabases -Sub $sub.name -SubId $sub.id
    Test-VirtualMachines -Sub $sub.name -SubId $sub.id
    Test-KeyVaults -Sub $sub.name -SubId $sub.id
    Test-IAM -Sub $sub.name -SubId $sub.id
    Test-PublicIPs -Sub $sub.name -SubId $sub.id
    Test-AppServices -Sub $sub.name -SubId $sub.id
    
    $subFindings = $script:allFindings | Where-Object { $_.Subscription -eq $sub.name }
    if ($subFindings.Count -gt 0) {
        $subFindings | Export-Csv -Path (Join-Path $subPath "Findings.csv") -NoTypeInformation
    }
    
    $subRes = $script:resourceInventory | Where-Object { $_.Subscription -eq $sub.name }
    if ($subRes.Count -gt 0) {
        $subRes | Export-Csv -Path (Join-Path $subPath "Resources.csv") -NoTypeInformation
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Subscriptions: $($subscriptions.Count)" -ForegroundColor White
Write-Host "Resources: $($script:resourceInventory.Count)" -ForegroundColor White
Write-Host "Total Findings: $script:totalFindings" -ForegroundColor White
Write-Host "  Critical: $script:criticalFindings" -ForegroundColor Red
Write-Host "  High: $script:highFindings" -ForegroundColor Red
Write-Host "  Medium: $script:mediumFindings" -ForegroundColor Yellow
Write-Host "  Low: $script:lowFindings" -ForegroundColor Gray
Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host ""
Write-Host "Reports: $reportPath" -ForegroundColor Cyan
Write-Host ""

if ($script:allFindings.Count -gt 0) {
    $masterFile = Join-Path $reportPath "MASTER-All-Findings.csv"
    $script:allFindings | Export-Csv -Path $masterFile -NoTypeInformation
    Write-Host "Master Report: $masterFile" -ForegroundColor Green
}

if ($script:resourceInventory.Count -gt 0) {
    $invFile = Join-Path $reportPath "MASTER-All-Resources.csv"
    $script:resourceInventory | Export-Csv -Path $invFile -NoTypeInformation
    Write-Host "Inventory: $invFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "READ-ONLY - No changes made" -ForegroundColor Green
Write-Host ""
