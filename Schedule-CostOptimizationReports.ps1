#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Automated Cost Optimization Reports with Email Delivery
.DESCRIPTION
    Runs Cost Optimization script 2x per week and emails reports to leadership
    Emails sent to: John, Shaun, Anthony
#>

$ErrorActionPreference = "Stop"

Write-Host "Setting up Cost Optimization Reports with Email..." -ForegroundColor Cyan

$recipients = @(
    "John.pinto@pyxhealth.com",
    "shaun.raj@pyxhealth.com",
    "anthony.schlak@pyxhealth.com"
)

$scriptPath = "D:\PYEX-AVD-Deployment\Cost-Optimization-Idle-Resources.ps1"
$taskName = "PYEX-Cost-Optimization-Reports"

$wrapperScriptPath = "D:\PYEX-AVD-Deployment\Run-CostReports-WithEmail.ps1"

$wrapperScript = @"
`$recipients = @('John.pinto@pyxhealth.com','shaun.raj@pyxhealth.com','anthony.schlak@pyxhealth.com')

Write-Host 'Running Cost Optimization script...' -ForegroundColor Cyan
& '$scriptPath'

Write-Host 'Finding latest report...' -ForegroundColor Cyan
`$latestReport = Get-ChildItem '.\Reports\All-Idle-Resources-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (`$latestReport) {
    Write-Host 'Emailing reports to leadership...' -ForegroundColor Cyan
    
    `$smtpServer = 'smtp.office365.com'
    `$smtpPort = 587
    `$smtpUser = 'YOUR_EMAIL@pyxhealth.com'
    `$smtpPassword = ConvertTo-SecureString 'YOUR_PASSWORD' -AsPlainText -Force
    `$credential = New-Object System.Management.Automation.PSCredential(`$smtpUser, `$smtpPassword)
    
    `$subject = "Cost Optimization Report - `$(Get-Date -Format 'yyyy-MM-dd')"
    `$body = @"
<html>
<body>
<h2>Automated Cost Optimization Report</h2>
<p>Please find attached the latest cost optimization report identifying idle resources and potential savings.</p>
<p><strong>Report Date:</strong> `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Includes:</strong></p>
<ul>
<li>Idle VMs and estimated savings</li>
<li>Unattached disks</li>
<li>Unused public IPs</li>
<li>Empty resource groups</li>
<li>Monthly and annual cost savings</li>
</ul>
<p>This is an automated report sent 2x per week.</p>
</body>
</html>
"@
    
    try {
        Send-MailMessage -From `$smtpUser -To `$recipients -Subject `$subject -Body `$body -BodyAsHtml -Attachments `$latestReport.FullName -SmtpServer `$smtpServer -Port `$smtpPort -UseSsl -Credential `$credential
        Write-Host 'Reports emailed successfully!' -ForegroundColor Green
    } catch {
        Write-Host "Email failed: `$_" -ForegroundColor Red
    }
}
"@

$wrapperScript | Out-File -FilePath $wrapperScriptPath -Encoding UTF8 -Force

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperScriptPath`""

$trigger1 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9:00AM
$trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At 9:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger1,$trigger2 -Principal $principal -Settings $settings | Out-Null

Write-Host "[OK] Task created with email to:" -ForegroundColor Green
foreach ($email in $recipients) {
    Write-Host "  - $email" -ForegroundColor White
}
Write-Host ""

