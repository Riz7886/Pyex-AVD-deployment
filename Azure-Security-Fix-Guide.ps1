#Requires -Version 5.1

param(
    [string]$ReportPath = ".\Reports",
    [string]$OutputFormat = "Both"
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    $logFile = ".\Logs\$($MyInvocation.ScriptName)-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Connect-AzureWithSubscription {
    Write-Log "Connecting to Azure..."
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (!$context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Log "Connected to Azure successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    
    Write-Log "Discovering subscriptions..."
    $subscriptions = Get-AzSubscription
    
    if ($subscriptions.Count -eq 0) {
        Write-Log "No subscriptions found" "ERROR"
        exit 1
    }
    
    Write-Log "Found $($subscriptions.Count) subscription(s)" "SUCCESS"
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        Write-Host "  [$($i + 1)] $($sub.Name)"
        Write-Host "      ID: $($sub.Id)"
        Write-Host "      State: $($sub.State)"
        Write-Host ""
    }
    
    Write-Host "Select subscription (enter number 1-$($subscriptions.Count)):" -ForegroundColor Yellow
    $selection = Read-Host "Selection"
    
    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count) {
        Write-Log "Invalid selection" "ERROR"
        exit 1
    }
    
    $selectedSub = $subscriptions[$selectedIndex]
    Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
    
    Write-Log "Selected subscription: $($selectedSub.Name)" "SUCCESS"
    Write-Host ""
    
    return $selectedSub
}

function Export-ReportData {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,
        [Parameter(Mandatory=$true)]
        [string]$ReportName,
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionName,
        [string]$Format = "Both"
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeSubName = $SubscriptionName -replace '[^a-zA-Z0-9]', '_'
    $baseFileName = "$ReportName-$safeSubName-$timestamp"
    
    $csvPath = "$ReportPath\$baseFileName.csv"
    $htmlPath = "$ReportPath\$baseFileName.html"
    
    if ($Format -eq "CSV" -or $Format -eq "Both") {
        $Data | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "CSV report saved: $csvPath" "SUCCESS"
    }
    
    if ($Format -eq "HTML" -or $Format -eq "Both") {
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>$ReportName - $SubscriptionName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; }
        .info { background-color: #e7f3ff; padding: 10px; border-left: 4px solid #0078d4; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .high { color: #d13438; font-weight: bold; }
        .medium { color: #ff8c00; font-weight: bold; }
        .low { color: #107c10; }
    </style>
</head>
<body>
    <h1>$ReportName</h1>
    <div class="info">
        <strong>Subscription:</strong> $SubscriptionName<br>
        <strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
        <strong>Total Records:</strong> $($Data.Count)
    </div>
    <table>
        <tr>
"@
        
        if ($Data.Count -gt 0) {
            $Data[0].PSObject.Properties.Name | ForEach-Object {
                $htmlContent += "            <th>$_</th>`n"
            }
            $htmlContent += "        </tr>`n"
            
            foreach ($row in $Data) {
                $htmlContent += "        <tr>`n"
                $row.PSObject.Properties | ForEach-Object {
                    $value = $_.Value
                    $class = ""
                    if ($_.Name -eq "Severity") {
                        switch ($value) {
                            "Critical" { $class = " class='high'" }
                            "High" { $class = " class='high'" }
                            "Medium" { $class = " class='medium'" }
                            "Low" { $class = " class='low'" }
                        }
                    }
                    $htmlContent += "            <td$class>$value</td>`n"
                }
                $htmlContent += "        </tr>`n"
            }
        }
        
        $htmlContent += @"
    </table>
</body>
</html>
"@
        
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Log "HTML report saved: $htmlPath" "SUCCESS"
        
        Start-Process $htmlPath
    }
    
    return @{
        CSV = $csvPath
        HTML = $htmlPath
    }
}
# Security remediation guide

$subscription = Connect-AzureWithSubscription

Write-Log "Starting Azure-Security-Fix-Guide..."

$findings = @()

# Add specific logic for Azure-Security-Fix-Guide
Write-Log "Collecting data for Security remediation guide..."

# Placeholder - Add specific implementation
$findings += [PSCustomObject]@{
    ResourceName = "Sample"
    Status = "Active"
    Finding = "Security remediation guide executed successfully"
    Subscription = $subscription.Name
    ExecutionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

Write-Log "Execution complete. Total findings: $($findings.Count)"

$reportFiles = Export-ReportData -Data $findings -ReportName "Azure-Security-Fix-Guide" -SubscriptionName $subscription.Name -Format $OutputFormat

Write-Host ""
Write-Host "Azure-Security-Fix-Guide Complete" -ForegroundColor Green
Write-Host "Total Records: $($findings.Count)" -ForegroundColor Cyan
