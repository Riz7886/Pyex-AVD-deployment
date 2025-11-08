<#
SYNOPSIS
  Uploads all reports (HTML, PDF, CSV) to a SharePoint document library folder.
REQUIRES
  PnP.PowerShell module and interactive login.
USAGE
  .\Upload-Reports-To-SharePoint.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/CloudOps" -Library "Shared Documents" -Folder "Datadog/Monthly Reports/2025-11"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SiteUrl,
  [Parameter(Mandatory=$true)][string]$Library,
  [Parameter(Mandatory=$true)][string]$Folder
)

if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
  Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
}
Import-Module PnP.PowerShell
Connect-PnPOnline -Url $SiteUrl -Interactive

$reports = Join-Path (Get-Location) 'reports'
if (-not (Test-Path $reports)) { Write-Error "reports folder not found."; exit 2 }

# Ensure destination folder path exists
$parts = $Folder -split '[\\/]' | Where-Object { $_ -ne '' }
$path = ""
foreach ($p in $parts) {
  $path = ($path -ne "") ? ($path + "/" + $p) : $p
  Ensure-PnPFolder -SiteRelativePath ($Library + "/" + $path) | Out-Null
}

Get-ChildItem $reports -File | Where-Object { $_.Extension -in ".html",".pdf",".csv" } | ForEach-Object {
  $dest = ($Library.TrimEnd('/')) + '/' + $Folder.Trim('/')
  Write-Host "Uploading $($_.Name) -> $dest"
  Upload-PnPFile -Path $_.FullName -Folder $dest -Overwrite
}
Write-Host "SharePoint upload complete."
