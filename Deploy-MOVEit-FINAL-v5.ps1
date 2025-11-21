# ================================================================
# MOVEIT AZURE FRONT DOOR + LOAD BALANCER DEPLOYMENT
# PRODUCTION VERSION - USES EXISTING OR NEW RESOURCES
# Matches pyxiq Configuration As Close As Possible
# Version: 5.0 FINAL (Interactive RG/VNet/Subnet selection)
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT FRONT DOOR DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Uses Existing / New Infrastructure" -ForegroundColor Cyan
Write-Host "  Matches pyxiq Configuration" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# BASIC CONFIG (CAN EDIT)
# ----------------------------------------------------------------
$config = @{
    # Where to deploy new resources
    Location = "westus"

    # MOVEit backend private IP (inside selected VNet/Subnet)
    MOVEitPrivateIP = "192.168.0.5"

    # Names for NEW resources (these will be created if missing)
    FrontDoorProfileName    = "moveit-frontdoor-profile"
    FrontDoorEndpointName   = "moveit-endpoint"
    FrontDoorOriginGroupName = "moveit-origin-group"
    FrontDoorOriginName     = "moveit-origin"
    FrontDoorRouteName      = "moveit-route"
    FrontDoorSKU            = "Standard_AzureFrontDoor"

    WAFPolicyName           = "moveitWAFPolicy"
    WAFMode                 = "Prevention"
    WAFSKU                  = "Standard_AzureFrontDoor"

    LoadBalancerName        = "lb-moveit-ftps"
    LoadBalancerPublicIPName = "pip-moveit-ftps"

    NSGName                 = "nsg-moveit"

    # These will be filled in later by interactive selection
    ResourceGroup           = $null
    VNetName                = $null
    SubnetName              = $null
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
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-Log ("Azure CLI version: {0}" -f $azVersion."azure-cli") "Green"
} catch {
    Write-Log "ERROR: Azure CLI not found!" "Red"
    Write-Log "Install from: https://aka.ms/installazurecliwindows" "Yellow"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN TO AZURE
# ----------------------------------------------------------------
Write-Log "Checking Azure login status..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in - starting authentication (device code)..." "Yellow"
    az login --use-device-code | Out-Null
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
if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Log "No subscriptions visible for this account." "Red"
    Write-Log "If you need a NEW subscription, create it in the Azure Portal then re-run this script." "Yellow"
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
$selection = Read-Host "Select subscription number"
try {
    $selectedIndex = [int]$selection - 1
    $selectedSubscription = $subscriptions[$selectedIndex]
    Write-Log ("Setting subscription to: {0}" -f $selectedSubscription.name) "Cyan"
    az account set --subscription $selectedSubscription.id
    $currentSub = az account show --query name -o tsv
    Write-Log ("Active subscription: {0}" -f $currentSub) "Green"
} catch {
    Write-Log "ERROR: Invalid selection." "Red"
    exit 1
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 3B: SELECT OR CREATE RESOURCE GROUP
# ----------------------------------------------------------------
Write-Log "Retrieving resource groups..." "Yellow"
$resourceGroups = az group list --query "[].name" -o tsv
$rgArray = @()

if ($resourceGroups) {
    for ($i = 0; $i -lt $resourceGroups.Count; $i++) {
        $rgArray += $resourceGroups[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $resourceGroups[$i]) -ForegroundColor White
    }
} else {
    Write-Log "No resource groups found in this subscription." "Yellow"
}

$createRgIndex = $rgArray.Count + 1
Write-Host ("[{0}] Create NEW resource group" -f $createRgIndex) -ForegroundColor Cyan
$rgChoice = Read-Host "Select resource group number"

if ([int]$rgChoice -eq $createRgIndex -or (-not $resourceGroups)) {
    $newRgName = Read-Host "Enter NEW resource group name (e.g. rg-moveit-prod)"
    $newRgLocation = Read-Host ("Enter location for new RG (default: {0})" -f $config.Location)
    if ([string]::IsNullOrWhiteSpace($newRgLocation)) {
        $newRgLocation = $config.Location
    }
    Write-Log ("Creating resource group {0} in {1}..." -f $newRgName, $newRgLocation) "Cyan"
    az group create --name $newRgName --location $newRgLocation --output none
    $config.ResourceGroup = $newRgName
    $config.Location = $newRgLocation
    Write-Log ("Resource group created: {0}" -f $config.ResourceGroup) "Green"
} else {
    $index = [int]$rgChoice - 1
    $config.ResourceGroup = $rgArray[$index]
    Write-Log ("Using existing resource group: {0}" -f $config.ResourceGroup) "Green"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 3C: SELECT OR CREATE VNET
# ----------------------------------------------------------------
Write-Log ("Listing VNets in RG {0}..." -f $config.ResourceGroup) "Yellow"
$vnetList = az network vnet list -g $config.ResourceGroup --query "[].name" -o tsv
$vnetArray = @()

if ($vnetList) {
    for ($i = 0; $i -lt $vnetList.Count; $i++) {
        $vnetArray += $vnetList[$i]
        Write-Host ("[{0}] {1}" -f ($i + 1), $vnetList[$i]) -ForegroundColor White
    }
} else {
    Write-Log "No VNets found in this resource group." "Yellow"
}

$createVnetIndex = $vnetArray.Count + 1
Write-Host ("[{0}] Create NEW VNet" -f $createVnetIndex) -ForegroundColor Cyan
$vnetChoice = Read-Host "Select VNet number"

if ([int]$vnetChoice -eq $createVnetIndex -or (-not $vnetList)) {
    $newVnetName = Read-Host "Enter NEW VNet name (e.g. vnet-prod)"
    $newVnetPrefix = Read-Host "Enter address space for VNet (e.g. 192.168.0.0/16)"
    if ([string]::IsNullOrWhiteSpace($newVnetPrefix)) {
        $newVnetPrefix = "192.168.0.0/16"
    }
    $newSubnetName = Read-Host "Enter FIRST subnet name (e.g. snet-moveit)"
    $newSubnetPrefix = Read-Host "Enter subnet prefix (e.g. 192.168.0.0/24)"
    if ([string]::IsNullOrWhiteSpace($newSubnetPrefix)) {
        $newSubnetPrefix = "192.168.0.0/24"
    }

    Write-Log ("Creating VNet {0} with subnet {1}..." -f $newVnetName, $newSubnetName) "Cyan"
    az network vnet create `
        --resource-group $config.ResourceGroup `
        --name $newVnetName `
        --address-prefixes $newVnetPrefix `
        --subnet-name $newSubnetName `
        --subnet-prefix $newSubnetPrefix `
        --location $config.Location `
        --output none

    $config.VNetName = $newVnetName
    $config.SubnetName = $newSubnetName
    Write-Log ("VNet and subnet created: {0} / {1}" -f $config.VNetName, $config.SubnetName) "Green"
} else {
    $index = [int]$vnetChoice - 1
    $config.VNetName = $vnetArray[$index]
    Write-Log ("Using existing VNet: {0}" -f $config.VNetName) "Green"

    # ----------------------------------------------------------------
    # STEP 3D: SELECT OR CREATE SUBNET INSIDE EXISTING VNET
    # ----------------------------------------------------------------
    Write-Log ("Listing subnets in VNet {0}..." -f $config.VNetName) "Yellow"
    $subnetList = az network vnet subnet list `
        -g $config.ResourceGroup `
        --vnet-name $config.VNetName `
        --query "[].name" `
        -o tsv

    $subnetArray = @()
    if ($subnetList) {
        for ($i = 0; $i -lt $subnetList.Count; $i++) {
            $subnetArray += $subnetList[$i]
            Write-Host ("[{0}] {1}" -f ($i + 1), $subnetList[$i]) -ForegroundColor White
        }
    } else {
        Write-Log "No subnets found in this VNet." "Yellow"
    }

    $createSubnetIndex = $subnetArray.Count + 1
    Write-Host ("[{0}] Create NEW subnet" -f $createSubnetIndex) -ForegroundColor Cyan
    $subChoice = Read-Host "Select subnet number"

    if ([int]$subChoice -eq $createSubnetIndex -or (-not $subnetList)) {
        $newSubnetName = Read-Host "Enter NEW subnet name (e.g. snet-moveit)"
        $newSubnetPrefix = Read-Host "Enter subnet prefix (e.g. 192.168.0.0/24)"
        if ([string]::IsNullOrWhiteSpace($newSubnetPrefix)) {
            $newSubnetPrefix = "192.168.0.0/24"
        }

        Write-Log ("Creating subnet {0}..." -f $newSubnetName) "Cyan"
        az network vnet subnet create `
            --resource-group $config.ResourceGroup `
            --vnet-name $config.VNetName `
            --name $newSubnetName `
            --address-prefixes $newSubnetPrefix `
            --output none

        $config.SubnetName = $newSubnetName
        Write-Log ("Subnet created: {0}" -f $config.SubnetName) "Green"
    } else {
        $index = [int]$subChoice - 1
        $config.SubnetName = $subnetArray[$index]
        Write-Log ("Using existing subnet: {0}" -f $config.SubnetName) "Green"
    }
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 4: VERIFY RESOURCES (SAFETY CHECK)
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "VERIFYING SELECTED RESOURCES" "Cyan"
Write-Log "============================================" "Cyan"

# Check Resource Group
Write-Log ("Checking Resource Group: {0}..." -f $config.ResourceGroup) "Yellow"
$rgExists = az group show --name $config.ResourceGroup 2>$null
if (-not $rgExists) {
    Write-Log ("ERROR: Resource Group not found: {0}" -f $config.ResourceGroup) "Red"
    exit 1
}
Write-Log "Resource Group verified." "Green"

# Check VNet
Write-Log ("Checking VNet: {0}..." -f $config.VNetName) "Yellow"
$vnetExists = az network vnet show --resource-group $config.ResourceGroup --name $config.VNetName 2>$null
if (-not $vnetExists) {
    Write-Log ("ERROR: VNet not found: {0}" -f $config.VNetName) "Red"
    exit 1
}
Write-Log "VNet verified." "Green"

# Check Subnet
Write-Log ("Checking Subnet: {0}..." -f $config.SubnetName) "Yellow"
$subnetExists = az network vnet subnet show `
    --resource-group $config.ResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName 2>$null

if (-not $subnetExists) {
    Write-Log ("ERROR: Subnet not found: {0}" -f $config.SubnetName) "Red"
    exit 1
}
Write-Log "Subnet verified." "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 5: CREATE NETWORK SECURITY GROUP (NEW)
# ----------------------------------------------------------------
Write-Log "Creating / Updating Network Security Group..." "Cyan"

$nsgExists = az network nsg show --resource-group $config.ResourceGroup --name $config.NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create `
        --resource-group $config.ResourceGroup `
        --name $config.NSGName `
        --location $config.Location `
        --output none
    Write-Log ("NSG created: {0}" -f $config.NSGName) "Green"
} else {
    Write-Log ("NSG already exists: {0}" -f $config.NSGName) "Yellow"
}

# Add NSG rules (idempotent: ignore errors if they exist)
function Add-NsgRule {
    param(
        [string]$RuleName,
        [int]$Priority,
        [int]$Port
    )
    Write-Log ("Ensuring NSG rule {0} for port {1}..." -f $RuleName, $Port) "Cyan"
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

Add-NsgRule -RuleName "Allow-FTPS-990" -Priority 100 -Port 990
Add-NsgRule -RuleName "Allow-FTPS-989" -Priority 110 -Port 989
Add-NsgRule -RuleName "Allow-HTTPS-443" -Priority 120 -Port 443

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
Write-Log "Ensuring Public IP for Load Balancer..." "Cyan"
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
    Write-Log ("Public IP created: {0}" -f $config.LoadBalancerPublicIPName) "Green"
} else {
    Write-Log "Public IP already exists." "Yellow"
}

# Load Balancer
Write-Log "Ensuring Load Balancer..." "Cyan"
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

    # Backend address
    az network lb address-pool address add `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --pool-name "backend-pool-lb" `
        --name "moveit-backend" `
        --vnet $config.VNetName `
        --ip-address $config.MOVEitPrivateIP `
        --output none

    # Health probe
    az network lb probe create `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name "health-probe-ftps" `
        --protocol tcp `
        --port 990 `
        --interval 15 `
        --threshold 2 `
        --output none

    # LB rules 990 and 989
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

    Write-Log ("Load Balancer created: {0}" -f $config.LoadBalancerName) "Green"
} else {
    Write-Log "Load Balancer already exists." "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 7: CREATE WAF POLICY
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING WAF POLICY" "Cyan"
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

    Write-Log "Adding managed rule sets..." "Cyan"
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

    Write-Log "Adding custom rules..." "Cyan"
    az network front-door waf-policy rule create `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --name "AllowLargeUploads" `
        --rule-type MatchRule `
        --priority 100 `
        --action Allow `
        --match-condition "RequestMethod Equal POST PUT PATCH" `
        --output none 2>$null

    az network front-door waf-policy rule create `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --name "AllowMOVEitMethods" `
        --rule-type MatchRule `
        --priority 110 `
        --action Allow `
        --match-condition "RequestMethod Equal GET POST HEAD OPTIONS PUT PATCH DELETE" `
        --output none 2>$null

    Write-Log ("WAF Policy created: {0}" -f $config.WAFPolicyName) "Green"
} else {
    Write-Log "WAF Policy already exists." "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 8: CREATE AZURE FRONT DOOR
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING AZURE FRONT DOOR" "Cyan"
Write-Log "============================================" "Cyan"

# Front Door Profile
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
} else {
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
} else {
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
} else {
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
    Write-Log "Origin created." "Green"
} else {
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
    Write-Log "Route created." "Green"
} else {
    Write-Log "Route already exists." "Yellow"
}

# Associate WAF
Write-Log "Associating WAF policy with Front Door..." "Cyan"
$wafPolicyId = az network front-door waf-policy show `
    --resource-group $config.ResourceGroup `
    --name $config.WAFPolicyName `
    --query id `
    --output tsv

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
# STEP 9: ENABLE MICROSOFT DEFENDER (OPTIONAL)
# ----------------------------------------------------------------
Write-Log "Enabling Microsoft Defender for Cloud (VMs, AppServices, Storage)..." "Cyan"
az security pricing create --name VirtualMachines  --tier Standard --output none 2>$null
az security pricing create --name AppServices     --tier Standard --output none 2>$null
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "Microsoft Defender configuration complete." "Green"
Write-Host ""

# ----------------------------------------------------------------
# DEPLOYMENT COMPLETE - SUMMARY
# ----------------------------------------------------------------
Write-Log "============================================" "Green"
Write-Log "  DEPLOYMENT COMPLETED SUCCESSFULLY!" "Green"
Write-Log "============================================" "Green"
Write-Host ""

$ftpsPublicIP = az network public-ip show `
    --resource-group $config.ResourceGroup `
    --name $config.LoadBalancerPublicIPName `
    --query ipAddress `
    --output tsv

$frontDoorEndpoint = az afd endpoint show `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --query hostName `
    --output tsv

Write-Log "DEPLOYMENT SUMMARY:" "Cyan"
Write-Log "===================" "Cyan"
Write-Host ""
Write-Log "RESOURCE SCOPE:" "Yellow"
Write-Log ("  Subscription: {0}" -f (az account show --query name -o tsv)) "White"
Write-Log ("  Resource Group: {0}" -f $config.ResourceGroup) "White"
Write-Log ("  VNet: {0}" -f $config.VNetName) "White"
Write-Log ("  Subnet: {0}" -f $config.SubnetName) "White"
Write-Log ("  MOVEit Server IP: {0}" -f $config.MOVEitPrivateIP) "White"
Write-Host ""
Write-Log "NEW RESOURCES:" "Yellow"
Write-Log ("  Front Door: {0}" -f $config.FrontDoorProfileName) "White"
Write-Log ("  Endpoint: {0}" -f $frontDoorEndpoint) "White"
Write-Log ("  Load Balancer: {0}" -f $config.LoadBalancerName) "White"
Write-Log ("  Public IP: {0}" -f $ftpsPublicIP) "White"
Write-Log ("  WAF Policy: {0}" -f $config.WAFPolicyName) "White"
Write-Log ("  NSG: {0}" -f $config.NSGName) "White"
Write-Host ""
Write-Log "PUBLIC ACCESS:" "Cyan"
Write-Log ("  FTPS: {0}:990, {0}:989" -f $ftpsPublicIP) "Green"
Write-Log ("  HTTPS: https://{0}" -f $frontDoorEndpoint) "Green"
Write-Host ""
Write-Log "============================================" "Green"
Write-Log "  READY FOR PRODUCTION" "Green"
Write-Log "============================================" "Green"

# Save summary on Desktop
$summaryFile = Join-Path $env:USERPROFILE "Desktop\MOVEit-Deployment-Summary.txt"
@"
============================================
MOVEIT FRONT DOOR DEPLOYMENT SUMMARY
============================================
Deployed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Subscription: $(az account show --query name -o tsv)

Resource Group: $($config.ResourceGroup)
VNet: $($config.VNetName)
Subnet: $($config.SubnetName)
MOVEit Backend IP: $($config.MOVEitPrivateIP)

Front Door Profile: $($config.FrontDoorProfileName)
Front Door Endpoint: $frontDoorEndpoint
Load Balancer: $($config.LoadBalancerName)
Public IP: $ftpsPublicIP
WAF Policy: $($config.WAFPolicyName)
NSG: $($config.NSGName)

FTPS Ports: 990, 989
HTTPS Port: 443

Health Probe: 30 seconds
Sample Size: 4
Successful Samples: 2
Session Affinity: Disabled
WAF Rules: DefaultRuleSet 1.0 + BotManager

============================================
"@ | Out-File -FilePath $summaryFile -Encoding ASCII

Write-Log ("Summary saved to: {0}" -f $summaryFile) "Cyan"
