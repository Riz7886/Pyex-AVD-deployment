#Requires -Version 5.1
<#
Fix-Terraform-RP-Registration-ASCII.ps1
Purpose:
  - Fix Terraform "insufficient permissions to register resource providers" issues.
  - Lets you select one or more subscriptions (across all tenants).
  - Registers either a COMMON set of providers or ALL available providers for the subscription(s).
  - Verifies registration status and retries until confirmed or timeout.
  - ASCII only. No Unicode. No backtick continuations.
  - Uses built-in -WhatIf (SupportsShouldProcess). No custom -WhatIf.

Quick Start:
  .\Fix-Terraform-RP-Registration-ASCII.ps1
  .\Fix-Terraform-RP-Registration-ASCII.ps1 -WhatIf

Notes:
  - You typically need Contributor or Owner on the subscription to register providers.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Low")]
param(
  [ValidateSet("Common","All")]
  [string]$Mode = "Common",
  [int]$ConfirmTimeoutSec = 120
)

$ErrorActionPreference = "Stop"

function Out-Info { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Cyan }
function Out-Ok   { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Green }
function Out-Warn { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Yellow }
function Out-Err  { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Red }

function Ensure-Modules {
  try {
    $pg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if($pg -and $pg.InstallationPolicy -ne "Trusted"){
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
    }
  } catch {}
  $mods = @("Az.Accounts","Az.Resources")
  foreach($m in $mods){
    if(!(Get-Module -ListAvailable -Name $m)){
      Out-Info ("Installing {0}..." -f $m)
      Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
    }
    Import-Module $m -ErrorAction Stop | Out-Null
  }
  Out-Ok "Modules ready"
}

function Connect-Azure {
  $ctx = Get-AzContext -ErrorAction SilentlyContinue
  if($ctx -and $ctx.Account){
    Out-Ok ("Using existing context: {0}" -f $ctx.Account.Id)
    return
  }
  try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
    if($ctx -and $ctx.Account){
      Out-Ok ("Connected via Managed Identity: {0}" -f $ctx.Account.Id)
      return
    }
  } catch {}
  Connect-AzAccount -UseDeviceAuthentication:$true -ErrorAction Stop | Out-Null
  $ctx = Get-AzContext
  if(-not ($ctx -and $ctx.Account)){
    throw "Unable to obtain an Azure context."
  }
  Out-Ok ("Connected as: {0}" -f $ctx.Account.Id)
}

function Get-AllEnabledSubscriptions {
  $all = @()
  try {
    $tenants = Get-AzTenant -ErrorAction Stop
  } catch {
    $tenants = @()
  }
  if($tenants -and $tenants.Count -gt 0){
    foreach($t in $tenants){
      try {
        $subs = Get-AzSubscription -TenantId $t.TenantId -ErrorAction SilentlyContinue
        if($subs){ $all += ($subs | Where-Object { $_.State -eq "Enabled" }) }
      } catch {}
    }
  }
  if(-not $all -or $all.Count -eq 0){
    $all = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
  }
  if(-not $all -or $all.Count -eq 0){
    throw "No enabled subscriptions found."
  }
  $all | Sort-Object -Property Id -Unique
}

function Show-IndexedList {
  param([array]$Items,[string]$Header)
  if($Header){ Out-Info $Header }
  for($i=0; $i -lt $Items.Count; $i++){
    $idx = $i + 1
    Write-Host ("[{0}] {1}" -f $idx, $Items[$i])
  }
}

function Parse-IndexSelection {
  param([string]$Text,[int]$Max)
  if([string]::IsNullOrWhiteSpace($Text)){ return @() }
  $norm = $Text.Trim()
  if($norm -match '^(all|\*|everything)$'){ return @(for($i=0;$i -lt $Max;$i++){$i}) }
  $norm = ($norm -replace '[^0-9,\-\s;\|]', '')
  $norm = ($norm -replace '[\s;\|]+', ',')
  $norm = ($norm -replace ',{2,}', ',').Trim(',')
  if([string]::IsNullOrWhiteSpace($norm)){ return @() }
  $parts = $norm -split ','
  $idxs = New-Object System.Collections.Generic.List[int]
  foreach($p in $parts){
    if($p -match '^\d+$'){
      $v = [int]$p
      if($v -ge 1 -and $v -le $Max){ [void]$idxs.Add($v-1) }
    } elseif($p -match '^\d+-\d+$'){
      $a,$b = $p -split '-'
      $a=[int]$a; $b=[int]$b
      if($a -gt $b){ $tmp=$a; $a=$b; $b=$tmp }
      for($z=$a; $z -le $b; $z++){ if($z -ge 1 -and $z -le $Max){ [void]$idxs.Add($z-1) } }
    }
  }
  $idxs.ToArray() | Sort-Object -Unique
}

function Choose-Subscriptions {
  $subs = Get-AllEnabledSubscriptions
  $display = @()
  foreach($s in $subs){
    $display += ("{0}  ({1})  Tenant: {2}" -f $s.Name,$s.Id,$s.TenantId)
  }
  Show-IndexedList -Items $display -Header "Enabled subscriptions across ALL tenants:"
  Out-Ok ("Total enabled subscriptions: {0}" -f $subs.Count)
  while($true){
    $ans = Read-Host "Enter index/indices (2 OR 1,3-5 OR 2 1,3,5 OR ALL). Enter to select ALL"
    if([string]::IsNullOrWhiteSpace($ans)){ return ,$subs }
    $idx = Parse-IndexSelection -Text $ans -Max $subs.Count
    if($idx.Count -gt 0){
      $chosen = foreach($j in $idx){ $subs[$j] }
      return ,$chosen
    }
    Out-Err "Invalid selection. Try again."
  }
}

function Get-CommonProviders {
  @(
    "Microsoft.Resources",
    "Microsoft.Authorization",
    "Microsoft.Features",
    "Microsoft.Subscriptions",
    "Microsoft.PolicyInsights",
    "Microsoft.Network",
    "Microsoft.Compute",
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.ContainerService",
    "Microsoft.ContainerRegistry",
    "Microsoft.OperationalInsights",
    "Microsoft.Insights",
    "Microsoft.Monitor",
    "Microsoft.Web",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.DBforMySQL",
    "Microsoft.Sql",
    "Microsoft.DocumentDB",
    "Microsoft.EventHub",
    "Microsoft.ServiceBus",
    "Microsoft.App",
    "Microsoft.Kubernetes",
    "Microsoft.KubernetesConfiguration"
  )
}

function Register-ProvidersForSubscription {
  param(
    [string]$SubscriptionId,
    [string]$TenantId,
    [ValidateSet("Common","All")]
    [string]$Mode,
    [int]$ConfirmTimeoutSec
  )

  Set-AzContext -SubscriptionId $SubscriptionId -Tenant $TenantId -ErrorAction Stop | Out-Null
  Out-Info ("Registering providers in subscription {0}" -f $SubscriptionId)

  $targetProviders = @()
  if($Mode -eq "All"){
    $all = Get-AzResourceProvider -ErrorAction Stop
    if(-not $all){ throw "Unable to list providers." }
    $targetProviders = $all.ProviderNamespace
  } else {
    $targetProviders = Get-CommonProviders
  }

  $targetProviders = $targetProviders | Sort-Object -Unique

  foreach($ns in $targetProviders){
    try {
      $rp = Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction SilentlyContinue
      $state = $null
      if($rp){ $state = $rp.RegistrationState }
      if($state -and $state -eq "Registered"){
        Out-Ok ("Already registered: {0}" -f $ns)
        continue
      }

      $msg = ("Register provider: {0}" -f $ns)
      if($PSCmdlet.ShouldProcess($ns, $msg)){
        try {
          Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
          Out-Info ("Requested registration: {0}" -f $ns)
        } catch {
          Out-Err ("Failed to register {0}: {1}" -f $ns, $_.Exception.Message)
          continue
        }

        # Confirm registration
        $deadline = (Get-Date).AddSeconds($ConfirmTimeoutSec)
        while((Get-Date) -lt $deadline){
          Start-Sleep -Seconds 3
          $rp2 = Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction SilentlyContinue
          if($rp2 -and $rp2.RegistrationState -eq "Registered"){
            Out-Ok ("Confirmed: {0} -> Registered" -f $ns)
            break
          }
        }
        if(-not ($rp2 -and $rp2.RegistrationState -eq "Registered")){
          Out-Warn ("Timed out confirming {0}. It may complete shortly; re-run to verify." -f $ns)
        }
      } else {
        if($WhatIfPreference){ Out-Info ("WHATIF: would register provider {0}" -f $ns) }
      }
    } catch {
      Out-Err ("Error handling {0}: {1}" -f $ns, $_.Exception.Message)
    }
  }
}

try {
  Out-Info "Starting Resource Provider registration fixer..."
  Ensure-Modules
  Connect-Azure

  $subs = Choose-Subscriptions
  Out-Ok ("Selected subscriptions: {0}" -f ($subs | ForEach-Object { $_.Id } | Sort-Object | Out-String))

  Out-Info ("Mode: {0}" -f $Mode)
  foreach($s in $subs){
    Register-ProvidersForSubscription -SubscriptionId $s.Id -TenantId $s.TenantId -Mode $Mode -ConfirmTimeoutSec $ConfirmTimeoutSec
  }

  if($WhatIfPreference){
    Out-Warn "WHATIF run: No changes were made."
  } else {
    Out-Ok "Completed Resource Provider registration checks."
  }
  exit 0
}
catch {
  Out-Err ("FAILED: {0}" -f $_.Exception.Message)
  exit 1
}
