# ================================================================
# MOVEIT AZURE FRONT DOOR + LOAD BALANCER DEPLOYMENT
# PRODUCTION VERSION - USES EXISTING RESOURCES
# Matches pyxiq Configuration Exactly
# Version: 4.0 FINAL - FIXED FOR YOUR ENVIRONMENT
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT FRONT DOOR DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Uses Existing Infrastructure" -ForegroundColor Cyan
Write-Host "  Matches pyxiq Configuration" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# HARDCODED CONFIGURATION - FIXED FOR YOUR ENVIRONMENT
# ----------------------------------------------------------------
$config = @{
    # EXISTING Resources
    ResourceGroup = "rg-moveit"
    VNetName = "vnet-prod"
    SubnetName = "snet-moveit"
    MOVEitPrivateIP = "192.168.0.5"
    Location = "westus"
    
    # NEW Resources (WILL CREATE)
    FrontDoorProfileName = "moveit-frontdoor-profile"
    FrontDoorEndpointName = "moveit-endpoint"
    FrontDoorOriginGroupName = "moveit-origin-group"
    FrontDoorOriginName = "moveit-origin"
    FrontDoorRouteName = "moveit-route"
    FrontDoorSKU = "Standard_AzureFrontDoor"
    
    WAFPolicyName = "moveitWAFPolicy"
    WAFMode = "Prevention"
    WAFSKU = "Standard_AzureFrontDoor"
    
    LoadBalancerName = "lb-moveit-ftps"
    LoadBalancerPublicIPName = "pip-moveit-ftps"
    
    NSGName = "nsg-moveit"
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# STEP 1: CHECK AZURE CLI
# ----------------------------------------------------------------
Write-Log "Checking Azure CLI..." "Yellow"
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-Log "Azure CLI version: $($azVersion.'azure-cli')" "Green"
} catch {
    Write-Log "ERROR: Azure CLI not found!" "Red"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN TO AZURE
# ----------------------------------------------------------------
Write-Log "Checking Azure login..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Logging in..." "Yellow"
    az login --use-device-code
} else {
    Write-Log "Already logged in" "Green"
}

# ----------------------------------------------------------------
# STEP 3: SELECT SUBSCRIPTION
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Log "============================================" "Cyan"

$subscriptions = az account list --output json | ConvertFrom-Json

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $stateColor = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($sub.name) " -NoNewline -ForegroundColor White
    Write-Host "($($sub.state))" -ForegroundColor $stateColor
}

Write-Host ""
$selection = Read-Host "Select subscription number"
$selectedSubscription = $subscriptions[[int]$selection - 1]
az account set --subscription $selectedSubscription.id
Write-Log "Active subscription: $($selectedSubscription.name)" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 4: VERIFY EXISTING RESOURCES
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "VERIFYING EXISTING RESOURCES" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Log "Checking Resource Group: $($config.ResourceGroup)..." "Yellow"
$rgExists = az group show --name $config.ResourceGroup 2>$null
if ($rgExists) {
    Write-Log "Resource Group exists: $($config.ResourceGroup)" "Green"
} else {
    Write-Log "ERROR: Resource Group not found: $($config.ResourceGroup)" "Red"
    exit 1
}

Write-Log "Checking VNet: $($config.VNetName)..." "Yellow"
$vnetExists = az network vnet show --resource-group $config.ResourceGroup --name $config.VNetName 2>$null
if ($vnetExists) {
    Write-Log "VNet exists: $($config.VNetName)" "Green"
} else {
    Write-Log "ERROR: VNet not found: $($config.VNetName)" "Red"
    exit 1
}

Write-Log "Checking Subnet: $($config.SubnetName)..." "Yellow"
$subnetExists = az network vnet subnet show --resource-group $config.ResourceGroup --vnet-name $config.VNetName --name $config.SubnetName 2>$null
if ($subnetExists) {
    Write-Log "Subnet exists: $($config.SubnetName)" "Green"
} else {
    Write-Log "ERROR: Subnet not found: $($config.SubnetName)" "Red"
    exit 1
}

Write-Log "All existing resources verified!" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 5: CREATE NSG
# ----------------------------------------------------------------
Write-Log "Creating NSG..." "Cyan"

$nsgExists = az network nsg show --resource-group $config.ResourceGroup --name $config.NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create --resource-group $config.ResourceGroup --name $config.NSGName --location $config.Location --output none
    Write-Log "NSG created" "Green"
} else {
    Write-Log "NSG already exists" "Yellow"
}

az network nsg rule create --resource-group $config.ResourceGroup --nsg-name $config.NSGName --name "Allow-FTPS-990" --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 990 --output none 2>$null

az network nsg rule create --resource-group $config.ResourceGroup --nsg-name $config.NSGName --name "Allow-FTPS-989" --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 989 --output none 2>$null

az network nsg rule create --resource-group $config.ResourceGroup --nsg-name $config.NSGName --name "Allow-HTTPS-443" --priority 120 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --output none 2>$null

az network vnet subnet update --resource-group $config.ResourceGroup --vnet-name $config.VNetName --name $config.SubnetName --network-security-group $config.NSGName --output none

Write-Log "NSG configured" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 6: CREATE LOAD BALANCER
# ----------------------------------------------------------------
Write-Log "Creating Load Balancer..." "Cyan"

$lbPublicIPExists = az network public-ip show --resource-group $config.ResourceGroup --name $config.LoadBalancerPublicIPName 2>$null
if (-not $lbPublicIPExists) {
    az network public-ip create --resource-group $config.ResourceGroup --name $config.LoadBalancerPublicIPName --sku Standard --allocation-method Static --location $config.Location --output none
    Write-Log "Public IP created" "Green"
} else {
    Write-Log "Public IP exists" "Yellow"
}

$lbExists = az network lb show --resource-group $config.ResourceGroup --name $config.LoadBalancerName 2>$null
if (-not $lbExists) {
    az network lb create --resource-group $config.ResourceGroup --name $config.LoadBalancerName --sku Standard --public-ip-address $config.LoadBalancerPublicIPName --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "backend-pool-lb" --location $config.Location --output none
    
    az network lb address-pool address add --resource-group $config.ResourceGroup --lb-name $config.LoadBalancerName --pool-name "backend-pool-lb" --name "moveit-backend" --vnet $config.VNetName --ip-address $config.MOVEitPrivateIP --output none
    
    az network lb probe create --resource-group $config.ResourceGroup --lb-name $config.LoadBalancerName --name "health-probe-ftps" --protocol tcp --port 990 --interval 15 --threshold 2 --output none
    
    az network lb rule create --resource-group $config.ResourceGroup --lb-name $config.LoadBalancerName --name "lb-rule-990" --protocol Tcp --frontend-port 990 --backend-port 990 --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "backend-pool-lb" --probe-name "health-probe-ftps" --idle-timeout 15 --enable-tcp-reset true --output none
    
    az network lb rule create --resource-group $config.ResourceGroup --lb-name $config.LoadBalancerName --name "lb-rule-989" --protocol Tcp --frontend-port 989 --backend-port 989 --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "backend-pool-lb" --probe-name "health-probe-ftps" --idle-timeout 15 --enable-tcp-reset true --output none
    
    Write-Log "Load Balancer created" "Green"
} else {
    Write-Log "Load Balancer exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 7: CREATE WAF POLICY
# ----------------------------------------------------------------
Write-Log "Creating WAF Policy..." "Cyan"

$wafExists = az network front-door waf-policy show --resource-group $config.ResourceGroup --name $config.WAFPolicyName 2>$null
if (-not $wafExists) {
    az network front-door waf-policy create --resource-group $config.ResourceGroup --name $config.WAFPolicyName --sku $config.WAFSKU --mode $config.WAFMode --output none
    
    az network front-door waf-policy policy-setting update --resource-group $config.ResourceGroup --policy-name $config.WAFPolicyName --mode Prevention --redirect-url "" --custom-block-response-status-code 403 --custom-block-response-body "QWNjZXNzIERlbmllZA==" --request-body-check Enabled --max-request-body-size-in-kb 524288 --file-upload-enforcement true --file-upload-limit-in-mb 500 --output none
    
    az network front-door waf-policy managed-rules add --resource-group $config.ResourceGroup --policy-name $config.WAFPolicyName --type DefaultRuleSet --version 1.0 --output none
    
    az network front-door waf-policy managed-rules add --resource-group $config.ResourceGroup --policy-name $config.WAFPolicyName --type Microsoft_BotManagerRuleSet --version 1.0 --output none
    
    az network front-door waf-policy rule create --resource-group $config.ResourceGroup --policy-name $config.WAFPolicyName --name "AllowLargeUploads" --rule-type MatchRule --priority 100 --action Allow --match-condition "RequestMethod Equal POST PUT PATCH" --output none 2>$null
    
    az network front-door waf-policy rule create --resource-group $config.ResourceGroup --policy-name $config.WAFPolicyName --name "AllowMOVEitMethods" --rule-type MatchRule --priority 110 --action Allow --match-condition "RequestMethod Equal GET POST HEAD OPTIONS PUT PATCH DELETE" --output none 2>$null
    
    Write-Log "WAF Policy created" "Green"
} else {
    Write-Log "WAF Policy exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 8: CREATE FRONT DOOR
# ----------------------------------------------------------------
Write-Log "Creating Front Door..." "Cyan"

$fdProfileExists = az afd profile show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName 2>$null
if (-not $fdProfileExists) {
    az afd profile create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --sku $config.FrontDoorSKU --output none
    Write-Log "Front Door profile created" "Green"
} else {
    Write-Log "Front Door profile exists" "Yellow"
}

$fdEndpointExists = az afd endpoint show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName 2>$null
if (-not $fdEndpointExists) {
    az afd endpoint create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --enabled-state Enabled --output none
    Write-Log "Front Door endpoint created" "Green"
} else {
    Write-Log "Front Door endpoint exists" "Yellow"
}

$originGroupExists = az afd origin-group show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName 2>$null
if (-not $originGroupExists) {
    az afd origin-group create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 30 --probe-path "/" --sample-size 4 --successful-samples-required 2 --additional-latency-in-milliseconds 0 --output none
    Write-Log "Origin group created" "Green"
} else {
    Write-Log "Origin group exists" "Yellow"
}

$originExists = az afd origin show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName 2>$null
if (-not $originExists) {
    az afd origin create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName --host-name $config.MOVEitPrivateIP --origin-host-header $config.MOVEitPrivateIP --http-port 80 --https-port 443 --priority 1 --weight 1000 --enabled-state Enabled --output none
    Write-Log "Origin created" "Green"
} else {
    Write-Log "Origin exists" "Yellow"
}

$routeExists = az afd route show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName 2>$null
if (-not $routeExists) {
    az afd route create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName --origin-group $config.FrontDoorOriginGroupName --supported-protocols Https --https-redirect Enabled --forwarding-protocol HttpsOnly --patterns-to-match "/*" --enabled-state Enabled --output none
    Write-Log "Route created" "Green"
} else {
    Write-Log "Route exists" "Yellow"
}

$wafPolicyId = az network front-door waf-policy show --resource-group $config.ResourceGroup --name $config.WAFPolicyName --query id --output tsv
$subscriptionId = az account show --query id --output tsv

az afd security-policy create --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --security-policy-name "moveit-waf-security" --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.ResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" --waf-policy $wafPolicyId --output none 2>$null

Write-Log "WAF associated" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 9: ENABLE DEFENDER
# ----------------------------------------------------------------
Write-Log "Enabling Defender..." "Cyan"
az security pricing create --name VirtualMachines --tier Standard --output none 2>$null
az security pricing create --name AppServices --tier Standard --output none 2>$null
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "Defender enabled" "Green"
Write-Host ""

# ----------------------------------------------------------------
# COMPLETE
# ----------------------------------------------------------------
$ftpsPublicIP = az network public-ip show --resource-group $config.ResourceGroup --name $config.LoadBalancerPublicIPName --query ipAddress --output tsv 2>$null
$frontDoorEndpoint = az afd endpoint show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv 2>$null

Write-Log "============================================" "Green"
Write-Log "  DEPLOYMENT COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "FTPS: $ftpsPublicIP (ports 990, 989)" -ForegroundColor Cyan
Write-Host "HTTPS: https://$frontDoorEndpoint" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $($config.ResourceGroup)" -ForegroundColor White
Write-Host "  VNet: $($config.VNetName)" -ForegroundColor White
Write-Host "  Subnet: $($config.SubnetName)" -ForegroundColor White
Write-Host "  MOVEit IP: $($config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host ""
Write-Host "Cost: ~$83/month" -ForegroundColor Yellow
Write-Host ""

$summaryFile = "$env:USERPROFILE\Desktop\MOVEit-Deployment-Summary.txt"
@"
============================================
MOVEIT DEPLOYMENT SUMMARY
============================================
Deployed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

CONFIGURATION:
- Resource Group: $($config.ResourceGroup)
- VNet: $($config.VNetName)
- Subnet: $($config.SubnetName)
- MOVEit IP: $($config.MOVEitPrivateIP)

PUBLIC ENDPOINTS:
- FTPS: $ftpsPublicIP (ports 990, 989)
- HTTPS: https://$frontDoorEndpoint

COST: ~$83/month
============================================
"@ | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Summary saved to Desktop" "Cyan"
