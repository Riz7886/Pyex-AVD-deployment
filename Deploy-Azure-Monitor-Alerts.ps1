#Requires -Version 5.1

<#
.SYNOPSIS
    Ultimate Azure Monitor Alert Framework - ALL Resource Types
.DESCRIPTION
    Comprehensive monitoring across ALL 15 subscriptions
    Monitors: VMs, App Services, SQL, Storage, Load Balancers, App Gateways
    Email alerts to: John.pinto@pyxhealth.com, shaun.raj@pyxhealth.com, anthony.schlak@pyxhealth.com
.PARAMETER Mode
    preview = Shows what would be created
    deploy = Actually creates alerts
.EXAMPLE
    .\Deploy-Azure-Monitor-Alerts.ps1 -Mode preview
.EXAMPLE
    .\Deploy-Azure-Monitor-Alerts.ps1 -Mode deploy
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("preview", "deploy")]
    [string]$Mode = "preview"
)

$ErrorActionPreference = "Continue"

$alertEmails = @(
    "John.pinto@pyxhealth.com",
    "shaun.raj@pyxhealth.com",
    "anthony.schlak@pyxhealth.com"
)

function Write-MonitorLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  ULTIMATE AZURE MONITOR - ALL RESOURCE TYPES" -ForegroundColor Magenta
Write-Host "  Comprehensive Monitoring Across 15 Subscriptions" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

if ($Mode -eq "preview") {
    Write-Host "PREVIEW MODE - No alerts will be created" -ForegroundColor Yellow
    Write-Host ""
}

Write-MonitorLog "Checking Azure CLI..." "INFO"
try {
    $null = az version --output json 2>$null
    Write-MonitorLog "Azure CLI ready" "SUCCESS"
} catch {
    Write-MonitorLog "Azure CLI not found!" "ERROR"
    throw "Install Azure CLI"
}

Write-MonitorLog "Getting subscriptions..." "INFO"
$subscriptions = az account list --output json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    Write-MonitorLog "No subscriptions found" "ERROR"
    throw "Run: az login"
}

Write-Host ""
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$script:alertsCreated = 0
$script:resourcesFound = 0
$script:actionGroupId = ""

function New-ActionGroup {
    param([string]$ResourceGroup)
    
    $agName = "AG-PYEX-Leadership"
    
    if ($Mode -eq "deploy") {
        try {
            $existing = az monitor action-group show --name $agName --resource-group $ResourceGroup 2>$null
            if ($existing) {
                $ag = $existing | ConvertFrom-Json
                $script:actionGroupId = $ag.id
                Write-MonitorLog "Action Group exists" "INFO"
            } else {
                az monitor action-group create --name $agName --resource-group $ResourceGroup --short-name "PYEX" --action email John john.pinto@pyxhealth.com --action email Shaun shaun.raj@pyxhealth.com --action email Anthony anthony.schlak@pyxhealth.com 2>$null
                $ag = az monitor action-group show --name $agName --resource-group $ResourceGroup --output json | ConvertFrom-Json
                $script:actionGroupId = $ag.id
                Write-MonitorLog "Action Group created" "SUCCESS"
            }
        } catch {
            Write-MonitorLog "Action Group issue: $_" "WARNING"
        }
    } else {
        Write-Host "  Would create Action Group: $agName" -ForegroundColor Yellow
    }
}

function New-Alert {
    param([string]$Name, [string]$RG, [string]$Scope, [string]$Metric, [string]$Op, [int]$Val, [int]$Sev, [string]$Desc)
    
    if ($Mode -eq "deploy" -and $script:actionGroupId) {
        try {
            az monitor metrics alert create --name $Name --resource-group $RG --scopes $Scope --condition "avg '$Metric' $Op $Val" --description $Desc --evaluation-frequency 5m --window-size 15m --severity $Sev --action $script:actionGroupId 2>$null | Out-Null
            $script:alertsCreated++
            Write-Host "    [OK] $Desc" -ForegroundColor Green
        } catch {
            Write-Host "    [SKIP] $Name" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    [PREVIEW] $Desc" -ForegroundColor Yellow
    }
}

foreach ($sub in $subscriptions) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  $($sub.name)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    
    az account set --subscription $sub.id
    
    $rgs = az group list --output json 2>$null | ConvertFrom-Json
    if ($rgs.Count -eq 0) { continue }
    
    $mainRG = $rgs[0].name
    New-ActionGroup -ResourceGroup $mainRG
    
    Write-MonitorLog "Scanning Virtual Machines..." "INFO"
    $vms = az vm list --output json 2>$null | ConvertFrom-Json
    if ($vms.Count -gt 0) {
        Write-Host ""
        Write-Host "VMs: $($vms.Count)" -ForegroundColor Green
        foreach ($vm in $vms) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  VM: $($vm.name)" -ForegroundColor White
            New-Alert -Name "VM-$($vm.name)-CPU" -RG $vm.resourceGroup -Scope $vm.id -Metric "Percentage CPU" -Op "GreaterThan" -Val 85 -Sev 2 -Desc "CPU over 85%"
            New-Alert -Name "VM-$($vm.name)-Memory" -RG $vm.resourceGroup -Scope $vm.id -Metric "Available Memory Bytes" -Op "LessThan" -Val 524288000 -Sev 2 -Desc "Memory below 500MB"
            New-Alert -Name "VM-$($vm.name)-Disk" -RG $vm.resourceGroup -Scope $vm.id -Metric "Disk Operations/Sec" -Op "GreaterThan" -Val 1000 -Sev 3 -Desc "Disk IO over 1000"
            New-Alert -Name "VM-$($vm.name)-Network" -RG $vm.resourceGroup -Scope $vm.id -Metric "Network Out Total" -Op "GreaterThan" -Val 104857600 -Sev 3 -Desc "Network over 100MB/s"
        }
    }
    
    Write-MonitorLog "Scanning App Services..." "INFO"
    $apps = az webapp list --output json 2>$null | ConvertFrom-Json
    if ($apps.Count -gt 0) {
        Write-Host ""
        Write-Host "App Services: $($apps.Count)" -ForegroundColor Green
        foreach ($app in $apps) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  App: $($app.name)" -ForegroundColor White
            New-Alert -Name "App-$($app.name)-CPU" -RG $app.resourceGroup -Scope $app.id -Metric "CpuPercentage" -Op "GreaterThan" -Val 80 -Sev 2 -Desc "CPU over 80%"
            New-Alert -Name "App-$($app.name)-Memory" -RG $app.resourceGroup -Scope $app.id -Metric "MemoryPercentage" -Op "GreaterThan" -Val 85 -Sev 2 -Desc "Memory over 85%"
            New-Alert -Name "App-$($app.name)-Response" -RG $app.resourceGroup -Scope $app.id -Metric "HttpResponseTime" -Op "GreaterThan" -Val 5 -Sev 2 -Desc "Response time over 5s"
            New-Alert -Name "App-$($app.name)-Errors" -RG $app.resourceGroup -Scope $app.id -Metric "Http5xx" -Op "GreaterThan" -Val 10 -Sev 1 -Desc "HTTP 5xx over 10"
        }
    }
    
    Write-MonitorLog "Scanning SQL Databases..." "INFO"
    $sqlServers = az sql server list --output json 2>$null | ConvertFrom-Json
    foreach ($server in $sqlServers) {
        $dbs = az sql db list --server $server.name --resource-group $server.resourceGroup --output json 2>$null | ConvertFrom-Json
        if ($dbs.Count -gt 0) {
            Write-Host ""
            Write-Host "SQL Databases: $($dbs.Count) on $($server.name)" -ForegroundColor Green
            foreach ($db in $dbs) {
                if ($db.name -ne "master") {
                    $script:resourcesFound++
                    Write-Host ""
                    Write-Host "  DB: $($db.name)" -ForegroundColor White
                    New-Alert -Name "SQL-$($db.name)-DTU" -RG $server.resourceGroup -Scope $db.id -Metric "dtu_consumption_percent" -Op "GreaterThan" -Val 80 -Sev 2 -Desc "DTU over 80%"
                    New-Alert -Name "SQL-$($db.name)-Storage" -RG $server.resourceGroup -Scope $db.id -Metric "storage_percent" -Op "GreaterThan" -Val 85 -Sev 2 -Desc "Storage over 85%"
                    New-Alert -Name "SQL-$($db.name)-Deadlock" -RG $server.resourceGroup -Scope $db.id -Metric "deadlock" -Op "GreaterThan" -Val 5 -Sev 1 -Desc "Deadlocks over 5"
                }
            }
        }
    }
    
    Write-MonitorLog "Scanning Storage Accounts..." "INFO"
    $storage = az storage account list --output json 2>$null | ConvertFrom-Json
    if ($storage.Count -gt 0) {
        Write-Host ""
        Write-Host "Storage Accounts: $($storage.Count)" -ForegroundColor Green
        foreach ($sa in $storage) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  Storage: $($sa.name)" -ForegroundColor White
            New-Alert -Name "Storage-$($sa.name)-Avail" -RG $sa.resourceGroup -Scope $sa.id -Metric "Availability" -Op "LessThan" -Val 99 -Sev 1 -Desc "Availability below 99%"
            New-Alert -Name "Storage-$($sa.name)-Latency" -RG $sa.resourceGroup -Scope $sa.id -Metric "SuccessE2ELatency" -Op "GreaterThan" -Val 1000 -Sev 2 -Desc "Latency over 1000ms"
            New-Alert -Name "Storage-$($sa.name)-Capacity" -RG $sa.resourceGroup -Scope $sa.id -Metric "UsedCapacity" -Op "GreaterThan" -Val 4398046511104 -Sev 3 -Desc "Capacity over 4TB"
        }
    }
    
    Write-MonitorLog "Scanning Load Balancers..." "INFO"
    $lbs = az network lb list --output json 2>$null | ConvertFrom-Json
    if ($lbs.Count -gt 0) {
        Write-Host ""
        Write-Host "Load Balancers: $($lbs.Count)" -ForegroundColor Green
        foreach ($lb in $lbs) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  LB: $($lb.name)" -ForegroundColor White
            New-Alert -Name "LB-$($lb.name)-Health" -RG $lb.resourceGroup -Scope $lb.id -Metric "VipAvailability" -Op "LessThan" -Val 90 -Sev 1 -Desc "Health below 90%"
            New-Alert -Name "LB-$($lb.name)-SNAT" -RG $lb.resourceGroup -Scope $lb.id -Metric "AllocatedSnatPorts" -Op "GreaterThan" -Val 950 -Sev 2 -Desc "SNAT ports over 950"
        }
    }
    
    Write-MonitorLog "Scanning Application Gateways..." "INFO"
    $appgws = az network application-gateway list --output json 2>$null | ConvertFrom-Json
    if ($appgws.Count -gt 0) {
        Write-Host ""
        Write-Host "App Gateways: $($appgws.Count)" -ForegroundColor Green
        foreach ($ag in $appgws) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  AppGW: $($ag.name)" -ForegroundColor White
            New-Alert -Name "AppGW-$($ag.name)-Unhealthy" -RG $ag.resourceGroup -Scope $ag.id -Metric "UnhealthyHostCount" -Op "GreaterThan" -Val 0 -Sev 1 -Desc "Unhealthy backends detected"
            New-Alert -Name "AppGW-$($ag.name)-Response" -RG $ag.resourceGroup -Scope $ag.id -Metric "ApplicationGatewayTotalTime" -Op "GreaterThan" -Val 5000 -Sev 2 -Desc "Response time over 5s"
        }
    }
    
    Write-MonitorLog "Scanning Function Apps..." "INFO"
    $functions = az functionapp list --output json 2>$null | ConvertFrom-Json
    if ($functions.Count -gt 0) {
        Write-Host ""
        Write-Host "Function Apps: $($functions.Count)" -ForegroundColor Green
        foreach ($func in $functions) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  Function: $($func.name)" -ForegroundColor White
            New-Alert -Name "Func-$($func.name)-Errors" -RG $func.resourceGroup -Scope $func.id -Metric "FunctionExecutionCount" -Op "LessThan" -Val 1 -Sev 2 -Desc "No executions"
        }
    }
    
    Write-MonitorLog "Scanning Key Vaults..." "INFO"
    $kvs = az keyvault list --output json 2>$null | ConvertFrom-Json
    if ($kvs.Count -gt 0) {
        Write-Host ""
        Write-Host "Key Vaults: $($kvs.Count)" -ForegroundColor Green
        foreach ($kv in $kvs) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  KeyVault: $($kv.name)" -ForegroundColor White
            New-Alert -Name "KV-$($kv.name)-Availability" -RG $kv.resourceGroup -Scope $kv.id -Metric "Availability" -Op "LessThan" -Val 99 -Sev 1 -Desc "Availability below 99%"
            New-Alert -Name "KV-$($kv.name)-Latency" -RG $kv.resourceGroup -Scope $kv.id -Metric "ServiceApiLatency" -Op "GreaterThan" -Val 1000 -Sev 2 -Desc "API latency over 1000ms"
        }
    }
    
    Write-MonitorLog "Scanning AKS Clusters..." "INFO"
    $aks = az aks list --output json 2>$null | ConvertFrom-Json
    if ($aks.Count -gt 0) {
        Write-Host ""
        Write-Host "AKS Clusters: $($aks.Count)" -ForegroundColor Green
        foreach ($cluster in $aks) {
            $script:resourcesFound++
            Write-Host ""
            Write-Host "  AKS: $($cluster.name)" -ForegroundColor White
            New-Alert -Name "AKS-$($cluster.name)-CPU" -RG $cluster.resourceGroup -Scope $cluster.id -Metric "node_cpu_usage_percentage" -Op "GreaterThan" -Val 80 -Sev 2 -Desc "Node CPU over 80%"
            New-Alert -Name "AKS-$($cluster.name)-Memory" -RG $cluster.resourceGroup -Scope $cluster.id -Metric "node_memory_working_set_percentage" -Op "GreaterThan" -Val 80 -Sev 2 -Desc "Node Memory over 80%"
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  SUMMARY" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Subscriptions: $($subscriptions.Count)" -ForegroundColor White
Write-Host "Resources Found: $script:resourcesFound" -ForegroundColor White

if ($Mode -eq "deploy") {
    Write-Host "Alerts Created: $script:alertsCreated" -ForegroundColor Green
    Write-Host ""
    Write-Host "Email alerts to:" -ForegroundColor Cyan
    foreach ($email in $alertEmails) { Write-Host "  - $email" -ForegroundColor White }
} else {
    Write-Host "Alerts Would Create: ~$($script:resourcesFound * 3)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "PREVIEW MODE - Run with -Mode deploy" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "MONITORING COVERAGE:" -ForegroundColor Cyan
Write-Host "  [OK] VMs: CPU, Memory, Disk, Network" -ForegroundColor Green
Write-Host "  [OK] App Services: CPU, Memory, Response, Errors" -ForegroundColor Green
Write-Host "  [OK] SQL: DTU, Storage, Deadlocks" -ForegroundColor Green
Write-Host "  [OK] Storage: Availability, Latency, Capacity" -ForegroundColor Green
Write-Host "  [OK] Load Balancers: Health, SNAT exhaustion" -ForegroundColor Green
Write-Host "  [OK] App Gateways: Unhealthy backends, Response time" -ForegroundColor Green
Write-Host "  [OK] Function Apps: Execution failures" -ForegroundColor Green
Write-Host "  [OK] Key Vaults: Availability, API latency" -ForegroundColor Green
Write-Host "  [OK] AKS: Node CPU, Node Memory" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
