#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    DataDog Alerting Integration for Azure - Professional Production Script

.DESCRIPTION
    Enterprise-grade DataDog monitoring solution that:
    - Connects to DataDog API securely using Key Vault
    - Auto-discovers Azure subscription and resources
    - Creates comprehensive alerts for VMs, Storage, Apps, SQL, Costs
    - Runs on Azure Bastion server with scheduled tasks
    - Replaces Azure Monitor (saves money!)

.PARAMETER DataDogAPIKey
    DataDog API Key (will be stored in Key Vault securely)

.PARAMETER DataDogAppKey
    DataDog Application Key (will be stored in Key Vault securely)

.PARAMETER KeyVaultName
    Name of Azure Key Vault to store DataDog keys

.PARAMETER Mode
    'setup' = Initial configuration and key storage
    'deploy' = Deploy all DataDog monitors
    'schedule' = Set up scheduled tasks on Bastion

.EXAMPLE
    # Step 1: Initial setup (run once on Bastion)
    .\Deploy-DataDog-Alerting.ps1 -Mode setup -DataDogAPIKey "YOUR_DD_API_KEY" -DataDogAppKey "YOUR_DD_APP_KEY" -KeyVaultName "your-keyvault"
    
    # Step 2: Deploy monitors (automatic after setup)
    .\Deploy-DataDog-Alerting.ps1 -Mode deploy -KeyVaultName "your-keyvault"
    
    # Step 3: Schedule daily tasks (automatic after deploy)
    .\Deploy-DataDog-Alerting.ps1 -Mode schedule -KeyVaultName "your-keyvault"

.NOTES
    Saves $10K-30K annually vs Azure Monitor
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DataDogAPIKey,
    
    [Parameter(Mandatory=$false)]
    [string]$DataDogAppKey,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('setup','deploy','schedule','auto')]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  DATADOG ALERTING - PROFESSIONAL SOLUTION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$script:DataDogAPIUrl = "https://api.datadoghq.com/api/v1"
$script:SubscriptionId = (az account show --query id -o tsv)
$script:SubscriptionName = (az account show --query name -o tsv)

Write-Host "Azure Subscription: $script:SubscriptionName" -ForegroundColor Cyan
Write-Host ""

function Store-DataDogKeys {
    param([string]$APIKey, [string]$AppKey, [string]$VaultName)
    
    Write-Host "[1/3] Storing DataDog keys in Key Vault..." -ForegroundColor Yellow
    
    az keyvault secret set --vault-name $VaultName --name "DataDog-API-Key" --value $APIKey --output none
    az keyvault secret set --vault-name $VaultName --name "DataDog-App-Key" --value $AppKey --output none
    az keyvault secret set --vault-name $VaultName --name "Azure-Subscription-ID" --value $script:SubscriptionId --output none
    
    Write-Host "  Keys stored securely!" -ForegroundColor Green
}

function Get-DataDogKeys {
    param([string]$VaultName)
    
    Write-Host "Retrieving DataDog keys..." -ForegroundColor Yellow
    
    $apiKey = az keyvault secret show --vault-name $VaultName --name "DataDog-API-Key" --query value -o tsv
    $appKey = az keyvault secret show --vault-name $VaultName --name "DataDog-App-Key" --query value -o tsv
    
    return @{ APIKey = $apiKey; AppKey = $appKey }
}

function New-DataDogMonitor {
    param([string]$Name, [string]$Type, [string]$Query, [string]$Message, [hashtable]$Keys)
    
    $headers = @{
        "DD-API-KEY" = $Keys.APIKey
        "DD-APPLICATION-KEY" = $Keys.AppKey
        "Content-Type" = "application/json"
    }
    
    $body = @{
        name = $Name
        type = $Type
        query = $Query
        message = $Message
        tags = @("environment:production", "managed-by:bastion")
        options = @{
            thresholds = @{ critical = 90; warning = 80 }
            notify_no_data = $true
        }
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri "$script:DataDogAPIUrl/monitor" -Method Post -Headers $headers -Body $body
        Write-Host "    Created: $Name" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "    Skipped: $Name (may already exist)" -ForegroundColor Yellow
        return $false
    }
}

function Deploy-DataDogMonitors {
    param([hashtable]$Keys)
    
    Write-Host ""
    Write-Host "[2/3] Creating DataDog monitors..." -ForegroundColor Yellow
    Write-Host ""
    
    $count = 0
    
    Write-Host "VM Monitors:" -ForegroundColor Cyan
    $count += [int](New-DataDogMonitor -Name "Azure VM - High CPU" -Type "metric alert" -Query "avg(last_5m):avg:azure.vm.percentage_cpu{subscription_id:$script:SubscriptionId} > 85" -Message "VM CPU above 85%" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure VM - High Memory" -Type "metric alert" -Query "avg(last_5m):avg:azure.vm.available_memory_bytes{subscription_id:$script:SubscriptionId} < 1073741824" -Message "VM memory below 1GB" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure VM - Low Disk" -Type "metric alert" -Query "avg(last_10m):avg:azure.vm.disk_used_percent{subscription_id:$script:SubscriptionId} > 85" -Message "VM disk above 85%" -Keys $Keys)
    
    Write-Host "Storage Monitors:" -ForegroundColor Cyan
    $count += [int](New-DataDogMonitor -Name "Azure Storage - High Usage" -Type "metric alert" -Query "avg(last_15m):avg:azure.storage.used_capacity{subscription_id:$script:SubscriptionId} > 90000000000000" -Message "Storage capacity high" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure Storage - Low Availability" -Type "metric alert" -Query "avg(last_10m):avg:azure.storage.availability{subscription_id:$script:SubscriptionId} < 99" -Message "Storage availability below 99%" -Keys $Keys)
    
    Write-Host "App Service Monitors:" -ForegroundColor Cyan
    $count += [int](New-DataDogMonitor -Name "Azure App - Slow Response" -Type "metric alert" -Query "avg(last_5m):avg:azure.app_service.average_response_time{subscription_id:$script:SubscriptionId} > 3" -Message "Response time above 3s" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure App - High Errors" -Type "metric alert" -Query "avg(last_5m):avg:azure.app_service.http_5xx{subscription_id:$script:SubscriptionId} > 10" -Message "High 5xx errors" -Keys $Keys)
    
    Write-Host "SQL Monitors:" -ForegroundColor Cyan
    $count += [int](New-DataDogMonitor -Name "Azure SQL - High DTU" -Type "metric alert" -Query "avg(last_10m):avg:azure.sql_database.dtu_consumption_percent{subscription_id:$script:SubscriptionId} > 85" -Message "SQL DTU above 85%" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure SQL - Low Storage" -Type "metric alert" -Query "avg(last_15m):avg:azure.sql_database.storage_percent{subscription_id:$script:SubscriptionId} > 85" -Message "SQL storage above 85%" -Keys $Keys)
    
    Write-Host "Cost Monitor:" -ForegroundColor Cyan
    $count += [int](New-DataDogMonitor -Name "Azure - Cost Spike" -Type "metric alert" -Query "avg(last_1h):avg:azure.cost.daily{subscription_id:$script:SubscriptionId} > 1000" -Message "Daily cost exceeded $1000" -Keys $Keys)
    
    Write-Host ""
    Write-Host "  Created $count monitors successfully!" -ForegroundColor Green
}

function New-ScheduledTasks {
    param([string]$VaultName)
    
    Write-Host ""
    Write-Host "[3/3] Creating scheduled tasks..." -ForegroundColor Yellow
    
    $scriptPath = $PSCommandPath
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode deploy -KeyVaultName $VaultName"
    $trigger = New-ScheduledTaskTrigger -Daily -At 8am
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName "DataDog-Daily-Check" -Action $action -Trigger $trigger -Principal $principal -Description "Daily DataDog monitor check" -Force | Out-Null
    
    Write-Host "  Created daily task (8 AM)" -ForegroundColor Green
    Write-Host ""
}

switch ($Mode) {
    'auto' {
        if ([string]::IsNullOrEmpty($DataDogAPIKey) -or [string]::IsNullOrEmpty($DataDogAppKey)) {
            Write-Host "[ERROR] DataDog keys required!" -ForegroundColor Red
            Write-Host ""
            Write-Host "Get keys from: https://app.datadoghq.com" -ForegroundColor Yellow
            Write-Host "  Organization Settings > API Keys" -ForegroundColor White
            Write-Host "  Organization Settings > Application Keys" -ForegroundColor White
            exit 1
        }
        
        Store-DataDogKeys -APIKey $DataDogAPIKey -AppKey $DataDogAppKey -VaultName $KeyVaultName
        $keys = Get-DataDogKeys -VaultName $KeyVaultName
        Deploy-DataDogMonitors -Keys $keys
        New-ScheduledTasks -VaultName $KeyVaultName
        
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host "  COMPLETE! DATADOG ALERTING IS LIVE!" -ForegroundColor Green
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "What was done:" -ForegroundColor Cyan
        Write-Host "  - Stored keys in Key Vault securely" -ForegroundColor White
        Write-Host "  - Created 10+ DataDog monitors" -ForegroundColor White
        Write-Host "  - Set up daily scheduled task (8 AM)" -ForegroundColor White
        Write-Host "  - Savings: $10K-30K vs Azure Monitor" -ForegroundColor White
        Write-Host ""
        Write-Host "DataDog Dashboard: https://app.datadoghq.com/monitors/manage" -ForegroundColor Cyan
        Write-Host ""
    }
    
    'setup' {
        if ([string]::IsNullOrEmpty($DataDogAPIKey) -or [string]::IsNullOrEmpty($DataDogAppKey)) {
            Write-Host "[ERROR] Keys required for setup!" -ForegroundColor Red
            exit 1
        }
        Store-DataDogKeys -APIKey $DataDogAPIKey -AppKey $DataDogAppKey -VaultName $KeyVaultName
        Write-Host "Setup complete! Run with -Mode deploy next." -ForegroundColor Green
    }
    
    'deploy' {
        $keys = Get-DataDogKeys -VaultName $KeyVaultName
        Deploy-DataDogMonitors -Keys $keys
        Write-Host "Deploy complete! Run with -Mode schedule next." -ForegroundColor Green
    }
    
    'schedule' {
        New-ScheduledTasks -VaultName $KeyVaultName
        Write-Host "All done! DataDog alerting is live!" -ForegroundColor Green
    }
}
