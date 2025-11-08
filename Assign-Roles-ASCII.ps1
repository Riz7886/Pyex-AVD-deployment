# ===== BEGIN ASCII INLINE RBAC ASSIGN =====
# ASCII-safe PowerShell script to assign Azure roles to DevOps groups.
# Tested for corporate laptops with strict policy (no Unicode, no signature).

$SubscriptionId = "da72e6ae-e86d-4dfd-a5fd-dd6b2c96ae05"
$ScopeType = "Subscription"
$RoleNames = @("Contributor","User Access Administrator")
$GroupNames = @("DevOps","Platform-DevOps")
$GroupSearchTop = 200
$PickFirstOnMultiple = $true

$mods = @("Az.Accounts","Az.Resources")
foreach ($m in $mods) {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    try { Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop | Out-Null }
    catch { Write-Error "Failed to install module $m. $_"; return }
  }
}
foreach ($m in $mods) { Import-Module $m -ErrorAction Stop | Out-Null }

if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
  try { Connect-AzAccount -ErrorAction Stop | Out-Null } catch { Write-Error "Connect-AzAccount failed. $_"; return }
}
try { Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null } catch { Write-Error "Set-AzContext failed. $_"; return }

function Get-Scope {
  $sub = (Get-AzContext).Subscription
  if ($ScopeType -eq "Subscription") { return "/subscriptions/$($sub.Id)" }
  throw "Only subscription-level scope supported in this build."
}

function Get-GraphToken {
  try { return (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop).Token } catch { return $null }
}

function Invoke-GraphGet {
  param([string]$Url)
  $t = Get-GraphToken
  if (-not $t) { return $null }
  $h = @{ Authorization = "Bearer $t"; ConsistencyLevel = "eventual" }
  try { return Invoke-RestMethod -Method Get -Uri $Url -Headers $h -ErrorAction Stop } catch { return $null }
}

function Find-Groups {
  param([string]$Query,[int]$Top=200)
  $res=@()
  try {
    $g1=Get-AzADGroup -DisplayName $Query -First $Top -ErrorAction SilentlyContinue
    if($g1){$res+=$g1}
    $q="startswith(DisplayName,'{0}')" -f $Query.Replace("'","''")
    $g2=Get-AzADGroup -Filter $q -First $Top -ErrorAction SilentlyContinue
    if($g2){$res+=$g2}
  }catch{}
  $res=$res|Sort-Object Id -Unique
  if($res -and $res.Count -gt 0){return $res}
  $enc=[System.Web.HttpUtility]::UrlEncode($Query)
  $url="https://graph.microsoft.com/v1.0/groups?$top=$Top&$filter=contains(displayName,'$enc')"
  $r=Invoke-GraphGet -Url $url
  if($r -and $r.value){return ($r.value|ForEach-Object{[PSCustomObject]@{Id=$_.id;DisplayName=$_.displayName}})}
  return @()
}

function Ensure-RoleAssignment {
  param([string]$Scope,[string]$ObjectId,[string]$RoleName)
  $exist=Get-AzRoleAssignment -Scope $Scope -ObjectId $ObjectId -RoleDefinitionName $RoleName -ErrorAction SilentlyContinue
  if($exist){Write-Host "SKIP: $ObjectId already has $RoleName at $Scope";return}
  try{
    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop|Out-Null
    Write-Host "OK: Assigned $RoleName -> $ObjectId at $Scope"
  }catch{Write-Warning "FAILED: $RoleName -> $ObjectId at $Scope. $($_.Exception.Message)"}
}

$RoleDefs=@()
foreach($r in $RoleNames){
  $d=Get-AzRoleDefinition -Name $r -ErrorAction SilentlyContinue
  if($d){$RoleDefs+=$d}else{Write-Warning "Role not found: $r"}
}
if(-not $RoleDefs){Write-Error "No valid roles";return}
$scope=Get-Scope
Write-Host "Scope: $scope"

$PrincipalObjectIds=@()
foreach($g in $GroupNames){
  $f=Find-Groups -Query $g -Top $GroupSearchTop
  if(-not $f -or $f.Count -eq 0){Write-Warning "No group found for $g";continue}
  $PrincipalObjectIds+=$f[0].Id
}
if(-not $PrincipalObjectIds){Write-Error "No groups resolved";return}

foreach($pid in $PrincipalObjectIds){
  foreach($rd in $RoleDefs){
    Ensure-RoleAssignment -Scope $scope -ObjectId $pid -RoleName $rd.Name
  }
}
Write-Host "Done."
# ===== END ASCII INLINE RBAC ASSIGN =====
