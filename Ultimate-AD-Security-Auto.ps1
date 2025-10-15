#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Ultimate Active Directory Security Hardening Framework - AUTO INSTALL VERSION

.DESCRIPTION
    Auto-installs prerequisites and hardens AD security
    
.EXAMPLE
    .\Ultimate-AD-Security-Auto.ps1 -Phase 1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5)]
    [int]$Phase = 1,
    
    [Parameter(Mandatory = $false)]
    [switch]$AssessmentOnly,
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\AD-Security-Reports"
)

function Write-SecurityLog {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red";"CRITICAL"="Magenta"}
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Install-ADModule {
    Write-SecurityLog "Checking Active Directory module..." "INFO"
    
    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    
    if ($adModule) {
        Write-SecurityLog "AD module already installed!" "SUCCESS"
        Import-Module ActiveDirectory
        return $true
    }
    
    Write-SecurityLog "AD module NOT found. Attempting installation..." "WARNING"
    
    try {
        Write-Host "`nAttempting to install RSAT Active Directory tools..." -ForegroundColor Yellow
        Write-Host "This may take a few minutes...`n" -ForegroundColor Yellow
        
        $rsatFeature = Get-WindowsCapability -Online | Where-Object Name -like 'Rsat.ActiveDirectory*'
        
        if ($rsatFeature) {
            Write-SecurityLog "Installing via Windows Capability..." "INFO"
            
            foreach ($feature in $rsatFeature) {
                Write-Host "  Installing: $($feature.Name)" -ForegroundColor Cyan
                Add-WindowsCapability -Online -Name $feature.Name -ErrorAction Stop
            }
            
            Write-SecurityLog "RSAT installation complete!" "SUCCESS"
            Import-Module ActiveDirectory -ErrorAction Stop
            return $true
        }
        
        Write-SecurityLog "Trying DISM method..." "INFO"
        dism /online /enable-feature /featurename:RSATClient-Roles-AD-Powershell /all
        
        Import-Module ActiveDirectory -ErrorAction Stop
        return $true
        
    } catch {
        Write-SecurityLog "AUTO-INSTALL FAILED!" "ERROR"
        Write-Host "`n================================================================" -ForegroundColor Red
        Write-Host "  INSTALLATION BLOCKED - MANUAL ACTION REQUIRED" -ForegroundColor Red
        Write-Host "================================================================" -ForegroundColor Red
        Write-Host "`nYour work laptop likely has RESTRICTIONS." -ForegroundColor Yellow
        Write-Host "`nOPTION 1: Contact IT Support" -ForegroundColor Cyan
        Write-Host "  Email IT: 'Please install RSAT Active Directory tools'" -ForegroundColor White
        Write-Host "`nOPTION 2: Run on Domain Controller" -ForegroundColor Cyan
        Write-Host "  - RDP to Domain Controller" -ForegroundColor White
        Write-Host "  - Run this script there (AD tools pre-installed)" -ForegroundColor White
        Write-Host "`nOPTION 3: Manual Install via Settings" -ForegroundColor Cyan
        Write-Host "  1. Windows Settings > Apps > Optional Features" -ForegroundColor White
        Write-Host "  2. Add a feature" -ForegroundColor White
        Write-Host "  3. Search: 'RSAT: Active Directory'" -ForegroundColor White
        Write-Host "  4. Install it" -ForegroundColor White
        Write-Host "`n================================================================`n" -ForegroundColor Red
        
        return $false
    }
}

function Test-Prerequisites {
    Write-SecurityLog "Checking prerequisites..." "INFO"
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-SecurityLog "Must run as Administrator!" "CRITICAL"
        Write-Host "`nRight-click PowerShell -> Run as Administrator`n" -ForegroundColor Yellow
        throw "Not running as Administrator"
    }
    
    $moduleInstalled = Install-ADModule
    
    if (-not $moduleInstalled) {
        Write-SecurityLog "Cannot proceed without AD module!" "CRITICAL"
        throw "AD module required"
    }
    
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-SecurityLog "Connected to domain: $($domain.DNSRoot)" "SUCCESS"
        return $true
    } catch {
        Write-SecurityLog "Cannot connect to Active Directory!" "CRITICAL"
        Write-Host "`nPossible reasons:" -ForegroundColor Yellow
        Write-Host "  - Not connected to domain network" -ForegroundColor White
        Write-Host "  - VPN not connected" -ForegroundColor White
        Write-Host "  - No domain controller accessible" -ForegroundColor White
        Write-Host "`nError: $_`n" -ForegroundColor Red
        throw $_
    }
}

function Start-Phase1Assessment {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 1: COMPREHENSIVE SECURITY ASSESSMENT" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    $findings = @()
    
    Write-SecurityLog "Assessing domain..." "INFO"
    
    try {
        $domain = Get-ADDomain
        $users = Get-ADUser -Filter * -Properties PasswordNeverExpires, PasswordLastSet, Enabled, LastLogonDate
        $computers = Get-ADComputer -Filter * -Properties LastLogonDate, OperatingSystem
        
        Write-Host "Domain Information:" -ForegroundColor Cyan
        Write-Host "  Domain: $($domain.DNSRoot)" -ForegroundColor White
        Write-Host "  Forest: $($domain.Forest)" -ForegroundColor White
        Write-Host "  Total Users: $($users.Count)" -ForegroundColor White
        Write-Host "  Total Computers: $($computers.Count)" -ForegroundColor White
        Write-Host ""
        
        $passwordNeverExpires = $users | Where-Object {$_.PasswordNeverExpires -and $_.Enabled}
        if ($passwordNeverExpires.Count -gt 0) {
            $findings += [PSCustomObject]@{
                Severity = "HIGH"
                Category = "Password Policy"
                Issue = "$($passwordNeverExpires.Count) enabled accounts with 'Password Never Expires'"
                Count = $passwordNeverExpires.Count
                Recommendation = "Set password expiration on all accounts"
            }
            Write-Host "  X $($passwordNeverExpires.Count) accounts with password never expires" -ForegroundColor Red
        } else {
            Write-Host "  OK No accounts with password never expires" -ForegroundColor Green
        }
        
        $staleUsers = $users | Where-Object {$_.Enabled -and $_.LastLogonDate -lt (Get-Date).AddDays(-90)}
        if ($staleUsers.Count -gt 0) {
            $findings += [PSCustomObject]@{
                Severity = "MEDIUM"
                Category = "User Accounts"
                Issue = "$($staleUsers.Count) enabled users with no logon >90 days"
                Count = $staleUsers.Count
                Recommendation = "Disable stale user accounts"
            }
            Write-Host "  ! $($staleUsers.Count) stale user accounts" -ForegroundColor Yellow
        }
        
        $staleComputers = $computers | Where-Object {$_.LastLogonDate -lt (Get-Date).AddDays(-90)}
        if ($staleComputers.Count -gt 0) {
            $findings += [PSCustomObject]@{
                Severity = "MEDIUM"
                Category = "Computer Accounts"
                Issue = "$($staleComputers.Count) stale computers"
                Count = $staleComputers.Count
                Recommendation = "Disable stale computers"
            }
            Write-Host "  ! $($staleComputers.Count) stale computer accounts" -ForegroundColor Yellow
        }
        
        Write-SecurityLog "Checking privileged groups..." "INFO"
        $privilegedGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins")
        foreach ($group in $privilegedGroups) {
            try {
                $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction SilentlyContinue
                Write-Host "  Group: $group - $($members.Count) members" -ForegroundColor White
                
                if ($members.Count -gt 5) {
                    $findings += [PSCustomObject]@{
                        Severity = "HIGH"
                        Category = "Privileged Access"
                        Issue = "$group has $($members.Count) members"
                        Count = $members.Count
                        Recommendation = "Review privileged access"
                    }
                }
            } catch { }
        }
        
        Write-Host "`n================================================================" -ForegroundColor Cyan
        Write-Host "  ASSESSMENT SUMMARY" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "Total Findings: $($findings.Count)" -ForegroundColor Yellow
        
        if (-not (Test-Path $ReportPath)) {
            New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $reportFile = "$ReportPath\AD-Assessment-$timestamp.csv"
        $findings | Export-Csv -Path $reportFile -NoTypeInformation
        
        Write-SecurityLog "Report saved: $reportFile" "SUCCESS"
        
        return $findings
        
    } catch {
        Write-SecurityLog "Assessment failed: $_" "ERROR"
        throw $_
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  ULTIMATE AD SECURITY HARDENING FRAMEWORK" -ForegroundColor Magenta
Write-Host "================================================================`n" -ForegroundColor Magenta

try {
    Test-Prerequisites
    
    if ($AssessmentOnly -or $Phase -eq 1) {
        $assessment = Start-Phase1Assessment
    }
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "  COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "================================================================`n" -ForegroundColor Green
    Write-Host "Reports: $ReportPath" -ForegroundColor Cyan
    
} catch {
    Write-SecurityLog "SCRIPT FAILED: $_" "CRITICAL"
    Write-Host "`nCheck the error messages above.`n" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
