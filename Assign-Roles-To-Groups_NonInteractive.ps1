# File: Assign-Roles-To-Groups_NonInteractive.ps1
# Purpose: ASCII-only, non-interactive script to assign Azure RBAC roles to AAD groups or users.
# Notes:
#   - No Unicode characters. Plain ASCII only.
#   - Idempotent: skips existing assignments.
#   - Uses Az cmdlets first; if group lookup returns nothing, falls back to Microsoft Graph REST using the Azure token.
#   - You can pass group ObjectIds directly or search by display name.
#   - Works for scopes: Management Group, Subscription, Resource Group, or full ResourceId.
#   - Tested on Windows PowerShell 5.1 and PowerShell 7.
#
# Example:
#   .\Assign-Roles-To-Groups_NonInteractive.ps1 -SubscriptionName "Sub-Production" -ScopeType Subscription `
#     -RoleNames "Contributor","User Access Administrator" -GroupNames "DevOps","Platform-DevOps"
#
#   .\Assign-Roles-To-Groups_NonInteractive.ps1 -SubscriptionId "da72e6ae-e86d-4dfd-a5fd-dd6b2c96ae05" -ScopeType ResourceGroup `
#     -ResourceGroupName "rg-apps-prod" -RoleNames "Contributor" -PrincipalObjectIds "00000000-0000-0000-0000-000000000000"
[CmdletBinding()]
param(
  [string]$SubscriptionId,
  [string]$SubscriptionName,
  [ValidateSet("ManagementGroup","Subscription","ResourceGroup","ResourceId")]
  [string]$ScopeType = "Subscription",
  [string]$ManagementGroupId,
  [string]$ResourceGroupName,
  [string]$ResourceId,
  [string[]]$RoleNames = @("Contributor","User Access Administrator"),
  [string[]]$GroupNames,            # display name search terms (exact or partial, multiple allowed)
  [string[]]$PrincipalObjectIds,    # if provided, used directly
  [switch]$WhatIf,
  [int]$GroupSearchTop = 200,
  [switch]$PickFirstOnMultiple      # if multiple results for a GroupName, pick first automatically
)

# ---------------- Helpers ----------------
function Ensure-AzModules {
  $mods = @("Az.Accounts","Az.Resources")
  foreach ($m in $mods) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
      try {
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop | Out-Null
      } catch {
        Write-Error "Failed to install module $m. $_"
        exit 1
      }
    }
  }
  foreach ($m in $mods) { Import-Module $m -ErrorAction Stop | Out-Null }
}

function Connect-IfNeeded {
  $ctx = Get-AzContext -ErrorAction SilentlyContinue
  if (-not $ctx) {
    try {
      Connect-AzAccount -ErrorAction Stop | Out-Null
    } catch {
      Write-Error "Connect-AzAccount failed. $_"
      exit 1
    }
  }
}

function Set-SubContext {
  if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
  } elseif ($SubscriptionName) {
    $s = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop
    Set-AzContext -SubscriptionId $s.Id -ErrorAction Stop | Out-Null
  } else {
    # keep current context
    $s = (Get-AzContext).Subscription
    if (-not $s) { Write-Error "No active subscription context. Provide -SubscriptionId or -SubscriptionName."; exit 1 }
  }
}

function Build-Scope {
  $sub = (Get-AzContext).Subscription
  switch ($ScopeType) {
    "ManagementGroup" {
      if (-not $ManagementGroupId) { Write-Error "ManagementGroupId is required for ScopeType=ManagementGroup."; exit 1 }
      return "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    }
    "Subscription" {
      return "/subscriptions/$($sub.Id)"
    }
    "ResourceGroup" {
      if (-not $ResourceGroupName) { Write-Error "ResourceGroupName is required for ScopeType=ResourceGroup."; exit 1 }
      return "/subscriptions/$($sub.Id)/resourceGroups/$ResourceGroupName"
    }
    "ResourceId" {
      if (-not $ResourceId -or -not $ResourceId.StartsWith("/")) { Write-Error "Valid ResourceId is required for ScopeType=ResourceId."; exit 1 }
      return $ResourceId
    }
  }
}

function Get-GraphToken {
  try {
    $tok = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop
    return $tok.Token
  } catch { return $null }
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
  $results = @()
  try {
    if ([string]::IsNullOrWhiteSpace($Query)) {
      $batch = Get-AzADGroup -First $Top -ErrorAction SilentlyContinue
      if ($batch) { $results += $batch }
    } else {
      # exact display name
      $g1 = Get-AzADGroup -DisplayName $Query -First $Top -ErrorAction SilentlyContinue
      if ($g1) { $results += $g1 }
      # startswith server-side
      $g2 = Get-AzADGroup -Filter ("startswith(DisplayName,'{0}')" -f $Query.Replace("'","''")) -First $Top -ErrorAction SilentlyContinue
      if ($g2) { $results += $g2 }
      if (-not $results) {
        $batch = Get-AzADGroup -First $Top -ErrorAction SilentlyContinue
        if ($batch) { $results += ($batch | Where-Object { $_.DisplayName -like ("*{0}*" -f $Query) }) }
      }
    }
  } catch {}
  $results = $results | Sort-Object Id -Unique
  if ($results -and $results.Count -gt 0) { return $results }

  # Graph fallback
  $enc = [System.Web.HttpUtility]::UrlEncode($Query)
  $url = if ([string]::IsNullOrWhiteSpace($Query)) {
    "https://graph.microsoft.com/v1.0/groups?$top=$Top"
  } else {
    "https://graph.microsoft.com/v1.0/groups?$count=true&$top=$Top&$filter=contains(displayName,'$enc')"
  }
  $resp = Graph-Get -Url $url
  if ($resp -and $resp.value) {
    $mapped = @()
    foreach ($g in $resp.value) {
      $mapped += [PSCustomObject]@{ Id = $g.id; DisplayName = $g.displayName; Mail = $g.mail }
    }
    return ($mapped | Sort-Object Id -Unique)
  }
  return @()
}

function Ensure-Assignment {
  param(
    [string]$Scope, [string]$ObjectId, [string]$RoleName, [switch]$WhatIf
  )
  $existing = Get-AzRoleAssignment -Scope $Scope -ObjectId $ObjectId -RoleDefinitionName $RoleName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host ("SKIP: {0} already has {1} at {2}" -f $ObjectId, $RoleName, $Scope)
    return
  }
  try {
    if ($WhatIf) {
      New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -WhatIf -ErrorAction Stop | Out-Null
      Write-Host ("WHATIF: Assign {0} -> {1} at {2}" -f $RoleName, $ObjectId, $Scope)
    } else {
      New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
      Write-Host ("OK: Assign {0} -> {1} at {2}" -f $RoleName, $ObjectId, $Scope)
    }
  } catch {
    Write-Warning ("FAILED: {0} -> {1} at {2}. {3}" -f $RoleName, $ObjectId, $Scope, $_.Exception.Message)
  }
}

# ---------------- Main ----------------
try {
  Ensure-AzModules
  Connect-IfNeeded
  Set-SubContext
  $scope = Build-Scope

  # Resolve principals
  $principalIds = @()
  if ($PrincipalObjectIds -and $PrincipalObjectIds.Count -gt 0) {
    $principalIds += $PrincipalObjectIds
  }
  if ($GroupNames -and $GroupNames.Count -gt 0) {
    foreach ($gn in $GroupNames) {
      $found = Search-Groups -Query $gn -Top $GroupSearchTop
      if (-not $found -or $found.Count -eq 0) {
        Write-Warning ("No groups found for search '{0}'" -f $gn)
        continue
      }
      if ($found.Count -gt 1 -and -not $PickFirstOnMultiple) {
        # Prefer exact match if available
        $exact = $found | Where-Object { $_.DisplayName -eq $gn }
        if ($exact -and $exact.Count -gt 0) {
          $principalIds += ($exact | Select-Object -ExpandProperty Id)
        } else {
          # pick the first deterministically
          $principalIds += $found[0].Id
          Write-Warning ("Multiple groups matched '{0}'. Using first: {1} ({2}). Use -PickFirstOnMultiple to silence this." -f $gn, $found[0].DisplayName, $found[0].Id)
        }
      } else {
        $principalIds += ($found | Select-Object -First 1 -ExpandProperty Id)
      }
    }
  }

  $principalIds = $principalIds | Where-Object { $_ } | Sort-Object -Unique

  if (-not $principalIds -or $principalIds.Count -eq 0) {
    Write-Error "No principals resolved. Provide -PrincipalObjectIds or -GroupNames that exist."
    exit 1
  }

  # Resolve roles
  $roleDefs = @()
  foreach ($rn in $RoleNames) {
    $rd = Get-AzRoleDefinition -Name $rn -ErrorAction SilentlyContinue
    if (-not $rd) {
      $rd = Get-AzRoleDefinition | Where-Object { $_.Name -eq $rn -or $_.RoleName -eq $rn -or $_.Id -eq $rn }
    }
    if ($rd) { $roleDefs += $rd } else { Write-Warning ("Role not found: {0}" -f $rn) }
  }

  if (-not $roleDefs) { Write-Error "No valid roles resolved from -RoleNames."; exit 1 }

  # Assign
  foreach ($pid in $principalIds) {
    foreach ($rd in $roleDefs) {
      Ensure-Assignment -Scope $scope -ObjectId $pid -RoleName $rd.Name -WhatIf:$WhatIf
    }
  }

  Write-Host "Done."
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
