<#
SYNOPSIS
  Auto-detect Azure services already reporting to Datadog and create ONLY the relevant alerts.
  Routes ALL alerts to PagerDuty in addition to email (and Slack if added to -Notify).
  ASCII file. No Datadog CLI needed; REST API only. US3 default.
#>
[CmdletBinding()]
param(
  [ValidateSet('us','us3','us5','eu','gov')][string]$DatadogSite = 'us3',
  [switch]$SkipUpdates = $true,
  [switch]$AutoDiscover = $true,
  [string]$Notify = '@john.pinto@pyxhealth.com @anthoney.schlak@pyxhealth.com @shaun.raj@pyxhealth.com',
  [string]$PagerDutyService = '@pagerduty-pyxhealth-oncall'
)
if ([string]::IsNullOrWhiteSpace($PagerDutyService)) { $PagerDutyService = '@pagerduty-pyxhealth-oncall' }
if ($Notify -notmatch [regex]::Escape($PagerDutyService)) { $Notify = "$Notify $PagerDutyService" }

# Slack routing per environment (update these to match your Datadog Slack integration names)
$SlackProd    = '@slack-alerts-prod'
$SlackStaging = '@slack-alerts-stg'
$SlackQA      = '@slack-alerts-qa'
$SlackDev     = '@slack-alerts-dev'

$script:DD_APP = '195558c2-6170-4af6-ba4f-4267b05e4017'
$script:DD_API = '14fe5ae3-6459-40a4-8f3b-b3c8c97e520e'
function Get-DDSiteBase { param([string]$Site) switch ($Site) {'us'{'datadoghq.com'}'us3'{'us3.datadoghq.com'}'us5'{'us5.datadoghq.com'}'eu'{'datadoghq.eu'}'gov'{'ddog-gov.com'} default{throw "Unsupported site:$Site"}}}
$global:DDBase = Get-DDSiteBase -Site $DatadogSite
function Invoke-DD { param([ValidateSet('GET','POST','PUT','DELETE')][string]$Method,[string]$Path,[object]$Body)$uri="https://api.$($global:DDBase)$Path";$h=@{'DD-API-KEY'=$script:DD_API;'DD-APPLICATION-KEY'=$script:DD_APP;'Content-Type'='application/json'};if($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body){$json=($Body|ConvertTo-Json -Depth 12 -Compress);return Invoke-RestMethod -Method $Method -Uri $uri -Headers $h -Body $json};return Invoke-RestMethod -Method $Method -Uri $uri -Headers $h}
function Find-MonitorByExactName{param([string]$Name)$e=[System.Web.HttpUtility]::UrlEncode($Name);$r=Invoke-DD -Method GET -Path "/api/v1/monitor/search?query=name%3A$e";if($r -and $r.count -gt 0){foreach($m in $r.monitors){if($m.name -eq $Name){return $m}}}$null}
function Ensure-Monitor{param([string]$Name,[object]$Payload,[switch]$NoUpdate)$ex=Find-MonitorByExactName -Name $Name;if($ex){if($NoUpdate){Write-Host "Exists, skipping: $Name";return $ex}else{return Invoke-DD -Method PUT -Path "/api/v1/monitor/$($ex.id)" -Body $Payload}};Invoke-DD -Method POST -Path "/api/v1/monitor/validate" -Body $Payload|Out-Null;Write-Host "Creating: $Name";Invoke-DD -Method POST -Path "/api/v1/monitor" -Body $Payload}
function New-MetricMonitorPayload{param([string]$Name,[string]$Query,[string]$Message,[string[]]$Tags,[hashtable]$Thresholds,[int]$Renotify,[int]$EvalDelay,[switch]$NotifyNoData,[int]$NoDataMinutes)$o=@{thresholds=$Thresholds;renotify_interval=$Renotify;evaluation_delay=$EvalDelay;include_tags=$true;notify_audit=$false;require_full_window=$true};if($NotifyNoData){$o.notify_no_data=$true;$o.no_data_timeframe=$NoDataMinutes};@{name=$Name;type='query alert';query=$Query;message=$Message;tags=$Tags;options=$o;priority=3}}
function New-LogAlertPayload{param([string]$Name,[string]$Query,[string]$Message,[string[]]$Tags,[hashtable]$Thresholds)@{name=$Name;type='log alert';query=$Query;message=$Message;tags=$Tags;options=@{thresholds=$Thresholds;renotify_interval=60;include_tags=$true;require_full_window=$true};priority=3}}
function New-ServiceCheckPayload{param([string]$Name,[string]$Check,[string]$Query,[string]$Message,[string[]]$Tags)@{name=$Name;type='service check';query=$Query;message=$Message;tags=$Tags;options=@{renotify_interval=60;include_tags=$true;notify_audit=$false;require_full_window=$true};priority=2}}
function Set-Tag{param([string]$K,[string]$V)if([string]::IsNullOrWhiteSpace($V)){''}else{"$K`:$V"}}
function Infer-Env{param([string]$n)$n=$n.ToLowerInvariant();if($n -match 'prod'){'prod'}elseif($n -match 'stag|stage'){'staging'}elseif($n -match 'qa'){'qa'}elseif($n -match 'test'){'test'}else{'dev'}}
function Get-ActiveMetricsForScope{param([string]$SubscriptionId,[int]$FromUnix)$p="/api/v1/metrics?from=$FromUnix&tag_filter=subscription:$SubscriptionId";try{Invoke-DD -Method GET -Path $p}catch{$null}}
if(-not (Get-Module -ListAvailable -Name Az.Accounts)){Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber};Import-Module Az.Accounts;try{Connect-AzAccount -WarningAction SilentlyContinue|Out-Null}catch{}
$az=Get-AzSubscription;if(-not $az -or $az.Count -eq 0){Write-Error "No Azure subscriptions found.";exit 3}
$TagKeys=@{EnvKey='env';SubscriptionKey='subscription'};$Def=@{Cpu=85;Mem=85;Disk=85;NoData=15;Err=50;Re=60;Ev=120}
$from=[int][double]::Parse((Get-Date -Date ((Get-Date).AddHours(-24)).ToUniversalTime() -UFormat %s))
$created=@();foreach($s in $az){$name=$s.Name;$id=$s.Id;$env=(Infer-Env $name)
  # Append Slack handle based on environment
  switch ($env) {
    'prod'    { if ($Notify -notmatch [regex]::Escape($SlackProd))    { $Notify = "$Notify $SlackProd" } }
    'staging' { if ($Notify -notmatch [regex]::Escape($SlackStaging)) { $Notify = "$Notify $SlackStaging" } }
    'qa'      { if ($Notify -notmatch [regex]::Escape($SlackQA))      { $Notify = "$Notify $SlackQA" } }
    default   { if ($Notify -notmatch [regex]::Escape($SlackDev))     { $Notify = "$Notify $SlackDev" } }
  };$envTag=Set-Tag -K $TagKeys.EnvKey -V $env;$subTag=Set-Tag -K $TagKeys.SubscriptionKey -V $id;$tags=@('managed_by:auto','stack:azure',$envTag,$subTag)
$act=Get-ActiveMetricsForScope -SubscriptionId $id -FromUnix $from;$m=@();if($act -and $act.metrics){$m=$act.metrics}
if($m -match 'system\.cpu\.idle'){$q="avg(last_5m):(100 - avg:system.cpu.idle{$envTag,$subTag} by {host}) > $($Def.Cpu)";$p=New-MetricMonitorPayload -Name "[$env][$name] CPU > $($Def.Cpu)% (per host)" -Query $q -Message "High CPU on {{host.name}} in $name/$env. $Notify" -Tags $tags -Thresholds @{critical=$Def.Cpu} -Renotify $Def.Re -EvalDelay $Def.Ev;$created+=Ensure-Monitor -Name $p.name -Payload $p -NoUpdate:$SkipUpdates}
if($m -match 'system\.mem\.pct_usable'){$q="avg(last_5m):((1 - avg:system.mem.pct_usable{$envTag,$subTag} by {host}) * 100) > $($Def.Mem)";$p=New-MetricMonitorPayload -Name "[$env][$name] Memory > $($Def.Mem)% (per host)" -Query $q -Message "High Mem on {{host.name}} in $name/$env. $Notify" -Tags $tags -Thresholds @{critical=$Def.Mem} -Renotify $Def.Re -EvalDelay $Def.Ev;$created+=Ensure-Monitor -Name $p.name -Payload $p -NoUpdate:$SkipUpdates}
if($m -match 'system\.disk\.in_use'){$crit=[Math]::Round($Def.Disk/100,2);$q="avg(last_5m):avg:system.disk.in_use{$envTag,$subTag,device:!tmpfs,device:!overlay} by {host,device} > $crit";$p=New-MetricMonitorPayload -Name "[$env][$name] Disk > $($Def.Disk)% (per device)" -Query $q -Message "High disk on {{host.name}} {{device.name}} in $name/$env. $Notify" -Tags $tags -Thresholds @{critical=$crit} -Renotify $Def.Re -EvalDelay $Def.Ev;$created+=Ensure-Monitor -Name $p.name -Payload $p -NoUpdate:$SkipUpdates}
$svc='"datadog.agent.up".over("'+$envTag+'","'+$subTag+'").by("host").last('+$Def.NoData+'m) == "0"';$pp=New-ServiceCheckPayload -Name "[$env][$name] Datadog Agent heartbeat missing ("+$Def.NoData+" m)" -Check 'datadog.agent.up' -Query $svc -Message "No agent heartbeat from {{host.name}} in $name/$env. $Notify" -Tags $tags;$created+=Ensure-Monitor -Name $pp.name -Payload $pp -NoUpdate:$SkipUpdates
$err='logs("status:error '+$envTag+' '+$subTag+'").index("*").rollup("count").last("5m") > '+$Def.Err;$pe=New-LogAlertPayload -Name "[$env][$name] Error logs > $($Def.Err) in 5m" -Query $err -Message "High error log volume in $name/$env. $Notify" -Tags $tags -Thresholds @{critical=$Def.Err};$created+=Ensure-Monitor -Name $pe.name -Payload $pe -NoUpdate:$SkipUpdates}
Write-Host ("Monitors created/seen: {0}" -f $created.Count)
