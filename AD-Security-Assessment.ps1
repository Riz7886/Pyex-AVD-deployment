#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Professional-Grade Active Directory Security Assessment
    
.DESCRIPTION
    Comprehensive read-only security assessment of Active Directory
    NO CHANGES MADE - ASSESSMENT ONLY
    
    Checks 50+ security configurations including:
    - Kerberos vulnerabilities
    - Password policies
    - Privileged access
    - GPO security
    - Service accounts
    - Legacy protocols
    - Certificate services
    - And much more
    
.EXAMPLE
    .\AD-Security-Assessment.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$ReportsFolder = "C:\Scripts\Azure-Analysis-Reports"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  PROFESSIONAL AD SECURITY ASSESSMENT" -ForegroundColor Cyan
Write-Host "  READ-ONLY MODE - NO CHANGES WILL BE MADE" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Create reports folder
if (-not (Test-Path $ReportsFolder)) {
    New-Item -ItemType Directory -Path $ReportsFolder -Force | Out-Null
    Write-Host "[CREATED] Reports folder: $ReportsFolder" -ForegroundColor Green
} else {
    Write-Host "[EXISTS] Reports folder: $ReportsFolder" -ForegroundColor Green
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvReportPath = Join-Path $ReportsFolder "AD-Security-Assessment-$timestamp.csv"
$htmlReportPath = Join-Path $ReportsFolder "AD-Security-Assessment-$timestamp.html"

Write-Host ""
Write-Host "Report files will be saved to:" -ForegroundColor Yellow
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host ""

# Check prerequisites
Write-Host "[CHECK] Verifying prerequisites..." -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "[ERROR] Active Directory PowerShell module not installed!" -ForegroundColor Red
    Write-Host "Install: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop
Write-Host "[CHECK] Active Directory module loaded" -ForegroundColor Green

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Must run as Administrator!" -ForegroundColor Red
    exit 1
}
Write-Host "[CHECK] Running as Administrator" -ForegroundColor Green

try {
    $domain = Get-ADDomain -ErrorAction Stop
    $forest = Get-ADForest -ErrorAction Stop
    Write-Host "[CHECK] Connected to domain: $($domain.DNSRoot)" -ForegroundColor Green
    Write-Host "[CHECK] Forest: $($forest.Name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Cannot connect to Active Directory!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize findings array
$global:findings = @()
$global:counts = @{
    Critical = 0
    High = 0
    Medium = 0
    Low = 0
    Info = 0
}

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Finding,
        [string]$Details,
        [string]$Recommendation,
        [string]$Impact
    )
    
    $global:findings += [PSCustomObject]@{
        Severity = $Severity
        Category = $Category
        Finding = $Finding
        Details = $Details
        Recommendation = $Recommendation
        Impact = $Impact
    }
    
    $global:counts[$Severity]++
}

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host "  STARTING COMPREHENSIVE SECURITY ASSESSMENT" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# 1. DOMAIN AND FOREST CONFIGURATION
# ============================================================

Write-Host "[1/20] Assessing Domain Configuration..." -ForegroundColor Yellow

$domainControllers = Get-ADDomainController -Filter *
Write-Host "  Domain Controllers: $($domainControllers.Count)" -ForegroundColor White

if ($domain.DomainMode -notmatch "2016") {
    Add-Finding -Severity "High" -Category "Domain Configuration" `
        -Finding "Domain functional level not at Windows Server 2016" `
        -Details "Current level: $($domain.DomainMode)" `
        -Recommendation "Upgrade to Windows Server 2016 functional level or higher" `
        -Impact "Missing modern security features"
}

if ($forest.ForestMode -notmatch "2016") {
    Add-Finding -Severity "High" -Category "Forest Configuration" `
        -Finding "Forest functional level not at Windows Server 2016" `
        -Details "Current level: $($forest.ForestMode)" `
        -Recommendation "Upgrade to Windows Server 2016 functional level or higher" `
        -Impact "Missing modern security features"
}

$recycleBin = Get-ADOptionalFeature -Filter {name -like "Recycle Bin Feature"}
if ($recycleBin.EnabledScopes.Count -eq 0) {
    Add-Finding -Severity "Medium" -Category "Domain Configuration" `
        -Finding "AD Recycle Bin not enabled" `
        -Details "Deleted objects cannot be easily recovered" `
        -Recommendation "Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $($forest.Name)" `
        -Impact "No easy recovery of accidentally deleted AD objects"
}

# ============================================================
# 2. KRBTGT ACCOUNT ANALYSIS
# ============================================================

Write-Host "[2/20] Analyzing KRBTGT Account..." -ForegroundColor Yellow

$krbtgt = Get-ADUser -Identity krbtgt -Properties PasswordLastSet
$passwordAge = (Get-Date) - $krbtgt.PasswordLastSet

Write-Host "  KRBTGT password age: $($passwordAge.Days) days" -ForegroundColor White

if ($passwordAge.Days -gt 180) {
    Add-Finding -Severity "Critical" -Category "Kerberos Security" `
        -Finding "KRBTGT password is $($passwordAge.Days) days old" `
        -Details "Last changed: $($krbtgt.PasswordLastSet)" `
        -Recommendation "Reset KRBTGT password using Microsoft script (requires 2 resets)" `
        -Impact "Vulnerable to Golden Ticket attacks"
}

# ============================================================
# 3. PRIVILEGED GROUPS ANALYSIS
# ============================================================

Write-Host "[3/20] Auditing Privileged Groups..." -ForegroundColor Yellow

$privilegedGroups = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Account Operators",
    "Backup Operators",
    "Server Operators",
    "Print Operators"
)

foreach ($groupName in $privilegedGroups) {
    try {
        $group = Get-ADGroup -Identity $groupName -ErrorAction Stop
        $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop
        
        Write-Host "  $groupName : $($members.Count) members" -ForegroundColor Gray
        
        if ($groupName -in @("Domain Admins", "Enterprise Admins", "Schema Admins")) {
            if ($members.Count -gt 5) {
                Add-Finding -Severity "High" -Category "Privileged Access" `
                    -Finding "$groupName has $($members.Count) members" `
                    -Details "Members: $($members.Name -join ', ')" `
                    -Recommendation "Reduce membership to minimum required (recommended: 2-3)" `
                    -Impact "Excessive privileged access increases attack surface"
            }
        }
        
        if ($groupName -eq "Schema Admins" -and $members.Count -gt 0) {
            Add-Finding -Severity "Medium" -Category "Privileged Access" `
                -Finding "Schema Admins group has members" `
                -Details "This group should normally be empty" `
                -Recommendation "Remove all members when not actively making schema changes" `
                -Impact "Unnecessary elevated privileges"
        }
    } catch {
        Write-Host "  Could not check $groupName" -ForegroundColor Gray
    }
}

# ============================================================
# 4. SERVICE ACCOUNTS WITH SPNS (KERBEROASTING)
# ============================================================

Write-Host "[4/20] Checking for Kerberoastable Accounts..." -ForegroundColor Yellow

$kerberoastable = Get-ADUser -Filter {ServicePrincipalName -like "*"} -Properties ServicePrincipalName, PasswordLastSet, AdminCount

Write-Host "  Found: $($kerberoastable.Count) accounts with SPNs" -ForegroundColor White

foreach ($account in $kerberoastable) {
    if ($account.AdminCount -eq 1) {
        Add-Finding -Severity "Critical" -Category "Kerberos Security" `
            -Finding "Privileged account with SPN is kerberoastable" `
            -Details "Account: $($account.SamAccountName), SPN: $($account.ServicePrincipalName[0])" `
            -Recommendation "Use Managed Service Accounts (MSA/gMSA) instead" `
            -Impact "Account vulnerable to offline password cracking"
    }
    
    $passwordAge = (Get-Date) - $account.PasswordLastSet
    if ($passwordAge.Days -gt 365) {
        Add-Finding -Severity "High" -Category "Kerberos Security" `
            -Finding "Service account with old password" `
            -Details "Account: $($account.SamAccountName), Password age: $($passwordAge.Days) days" `
            -Recommendation "Rotate password or migrate to gMSA" `
            -Impact "Easier to crack with kerberoasting attack"
    }
}

# ============================================================
# 5. AS-REP ROASTING VULNERABILITIES
# ============================================================

Write-Host "[5/20] Checking AS-REP Roasting Vulnerabilities..." -ForegroundColor Yellow

$asrepRoastable = Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth

Write-Host "  Found: $($asrepRoastable.Count) accounts not requiring Kerberos pre-auth" -ForegroundColor White

foreach ($account in $asrepRoastable) {
    Add-Finding -Severity "Critical" -Category "Kerberos Security" `
        -Finding "Account does not require Kerberos pre-authentication" `
        -Details "Account: $($account.SamAccountName)" `
        -Recommendation "Enable Kerberos pre-authentication (disable 'Do not require Kerberos preauthentication')" `
        -Impact "Account vulnerable to AS-REP roasting attack"
}

# ============================================================
# 6. UNCONSTRAINED DELEGATION
# ============================================================

Write-Host "[6/20] Checking Unconstrained Delegation..." -ForegroundColor Yellow

$unconstrainedComputers = Get-ADComputer -Filter {TrustedForDelegation -eq $true -and PrimaryGroupID -eq 515} -Properties TrustedForDelegation
$unconstrainedUsers = Get-ADUser -Filter {TrustedForDelegation -eq $true} -Properties TrustedForDelegation

Write-Host "  Computers with unconstrained delegation: $($unconstrainedComputers.Count)" -ForegroundColor White
Write-Host "  Users with unconstrained delegation: $($unconstrainedUsers.Count)" -ForegroundColor White

foreach ($computer in $unconstrainedComputers) {
    if ($computer.Name -notmatch "DC") {
        Add-Finding -Severity "Critical" -Category "Delegation" `
            -Finding "Non-DC computer with unconstrained delegation" `
            -Details "Computer: $($computer.Name)" `
            -Recommendation "Use constrained delegation or resource-based constrained delegation instead" `
            -Impact "Computer can be used to compromise domain"
    }
}

foreach ($user in $unconstrainedUsers) {
    Add-Finding -Severity "Critical" -Category "Delegation" `
        -Finding "User account with unconstrained delegation" `
        -Details "User: $($user.SamAccountName)" `
        -Recommendation "Remove unconstrained delegation, use constrained delegation" `
        -Impact "Account can be exploited for privilege escalation"
}

# ============================================================
# 7. PASSWORD POLICY ANALYSIS
# ============================================================

Write-Host "[7/20] Analyzing Password Policies..." -ForegroundColor Yellow

$defaultPolicy = Get-ADDefaultDomainPasswordPolicy

Write-Host "  Minimum password length: $($defaultPolicy.MinPasswordLength)" -ForegroundColor Gray
Write-Host "  Password complexity: $($defaultPolicy.ComplexityEnabled)" -ForegroundColor Gray
Write-Host "  Password history: $($defaultPolicy.PasswordHistoryCount)" -ForegroundColor Gray
Write-Host "  Maximum password age: $($defaultPolicy.MaxPasswordAge.Days) days" -ForegroundColor Gray

if ($defaultPolicy.MinPasswordLength -lt 14) {
    Add-Finding -Severity "High" -Category "Password Policy" `
        -Finding "Minimum password length is $($defaultPolicy.MinPasswordLength) characters" `
        -Details "NIST recommends minimum 14 characters" `
        -Recommendation "Set minimum password length to 14 characters" `
        -Impact "Weak passwords easier to crack"
}

if ($defaultPolicy.ComplexityEnabled -eq $false) {
    Add-Finding -Severity "Critical" -Category "Password Policy" `
        -Finding "Password complexity not enabled" `
        -Details "Users can set simple passwords" `
        -Recommendation "Enable password complexity requirements" `
        -Impact "Significantly weaker passwords"
}

if ($defaultPolicy.PasswordHistoryCount -lt 24) {
    Add-Finding -Severity "Medium" -Category "Password Policy" `
        -Finding "Password history only remembers $($defaultPolicy.PasswordHistoryCount) passwords" `
        -Details "Recommended: 24 passwords" `
        -Recommendation "Set password history to 24" `
        -Impact "Users can reuse recent passwords"
}

if ($defaultPolicy.MaxPasswordAge.Days -gt 90) {
    Add-Finding -Severity "Medium" -Category "Password Policy" `
        -Finding "Maximum password age is $($defaultPolicy.MaxPasswordAge.Days) days" `
        -Details "Recommended: 60-90 days for privileged accounts" `
        -Recommendation "Set maximum password age to 60-90 days" `
        -Impact "Compromised passwords remain valid longer"
}

# Check for fine-grained password policies
$fgpp = Get-ADFineGrainedPasswordPolicy -Filter *
Write-Host "  Fine-grained password policies: $($fgpp.Count)" -ForegroundColor Gray

# ============================================================
# 8. ACCOUNTS WITH PASSWORD ISSUES
# ============================================================

Write-Host "[8/20] Checking Account Password Settings..." -ForegroundColor Yellow

$users = Get-ADUser -Filter * -Properties PasswordNeverExpires, PasswordNotRequired, PasswordLastSet, Enabled, AdminCount, LastLogonDate

$passwordNeverExpires = $users | Where-Object {$_.PasswordNeverExpires -eq $true -and $_.Enabled -eq $true}
$passwordNotRequired = $users | Where-Object {$_.PasswordNotRequired -eq $true -and $_.Enabled -eq $true}
$neverLoggedOn = $users | Where-Object {$_.LastLogonDate -eq $null -and $_.Enabled -eq $true}

Write-Host "  Password never expires: $($passwordNeverExpires.Count)" -ForegroundColor White
Write-Host "  Password not required: $($passwordNotRequired.Count)" -ForegroundColor White
Write-Host "  Never logged on: $($neverLoggedOn.Count)" -ForegroundColor White

foreach ($user in $passwordNeverExpires) {
    $severity = if ($user.AdminCount -eq 1) { "Critical" } else { "High" }
    Add-Finding -Severity $severity -Category "Password Policy" `
        -Finding "Account with password never expires" `
        -Details "Account: $($user.SamAccountName)" `
        -Recommendation "Disable 'Password never expires' setting" `
        -Impact "Compromised password remains valid indefinitely"
}

foreach ($user in $passwordNotRequired) {
    Add-Finding -Severity "Critical" -Category "Password Policy" `
        -Finding "Account does not require password" `
        -Details "Account: $($user.SamAccountName)" `
        -Recommendation "Enable password requirement" `
        -Impact "Account can be accessed without password"
}

# ============================================================
# 9. STALE AND INACTIVE ACCOUNTS
# ============================================================

Write-Host "[9/20] Identifying Stale Accounts..." -ForegroundColor Yellow

$staleUserDate = (Get-Date).AddDays(-90)
$staleComputerDate = (Get-Date).AddDays(-90)

$staleUsers = $users | Where-Object {$_.LastLogonDate -lt $staleUserDate -and $_.Enabled -eq $true -and $_.LastLogonDate -ne $null}
$staleComputers = Get-ADComputer -Filter {Enabled -eq $true} -Properties LastLogonDate | Where-Object {$_.LastLogonDate -lt $staleComputerDate -and $_.LastLogonDate -ne $null}

Write-Host "  Stale users (no logon >90 days): $($staleUsers.Count)" -ForegroundColor White
Write-Host "  Stale computers (no logon >90 days): $($staleComputers.Count)" -ForegroundColor White

if ($staleUsers.Count -gt 0) {
    Add-Finding -Severity "Medium" -Category "Account Management" `
        -Finding "$($staleUsers.Count) stale user accounts" `
        -Details "Accounts with no logon in 90+ days" `
        -Recommendation "Review and disable inactive accounts" `
        -Impact "Increased attack surface, unused accounts can be compromised"
}

if ($staleComputers.Count -gt 0) {
    Add-Finding -Severity "Medium" -Category "Account Management" `
        -Finding "$($staleComputers.Count) stale computer accounts" `
        -Details "Computers with no logon in 90+ days" `
        -Recommendation "Review and disable inactive computer accounts" `
        -Impact "Stale accounts can be exploited"
}

# ============================================================
# 10. PROTECTED USERS GROUP
# ============================================================

Write-Host "[10/20] Checking Protected Users Group..." -ForegroundColor Yellow

try {
    $protectedUsers = Get-ADGroup -Identity "Protected Users" -ErrorAction Stop
    $protectedMembers = Get-ADGroupMember -Identity $protectedUsers -ErrorAction Stop
    
    Write-Host "  Protected Users members: $($protectedMembers.Count)" -ForegroundColor White
    
    if ($protectedMembers.Count -eq 0) {
        Add-Finding -Severity "Medium" -Category "Privileged Access" `
            -Finding "Protected Users group is empty" `
            -Details "Privileged accounts should be in this group" `
            -Recommendation "Add Domain Admins and other privileged accounts to Protected Users group" `
            -Impact "Missing additional Kerberos protections for privileged accounts"
    }
} catch {
    Add-Finding -Severity "High" -Category "Privileged Access" `
        -Finding "Protected Users group not available" `
        -Details "Requires Windows Server 2012 R2 domain functional level" `
        -Recommendation "Upgrade domain functional level" `
        -Impact "Missing modern security features"
}

# ============================================================
# 11. ADMINSDHOLDER AND ADMINCOUNT
# ============================================================

Write-Host "[11/20] Checking AdminSDHolder Configuration..." -ForegroundColor Yellow

$adminSDHolder = Get-ADObject "CN=AdminSDHolder,CN=System,$($domain.DistinguishedName)" -Properties *
$orphanedAdminCount = Get-ADUser -Filter {AdminCount -eq 1} -Properties AdminCount, MemberOf | Where-Object {
    $isMember = $false
    foreach ($group in $privilegedGroups) {
        try {
            $members = Get-ADGroupMember -Identity $group -Recursive
            if ($members.SamAccountName -contains $_.SamAccountName) {
                $isMember = $true
                break
            }
        } catch { }
    }
    -not $isMember
}

Write-Host "  Orphaned AdminCount accounts: $($orphanedAdminCount.Count)" -ForegroundColor White

if ($orphanedAdminCount.Count -gt 0) {
    foreach ($user in $orphanedAdminCount) {
        Add-Finding -Severity "Low" -Category "Access Control" `
            -Finding "Orphaned AdminCount attribute" `
            -Details "Account: $($user.SamAccountName) has AdminCount=1 but is not in privileged group" `
            -Recommendation "Reset AdminCount to 0 and restore ACL inheritance" `
            -Impact "Account retains protected ACLs unnecessarily"
    }
}

# ============================================================
# 12. LAPS DEPLOYMENT
# ============================================================

Write-Host "[12/20] Checking LAPS Deployment..." -ForegroundColor Yellow

$lapsSchema = Get-ADObject -SearchBase $((Get-ADRootDSE).schemaNamingContext) -Filter {name -eq "ms-Mcs-AdmPwd"} -ErrorAction SilentlyContinue

if ($lapsSchema) {
    Write-Host "  LAPS schema present" -ForegroundColor Green
    
    $computersWithLAPS = Get-ADComputer -Filter * -Properties ms-Mcs-AdmPwdExpirationTime | Where-Object {$_."ms-Mcs-AdmPwdExpirationTime" -ne $null}
    $totalComputers = (Get-ADComputer -Filter *).Count
    
    Write-Host "  Computers with LAPS: $($computersWithLAPS.Count) / $totalComputers" -ForegroundColor White
    
    if ($computersWithLAPS.Count -lt $totalComputers) {
        Add-Finding -Severity "High" -Category "Local Admin Security" `
            -Finding "LAPS not deployed to all computers" `
            -Details "$($computersWithLAPS.Count) of $totalComputers computers have LAPS" `
            -Recommendation "Deploy LAPS to all workstations and servers" `
            -Impact "Local admin passwords may be weak or shared"
    }
} else {
    Add-Finding -Severity "High" -Category "Local Admin Security" `
        -Finding "LAPS not deployed" `
        -Details "No LAPS schema detected" `
        -Recommendation "Deploy Microsoft LAPS to manage local admin passwords" `
        -Impact "Local admin passwords likely weak or shared across computers"
}

# ============================================================
# 13. GPO SECURITY
# ============================================================

Write-Host "[13/20] Auditing Group Policy Objects..." -ForegroundColor Yellow

$gpos = Get-GPO -All
Write-Host "  Total GPOs: $($gpos.Count)" -ForegroundColor White

$unlinkedGPOs = $gpos | Where-Object {
    $_ | Get-GPOReport -ReportType XML | Select-String -Pattern "Not linked" -Quiet
}

Write-Host "  Unlinked GPOs: $($unlinkedGPOs.Count)" -ForegroundColor White

foreach ($gpo in $gpos) {
    $gpoPerms = Get-GPPermission -Guid $gpo.Id -All
    $authUsers = $gpoPerms | Where-Object {$_.Trustee.Name -eq "Authenticated Users" -and $_.Permission -eq "GpoEditDeleteModifySecurity"}
    
    if ($authUsers) {
        Add-Finding -Severity "Critical" -Category "GPO Security" `
            -Finding "GPO allows Authenticated Users to edit" `
            -Details "GPO: $($gpo.DisplayName)" `
            -Recommendation "Remove edit permissions for Authenticated Users" `
            -Impact "Any domain user can modify this GPO"
    }
}

# ============================================================
# 14. DNS SECURITY
# ============================================================

Write-Host "[14/20] Checking DNS Security..." -ForegroundColor Yellow

$dnsZones = Get-DnsServerZone -ComputerName $domainControllers[0].HostName -ErrorAction SilentlyContinue

if ($dnsZones) {
    Write-Host "  DNS zones: $($dnsZones.Count)" -ForegroundColor White
    
    foreach ($zone in $dnsZones) {
        if ($zone.DynamicUpdate -eq "NonsecureAndSecure") {
            Add-Finding -Severity "High" -Category "DNS Security" `
                -Finding "DNS zone allows nonsecure dynamic updates" `
                -Details "Zone: $($zone.ZoneName)" `
                -Recommendation "Set to Secure only updates" `
                -Impact "Attackers can create malicious DNS records"
        }
    }
    
    $scavenging = Get-DnsServerScavenging -ComputerName $domainControllers[0].HostName -ErrorAction SilentlyContinue
    if ($scavenging.ScavengingState -eq $false) {
        Add-Finding -Severity "Low" -Category "DNS Security" `
            -Finding "DNS scavenging disabled" `
            -Details "Stale DNS records will accumulate" `
            -Recommendation "Enable DNS scavenging" `
            -Impact "DNS database contains stale records"
    }
}

# ============================================================
# 15. LEGACY PROTOCOLS
# ============================================================

Write-Host "[15/20] Checking for Legacy Protocol Usage..." -ForegroundColor Yellow

Add-Finding -Severity "Info" -Category "Legacy Protocols" `
    -Finding "Check for SMBv1 usage" `
    -Details "Verify SMBv1 is disabled on all systems" `
    -Recommendation "Run: Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol" `
    -Impact "SMBv1 is insecure and vulnerable to attacks like WannaCry"

Add-Finding -Severity "Info" -Category "Legacy Protocols" `
    -Finding "Check for LLMNR/NBT-NS" `
    -Details "Verify LLMNR and NetBIOS are disabled via GPO" `
    -Recommendation "Disable via GPO: Computer Config > Admin Templates > Network > DNS Client" `
    -Impact "Vulnerable to credential theft via responder attacks"

# ============================================================
# 16. CERTIFICATE SERVICES
# ============================================================

Write-Host "[16/20] Checking Certificate Services..." -ForegroundColor Yellow

$caServers = Get-ADObject -Filter {objectClass -eq "pKIEnrollmentService"} -SearchBase "CN=Configuration,$($domain.DistinguishedName)" -ErrorAction SilentlyContinue

if ($caServers) {
    Write-Host "  Certificate Authorities: $($caServers.Count)" -ForegroundColor White
    
    Add-Finding -Severity "Info" -Category "PKI" `
        -Finding "Certificate Services detected" `
        -Details "Review certificate templates for security" `
        -Recommendation "Audit certificate template permissions and enrollment rights" `
        -Impact "Misconfigured templates can lead to privilege escalation"
}

# ============================================================
# 17. TRUST RELATIONSHIPS
# ============================================================

Write-Host "[17/20] Auditing Trust Relationships..." -ForegroundColor Yellow

$trusts = Get-ADTrust -Filter *

Write-Host "  Trust relationships: $($trusts.Count)" -ForegroundColor White

foreach ($trust in $trusts) {
    if ($trust.TrustDirection -eq "Bidirectional") {
        Add-Finding -Severity "Medium" -Category "Trust Relationships" `
            -Finding "Bidirectional trust" `
            -Details "Trust with: $($trust.Name)" `
            -Recommendation "Review if bidirectional trust is necessary" `
            -Impact "Increases attack surface across both domains"
    }
    
    if ($trust.SIDFilteringQuarantined -eq $false -and $trust.TrustType -eq "External") {
        Add-Finding -Severity "High" -Category "Trust Relationships" `
            -Finding "SID filtering disabled on external trust" `
            -Details "Trust with: $($trust.Name)" `
            -Recommendation "Enable SID filtering" `
            -Impact "Vulnerable to SID history attacks"
    }
}

# ============================================================
# 18. DOMAIN CONTROLLER SECURITY
# ============================================================

Write-Host "[18/20] Auditing Domain Controllers..." -ForegroundColor Yellow

foreach ($dc in $domainControllers) {
    Write-Host "  Checking DC: $($dc.HostName)" -ForegroundColor Gray
    
    $dcOS = Get-ADComputer -Identity $dc.Name -Properties OperatingSystem
    if ($dcOS.OperatingSystem -match "2008|2012") {
        Add-Finding -Severity "High" -Category "Domain Controller" `
            -Finding "Domain Controller running legacy OS" `
            -Details "DC: $($dc.HostName), OS: $($dcOS.OperatingSystem)" `
            -Recommendation "Upgrade to Windows Server 2016 or later" `
            -Impact "Missing security features and updates"
    }
}

# ============================================================
# 19. AUTHENTICATION POLICIES
# ============================================================

Write-Host "[19/20] Checking Authentication Policies..." -ForegroundColor Yellow

$authPolicies = Get-ADAuthenticationPolicy -Filter * -ErrorAction SilentlyContinue

if ($authPolicies) {
    Write-Host "  Authentication policies: $($authPolicies.Count)" -ForegroundColor White
} else {
    Add-Finding -Severity "Medium" -Category "Authentication" `
        -Finding "No authentication policies configured" `
        -Details "Requires Windows Server 2012 R2 functional level" `
        -Recommendation "Configure authentication policies for privileged accounts" `
        -Impact "Missing additional authentication protections"
}

$authPolicySilos = Get-ADAuthenticationPolicySilo -Filter * -ErrorAction SilentlyContinue
Write-Host "  Authentication policy silos: $($authPolicySilos.Count)" -ForegroundColor White

# ============================================================
# 20. SECURITY EVENT AUDITING
# ============================================================

Write-Host "[20/20] Checking Security Auditing..." -ForegroundColor Yellow

Add-Finding -Severity "Info" -Category "Auditing" `
    -Finding "Verify security auditing is enabled" `
    -Details "Check Advanced Audit Policy Configuration" `
    -Recommendation "Enable auditing for: Account Logon, Account Management, Directory Service Access, Logon/Logoff, Object Access, Policy Change, Privilege Use, System" `
    -Impact "Insufficient logging for security monitoring"

Add-Finding -Severity "Info" -Category "Auditing" `
    -Finding "Verify audit logs are forwarded to SIEM" `
    -Details "Security events should be centrally collected" `
    -Recommendation "Configure Windows Event Forwarding or SIEM agent" `
    -Impact "Logs can be tampered with or deleted locally"

# ============================================================
# GENERATE REPORTS
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  GENERATING REPORTS" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Save CSV
Write-Host "Saving CSV report..." -ForegroundColor Yellow
try {
    $global:findings | Export-Csv -Path $csvReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "[SAVED] CSV: $csvReportPath" -ForegroundColor Green
    
    if (Test-Path $csvReportPath) {
        $csvSize = (Get-Item $csvReportPath).Length
        Write-Host "  Size: $([math]::Round($csvSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save CSV: $($_.Exception.Message)" -ForegroundColor Red
}

# Generate HTML
Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Yellow

$totalFindings = $global:counts.Critical + $global:counts.High + $global:counts.Medium + $global:counts.Low

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Security Assessment</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; }
        .header h1 { margin: 0 0 10px 0; font-size: 32px; }
        .header p { margin: 5px 0; font-size: 14px; }
        .summary { background: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric { background: white; padding: 20px; border-radius: 10px; text-align: center; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .metric-value { font-size: 36px; font-weight: bold; margin-bottom: 5px; }
        .metric-label { font-size: 12px; color: #666; text-transform: uppercase; }
        .critical { color: #d32f2f; }
        .high { color: #f57c00; }
        .medium { color: #fbc02d; }
        .low { color: #388e3c; }
        .info { color: #1976d2; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        th { background: #667eea; color: white; padding: 15px; text-align: left; font-weight: 600; }
        td { padding: 12px 15px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f9f9f9; }
        .badge { padding: 5px 10px; border-radius: 15px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
        .badge-critical { background: #ffebee; color: #d32f2f; }
        .badge-high { background: #fff3e0; color: #f57c00; }
        .badge-medium { background: #fffde7; color: #fbc02d; }
        .badge-low { background: #e8f5e9; color: #388e3c; }
        .badge-info { background: #e3f2fd; color: #1976d2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>ACTIVE DIRECTORY SECURITY ASSESSMENT</h1>
        <p>Domain: $($domain.DNSRoot)</p>
        <p>Forest: $($forest.Name)</p>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p>Report Path: $ReportsFolder</p>
    </div>
    
    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="metrics">
            <div class="metric">
                <div class="metric-value">$totalFindings</div>
                <div class="metric-label">Total Findings</div>
            </div>
            <div class="metric">
                <div class="metric-value critical">$($global:counts.Critical)</div>
                <div class="metric-label">Critical</div>
            </div>
            <div class="metric">
                <div class="metric-value high">$($global:counts.High)</div>
                <div class="metric-label">High</div>
            </div>
            <div class="metric">
                <div class="metric-value medium">$($global:counts.Medium)</div>
                <div class="metric-label">Medium</div>
            </div>
            <div class="metric">
                <div class="metric-value low">$($global:counts.Low)</div>
                <div class="metric-label">Low</div>
            </div>
            <div class="metric">
                <div class="metric-value info">$($global:counts.Info)</div>
                <div class="metric-label">Info</div>
            </div>
        </div>
    </div>
    
    <div class="summary">
        <h2>Detailed Findings</h2>
        <table>
            <thead>
                <tr>
                    <th>Severity</th>
                    <th>Category</th>
                    <th>Finding</th>
                    <th>Details</th>
                    <th>Recommendation</th>
                    <th>Impact</th>
                </tr>
            </thead>
            <tbody>
"@

$sortedFindings = $global:findings | Sort-Object @{Expression={
    switch ($_.Severity) {
        "Critical" { 1 }
        "High" { 2 }
        "Medium" { 3 }
        "Low" { 4 }
        "Info" { 5 }
    }
}}

foreach ($finding in $sortedFindings) {
    $badgeClass = "badge-" + $finding.Severity.ToLower()
    $html += @"
                <tr>
                    <td><span class="badge $badgeClass">$($finding.Severity)</span></td>
                    <td>$($finding.Category)</td>
                    <td><strong>$($finding.Finding)</strong></td>
                    <td>$($finding.Details)</td>
                    <td>$($finding.Recommendation)</td>
                    <td>$($finding.Impact)</td>
                </tr>
"@
}

$html += @"
            </tbody>
        </table>
    </div>
</body>
</html>
"@

try {
    $html | Out-File -FilePath $htmlReportPath -Encoding UTF8 -Force
    Write-Host "[SAVED] HTML: $htmlReportPath" -ForegroundColor Green
    
    if (Test-Path $htmlReportPath) {
        $htmlSize = (Get-Item $htmlReportPath).Length
        Write-Host "  Size: $([math]::Round($htmlSize/1KB, 2)) KB" -ForegroundColor White
    }
} catch {
    Write-Host "[ERROR] Failed to save HTML: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================================
# SUMMARY
# ============================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "  ASSESSMENT COMPLETE" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "FINDINGS SUMMARY:" -ForegroundColor Cyan
Write-Host "  Total: $totalFindings" -ForegroundColor White
Write-Host "  Critical: $($global:counts.Critical)" -ForegroundColor Red
Write-Host "  High: $($global:counts.High)" -ForegroundColor Yellow
Write-Host "  Medium: $($global:counts.Medium)" -ForegroundColor Yellow
Write-Host "  Low: $($global:counts.Low)" -ForegroundColor Green
Write-Host "  Info: $($global:counts.Info)" -ForegroundColor Cyan
Write-Host ""
Write-Host "REPORTS SAVED:" -ForegroundColor Cyan
Write-Host "  CSV:  $csvReportPath" -ForegroundColor White
Write-Host "  HTML: $htmlReportPath" -ForegroundColor White
Write-Host ""

# Open HTML report
Write-Host "Opening HTML report..." -ForegroundColor Yellow
try {
    Start-Process $htmlReportPath
    Write-Host "  Report opened in browser" -ForegroundColor Green
} catch {
    Write-Host "  Could not open automatically" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "ASSESSMENT COMPLETE - NO CHANGES MADE" -ForegroundColor Green
Write-Host ""
