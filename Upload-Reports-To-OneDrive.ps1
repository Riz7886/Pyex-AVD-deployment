<#
SYNOPSIS
  Uploads all reports (HTML, PDF, CSV) to OneDrive using Microsoft Graph.
REQUIRES
  Microsoft.Graph modules and consent to Files.ReadWrite.All.
USAGE
  .\Upload-Reports-To-OneDrive.ps1 -OneDrivePath "Documents/Datadog/Monthly Reports/2025-11"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$OneDrivePath
)

$modules = @('Microsoft.Graph.Authentication','Microsoft.Graph.Files')
foreach ($m in $modules) {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
}
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Files
Connect-MgGraph -Scopes "Files.ReadWrite.All" | Out-Null

$reports = Join-Path (Get-Location) 'reports'
if (-not (Test-Path $reports)) { Write-Error "reports folder not found."; exit 2 }

# Ensure path exists by creating nested folders
$segments = $OneDrivePath -split '[\\/]' | Where-Object { $_ -ne '' }
$basePath = ''
foreach ($seg in $segments) {
  $basePath = ($basePath -eq '') ? $seg : ($basePath + '/' + $seg)
  $check = Get-MgDriveItem -DriveId (Get-MgDrive -DriveType personal | Select-Object -First 1).Id -ItemId 'root' -ErrorAction SilentlyContinue
  # Create folder under root:/basePath:
  try {
    New-MgDriveItem -DriveId (Get-MgDrive -DriveType personal | Select-Object -First 1).Id -Name $seg -Folder @{} -ParentItemId 'root' -ErrorAction Stop | Out-Null
  } catch { }
}

# Upload files
$drive = Get-MgDrive -DriveType personal | Select-Object -First 1
Get-ChildItem $reports -File | Where-Object { $_.Extension -in ".html",".pdf",".csv" } | ForEach-Object {
  $rel = "$OneDrivePath/" + $_.Name
  $stream = [System.IO.File]::OpenRead($_.FullName)
  try {
    Invoke-MgGraphRequest -Method PUT -Uri "/me/drive/root:/$rel:/content" -Body $stream -ContentType "application/octet-stream" | Out-Null
    Write-Host "Uploaded: $rel"
  } finally {
    $stream.Dispose()
  }
}
Write-Host "OneDrive upload complete."
