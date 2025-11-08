<#
SYNOPSIS
  End-to-end monthly workflow:
   1) Generate per-subscription cost reports (HTML + CSV)
   2) Convert HTML pages to PDF (if Edge/Chrome available)
   3) Upload to SharePoint and/or OneDrive (optional)
   4) Email index + CSV to recipients
USAGE
  # SharePoint upload + email
  .\Run-Monthly-ReportingWorkflow.ps1 -SharePointSiteUrl "https://tenant.sharepoint.com/sites/CloudOps" -SharePointLibrary "Shared Documents" -SharePointFolder "Datadog/Monthly Reports/$(Get-Date -Format yyyy-MM)" -SendEmail -Cred (Get-Credential)

  # OneDrive upload + email
  .\Run-Monthly-ReportingWorkflow.ps1 -OneDrivePath "Documents/Datadog/Monthly Reports/$(Get-Date -Format yyyy-MM)" -SendEmail -Cred (Get-Credential)

  # Both SP + OneDrive + email
  .\Run-Monthly-ReportingWorkflow.ps1 -SharePointSiteUrl ... -SharePointLibrary ... -SharePointFolder ... -OneDrivePath ... -SendEmail -Cred (Get-Credential)
#>
[CmdletBinding()]
param(
  [string]$DatadogSite = 'us3',
  [string]$SharePointSiteUrl,
  [string]$SharePointLibrary,
  [string]$SharePointFolder,
  [string]$OneDrivePath,
  [switch]$SendEmail,
  [pscredential]$Cred
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$gen  = Join-Path $here 'Generate-Datadog-CostReports-ASCII.ps1'
$pdf  = Join-Path $here 'Convert-Reports-To-PDF.ps1'
$sp   = Join-Path $here 'Upload-Reports-To-SharePoint.ps1'
$od   = Join-Path $here 'Upload-Reports-To-OneDrive.ps1'
$send = Join-Path $here 'Send-Monthly-CostReport.ps1'

# 1) Generate
powershell -NoProfile -ExecutionPolicy Bypass -File $gen -DatadogSite $DatadogSite

# 2) Convert to PDF
powershell -NoProfile -ExecutionPolicy Bypass -File $pdf

# 3) Upload destinations (optional)
if ($SharePointSiteUrl -and $SharePointLibrary -and $SharePointFolder) {
  powershell -NoProfile -ExecutionPolicy Bypass -File $sp -SiteUrl $SharePointSiteUrl -Library $SharePointLibrary -Folder $SharePointFolder
}
if ($OneDrivePath) {
  powershell -NoProfile -ExecutionPolicy Bypass -File $od -OneDrivePath $OneDrivePath
}

# 4) Email index + CSV (optional)
if ($SendEmail) {
  if ($null -eq $Cred) { $Cred = Get-Credential -Message "Enter sender mailbox credentials for SMTP" }
  powershell -NoProfile -ExecutionPolicy Bypass -File $send -Credential $Cred
}

Write-Host "Monthly workflow complete."
