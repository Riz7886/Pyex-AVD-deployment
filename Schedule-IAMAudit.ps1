#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Schedule Automated IAM Security Audits

.DESCRIPTION
    Creates Windows Task Scheduler tasks to run IAM security audits automatically:
    - Twice per week (Wednesday 8 AM, Friday 2 PM)
    - Runs all year long unattended
    - Automatic email delivery to stakeholders

.PARAMETER RemoveSchedule
    Switch to remove scheduled tasks

.PARAMETER TestRun
    Switch to test the scheduled task immediately

.EXAMPLE
    .\Schedule-IAMAudit.ps1

.EXAMPLE
    .\Schedule-IAMAudit.ps1 -RemoveSchedule

.EXAMPLE
    .\Schedule-IAMAudit.ps1 -TestRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ScriptPath = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [switch]$RemoveSchedule,

    [Parameter(Mandatory = $false)]
    [switch]$TestRun
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  IAM SECURITY AUDIT - AUTOMATED SCHEDULING"
Write-Host "=============================================================="
Write-Host ""

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$auditScript = Join-Path $ScriptPath "Audit-IAMSecurity.ps1"
$emailScript = Join-Path $ScriptPath "Send-IAMReport.ps1"

if (-not (Test-Path $auditScript)) {
    Write-Host "ERROR: Audit-IAMSecurity.ps1 not found" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $emailScript)) {
    Write-Host "ERROR: Send-IAMReport.ps1 not found" -ForegroundColor Red
    exit 1
}

Write-Host "Scripts verified successfully" -ForegroundColor Green
Write-Host ""

if ($RemoveSchedule) {
    Write-Host "Removing scheduled tasks..." -ForegroundColor Yellow
    
    $taskNames = @(
        "IAM-Security-Audit-Wednesday",
        "IAM-Security-Audit-Friday"
    )
    
    foreach ($taskName in $taskNames) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "Removed: $taskName" -ForegroundColor Green
            }
        } catch {
            Write-Host "Task not found: $taskName" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "Schedule removal complete!" -ForegroundColor Green
    Write-Host ""
    exit 0
}

if ($TestRun) {
    Write-Host "Running test execution..." -ForegroundColor Yellow
    Write-Host ""
    
    & PowerShell.exe -ExecutionPolicy Bypass -File $auditScript -SendEmail
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Test execution completed successfully!" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "Test execution failed" -ForegroundColor Red
        Write-Host ""
    }
    
    exit 0
}

Write-Host "Creating scheduled tasks..." -ForegroundColor Cyan
Write-Host ""

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Host "1. Creating: Wednesday 8:00 AM Audit Task" -ForegroundColor Yellow

$action1 = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$auditScript`" -SendEmail" `
    -WorkingDirectory $ScriptPath

$trigger1 = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek Wednesday `
    -At "08:00"

$settings1 = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

$principal1 = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType ServiceAccount `
    -RunLevel Highest

try {
    Register-ScheduledTask `
        -TaskName "IAM-Security-Audit-Wednesday" `
        -Description "Automated IAM Security Audit - Wednesday 8:00 AM" `
        -Action $action1 `
        -Trigger $trigger1 `
        -Settings $settings1 `
        -Principal $principal1 `
        -Force | Out-Null
    
    Write-Host "Wednesday task created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to create Wednesday task: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Creating: Friday 2:00 PM Audit Task" -ForegroundColor Yellow

$action2 = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$auditScript`" -SendEmail" `
    -WorkingDirectory $ScriptPath

$trigger2 = New-ScheduledTaskTrigger `
    -Weekly `
    -DaysOfWeek Friday `
    -At "14:00"

$settings2 = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

$principal2 = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType ServiceAccount `
    -RunLevel Highest

try {
    Register-ScheduledTask `
        -TaskName "IAM-Security-Audit-Friday" `
        -Description "Automated IAM Security Audit - Friday 2:00 PM" `
        -Action $action2 `
        -Trigger $trigger2 `
        -Settings $settings2 `
        -Principal $principal2 `
        -Force | Out-Null
    
    Write-Host "Friday task created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to create Friday task: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "  AUTOMATED SCHEDULING COMPLETE"
Write-Host "=============================================================="
Write-Host ""
Write-Host "Schedule:"
Write-Host "  Wednesday @ 8:00 AM"
Write-Host "  Friday @ 2:00 PM"
Write-Host "  Frequency: 2 times per week"
Write-Host "  Annual Reports: 104 per year"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Configure email: .\Config\email-config.json"
Write-Host "  2. Test: .\Schedule-IAMAudit.ps1 -TestRun"
Write-Host "  3. View tasks: taskschd.msc"
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""

$openScheduler = Read-Host "Open Task Scheduler? (Y/n)"
if ($openScheduler -ne 'n' -and $openScheduler -ne 'N') {
    Start-Process "taskschd.msc"
}