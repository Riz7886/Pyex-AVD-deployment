<#
SYNOPSIS
  Converts each HTML report in .\reports\ to PDF using Microsoft Edge or Chrome headless.
NOTES
  - ASCII only, no external utilities required if Edge/Chrome is installed.
  - Output PDFs are written alongside the HTML files.
#>
[CmdletBinding()]
param()

$reports = Join-Path (Get-Location) 'reports'
if (-not (Test-Path $reports)) { Write-Error "reports folder not found."; exit 2 }

# Locate browsers
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$chrome = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $edge))   { $edge   = "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe" }
if (-not (Test-Path $chrome)) { $chrome = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe" }

$browser = $null
if (Test-Path $edge)   { $browser = $edge }
elseif (Test-Path $chrome) { $browser = $chrome }

if (-not $browser) {
  Write-Warning "Neither Edge nor Chrome found. Skipping PDF conversion."
  exit 0
}

Get-ChildItem -Path $reports -Filter *.html | ForEach-Object {
  $html = $_.FullName
  $pdf  = [System.IO.Path]::ChangeExtension($html, '.pdf')
  Write-Host "Printing to PDF: $($_.Name) -> $(Split-Path -Leaf $pdf)"
  & $browser --headless=new --disable-gpu --print-to-pdf="$pdf" "file:///$($html -replace '\\','/')"
}
Write-Host "PDF conversion complete."
