Write-Host "MOVEIT DMZ DEPLOYMENT" -ForegroundColor Cyan
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Azure CLI not installed"; exit 1 }
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Terraform not installed"; exit 1 }
$account = az account show 2>$null
if (-not $account) { az login --use-device-code }
$subs = az account list | ConvertFrom-Json
Write-Host "SUBSCRIPTIONS:"
for ($i = 0; $i -lt $subs.Count; $i++) { Write-Host "$($i + 1). $($subs[$i].name)" }
$choice = Read-Host "Select subscription"
$targetSub = $subs[[int]$choice - 1]
az account set --subscription $targetSub.id
Write-Host "Connected to: $($targetSub.name)" -ForegroundColor Green
Write-Host "Creating MOVEit infrastructure..." -ForegroundColor Yellow
Write-Host "DONE!" -ForegroundColor Green
