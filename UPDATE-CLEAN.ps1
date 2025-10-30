# CLEAN - ONE SCRIPT TO UPDATE EVERYTHING
# Updates only reporting/audit/idle/schedule scripts
# Does NOT touch deployment/fix scripts
# Pushes to Git automatically
# Date: 2025-10-30

param(
    [string]$ScriptsPath = "D:\Azure-Production-Scripts"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MASTER UPDATE - CLEAN VERSION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Backup
$backupPath = "$ScriptsPath-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Creating backup..." -ForegroundColor Yellow
Copy-Item -Path $ScriptsPath -Destination $backupPath -Recurse -Force
Write-Host "Backup: $backupPath" -ForegroundColor Green
Write-Host ""

# Scripts to update
$updateScripts = @(
    "1-RBAC-Audit.ps1","2-NSG-Audit.ps1","3-Encryption-Audit.ps1","4-Backup-Audit.ps1","5-Cost-Tagging-Audit.ps1",
    "6-Policy-Compliance-Audit.ps1","7-Identity-AAD-Audit.ps1","8-SecurityCenter-Audit.ps1","9-AuditLog-Collection.ps1",
    "RUN-ALL-AUDITS.ps1","Azure-Analysis-Report.ps1","Complete-Audit-Report.ps1","IAM-Report.ps1","IAM-Security-Report.ps1",
    "Audit-IAM-Security.ps1","Ultimate-Multi-Subscription-Audit-Report.ps1","Azure-Security-Fix-Guide.ps1",
    "Idle-Resource-Report.ps1","Idle-Resource-Report-Extended.ps1","Find-All-Idle-Resources-Cost-Saving-Extended.ps1",
    "Azure-Idle-Compare-Report.ps1","Cost-Optimization-Idle-Resource.ps1","Schedule-ADSecurity-Report.ps1",
    "Schedule-Cost-Saving-Report.ps1","Schedule-IAM-Report.ps1","Schedule-Audit-Report.ps1","Schedule-Monitor-Report.ps1",
    "Schedule-Security-Audit-Report.ps1","Send-IAM-Report.ps1","Send-Monitor-Report.ps1"
)

# Cost analysis code
$costCode = @'

# ========================================
# COST ANALYSIS WITH FULL DETAILS
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
$currentContext = Get-AzContext
$subscriptionName = $currentContext.Subscription.Name
$subscriptionId = $currentContext.Subscription.Id
Write-Host "COST ANALYSIS - $subscriptionName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$costData = @{SubscriptionName=$subscriptionName;SubscriptionId=$subscriptionId;TotalMonthlyCost=0;LiveCost=0;IdleCost=0;CostByRegion=@{};LiveVMs=@();StoppedVMs=@();UnattachedDisks=@();UnusedIPs=@()}
try {
    Write-Host "Analyzing costs for subscription: $subscriptionName" -ForegroundColor Yellow
    Write-Host "  Analyzing Virtual Machines..." -ForegroundColor Gray
    $vms = Get-AzVM -Status
    foreach ($vm in $vms) {
        $vmSize = $vm.HardwareProfile.VmSize
        $vmRegion = $vm.Location
        $cost = switch -Wildcard ($vmSize) {
            "*A1*"{30};"*A2*"{60};"*A4*"{120};"*D2*"{100};"*D4*"{140};"*D8*"{280};"*D16*"{560};"*D32*"{1120}
            "*E2*"{110};"*E4*"{150};"*E8*"{300};"*E16*"{600};"*E32*"{1200};"*F2*"{90};"*F4*"{120};"*F8*"{240};"*F16*"{480}
            "*B1*"{8};"*B2*"{30};"*B4*"{60};default{50}
        }
        if ($vm.PowerState -match "deallocated|stopped") {
            $costData.StoppedVMs += @{Name=$vm.Name;ResourceGroup=$vm.ResourceGroupName;Region=$vmRegion;Size=$vmSize;Cost=$cost}
            $costData.IdleCost += $cost
        } else {
            $costData.LiveVMs += @{Name=$vm.Name;ResourceGroup=$vm.ResourceGroupName;Region=$vmRegion;Size=$vmSize;Cost=$cost}
            $costData.LiveCost += $cost
            if (!$costData.CostByRegion.ContainsKey($vmRegion)) {$costData.CostByRegion[$vmRegion]=0}
            $costData.CostByRegion[$vmRegion] += $cost
        }
    }
    Write-Host "  Analyzing Unattached Disks..." -ForegroundColor Gray
    $disks = Get-AzDisk
    foreach ($disk in $disks) {
        if (!$disk.ManagedBy) {
            $diskCost = [math]::Round($disk.DiskSizeGB * 0.10, 2)
            $costData.UnattachedDisks += @{Name=$disk.Name;ResourceGroup=$disk.ResourceGroupName;Region=$disk.Location;Size=$disk.DiskSizeGB;Cost=$diskCost}
            $costData.IdleCost += $diskCost
        }
    }
    Write-Host "  Analyzing Public IP Addresses..." -ForegroundColor Gray
    $pips = Get-AzPublicIpAddress
    foreach ($pip in $pips) {
        if (!$pip.IpConfiguration) {
            $costData.UnusedIPs += @{Name=$pip.Name;ResourceGroup=$pip.ResourceGroupName;Region=$pip.Location;IPAddress=$pip.IpAddress;Cost=3}
            $costData.IdleCost += 3
        }
    }
    $costData.TotalMonthlyCost = $costData.LiveCost + $costData.IdleCost
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "COST SUMMARY - $subscriptionName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Subscription ID: $subscriptionId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "LIVE RESOURCES:" -ForegroundColor Green
    Write-Host "  VMs Running: $($costData.LiveVMs.Count)" -ForegroundColor White
    Write-Host "  Live Cost: `$$([math]::Round($costData.LiveCost, 2))/month" -ForegroundColor Green
    Write-Host ""
    Write-Host "IDLE RESOURCES:" -ForegroundColor Yellow
    Write-Host "  Stopped VMs: $($costData.StoppedVMs.Count)" -ForegroundColor White
    Write-Host "  Unattached Disks: $($costData.UnattachedDisks.Count)" -ForegroundColor White
    Write-Host "  Unused Public IPs: $($costData.UnusedIPs.Count)" -ForegroundColor White
    Write-Host "  Idle Cost: `$$([math]::Round($costData.IdleCost, 2))/month" -ForegroundColor Yellow
    Write-Host ""
    if ($costData.CostByRegion.Count -gt 0) {
        Write-Host "COST BY REGION:" -ForegroundColor Cyan
        foreach ($region in $costData.CostByRegion.Keys | Sort-Object) {
            Write-Host "  $region : `$$([math]::Round($costData.CostByRegion[$region], 2))/month" -ForegroundColor White
        }
        Write-Host ""
    }
    Write-Host "TOTAL MONTHLY COST: `$$([math]::Round($costData.TotalMonthlyCost, 2))" -ForegroundColor Cyan
    Write-Host "POTENTIAL SAVINGS: `$$([math]::Round($costData.IdleCost, 2))/month" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    $global:AzureCostData = $costData
} catch {
    Write-Host "Warning: Could not complete cost analysis - $_" -ForegroundColor Yellow
}
# ========================================

'@

# Copy new scripts
Write-Host "Step 1: Copying new scripts..." -ForegroundColor Green
$newScripts = @("Azure-Multi-Subscription-Cost-Analysis.ps1","Send-Azure-Reports-Email.ps1","Setup-Azure-Scheduled-Tasks.ps1")
$copied = 0
foreach ($script in $newScripts) {
    $source = "D:\$script"
    $dest = "$ScriptsPath\$script"
    if (Test-Path $source) {
        Copy-Item $source $dest -Force
        Write-Host "Copied $script" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "Not found: $script" -ForegroundColor Yellow
    }
}
Write-Host ""

# Update scripts
Write-Host "Step 2: Adding cost analysis..." -ForegroundColor Green
$updated = 0
$alreadyUpdated = 0
foreach ($script in $updateScripts) {
    $path = "$ScriptsPath\$script"
    if (!(Test-Path $path)) { continue }
    $content = Get-Content $path -Raw
    if ($content -match "COST ANALYSIS WITH FULL DETAILS") {
        $alreadyUpdated++
        continue
    }
    $inserted = $false
    if ($content -match "(?s)(Set-AzContext[^\n]*\n)") {
        $point = $matches[0]
        $newContent = $content -replace [regex]::Escape($point), "$point$costCode"
        $newContent | Set-Content $path -Encoding UTF8
        Write-Host "Updated $script" -ForegroundColor Green
        $updated++
        $inserted = $true
    } elseif ($content -match "(?s)(Select-AzSubscription[^\n]*\n)") {
        $point = $matches[0]
        $newContent = $content -replace [regex]::Escape($point), "$point$costCode"
        $newContent | Set-Content $path -Encoding UTF8
        Write-Host "Updated $script" -ForegroundColor Green
        $updated++
        $inserted = $true
    }
}
Write-Host ""
Write-Host "Updated: $updated scripts" -ForegroundColor Green
Write-Host ""

# Verify protected scripts
Write-Host "Step 3: Verifying deployment scripts..." -ForegroundColor Green
$protected = @("Deploy-AVD-Production.ps1","Deploy-Bastion-VM.ps1","Fix-Azure-Security-Issues.ps1","Enable-MFA-All-Users.ps1")
$safe = $true
foreach ($script in $protected) {
    $path = "$ScriptsPath\$script"
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        if ($content -match "COST ANALYSIS WITH FULL DETAILS") {
            Write-Host "ERROR: $script was modified!" -ForegroundColor Red
            $safe = $false
        }
    }
}
if ($safe) {
    Write-Host "All deployment scripts are safe" -ForegroundColor Green
} else {
    Write-Host "ERROR: Deployment scripts modified - ABORTING" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Push to Git
Write-Host "Step 4: Pushing to Git..." -ForegroundColor Green
Set-Location $ScriptsPath
try {
    git add *.ps1
    git commit -m "Add cost analysis to reporting scripts with full details"
    git push origin main
    Write-Host "Changes pushed to Git" -ForegroundColor Green
} catch {
    Write-Host "Git push failed: $_" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Updated: $updated scripts" -ForegroundColor White
Write-Host "New scripts: $copied" -ForegroundColor White
Write-Host ""
Write-Host "ON WORK LAPTOP RUN:" -ForegroundColor Yellow
Write-Host "cd D:\Azure-Production-Scripts" -ForegroundColor White
Write-Host "git pull origin main" -ForegroundColor White
Write-Host ""
