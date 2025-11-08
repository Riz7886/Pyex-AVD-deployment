<#
SYNOPSIS
  Registers a Windows Scheduled Task to run the monthly Datadog cost report + email.
  Runs on the 1st of each month at 08:00 local time.
USAGE
  .\Register-Monthly-ReportTask.ps1 -User "DOMAIN\User" -Password "Secret!23"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$User,
  [Parameter(Mandatory=$true)][string]$Password
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$send = Join-Path $here 'Send-Monthly-CostReport.ps1'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $send + '"')
$trigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 08:00
$principal = New-ScheduledTaskPrincipal -UserId $User -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask -TaskName 'Datadog-Monthly-Cost-Email' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -Password $Password
Write-Host "Registered task 'Datadog-Monthly-Cost-Email' to run on the 1st of every month at 08:00."
