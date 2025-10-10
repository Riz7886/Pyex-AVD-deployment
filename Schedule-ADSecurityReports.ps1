#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Automated AD Security Reports with Email Delivery
.DESCRIPTION
    Runs AD Security script 2x per week and emails reports to leadership
    Emails sent to: John, Shaun, Anthony
#>

$ErrorActionPreference = "Stop"

Write-Host "Setting up AD Security Reports with Email..." -ForegroundColor Cyan

$recipients = @(
    "John.pinto@pyxhealth.com",
    "shaun.raj@pyxhealth.com",
    "anthony.schlak@pyxhealth.com"
)

$scriptPath = "D:\PYEX-AVD-Deployment\Ultimate-AD-Security-Hardening.ps1"
$taskName = "PYEX-AD-Security-Reports"

$wrapperScriptPath = "D:\PYEX-AVD-Deployment\Run-ADSecurity-WithEmail.ps1"

$wrapperScript = @"
`$recipients = @('John.pinto@pyxhealth.com','shaun.raj@pyxhealth.com','anthony.schlak@pyxhealth.com')

Write-Host 'Running AD Security script...' -ForegroundColor Cyan
& '$scriptPath'

Write-Host 'Finding latest report...' -ForegroundColor Cyan
`$latestReport = Get-ChildItem '.\Reports\*AD*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (`$latestReport) {
    Write-Host 'Emailing reports to leadership...' -ForegroundColor Cyan
    
    `$smtpServer = 'smtp.office365.com'
    `$smtpPort = 587
    `$smtpUser = 'YOUR_EMAIL@pyxhealth.com'
    `$smtpPassword = ConvertTo-SecureString 'YOUR_PASSWORD' -AsPlainText -Force
    `$credential = New-Object System.Management.Automation.PSCredential(`$smtpUser, `$smtpPassword)
    
    `$subject = "AD Security Report - `$(Get-Date -Format 'yyyy-MM-dd')"
    `$body = @"
<html>
<body>
<h2>Automated AD Security Report</h2>
<p>Please find attached the latest Active Directory security audit report.</p>
<p><strong>Report Date:</strong> `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>AD Security Checks:</strong></p>
<ul>
<li>Privileged account audit</li>
<li>Password policy compliance</li>
<li>Stale account detection</li>
<li>Group membership audit</li>
<li>Domain controller security</li>
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

$trigger1 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At 9:00AM
$trigger2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 9:00AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger1,$trigger2 -Principal $principal -Settings $settings | Out-Null

Write-Host "[OK] Task created with email to:" -ForegroundColor Green
foreach ($email in $recipients) {
    Write-Host "  - $email" -ForegroundColor White
}
Write-Host ""
