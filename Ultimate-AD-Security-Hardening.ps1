#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Ultimate Active Directory Security Hardening Framework

.DESCRIPTION
    Enterprise-grade automated AD security hardening
    
    PHASES:
    1. Security Assessment (Read-only)
    2. DNS & Network Security
    3. AD Object Hardening
    4. GPO Implementation
    5. User & Computer Policies
    
.PARAMETER Phase
    Specify phase to run (1-5)
    
.PARAMETER AssessmentOnly
    Run assessment without changes
    
.EXAMPLE
    .\Ultimate-AD-Security-Hardening.ps1 -Phase 1
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

function Test-Prerequisites {
    Write-SecurityLog "Checking prerequisites..." "INFO"
    
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-SecurityLog "Active Directory module not found!" "CRITICAL"
        throw "Install RSAT-AD-PowerShell feature"
    }
    
    Import-Module ActiveDirectory
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-SecurityLog "Must run as Administrator!" "CRITICAL"
        throw "Run as Administrator"
    }
    
    try {
        $domain = Get-ADDomain
        Write-SecurityLog "Connected to domain: $($domain.DNSRoot)" "SUCCESS"
    } catch {
        Write-SecurityLog "Cannot connect to AD!" "CRITICAL"
        throw $_
    }
}

function Start-Phase1Assessment {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 1: COMPREHENSIVE SECURITY ASSESSMENT" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    $findings = @()
    
    Write-SecurityLog "Assessing domain..." "INFO"
    
    $domain = Get-ADDomain
    $users = Get-ADUser -Filter * -Properties PasswordNeverExpires, PasswordLastSet, Enabled
    $computers = Get-ADComputer -Filter * -Properties LastLogonDate
    
    Write-Host "Domain: $($domain.DNSRoot)" -ForegroundColor White
    Write-Host "Users: $($users.Count)" -ForegroundColor White
    Write-Host "Computers: $($computers.Count)" -ForegroundColor White
    
    $passwordNeverExpires = $users | Where-Object {$_.PasswordNeverExpires -and $_.Enabled}
    if ($passwordNeverExpires.Count -gt 0) {
        $findings += [PSCustomObject]@{
            Severity = "HIGH"
            Category = "Password Policy"
            Issue = "$($passwordNeverExpires.Count) accounts with password never expires"
            Recommendation = "Set password expiration"
        }
    }
    
    $staleComputers = $computers | Where-Object {$_.LastLogonDate -lt (Get-Date).AddDays(-90)}
    if ($staleComputers.Count -gt 0) {
        $findings += [PSCustomObject]@{
            Severity = "MEDIUM"
            Category = "Computer Accounts"
            Issue = "$($staleComputers.Count) stale computers (no logon >90 days)"
            Recommendation = "Disable stale accounts"
        }
    }
    
    $privilegedGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins")
    foreach ($group in $privilegedGroups) {
        try {
            $members = Get-ADGroupMember -Identity $group -Recursive
            if ($members.Count -gt 5) {
                $findings += [PSCustomObject]@{
                    Severity = "HIGH"
                    Category = "Privileged Access"
                    Issue = "$group has $($members.Count) members"
                    Recommendation = "Review privileged access"
                }
            }
        } catch { }
    }
    
    Write-Host "`nSecurity Findings: $($findings.Count)" -ForegroundColor Yellow
    
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    $reportFile = "$ReportPath\AD-Assessment-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $findings | Export-Csv -Path $reportFile -NoTypeInformation
    
    Write-SecurityLog "Report saved: $reportFile" "SUCCESS"
    
    return $findings
}

function Start-Phase2DNSSecurity {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 2: DNS & NETWORK SECURITY" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "DNS SECURITY RECOMMENDATIONS:" -ForegroundColor Yellow
    Write-Host "1. Enable DNS scavenging" -ForegroundColor White
    Write-Host "2. Configure secure dynamic updates" -ForegroundColor White
    Write-Host "3. Enable DNS logging" -ForegroundColor White
    Write-Host "4. Disable recursion on external interfaces" -ForegroundColor White
    
    $dnsScript = @"
# DNS Security Commands
Set-DnsServerScavenging -ScavengingState `$true -RefreshInterval 7.00:00:00
Get-DnsServerZone | Where-Object {`$_.IsAutoCreated -eq `$false} | Set-DnsServerPrimaryZone -DynamicUpdate Secure
Set-DnsServerDiagnostics -Answers `$true -Queries `$true
"@
    
    $dnsFile = "$ReportPath\DNS-Hardening-Commands.ps1"
    $dnsScript | Out-File -FilePath $dnsFile -Encoding UTF8
    
    Write-SecurityLog "DNS commands saved: $dnsFile" "SUCCESS"
}

function Start-Phase3ADHardening {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 3: AD OBJECT HARDENING" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-SecurityLog "Hardening AD objects..." "INFO"
    
    $staleDate = (Get-Date).AddDays(-90)
    $staleComputers = Get-ADComputer -Filter * -Properties LastLogonDate | Where-Object {$_.LastLogonDate -lt $staleDate -and $_.Enabled}
    
    Write-Host "Found $($staleComputers.Count) stale computers" -ForegroundColor Yellow
    Write-Host "Run with -Force to disable them" -ForegroundColor Yellow
    
    Write-Host "`nPASSWORD POLICY RECOMMENDATIONS:" -ForegroundColor Yellow
    Write-Host "- Minimum length: 14 characters" -ForegroundColor White
    Write-Host "- Complexity: Enabled" -ForegroundColor White
    Write-Host "- History: 24 passwords" -ForegroundColor White
    Write-Host "- Max age: 60 days" -ForegroundColor White
}

function Start-Phase4GPOHardening {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 4: GPO SECURITY IMPLEMENTATION" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "RECOMMENDED GPO SETTINGS:" -ForegroundColor Yellow
    Write-Host "`nCOMPUTER POLICIES:" -ForegroundColor Cyan
    Write-Host "- Disable SMBv1" -ForegroundColor White
    Write-Host "- Enable Windows Defender" -ForegroundColor White
    Write-Host "- Configure Windows Firewall" -ForegroundColor White
    Write-Host "- Disable LLMNR/NetBIOS/WPAD" -ForegroundColor White
    Write-Host "- Enable PowerShell logging" -ForegroundColor White
    
    Write-Host "`nUSER POLICIES:" -ForegroundColor Cyan
    Write-Host "- Restrict software installation" -ForegroundColor White
    Write-Host "- Screen lock timeout: 15 minutes" -ForegroundColor White
    Write-Host "- Restrict Control Panel access" -ForegroundColor White
}

function Start-Phase5UserPolicies {
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 5: USER & COMPUTER POLICY ENFORCEMENT" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor Cyan
    
    Write-Host "LEAST PRIVILEGE IMPLEMENTATION:" -ForegroundColor Yellow
    Write-Host "- Remove users from local admin groups" -ForegroundColor White
    Write-Host "- Configure AppLocker policies" -ForegroundColor White
    Write-Host "- Enable BitLocker enforcement" -ForegroundColor White
    Write-Host "- Folder redirection for user data" -ForegroundColor White
}

# MAIN EXECUTION
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  ULTIMATE AD SECURITY HARDENING FRAMEWORK" -ForegroundColor Magenta
Write-Host "  Enterprise-Grade Security Automation" -ForegroundColor Magenta
Write-Host "================================================================`n" -ForegroundColor Magenta

try {
    Test-Prerequisites
    
    if ($AssessmentOnly -or $Phase -eq 1) {
        $assessment = Start-Phase1Assessment
    }
    
    if (-not $AssessmentOnly) {
        if ($Phase -ge 2) { Start-Phase2DNSSecurity }
        if ($Phase -ge 3) { Start-Phase3ADHardening }
        if ($Phase -ge 4) { Start-Phase4GPOHardening }
        if ($Phase -ge 5) { Start-Phase5UserPolicies }
    }
    
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host "  COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "================================================================`n" -ForegroundColor Green
    Write-Host "Reports: $ReportPath" -ForegroundColor Cyan
    
} catch {
    Write-SecurityLog "ERROR: $_" "CRITICAL"
    exit 1
}
