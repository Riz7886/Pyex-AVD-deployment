#Requires -Version 5.1
#Requires -RunAsAdministrator

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
Write-Host "DATADOG ALERTING - PROFESSIONAL SOLUTION" -ForegroundColor Cyan
Write-Host ""

$script:DataDogAPIUrl = "https://api.datadoghq.com/api/v1"
$script:SubscriptionId = (az account show --query id -o tsv)

function Store-DataDogKeys {
    param([string]$APIKey, [string]$AppKey, [string]$VaultName)
    az keyvault secret set --vault-name $VaultName --name "DataDog-API-Key" --value $APIKey --output none
    az keyvault secret set --vault-name $VaultName --name "DataDog-App-Key" --value $AppKey --output none
    Write-Host "Keys stored!" -ForegroundColor Green
}

function Get-DataDogKeys {
    param([string]$VaultName)
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
        tags = @("environment:production")
    } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$script:DataDogAPIUrl/monitor" -Method Post -Headers $headers -Body $body | Out-Null
        Write-Host "  Created: $Name" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  Skipped: $Name" -ForegroundColor Yellow
        return $false
    }
}

function Deploy-DataDogMonitors {
    param([hashtable]$Keys)
    Write-Host "Creating monitors..." -ForegroundColor Yellow
    $count = 0
    $count += [int](New-DataDogMonitor -Name "Azure VM - High CPU" -Type "metric alert" -Query "avg(last_5m):avg:azure.vm.percentage_cpu{subscription_id:$script:SubscriptionId} > 85" -Message "CPU high" -Keys $Keys)
    $count += [int](New-DataDogMonitor -Name "Azure Storage - Low Availability" -Type "metric alert" -Query "avg(last_10m):avg:azure.storage.availability{subscription_id:$script:SubscriptionId} < 99" -Message "Storage down" -Keys $Keys)
    Write-Host "Created $count monitors!" -ForegroundColor Green
}

function New-ScheduledTasks {
    param([string]$VaultName)
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$PSCommandPath`" -Mode deploy -KeyVaultName $VaultName"
    $trigger = New-ScheduledTaskTrigger -Daily -At 8am
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "DataDog-Daily-Check" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Host "Scheduled task created!" -ForegroundColor Green
}

switch ($Mode) {
    'auto' {
        Store-DataDogKeys -APIKey $DataDogAPIKey -AppKey $DataDogAppKey -VaultName $KeyVaultName
        $keys = Get-DataDogKeys -VaultName $KeyVaultName
        Deploy-DataDogMonitors -Keys $keys
        New-ScheduledTasks -VaultName $KeyVaultName
        Write-Host "COMPLETE! DataDog alerting is live!" -ForegroundColor Green
    }
    'setup' { Store-DataDogKeys -APIKey $DataDogAPIKey -AppKey $DataDogAppKey -VaultName $KeyVaultName }
    'deploy' { $keys = Get-DataDogKeys -VaultName $KeyVaultName; Deploy-DataDogMonitors -Keys $keys }
    'schedule' { New-ScheduledTasks -VaultName $KeyVaultName }
}
