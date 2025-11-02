#Requires -Version 5.1
<#
.SYNOPSIS
    Cisco AnyConnect VPN Detection Module - OPTIONAL CHECK
.DESCRIPTION
    Detects if user is connected to Cisco AnyConnect VPN
    Used for END USER access, not admin deployment
.EXAMPLE
    Test-VPNConnection -Informational
#>

function Test-VPNConnection {
    [CmdletBinding()]
    param(
        [switch]$Informational  # Just show info, don't block
    )
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  VPN CONNECTION CHECK (Informational)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $vpnConnected = $false
    
    # Check Cisco AnyConnect Process
    $ciscoProcess = Get-Process -Name "vpnui" -ErrorAction SilentlyContinue
    if ($ciscoProcess) {
        Write-Host "  Cisco AnyConnect: RUNNING" -ForegroundColor Green
        $vpnConnected = $true
    } else {
        Write-Host "  Cisco AnyConnect: NOT DETECTED" -ForegroundColor Yellow
    }
    
    # Check VPN Network Adapter
    $vpnAdapters = Get-NetAdapter | Where-Object { 
        $_.InterfaceDescription -match "Cisco|VPN|AnyConnect" -and $_.Status -eq "Up"
    }
    
    if ($vpnAdapters) {
        Write-Host "  VPN Adapter: CONNECTED" -ForegroundColor Green
        $vpnConnected = $true
    } else {
        Write-Host "  VPN Adapter: NOT CONNECTED" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    if ($vpnConnected) {
        Write-Host "  STATUS: VPN Connected - End users can access Bastion" -ForegroundColor Green
    } else {
        Write-Host "  STATUS: No VPN detected" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  NOTE: This is OK for admin deployment tasks" -ForegroundColor Cyan
        Write-Host "  End users will need VPN to connect to VMs via Bastion" -ForegroundColor Cyan
    }
    
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    return $vpnConnected
}

Export-ModuleMember -Function Test-VPNConnection
