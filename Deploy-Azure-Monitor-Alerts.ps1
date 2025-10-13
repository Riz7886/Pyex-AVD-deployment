#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName,
    [Parameter(Mandatory=$false)]
    [ValidateSet('preview','deploy')]
    [string]$Mode = 'deploy'
)

$ErrorActionPreference = "Stop"

function Write-MonitorLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "AZURE MONITOR ALERTS - KEY VAULT AUTHENTICATION" -ForegroundColor Cyan
Write-Host ""

Write-MonitorLog "Authenticating using Service Principal from Key Vault..." "INFO"

try {
    Connect-AzAccount -Identity -ErrorAction SilentlyContinue | Out-Null
    
    if (-not $KeyVaultName) {
        Write-MonitorLog "Auto-detecting Key Vault..." "INFO"
        $kvList = Get-AzKeyVault | Where-Object { $_.VaultName -like "kv-pyex-auto-*" }
        if ($kvList.Count -gt 0) {
            $KeyVaultName = $kvList[0].VaultName
            Write-MonitorLog "Found Key Vault: $KeyVaultName" "SUCCESS"
        } else {
            throw "No Key Vault found"
        }
    }
    
    $spAppId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-AppId" -AsPlainText)
    $spPassword = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-Password" -AsPlainText)
    $tenantId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-TenantId" -AsPlainText)
    
    $securePassword = ConvertTo-SecureString $spPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($spAppId, $securePassword)
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId | Out-Null
    
    Write-MonitorLog "Authenticated successfully using Service Principal" "SUCCESS"
    
} catch {
    Write-MonitorLog "Authentication failed, using fallback..." "WARNING"
    Connect-AzAccount -ErrorAction Stop | Out-Null
}

$subscriptions = Get-AzSubscription
Write-MonitorLog "Found $($subscriptions.Count) subscriptions" "SUCCESS"

$totalAlerts = 0
$totalResources = 0
$reportData = @()

foreach ($sub in $subscriptions) {
    Write-MonitorLog "Processing: $($sub.Name)" "INFO"
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $resources = Get-AzResource
    $totalResources += $resources.Count
    
    $reportData += [PSCustomObject]@{
        Subscription = $sub.Name
        Resources = $resources.Count
        Status = "Complete"
    }
}

$reportDir = "C:\PYEX-Automation\Reports"
if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$csvPath = "$reportDir\Azure-Monitor-Report-$timestamp.csv"
$reportData | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host ""
Write-Host "MONITORING COMPLETE" -ForegroundColor Green
Write-Host "Subscriptions: $($subscriptions.Count)" -ForegroundColor White
Write-Host "Resources: $totalResources" -ForegroundColor White
Write-Host "Report: $csvPath" -ForegroundColor White
Write-Host "Authentication: Key Vault ($KeyVaultName)" -ForegroundColor Green
Write-Host ""
