# Setup Azure Scheduled Tasks
# Creates automated scheduled tasks for all audit, reporting, and cost analysis scripts
# Author: Automated Task Scheduler
# Date: 2025-10-30

#Requires -RunAsAdministrator

param(
    [string]$ScriptsPath = "D:\Azure-Production-Scripts",
    [string]$ReportsPath = "C:\Scripts\Reports",
    [string]$TaskScheduleTime = "06:00AM",  # When to run daily tasks
    [string]$WeeklyDay = "Friday",          # Day for weekly reports
    [switch]$RemoveExisting
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure Scheduled Tasks Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "✗ This script must be run as Administrator" -ForegroundColor Red
    Write-Host "  Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Create reports directory if it doesn't exist
if (!(Test-Path $ReportsPath)) {
    New-Item -ItemType Directory -Path $ReportsPath -Force | Out-Null
    Write-Host "✓ Created reports directory: $ReportsPath" -ForegroundColor Green
}

# Task prefix for easy identification
$taskPrefix = "Azure-"

# Remove existing tasks if requested
if ($RemoveExisting) {
    Write-Host "Removing existing Azure scheduled tasks..." -ForegroundColor Yellow
    Get-ScheduledTask | Where-Object { $_.TaskName -like "$taskPrefix*" } | 
        ForEach-Object { 
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false 
            Write-Host "  ✓ Removed: $($_.TaskName)" -ForegroundColor Gray
        }
    Write-Host ""
}

# Function to create a scheduled task
function New-AzureScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Description,
        [string]$Schedule,  # Daily, Weekly, Monthly
        [string]$Time = "06:00AM",
        [string]$DayOfWeek = "Friday",
        [int]$DayOfMonth = 1
    )
    
    $fullTaskName = "$taskPrefix$TaskName"
    
    # Check if script exists
    if (!(Test-Path $ScriptPath)) {
        Write-Host "  ✗ Script not found: $ScriptPath" -ForegroundColor Red
        return $false
    }
    
    try {
        # Create action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`"" `
            -WorkingDirectory (Split-Path $ScriptPath)
        
        # Create trigger based on schedule
        switch ($Schedule) {
            "Daily" {
                $trigger = New-ScheduledTaskTrigger -Daily -At $Time
            }
            "Weekly" {
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time
            }
            "Monthly" {
                $trigger = New-ScheduledTaskTrigger -Daily -At $Time
                # Note: Monthly trigger requires additional configuration
            }
            default {
                Write-Host "  ✗ Invalid schedule: $Schedule" -ForegroundColor Red
                return $false
            }
        }
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew
        
        # Create principal (run as SYSTEM)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Register the task
        Register-ScheduledTask `
            -TaskName $fullTaskName `
            -Description $Description `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null
        
        Write-Host "  ✓ Created: $fullTaskName" -ForegroundColor Green
        return $true
        
    } catch {
        Write-Host "  ✗ Failed to create task: $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "Creating scheduled tasks..." -ForegroundColor Green
Write-Host ""

$successCount = 0
$failCount = 0

# ===== AUDIT SCRIPTS (Run Daily) =====
Write-Host "📋 Audit Scripts (Daily at $TaskScheduleTime)" -ForegroundColor Magenta

$auditTasks = @(
    @{Name="RBAC-Audit-Daily"; Script="1-RBAC-Audit.ps1"; Desc="Daily RBAC and permissions audit"},
    @{Name="NSG-Audit-Daily"; Script="2-NSG-Audit.ps1"; Desc="Daily network security group audit"},
    @{Name="Encryption-Audit-Daily"; Script="3-Encryption-Audit.ps1"; Desc="Daily encryption compliance audit"},
    @{Name="Backup-Audit-Daily"; Script="4-Backup-Audit.ps1"; Desc="Daily backup policy audit"},
    @{Name="Cost-Tagging-Audit-Daily"; Script="5-Cost-Tagging-Audit.ps1"; Desc="Daily cost and tagging audit"},
    @{Name="Policy-Compliance-Daily"; Script="6-Policy-Compliance-Audit.ps1"; Desc="Daily policy compliance audit"},
    @{Name="Identity-AAD-Audit-Daily"; Script="7-Identity-AAD-Audit.ps1"; Desc="Daily Azure AD identity audit"},
    @{Name="SecurityCenter-Audit-Daily"; Script="8-SecurityCenter-Audit.ps1"; Desc="Daily Security Center audit"},
    @{Name="AuditLog-Collection-Daily"; Script="9-AuditLog-Collection.ps1"; Desc="Daily audit log collection"}
)

foreach ($task in $auditTasks) {
    $scriptPath = Join-Path $ScriptsPath $task.Script
    $result = New-AzureScheduledTask -TaskName $task.Name -ScriptPath $scriptPath `
        -Description $task.Desc -Schedule "Daily" -Time $TaskScheduleTime
    
    if ($result) { $successCount++ } else { $failCount++ }
}

Write-Host ""

# ===== REPORTING SCRIPTS (Run Weekly on Friday) =====
Write-Host "📊 Reporting Scripts (Weekly on $WeeklyDay at $TaskScheduleTime)" -ForegroundColor Magenta

$reportTasks = @(
    @{Name="Azure-Analysis-Weekly"; Script="Azure-Analysis-Report.ps1"; Desc="Weekly Azure infrastructure analysis"},
    @{Name="Complete-Audit-Weekly"; Script="Complete-Audit-Report.ps1"; Desc="Weekly complete audit report"},
    @{Name="IAM-Report-Weekly"; Script="IAM-Report.ps1"; Desc="Weekly IAM and permissions report"},
    @{Name="IAM-Security-Weekly"; Script="IAM-Security-Report.ps1"; Desc="Weekly IAM security report"},
    @{Name="Multi-Sub-Audit-Weekly"; Script="Ultimate-Multi-Subscription-Audit-Report.ps1"; Desc="Weekly multi-subscription audit"}
)

foreach ($task in $reportTasks) {
    $scriptPath = Join-Path $ScriptsPath $task.Script
    $result = New-AzureScheduledTask -TaskName $task.Name -ScriptPath $scriptPath `
        -Description $task.Desc -Schedule "Weekly" -Time $TaskScheduleTime -DayOfWeek $WeeklyDay
    
    if ($result) { $successCount++ } else { $failCount++ }
}

Write-Host ""

# ===== IDLE RESOURCE SCRIPTS (Run Weekly on Friday) =====
Write-Host "💤 Idle Resource Scripts (Weekly on $WeeklyDay at $TaskScheduleTime)" -ForegroundColor Magenta

$idleTasks = @(
    @{Name="Idle-Resources-Weekly"; Script="Idle-Resource-Report.ps1"; Desc="Weekly idle resource identification"},
    @{Name="Idle-Extended-Weekly"; Script="Idle-Resource-Report-Extended.ps1"; Desc="Weekly extended idle resource report"},
    @{Name="Cost-Savings-Weekly"; Script="Find-All-Idle-Resources-Cost-Saving-Extended.ps1"; Desc="Weekly cost savings analysis"},
    @{Name="Idle-Compare-Weekly"; Script="Azure-Idle-Compare-Report.ps1"; Desc="Weekly idle resource comparison"},
    @{Name="Cost-Optimization-Weekly"; Script="Cost-Optimization-Idle-Resource.ps1"; Desc="Weekly cost optimization report"}
)

foreach ($task in $idleTasks) {
    $scriptPath = Join-Path $ScriptsPath $task.Script
    $result = New-AzureScheduledTask -TaskName $task.Name -ScriptPath $scriptPath `
        -Description $task.Desc -Schedule "Weekly" -Time $TaskScheduleTime -DayOfWeek $WeeklyDay
    
    if ($result) { $successCount++ } else { $failCount++ }
}

Write-Host ""

# ===== COST ANALYSIS (Run Weekly on Friday) =====
Write-Host "💰 Cost Analysis Scripts (Weekly on $WeeklyDay at $TaskScheduleTime)" -ForegroundColor Magenta

$costScript = Join-Path $ScriptsPath "Azure-Multi-Subscription-Cost-Analysis.ps1"
$result = New-AzureScheduledTask -TaskName "Cost-Analysis-Weekly" -ScriptPath $costScript `
    -Description "Weekly multi-subscription cost analysis for all 13 subscriptions" `
    -Schedule "Weekly" -Time $TaskScheduleTime -DayOfWeek $WeeklyDay

if ($result) { $successCount++ } else { $failCount++ }

Write-Host ""

# ===== EMAIL REPORTS (Run after audits complete) =====
Write-Host "📧 Email Report Tasks (Weekly on $WeeklyDay)" -ForegroundColor Magenta

# Calculate time 30 minutes after main tasks
$emailTime = (Get-Date $TaskScheduleTime).AddMinutes(30).ToString("hh:mmtt")

$emailTasks = @(
    @{Name="Email-Weekly-Reports"; Script="Send-Azure-Reports-Email.ps1"; Args="-ReportType Weekly"; Desc="Send weekly summary reports via email"},
    @{Name="Email-Cost-Analysis"; Script="Send-Azure-Reports-Email.ps1"; Args="-ReportType CostAnalysis"; Desc="Send cost analysis reports via email"},
    @{Name="Email-Idle-Resources"; Script="Send-Azure-Reports-Email.ps1"; Args="-ReportType IdleResources"; Desc="Send idle resource reports via email"}
)

foreach ($task in $emailTasks) {
    $scriptPath = Join-Path $ScriptsPath $task.Script
    
    if (Test-Path $scriptPath) {
        $fullTaskName = "$taskPrefix$($task.Name)"
        
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" $($task.Args)" `
            -WorkingDirectory (Split-Path $scriptPath)
        
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $WeeklyDay -At $emailTime
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        try {
            Register-ScheduledTask `
                -TaskName $fullTaskName `
                -Description $task.Desc `
                -Action $action `
                -Trigger $trigger `
                -Settings $settings `
                -Principal $principal `
                -Force | Out-Null
            
            Write-Host "  ✓ Created: $fullTaskName (at $emailTime)" -ForegroundColor Green
            $successCount++
        } catch {
            Write-Host "  ✗ Failed to create: $fullTaskName" -ForegroundColor Red
            $failCount++
        }
    }
}

Write-Host ""

# ===== MASTER RUN-ALL TASK (Run Weekly) =====
Write-Host "🚀 Master Execution Task (Weekly on $WeeklyDay at $TaskScheduleTime)" -ForegroundColor Magenta

$runAllScript = Join-Path $ScriptsPath "RUN-ALL-AUDITS.ps1"
if (Test-Path $runAllScript) {
    $result = New-AzureScheduledTask -TaskName "Run-All-Audits-Weekly" -ScriptPath $runAllScript `
        -Description "Master script to run all audit scripts in sequence" `
        -Schedule "Weekly" -Time $TaskScheduleTime -DayOfWeek $WeeklyDay
    
    if ($result) { $successCount++ } else { $failCount++ }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Task Creation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successfully Created: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if($failCount -gt 0){"Red"}else{"Green"})
Write-Host ""

# Show created tasks
Write-Host "Created Scheduled Tasks:" -ForegroundColor Green
$allTasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "$taskPrefix*" } | Sort-Object TaskName

foreach ($task in $allTasks) {
    $nextRun = (Get-ScheduledTaskInfo -TaskName $task.TaskName).NextRunTime
    Write-Host "  ✓ $($task.TaskName)" -ForegroundColor Cyan
    Write-Host "    Next Run: $nextRun" -ForegroundColor Gray
    Write-Host "    $($task.Description)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Schedule Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Daily Tasks: Run every day at $TaskScheduleTime" -ForegroundColor White
Write-Host "  - All audit scripts (9 tasks)" -ForegroundColor Gray
Write-Host ""
Write-Host "Weekly Tasks: Run every $WeeklyDay at $TaskScheduleTime" -ForegroundColor White
Write-Host "  - All reporting scripts (5 tasks)" -ForegroundColor Gray
Write-Host "  - Idle resource scripts (5 tasks)" -ForegroundColor Gray
Write-Host "  - Cost analysis (1 task)" -ForegroundColor Gray
Write-Host "  - Master run-all script (1 task)" -ForegroundColor Gray
Write-Host ""
Write-Host "Email Tasks: Run every $WeeklyDay at $emailTime" -ForegroundColor White
Write-Host "  - Weekly summary email (1 task)" -ForegroundColor Gray
Write-Host "  - Cost analysis email (1 task)" -ForegroundColor Gray
Write-Host "  - Idle resources email (1 task)" -ForegroundColor Gray
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ ALL DONE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Configure email credentials for report sending:" -ForegroundColor White
Write-Host "   `$credential = Get-Credential" -ForegroundColor Gray
Write-Host "   `$credential | Export-Clixml -Path \"`$env:USERPROFILE\AzureReportsCredential.xml\"" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test a scheduled task manually:" -ForegroundColor White
Write-Host "   Start-ScheduledTask -TaskName 'Azure-Cost-Analysis-Weekly'" -ForegroundColor Gray
Write-Host ""
Write-Host "3. View task history:" -ForegroundColor White
Write-Host "   Get-ScheduledTask | Where-Object {`$_.TaskName -like 'Azure-*'} | Get-ScheduledTaskInfo" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Monitor reports in: $ReportsPath" -ForegroundColor White
Write-Host ""
Write-Host "All tasks are now scheduled and will run automatically! 🎉" -ForegroundColor Green
Write-Host ""

# Create a helper script to view task status
$helperScript = @"
# View Azure Scheduled Task Status
# Quick helper to see status of all Azure scheduled tasks

Write-Host "Azure Scheduled Tasks Status" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

Get-ScheduledTask | Where-Object { `$_.TaskName -like 'Azure-*' } | ForEach-Object {
    `$info = Get-ScheduledTaskInfo -TaskName `$_.TaskName
    
    Write-Host `$_.TaskName -ForegroundColor Green
    Write-Host "  State: `$(`$_.State)" -ForegroundColor Gray
    Write-Host "  Last Run: `$(`$info.LastRunTime)" -ForegroundColor Gray
    Write-Host "  Next Run: `$(`$info.NextRunTime)" -ForegroundColor Gray
    Write-Host "  Last Result: `$(`$info.LastTaskResult)" -ForegroundColor Gray
    Write-Host ""
}
"@

$helperScriptPath = Join-Path $ScriptsPath "View-Azure-Task-Status.ps1"
$helperScript | Out-File -FilePath $helperScriptPath -Encoding UTF8
Write-Host "Created helper script: $helperScriptPath" -ForegroundColor Cyan
Write-Host "Run it anytime to check task status!" -ForegroundColor Gray
