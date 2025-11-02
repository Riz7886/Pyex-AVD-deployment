#Requires -Version 5.1
<#
.SYNOPSIS
    Cisco AnyConnect VPN Detection Module - OPTIONAL CHECK
.DESCRIPTION
    Detects if user is connected to Cisco AnyConnect VPN
    Used for END USER access, not admin deployment
.EXAMPLE
    . .\VPN-Detection-Module.ps1
    Test-VPNConnection -Informational
#>

function Test-VPNConnection {
    [CmdletBinding()]
    param(
        [switch]$Informational
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
        Write-Host "  STATUS: VPN Connected" -ForegroundColor Green
    } else {
        Write-Host "  STATUS: No VPN detected" -ForegroundColor Yellow
        Write-Host "  NOTE: VPN not required for admin deployment" -ForegroundColor Cyan
    }
    
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    return $vpnConnected
}
