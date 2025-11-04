#Requires -Version 5.1
<#
Deploy-AVD-MENU-TEST-ASCII.ps1
Purpose: Validate parsing and menus on locked-down shells (work laptop).
- ASCII only (no smart quotes, no Unicode).
- No backtick line continuations.
- No Azure resource creation. Safe to run anywhere.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Color {
  param([string]$Msg,[ValidateSet("INFO","SUCCESS","WARNING","ERROR")][string]$Type="INFO")
  $c = switch($Type){"SUCCESS"{"Green"}"ERROR"{"Red"}"WARNING"{"Yellow"}default{"Cyan"}}
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $Msg" -ForegroundColor $c
}

function Parse-IndexSelection {
  param([string]$Text,[int]$Max)
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $sel = ($Text.Trim() -replace '\s','')
  $parts = $sel -split ','
  $idxs = New-Object System.Collections.Generic.List[int]
  foreach ($p in $parts) {
    if ($p -match '^\d+$') {
      $v = [int]$p
      if ($v -ge 1 -and $v -le $Max) { [void]$idxs.Add($v-1) }
    } elseif ($p -match '^\d+-\d+$') {
      $a,$b = $p -split '-'
      $a = [int]$a; $b = [int]$b
      if ($a -gt $b) { $tmp=$a; $a=$b; $b=$tmp }
      for ($z=$a; $z -le $b; $z++) { if ($z -ge 1 -and $z -le $Max) { [void]$idxs.Add($z-1) } }
    }
  }
  $idxs.ToArray() | Sort-Object -Unique
}

function Try-GetSubscriptions {
  $subs = @()
  try {
    Import-Module Az.Accounts -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
      try { Connect-AzAccount -ErrorAction Stop | Out-Null } catch {}
    }
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" }
  } catch {
    $subs = @()
  }
  if (-not $subs -or $subs.Count -eq 0) {
    Write-Color "Az.Accounts not available or no enabled subs found. Using mock list for menu test." "WARNING"
    $subs = @(
      [pscustomobject]@{ Name="Mock-Sub-A"; Id="11111111-1111-1111-1111-111111111111"; TenantId="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" },
      [pscustomobject]@{ Name="Mock-Sub-B"; Id="22222222-2222-2222-2222-222222222222"; TenantId="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" },
      [pscustomobject]@{ Name="Mock-Sub-C"; Id="33333333-3333-3333-3333-333333333333"; TenantId="cccccccc-cccc-cccc-cccc-cccccccccccc" }
    )
  }
  $subs | Sort-Object -Property Id -Unique
}

function Show-SubscriptionsIndexed {
  param([array]$Subs)
  Write-Color "Enabled subscriptions across ALL tenants (or mock list):" "INFO"
  for ($i=0; $i -lt $Subs.Count; $i++) {
    $idx = $i + 1
    Write-Host ("[{0}]  {1}  ({2})  Tenant: {3}" -f $idx, $Subs[$i].Name, $Subs[$i].Id, $Subs[$i].TenantId)
  }
  Write-Color ("Total subscriptions shown: {0}" -f $Subs.Count) "SUCCESS"
}

# VM size menu to match your real script
$VmSizeMenu = @("Standard_D2s_v5","Standard_D4s_v5","Standard_D8s_v5","Standard_D2as_v5","Standard_D4as_v5")

try {
  # Subscriptions menu
  $subs = Try-GetSubscriptions
  if (-not $subs -or $subs.Count -eq 0) { throw "No subscriptions available to show." }
  Show-SubscriptionsIndexed -Subs $subs

  while ($true) {
    $answer = Read-Host "Enter the index/indices to deploy (e.g., 2 or 1,3-5). Required"
    $idx = Parse-IndexSelection -Text $answer -Max $subs.Count
    if ($idx.Count -gt 0) {
      $chosen = foreach($j in $idx){ $subs[$j] }
      Write-Color ("Selected {0} subscription(s)." -f $chosen.Count) "SUCCESS"
      break
    }
    Write-Color "Invalid or empty selection. Please try again." "ERROR"
  }

  # Host count menu
  Write-Host ""
  Write-Color "Host Count Options:" "INFO"
  for ($i=1; $i -le 10; $i++) {
    $sfx = $(if($i -gt 1){"s"}else{""})
    Write-Host ("[{0}]  {1} host{2}" -f $i,$i,$sfx)
  }
  $chosenCount = $null
  while ($true) {
    $countAns = Read-Host "Select host count (1-10). Required"
    if (($countAns -match '^\d+$') -and ([int]$countAns -ge 1) -and ([int]$countAns -le 10)) {
      $chosenCount = [int]$countAns
      break
    }
    Write-Color "Invalid selection. Enter a number 1-10." "ERROR"
  }

  # VM size menu
  Write-Host ""
  Write-Color "VM Size Options:" "INFO"
  for ($i=0; $i -lt $VmSizeMenu.Count; $i++) {
    Write-Host ("[{0}]  {1}" -f ($i+1), $VmSizeMenu[$i])
  }
  $chosenSize = $null
  while ($true) {
    $sizeAns = Read-Host ("Select VM size (1-{0}). Required" -f $VmSizeMenu.Count)
    if (($sizeAns -match '^\d+$') -and ([int]$sizeAns -ge 1) -and ([int]$sizeAns -le $VmSizeMenu.Count)) {
      $chosenSize = $VmSizeMenu[[int]$sizeAns - 1]
      break
    }
    Write-Color ("Invalid selection. Enter a number 1-{0}." -f $VmSizeMenu.Count) "ERROR"
  }

  Write-Host ""
  Write-Color "SUMMARY" "INFO"
  Write-Color ("Subscriptions chosen: {0}" -f (($chosen | ForEach-Object { $_.Name + " (" + $_.Id + ")" }) -join "; ")) "SUCCESS"
  Write-Color ("Host count chosen: {0}" -f $chosenCount) "SUCCESS"
  Write-Color ("VM size chosen: {0}" -f $chosenSize) "SUCCESS"
  Write-Color "Menu test completed successfully. No deployment executed." "SUCCESS"
  exit 0
}
catch {
  Write-Color ("MENU TEST FAILED: {0}" -f $_.Exception.Message) "ERROR"
  exit 1
}
