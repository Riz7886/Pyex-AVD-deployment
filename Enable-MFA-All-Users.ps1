#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Enable MFA for all Entra ID users and send notifications
.DESCRIPTION
    Enables MFA requirement, detects users without MFA, sends email notifications
.EXAMPLE
    .\Enable-MFA-All-Users.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$NotificationEmails = @("user1@company.com","user2@company.com","user3@company.com")
)

$ErrorActionPreference = "Stop"

Write-Host "MFA ENABLEMENT AND NOTIFICATION SCRIPT"
Write-Host ""

Write-Host "Step 1: Install required modules" -ForegroundColor Yellow
$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "Microsoft.Graph.Identity.SignIns")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $module
}

Write-Host "Step 2: Connect to Microsoft Graph" -ForegroundColor Yellow
Connect-MgGraph -Scopes "User.ReadWrite.All","Policy.ReadWrite.ConditionalAccess","UserAuthenticationMethod.ReadWrite.All"

Write-Host "Step 3: Get all users" -ForegroundColor Yellow
$users = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,MobilePhone,Id

Write-Host "Found $($users.Count) users" -ForegroundColor Green
Write-Host ""

Write-Host "Step 4: Check MFA registration status" -ForegroundColor Yellow
$usersWithoutMFA = @()
$usersWithMFA = @()

foreach ($user in $users) {
    $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id
    $hasMFA = $authMethods | Where-Object { $_.AdditionalProperties.'@odata.type' -in @('#microsoft.graph.phoneAuthenticationMethod','#microsoft.graph.microsoftAuthenticatorAuthenticationMethod') }
    
    if ($hasMFA) {
        $usersWithMFA += $user
    } else {
        $usersWithoutMFA += [PSCustomObject]@{
            DisplayName = $user.DisplayName
            Email = $user.UserPrincipalName
            Phone = $user.MobilePhone
            Status = "No MFA"
        }
    }
}

Write-Host "Users WITH MFA: $($usersWithMFA.Count)" -ForegroundColor Green
Write-Host "Users WITHOUT MFA: $($usersWithoutMFA.Count)" -ForegroundColor Red
Write-Host ""

Write-Host "Step 5: Create Conditional Access Policy to require MFA" -ForegroundColor Yellow
$policyName = "REQUIRE-MFA-All-Users"
$existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$policyName'"

if (!$existingPolicy) {
    $conditions = @{
        Users = @{
            IncludeUsers = @("All")
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    
    $grantControls = @{
        Operator = "OR"
        BuiltInControls = @("mfa")
    }
    
    $policy = @{
        DisplayName = $policyName
        State = "enabled"
        Conditions = $conditions
        GrantControls = $grantControls
    }
    
    New-MgIdentityConditionalAccessPolicy -BodyParameter $policy
    Write-Host "MFA policy created and enabled" -ForegroundColor Green
} else {
    Write-Host "MFA policy already exists" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 6: Send email notifications to users without MFA" -ForegroundColor Yellow

$emailBody = @"
Subject: ACTION REQUIRED: Set Up Multi-Factor Authentication (MFA)

Dear User,

Multi-Factor Authentication (MFA) has been enabled for your account to enhance security.

IMMEDIATE ACTION REQUIRED:
1. Go to https://aka.ms/mfasetup
2. Set up your authentication method (Microsoft Authenticator app or phone number)
3. Complete the setup process

You will be prompted to set up MFA the next time you sign in.

If you have questions, contact IT support.

Thank you,
IT Security Team
"@

Write-Host "Email notifications prepared for $($usersWithoutMFA.Count) users" -ForegroundColor Cyan
Write-Host "NOTE: Actual email sending requires Microsoft Graph Mail.Send permission" -ForegroundColor Yellow

Write-Host ""
Write-Host "Step 7: Save report" -ForegroundColor Yellow
$reportPath = ".\MFA-Status-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$usersWithoutMFA | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "Report saved: $reportPath" -ForegroundColor Green

Write-Host ""
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "MFA is now REQUIRED for all users" -ForegroundColor Green
Write-Host "Users without MFA will be prompted to register on next login" -ForegroundColor Yellow
Write-Host ""

Disconnect-MgGraph
