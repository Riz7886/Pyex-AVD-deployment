# ================================================================
# MOVEIT AZURE FRONT DOOR + LOAD BALANCER DEPLOYMENT
# PRODUCTION VERSION - USES/CREATES INFRASTRUCTURE AS NEEDED
# Matches pyxiq-style Configuration
# Version: 5.0 FINAL (Ensure RG/VNet/Subnet exist or create)
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT FRONT DOOR DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Uses Existing / Creates Missing Resources" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# CONFIGURATION (EDIT THESE FOR OTHER ENVIRONMENTS)
# ----------------------------------------------------------------
$config = @{
    # Resource Group / Network
    ResourceGroup      = "rg-networking"      # existing RG name (or will be created)
    Location           = "westus"             # Azure region
    VNetName           = "vnet-prod"          # existing VNet name (or will be created)
    VNetAddressSpace   = "192.168.0.0/16"     # used only if VNet must be created
    SubnetName         = "snet-moveit"        # existing subnet (or will be created)
    SubnetPrefix       = "192.168.0.0/24"     # used only if subnet must be created

    # MOVEit backend
    MOVEitPrivateIP    = "192.168.0.5"

    # Front Door
    FrontDoorProfileName    = "moveit-frontdoor-profile"
    FrontDoorEndpointName   = "moveit-endpoint"
    FrontDoorOriginGroupName= "moveit-origin-group"
    FrontDoorOriginName     = "moveit-origin"
    FrontDoorRouteName      = "moveit-route"
    FrontDoorSKU            = "Standard_AzureFrontDoor"

    # WAF
    WAFPolicyName      = "moveitWAFPolicy"
    WAFMode            = "Prevention"
    WAFSKU             = "Standard_AzureFrontDoor"

    # Load Balancer
    LoadBalancerName       = "lb-moveit-ftps"
    LoadBalancerPublicIPName = "pip-moveit-ftps"

    # NSG
    NSGName             = "nsg-moveit"
}

# ----------------------------------------------------------------
# FUNCTION: Write Log
# ----------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# STEP 1: CHECK AZURE CLI
# ----------------------------------------------------------------
Write-Log "Checking Azure CLI..." "Yellow"
try {
    $azVersionJson = az version --output json 2>$null
    if (-not $azVersionJson) {
        throw "az version returned no data"
    }
    $azVersion = $azVersionJson | ConvertFrom-Json
    Write-Log "Azure CLI version: $($azVersion.'azure-cli')" "Green"
}
catch {
    Write-Log "ERROR: Azure CLI not found or not working." "Red"
    Write-Log "Install from: https://aka.ms/installazurecliwindows" "Yellow"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN TO AZURE (DEVICE CODE IF NEEDED)
# ----------------------------------------------------------------
Write-Log "Checking Azure login status..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in - starting device code login..." "Yellow"
    az login --use-device-code | Out-Null
}
else {
    Write-Log "Already logged in." "Green"
}

# ----------------------------------------------------------------
# STEP 3: SELECT SUBSCRIPTION (SHOW ALL, LET USER CHOOSE)
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Log "============================================" "Cyan"

$subscriptions = az account list --output json | ConvertFrom-Json
if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Log "ERROR: No subscriptions visible for this account." "Red"
    exit 1
}

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $stateColor = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host ("[{0}] " -f ($i + 1)) -NoNewline -ForegroundColor Cyan
    Write-Host ($sub.name + " ") -NoNewline -ForegroundColor White
    Write-Host ("({0})" -f $sub.state) -ForegroundColor $stateColor
}

Write-Host ""
Write-Host -NoNewline (Get-Date -Format "yyyy-MM-dd HH:mm:ss")" Select subscription number: "
$selection = Read-Host

try {
    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count) {
        throw "Index out of range"
    }
    $selectedSubscription = $subscriptions[$selectedIndex]
    Write-Log "Setting subscription to: $($selectedSubscription.name)" "Cyan"
    az account set --subscription $selectedSubscription.id
    $currentSub = az account show --query name -o tsv
    Write-Log "Active subscription: $currentSub" "Green"
}
catch {
    Write-Log "ERROR: Invalid subscription selection." "Red"
    exit 1
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 4: ENSURE RESOURCE GROUP / VNET / SUBNET EXIST
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "CHECKING / CREATING NETWORK RESOURCES" "Cyan"
Write-Log "============================================" "Cyan"

# 4a) Resource Group
Write-Log "Checking Resource Group: $($config.ResourceGroup)..." "Yellow"
$rgExists = az group show --name $config.ResourceGroup 2>$null
if ($rgExists) {
    Write-Log "Resource Group exists: $($config.ResourceGroup)" "Green"
}
else {
    Write-Log "Resource Group not found. Creating: $($config.ResourceGroup)" "Yellow"
    az group create `
        --name $config.ResourceGroup `
        --location $config.Location `
        --output none
    Write-Log "Resource Group created." "Green"
}

# 4b) Virtual Network
Write-Log "Checking VNet: $($config.VNetName)..." "Yellow"
$vnetExists = az network vnet show `
    --resource-group $config.ResourceGroup `
    --name $config.VNetName 2>$null

if ($vnetExists) {
    Write-Log "VNet exists: $($config.VNetName)" "Green"
}
else {
    Write-Log "VNet not found. Creating VNet: $($config.VNetName)" "Yellow"
    az network vnet create `
        --resource-group $config.ResourceGroup `
        --name $config.VNetName `
        --address-prefixes $config.VNetAddressSpace `
        --location $config.Location `
        --subnet-name $config.SubnetName `
        --subnet-prefixes $config.SubnetPrefix `
        --output none
    Write-Log "VNet and subnet created: $($config.VNetName) / $($config.SubnetName)" "Green"
}

# 4c) Subnet (if VNet existed but subnet might not)
Write-Log "Checking Subnet: $($config.SubnetName)..." "Yellow"
$subnetExists = az network vnet subnet show `
    --resource-group $config.ResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName 2>$null

if ($subnetExists) {
    Write-Log "Subnet exists: $($config.SubnetName)" "Green"
}
else {
    Write-Log "Subnet not found. Creating subnet: $($config.SubnetName)" "Yellow"
    az network vnet subnet create `
        --resource-group $config.ResourceGroup `
        --vnet-name $config.VNetName `
        --name $config.SubnetName `
        --address-prefixes $config.SubnetPrefix `
        --output none
    Write-Log "Subnet created." "Green"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 5: CREATE NETWORK SECURITY GROUP
# ----------------------------------------------------------------
Write-Log "Creating / Checking Network Security Group..." "Cyan"

$nsgExists = az network nsg show `
    --resource-group $config.ResourceGroup `
    --name $config.NSGName 2>$null

if (-not $nsgExists) {
    az network nsg create `
        --resource-group $config.ResourceGroup `
        --name $config.NSGName `
        --location $config.Location `
        --output none
    Write-Log "NSG created: $($config.NSGName)" "Green"
}
else {
    Write-Log "NSG already exists: $($config.NSGName)" "Yellow"
}

# Add/update rules (idempotent: overwrite if exist)
function Ensure-NsgRule {
    param(
        [string]$RuleName,
        [int]$Priority,
        [int]$Port
    )
    Write-Log "Ensuring NSG rule $RuleName on port $Port..." "Cyan"
    az network nsg rule create `
        --resource-group $config.ResourceGroup `
        --nsg-name $config.NSGName `
        --name $RuleName `
        --priority $Priority `
        --direction Inbound `
        --access Allow `
        --protocol Tcp `
        --source-address-prefixes "*" `
        --source-port-ranges "*" `
        --destination-address-prefixes "*" `
        --destination-port-ranges $Port `
        --output none 2>$null
}

Ensure-NsgRule -RuleName "Allow-FTPS-990" -Priority 100 -Port 990
Ensure-NsgRule -RuleName "Allow-FTPS-989" -Priority 110 -Port 989
Ensure-NsgRule -RuleName "Allow-HTTPS-443" -Priority 120 -Port 443

# Associate NSG with subnet
Write-Log "Associating NSG with subnet..." "Cyan"
az network vnet subnet update `
    --resource-group $config.ResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName `
    --network-security-group $config.NSGName `
    --output none

Write-Log "NSG configured successfully." "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 6: CREATE LOAD BALANCER FOR FTPS
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING LOAD BALANCER FOR FTPS" "Cyan"
Write-Log "============================================" "Cyan"

# Public IP
Write-Log "Checking Public IP for Load Balancer..." "Cyan"
$lbPublicIPExists = az network public-ip show `
    --resource-group $config.ResourceGroup `
    --name $config.LoadBalancerPublicIPName 2>$null

if (-not $lbPublicIPExists) {
    az network public-ip create `
        --resource-group $config.ResourceGroup `
        --name $config.LoadBalancerPublicIPName `
        --sku Standard `
        --allocation-method Static `
        --location $config.Location `
        --output none
    Write-Log "Public IP created: $($config.LoadBalancerPublicIPName)" "Green"
}
else {
    Write-Log "Public IP already exists." "Yellow"
}

# Load Balancer
Write-Log "Checking Load Balancer..." "Cyan"
$lbExists = az network lb show `
    --resource-group $config.ResourceGroup `
    --name $config.LoadBalancerName 2>$null

if (-not $lbExists) {
    az network lb create `
        --resource-group $config.ResourceGroup `
        --name $config.LoadBalancerName `
        --sku Standard `
        --public-ip-address $config.LoadBalancerPublicIPName `
        --frontend-ip-name "LoadBalancerFrontEnd" `
        --backend-pool-name "backend-pool-lb" `
        --location $config.Location `
        --output none

    # backend address
    az network lb address-pool address add `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --pool-name "backend-pool-lb" `
        --name "moveit-backend" `
        --vnet $config.VNetName `
        --ip-address $config.MOVEitPrivateIP `
        --output none

    # health probe
    az network lb probe create `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name "health-probe-ftps" `
        --protocol tcp `
        --port 990 `
        --interval 15 `
        --threshold 2 `
        --output none

    # LB rules
    az network lb rule create `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name "lb-rule-990" `
        --protocol Tcp `
        --frontend-port 990 `
        --backend-port 990 `
        --frontend-ip-name "LoadBalancerFrontEnd" `
        --backend-pool-name "backend-pool-lb" `
        --probe-name "health-probe-ftps" `
        --idle-timeout 15 `
        --enable-tcp-reset true `
        --output none

    az network lb rule create `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name "lb-rule-989" `
        --protocol Tcp `
        --frontend-port 989 `
        --backend-port 989 `
        --frontend-ip-name "LoadBalancerFrontEnd" `
        --backend-pool-name "backend-pool-lb" `
        --probe-name "health-probe-ftps" `
        --idle-timeout 15 `
        --enable-tcp-reset true `
        --output none

    Write-Log "Load Balancer created: $($config.LoadBalancerName)" "Green"
}
else {
    Write-Log "Load Balancer already exists." "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 7: CREATE WAF POLICY (MATCHING PYXIQ-STYLE)
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING / CHECKING WAF POLICY" "Cyan"
Write-Log "============================================" "Cyan"

$wafExists = az network front-door waf-policy show `
    --resource-group $config.ResourceGroup `
    --name $config.WAFPolicyName 2>$null

if (-not $wafExists) {
    Write-Log "Creating WAF policy..." "Cyan"
    az network front-door waf-policy create `
        --resource-group $config.ResourceGroup `
        --name $config.WAFPolicyName `
        --sku $config.WAFSKU `
        --mode $config.WAFMode `
        --output none

    az network front-door waf-policy policy-setting update `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --mode Prevention `
        --custom-block-response-status-code 403 `
        --custom-block-response-body "QWNjZXNzIERlbmllZA==" `
        --request-body-check Enabled `
        --max-request-body-size-in-kb 524288 `
        --file-upload-enforcement true `
        --file-upload-limit-in-mb 500 `
        --output none

    az network front-door waf-policy managed-rules add `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type DefaultRuleSet `
        --version 1.0 `
        --output none

    az network front-door waf-policy managed-rules add `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type Microsoft_BotManagerRuleSet `
        --version 1.0 `
        --output none

    Write-Log "WAF Policy created: $($config.WAFPolicyName)" "Green"
}
else {
    Write-Log "WAF Policy already exists: $($config.WAFPolicyName)" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 8: CREATE AZURE FRONT DOOR
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING AZURE FRONT DOOR" "Cyan"
Write-Log "============================================" "Cyan"

# Profile
$fdProfileExists = az afd profile show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName 2>$null

if (-not $fdProfileExists) {
    az afd profile create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --sku $config.FrontDoorSKU `
        --output none
    Write-Log "Front Door profile created." "Green"
}
else {
    Write-Log "Front Door profile already exists." "Yellow"
}

# Endpoint
$fdEndpointExists = az afd endpoint show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName 2>$null

if (-not $fdEndpointExists) {
    az afd endpoint create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --enabled-state Enabled `
        --output none
    Write-Log "Front Door endpoint created." "Green"
}
else {
    Write-Log "Front Door endpoint already exists." "Yellow"
}

# Origin Group
$originGroupExists = az afd origin-group show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --origin-group-name $config.FrontDoorOriginGroupName 2>$null

if (-not $originGroupExists) {
    az afd origin-group create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name $config.FrontDoorOriginGroupName `
        --probe-request-type GET `
        --probe-protocol Https `
        --probe-interval-in-seconds 30 `
        --probe-path "/" `
        --sample-size 4 `
        --successful-samples-required 2 `
        --additional-latency-in-milliseconds 0 `
        --output none
    Write-Log "Origin group created." "Green"
}
else {
    Write-Log "Origin group already exists." "Yellow"
}

# Origin
$originExists = az afd origin show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --origin-group-name $config.FrontDoorOriginGroupName `
    --origin-name $config.FrontDoorOriginName 2>$null

if (-not $originExists) {
    az afd origin create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name $config.FrontDoorOriginGroupName `
        --origin-name $config.FrontDoorOriginName `
        --host-name $config.MOVEitPrivateIP `
        --origin-host-header $config.MOVEitPrivateIP `
        --http-port 80 `
        --https-port 443 `
        --priority 1 `
        --weight 1000 `
        --enabled-state Enabled `
        --output none
    Write-Log "Origin created for MOVEit backend." "Green"
}
else {
    Write-Log "Origin already exists." "Yellow"
}

# Route
$routeExists = az afd route show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --route-name $config.FrontDoorRouteName 2>$null

if (-not $routeExists) {
    az afd route create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --route-name $config.FrontDoorRouteName `
        --origin-group $config.FrontDoorOriginGroupName `
        --supported-protocols Https `
        --https-redirect Enabled `
        --forwarding-protocol HttpsOnly `
        --patterns-to-match "/*" `
        --enabled-state Enabled `
        --output none
    Write-Log "HTTPS routing rule created." "Green"
}
else {
    Write-Log "Routing rule already exists." "Yellow"
}

# Associate WAF with Front Door
Write-Log "Associating WAF policy with Front Door..." "Cyan"
$wafPolicyId = az network front-door waf-policy show `
    --resource-group $config.ResourceGroup `
    --name $config.WAFPolicyName `
    --query id --output tsv

$subscriptionId = az account show --query id --output tsv

az afd security-policy create `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --security-policy-name "moveit-waf-security" `
    --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.ResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" `
    --waf-policy $wafPolicyId `
    --output none 2>$null

Write-Log "WAF policy associated with Front Door." "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 9: ENABLE DEFENDER FOR RELEVANT PLANS
# ----------------------------------------------------------------
Write-Log "Enabling Microsoft Defender plans (VMs, AppServices, Storage)..." "Cyan"
az security pricing create --name VirtualMachines --tier Standard --output none 2>$null
az security pricing create --name AppServices --tier Standard --output none 2>$null
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "Microsoft Defender plans ensured." "Green"
Write-Host ""

# ----------------------------------------------------------------
# DEPLOYMENT SUMMARY
# ----------------------------------------------------------------
Write-Log "============================================" "Green"
Write-Log "  DEPLOYMENT COMPLETED (OR ALREADY PRESENT)" "Green"
Write-Log "============================================" "Green"
Write-Host ""

$ftpsPublicIP = az network public-ip show `
    --resource-group $config.ResourceGroup `
    --name $config.LoadBalancerPublicIPName `
    --query ipAddress --output tsv

$frontDoorEndpoint = az afd endpoint show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --query hostName --output tsv

Write-Log "EXISTING / USED RESOURCES:" "Yellow"
Write-Log "  Resource Group: $($config.ResourceGroup)" "White"
Write-Log "  VNet: $($config.VNetName)" "White"
Write-Log "  Subnet: $($config.SubnetName)" "White"
Write-Log "  MOVEit Server IP: $($config.MOVEitPrivateIP)" "White"
Write-Host ""
Write-Log "NEW / ENSURED RESOURCES:" "Yellow"
Write-Log "  Front Door Profile: $($config.FrontDoorProfileName)" "White"
Write-Log "  Front Door Endpoint: $frontDoorEndpoint" "White"
Write-Log "  Load Balancer: $($config.LoadBalancerName)" "White"
Write-Log "  WAF Policy: $($config.WAFPolicyName)" "White"
Write-Log "  NSG: $($config.NSGName)" "White"
Write-Host ""
Write-Log "PUBLIC ENDPOINTS:" "Cyan"
Write-Log "  FTPS Public IP: $ftpsPublicIP (ports 989, 990)" "Green"
Write-Log "  HTTPS Front Door: https://$frontDoorEndpoint" "Green"
Write-Host ""

# Save summary to Desktop
$summaryFile = Join-Path $env:USERPROFILE "Desktop\MOVEit-Deployment-Summary.txt"
@"
============================================
MOVEIT FRONT DOOR DEPLOYMENT SUMMARY
============================================
Deployed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Subscription: $(az account show --query name -o tsv)

RESOURCE GROUP / NETWORK
- Resource Group: $($config.ResourceGroup)
- Location: $($config.Location)
- VNet: $($config.VNetName)  ($($config.VNetAddressSpace))
- Subnet: $($config.SubnetName)  ($($config.SubnetPrefix))
- MOVEit Server IP: $($config.MOVEitPrivateIP)

NEW / ENSURED RESOURCES
- Front Door Profile: $($config.FrontDoorProfileName)
- Front Door Endpoint: $frontDoorEndpoint
- Origin Group: $($config.FrontDoorOriginGroupName)
- Origin: $($config.FrontDoorOriginName)
- Load Balancer: $($config.LoadBalancerName)
- WAF Policy: $($config.WAFPolicyName)
- NSG: $($config.NSGName)

PUBLIC ENDPOINTS
- FTPS: $ftpsPublicIP (ports 989, 990)
- HTTPS: https://$frontDoorEndpoint

DEFENDER PLANS
- VirtualMachines: Standard
- AppServices: Standard
- StorageAccounts: Standard
============================================
"@ | Out-File -FilePath $summaryFile -Encoding ASCII

Write-Log "Summary saved to: $summaryFile" "Cyan"
Write-Log "DONE." "Green"
