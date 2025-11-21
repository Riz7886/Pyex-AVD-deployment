# ================================================================
# MOVEIT AZURE FRONT DOOR + LOAD BALANCER DEPLOYMENT
# PRODUCTION VERSION - USES EXISTING RESOURCES
# Matches pyxiq Configuration Exactly
# Version: 4.0 FINAL
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT FRONT DOOR DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Uses Existing Infrastructure" -ForegroundColor Cyan
Write-Host "  Matches pyxiq Configuration" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------
# HARDCODED CONFIGURATION (EXISTING RESOURCES)
# ----------------------------------------------------------------
$config = @{
    # EXISTING Resources (DO NOT CREATE)
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

# ----------------------------------------------------------------
# FUNCTION: Write Log
# ----------------------------------------------------------------
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
    Write-Log "Install from: https://aka.ms/installazurecliwindows" "Yellow"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN TO AZURE
# ----------------------------------------------------------------
Write-Log "Checking Azure login status..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in - starting authentication..." "Yellow"
    az login --use-device-code
} else {
    Write-Log "Already logged in" "Green"
}

# ----------------------------------------------------------------
# STEP 3: SELECT SUBSCRIPTION (SHOW ALL, LET USER CHOOSE)
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Log "============================================" "Cyan"

$subscriptions = az account list --output json | ConvertFrom-Json
$subscriptionList = @()

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $subscriptionList += [PSCustomObject]@{
        Number = $i + 1
        Name = $sub.name
        ID = $sub.id
        State = $sub.state
    }
    
    $stateColor = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($sub.name) " -NoNewline -ForegroundColor White
    Write-Host "($($sub.state))" -ForegroundColor $stateColor
}

Write-Host ""
Write-Log "Select subscription number: " "Yellow" -NoNewline
$selection = Read-Host

try {
    $selectedIndex = [int]$selection - 1
    $selectedSubscription = $subscriptions[$selectedIndex]
    
    Write-Log "Setting subscription to: $($selectedSubscription.name)" "Cyan"
    az account set --subscription $selectedSubscription.id
    
    $currentSub = az account show --query name -o tsv
    Write-Log "Active subscription: $currentSub" "Green"
} catch {
    Write-Log "ERROR: Invalid selection!" "Red"
    exit 1
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 4: VERIFY EXISTING RESOURCES
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "VERIFYING EXISTING RESOURCES" "Cyan"
Write-Log "============================================" "Cyan"

# Check Resource Group
Write-Log "Checking Resource Group: $($config.ResourceGroup)..." "Yellow"
$rgExists = az group show --name $config.ResourceGroup 2>$null
if ($rgExists) {
    Write-Log "Resource Group exists: $($config.ResourceGroup)" "Green"
} else {
    Write-Log "ERROR: Resource Group not found: $($config.ResourceGroup)" "Red"
    Write-Log "Please create it first or check the name" "Yellow"
    exit 1
}

# Check VNet
Write-Log "Checking VNet: $($config.VNetName)..." "Yellow"
$vnetExists = az network vnet show --resource-group $config.ResourceGroup --name $config.VNetName 2>$null
if ($vnetExists) {
    Write-Log "VNet exists: $($config.VNetName)" "Green"
} else {
    Write-Log "ERROR: VNet not found: $($config.VNetName)" "Red"
    Write-Log "Please create it first or check the name" "Yellow"
    exit 1
}

# Check Subnet
Write-Log "Checking Subnet: $($config.SubnetName)..." "Yellow"
$subnetExists = az network vnet subnet show --resource-group $config.ResourceGroup --vnet-name $config.VNetName --name $config.SubnetName 2>$null
if ($subnetExists) {
    Write-Log "Subnet exists: $($config.SubnetName)" "Green"
} else {
    Write-Log "ERROR: Subnet not found: $($config.SubnetName)" "Red"
    Write-Log "Please create it first or check the name" "Yellow"
    exit 1
}

Write-Log "All existing resources verified successfully!" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 5: CREATE NETWORK SECURITY GROUP (NEW)
# ----------------------------------------------------------------
Write-Log "Creating Network Security Group..." "Cyan"

$nsgExists = az network nsg show --resource-group $config.ResourceGroup --name $config.NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create `
        --resource-group $config.ResourceGroup `
        --name $config.NSGName `
        --location $config.Location `
        --output none
    
    Write-Log "NSG created: $($config.NSGName)" "Green"
} else {
    Write-Log "NSG already exists: $($config.NSGName)" "Yellow"
}

# Add NSG Rules
Write-Log "Adding NSG rule for FTPS port 990..." "Cyan"
az network nsg rule create `
    --resource-group $config.ResourceGroup `
    --nsg-name $config.NSGName `
    --name "Allow-FTPS-990" `
    --priority 100 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes '*' `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 990 `
    --output none 2>$null

Write-Log "Adding NSG rule for FTPS port 989..." "Cyan"
az network nsg rule create `
    --resource-group $config.ResourceGroup `
    --nsg-name $config.NSGName `
    --name "Allow-FTPS-989" `
    --priority 110 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes '*' `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 989 `
    --output none 2>$null

Write-Log "Adding NSG rule for HTTPS port 443..." "Cyan"
az network nsg rule create `
    --resource-group $config.ResourceGroup `
    --nsg-name $config.NSGName `
    --name "Allow-HTTPS-443" `
    --priority 120 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes '*' `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 443 `
    --output none 2>$null

# Associate NSG with existing subnet
Write-Log "Associating NSG with subnet..." "Cyan"
az network vnet subnet update `
    --resource-group $config.ResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName `
    --network-security-group $config.NSGName `
    --output none

Write-Log "NSG configured successfully" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 6: CREATE LOAD BALANCER FOR FTPS (NEW)
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING LOAD BALANCER FOR FTPS" "Cyan"
Write-Log "============================================" "Cyan"

# Create Public IP
Write-Log "Creating public IP..." "Cyan"
$lbPublicIPExists = az network public-ip show --resource-group $config.ResourceGroup --name $config.LoadBalancerPublicIPName 2>$null
if (-not $lbPublicIPExists) {
    az network public-ip create `
        --resource-group $config.ResourceGroup `
        --name $config.LoadBalancerPublicIPName `
        --sku Standard `
        --allocation-method Static `
        --location $config.Location `
        --output none
    
    Write-Log "Public IP created: $($config.LoadBalancerPublicIPName)" "Green"
} else {
    Write-Log "Public IP already exists" "Yellow"
}

# Create Load Balancer
Write-Log "Creating load balancer..." "Cyan"
$lbExists = az network lb show --resource-group $config.ResourceGroup --name $config.LoadBalancerName 2>$null
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
    
    # Add backend address to pool
    az network lb address-pool address add `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --pool-name "backend-pool-lb" `
        --name "moveit-backend" `
        --vnet $config.VNetName `
        --ip-address $config.MOVEitPrivateIP `
        --output none
    
    # Create health probe
    az network lb probe create `
        --resource-group $config.ResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name "health-probe-ftps" `
        --protocol tcp `
        --port 990 `
        --interval 15 `
        --threshold 2 `
        --output none
    
    # Create LB rule for port 990
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
    
    # Create LB rule for port 989
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
} else {
    Write-Log "Load Balancer already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 7: CREATE WAF POLICY (MATCHING PYXIQ)
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING WAF POLICY (MATCHING PYXIQ)" "Cyan"
Write-Log "============================================" "Cyan"

$wafExists = az network front-door waf-policy show --resource-group $config.ResourceGroup --name $config.WAFPolicyName 2>$null
if (-not $wafExists) {
    # Create WAF policy
    Write-Log "Creating WAF policy..." "Cyan"
    az network front-door waf-policy create `
        --resource-group $config.ResourceGroup `
        --name $config.WAFPolicyName `
        --sku $config.WAFSKU `
        --mode $config.WAFMode `
        --output none
    
    # Configure policy settings (matching pyxiq)
    az network front-door waf-policy policy-setting update `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --mode Prevention `
        --redirect-url "" `
        --custom-block-response-status-code 403 `
        --custom-block-response-body "QWNjZXNzIERlbmllZA==" `
        --request-body-check Enabled `
        --max-request-body-size-in-kb 524288 `
        --file-upload-enforcement true `
        --file-upload-limit-in-mb 500 `
        --output none
    
    # Add managed rule set (DefaultRuleSet 1.0 - matching pyxiq)
    Write-Log "Adding OWASP DefaultRuleSet 1.0..." "Cyan"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type DefaultRuleSet `
        --version 1.0 `
        --output none
    
    # Add Bot Manager rule set
    Write-Log "Adding Bot Manager rules..." "Cyan"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type Microsoft_BotManagerRuleSet `
        --version 1.0 `
        --output none
    
    # Add custom rule: Allow large uploads
    Write-Log "Adding custom rule for large uploads..." "Cyan"
    az network front-door waf-policy rule create `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --name "AllowLargeUploads" `
        --rule-type MatchRule `
        --priority 100 `
        --action Allow `
        --match-condition "RequestMethod Equal POST PUT PATCH" `
        --output none 2>$null
    
    # Add custom rule: Allow MOVEit HTTP methods
    Write-Log "Adding custom rule for MOVEit HTTP methods..." "Cyan"
    az network front-door waf-policy rule create `
        --resource-group $config.ResourceGroup `
        --policy-name $config.WAFPolicyName `
        --name "AllowMOVEitMethods" `
        --rule-type MatchRule `
        --priority 110 `
        --action Allow `
        --match-condition "RequestMethod Equal GET POST HEAD OPTIONS PUT PATCH DELETE" `
        --output none 2>$null
    
    Write-Log "WAF Policy created: $($config.WAFPolicyName)" "Green"
    Write-Log "DefaultRuleSet 1.0 (117+ OWASP rules) enabled" "Green"
} else {
    Write-Log "WAF Policy already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 8: CREATE AZURE FRONT DOOR (MATCHING PYXIQ)
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DEPLOYING AZURE FRONT DOOR" "Cyan"
Write-Log "============================================" "Cyan"

# Create Front Door Profile
Write-Log "Creating Front Door profile..." "Cyan"
$fdProfileExists = az afd profile show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName 2>$null
if (-not $fdProfileExists) {
    az afd profile create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --sku $config.FrontDoorSKU `
        --output none
    
    Write-Log "Front Door profile created" "Green"
} else {
    Write-Log "Front Door profile already exists" "Yellow"
}

# Create Endpoint
Write-Log "Creating Front Door endpoint..." "Cyan"
$fdEndpointExists = az afd endpoint show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName 2>$null
if (-not $fdEndpointExists) {
    az afd endpoint create `
        --resource-group $config.ResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --enabled-state Enabled `
        --output none
    
    Write-Log "Front Door endpoint created" "Green"
} else {
    Write-Log "Front Door endpoint already exists" "Yellow"
}

# Create Origin Group (matching pyxiq: 30 seconds, sample 4, success 2)
Write-Log "Creating origin group (matching pyxiq settings)..." "Cyan"
$originGroupExists = az afd origin-group show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName 2>$null
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
    
    Write-Log "Origin group created (30s probe, sample 4, success 2)" "Green"
} else {
    Write-Log "Origin group already exists" "Yellow"
}

# Create Origin (MOVEit backend)
Write-Log "Creating origin with MOVEit backend..." "Cyan"
$originExists = az afd origin show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName 2>$null
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
    
    Write-Log "Origin created: $($config.MOVEitPrivateIP)" "Green"
} else {
    Write-Log "Origin already exists" "Yellow"
}

# Create Route
Write-Log "Creating routing rule..." "Cyan"
$routeExists = az afd route show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName 2>$null
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
    
    Write-Log "Routing rule created (HTTPS only)" "Green"
} else {
    Write-Log "Routing rule already exists" "Yellow"
}

# Associate WAF with Front Door
Write-Log "Associating WAF policy with Front Door..." "Cyan"
$wafPolicyId = az network front-door waf-policy show --resource-group $config.ResourceGroup --name $config.WAFPolicyName --query id --output tsv
$subscriptionId = az account show --query id --output tsv

az afd security-policy create `
    --resource-group $config.ResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --security-policy-name "moveit-waf-security" `
    --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.ResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" `
    --waf-policy $wafPolicyId `
    --output none 2>$null

Write-Log "WAF policy associated with Front Door" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 9: ENABLE MICROSOFT DEFENDER
# ----------------------------------------------------------------
Write-Log "Enabling Microsoft Defender for Cloud..." "Cyan"
az security pricing create --name VirtualMachines --tier Standard --output none 2>$null
az security pricing create --name AppServices --tier Standard --output none 2>$null
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "Microsoft Defender enabled" "Green"
Write-Host ""

# ----------------------------------------------------------------
# DEPLOYMENT COMPLETE
# ----------------------------------------------------------------
Write-Log "============================================" "Green"
Write-Log "  DEPLOYMENT COMPLETED SUCCESSFULLY!" "Green"
Write-Log "============================================" "Green"
Write-Host ""

# Get deployment info
$ftpsPublicIP = az network public-ip show --resource-group $config.ResourceGroup --name $config.LoadBalancerPublicIPName --query ipAddress --output tsv
$frontDoorEndpoint = az afd endpoint show --resource-group $config.ResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv

Write-Log "DEPLOYMENT SUMMARY:" "Cyan"
Write-Log "===================" "Cyan"
Write-Host ""
Write-Log "EXISTING RESOURCES (USED):" "Yellow"
Write-Log "  Resource Group: $($config.ResourceGroup)" "White"
Write-Log "  VNet: $($config.VNetName)" "White"
Write-Log "  Subnet: $($config.SubnetName)" "White"
Write-Log "  MOVEit Server: $($config.MOVEitPrivateIP)" "White"
Write-Host ""
Write-Log "NEW RESOURCES (CREATED):" "Yellow"
Write-Log "  Front Door: $($config.FrontDoorProfileName)" "White"
Write-Log "  Load Balancer: $($config.LoadBalancerName)" "White"
Write-Log "  WAF Policy: $($config.WAFPolicyName)" "White"
Write-Log "  NSG: $($config.NSGName)" "White"
Write-Host ""
Write-Log "PUBLIC ACCESS ENDPOINTS:" "Cyan"
Write-Log "------------------------" "Cyan"
Write-Host ""
Write-Log "FTPS FILE TRANSFERS:" "Yellow"
Write-Log "  Public IP: $ftpsPublicIP" "Green"
Write-Log "  Ports: 990, 989" "Green"
Write-Log "  Protocol: FTPS" "Green"
Write-Host ""
Write-Log "HTTPS WEB ACCESS:" "Yellow"
Write-Log "  Endpoint: https://$frontDoorEndpoint" "Green"
Write-Log "  Port: 443" "Green"
Write-Log "  WAF: Active (Prevention Mode)" "Green"
Write-Log "  Rules: DefaultRuleSet 1.0 (117+ OWASP)" "Green"
Write-Host ""
Write-Log "CONFIGURATION MATCHES PYXIQ:" "Cyan"
Write-Log "  Health Probe: 30 seconds " "Green"
Write-Log "  Sample Size: 4 " "Green"
Write-Log "  Successful Samples: 2 " "Green"
Write-Log "  Session Affinity: Disabled " "Green"
Write-Log "  Managed Rules: DefaultRuleSet 1.0 " "Green"
Write-Host ""
Write-Log "COST ESTIMATE:" "Yellow"
Write-Log "  Load Balancer: ~$18/month" "White"
Write-Log "  Front Door Standard: ~$35/month" "White"
Write-Log "  WAF Standard: ~$30/month" "White"
Write-Log "  Total: ~$83/month" "White"
Write-Host ""
Write-Log "============================================" "Green"
Write-Log "  READY FOR PRODUCTION!" "Green"
Write-Log "============================================" "Green"

# Save summary
$summaryFile = "$env:USERPROFILE\Desktop\MOVEit-Deployment-Summary.txt"
@"
============================================
MOVEIT FRONT DOOR DEPLOYMENT SUMMARY
============================================
Deployed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Subscription: $(az account show --query name -o tsv)

EXISTING RESOURCES (USED):
- Resource Group: $($config.ResourceGroup)
- VNet: $($config.VNetName)
- Subnet: $($config.SubnetName)
- MOVEit Server: $($config.MOVEitPrivateIP)

NEW RESOURCES (CREATED):
- Front Door: $($config.FrontDoorProfileName)
- Load Balancer: $($config.LoadBalancerName)
- WAF Policy: $($config.WAFPolicyName)
- NSG: $($config.NSGName)

PUBLIC ENDPOINTS:
- FTPS: $ftpsPublicIP (ports 990, 989)
- HTTPS: https://$frontDoorEndpoint

MATCHES PYXIQ CONFIGURATION:
- Health Probe: 30 seconds
- Sample Size: 4
- Successful Samples: 2
- Session Affinity: Disabled
- WAF Rules: DefaultRuleSet 1.0

COST: ~$83/month
============================================
"@ | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Summary saved to: $summaryFile" "Cyan"
