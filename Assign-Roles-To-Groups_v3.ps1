<# 
 File: Assign-Roles-To-Groups_v3.ps1
 Purpose:
   Interactive, ASCII-only script to assign Azure RBAC roles (built-in or custom)
   to Azure AD groups or users. Fixes "no groups found" by adding Microsoft Graph
   fallback search using the Azure token from Connect-AzAccount.

 Highlights:
   - Robust group search: tries Get-AzADGroup first; if empty, uses Graph REST.
   - Works with partial names and lists top results with paging.
   - Lets you paste Object IDs directly if you already know them.
   - Allows role bundles (DevOps Essentials) or manual multi-select of any role.
   - Idempotent: skips existing assignments.
   - Supports scopes: Mgmt Group, Subscription, RG, or Resource.
   - Optional -WhatIf.

 Usage:
   .\Assign-Roles-To-Groups_v3.ps1
   .\Assign-Roles-To-Groups_v3.ps1 -WhatIf

 Requirements:
   - PowerShell 5.1+ (or 7.x)
   - Az.Accounts, Az.Resources
   - Directory read + role assignment permissions at chosen scope
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$WhatIf
)

# ---------------------------- Helpers ----------------------------

function Ensure-AzModules {
  $mods = @("Az.Accounts","Az.Resources")
  foreach ($m in $mods) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
      Write-Host "Installing module $m ..."
      try {
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      } catch {
        Write-Error "Failed to install module $m. $_"
        exit 1
      }
    }
  }
  foreach ($m in $mods) { Import-Module $m -ErrorAction Stop }
}

function Connect-IfNeeded {
  try {
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
      Write-Host "Connecting to Azure..."
      Connect-AzAccount -ErrorAction Stop | Out-Null
    }
  } catch {
    Write-Error "Failed to connect to Azure. $_"
    exit 1
  }
}

function Select-SubscriptionInteractive {
  $subs = Get-AzSubscription | Sort-Object Name
  if (-not $subs) { Write-Error "No subscriptions found for the signed-in account."; exit 1 }

  Write-Host ""
  Write-Host "Available Subscriptions:"
  for ($i=0; $i -lt $subs.Count; $i++) {
    $s = $subs[$i]
    Write-Host ("[{0}] {1}  ({2})" -f ($i+1), $s.Name, $s.Id)
  }

  $choice = Read-Host "Enter number of subscription to use"
  if (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $subs.Count) {
    Write-Error "Invalid selection."; exit 1
  }

  $selected = $subs[$choice-1]
  Set-AzContext -SubscriptionId $selected.Id -ErrorAction Stop | Out-Null
  Write-Host ("Selected subscription: {0} ({1})" -f $selected.Name, $selected.Id)
  return $selected
}

function Select-Scope {
  Write-Host ""
  Write-Host "Choose scope type:"
  Write-Host "[1] Management Group"
  Write-Host "[2] Subscription"
  Write-Host "[3] Resource Group"
  Write-Host "[4] Resource (enter full resource ID)"
  $choice = Read-Host "Enter 1-4"

  switch ($choice) {
    "1" {
      $mgId = Read-Host "Enter Management Group ID"
      if ([string]::IsNullOrWhiteSpace($mgId)) { Write-Error "Management Group ID is required."; exit 1 }
      $scope = "/providers/Microsoft.Management/managementGroups/$mgId"
    }
    "2" {
      $sub = (Get-AzContext).Subscription
      if (-not $sub) { Write-Error "No active subscription context."; exit 1 }
      $scope = "/subscriptions/$($sub.Id)"
    }
    "3" {
      $rgs = Get-AzResourceGroup | Sort-Object ResourceGroupName
      if (-not $rgs) { Write-Error "No resource groups found in this subscription."; exit 1 }
      Write-Host ""
      Write-Host "Resource Groups:"
      for ($i=0; $i -lt $rgs.Count; $i++) {
        $rg = $rgs[$i]
        Write-Host ("[{0}] {1}" -f ($i+1), $rg.ResourceGroupName)
      }
      $idx = Read-Host "Enter number of Resource Group"
      if (-not ($idx -as [int]) -or $idx -lt 1 -or $idx -gt $rgs.Count) { Write-Error "Invalid selection."; exit 1 }
      $rgName = $rgs[$idx-1].ResourceGroupName
      $scope = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$rgName"
    }
    "4" {
      $resId = Read-Host "Paste full Resource ID"
      if (-not $resId.StartsWith("/")) { Write-Error "Invalid Resource ID."; exit 1 }
      $scope = $resId
    }
    default { Write-Error "Invalid selection."; exit 1 }
  }

  Write-Host ("Scope set to: {0}" -f $scope)
  return $scope
}

# Role selection: allow bundles or manual multi-pick.
function Select-Roles {
  Write-Host ""
  Write-Host "Choose role selection mode:"
  Write-Host "[1] DevOps Essentials bundle (Contributor + User Access Administrator)"
  Write-Host "[2] Manual multi-select from ALL roles (built-in and custom)"
  $mode = Read-Host "Enter 1 or 2"

  if ($mode -eq "1") {
    $bundle = @("Contributor","User Access Administrator")
    $defs = @()
    foreach ($b in $bundle) {
      $rd = Get-AzRoleDefinition -Name $b -ErrorAction SilentlyContinue
      if ($rd) { $defs += $rd }
    }
    if (-not $defs) { Write-Error "Could not resolve bundle roles."; exit 1 }
    Write-Host ("Selected roles: {0}" -f ($defs | ForEach-Object Name -join ", "))
    return $defs
  }

  $all = Get-AzRoleDefinition | Sort-Object Name
  if (-not $all) { Write-Error "No role definitions found."; exit 1 }

  # Optional text filter to reduce list
  $filter = Read-Host "Optional: type part of role name to filter (Enter to skip)"
  if ($filter) {
    $all = $all | Where-Object { $_.Name -like "*$filter*" }
  }
  if (-not $all) { Write-Error "No roles match your filter."; exit 1 }

  Write-Host ""
  Write-Host "Available Roles:"
  for ($i=0; $i -lt $all.Count; $i++) {
    $r = $all[$i]
    $tag = if ($r.IsCustom) { "Custom" } else { "BuiltIn" }
    Write-Host ("[{0}] {1}  ({2})" -f ($i+1), $r.Name, $tag)
  }

  Write-Host "You can select multiple. Example: 1,3,7"
  $sel = Read-Host "Enter role numbers"
  $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
  if (-not $nums) { Write-Error "No valid selection."; exit 1 }

  $picked = @()
  foreach ($n in $nums) {
    $idx = [int]$n
    if ($idx -lt 1 -or $idx -gt $all.Count) { Write-Error "Invalid role number: $n"; exit 1 }
    $picked += $all[$idx-1]
  }

  Write-Host ("Selected roles: {0}" -f ($picked | ForEach-Object Name -join ", "))
  return $picked
}

# -------- Robust Group/User search with Graph fallback --------

function Get-GraphToken {
  try {
    $tok = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop
    return $tok.Token
  } catch {
    return $null
  }
}

function Graph-Get {
  param([string]$Url)
  $t = Get-GraphToken
  if (-not $t) { return $null }
  $headers = @{ Authorization = "Bearer $t"; ConsistencyLevel = "eventual" }
  try {
    $resp = Invoke-RestMethod -Method Get -Uri $Url -Headers $headers -ErrorAction Stop
    return $resp
  } catch { return $null }
}

function Search-Groups {
  param([string]$Query, [int]$Top = 200)

  # Try Az first (DisplayName exact or startswith + paging)
  $results = @()
  try {
    if ([string]::IsNullOrWhiteSpace($Query)) {
      $batch = Get-AzADGroup -First $Top -ErrorAction SilentlyContinue
      if ($batch) { $results += $batch }
    } else {
      $tryExact = Get-AzADGroup -DisplayName $Query -First $Top -ErrorAction SilentlyContinue
      if ($tryExact) { $results += $tryExact }
      $tryStarts = Get-AzADGroup -Filter "startswith(DisplayName,'$Query')" -First $Top -ErrorAction SilentlyContinue
      if ($tryStarts) { $results += $tryStarts }
      # As a last resort, get first Top and do client-side contains
      if (-not $results) {
        $batch = Get-AzADGroup -First $Top -ErrorAction SilentlyContinue
        if ($batch) { $results += ($batch | Where-Object { $_.DisplayName -like "*$Query*" }) }
      }
    }
  } catch {}

  $results = $results | Sort-Object Id -Unique

  if ($results -and $results.Count -gt 0) { return $results }

  # Graph fallback (v1.0)
  $encoded = [System.Web.HttpUtility]::UrlEncode($Query)
  $url = if ([string]::IsNullOrWhiteSpace($Query)) {
    "https://graph.microsoft.com/v1.0/groups?$top=$Top"
  } else {
    # Use contains on displayName; requires $count with header ConsistencyLevel eventual
    "https://graph.microsoft.com/v1.0/groups?$count=true&$top=$Top&$filter=contains(displayName,'$encoded')"
  }

  $resp = Graph-Get -Url $url
  if ($resp -and $resp.value) {
    # Map to objects similar to Get-AzADGroup
    $mapped = @()
    foreach ($g in $resp.value) {
      $mapped += [PSCustomObject]@{
        Id = $g.id
        DisplayName = $g.displayName
        Mail = $g.mail
      }
    }
    return ($mapped | Sort-Object Id -Unique)
  }

  return @()
}

function Search-Users {
  param([string]$Query, [int]$Top = 100)
  $users = @()

  try {
    if ([string]::IsNullOrWhiteSpace($Query)) {
      $u = Get-AzADUser -First $Top -ErrorAction SilentlyContinue
      if ($u) { $users += $u }
    } else {
      $u1 = Get-AzADUser -UserPrincipalName $Query -ErrorAction SilentlyContinue
      if ($u1) { $users += $u1 }
      $u2 = Get-AzADUser -DisplayName $Query -First $Top -ErrorAction SilentlyContinue
      if ($u2) { $users += $u2 }
      if (-not $users) {
        $u3 = Get-AzADUser -Filter "startswith(DisplayName,'$Query')" -First $Top -ErrorAction SilentlyContinue
        if ($u3) { $users += $u3 }
      }
    }
  } catch {}

  $users = $users | Sort-Object Id -Unique
  if ($users -and $users.Count -gt 0) { return $users }

  # Graph fallback
  $encoded = [System.Web.HttpUtility]::UrlEncode($Query)
  $url = if ([string]::IsNullOrWhiteSpace($Query)) {
    "https://graph.microsoft.com/v1.0/users?$top=$Top"
  } else {
    "https://graph.microsoft.com/v1.0/users?$count=true&$top=$Top&$filter=contains(displayName,'$encoded')"
  }
  $resp = Graph-Get -Url $url
  if ($resp -and $resp.value) {
    $mapped = @()
    foreach ($u in $resp.value) {
      $mapped += [PSCustomObject]@{
        Id = $u.id
        DisplayName = $u.displayName
        UserPrincipalName = $u.userPrincipalName
      }
    }
    return ($mapped | Sort-Object Id -Unique)
  }

  return @()
}

function Select-Principals {
  Write-Host ""
  Write-Host "Assign to which principal type?"
  Write-Host "[1] Azure AD Group(s)"
  Write-Host "[2] Azure AD User(s)"
  Write-Host "[3] Paste ObjectId(s) directly"
  $choice = Read-Host "Enter 1-3"

  $principals = @()

  switch ($choice) {
    "1" {
      $query = Read-Host "Enter part of Group display name to search (Enter for top results)"
      $groups = Search-Groups -Query $query -Top 200
      if (-not $groups -or $groups.Count -eq 0) {
        Write-Warning "No groups found. If this tenant restricts directory read, paste ObjectIds instead."
        return Select-Principals
      }
      Write-Host ""
      Write-Host "Groups:"
      for ($i=0; $i -lt $groups.Count; $i++) {
        $g = $groups[$i]
        Write-Host ("[{0}] {1}  (ObjectId: {2})" -f ($i+1), $g.DisplayName, $g.Id)
      }
      Write-Host "You can select multiple. Example: 1,2,10"
      $sel = Read-Host "Enter group numbers"
      $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
      if (-not $nums) { Write-Error "No valid selection."; exit 1 }
      foreach ($n in $nums) {
        $idx = [int]$n
        if ($idx -lt 1 -or $idx -gt $groups.Count) { Write-Error "Invalid group number: $n"; exit 1 }
        $principals += [PSCustomObject]@{ Type="Group"; Name=$groups[$idx-1].DisplayName; ObjectId=$groups[$idx-1].Id }
      }
    }
    "2" {
      $query = Read-Host "Enter part of User display name or UPN to search"
      if ([string]::IsNullOrWhiteSpace($query)) { Write-Error "User search query is required."; exit 1 }
      $users = Search-Users -Query $query -Top 200
      if (-not $users) { Write-Error "No users found."; exit 1 }
      Write-Host ""
      Write-Host "Users:"
      for ($i=0; $i -lt $users.Count; $i++) {
        $u = $users[$i]
        Write-Host ("[{0}] {1}  UPN:{2}  (ObjectId: {3})" -f ($i+1), $u.DisplayName, $u.UserPrincipalName, $u.Id)
      }
      Write-Host "You can select multiple. Example: 1,4"
      $sel = Read-Host "Enter user numbers"
      $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
      if (-not $nums) { Write-Error "No valid selection."; exit 1 }
      foreach ($n in $nums) {
        $idx = [int]$n
        if ($idx -lt 1 -or $idx -gt $users.Count) { Write-Error "Invalid user number: $n"; exit 1 }
        $principals += [PSCustomObject]@{ Type="User"; Name=$users[$idx-1].DisplayName; ObjectId=$users[$idx-1].Id }
      }
    }
    "3" {
      $ids = Read-Host "Paste one or more ObjectIds (comma-separated)"
      $arr = $ids -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[0-9a-fA-F-]{36}$" }
      if (-not $arr) { Write-Error "No valid ObjectIds provided."; exit 1 }
      foreach ($oid in $arr) { $principals += [PSCustomObject]@{ Type="Unknown"; Name=$oid; ObjectId=$oid } }
    }
    default { Write-Error "Invalid selection."; exit 1 }
  }

  Write-Host ("Selected principals: {0}" -f ($principals | ForEach-Object { $_.Name } -join ", "))
  return $principals
}

function Ensure-Assignment {
  param(
    [Parameter(Mandatory=$true)] [string]$Scope,
    [Parameter(Mandatory=$true)] [string]$ObjectId,
    [Parameter(Mandatory=$true)] [string]$RoleName,
    [switch]$WhatIf
  )

  $existing = Get-AzRoleAssignment -Scope $Scope -ObjectId $ObjectId -RoleDefinitionName $RoleName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host ("SKIP: Role '{0}' already assigned at scope '{1}' to object '{2}'." -f $RoleName, $Scope, $ObjectId)
    return
  }

  $msg = "Assign role '{0}' at scope '{1}' to object '{2}'" -f $RoleName, $Scope, $ObjectId
  if ($PSCmdlet.ShouldProcess($msg)) {
    try {
      if ($WhatIf) {
        New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -WhatIf -ErrorAction Stop | Out-Null
        Write-Host ("WHATIF: {0}" -f $msg)
      } else {
        New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
        Write-Host ("OK: {0}" -f $msg)
      }
    } catch {
      Write-Warning ("FAILED: {0}. Error: {1}" -f $msg, $_.Exception.Message)
    }
  }
}

# ---------------------------- Main ----------------------------
try {
  Ensure-AzModules
  Connect-IfNeeded

  $sub = Select-SubscriptionInteractive
  $scope = Select-Scope
  $roles = Select-Roles
  $principals = Select-Principals

  Write-Host ""
  Write-Host "Summary:"
  Write-Host ("  Subscription: {0} ({1})" -f $sub.Name, $sub.Id)
  Write-Host ("  Scope: {0}" -f $scope)
  Write-Host ("  Roles: {0}" -f ($roles | ForEach-Object Name -join ", "))
  Write-Host ("  Principals: {0}" -f ($principals | ForEach-Object Name -join ", "))
  $confirm = Read-Host "Proceed with assignments? (Y/N)"
  if ($confirm -notin @("Y","y","Yes","yes")) { Write-Host "Aborted by user."; exit 0 }

  foreach ($p in $principals) {
    foreach ($r in $roles) {
      Ensure-Assignment -Scope $scope -ObjectId $p.ObjectId -RoleName $r.Name -WhatIf:$WhatIf
    }
  }

  Write-Host ""
  Write-Host "Done."
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
