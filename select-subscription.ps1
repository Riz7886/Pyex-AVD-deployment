#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Azure Subscription Selector for Drivers Health Front Door Deployment
.DESCRIPTION
    Lists all available Azure subscriptions and creates terraform.tfvars
    with selected subscription for Terraform deployment
.NOTES
    Author: Syed Rizvi
    Company: Pyx Health
    Service: Drivers Health
#>

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  AZURE SUBSCRIPTION SELECTOR - DRIVERS HEALTH" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        throw "Not connected"
    }
    Write-Host "Already connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Host "Not logged into Azure. Initiating login..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}

Write-Host ""
Write-Host "Searching for Drivers Health subscriptions..." -ForegroundColor Cyan
Write-Host ""

$subscriptions = Get-AzSubscription | Sort-Object Name

Write-Host "Available Azure Subscriptions:" -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    Write-Host "[$i] $($sub.Name)" -ForegroundColor White
    Write-Host "    ID: $($sub.Id)" -ForegroundColor Gray
    
    if ($sub.Name -like "*Drivers*Health*" -or $sub.Name -like "*DriversHealth*") {
        Write-Host "    (Drivers Health Match)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "----------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "Enter subscription number to use for Drivers Health Front Door"

if ($choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -lt $subscriptions.Count) {
    $selectedSub = $subscriptions[[int]$choice]
    
    Write-Host ""
    Write-Host "Selected Subscription: $($selectedSub.Name)" -ForegroundColor Green
    Write-Host "Subscription ID: $($selectedSub.Id)" -ForegroundColor Green
    Write-Host ""
    
    Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
    
    $tfvarsContent = @"
target_subscription_id = "$($selectedSub.Id)"
subscription_name      = "$($selectedSub.Name)"

company_name  = "Pyx Health"
service_name  = "DriversHealth"
naming_prefix = "dh"
environment   = "prod"

resource_group_name = "rg-drivershealth-prod"
location            = "eastus"

frontdoor_name = "fdh-prod"
frontdoor_sku  = "Premium_AzureFrontDoor"

endpoint_name      = "afd-drivershealth-prod"
origin_group_name  = "dh-origin-group"
route_name         = "route-drivershealth-prod"

waf_mode = "Prevention"

health_probe_path     = "/health"
health_probe_interval = 30

session_affinity_enabled = true
enable_https_redirect    = true
enable_caching           = false
enable_compression       = true
enable_managed_identity  = true
enable_diagnostics       = true

log_retention_days = 90

auto_detect_backends     = true
manual_backend_hostname  = "appcsvc-drivershealth-prod.azurewebsites.net"

backend_search_patterns = [
  "*drivershealth*",
  "*drivers-health*",
  "*dh-*"
]

tags = {
  Company    = "Pyx Health"
  Service    = "Drivers Health"
  ManagedBy  = "Terraform"
  CostCenter = "Drivers-Health"
  Compliance = "HIPAA"
  Purpose    = "Drivers Health Platform"
}

create_new_frontdoor = true
"@
    
    $tfvarsContent | Out-File -FilePath "terraform.tfvars" -Encoding UTF8
    
    Write-Host "Subscription configuration saved to terraform.tfvars" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Review terraform.tfvars file" -ForegroundColor White
    Write-Host "2. Run: terraform init" -ForegroundColor White
    Write-Host "3. Run: terraform plan" -ForegroundColor White
    Write-Host "4. Run: terraform apply" -ForegroundColor White
    Write-Host ""
}
else {
    Write-Host ""
    Write-Host "Invalid selection. Please run the script again." -ForegroundColor Red
    Write-Host ""
    exit 1
}
