#Requires -Version 5.1
<#
Assign-DevOps-Role-SubProd.ps1
Purpose:
  - Assign a single Azure built-in role (Contributor or Owner) to Entra ID group "devops".
  - Pinned to production subscription by ID:
        Name (expected): Sub-Production
        ID: da72e6ae-e86d-4dfd-a5fd-dd6b2c96ae05
  - ASCII only. No Unicode. No backtick line continuations.
  - Safe idempotency: skips if the exact role assignment already exists.
  - Does not change or remove any other role assignments.

Usage:
  .\Assign-DevOps-Role-SubProd.ps1
  .\Assign-DevOps-Role-SubProd.ps1 -RoleName Owner
  .\Assign-DevOps-Role-SubProd.ps1 -WhatIf

Notes:
  - Use Contributor for Terraform deployments.
  - Only use Owner if Terraform must create role assignments (RBAC) itself.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Low")]
param(
  [ValidateSet("Contributor","Owner")]
  [string]$RoleName = "Contributor",
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Pinned subscription constants
$ExpectedSubscriptionName = "Sub-Production"
$PinnedSubscriptionId     = "da72e6ae-e86d-4dfd-a5fd-dd6b2c96ae05"

function Write-Info { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" -ForegroundColor Red }

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
      Write-Info ("Installing module {0}..." -f $m)
      Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
    }
    Import-Module $m -ErrorAction Stop | Out-Null
  }
  Write-Ok "Modules ready"
}

function Connect-Azure {
  $ctx = Get-AzContext -ErrorAction SilentlyContinue
  if($ctx -and $ctx.Account){
    Write-Ok ("Using existing context: {0}" -f $ctx.Account.Id)
    return
  }
  try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
    if($ctx -and $ctx.Account){
      Write-Ok ("Connected via Managed Identity: {0}" -f $ctx.Account.Id)
      return
    }
  } catch {}
  Connect-AzAccount -UseDeviceAuthentication:$true -ErrorAction Stop | Out-Null
  $ctx = Get-AzContext
  if(-not ($ctx -and $ctx.Account)){
    throw "Unable to obtain an Azure context."
  }
  Write-Ok ("Connected as: {0}" -f $ctx.Account.Id)
}

function Get-ProdSubscription {
  # Search all tenants for the pinned subscription ID
  $tenants = @()
  try { $tenants = Get-AzTenant -ErrorAction Stop } catch { $tenants = @() }

  $found = $null
  if($tenants -and $tenants.Count -gt 0){
    foreach($t in $tenants){
      $subs = Get-AzSubscription -TenantId $t.TenantId -ErrorAction SilentlyContinue
      if($subs){
        $match = $subs | Where-Object { $_.Id -eq $PinnedSubscriptionId -and $_.State -eq "Enabled" }
        if($match){ $found = $match[0]; break }
      }
    }
  }
  if(-not $found){
    # Fallback: use global list
    $subs = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
    $found = $subs | Where-Object { $_.Id -eq $PinnedSubscriptionId } | Select-Object -First 1
  }
  if(-not $found){
    throw ("Pinned subscription not found or not enabled: {0}" -f $PinnedSubscriptionId)
  }

  if($found.Name -ne $ExpectedSubscriptionName){
    Write-Warn ("Subscription name mismatch: expected '{0}', actual '{1}'. Proceeding by ID." -f $ExpectedSubscriptionName,$found.Name)
  } else {
    Write-Ok ("Subscription name confirmed: {0}" -f $ExpectedSubscriptionName)
  }
  return $found
}

function Get-DevOpsGroupId {
  $groups = Get-AzADGroup -DisplayName "devops" -ErrorAction SilentlyContinue
  $exact = @()
  if($groups){ $exact = $groups | Where-Object { $_.DisplayName -ieq "devops" } }
  if(-not $exact -or $exact.Count -eq 0){
    throw "Group 'devops' not found. Create the group first."
  }
  if($exact.Count -gt 1){
    $list = $exact | ForEach-Object { "DisplayName={0} Id={1}" -f $_.DisplayName, $_.Id } | Out-String
    throw ("Multiple groups named 'devops' found. Resolve duplication. {0}" -f $list)
  }
  return $exact[0].Id
}

function Ensure-RoleAssignment {
  param(
    [string]$SubscriptionId,
    [string]$TenantId,
    [string]$ObjectId,
    [string]$RoleName
  )
  $scope = "/subscriptions/$SubscriptionId"

  Set-AzContext -SubscriptionId $SubscriptionId -Tenant $TenantId -ErrorAction Stop | Out-Null

  # Check existing assignment
  $existing = @()
  try {
    $existing = Get-AzRoleAssignment -ObjectId $ObjectId -Scope $scope -ErrorAction SilentlyContinue |
                Where-Object { $_.RoleDefinitionName -eq $RoleName }
  } catch {
    $existing = @()
  }
  if($existing -and $existing.Count -gt 0){
    Write-Ok ("Already assigned: {0} -> {1}" -f $RoleName,$scope)
    return
  }

  $msg = ("Assign role '{0}' to 'devops' at {1}" -f $RoleName,$scope)
  if($PSCmdlet.ShouldProcess($scope, $msg)){
    if($WhatIf){
      Write-Info ("WHATIF: would assign {0} at {1}" -f $RoleName,$scope)
    } else {
      try {
        New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $scope -ErrorAction Stop | Out-Null
        Write-Ok ("Assigned: {0} -> {1}" -f $RoleName,$scope)
      } catch {
        if($_.Exception.Message -match "already exists" -or $_.Exception.Message -match "AssignmentExists"){
          Write-Ok ("Assignment already exists (server-side). Skipping: {0}" -f $scope)
        } else {
          Write-Err ("Failed to assign {0} at {1}: {2}" -f $RoleName,$scope,$_.Exception.Message)
          throw
        }
      }
    }
  }
}

try {
  Write-Info "Starting role assignment (pinned to Sub-Production)..."
  Ensure-Modules
  Connect-Azure

  $sub = Get-ProdSubscription
  Write-Ok ("Using subscription: {0} [{1}]  Tenant: {2}" -f $sub.Name,$sub.Id,$sub.TenantId)

  $devOpsObjectId = Get-DevOpsGroupId
  Write-Ok ("devops group objectId: {0}" -f $devOpsObjectId)

  Ensure-RoleAssignment -SubscriptionId $sub.Id -TenantId $sub.TenantId -ObjectId $devOpsObjectId -RoleName $RoleName

  Write-Ok "Completed. No other role assignments were changed."
  if($WhatIf){ Write-Warn "This was a WHATIF run. Re-run without -WhatIf to apply." }
  exit 0
}
catch {
  Write-Err ("FAILED: {0}" -f $_.Exception.Message)
  exit 1
}
