#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Automated Azure Monitor Reports with Email Delivery
.DESCRIPTION
    Runs Azure Monitor script 2x per week and emails reports to leadership
    Emails sent to: John, Shaun, Anthony
.EXAMPLE
    .\Schedule-MonitorReports.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "Setting up Azure Monitor Reports with Email..." -ForegroundColor Cyan

$recipients = @(
    "John.pinto@pyxhealth.com",
    "shaun.raj@pyxhealth.com",
    "anthony.schlak@pyxhealth.com"
)

$scriptPath = "D:\PYEX-AVD-Deployment\Deploy-Azure-Monitor-Alerts.ps1"
$taskName = "PYEX-Azure-Monitor-Reports"

$wrapperScriptPath = "D:\PYEX-AVD-Deployment\Run-MonitorReports-WithEmail.ps1"

$wrapperScript = @"
`$recipients = @('John.pinto@pyxhealth.com','shaun.raj@pyxhealth.com','anthony.schlak@pyxhealth.com')

Write-Host 'Running Azure Monitor script...' -ForegroundColor Cyan
& '$scriptPath' -Mode deploy

Write-Host 'Finding latest report...' -ForegroundColor Cyan
`$latestReport = Get-ChildItem '.\Reports\Azure-Monitor-Report-*.html' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
`$latestCSV = Get-ChildItem '.\Reports\Azure-Monitor-Report-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (`$latestReport -and `$latestCSV) {
    Write-Host 'Emailing reports to leadership...' -ForegroundColor Cyan
    
    `$smtpServer = 'smtp.office365.com'
    `$smtpPort = 587
    `$smtpUser = 'YOUR_EMAIL@pyxhealth.com'
    `$smtpPassword = ConvertTo-SecureString 'YOUR_PASSWORD' -AsPlainText -Force
    `$credential = New-Object System.Management.Automation.PSCredential(`$smtpUser, `$smtpPassword)
    
    `$subject = "Azure Monitor Report - `$(Get-Date -Format 'yyyy-MM-dd')"
    `$body = @"
<html>
<body>
<h2>Automated Azure Monitor Report</h2>
<p>Please find attached the latest Azure Monitor report covering all 15 subscriptions.</p>
<p><strong>Report Date:</strong> `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Includes:</strong></p>
<ul>
<li>Resource monitoring status</li>
<li>Alerts created</li>
<li>Issues fixed</li>
<li>Cost analysis and projections</li>
</ul>
<p>This is an automated report sent 2x per week.</p>
</body>
</html>
"@
    
    try {
        Send-MailMessage -From `$smtpUser -To `$recipients -Subject `$subject -Body `$body -BodyAsHtml -Attachments `$latestReport.FullName,`$latestCSV.FullName -SmtpServer `$smtpServer -Port `$smtpPort -UseSsl -Credential `$credential
        Write-Host 'Reports emailed successfully!' -ForegroundColor Green
    } catch {
        Write-Host "Email failed: `$_" -ForegroundColor Red
        Write-Host 'Reports saved locally in .\Reports folder' -ForegroundColor Yellow
    }
} else {
    Write-Host 'No reports found to email' -ForegroundColor Yellow
}
"@

$wrapperScript | Out-File -FilePath $wrapperScriptPath -Encoding UTF8 -Force

$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperScriptPath`""

$trigger1 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 8:00AM
$trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At 8:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger1,$trigger2 -Principal $principal -Settings $settings | Out-Null

Write-Host "[OK] Task created with email to:" -ForegroundColor Green
foreach ($email in $recipients) {
    Write-Host "  - $email" -ForegroundColor White
}
Write-Host ""

