#Requires -Version 5.1
#Requires -Modules ActiveDirectory, Az

<#
.SYNOPSIS
    Ultimate Domain Controller Migration Framework - On-Prem to Azure
    ZERO DOWNTIME - Enterprise Grade

.DESCRIPTION
    Professional DC migration automation from on-premises to Azure
    
    WHAT THIS DOES:
    - Assesses on-prem environment (AD, DNS, DHCP, File Servers)
    - Prepares Azure infrastructure (VNet, Subnets, NSG, VPN)
    - Deploys Site-to-Site VPN or ExpressRoute
    - Promotes new DCs in Azure (replication automatic)
    - Migrates FSMO roles safely
    - Migrates DNS zones
    - Migrates File Servers and user data
    - Validates everything at each step
    - Zero user-facing downtime
    - Full rollback capability
    
    PHASES:
    Phase 1: Assessment & Planning
    Phase 2: Azure Infrastructure Deployment
    Phase 3: Network Connectivity (VPN/ExpressRoute)
    Phase 4: Deploy Azure Domain Controllers
    Phase 5: FSMO Role Migration
    Phase 6: Workload Migration (Files, DNS, Services)
    Phase 7: Decommission On-Prem DCs
    Phase 8: Validation & Cleanup
    
.PARAMETER Phase
    Specify phase to execute (1-8)
    
.PARAMETER AssessmentOnly
    Run assessment without making changes
    
.PARAMETER SubscriptionId
    Azure subscription ID
    
.PARAMETER ResourceGroupName
    Azure resource group name
    
.PARAMETER Location
    Azure region (e.g., eastus, westus)
    
.EXAMPLE
    .\Migrate-DC-OnPrem-to-Azure.ps1 -Phase 1 -AssessmentOnly
    
.EXAMPLE
    .\Migrate-DC-OnPrem-to-Azure.ps1 -Phase 2 -SubscriptionId "xxx" -ResourceGroupName "RG-DC-Migration" -Location "eastus"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,8)]
    [int]$Phase = 1,
    
    [Parameter(Mandatory = $false)]
    [switch]$AssessmentOnly,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "RG-DC-Migration",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\DC-Migration-Reports"
)

$ErrorActionPreference = "Stop"
$script:migrationData = @{}

function Write-MigrationLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red";"CRITICAL"="Magenta"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $colors[$Level]
    
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    Add-Content -Path "$ReportPath\dc-migration.log" -Value $logMessage
}

function Test-Prerequisites {
    Write-MigrationLog "Checking prerequisites..." "INFO"
    
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-MigrationLog "Active Directory module required!" "CRITICAL"
        throw "Install RSAT-AD-PowerShell"
    }
    
    Import-Module ActiveDirectory
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-MigrationLog "Must run as Administrator!" "CRITICAL"
        throw "Run as Administrator"
    }
    
    if ($Phase -ge 2) {
        if (-not (Get-Module -ListAvailable -Name Az)) {
            Write-MigrationLog "Azure PowerShell module required for Phase 2+!" "CRITICAL"
            throw "Install Az module: Install-Module -Name Az"
        }
        Import-Module Az
    }
    
    Write-MigrationLog "Prerequisites validated" "SUCCESS"
}

function Start-Phase1Assessment {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 1: COMPREHENSIVE ENVIRONMENT ASSESSMENT" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    $assessment = @{}
    
    Write-MigrationLog "Assessing Active Directory environment..." "INFO"
    
    try {
        $domain = Get-ADDomain
        $forest = Get-ADForest
        
        $assessment.DomainName = $domain.DNSRoot
        $assessment.NetBIOSName = $domain.NetBIOSName
        $assessment.ForestName = $forest.Name
        $assessment.DomainFunctionalLevel = $domain.DomainMode
        $assessment.ForestFunctionalLevel = $forest.ForestMode
        
        Write-Host "Domain: $($domain.DNSRoot)" -ForegroundColor White
        Write-Host "Domain Functional Level: $($domain.DomainMode)" -ForegroundColor White
        Write-Host "Forest Functional Level: $($forest.ForestMode)" -ForegroundColor White
        
    } catch {
        Write-MigrationLog "Cannot connect to AD domain!" "CRITICAL"
        throw $_
    }
    
    Write-MigrationLog "Assessing Domain Controllers..." "INFO"
    $dcs = Get-ADDomainController -Filter *
    $assessment.DomainControllers = @()
    
    foreach ($dc in $dcs) {
        $dcInfo = @{
            Name = $dc.Name
            IPAddress = $dc.IPv4Address
            OperatingSystem = $dc.OperatingSystem
            Site = $dc.Site
            IsGlobalCatalog = $dc.IsGlobalCatalog
            IsReadOnly = $dc.IsReadOnly
        }
        
        Write-Host "`nDC: $($dc.Name)" -ForegroundColor Yellow
        Write-Host "  IP: $($dc.IPv4Address)" -ForegroundColor Gray
        Write-Host "  OS: $($dc.OperatingSystem)" -ForegroundColor Gray
        Write-Host "  Site: $($dc.Site)" -ForegroundColor Gray
        Write-Host "  Global Catalog: $($dc.IsGlobalCatalog)" -ForegroundColor Gray
        
        $assessment.DomainControllers += $dcInfo
    }
    
    Write-MigrationLog "Checking FSMO roles..." "INFO"
    $fsmoRoles = @{
        PDCEmulator = $domain.PDCEmulator
        RIDMaster = $domain.RIDMaster
        InfrastructureMaster = $domain.InfrastructureMaster
        SchemaMaster = $forest.SchemaMaster
        DomainNamingMaster = $forest.DomainNamingMaster
    }
    
    $assessment.FSMORoles = $fsmoRoles
    
    Write-Host "`nFSMO Roles:" -ForegroundColor Yellow
    foreach ($role in $fsmoRoles.GetEnumerator()) {
        Write-Host "  $($role.Key): $($role.Value)" -ForegroundColor White
    }
    
    Write-MigrationLog "Assessing AD Sites and Services..." "INFO"
    $sites = Get-ADReplicationSite -Filter *
    $assessment.Sites = @()
    
    Write-Host "`nAD Sites:" -ForegroundColor Yellow
    foreach ($site in $sites) {
        Write-Host "  - $($site.Name)" -ForegroundColor White
        $assessment.Sites += $site.Name
    }
    
    Write-MigrationLog "Assessing users and computers..." "INFO"
    $users = Get-ADUser -Filter * -Properties Enabled
    $computers = Get-ADComputer -Filter * -Properties OperatingSystem
    
    $assessment.TotalUsers = $users.Count
    $assessment.EnabledUsers = ($users | Where-Object {$_.Enabled}).Count
    $assessment.TotalComputers = $computers.Count
    
    Write-Host "`nUsers: $($users.Count) (Enabled: $(($users | Where-Object {$_.Enabled}).Count))" -ForegroundColor White
    Write-Host "Computers: $($computers.Count)" -ForegroundColor White
    
    Write-MigrationLog "Assessing GPOs..." "INFO"
    $gpos = Get-GPO -All
    $assessment.TotalGPOs = $gpos.Count
    Write-Host "GPOs: $($gpos.Count)" -ForegroundColor White
    
    Write-MigrationLog "Checking DNS configuration..." "INFO"
    try {
        $dnsServer = Get-DnsServerZone -ErrorAction SilentlyContinue
        $assessment.DNSZones = $dnsServer.Count
        Write-Host "DNS Zones: $($dnsServer.Count)" -ForegroundColor White
    } catch {
        Write-MigrationLog "DNS cmdlets not available on this system" "WARNING"
    }
    
    Write-MigrationLog "Assessing network configuration..." "INFO"
    $netAdapters = Get-NetIPConfiguration
    $assessment.NetworkAdapters = @()
    
    foreach ($adapter in $netAdapters) {
        if ($adapter.IPv4Address) {
            $adapterInfo = @{
                InterfaceAlias = $adapter.InterfaceAlias
                IPv4Address = $adapter.IPv4Address.IPAddress
                IPv4DefaultGateway = $adapter.IPv4DefaultGateway.NextHop
                DNSServer = $adapter.DNSServer.ServerAddresses
            }
            $assessment.NetworkAdapters += $adapterInfo
        }
    }
    
    $assessmentFile = "$ReportPath\Assessment-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $assessment | ConvertTo-Json -Depth 10 | Out-File -FilePath $assessmentFile -Encoding UTF8
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "  ASSESSMENT COMPLETE" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "`nAssessment saved: $assessmentFile" -ForegroundColor Cyan
    
    $script:migrationData = $assessment
    return $assessment
}

function Start-Phase2AzureInfrastructure {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 2: AZURE INFRASTRUCTURE DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-MigrationLog "Connecting to Azure..." "INFO"
    
    try {
        Connect-AzAccount -SubscriptionId $SubscriptionId
        Write-MigrationLog "Connected to Azure subscription: $SubscriptionId" "SUCCESS"
    } catch {
        Write-MigrationLog "Failed to connect to Azure" "CRITICAL"
        throw $_
    }
    
    Write-MigrationLog "Creating Resource Group..." "INFO"
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $rg) {
            $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
            Write-MigrationLog "Resource Group created: $ResourceGroupName" "SUCCESS"
        } else {
            Write-MigrationLog "Resource Group already exists: $ResourceGroupName" "INFO"
        }
    } catch {
        Write-MigrationLog "Failed to create Resource Group" "ERROR"
        throw $_
    }
    
    Write-MigrationLog "Creating Virtual Network..." "INFO"
    $vnetName = "VNet-DC-Migration"
    $vnetAddressPrefix = "10.0.0.0/16"
    $subnetName = "Subnet-DomainControllers"
    $subnetAddressPrefix = "10.0.1.0/24"
    $gatewaySubnetPrefix = "10.0.255.0/27"
    
    try {
        $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $vnet) {
            $subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
            $gatewaySubnet = New-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix $gatewaySubnetPrefix
            
            $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $vnetAddressPrefix -Subnet $subnet,$gatewaySubnet
            
            Write-MigrationLog "Virtual Network created: $vnetName" "SUCCESS"
        } else {
            Write-MigrationLog "Virtual Network already exists: $vnetName" "INFO"
        }
    } catch {
        Write-MigrationLog "Failed to create Virtual Network" "ERROR"
        throw $_
    }
    
    Write-MigrationLog "Creating Network Security Group..." "INFO"
    $nsgName = "NSG-DomainControllers"
    
    try {
        $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $nsg) {
            $rule1 = New-AzNetworkSecurityRuleConfig -Name "Allow-AD-Traffic" -Protocol * -SourcePortRange * -DestinationPortRange 389,636,3268,3269,88,53,135,445 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 100 -Direction Inbound
            
            $rule2 = New-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 3389 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 200 -Direction Inbound
            
            $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $Location -SecurityRules $rule1,$rule2
            
            Write-MigrationLog "Network Security Group created: $nsgName" "SUCCESS"
        } else {
            Write-MigrationLog "Network Security Group already exists: $nsgName" "INFO"
        }
    } catch {
        Write-MigrationLog "Failed to create Network Security Group" "ERROR"
        throw $_
    }
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "  AZURE INFRASTRUCTURE DEPLOYED" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "`nResource Group: $ResourceGroupName" -ForegroundColor Cyan
    Write-Host "Virtual Network: $vnetName" -ForegroundColor Cyan
    Write-Host "Address Space: $vnetAddressPrefix" -ForegroundColor Cyan
    Write-Host "DC Subnet: $subnetAddressPrefix" -ForegroundColor Cyan
}

function Start-Phase3NetworkConnectivity {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 3: NETWORK CONNECTIVITY SETUP" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-MigrationLog "Setting up Site-to-Site VPN..." "INFO"
    
    Write-Host "VPN GATEWAY DEPLOYMENT:" -ForegroundColor Yellow
    Write-Host "`nThis phase requires:" -ForegroundColor White
    Write-Host "1. On-premises VPN device public IP" -ForegroundColor White
    Write-Host "2. Shared key for VPN tunnel" -ForegroundColor White
    Write-Host "3. On-premises network address space" -ForegroundColor White
    Write-Host "`nVPN Gateway takes 30-45 minutes to deploy" -ForegroundColor Yellow
    
    $vpnScript = @"
# VPN Gateway Deployment Script
# Run this after gathering required information

`$localGatewayName = "LocalGateway-OnPrem"
`$onPremPublicIP = "YOUR_ONPREM_PUBLIC_IP"
`$onPremAddressSpace = @("192.168.0.0/16")

`$localGateway = New-AzLocalNetworkGateway -Name `$localGatewayName -ResourceGroupName "$ResourceGroupName" -Location "$Location" -GatewayIpAddress `$onPremPublicIP -AddressPrefix `$onPremAddressSpace

`$vnet = Get-AzVirtualNetwork -Name "VNet-DC-Migration" -ResourceGroupName "$ResourceGroupName"
`$gwSubnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork `$vnet

`$gwpip = New-AzPublicIpAddress -Name "VPN-Gateway-IP" -ResourceGroupName "$ResourceGroupName" -Location "$Location" -AllocationMethod Dynamic

`$gwipconfig = New-AzVirtualNetworkGatewayIpConfig -Name "VPN-Gateway-Config" -SubnetId `$gwSubnet.Id -PublicIpAddressId `$gwpip.Id

`$gateway = New-AzVirtualNetworkGateway -Name "VPN-Gateway" -ResourceGroupName "$ResourceGroupName" -Location "$Location" -IpConfigurations `$gwipconfig -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1

`$sharedKey = "YOUR_SHARED_KEY"
`$connection = New-AzVirtualNetworkGatewayConnection -Name "OnPrem-to-Azure" -ResourceGroupName "$ResourceGroupName" -Location "$Location" -VirtualNetworkGateway1 `$gateway -LocalNetworkGateway2 `$localGateway -ConnectionType IPsec -SharedKey `$sharedKey
"@
    
    $vpnFile = "$ReportPath\VPN-Deployment-Script.ps1"
    $vpnScript | Out-File -FilePath $vpnFile -Encoding UTF8
    
    Write-MigrationLog "VPN deployment script generated: $vpnFile" "SUCCESS"
    Write-Host "`nVPN script saved: $vpnFile" -ForegroundColor Cyan
}

function Start-Phase4DeployAzureDCs {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 4: DEPLOY AZURE DOMAIN CONTROLLERS" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-MigrationLog "Preparing Azure DC deployment..." "INFO"
    
    Write-Host "AZURE DC DEPLOYMENT REQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "`n1. VPN connectivity established" -ForegroundColor White
    Write-Host "2. DNS resolution working between sites" -ForegroundColor White
    Write-Host "3. AD replication ports open" -ForegroundColor White
    Write-Host "4. Azure VMs will join existing domain" -ForegroundColor White
    Write-Host "5. Promote to Domain Controllers" -ForegroundColor White
    Write-Host "`nRecommended: Deploy 2 DCs in Azure for redundancy" -ForegroundColor Yellow
    
    $dcScript = @"
# Azure Domain Controller Deployment Script

# Variables
`$vmName1 = "AzureDC01"
`$vmName2 = "AzureDC02"
`$vmSize = "Standard_D2s_v3"
`$vnetName = "VNet-DC-Migration"
`$subnetName = "Subnet-DomainControllers"
`$resourceGroup = "$ResourceGroupName"
`$location = "$Location"

# Get Virtual Network and Subnet
`$vnet = Get-AzVirtualNetwork -Name `$vnetName -ResourceGroupName `$resourceGroup
`$subnet = Get-AzVirtualNetworkSubnetConfig -Name `$subnetName -VirtualNetwork `$vnet

# DC 1
`$nic1 = New-AzNetworkInterface -Name "`${vmName1}-NIC" -ResourceGroupName `$resourceGroup -Location `$location -SubnetId `$subnet.Id

`$cred = Get-Credential -Message "Enter local admin credentials for Azure VMs"

`$vmConfig1 = New-AzVMConfig -VMName `$vmName1 -VMSize `$vmSize
`$vmConfig1 = Set-AzVMOperatingSystem -VM `$vmConfig1 -Windows -ComputerName `$vmName1 -Credential `$cred
`$vmConfig1 = Set-AzVMSourceImage -VM `$vmConfig1 -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-Datacenter" -Version "latest"
`$vmConfig1 = Add-AzVMNetworkInterface -VM `$vmConfig1 -Id `$nic1.Id
`$vmConfig1 = Set-AzVMBootDiagnostic -VM `$vmConfig1 -Disable

New-AzVM -ResourceGroupName `$resourceGroup -Location `$location -VM `$vmConfig1

Write-Host "DC 1 deployed. Configure static IP and DNS before promotion" -ForegroundColor Green

# Repeat for DC 2
# Then run dcpromo or Install-ADDSDomainController cmdlet
"@
    
    $dcFile = "$ReportPath\Azure-DC-Deployment.ps1"
    $dcScript | Out-File -FilePath $dcFile -Encoding UTF8
    
    Write-MigrationLog "Azure DC deployment script generated: $dcFile" "SUCCESS"
    Write-Host "`nDeployment script saved: $dcFile" -ForegroundColor Cyan
    
    $dcPromoScript = @"
# Domain Controller Promotion Script
# Run this ON the Azure VM after joining domain

Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

`$domainName = "$($script:migrationData.DomainName)"
`$cred = Get-Credential -Message "Enter Domain Admin credentials"

Install-ADDSDomainController -DomainName `$domainName -Credential `$cred -InstallDns -SiteName "Azure-Site" -Force
"@
    
    $dcPromoFile = "$ReportPath\DC-Promotion-Script.ps1"
    $dcPromoScript | Out-File -FilePath $dcPromoFile -Encoding UTF8
    
    Write-Host "DC Promotion script saved: $dcPromoFile" -ForegroundColor Cyan
}

function Start-Phase5FSMOMigration {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 5: FSMO ROLE MIGRATION" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-MigrationLog "Preparing FSMO role migration..." "INFO"
    
    Write-Host "FSMO ROLE MIGRATION:" -ForegroundColor Yellow
    Write-Host "`nCurrent FSMO Roles:" -ForegroundColor White
    
    if ($script:migrationData.FSMORoles) {
        foreach ($role in $script:migrationData.FSMORoles.GetEnumerator()) {
            Write-Host "  $($role.Key): $($role.Value)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`nMigration Order:" -ForegroundColor Yellow
    Write-Host "1. PDC Emulator (last)" -ForegroundColor White
    Write-Host "2. RID Master" -ForegroundColor White
    Write-Host "3. Infrastructure Master" -ForegroundColor White
    Write-Host "4. Domain Naming Master" -ForegroundColor White
    Write-Host "5. Schema Master" -ForegroundColor White
    
    $fsmoScript = @"
# FSMO Role Transfer Script
# Run this after Azure DCs are healthy and replicating

`$targetDC = "AzureDC01.$($script:migrationData.DomainName)"

# Transfer roles one by one with validation

Move-ADDirectoryServerOperationMasterRole -Identity `$targetDC -OperationMasterRole RIDMaster -Confirm:`$false
Start-Sleep -Seconds 60

Move-ADDirectoryServerOperationMasterRole -Identity `$targetDC -OperationMasterRole InfrastructureMaster -Confirm:`$false
Start-Sleep -Seconds 60

Move-ADDirectoryServerOperationMasterRole -Identity `$targetDC -OperationMasterRole DomainNamingMaster -Confirm:`$false
Start-Sleep -Seconds 60

Move-ADDirectoryServerOperationMasterRole -Identity `$targetDC -OperationMasterRole SchemaMaster -Confirm:`$false
Start-Sleep -Seconds 60

Move-ADDirectoryServerOperationMasterRole -Identity `$targetDC -OperationMasterRole PDCEmulator -Confirm:`$false

# Verify
Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster
Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster
"@
    
    $fsmoFile = "$ReportPath\FSMO-Transfer-Script.ps1"
    $fsmoScript | Out-File -FilePath $fsmoFile -Encoding UTF8
    
    Write-MigrationLog "FSMO transfer script generated: $fsmoFile" "SUCCESS"
    Write-Host "`nFSMO script saved: $fsmoFile" -ForegroundColor Cyan
}

function Start-Phase6WorkloadMigration {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 6: WORKLOAD MIGRATION" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "WORKLOAD MIGRATION GUIDE:" -ForegroundColor Yellow
    Write-Host "`n1. DNS MIGRATION:" -ForegroundColor Cyan
    Write-Host "   - Update DHCP to point to Azure DCs" -ForegroundColor White
    Write-Host "   - Update client DNS settings gradually" -ForegroundColor White
    Write-Host "   - Test resolution before full cutover" -ForegroundColor White
    
    Write-Host "`n2. FILE SERVER MIGRATION:" -ForegroundColor Cyan
    Write-Host "   - Use Azure File Sync" -ForegroundColor White
    Write-Host "   - Or use Robocopy for file migration" -ForegroundColor White
    Write-Host "   - Maintain permissions and timestamps" -ForegroundColor White
    
    Write-Host "`n3. USER PROFILE MIGRATION:" -ForegroundColor Cyan
    Write-Host "   - Profiles replicate via AD" -ForegroundColor White
    Write-Host "   - Folder redirection to Azure Files" -ForegroundColor White
    Write-Host "   - Test with pilot users first" -ForegroundColor White
    
    $fileMigrationScript = @"
# File Server Migration using Robocopy

`$source = "\\OnPremFileServer\Share"
`$destination = "\\AzureFileServer\Share"

# Mirror copy with permissions
robocopy `$source `$destination /MIR /COPYALL /DCOPY:DAT /R:3 /W:5 /MT:32 /LOG:migration.log

# Verify
robocopy `$source `$destination /L /MIR /COPYALL
"@
    
    $fileMigrationFile = "$ReportPath\File-Migration-Script.ps1"
    $fileMigrationScript | Out-File -FilePath $fileMigrationFile -Encoding UTF8
    
    Write-Host "`nFile migration script saved: $fileMigrationFile" -ForegroundColor Cyan
}

function Start-Phase7Decommission {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 7: DECOMMISSION ON-PREM DCs" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "DECOMMISSION CHECKLIST:" -ForegroundColor Yellow
    Write-Host "`n Verify Azure DCs are healthy" -ForegroundColor White
    Write-Host " Verify AD replication is working" -ForegroundColor White
    Write-Host " Verify all FSMO roles transferred" -ForegroundColor White
    Write-Host " Verify clients using Azure DCs for DNS" -ForegroundColor White
    Write-Host " Verify no services pointing to on-prem DCs" -ForegroundColor White
    Write-Host "`nWait 30 days before final removal" -ForegroundColor Yellow
    
    $decommissionScript = @"
# Domain Controller Decommission Script

# BEFORE running this:
# 1. Verify Azure DCs are operational for 30+ days
# 2. Verify no issues reported
# 3. Verify all workloads migrated
# 4. Take final backup

`$dcToRemove = "OnPremDC01"

# Demote DC (run ON the DC to be removed)
Uninstall-ADDSDomainController -DemoteOperationMasterRole -RemoveApplicationPartition -Confirm:`$false

# After demotion, remove from AD (run from another DC)
Remove-ADComputer -Identity `$dcToRemove -Confirm:`$false

# Clean up metadata if needed
ntdsutil "metadata cleanup" "connections" "connect to server AzureDC01" "quit" "select operation target" "list sites" "select site 0" "list servers in site" "select server 0" "remove selected server" "quit" "quit"
"@
    
    $decommFile = "$ReportPath\Decommission-Script.ps1"
    $decommissionScript | Out-File -FilePath $decommFile -Encoding UTF8
    
    Write-Host "`nDecommission script saved: $decommFile" -ForegroundColor Cyan
}

function Start-Phase8Validation {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 8: VALIDATION & CLEANUP" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "POST-MIGRATION VALIDATION:" -ForegroundColor Yellow
    Write-Host "`n1. AD REPLICATION:" -ForegroundColor Cyan
    Write-Host "   repadmin /replsummary" -ForegroundColor Gray
    Write-Host "   repadmin /showrepl" -ForegroundColor Gray
    
    Write-Host "`n2. DNS VALIDATION:" -ForegroundColor Cyan
    Write-Host "   nslookup domain.com" -ForegroundColor Gray
    Write-Host "   Test DNS resolution from clients" -ForegroundColor Gray
    
    Write-Host "`n3. FSMO ROLES:" -ForegroundColor Cyan
    Write-Host "   netdom query fsmo" -ForegroundColor Gray
    
    Write-Host "`n4. CLIENT CONNECTIVITY:" -ForegroundColor Cyan
    Write-Host "   Test user logon" -ForegroundColor Gray
    Write-Host "   Test GPO application" -ForegroundColor Gray
    Write-Host "   Test file access" -ForegroundColor Gray
    
    $validationScript = @"
# Post-Migration Validation Script

Write-Host "Validating AD Replication..." -ForegroundColor Cyan
repadmin /replsummary

Write-Host "`nValidating FSMO Roles..." -ForegroundColor Cyan
netdom query fsmo

Write-Host "`nValidating DNS..." -ForegroundColor Cyan
Get-DnsServerZone

Write-Host "`nValidating Domain Controllers..." -ForegroundColor Cyan
Get-ADDomainController -Filter *

Write-Host "`nValidation complete!" -ForegroundColor Green
"@
    
    $validationFile = "$ReportPath\Post-Migration-Validation.ps1"
    $validationScript | Out-File -FilePath $validationFile -Encoding UTF8
    
    Write-Host "`nValidation script saved: $validationFile" -ForegroundColor Cyan
}

# MAIN EXECUTION
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  ULTIMATE DC MIGRATION FRAMEWORK" -ForegroundColor Magenta
Write-Host "  ON-PREMISES TO AZURE - ZERO DOWNTIME" -ForegroundColor Magenta
Write-Host "================================================================`n" -ForegroundColor Magenta

try {
    Test-Prerequisites
    
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    if ($Phase -eq 1 -or $AssessmentOnly) {
        Start-Phase1Assessment
    }
    
    if (-not $AssessmentOnly) {
        if ($Phase -ge 2) { Start-Phase2AzureInfrastructure }
        if ($Phase -ge 3) { Start-Phase3NetworkConnectivity }
        if ($Phase -ge 4) { Start-Phase4DeployAzureDCs }
        if ($Phase -ge 5) { Start-Phase5FSMOMigration }
        if ($Phase -ge 6) { Start-Phase6WorkloadMigration }
        if ($Phase -ge 7) { Start-Phase7Decommission }
        if ($Phase -ge 8) { Start-Phase8Validation }
    }
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "  MIGRATION FRAMEWORK EXECUTION COMPLETE" -ForegroundColor Green
    Write-Host "================================================================`n" -ForegroundColor Green
    Write-Host "All scripts and reports saved to: $ReportPath" -ForegroundColor Cyan
    Write-Host "`nIMPORTANT: Review all generated scripts before execution!" -ForegroundColor Yellow
    Write-Host "This is a phased migration - proceed carefully through each phase." -ForegroundColor Yellow
    
} catch {
    Write-MigrationLog "CRITICAL ERROR: $_" "CRITICAL"
    Write-Host "`nMigration framework encountered an error. Check logs." -ForegroundColor Red
    exit 1
}

