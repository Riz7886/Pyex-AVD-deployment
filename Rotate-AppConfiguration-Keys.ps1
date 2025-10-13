#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('preview','rotate')]
    [string]$Mode = 'rotate',
    
    [Parameter(Mandatory=$false)]
    [int]$RotationThresholdDays = 180,
    
    [Parameter(Mandatory=$false)]
    [string[]]$NotificationEmails = @('john.pinto@pyxhealth.com','shaun.raj@pyxhealth.com','anthony.schlak@pyxhealth.com')
)

$ErrorActionPreference = "Stop"
$script:rotationReport = @()
$script:keysRotated = 0
$script:appServicesUpdated = 0
$script:issuesFound = 0
$script:appServicesScanned = 0
$script:storageAccountsScanned = 0

function Write-RotationLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red";"CRITICAL"="Magenta"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Add-RotationEntry {
    param(
        [string]$Subscription,
        [string]$ResourceType,
        [string]$ResourceName,
        [string]$KeyType,
        [int]$KeyAgeDays,
        [string]$Action,
        [string]$Status,
        [string]$Details,
        [string]$OldKeyPreview,
        [string]$NewKeyPreview
    )
    
    $script:rotationReport += [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Subscription = $Subscription
        ResourceType = $ResourceType
        ResourceName = $ResourceName
        KeyType = $KeyType
        KeyAgeDays = $KeyAgeDays
        RotationNeeded = if($KeyAgeDays -gt $RotationThresholdDays){"YES"}else{"NO"}
        Action = $Action
        Status = $Status
        Details = $Details
        OldKeyPreview = $OldKeyPreview
        NewKeyPreview = $NewKeyPreview
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE KEY ROTATION - AUTOMATED SECURITY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($Mode -eq "preview") {
    Write-Host "PREVIEW MODE - No keys will be rotated" -ForegroundColor Yellow
} else {
    Write-Host "ROTATION MODE - Keys older than $RotationThresholdDays days will be rotated" -ForegroundColor Magenta
}
Write-Host ""

Write-RotationLog "Authenticating with Key Vault..." "INFO"

try {
    Connect-AzAccount -Identity -ErrorAction SilentlyContinue | Out-Null
    
    if (-not $KeyVaultName) {
        $kvList = Get-AzKeyVault | Where-Object { $_.VaultName -like "kv-pyex-auto-*" }
        if ($kvList.Count -gt 0) {
            $KeyVaultName = $kvList[0].VaultName
            Write-RotationLog "Found Key Vault: $KeyVaultName" "SUCCESS"
        }
    }
    
    if ($KeyVaultName) {
        $spAppId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-AppId" -AsPlainText)
        $spPassword = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-Password" -AsPlainText)
        $tenantId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "SP-TenantId" -AsPlainText)
        
        $securePassword = ConvertTo-SecureString $spPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($spAppId, $securePassword)
        Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId | Out-Null
        
        Write-RotationLog "Authenticated using Service Principal" "SUCCESS"
    }
} catch {
    Write-RotationLog "Using fallback authentication" "WARNING"
    Connect-AzAccount -ErrorAction SilentlyContinue | Out-Null
}

Write-RotationLog "Checking Azure CLI..." "INFO"
try {
    $null = az version --output json 2>$null
    Write-RotationLog "Azure CLI ready" "SUCCESS"
} catch {
    throw "Azure CLI not found"
}

Write-Host ""
Write-RotationLog "Scanning subscriptions for resources with old keys..." "INFO"
$subscriptions = az account list --output json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    throw "No subscriptions found"
}

Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

foreach ($sub in $subscriptions) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  SUBSCRIPTION: $($sub.name)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    az account set --subscription $sub.id
    
    Write-RotationLog "Scanning Storage Accounts for old keys..." "INFO"
    $storageAccounts = az storage account list --output json 2>$null | ConvertFrom-Json
    
    if ($storageAccounts.Count -gt 0) {
        Write-Host "Found $($storageAccounts.Count) Storage Accounts" -ForegroundColor Green
        
        foreach ($storage in $storageAccounts) {
            $script:storageAccountsScanned++
            Write-Host ""
            Write-Host "  Checking: $($storage.name)" -ForegroundColor White
            
            try {
                $keys = az storage account keys list --account-name $storage.name --resource-group $storage.resourceGroup --output json 2>$null | ConvertFrom-Json
                
                foreach ($key in $keys) {
                    $keyName = $key.keyName
                    $keyValue = $key.value
                    $creationTime = if($key.creationTime) { [DateTime]::Parse($key.creationTime) } else { (Get-Date).AddDays(-365) }
                    $keyAgeDays = ((Get-Date) - $creationTime).Days
                    
                    $keyPreview = if($keyValue.Length -gt 8) { $keyValue.Substring(0,4) + "..." + $keyValue.Substring($keyValue.Length-4,4) } else { "***" }
                    
                    $needsRotation = $keyAgeDays -gt $RotationThresholdDays
                    
                    Write-Host "    Key: $keyName - Age: $keyAgeDays days" -ForegroundColor $(if($needsRotation){"Red"}else{"Green"})
                    
                    if ($needsRotation) {
                        $script:issuesFound++
                        
                        if ($Mode -eq "rotate") {
                            Write-Host "      [ROTATING] $keyName..." -ForegroundColor Yellow
                            
                            try {
                                az storage account keys renew --account-name $storage.name --resource-group $storage.resourceGroup --key $keyName --output none 2>$null
                                
                                $newKeys = az storage account keys list --account-name $storage.name --resource-group $storage.resourceGroup --output json 2>$null | ConvertFrom-Json
                                $newKey = $newKeys | Where-Object { $_.keyName -eq $keyName }
                                
                                if ($newKey) {
                                    $newKeyValue = $newKey.value
                                    $newKeyPreview = if($newKeyValue.Length -gt 8) { $newKeyValue.Substring(0,4) + "..." + $newKeyValue.Substring($newKeyValue.Length-4,4) } else { "***" }
                                    
                                    Write-Host "      [OK] Storage key rotated" -ForegroundColor Green
                                    $script:keysRotated++
                                    
                                    $secretName = "Storage-$($storage.name)-$keyName"
                                    if ($KeyVaultName) {
                                        try {
                                            Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -SecretValue (ConvertTo-SecureString $newKeyValue -AsPlainText -Force) | Out-Null
                                            Write-Host "      [OK] Stored in Key Vault" -ForegroundColor Green
                                        } catch {
                                            Write-Host "      [WARNING] Could not store in Key Vault" -ForegroundColor Yellow
                                        }
                                    }
                                    
                                    Write-Host "      [CHECKING] App Services for updates..." -ForegroundColor Cyan
                                    $appServices = az webapp list --output json 2>$null | ConvertFrom-Json
                                    
                                    foreach ($app in $appServices) {
                                        $appSettings = az webapp config appsettings list --name $app.name --resource-group $app.resourceGroup --output json 2>$null | ConvertFrom-Json
                                        
                                        $needsUpdate = $false
                                        foreach ($setting in $appSettings) {
                                            if ($setting.value -like "*$($storage.name)*" -or $setting.value -eq $keyValue) {
                                                $needsUpdate = $true
                                                break
                                            }
                                        }
                                        
                                        if ($needsUpdate) {
                                            Write-Host "        [UPDATE] $($app.name)" -ForegroundColor Yellow
                                            
                                            $connectionString = "DefaultEndpointsProtocol=https;AccountName=$($storage.name);AccountKey=$newKeyValue;EndpointSuffix=core.windows.net"
                                            
                                            try {
                                                az webapp config appsettings set --name $app.name --resource-group $app.resourceGroup --settings "StorageConnectionString=$connectionString" --output none 2>$null
                                                az webapp restart --name $app.name --resource-group $app.resourceGroup --output none 2>$null
                                                Write-Host "        [OK] Updated and restarted" -ForegroundColor Green
                                                $script:appServicesUpdated++
                                            } catch {
                                                Write-Host "        [WARNING] Update failed" -ForegroundColor Yellow
                                            }
                                        }
                                    }
                                    
                                    Add-RotationEntry -Subscription $sub.name -ResourceType "StorageAccount" -ResourceName $storage.name -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotated" -Status "Success" -Details "Storage key rotated, stored in Key Vault, app services updated" -OldKeyPreview $keyPreview -NewKeyPreview $newKeyPreview
                                    
                                } else {
                                    Write-Host "      [ERROR] Rotation failed" -ForegroundColor Red
                                    Add-RotationEntry -Subscription $sub.name -ResourceType "StorageAccount" -ResourceName $storage.name -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotation Failed" -Status "Error" -Details "Could not rotate key" -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                                }
                                
                            } catch {
                                Write-Host "      [ERROR] $($_.Exception.Message)" -ForegroundColor Red
                                Add-RotationEntry -Subscription $sub.name -ResourceType "StorageAccount" -ResourceName $storage.name -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotation Failed" -Status "Error" -Details $_.Exception.Message -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                            }
                            
                        } else {
                            Write-Host "      [PREVIEW] Would rotate this key" -ForegroundColor Yellow
                            Add-RotationEntry -Subscription $sub.name -ResourceType "StorageAccount" -ResourceName $storage.name -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Preview" -Status "Needs Rotation" -Details "Key is $keyAgeDays days old, exceeds $RotationThresholdDays day threshold" -OldKeyPreview $keyPreview -NewKeyPreview "Would be rotated"
                        }
                    } else {
                        Add-RotationEntry -Subscription $sub.name -ResourceType "StorageAccount" -ResourceName $storage.name -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Checked" -Status "OK" -Details "Key is only $keyAgeDays days old" -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                    }
                }
                
            } catch {
                Write-RotationLog "Error checking storage: $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Write-Host ""
    Write-RotationLog "Scanning App Configuration stores..." "INFO"
    
    $appConfigs = az appconfig list --output json 2>$null | ConvertFrom-Json
    
    if ($appConfigs.Count -eq 0) {
        Write-RotationLog "No App Configuration stores found" "INFO"
        continue
    }
    
    Write-Host "Found $($appConfigs.Count) App Configuration stores" -ForegroundColor Green
    Write-Host ""
    
    foreach ($config in $appConfigs) {
        $configName = $config.name
        $rgName = $config.resourceGroup
        
        Write-Host ""
        Write-Host "Checking: $configName" -ForegroundColor White
        
        try {
            $keys = az appconfig credential list --name $configName --resource-group $rgName --output json 2>$null | ConvertFrom-Json
            
            if (!$keys) {
                Write-RotationLog "Could not retrieve keys for $configName" "WARNING"
                $script:issuesFound++
                Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType "N/A" -KeyAgeDays 0 -Action "Check Failed" -Status "Warning" -Details "Unable to retrieve keys" -OldKeyPreview "N/A" -NewKeyPreview "N/A"
                continue
            }
            
            Write-Host ""
            foreach ($key in $keys) {
                $keyName = $key.name
                $keyId = $key.id
                $keyValue = $key.value
                $lastModified = if($key.lastModifiedDate) { [DateTime]::Parse($key.lastModifiedDate) } else { (Get-Date).AddDays(-365) }
                $keyAgeDays = ((Get-Date) - $lastModified).Days
                
                $keyPreview = if($keyValue.Length -gt 8) { $keyValue.Substring(0,4) + "..." + $keyValue.Substring($keyValue.Length-4,4) } else { "***" }
                
                $needsRotation = $keyAgeDays -gt $RotationThresholdDays
                
                Write-Host "  Key: $keyName - Age: $keyAgeDays days" -ForegroundColor $(if($needsRotation){"Red"}else{"Green"})
                
                if ($needsRotation) {
                    $script:issuesFound++
                    
                    if ($Mode -eq "rotate") {
                        Write-Host "    [ROTATING] $keyName..." -ForegroundColor Yellow
                        
                        try {
                            $newKey = az appconfig credential regenerate --name $configName --resource-group $rgName --id $keyId --output json 2>$null | ConvertFrom-Json
                            
                            if ($newKey) {
                                $newKeyValue = $newKey.value
                                $newKeyPreview = if($newKeyValue.Length -gt 8) { $newKeyValue.Substring(0,4) + "..." + $newKeyValue.Substring($newKeyValue.Length-4,4) } else { "***" }
                                
                                Write-Host "    [OK] Key rotated" -ForegroundColor Green
                                $script:keysRotated++
                                
                                $secretName = "AppConfig-$configName-$keyName"
                                if ($KeyVaultName) {
                                    try {
                                        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -SecretValue (ConvertTo-SecureString $newKey.connectionString -AsPlainText -Force) | Out-Null
                                        Write-Host "    [OK] Stored in Key Vault" -ForegroundColor Green
                                    } catch {
                                        Write-Host "    [WARNING] Could not store in Key Vault" -ForegroundColor Yellow
                                    }
                                }
                                
                                Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotated" -Status "Success" -Details "Key rotated and stored in Key Vault" -OldKeyPreview $keyPreview -NewKeyPreview $newKeyPreview
                                
                            } else {
                                Write-Host "    [ERROR] Rotation failed" -ForegroundColor Red
                                Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotation Failed" -Status "Error" -Details "Could not regenerate key" -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                            }
                            
                        } catch {
                            Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
                            Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Rotation Failed" -Status "Error" -Details $_.Exception.Message -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                        }
                        
                    } else {
                        Write-Host "    [PREVIEW] Would rotate this key" -ForegroundColor Yellow
                        Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Preview" -Status "Needs Rotation" -Details "Key is $keyAgeDays days old" -OldKeyPreview $keyPreview -NewKeyPreview "Would be regenerated"
                    }
                } else {
                    Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType $keyName -KeyAgeDays $keyAgeDays -Action "Checked" -Status "OK" -Details "Key is only $keyAgeDays days old" -OldKeyPreview $keyPreview -NewKeyPreview "N/A"
                }
            }
            
        } catch {
            Write-RotationLog "Error processing $configName : $($_.Exception.Message)" "ERROR"
            Add-RotationEntry -Subscription $sub.name -ResourceType "AppConfiguration" -ResourceName $configName -KeyType "N/A" -KeyAgeDays 0 -Action "Error" -Status "Failed" -Details $_.Exception.Message -OldKeyPreview "N/A" -NewKeyPreview "N/A"
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  ROTATION SUMMARY" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Mode: $Mode" -ForegroundColor White
Write-Host "Threshold: Keys older than $RotationThresholdDays days" -ForegroundColor White
Write-Host "Subscriptions Scanned: $($subscriptions.Count)" -ForegroundColor White
Write-Host "Storage Accounts Scanned: $script:storageAccountsScanned" -ForegroundColor White
Write-Host "Keys Requiring Rotation: $script:issuesFound" -ForegroundColor $(if($script:issuesFound -gt 0){"Red"}else{"Green"})
Write-Host ""

if ($Mode -eq "rotate") {
    Write-Host "ACTIONS TAKEN:" -ForegroundColor Yellow
    Write-Host "  Keys Rotated: $script:keysRotated" -ForegroundColor Green
    Write-Host "  App Services Updated: $script:appServicesUpdated" -ForegroundColor Green
} else {
    Write-Host "PREVIEW RESULTS:" -ForegroundColor Yellow
    Write-Host "  Keys Would Rotate: $script:issuesFound" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  GENERATING REPORTS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if (!(Test-Path ".\Reports")) {
    New-Item -Path ".\Reports" -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = ".\Reports\Key-Rotation-Report-$timestamp.csv"
$htmlPath = ".\Reports\Key-Rotation-Report-$timestamp.html"

$script:rotationReport | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "[OK] CSV Report: $csvPath" -ForegroundColor Green

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Key Rotation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; }
        h1 { color: #0078D4; border-bottom: 3px solid #0078D4; padding-bottom: 10px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #0078D4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .success { color: #107c10; font-weight: bold; }
        .error { color: #d13438; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure Key Rotation Report - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</h1>
        <p>Mode: $Mode | Threshold: $RotationThresholdDays days</p>
        <p>Subscriptions: $($subscriptions.Count) | Keys Requiring Rotation: $script:issuesFound</p>
        <table>
            <tr>
                <th>Timestamp</th>
                <th>Subscription</th>
                <th>Resource Name</th>
                <th>Key Type</th>
                <th>Age (Days)</th>
                <th>Action</th>
                <th>Status</th>
                <th>Details</th>
            </tr>
"@

foreach ($entry in $script:rotationReport) {
    $statusClass = if($entry.Status -eq "Success" -or $entry.Status -eq "OK") { "success" } else { "error" }
    
    $htmlContent += @"
            <tr>
                <td>$($entry.Timestamp)</td>
                <td>$($entry.Subscription)</td>
                <td>$($entry.ResourceName)</td>
                <td>$($entry.KeyType)</td>
                <td>$($entry.KeyAgeDays)</td>
                <td>$($entry.Action)</td>
                <td class="$statusClass">$($entry.Status)</td>
                <td>$($entry.Details)</td>
            </tr>
"@
}

$htmlContent += @"
        </table>
    </div>
</body>
</html>
"@

$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
Write-Host "[OK] HTML Report: $htmlPath" -ForegroundColor Green

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  KEY ROTATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""