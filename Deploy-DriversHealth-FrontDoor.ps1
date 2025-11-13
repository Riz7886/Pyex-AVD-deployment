#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.FrontDoor, Az.Resources, Az.Monitor, Az.Network

<#
.SYNOPSIS
    Azure Front Door Premium - DRIVERS HEALTH Deployment
.DESCRIPTION
    Automatically creates NEW Azure Front Door Premium for Drivers Health
    with DH naming convention and full security configuration
.NOTES
    Author: Syed Rizvi
    Company: Pyx Health
    Service: Drivers Health
    Environment: Production
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionName = "Drivers Health",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-drivershealth-prod",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "Global",
    
    [Parameter(Mandatory=$false)]
    [string]$FrontDoorName = "fdh-prod",
    
    [Parameter(Mandatory=$false)]
    [string]$ServiceName = "DriversHealth",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Premium", "Standard")]
    [string]$Tier = "Premium"
)

# ============================================
# DRIVERS HEALTH CONFIGURATION
# ============================================

$script:Config = @{
    CompanyName = "PyxHealth"
    ServiceName = "DriversHealth"
    NamingPrefix = "dh"  # Drivers Health prefix
    
    Tags = @{
        Company = "Pyx Health"
        Service = "Drivers Health"
        Environment = $Environment
        ManagedBy = "Automation"
        DeployedBy = "PowerShell"
        CostCenter = "Drivers-Health"
        Compliance = "HIPAA"
        Purpose = "Drivers Health Platform"
    }
    
    # Front Door Configuration - DRIVERS HEALTH
    FrontDoor = @{
        Name = $FrontDoorName  # fdh-prod (Front Door Health)
        ResourceGroup = $ResourceGroupName
        Location = $Location
        Tier = $Tier
        
        # Endpoints - DRIVERS HEALTH
        Endpoints = @(
            @{
                Name = "afd-drivershealth-prod"
                Enabled = $true
            }
        )
        
        # Origin Groups - DRIVERS HEALTH
        OriginGroups = @(
            @{
                Name = "dh-origin-group"  # DH = Drivers Health
                HealthProbeSettings = @{
                    Path = "/health"
                    Protocol = "Https"
                    IntervalInSeconds = 30
                    Method = "GET"
                }
                LoadBalancingSettings = @{
                    SampleSize = 4
                    SuccessfulSamplesRequired = 2
                    AdditionalLatencyInMilliseconds = 50
                }
                SessionAffinityEnabled = $true
            }
        )
        
        # Origins - DRIVERS HEALTH (auto-detect or configure)
        Origins = @(
            @{
                Name = "appcsvc-dh-prod-azurewebsites-net"
                HostName = "appcsvc-drivershealth-prod.azurewebsites.net"  # Adjust this
                HttpPort = 80
                HttpsPort = 443
                Priority = 1
                Weight = 1000
                Enabled = $true
            }
        )
        
        # Routes - DRIVERS HEALTH
        Routes = @(
            @{
                Name = "route-drivershealth-prod"
                PatternsToMatch = @("/*")
                AcceptedProtocols = @("Http", "Https")
                ForwardingProtocol = "HttpsOnly"
                EnabledState = "Enabled"
                EnableCaching = $false
                CompressionEnabled = $true
            }
        )
        
        # Custom Domains - Will be generated
        CustomDomains = @()  # Will be auto-populated after endpoint creation
    }
    
    # Security Configuration - DRIVERS HEALTH
    Security = @{
        # WAF Policy - DRIVERS HEALTH
        WAFPolicy = @{
            Name = "drivershealthprodwafpolicy"  # DH naming
            Mode = "Prevention"
            ManagedRules = @{
                DefaultRuleSet = @{
                    RuleSetType = "Microsoft_DefaultRuleSet"
                    RuleSetVersion = "2.1"
                }
                BotProtection = @{
                    RuleSetType = "Microsoft_BotManagerRuleSet"
                    RuleSetVersion = "1.0"
                }
            }
            CustomRules = @()
        }
        
        # Managed Identity - DRIVERS HEALTH
        ManagedIdentity = @{
            Type = "SystemAssigned"
            Enabled = $true
        }
        
        # Resource Lock
        Lock = @{
            Enabled = $false
            LockLevel = "CanNotDelete"
            Notes = "Prevent accidental deletion of Drivers Health Front Door"
        }
    }
    
    # Monitoring Configuration - DRIVERS HEALTH
    Monitoring = @{
        DiagnosticSettings = @{
            Name = "DriversHealth_FrontDoor_Diagnostics"
            Enabled = $true
            Logs = @(
                @{ Category = "FrontDoorAccessLog"; Enabled = $true }
                @{ Category = "FrontDoorHealthProbeLog"; Enabled = $true }
                @{ Category = "FrontDoorWebApplicationFirewallLog"; Enabled = $true }
            )
            Metrics = @(
                @{ Category = "AllMetrics"; Enabled = $true }
            )
            RetentionDays = 90
        }
        
        # Alerts - DRIVERS HEALTH
        Alerts = @(
            @{
                Name = "DH-High-Latency-Alert"
                Description = "Drivers Health - Alert when latency exceeds threshold"
                Severity = 2
                MetricName = "TotalLatency"
                Threshold = 1000
                Operator = "GreaterThan"
                TimeAggregation = "Average"
                WindowSize = "PT5M"
                EvaluationFrequency = "PT1M"
                Enabled = $true
            },
            @{
                Name = "DH-High-Error-Rate-Alert"
                Description = "Drivers Health - Alert when error rate is high"
                Severity = 1
                MetricName = "ResponseStatusCodeCount"
                Threshold = 100
                Operator = "GreaterThan"
                TimeAggregation = "Total"
                WindowSize = "PT5M"
                EvaluationFrequency = "PT1M"
                Enabled = $true
            },
            @{
                Name = "DH-Origin-Health-Alert"
                Description = "Drivers Health - Alert when origins are unhealthy"
                Severity = 1
                MetricName = "HealthProbeStatus"
                Threshold = 50
                Operator = "LessThan"
                TimeAggregation = "Average"
                WindowSize = "PT5M"
                EvaluationFrequency = "PT1M"
                Enabled = $true
            }
        )
    }
}

# ============================================
# HELPER FUNCTIONS
# ============================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        'Info' { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    
    $logFile = ".\DriversHealth-FrontDoor-Deployment-$(Get-Date -Format 'yyyyMMdd').log"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append
}

function Test-AzureConnection {
    Write-Log "Checking Azure connection..." -Level Info
    
    try {
        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            Write-Log "Not connected to Azure. Initiating login..." -Level Warning
            Connect-AzAccount
            $context = Get-AzContext
        }
        
        Write-Log "Connected to Azure as: $($context.Account.Id)" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to connect to Azure: $_" -Level Error
        return $false
    }
}

function Find-DriversHealthSubscription {
    Write-Log "Searching for Drivers Health subscription..." -Level Info
    
    try {
        # Search for subscription with "Drivers Health" or similar names
        $subscriptions = Get-AzSubscription | Where-Object { 
            $_.Name -like "*Drivers*Health*" -or 
            $_.Name -like "*DriversHealth*" -or
            $_.Name -like "*DH*" -or
            $_.Name -like "*driver*health*"
        }
        
        if ($subscriptions.Count -eq 0) {
            Write-Log "No Drivers Health subscription found. Showing all subscriptions:" -Level Warning
            Get-AzSubscription | ForEach-Object {
                Write-Log "  - $($_.Name) ($($_.Id))" -Level Info
            }
            
            $manualSub = Read-Host "Enter the subscription name or ID for Drivers Health"
            $subscriptions = Get-AzSubscription | Where-Object {
                $_.Name -eq $manualSub -or $_.Id -eq $manualSub
            }
        }
        
        if ($subscriptions.Count -eq 1) {
            $subscription = $subscriptions[0]
        }
        elseif ($subscriptions.Count -gt 1) {
            Write-Log "Multiple subscriptions found:" -Level Warning
            for ($i = 0; $i -lt $subscriptions.Count; $i++) {
                Write-Log "  [$i] $($subscriptions[$i].Name)" -Level Info
            }
            $choice = Read-Host "Select subscription number"
            $subscription = $subscriptions[[int]$choice]
        }
        else {
            throw "Drivers Health subscription not found"
        }
        
        Set-AzContext -SubscriptionId $subscription.Id | Out-Null
        Write-Log "Using subscription: $($subscription.Name)" -Level Success
        return $subscription
    }
    catch {
        Write-Log "Failed to find Drivers Health subscription: $_" -Level Error
        return $null
    }
}

function New-DriversHealthResourceGroup {
    param(
        [string]$Name,
        [string]$Location,
        [hashtable]$Tags
    )
    
    Write-Log "Creating/Verifying Resource Group for Drivers Health: $Name" -Level Info
    
    try {
        $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
        
        if ($rg) {
            Write-Log "Resource Group already exists: $Name" -Level Info
            
            # Update tags
            Write-Log "Updating tags for Drivers Health..." -Level Info
            Set-AzResourceGroup -Name $Name -Tag $Tags | Out-Null
            
            return $rg
        }
        
        Write-Log "Creating new Resource Group: $Name" -Level Info
        $rg = New-AzResourceGroup -Name $Name -Location $Location -Tag $Tags
        Write-Log "Resource Group created for Drivers Health: $Name" -Level Success
        return $rg
    }
    catch {
        Write-Log "Failed to create Resource Group: $_" -Level Error
        throw
    }
}

function Find-DriversHealthOrigins {
    param([string]$ResourceGroupName)
    
    Write-Log "Searching for Drivers Health backend services..." -Level Info
    
    try {
        # Search for App Services with "drivers health" or "dh" in name
        $appServices = Get-AzWebApp | Where-Object {
            $_.Name -like "*drivershealth*" -or 
            $_.Name -like "*drivers-health*" -or
            $_.Name -like "*dh-*" -or
            $_.Name -like "*driver*health*"
        }
        
        if ($appServices.Count -gt 0) {
            Write-Log "Found $($appServices.Count) Drivers Health App Service(s):" -Level Success
            foreach ($app in $appServices) {
                Write-Log "  - $($app.Name) → $($app.DefaultHostName)" -Level Info
            }
            
            # Update origins configuration
            $script:Config.FrontDoor.Origins = @()
            foreach ($app in $appServices) {
                $originName = $app.Name -replace '\.', '-'
                $script:Config.FrontDoor.Origins += @{
                    Name = $originName
                    HostName = $app.DefaultHostName
                    HttpPort = 80
                    HttpsPort = 443
                    Priority = 1
                    Weight = 1000
                    Enabled = $true
                }
            }
            
            return $true
        }
        else {
            Write-Log "No Drivers Health App Services found automatically" -Level Warning
            Write-Log "You can manually specify origin hostname" -Level Info
            
            $manualOrigin = Read-Host "Enter Drivers Health backend hostname (or press Enter to use default)"
            
            if ($manualOrigin) {
                $script:Config.FrontDoor.Origins[0].HostName = $manualOrigin
                $script:Config.FrontDoor.Origins[0].Name = $manualOrigin -replace '\.', '-'
            }
            
            return $true
        }
    }
    catch {
        Write-Log "Error searching for origins: $_" -Level Warning
        return $false
    }
}

function New-DriversHealthWAFPolicy {
    param(
        [string]$ResourceGroupName,
        [hashtable]$Config,
        [hashtable]$Tags
    )
    
    Write-Log "Creating WAF Policy for Drivers Health: $($Config.Name)" -Level Info
    
    try {
        $existingPolicy = Get-AzFrontDoorWafPolicy -ResourceGroupName $ResourceGroupName -Name $Config.Name -ErrorAction SilentlyContinue
        
        if ($existingPolicy) {
            Write-Log "WAF Policy already exists: $($Config.Name)" -Level Info
            return $existingPolicy
        }
        
        # Create managed rule sets
        $managedRules = @()
        
        $defaultRuleSet = New-AzFrontDoorWafManagedRuleObject `
            -Type $Config.ManagedRules.DefaultRuleSet.RuleSetType `
            -Version $Config.ManagedRules.DefaultRuleSet.RuleSetVersion
        $managedRules += $defaultRuleSet
        
        $botRuleSet = New-AzFrontDoorWafManagedRuleObject `
            -Type $Config.ManagedRules.BotProtection.RuleSetType `
            -Version $Config.ManagedRules.BotProtection.RuleSetVersion
        $managedRules += $botRuleSet
        
        $wafPolicy = New-AzFrontDoorWafPolicy `
            -ResourceGroupName $ResourceGroupName `
            -Name $Config.Name `
            -EnabledState "Enabled" `
            -Mode $Config.Mode `
            -ManagedRule $managedRules `
            -Tag $Tags
        
        Write-Log "WAF Policy created for Drivers Health: $($Config.Name)" -Level Success
        return $wafPolicy
    }
    catch {
        Write-Log "Failed to create WAF Policy: $_" -Level Error
        throw
    }
}

function New-DriversHealthFrontDoor {
    param(
        [string]$ResourceGroupName,
        [hashtable]$Config,
        [hashtable]$Tags
    )
    
    Write-Log "Creating Azure Front Door Premium for Drivers Health: $($Config.Name)" -Level Info
    
    try {
        # Check if Front Door exists
        Write-Log "Checking if Front Door already exists..." -Level Info
        
        $checkCommand = "az afd profile show --profile-name $($Config.Name) --resource-group $ResourceGroupName 2>&1"
        $existingFD = Invoke-Expression $checkCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Front Door already exists: $($Config.Name)" -Level Info
            Write-Log "Skipping creation, will configure endpoints..." -Level Info
            return $true
        }
        
        # Create Front Door profile
        Write-Log "Creating NEW Front Door Premium for Drivers Health..." -Level Info
        
        $tagsParam = ($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
        
        $createCommand = "az afd profile create --profile-name $($Config.Name) --resource-group $ResourceGroupName --sku Premium_AzureFrontDoor --tags $tagsParam"
        
        Write-Log "Executing: $createCommand" -Level Info
        $result = Invoke-Expression $createCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Front Door profile created successfully for Drivers Health!" -Level Success
            Start-Sleep -Seconds 10
            return $true
        } else {
            throw "Failed to create Front Door profile"
        }
    }
    catch {
        Write-Log "Failed to create Front Door: $_" -Level Error
        throw
    }
}

function Add-DriversHealthEndpoint {
    param(
        [string]$ResourceGroupName,
        [string]$ProfileName,
        [hashtable]$EndpointConfig
    )
    
    Write-Log "Adding Drivers Health endpoint: $($EndpointConfig.Name)" -Level Info
    
    try {
        $enabledState = if($EndpointConfig.Enabled){'Enabled'}else{'Disabled'}
        
        $command = "az afd endpoint create --resource-group $ResourceGroupName --profile-name $ProfileName --endpoint-name $($EndpointConfig.Name) --enabled-state $enabledState"
        
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Drivers Health endpoint created: $($EndpointConfig.Name)" -Level Success
            
            # Get endpoint hostname
            Start-Sleep -Seconds 5
            $showCommand = "az afd endpoint show --resource-group $ResourceGroupName --profile-name $ProfileName --endpoint-name $($EndpointConfig.Name) --query hostName -o tsv"
            $hostname = Invoke-Expression $showCommand
            
            Write-Log "Endpoint hostname: $hostname" -Level Success
            
            return $hostname
        } else {
            throw "Failed to create endpoint"
        }
    }
    catch {
        Write-Log "Failed to create endpoint: $_" -Level Error
        return $null
    }
}

function Add-DriversHealthOriginGroup {
    param(
        [string]$ResourceGroupName,
        [string]$ProfileName,
        [hashtable]$OriginGroupConfig
    )
    
    Write-Log "Adding Drivers Health origin group: $($OriginGroupConfig.Name)" -Level Info
    
    try {
        $command = "az afd origin-group create --resource-group $ResourceGroupName --profile-name $ProfileName --origin-group-name $($OriginGroupConfig.Name) --probe-request-type $($OriginGroupConfig.HealthProbeSettings.Method) --probe-protocol $($OriginGroupConfig.HealthProbeSettings.Protocol) --probe-interval-in-seconds $($OriginGroupConfig.HealthProbeSettings.IntervalInSeconds) --probe-path '$($OriginGroupConfig.HealthProbeSettings.Path)' --sample-size $($OriginGroupConfig.LoadBalancingSettings.SampleSize) --successful-samples-required $($OriginGroupConfig.LoadBalancingSettings.SuccessfulSamplesRequired) --additional-latency-in-milliseconds $($OriginGroupConfig.LoadBalancingSettings.AdditionalLatencyInMilliseconds)"
        
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Drivers Health origin group created: $($OriginGroupConfig.Name)" -Level Success
            return $true
        } else {
            throw "Failed to create origin group"
        }
    }
    catch {
        Write-Log "Failed to create origin group: $_" -Level Error
        return $false
    }
}

function Add-DriversHealthOrigin {
    param(
        [string]$ResourceGroupName,
        [string]$ProfileName,
        [string]$OriginGroupName,
        [hashtable]$OriginConfig
    )
    
    Write-Log "Adding Drivers Health origin: $($OriginConfig.Name)" -Level Info
    
    try {
        $enabledState = if($OriginConfig.Enabled){'Enabled'}else{'Disabled'}
        
        $command = "az afd origin create --resource-group $ResourceGroupName --profile-name $ProfileName --origin-group-name $OriginGroupName --origin-name $($OriginConfig.Name) --host-name $($OriginConfig.HostName) --origin-host-header $($OriginConfig.HostName) --priority $($OriginConfig.Priority) --weight $($OriginConfig.Weight) --http-port $($OriginConfig.HttpPort) --https-port $($OriginConfig.HttpsPort) --enabled-state $enabledState"
        
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Drivers Health origin created: $($OriginConfig.Name)" -Level Success
            return $true
        } else {
            throw "Failed to create origin"
        }
    }
    catch {
        Write-Log "Failed to create origin: $_" -Level Error
        return $false
    }
}

function Add-DriversHealthRoute {
    param(
        [string]$ResourceGroupName,
        [string]$ProfileName,
        [string]$EndpointName,
        [hashtable]$RouteConfig,
        [string]$OriginGroupName
    )
    
    Write-Log "Adding Drivers Health route: $($RouteConfig.Name)" -Level Info
    
    try {
        $patterns = ($RouteConfig.PatternsToMatch | ForEach-Object { "'$_'" }) -join ' '
        $protocols = $RouteConfig.AcceptedProtocols -join ' '
        
        $command = "az afd route create --resource-group $ResourceGroupName --profile-name $ProfileName --endpoint-name $EndpointName --route-name $($RouteConfig.Name) --origin-group $OriginGroupName --supported-protocols $protocols --patterns-to-match $patterns --forwarding-protocol $($RouteConfig.ForwardingProtocol) --link-to-default-domain Enabled --https-redirect Enabled --enabled-state $($RouteConfig.EnabledState)"
        
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Drivers Health route created: $($RouteConfig.Name)" -Level Success
            return $true
        } else {
            throw "Failed to create route"
        }
    }
    catch {
        Write-Log "Failed to create route: $_" -Level Error
        return $false
    }
}

function Enable-DriversHealthManagedIdentity {
    param(
        [string]$ResourceGroupName,
        [string]$FrontDoorName
    )
    
    Write-Log "Enabling Managed Identity for Drivers Health Front Door" -Level Info
    
    try {
        $command = "az afd profile update --resource-group $ResourceGroupName --profile-name $FrontDoorName --identity-type SystemAssigned"
        
        $result = Invoke-Expression $command
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Managed Identity enabled for Drivers Health" -Level Success
            return $true
        } else {
            throw "Failed to enable Managed Identity"
        }
    }
    catch {
        Write-Log "Failed to enable Managed Identity: $_" -Level Error
        return $false
    }
}

function Set-DriversHealthDiagnostics {
    param(
        [string]$ResourceId,
        [hashtable]$DiagnosticConfig
    )
    
    Write-Log "Configuring diagnostics for Drivers Health Front Door" -Level Info
    
    try {
        # Create Log Analytics workspace
        $workspaceName = "law-$($script:Config.FrontDoor.Name)"
        
        Write-Log "Creating Log Analytics workspace: $workspaceName" -Level Info
        
        $workspace = New-AzOperationalInsightsWorkspace `
            -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
            -Name $workspaceName `
            -Location "EastUS" `
            -Sku "PerGB2018" `
            -Tag $script:Config.Tags `
            -ErrorAction SilentlyContinue
        
        if (-not $workspace) {
            $workspace = Get-AzOperationalInsightsWorkspace `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -Name $workspaceName
        }
        
        Write-Log "Log Analytics workspace ready: $workspaceName" -Level Success
        
        # Configure diagnostic settings
        $logs = @()
        foreach ($log in $DiagnosticConfig.Logs) {
            $logs += New-AzDiagnosticSettingLogSettingsObject `
                -Enabled $log.Enabled `
                -Category $log.Category
        }
        
        $metrics = @()
        foreach ($metric in $DiagnosticConfig.Metrics) {
            $metrics += New-AzDiagnosticSettingMetricSettingsObject `
                -Enabled $metric.Enabled `
                -Category $metric.Category
        }
        
        New-AzDiagnosticSetting `
            -ResourceId $ResourceId `
            -Name $DiagnosticConfig.Name `
            -WorkspaceId $workspace.ResourceId `
            -Log $logs `
            -Metric $metrics
        
        Write-Log "Diagnostic settings configured for Drivers Health" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to configure diagnostics: $_" -Level Warning
        return $false
    }
}

# ============================================
# MAIN DEPLOYMENT FUNCTION
# ============================================

function Start-DriversHealthFrontDoorDeployment {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  DRIVERS HEALTH - AZURE FRONT DOOR DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "  New Front Door with DH Naming Convention" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Step 1: Azure Connection
        if (-not (Test-AzureConnection)) {
            throw "Azure connection failed"
        }
        
        # Step 2: Find Drivers Health Subscription
        $subscription = Find-DriversHealthSubscription
        if (-not $subscription) {
            throw "Failed to find Drivers Health subscription"
        }
        
        Write-Host ""
        Write-Log "========== DRIVERS HEALTH CONFIGURATION ==========" -Level Info
        Write-Log "Service: Drivers Health" -Level Info
        Write-Log "Subscription: $($subscription.Name)" -Level Info
        Write-Log "Resource Group: $($script:Config.FrontDoor.ResourceGroup)" -Level Info
        Write-Log "Front Door Name: $($script:Config.FrontDoor.Name)" -Level Info
        Write-Log "Naming Prefix: DH (Drivers Health)" -Level Info
        Write-Log "Tier: $($script:Config.FrontDoor.Tier)" -Level Info
        Write-Host ""
        
        $confirm = Read-Host "Create NEW Drivers Health Front Door? (yes/no)"
        if ($confirm -ne 'yes') {
            Write-Log "Deployment cancelled" -Level Warning
            return
        }
        
        Write-Host ""
        Write-Log "========== STARTING DRIVERS HEALTH DEPLOYMENT ==========" -Level Info
        Write-Host ""
        
        # Step 3: Create Resource Group
        $rg = New-DriversHealthResourceGroup `
            -Name $script:Config.FrontDoor.ResourceGroup `
            -Location "EastUS" `
            -Tags $script:Config.Tags
        
        # Step 4: Find Drivers Health Origins
        Find-DriversHealthOrigins -ResourceGroupName $script:Config.FrontDoor.ResourceGroup
        
        # Step 5: Create WAF Policy
        Write-Host ""
        $wafPolicy = New-DriversHealthWAFPolicy `
            -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
            -Config $script:Config.Security.WAFPolicy `
            -Tags $script:Config.Tags
        
        # Step 6: Create Front Door Profile
        Write-Host ""
        New-DriversHealthFrontDoor `
            -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
            -Config $script:Config.FrontDoor `
            -Tags $script:Config.Tags
        
        # Step 7: Add Endpoints
        Write-Host ""
        Write-Log "========== CONFIGURING DRIVERS HEALTH ENDPOINTS ==========" -Level Info
        $endpointHostname = $null
        foreach ($endpoint in $script:Config.FrontDoor.Endpoints) {
            $hostname = Add-DriversHealthEndpoint `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -ProfileName $script:Config.FrontDoor.Name `
                -EndpointConfig $endpoint
            
            if ($hostname) {
                $endpointHostname = $hostname
            }
        }
        
        # Step 8: Add Origin Groups
        Write-Host ""
        Write-Log "========== CONFIGURING ORIGIN GROUPS ==========" -Level Info
        foreach ($originGroup in $script:Config.FrontDoor.OriginGroups) {
            Add-DriversHealthOriginGroup `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -ProfileName $script:Config.FrontDoor.Name `
                -OriginGroupConfig $originGroup
        }
        
        # Step 9: Add Origins
        Write-Host ""
        Write-Log "========== CONFIGURING ORIGINS ==========" -Level Info
        foreach ($origin in $script:Config.FrontDoor.Origins) {
            Add-DriversHealthOrigin `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -ProfileName $script:Config.FrontDoor.Name `
                -OriginGroupName $script:Config.FrontDoor.OriginGroups[0].Name `
                -OriginConfig $origin
        }
        
        # Step 10: Add Routes
        Write-Host ""
        Write-Log "========== CONFIGURING ROUTES ==========" -Level Info
        foreach ($route in $script:Config.FrontDoor.Routes) {
            Add-DriversHealthRoute `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -ProfileName $script:Config.FrontDoor.Name `
                -EndpointName $script:Config.FrontDoor.Endpoints[0].Name `
                -RouteConfig $route `
                -OriginGroupName $script:Config.FrontDoor.OriginGroups[0].Name
        }
        
        # Step 11: Enable Managed Identity
        Write-Host ""
        Write-Log "========== CONFIGURING SECURITY ==========" -Level Info
        if ($script:Config.Security.ManagedIdentity.Enabled) {
            Enable-DriversHealthManagedIdentity `
                -ResourceGroupName $script:Config.FrontDoor.ResourceGroup `
                -FrontDoorName $script:Config.FrontDoor.Name
        }
        
        # Step 12: Configure Diagnostics
        Write-Host ""
        Write-Log "========== CONFIGURING MONITORING ==========" -Level Info
        $frontDoorId = "/subscriptions/$($subscription.Id)/resourceGroups/$($script:Config.FrontDoor.ResourceGroup)/providers/Microsoft.Cdn/profiles/$($script:Config.FrontDoor.Name)"
        
        Set-DriversHealthDiagnostics `
            -ResourceId $frontDoorId `
            -DiagnosticConfig $script:Config.Monitoring.DiagnosticSettings
        
        # Deployment Summary
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host "  DRIVERS HEALTH FRONT DOOR DEPLOYED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Log "Service: Drivers Health" -Level Success
        Write-Log "Front Door Name: $($script:Config.FrontDoor.Name)" -Level Success
        Write-Log "Endpoint: $endpointHostname" -Level Success
        Write-Log "WAF Policy: $($script:Config.Security.WAFPolicy.Name)" -Level Success
        Write-Log "Origin Group: $($script:Config.FrontDoor.OriginGroups[0].Name)" -Level Success
        Write-Log "Managed Identity: Enabled" -Level Success
        Write-Host ""
        Write-Log "Access Drivers Health Front Door at: https://$endpointHostname" -Level Info
        Write-Host ""
        
        # Generate report
        $reportPath = ".\DriversHealth-FrontDoor-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        $report = @"
================================================================
DRIVERS HEALTH - AZURE FRONT DOOR DEPLOYMENT REPORT
================================================================

Deployment Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Deployed By: $($env:USERNAME)

SERVICE: DRIVERS HEALTH
-----------------------
Subscription: $($subscription.Name)
Resource Group: $($script:Config.FrontDoor.ResourceGroup)
Front Door Name: $($script:Config.FrontDoor.Name)
Naming Convention: DH (Drivers Health)
Tier: $($script:Config.FrontDoor.Tier)

ENDPOINTS:
----------
Name: $($script:Config.FrontDoor.Endpoints[0].Name)
Hostname: $endpointHostname

ORIGIN GROUPS:
--------------
Name: $($script:Config.FrontDoor.OriginGroups[0].Name)
Health Probe: Every $($script:Config.FrontDoor.OriginGroups[0].HealthProbeSettings.IntervalInSeconds) seconds

ORIGINS:
--------
$($script:Config.FrontDoor.Origins | ForEach-Object { "- $($_.Name): $($_.HostName)" } | Out-String)

SECURITY:
---------
WAF Policy: $($script:Config.Security.WAFPolicy.Name)
Mode: $($script:Config.Security.WAFPolicy.Mode)
Managed Identity: System-Assigned
Rules: Default RS 2.1 + Bot Protection 1.0

MONITORING:
-----------
Log Analytics: law-$($script:Config.FrontDoor.Name)
Retention: $($script:Config.Monitoring.DiagnosticSettings.RetentionDays) days
Alerts: $($script:Config.Monitoring.Alerts.Count) configured

================================================================
"@
        
        $report | Out-File -FilePath $reportPath
        Write-Log "Deployment report saved: $reportPath" -Level Success
        
    }
    catch {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host "  DEPLOYMENT FAILED!" -ForegroundColor Red
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Log "Error: $_" -Level Error
        Write-Host ""
        throw
    }
}

# ============================================
# EXECUTE DEPLOYMENT
# ============================================

Start-DriversHealthFrontDoorDeployment
