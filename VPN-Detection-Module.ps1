#Requires -Version 5.1
<#
.SYNOPSIS
    Cisco AnyConnect VPN Detection Module
.DESCRIPTION
    Detects if user is connected to Cisco AnyConnect VPN before allowing Bastion operations
.EXAMPLE
    Test-VPNConnection
#>

function Test-VPNConnection {
    [CmdletBinding()]
    param(
        [switch]$Required,
        [switch]$Silent
    )
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  VPN CONNECTION SECURITY CHECK" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $vpnConnected = $false
    $vpnDetails = @{
        Type = "Unknown"
        Status = "Disconnected"
        Adapter = "Not Found"
        IPAddress = "N/A"
    }
    
    # Check 1: Cisco AnyConnect Process
    $ciscoProcess = Get-Process -Name "vpnui" -ErrorAction SilentlyContinue
    if ($ciscoProcess) {
        Write-Host "  [CHECK 1/4] Cisco AnyConnect Process: RUNNING" -ForegroundColor Green
        $vpnDetails.Type = "Cisco AnyConnect"
    } else {
        Write-Host "  [CHECK 1/4] Cisco AnyConnect Process: NOT RUNNING" -ForegroundColor Yellow
    }
    
    # Check 2: VPN Network Adapter
    $vpnAdapters = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -match "Cisco|VPN|AnyConnect" -or 
        $_.Name -match "VPN|AnyConnect"
    }
    
    if ($vpnAdapters) {
        $connectedAdapter = $vpnAdapters | Where-Object { $_.Status -eq "Up" }
        if ($connectedAdapter) {
            Write-Host "  [CHECK 2/4] VPN Network Adapter: CONNECTED" -ForegroundColor Green
            $vpnDetails.Adapter = $connectedAdapter.Name
            $vpnConnected = $true
            
            # Get IP Address
            $ipConfig = Get-NetIPAddress -InterfaceIndex $connectedAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipConfig) {
                $vpnDetails.IPAddress = $ipConfig.IPAddress
            }
        } else {
            Write-Host "  [CHECK 2/4] VPN Network Adapter: FOUND BUT DISCONNECTED" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [CHECK 2/4] VPN Network Adapter: NOT FOUND" -ForegroundColor Yellow
    }
    
    # Check 3: Corporate Network Route (10.x.x.x ranges)
    $corporateRoutes = Get-NetRoute | Where-Object { 
        $_.DestinationPrefix -match "^10\." -and $_.RouteMetric -lt 100
    }
    
    if ($corporateRoutes) {
        Write-Host "  [CHECK 3/4] Corporate Network Routes: DETECTED" -ForegroundColor Green
        $vpnConnected = $true
    } else {
        Write-Host "  [CHECK 3/4] Corporate Network Routes: NOT DETECTED" -ForegroundColor Yellow
    }
    
    # Check 4: DNS Suffix (corporate domain)
    $dnsClient = Get-DnsClient | Where-Object { 
        $_.ConnectionSpecificSuffix -match "corp|internal|local|vpn"
    }
    
    if ($dnsClient) {
        Write-Host "  [CHECK 4/4] Corporate DNS Suffix: DETECTED" -ForegroundColor Green
        $vpnConnected = $true
    } else {
        Write-Host "  [CHECK 4/4] Corporate DNS Suffix: NOT DETECTED" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    
    if ($vpnConnected) {
        $vpnDetails.Status = "Connected"
        Write-Host "  VPN STATUS: CONNECTED" -ForegroundColor Green
        Write-Host "  VPN Type: $($vpnDetails.Type)" -ForegroundColor White
        Write-Host "  Adapter: $($vpnDetails.Adapter)" -ForegroundColor White
        Write-Host "  IP Address: $($vpnDetails.IPAddress)" -ForegroundColor White
        Write-Host ""
        Write-Host "  Security Check: PASSED - Proceeding with Bastion operations" -ForegroundColor Green
    } else {
        Write-Host "  VPN STATUS: NOT CONNECTED" -ForegroundColor Red
        Write-Host ""
        Write-Host "  SECURITY REQUIREMENT:" -ForegroundColor Yellow
        Write-Host "  You MUST connect to Cisco AnyConnect VPN before using Bastion" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Steps to connect:" -ForegroundColor Cyan
        Write-Host "  1. Open Cisco AnyConnect VPN Client" -ForegroundColor White
        Write-Host "  2. Connect to your corporate VPN" -ForegroundColor White
        Write-Host "  3. Wait for connection to establish" -ForegroundColor White
        Write-Host "  4. Run this script again" -ForegroundColor White
        Write-Host ""
        
        if ($Required) {
            Write-Host "  OPERATION BLOCKED: VPN connection required" -ForegroundColor Red
            Write-Host "============================================================" -ForegroundColor Cyan
            Write-Host ""
            exit 1
        }
    }
    
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    return $vpnConnected
}

# Export function
Export-ModuleMember -Function Test-VPNConnection
