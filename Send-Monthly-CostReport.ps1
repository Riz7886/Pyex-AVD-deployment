<#
SYNOPSIS
  Generate Datadog cost reports (per subscription/env) and email them to recipients.
  Intended to be run monthly by Windows Task Scheduler.
#>
[CmdletBinding()]
param(
  [string]$DatadogSite = 'us3',
  [string[]]$To = @('john.pinto@pyxhealth.com','anthoney.schlak@pyxhealth.com','shaun.raj@pyxhealth.com'),
  [string]$From = 'cloudops@pyxhealth.com',
  [string]$SmtpServer = 'smtp.office365.com',
  [int]$SmtpPort = 587,
  [switch]$UseSsl = $true,
  [pscredential]$Credential
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$gen = Join-Path $here 'Generate-Datadog-CostReports-ASCII.ps1'

# 1) Generate reports
powershell -NoProfile -ExecutionPolicy Bypass -File $gen -DatadogSite $DatadogSite

$reports = Join-Path $here 'reports'
$index = Join-Path $reports 'index.html'
$csv   = Join-Path $reports 'costs.csv'

if (-not (Test-Path $index)) { Write-Error "index.html not found in $reports"; exit 2 }

# 2) Email
$subject = "Azure Cost Reports  Last 30 Days (Datadog)  $(Get-Date -Format yyyy-MM)"
$body = Get-Content $index -Raw

# Send-MailMessage is deprecated but widely available. For O365, provide -Credential (App Password / OAuth token-based app-specific)
try {
  Send-MailMessage -To $To -From $From -Subject $subject -Body $body -BodyAsHtml -SmtpServer $SmtpServer -Port $SmtpPort -UseSsl:$UseSsl -Credential $Credential -Attachments $csv
  Write-Host "Email sent to: $($To -join ', ')"
} catch {
  Write-Warning "Failed to send email via Send-MailMessage. Please verify SMTP, credentials, or consider an internal relay."
  throw
}
