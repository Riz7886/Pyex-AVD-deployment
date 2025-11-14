Write-Host "MOVEIT DMZ DEPLOYMENT" -ForegroundColor Cyan

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { 
    Write-Host "ERROR: Azure CLI not installed" -ForegroundColor Red
    exit 1 
}

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { 
    Write-Host "ERROR: Terraform not installed" -ForegroundColor Red
    exit 1 
}

$account = az account show 2>$null
if (-not $account) { 
    az login --use-device-code 
}

$subs = az account list | ConvertFrom-Json
Write-Host "SUBSCRIPTIONS:" -ForegroundColor Yellow

for ($i = 0; $i -lt $subs.Count; $i++) { 
    Write-Host "$($i + 1). $($subs[$i].name)" 
}

$choice = Read-Host "Select subscription"
$targetSub = $subs[[int]$choice - 1]

az account set --subscription $targetSub.id
Write-Host "Connected to: $($targetSub.name)" -ForegroundColor Green

Write-Host "Creating MOVEit infrastructure..." -ForegroundColor Yellow

# TODO: Add your terraform deployment commands here
# Example:
# Set-Location -Path "./terraform/moveit-dmz"
# terraform init
# terraform plan
# terraform apply -auto-approve

Write-Host "DONE!" -ForegroundColor Green
