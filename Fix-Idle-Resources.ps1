#Requires -Version 5.1

<#
.SYNOPSIS
    Fix Idle Resources - Deletes idle resources found by Cost-Optimization-Idle-Resources.ps1

.DESCRIPTION
    Reads the CSV report from Cost-Optimization-Idle-Resources.ps1
    and deletes idle resources with confirmation
    
    READ-ONLY BY DEFAULT - Use -Execute to make changes
    
.PARAMETER ReportPath
    Path to the All-Idle-Resources.csv report
    
.PARAMETER Execute
    Actually delete resources (prompts for each)
    
.PARAMETER Force
    Skip confirmation prompts
    
.EXAMPLE
    .\Fix-Idle-Resources.ps1 -ReportPath ".\Reports\All-Idle-Resources.csv"
    (Read-only - shows what would be deleted)
    
.EXAMPLE
    .\Fix-Idle-Resources.ps1 -ReportPath ".\Reports\All-Idle-Resources.csv" -Execute
    (Prompts for each deletion)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReportPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$Execute,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

function Write-FixLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  FIX IDLE RESOURCES" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

if (-not (Test-Path $ReportPath)) {
    Write-FixLog "Report file not found: $ReportPath" "ERROR"
    throw "Report file not found"
}

$idleResources = Import-Csv -Path $ReportPath

Write-FixLog "Found $($idleResources.Count) idle resources in report" "INFO"

if (-not $Execute) {
    Write-Host "`n⚠️  READ-ONLY MODE" -ForegroundColor Yellow
    Write-Host "This is a preview. Use -Execute to actually delete resources`n" -ForegroundColor Yellow
}

$deleted = 0
$failed = 0
$skipped = 0

foreach ($resource in $idleResources) {
    Write-Host "`n----------------------------------------" -ForegroundColor Gray
    Write-Host "Resource: $($resource.ResourceName)" -ForegroundColor White
    Write-Host "Type: $($resource.ResourceType)" -ForegroundColor Gray
    Write-Host "Subscription: $($resource.Subscription)" -ForegroundColor Gray
    Write-Host "Resource Group: $($resource.ResourceGroup)" -ForegroundColor Gray
    Write-Host "Monthly Cost: `$$($resource.EstimatedMonthlyCost)" -ForegroundColor Yellow
    Write-Host "Reason: $($resource.Status)" -ForegroundColor Gray
    
    if (-not $Execute) {
        Write-Host "WOULD DELETE (Read-only mode)" -ForegroundColor Yellow
        continue
    }
    
    if (-not $Force) {
        $confirm = Read-Host "`nDelete this resource? (yes/no/skip-all)"
        if ($confirm -eq "skip-all") {
            Write-FixLog "Skipping remaining resources" "WARNING"
            break
        }
        if ($confirm -ne "yes") {
            Write-FixLog "Skipped" "WARNING"
            $skipped++
            continue
        }
    }
    
    try {
        $resourceId = "/subscriptions/$($resource.Subscription)/resourceGroups/$($resource.ResourceGroup)"
        
        switch ($resource.ResourceType) {
            "VM (Stopped)" {
                $vmName = $resource.ResourceName
                Write-FixLog "Deleting VM: $vmName" "INFO"
                az vm delete --name $vmName --resource-group $resource.ResourceGroup --yes
                $deleted++
            }
            "Disk (Unattached)" {
                $diskName = $resource.ResourceName
                Write-FixLog "Deleting disk: $diskName" "INFO"
                az disk delete --name $diskName --resource-group $resource.ResourceGroup --yes
                $deleted++
            }
            "Public IP (Unused)" {
                $pipName = $resource.ResourceName
                Write-FixLog "Deleting public IP: $pipName" "INFO"
                az network public-ip delete --name $pipName --resource-group $resource.ResourceGroup
                $deleted++
            }
            "Network Interface (Unused)" {
                $nicName = $resource.ResourceName
                Write-FixLog "Deleting NIC: $nicName" "INFO"
                az network nic delete --name $nicName --resource-group $resource.ResourceGroup
                $deleted++
            }
            "Resource Group (Empty)" {
                $rgName = $resource.ResourceName
                Write-FixLog "Deleting empty resource group: $rgName" "INFO"
                az group delete --name $rgName --yes
                $deleted++
            }
            default {
                Write-FixLog "Unknown resource type: $($resource.ResourceType)" "WARNING"
                $skipped++
            }
        }
        
        Write-FixLog "Deleted successfully" "SUCCESS"
        
    } catch {
        Write-FixLog "Failed to delete: $_" "ERROR"
        $failed++
    }
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  SUMMARY" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "Total Resources: $($idleResources.Count)" -ForegroundColor White
Write-Host "Deleted: $deleted" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "Skipped: $skipped" -ForegroundColor Yellow

if (-not $Execute) {
    Write-Host "`n⚠️  NO CHANGES MADE (Read-only mode)" -ForegroundColor Yellow
    Write-Host "Run with -Execute to actually delete resources" -ForegroundColor Yellow
}
