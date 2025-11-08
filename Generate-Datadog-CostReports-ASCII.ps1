<#
SYNOPSIS
  Generate per-subscription cost & savings HTML + CSV reports from Datadog for the last 30 days,
  and compute "Savings vs Prior 30 Days" as a concrete dollar delta (previous30 - last30).
  Output:
    .\reports\index.html
    .\reports\<SubscriptionName>_<env>.html
    .\reports\costs.csv
NOTES
  - ASCII only
  - Uses Datadog REST API (US3 default)
  - Savings = Prior30dTotal - Last30dTotal (if negative, it's overspend)
#>
[CmdletBinding()]
param(
  [ValidateSet('us','us3','us5','eu','gov')][string]$DatadogSite = 'us3'
)

$ErrorActionPreference = 'Stop'

# === Keys embedded at request ===
$script:DD_APP = '195558c2-6170-4af6-ba4f-4267b05e4017'
$script:DD_API = '14fe5ae3-6459-40a4-8f3b-b3c8c97e520e'

function Get-DDSiteBase { param([string]$Site)
  switch ($Site) {
    'us'  { 'datadoghq.com' }
    'us3' { 'us3.datadoghq.com' }
    'us5' { 'us5.datadoghq.com' }
    'eu'  { 'datadoghq.eu' }
    'gov' { 'ddog-gov.com' }
    default { throw "Unsupported site: $Site" }
  }
}

$DDBase = Get-DDSiteBase -Site $DatadogSite

function Invoke-DD { param([ValidateSet('GET')][string]$Method='GET',[string]$Path)
  $uri = "https://api.$DDBase$Path"
  $h = @{'DD-API-KEY'=$script:DD_API;'DD-APPLICATION-KEY'=$script:DD_APP}
  Invoke-RestMethod -Method $Method -Uri $uri -Headers $h
}

function Infer-Env { param([string]$n)
  $x = $n.ToLowerInvariant()
  if ($x -match 'prod') { 'prod' }
  elseif ($x -match 'stag|stage') { 'staging' }
  elseif ($x -match 'qa') { 'qa' }
  elseif ($x -match 'test') { 'test' }
  else { 'dev' }
}

# Azure subscriptions list
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber }
Import-Module Az.Accounts
try { Connect-AzAccount -WarningAction SilentlyContinue | Out-Null } catch {}

$subs = Get-AzSubscription
if (-not $subs -or $subs.Count -eq 0) { Write-Error "No subscriptions found."; exit 3 }

# Time windows
$to = [int][double]::Parse((Get-Date -Date (Get-Date).ToUniversalTime() -UFormat %s))
$fromLast = [int][double]::Parse((Get-Date -Date ((Get-Date).AddDays(-30)).ToUniversalTime() -UFormat %s))
$fromPrev = [int][double]::Parse((Get-Date -Date ((Get-Date).AddDays(-60)).ToUniversalTime() -UFormat %s))
$toPrev   = [int][double]::Parse((Get-Date -Date ((Get-Date).AddDays(-30)).ToUniversalTime() -UFormat %s))

# Output folder
$root = Join-Path -Path (Get-Location) -ChildPath 'reports'
New-Item -Path $root -ItemType Directory -Force | Out-Null

# CSV writer
$csvPath = Join-Path $root 'costs.csv'
"Subscription,Env,SubscriptionId,Last30_USD,Prior30_USD,Savings_USD" | Out-File -FilePath $csvPath -Encoding ASCII -Force

# HTML helpers
function New-Html { param([string]$Title,[string]$Body)
  return "<!doctype html><html><head><meta charset='utf-8'><title>$Title</title><style>body{font-family:Segoe UI,Arial;margin:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px}th{background:#eef}h1,h2{color:#123}code{background:#f5f5f5;padding:2px 4px;border-radius:3px}</style></head><body>$Body</body></html>"
}

$indexRows = @()

foreach ($s in $subs) {
  $subName = $s.Name
  $subId   = $s.Id
  $env     = Infer-Env $subName

  # Query last 30
  $qLast = "/api/v1/query?from=$fromLast&to=$to&query=sum:cloud.cost.estimated_spend{provider:azure,subscription:$subId}.rollup(sum,86400)"
  $rLast = Invoke-DD -Path $qLast
  $sumLast = 0
  if ($rLast.series -and $rLast.series.pointlist) {
    foreach ($p in $rLast.series.pointlist) { if ($p.Count -ge 2 -and $p[1] -ne $null) { $sumLast += [double]$p[1] } }
  }

  # Query prior 30
  $qPrev = "/api/v1/query?from=$fromPrev&to=$toPrev&query=sum:cloud.cost.estimated_spend{provider:azure,subscription:$subId}.rollup(sum,86400)"
  $rPrev = Invoke-DD -Path $qPrev
  $sumPrev = 0
  if ($rPrev.series -and $rPrev.series.pointlist) {
    foreach ($p in $rPrev.series.pointlist) { if ($p.Count -ge 2 -and $p[1] -ne $null) { $sumPrev += [double]$p[1] } }
  }

  $savings = [math]::Round(($sumPrev - $sumLast), 2)
  $sumLast = [math]::Round($sumLast, 2)
  $sumPrev = [math]::Round($sumPrev, 2)

  # Write to CSV
  "$subName,$env,$subId,$sumLast,$sumPrev,$savings" | Out-File -FilePath $csvPath -Append -Encoding ASCII

  # Per-subscription HTML page
  $body = @"
<h1>Azure Cost Report  $subName (<code>$env</code>)</h1>
<h2>Summary (Last 30 Days)</h2>
<table>
  <tr><th>Subscription</th><td>$subName</td></tr>
  <tr><th>Env</th><td>$env</td></tr>
  <tr><th>Subscription Id</th><td><code>$subId</code></td></tr>
  <tr><th>Cost (Last 30d)</th><td><strong>$$sumLast</strong></td></tr>
  <tr><th>Cost (Prior 30d)</th><td>$$sumPrev</td></tr>
  <tr><th>Savings vs Prior 30d</th><td><strong>$$savings</strong></td></tr>
</table>
<p>Generated: $(Get-Date)</p>
"@

  $html = New-Html -Title "Cost  $subName" -Body $body
  $outPath = Join-Path $root ("{0}_{1}.html" -f ($subName -replace '[^\w\-]','_'), $env)
  [System.IO.File]::WriteAllText($outPath, $html)
  $indexRows += "<tr><td>$subName</td><td>$env</td><td><a href='./$(Split-Path -Leaf $outPath)'>Open report</a></td><td>$$sumLast</td><td>$$sumPrev</td><td>$$savings</td></tr>"
}

# Index HTML
$indexBody = "<h1>Azure Cost Reports (Last 30 Days)</h1><table><thead><tr><th>Subscription</th><th>Env</th><th>Report</th><th>Last30 ($)</th><th>Prior30 ($)</th><th>Savings ($)</th></tr></thead><tbody>"
$indexBody += ($indexRows -join [Environment]::NewLine)
$indexBody += "</tbody></table><p>Generated: $(Get-Date)</p>"
$indexHtml = New-Html -Title "Azure Cost Reports" -Body $indexBody
[System.IO.File]::WriteAllText((Join-Path $root 'index.html'), $indexHtml)

Write-Host "Reports generated at: $root"
Write-Host "CSV: $csvPath"
