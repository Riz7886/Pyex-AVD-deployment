<# 
File: datadog-alert-automation.ps1
Author: ChatGPT (generated)
Purpose:
  - Enumerate ALL Azure subscriptions available to your login
  - **Preflight**: verify Datadog is receiving Azure metrics per subscription; skip subs with no live data
  - Discover Azure resources and create Datadog Monitors (NO Azure Monitor alerts used)
  - Supported resource types:
      VMs, App Services, SQL Databases, Storage Accounts, AKS, Key Vault,
      Application Gateway (+WAF), Data Factory, Cosmos DB, Event Hub,
      API Management (APIM), Azure Cache for Redis, Logic Apps
  - Add tags per subscription/resource for filtering in Datadog
  - Create CSV + HTML reports (and optional email delivery)
  - BONUS: Report on Service Principal credentials expiring (<= 90 days) as a Datadog event + report section
Security:
  - Reads Datadog API credentials from environment variables: DD_API_KEY and DD_APP_KEY
  - You can set them per-session:
      $env:DD_API_KEY="xxx"; $env:DD_APP_KEY="yyy"; $env:DD_SITE="us3.datadoghq.com"
Prereqs:
  - PowerShell 7+
  - Azure CLI installed and 'az login' permitted
  - Datadog Azure integrations enabled for EACH subscription you want metrics from
  - Proper permissions to enumerate resources (Reader) and AAD apps (optional for SP report)
Usage (quick, dry-run):
  pwsh ./datadog-alert-automation.ps1 -DryRun

Usage (create + email + Slack + PagerDuty):
  pwsh ./datadog-alert-automation.ps1 `
    -Recipients "ops@example.com,managers@example.com" `
    -SlackChannels "slack-yourws-#oncall,slack-yourws-#prod-alerts" `
    -PagerDutyServices "oncall-primary,oncall-backup" `
    -WebhookNames "notify-security" `
    -EmailReportTo "ops@example.com" `
    -SmtpServer "smtp.office365.com" -SmtpPort 587 `
    -SmtpFrom "alerts@example.com" -SmtpUser "alerts@example.com"
#>

[CmdletBinding()]
param(
  [string]$DatadogSite = $(if ($env:DD_SITE) { $env:DD_SITE } else { "us3.datadoghq.com" }),
  [string]$DatadogApiKey = $env:DD_API_KEY,
  [string]$DatadogAppKey = $env:DD_APP_KEY,

  # Mentions / notifications
  [string]$Recipients = "",
  [string]$SlackChannels = "",
  [string]$PagerDutyServices = "",
  [string]$WebhookNames = "",

  [switch]$DryRun,
  [string]$OutputDir = "./output",

  # Email options (optional)
  [string]$EmailReportTo = "",
  [string]$SmtpServer = "",
  [int]$SmtpPort = 587,
  [string]$SmtpFrom = "",
  [string]$SmtpUser = ""
)

# ===== Helpers =====
$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err ($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Err "Azure CLI 'az' not found. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"; exit 1 }
if (-not $DatadogApiKey -or -not $DatadogAppKey) { Err "Missing DD_API_KEY or DD_APP_KEY env vars."; exit 1 }

try { az account show --only-show-errors | Out-Null } catch { Info "Launching az login…"; az login --only-show-errors | Out-Null }

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$logPath  = Join-Path $OutputDir "run-$ts.log"
$csvPath  = Join-Path $OutputDir "created-monitors-$ts.csv"
$htmlPath = Join-Path $OutputDir "created-monitors-$ts.html"
Start-Transcript -Path $logPath -Append | Out-Null

$DdBase = "https://api.$DatadogSite"
$DdHeaders = @{
  "DD-API-KEY"        = $DatadogApiKey
  "DD-APPLICATION-KEY"= $DatadogAppKey
  "Content-Type"      = "application/json"
}
try {
  $val = Invoke-RestMethod -Uri "$DdBase/api/v1/validate" -Headers $DdHeaders -Method GET -ErrorAction Stop
  if (-not $val.valid) { throw "Datadog validation returned invalid" }
  Info "Datadog keys validated for site $DatadogSite"
} catch { Err "Datadog API validation failed: $($_.Exception.Message)"; Stop-Transcript | Out-Null; exit 1 }

function Build-NotifySuffix {
  param([string]$Recipients,[string]$SlackChannels,[string]$PagerDutyServices,[string]$WebhookNames)
  $mentions = @()
  if ($Recipients)       { $mentions += ($Recipients.Split(",")      | ForEach-Object { "@$($_.Trim())" }) }
  if ($SlackChannels)    { $mentions += ($SlackChannels.Split(",")    | ForEach-Object { "@$($_.Trim())" }) }
  if ($PagerDutyServices){ $mentions += ($PagerDutyServices.Split(",")| ForEach-Object { "@pagerduty-$($_.Trim())" }) }
  if ($WebhookNames)     { $mentions += ($WebhookNames.Split(",")     | ForEach-Object { "@webhook-$($_.Trim())" }) }
  if ($mentions.Count -gt 0) { return " " + ($mentions -join " ") } else { return "" }
}
$NotifySuffix = Build-NotifySuffix -Recipients $Recipients -SlackChannels $SlackChannels -PagerDutyServices $PagerDutyServices -WebhookNames $WebhookNames

function New-DdMonitor {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Query,
    [Parameter(Mandatory)][string]$Message,
    [string[]]$Tags,
    [int]$NoDataMinutes=15
  )
  $payload = @{
    name=$Name; type="metric alert"; query=$Query; message=$Message;
    tags=$Tags;
    options=@{ notify_no_data=$true; no_data_timeframe=$NoDataMinutes; include_tags=$true;
               evaluation_delay=300; threshold_windows=@{trigger_window="last_5m";recovery_window="last_5m"} }
  }
  if ($DryRun) { return @{ id = -1; dryrun=$true; name=$Name; query=$Query } }
  try {
    return Invoke-RestMethod -Uri "$DdBase/api/v1/monitor" -Headers $DdHeaders -Method POST -Body ($payload | ConvertTo-Json -Depth 10)
  } catch { Warn "Create monitor failed for $Name: $($_.Exception.Message)"; return $null }
}
function Post-DdEvent {
  param([string]$Title,[string]$Text,[string[]]$Tags)
  if ($DryRun) { return }
  $payload=@{ title=$Title; text=$Text; tags=$Tags }
  try { Invoke-RestMethod -Uri "$DdBase/api/v1/events" -Headers $DdHeaders -Method POST -Body ($payload|ConvertTo-Json -Depth 6) | Out-Null } catch { Warn "Event post failed: $($_.Exception.Message)" }
}

# ========= NEW: Datadog preflight per-subscription =========
function Test-SubscriptionMetrics {
  param([Parameter(Mandatory)][string]$SubscriptionId)
  $from = [int][double]([DateTimeOffset](Get-Date).AddMinutes(-30)).ToUnixTimeSeconds()
  $to   = [int][double]([DateTimeOffset](Get-Date)).ToUnixTimeSeconds()
  $candidates = @(
    "avg:azure.vm.cpu_percent{subscription_id:$SubscriptionId}",
    "sum:azure.app_service.http5xx{subscription_id:$SubscriptionId}",
    "avg:azure.sql.cpu_percent{subscription_id:$SubscriptionId}",
    "avg:azure.storage.availability{subscription_id:$SubscriptionId}",
    "avg:azure.kubernetes.node_cpu_usage{subscription_id:$SubscriptionId}"
  )
  foreach ($q in $candidates) {
    try {
      $uri = "$DdBase/api/v1/query?from=$from&to=$to&query=$([uri]::EscapeDataString($q))"
      $resp = Invoke-RestMethod -Uri $uri -Headers $DdHeaders -Method GET -ErrorAction Stop
      if ($resp.series -and $resp.series.Count -gt 0) {
        foreach ($s in $resp.series) {
          if ($s.pointlist -and $s.pointlist.Count -gt 0) { return $true }
        }
      }
    } catch { continue }
  }
  return $false
}

# Discovery helpers
function Get-Subs       { az account list --query "[].{id:id,name:name}" -o json | ConvertFrom-Json }
function Get-VMs        { az vm list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Apps       { az webapp list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Sql        { az sql db list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Stg        { az storage account list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Aks        { az aks list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Kv         { az keyvault list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-AppGw      { az network application-gateway list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-ADF        { az datafactory factory list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Cosmos     { az cosmosdb list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-EventHubNS { az eventhubs namespace list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-APIM       { az apim list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-Redis      { az redis list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }
function Get-LogicApps  { az logic workflow list --query "[].{id:id,name:name,rg:resourceGroup}" -o json | ConvertFrom-Json }

$rows = New-Object System.Collections.Generic.List[Object]

function Get-ServicePrincipalsExpiration {
  try {
    $apps = az ad app list --all -o json | ConvertFrom-Json
  } catch { Warn "Unable to list AAD apps/service principals (permission required). Skipping."; return @() }
  $report = @()
  foreach ($a in $apps) {
    $creds = @()
    try { $creds = az ad app credential list --id $a.appId -o json | ConvertFrom-Json } catch { $creds = @() }
    foreach ($c in $creds) {
      if (-not $c.endDateTime) { continue }
      $exp = Get-Date $c.endDateTime
      $days = [int]([TimeSpan]::FromTicks(($exp - (Get-Date)).Ticks).TotalDays)
      $report += [pscustomobject]@{ AppName=$a.displayName; AppId=$a.appId; CredentialEnd=$exp; DaysToExpire=$days }
    }
  }
  return $report
}

$subs = Get-Subs
Info "Found $($subs.Count) subscription(s)."

foreach ($sub in $subs) {
  $sid=$sub.id; $sname=$sub.name

  $hasData = Test-SubscriptionMetrics -SubscriptionId $sid
  if (-not $hasData) {
    Warn "Skipping subscription '$sname' ($sid): No live Datadog Azure metrics detected in last 30 minutes. Enable Azure↔Datadog integration for this subscription to create monitors."
    continue
  }

  Write-Host "`n=== Subscription: $sname ($sid) ===" -ForegroundColor Green
  az account set --subscription $sid | Out-Null

# --- VMs ---
  foreach ($vm in (Get-VMs)) {
    $tags = @("subscription_id:$sid","subscription_name:$sname","resource_group:$($vm.rg)","resource_name:$($vm.name)","resource_id:$($vm.id)","type:vm")
    $n="VM status: $($vm.name) [$sname]"
    $q="min(last_5m):sum:azure.vm.count{subscription_id:$sid,resource_group:$($vm.rg),resource_name:$($vm.name),status:Running} < 1"
    $m="VM $($vm.name) not running or missing metrics.$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="VM";Resource=$vm.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="VM CPU high: $($vm.name) [$sname]"
    $q="avg(last_5m):avg:azure.vm.cpu_percent{subscription_id:$sid,resource_group:$($vm.rg),resource_name:$($vm.name)} > 85"
    $m="High CPU on VM $($vm.name) >85%.$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="VM";Resource=$vm.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- App Services ---
  foreach ($app in (Get-Apps)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($app.rg)","resource_name:$($app.name)","resource_id:$($app.id)","type:appservice")
    $n="AppService 5xx: $($app.name) [$sname]"
    $q="sum(last_5m):sum:azure.app_service.http5xx{subscription_id:$sid,resource_group:$($app.rg),resource_name:$($app.name)} > 5"
    $m="HTTP 5xx spike for AppService $($app.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AppService";Resource=$app.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="AppService CPU high: $($app.name) [$sname]"
    $q="avg(last_5m):avg:azure.app_service.cpu_percentage{subscription_id:$sid,resource_group:$($app.rg),resource_name:$($app.name)} > 80"
    $m="AppService CPU high $($app.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AppService";Resource=$app.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- SQL Databases ---
  foreach ($db in (Get-Sql)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($db.rg)","resource_name:$($db.name)","resource_id:$($db.id)","type:sqldb")
    $n="SQL CPU high: $($db.name) [$sname]"
    $q="avg(last_5m):avg:azure.sql.cpu_percent{subscription_id:$sid,resource_group:$($db.rg),resource_name:$($db.name)} > 80"
    $m="High CPU on SQL DB $($db.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="SQL";Resource=$db.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="SQL DTU high: $($db.name) [$sname]"
    $q="avg(last_5m):avg:azure.sql.dtu_used{subscription_id:$sid,resource_group:$($db.rg),resource_name:$($db.name)} > 80"
    $m="High DTU usage on SQL DB $($db.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="SQL";Resource=$db.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Storage Accounts ---
  foreach ($st in (Get-Stg)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($st.rg)","resource_name:$($st.name)","resource_id:$($st.id)","type:storage")
    $n="Storage availability low: $($st.name) [$sname]"
    $q="avg(last_5m):avg:azure.storage.availability{subscription_id:$sid,resource_group:$($st.rg),resource_name:$($st.name)} < 99"
    $m="Storage availability degraded for $($st.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="Storage";Resource=$st.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="Storage request spike: $($st.name) [$sname]"
    $q="sum(last_5m):sum:azure.storage.total_requests{subscription_id:$sid,resource_group:$($st.rg),resource_name:$($st.name)} > 100000"
    $m="High request volume on storage $($st.name) (possible throttling).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="Storage";Resource=$st.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- AKS ---
  foreach ($ak in (Get-Aks)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($ak.rg)","resource_name:$($ak.name)","resource_id:$($ak.id)","type:aks")
    $n="AKS node CPU high: $($ak.name) [$sname]"
    $q="avg(last_5m):avg:azure.kubernetes.node_cpu_usage{subscription_id:$sid,resource_group:$($ak.rg),resource_name:$($ak.name)} > 80"
    $m="AKS node CPU high on $($ak.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AKS";Resource=$ak.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="AKS node NotReady: $($ak.name) [$sname]"
    $q="min(last_5m):sum:azure.kubernetes.count{subscription_id:$sid,resource_group:$($ak.rg),resource_name:$($ak.name),status:NotReady} > 0"
    $m="AKS node NotReady detected for $($ak.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AKS";Resource=$ak.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Key Vault ---
  foreach ($kv in (Get-Kv)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($kv.rg)","resource_name:$($kv.name)","resource_id:$($kv.id)","type:keyvault")
    $n="Key Vault availability low: $($kv.name) [$sname]"
    $q="avg(last_5m):avg:azure.key_vault.availability{subscription_id:$sid,resource_group:$($kv.rg),resource_name:$($kv.name)} < 99"
    $m="Key Vault availability degraded $($kv.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="KeyVault";Resource=$kv.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="Key Vault throttling/service hits: $($kv.name) [$sname]"
    $q="sum(last_5m):sum:azure.key_vault.service_api_hit{subscription_id:$sid,resource_group:$($kv.rg),resource_name:$($kv.name)} > 5000"
    $m="High Key Vault service API hits (possible throttling) on $($kv.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="KeyVault";Resource=$kv.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Application Gateway + WAF ---
  foreach ($ag in (Get-AppGw)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($ag.rg)","resource_name:$($ag.name)","resource_id:$($ag.id)","type:appgw")
    $n="App Gateway 5xx: $($ag.name) [$sname]"
    $q="sum(last_5m):sum:azure.application_gateway.response_status{subscription_id:$sid,resource_group:$($ag.rg),resource_name:$($ag.name),status:500} > 10"
    $m="HTTP 5xx spikes on Application Gateway $($ag.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AppGateway";Resource=$ag.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="App Gateway Unhealthy hosts: $($ag.name) [$sname]"
    $q="avg(last_5m):avg:azure.application_gateway.unhealthy_host_count{subscription_id:$sid,resource_group:$($ag.rg),resource_name:$($ag.name)} > 0"
    $m="Unhealthy backend hosts detected on Application Gateway $($ag.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AppGateway";Resource=$ag.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="App Gateway WAF blocked requests: $($ag.name) [$sname]"
    $q="sum(last_5m):sum:azure.application_gateway.waf_blocked_requests{subscription_id:$sid,resource_group:$($ag.rg),resource_name:$($ag.name)} > 100"
    $m="WAF blocked requests high on Application Gateway $($ag.name). Review rules.$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags ($tags + @("feature:waf"))) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="AppGatewayWAF";Resource=$ag.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Data Factory ---
  foreach ($df in (Get-ADF)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($df.rg)","resource_name:$($df.name)","resource_id:$($df.id)","type:datafactory")
    $n="ADF failed pipeline runs: $($df.name) [$sname]"
    $q="sum(last_15m):sum:azure.data_factory.pipeline_failed_runs{subscription_id:$sid,resource_group:$($df.rg),resource_name:$($df.name)} > 0"
    $m="Data Factory pipeline failures in $($df.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="DataFactory";Resource=$df.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Cosmos DB ---
  foreach ($cs in (Get-Cosmos)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($cs.rg)","resource_name:$($cs.name)","resource_id:$($cs.id)","type:cosmosdb")
    $n="CosmosDB throttled requests: $($cs.name) [$sname]"
    $q="sum(last_5m):sum:azure.cosmosdb.throttled_requests{subscription_id:$sid,resource_group:$($cs.rg),resource_name:$($cs.name)} > 0"
    $m="Cosmos DB throttling detected on $($cs.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="CosmosDB";Resource=$cs.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="CosmosDB total requests spike: $($cs.name) [$sname]"
    $q="sum(last_5m):sum:azure.cosmosdb.total_requests{subscription_id:$sid,resource_group:$($cs.rg),resource_name:$($cs.name)} > 100000"
    $m="High request volume on Cosmos DB $($cs.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="CosmosDB";Resource=$cs.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- Event Hub ---
  foreach ($eh in (Get-EventHubNS)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($eh.rg)","resource_name:$($eh.name)","resource_id:$($eh.id)","type:eventhub")
    $n="EventHub throttled requests: $($eh.name) [$sname]"
    $q="sum(last_5m):sum:azure.event_hub.throttled_requests{subscription_id:$sid,resource_group:$($eh.rg),resource_name:$($eh.name)} > 0"
    $m="Event Hub throttling detected on $($eh.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="EventHub";Resource=$eh.name;Monitor=$n;Id=$r.id;Query=$q}) }
    $n="EventHub incoming messages drop: $($eh.name) [$sname]"
    $q="avg(last_5m):avg:azure.event_hub.incoming_messages{subscription_id:$sid,resource_group:$($eh.rg),resource_name:$($eh.name)} < 1"
    $m="Incoming messages dropped to zero for Event Hub $($eh.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) { $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="EventHub";Resource=$eh.name;Monitor=$n;Id=$r.id;Query=$q}) }
  }

# --- API Management (APIM) ---
  foreach ($ap in (Get-APIM)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($ap.rg)","resource_name:$($ap.name)","resource_id:$($ap.id)","type:apim")
    $n="APIM 5xx: $($ap.name) [$sname]"
    $q="sum(last_5m):sum:azure.api_management.gateway_5xx{subscription_id:$sid,resource_group:$($ap.rg),resource_name:$($ap.name)} > 10"
    $m="APIM 5xx errors spiking on $($ap.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) {$rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="APIM";Resource=$ap.name;Monitor=$n;Id=$r.id;Query=$q})}
    $n="APIM latency high: $($ap.name) [$sname]"
    $q="avg(last_5m):avg:azure.api_management.gateway_latency_ms{subscription_id:$sid,resource_group:$($ap.rg),resource_name:$($ap.name)} > 500"
    $m="APIM average latency > 500ms for $($ap.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) {$rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="APIM";Resource=$ap.name;Monitor=$n;Id=$r.id;Query=$q})}
  }

# --- Azure Cache for Redis ---
  foreach ($rd in (Get-Redis)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($rd.rg)","resource_name:$($rd.name)","resource_id:$($rd.id)","type:redis")
    $n="Redis server load high: $($rd.name) [$sname]"
    $q="avg(last_5m):avg:azure.redis.server_load{subscription_id:$sid,resource_group:$($rd.rg),resource_name:$($rd.name)} > 80"
    $m="Redis server load high on $($rd.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) {$rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="Redis";Resource=$rd.name;Monitor=$n;Id=$r.id;Query=$q})}
    $n="Redis evicted keys > 0: $($rd.name) [$sname]"
    $q="sum(last_5m):sum:azure.redis.evicted_keys{subscription_id:$sid,resource_group:$($rd.rg),resource_name:$($rd.name)} > 0"
    $m="Redis evictions occurring on $($rd.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) {$rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="Redis";Resource=$rd.name;Monitor=$n;Id=$r.id;Query=$q})}
  }

# --- Logic Apps ---
  foreach ($la in (Get-LogicApps)) {
    $tags=@("subscription_id:$sid","subscription_name:$sname","resource_group:$($la.rg)","resource_name:$($la.name)","resource_id:$($la.id)","type:logicapp")
    $n="Logic App run failures: $($la.name) [$sname]"
    $q="sum(last_15m):sum:azure.logic_apps.runs_failed{subscription_id:$sid,resource_group:$($la.rg),resource_name:$($la.name)} > 0"
    $m="Logic App failed runs detected on $($la.name).$NotifySuffix"
    if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags $tags) {$rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="LogicApp";Resource=$la.name;Monitor=$n;Id=$r.id;Query=$q})}
  }

  $n="Subscription resource failures: $sname"
  $q="sum(last_10m):sum:azure.*.count{subscription_id:$sid,status:Failed} > 0"
  $m="One or more resources are in FAILED state in subscription $sname ($sid).$NotifySuffix"
  if ($r=New-DdMonitor -Name $n -Query $q -Message $m -Tags @("subscription_id:$sid","subscription_name:$sname","type:subscription")) { 
    $rows.Add([pscustomobject]@{Subscription=$sname;ResourceType="Subscription";Resource=$sname;Monitor=$n;Id=$r.id;Query=$q}) 
  }
}

$spReport = Get-ServicePrincipalsExpiration
if ($spReport.Count -gt 0) {
  $soon = $spReport | Where-Object { $_.DaysToExpire -le 90 } | Sort-Object DaysToExpire
  if ($soon.Count -gt 0) {
    $lines = ($soon | Select-Object AppName,AppId,CredentialEnd,DaysToExpire |
      ForEach-Object { "* $($_.AppName) ($($_.AppId)) expires $($_.CredentialEnd) in $($_.DaysToExpire) days" }) -join "`n"
    Post-DdEvent -Title "Service Principal credentials expiring (<= 90 days)" -Text $lines -Tags @("type:serviceprincipal","category:expiration")
  }
}

$rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$summary = $rows | Group-Object Subscription,ResourceType | ForEach-Object {
  [pscustomobject]@{ Subscription=$_.Group[0].Subscription; ResourceType=$_.Group[0].ResourceType; Count=$_.Count }
}
$style = @"
<style>
body{font-family:Segoe UI,Roboto,Arial,sans-serif;font-size:14px;color:#222}
h1{font-size:20px}
table{border-collapse:collapse;width:100%;margin:10px 0}
th,td{border:1px solid #ddd;padding:6px;text-align:left}
th{background:#f3f4f6}
tr:nth-child(even){background:#fafafa}
code{background:#f6f8fa;padding:2px 4px;border-radius:4px}
.small{color:#666;font-size:12px}
</style>
"@
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("<html><head>$style</head><body>")
$null = $sb.AppendLine("<h1>Datadog Monitor Creation Report ($ts)</h1>")
$null = $sb.AppendLine("<p class='small'>Site: <code>$DatadogSite</code> | DryRun: <code>$($DryRun.IsPresent)</code></p>")

$null = $sb.AppendLine("<h2>Summary</h2><table><tr><th>Subscription</th><th>Resource Type</th><th>Created</th></tr>")
foreach ($g in $summary) { $null = $sb.AppendLine("<tr><td>$($g.Subscription)</td><td>$($g.ResourceType)</td><td>$($g.Count)</td></tr>") }
$null = $sb.AppendLine("</table>")

$null = $sb.AppendLine("<h2>Details</h2><table><tr><th>Subscription</th><th>Type</th><th>Resource</th><th>Monitor</th><th>ID</th><th>Query</th></tr>")
foreach ($r in $rows) {
  $null = $sb.AppendLine("<tr><td>$($r.Subscription)</td><td>$($r.ResourceType)</td><td>$($r.Resource)</td><td>$($r.Monitor)</td><td>$($r.Id)</td><td><code>$([System.Web.HttpUtility]::HtmlEncode($r.Query))</code></td></tr>")
}
$null = $sb.AppendLine("</table>")

if ($spReport.Count -gt 0) {
  $null = $sb.AppendLine("<h2>Service Principal Credential Expirations (top 50)</h2><table><tr><th>App</th><th>AppId</th><th>Expires</th><th>Days</th></tr>")
  foreach ($r in ($spReport | Sort-Object DaysToExpire | Select-Object -First 50)) {
    $null = $sb.AppendLine("<tr><td>$($r.AppName)</td><td>$($r.AppId)</td><td>$($r.CredentialEnd)</td><td>$($r.DaysToExpire)</td></tr>")
  }
  $null = $sb.AppendLine("</table>")
}

$null = $sb.AppendLine("</body></html>")
[System.IO.File]::WriteAllText($htmlPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

if ($EmailReportTo -and $SmtpServer -and $SmtpFrom) {
  if (-not $SmtpUser) { $SmtpUser = $SmtpFrom }
  $pwd = Read-Host -AsSecureString "SMTP password for $SmtpUser"
  $cred = New-Object System.Management.Automation.PSCredential($SmtpUser,$pwd)
  try {
    $subject = "[Datadog] Monitor creation report $ts"
    $body = Get-Content -Path $htmlPath -Raw
    Send-MailMessage -SmtpServer $SmtpServer -Port $SmtpPort -UseSsl -Credential $cred -From $SmtpFrom -To $EmailReportTo -Subject $subject -Body $body -BodyAsHtml -Attachments $csvPath,$htmlPath
    Info "Report emailed to $EmailReportTo"
  } catch { Warn "Email send failed: $($_.Exception.Message)" }
}

Info "CSV: $csvPath"
Info "HTML: $htmlPath"
Info "Log: $logPath"
Stop-Transcript | Out-Null
Write-Host "`nDone." -ForegroundColor Green
