param([string]$TargetSubscriptionName = "DriversHealth", [string]$BackendHostname = "drivershealth.azurewebsites.net", [string]$AlertEmail = "devops@drivershealth.com")
Write-Host "AZURE FRONT DOOR DEPLOYMENT" -ForegroundColor Green
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Azure CLI not installed"; exit 1 }
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Terraform not installed"; exit 1 }
Write-Host "Checking Azure authentication..."
$account = az account show 2>$null
if (-not $account) { Write-Host "Opening browser for login..." -ForegroundColor Yellow; az login --use-device-code }
Write-Host "Authenticated!" -ForegroundColor Green
$subs = az account list | ConvertFrom-Json
Write-Host "SUBSCRIPTIONS:"
for ($i = 0; $i -lt $subs.Count; $i++) { Write-Host "$($i + 1). $($subs[$i].name) - ID: $($subs[$i].id)" }
$targetSub = $subs | Where-Object { $_.name -like "*$TargetSubscriptionName*" } | Select-Object -First 1
if ($targetSub) { Write-Host "Found: $($targetSub.name)" -ForegroundColor Green } else { Write-Host "DriversHealth not found" -ForegroundColor Yellow; Write-Host "Options: 1) Select existing  2) Create new"; $option = Read-Host "Choose (1 or 2)"; if ($option -eq "2") { Write-Host "Go to: https://portal.azure.com/#create/Microsoft.Subscription" -ForegroundColor Yellow; exit 0 } else { $choice = Read-Host "Enter subscription number"; $targetSub = $subs[[int]$choice - 1] } }
az account set --subscription $targetSub.id
Write-Host "Using: $($targetSub.name)" -ForegroundColor Green
@"
project_name        = "DriversHealth"
environment         = "prod"
location            = "East US"
backend_host_name   = "$BackendHostname"
health_probe_path   = "/"
alert_email_address = "$AlertEmail"
"@ | Out-File terraform.tfvars -Encoding UTF8 -Force
Write-Host "Initializing Terraform..." -ForegroundColor Yellow
terraform init -upgrade
Write-Host "Validating..." -ForegroundColor Yellow
terraform validate
Write-Host "Deploying..." -ForegroundColor Yellow
terraform apply -auto-approve
if ($LASTEXITCODE -eq 0) { $fdUrl = terraform output -raw frontdoor_url 2>$null; Write-Host "SUCCESS! Front Door: $fdUrl" -ForegroundColor Green }
