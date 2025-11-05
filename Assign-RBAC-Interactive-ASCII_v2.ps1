#Requires -Version 5.1
<#
Assign-RBAC-Interactive-ASCII_v2.ps1
Purpose:
  - Interactive, ASCII-only script to assign Azure built-in roles to Entra ID groups.
  - Auto-discovers all enabled subscriptions across accessible tenants.
  - Lets you select target subscription(s), group(s), and role(s) to assign.
  - Sets tenant context to the FIRST chosen subscription before group lookup.
  - Idempotent: skips if the exact assignment already exists.
  - Scope: subscription-level by default.
  - Uses built-in -WhatIf (SupportsShouldProcess). No custom -WhatIf.
  - ASCII only. No Unicode. No backtick continuations.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Low")]
param()

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

function Resolve-GroupsInteractive {
  param([string]$TenantId)
  Out-Info ("Resolving groups in tenant: {0}" -f $TenantId)
  $namesRaw = Read-Host "Enter Entra ID group display name(s) (comma-separated), e.g. devops,sre"
  if([string]::IsNullOrWhiteSpace($namesRaw)){ throw "No groups provided." }
  $names = ($namesRaw -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  $unique = $names | Sort-Object -Unique

  $resolved = @()
  foreach($n in $unique){
    $exact = @()
    $candidates = @()
    try {
      $exact = Get-AzADGroup -DisplayName $n -ErrorAction SilentlyContinue
    } catch {}
    if(-not $exact){
      try {
        $candidates = Get-AzADGroup -SearchString $n -ErrorAction SilentlyContinue
      } catch {}
    } else {
      $candidates = $exact
    }
    if(-not $candidates -or $candidates.Count -eq 0){
      throw ("Group not found in this tenant: {0}" -f $n)
    }
    # Filter down to case-insensitive exact match if present; otherwise present choices
    $eq = $candidates | Where-Object { $_.DisplayName -ieq $n }
    if($eq -and $eq.Count -eq 1){
      $resolved += [pscustomobject]@{ Name=$eq[0].DisplayName; ObjectId=$eq[0].Id }
      continue
    }
    if($eq -and $eq.Count -gt 1){ $candidates = $eq }

    $list = @()
    foreach($g in $candidates){
      $list += ("{0}  ObjectId: {1}" -f $g.DisplayName, $g.Id)
    }
    Show-IndexedList -Items $list -Header ("Multiple groups matched '{0}'. Choose one or more:" -f $n)
    while($true){
      $pick = Read-Host "Enter index/indices for '{0}'" -f $n
      $idx = Parse-IndexSelection -Text $pick -Max $list.Count
      if($idx.Count -gt 0){
        foreach($j in $idx){
          $g = $candidates[$j]
          $resolved += [pscustomobject]@{ Name=$g.DisplayName; ObjectId=$g.Id }
        }
        break
      }
      Out-Err "Invalid selection. Try again."
    }
  }
  $resolved | Sort-Object ObjectId -Unique
}

function Get-BuiltInRoles {
  $defs = Get-AzRoleDefinition -ErrorAction Stop | Where-Object { -not $_.IsCustom }
  $defs | Sort-Object Name -Unique
}

function Choose-Roles {
  $defs = Get-BuiltInRoles
  $common = @(
    "Owner",
    "Contributor",
    "User Access Administrator",
    "Reader",
    "Virtual Machine Contributor",
    "Network Contributor",
    "Storage Account Contributor",
    "Storage Blob Data Contributor",
    "Key Vault Administrator",
    "Key Vault Secrets Officer",
    "AcrPush",
    "AcrPull",
    "Log Analytics Contributor",
    "Monitoring Contributor",
    "Security Admin"
  )
  $commonDefs = @()
  foreach($n in $common){
    $m = $defs | Where-Object { $_.Name -eq $n }
    if($m){ $commonDefs += $m }
  }
  $menu = @()
  foreach($d in $commonDefs){ $menu += $d.Name }
  Show-IndexedList -Items $menu -Header "Common roles:"
  Write-Host ""
  Out-Info "Select from common roles by index, OR type role names/keywords to search full built-in list."
  $ans = Read-Host "Enter indices (e.g., 2 or 1,3-5 or 2 1,3,5) OR enter role name keywords"
  $picked = @()
  $idx = Parse-IndexSelection -Text $ans -Max $menu.Count
  if($idx.Count -gt 0){
    foreach($j in $idx){ $picked += $commonDefs[$j] }
  } else {
    $terms = ($ans -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if($terms.Count -eq 0){
      throw "No roles selected."
    }
    foreach($t in $terms){
      $exact = $defs | Where-Object { $_.Name -ieq $t }
      if($exact){ $picked += $exact; continue }
      $sub = $defs | Where-Object { $_.Name -imatch [regex]::Escape($t) }
      if($sub){ $picked += $sub }
    }
    if($picked.Count -eq 0){ throw "No roles matched your input." }
    $picked = $picked | Sort-Object Name -Unique
  }
  $picked
}

function Ensure-RoleAssignment {
  param(
    [string]$SubscriptionId,
    [string]$TenantId,
    [string]$PrincipalObjectId,
    [string]$RoleName
  )
  $scope = "/subscriptions/$SubscriptionId"
  Set-AzContext -SubscriptionId $SubscriptionId -Tenant $TenantId -ErrorAction Stop | Out-Null

  $existing = @()
  try {
    $existing = Get-AzRoleAssignment -ObjectId $PrincipalObjectId -Scope $scope -ErrorAction SilentlyContinue |
                Where-Object { $_.RoleDefinitionName -eq $RoleName }
  } catch {
    $existing = @()
  }
  if($existing -and $existing.Count -gt 0){
    Out-Ok ("Already assigned: {0} -> {1}" -f $RoleName,$scope)
    return
  }

  $msg = ("Assign '{0}' at '{1}' to objectId '{2}'" -f $RoleName,$scope,$PrincipalObjectId)
  if($PSCmdlet.ShouldProcess($scope, $msg)){
    try {
      New-AzRoleAssignment -ObjectId $PrincipalObjectId -RoleDefinitionName $RoleName -Scope $scope -ErrorAction Stop | Out-Null
      Out-Ok ("Assigned: {0} -> {1}" -f $RoleName,$scope)
    } catch {
      if($_.Exception.Message -match "already exists" -or $_.Exception.Message -match "AssignmentExists"){
        Out-Ok ("Assignment already exists (server-side). Skipping: {0}" -f $scope)
      } else {
        Out-Err ("Failed to assign {0} at {1}: {2}" -f $RoleName,$scope,$_.Exception.Message)
        throw
      }
    }
  } else {
    if($WhatIfPreference){ Out-Info ("WHATIF: would assign {0} at {1}" -f $RoleName,$scope) }
  }
}

try {
  Out-Info "Starting interactive RBAC assignment..."
  Ensure-Modules
  Connect-Azure

  $targetSubs = Choose-Subscriptions
  Out-Ok ("Selected subscriptions: {0}" -f ($targetSubs | ForEach-Object { $_.Id } | Sort-Object | Out-String))

  # Set context to first selected subscription/tenant before group resolution
  $first = $targetSubs[0]
  Set-AzContext -SubscriptionId $first.Id -Tenant $first.TenantId -ErrorAction Stop | Out-Null
  Out-Info ("Group lookup will use tenant: {0}" -f $first.TenantId)

  $groups = Resolve-GroupsInteractive -TenantId $first.TenantId
  Out-Ok ("Target groups: {0}" -f ($groups | ForEach-Object { $_.Name } -join ", "))

  $roles = Choose-Roles
  Out-Ok ("Selected roles: {0}" -f ($roles | ForEach-Object { $_.Name } -join ", "))

  foreach($sub in $targetSubs){
    foreach($g in $groups){
      foreach($r in $roles){
        Ensure-RoleAssignment -SubscriptionId $sub.Id -TenantId $sub.TenantId -PrincipalObjectId $g.ObjectId -RoleName $r.Name
      }
    }
  }

  if($WhatIfPreference){
    Out-Warn "WHATIF run: No changes were made."
  } else {
    Out-Ok "Completed. No other role assignments were changed."
  }
  exit 0
}
catch {
  Out-Err ("FAILED: {0}" -f $_.Exception.Message)
  exit 1
}
