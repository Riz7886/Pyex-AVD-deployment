param([string]$TargetSubscriptionName = "DriversHealth", [string]$BackendHostname = "drivershealth.azurewebsites.net", [string]$AlertEmail = "devops@drivershealth.com")
Write-Host "AZURE FRONT DOOR DEPLOYMENT" -ForegroundColor Green
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Azure CLI not installed"; exit 1 }
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) { Write-Host "ERROR: Terraform not installed"; exit 1 }
$account = az account show 2>$null
if (-not $account) { az login }
$subs = az account list | ConvertFrom-Json
Write-Host "SUBSCRIPTIONS:"
for ($i = 0; $i -lt $subs.Count; $i++) { Write-Host "$($i + 1). $($subs[$i].name) - ID: $($subs[$i].id) - Tenant: $($subs[$i].tenantId)" }
$targetSub = $subs | Where-Object { $_.name -like "*$TargetSubscriptionName*" } | Select-Object -First 1
if (-not $targetSub) { $choice = Read-Host "Enter subscription number"; $targetSub = $subs[[int]$choice - 1] }
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
