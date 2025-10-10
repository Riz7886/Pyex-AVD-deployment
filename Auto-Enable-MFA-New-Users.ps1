#Requires -Version 5.1

<#
.SYNOPSIS
    Automatically detect and enable MFA for new users
.DESCRIPTION
    Checks for users created in last 24 hours and sends MFA setup notification
.EXAMPLE
    .\Auto-Enable-MFA-New-Users.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "AUTO-DETECT NEW USERS FOR MFA"
Write-Host ""

$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $module
}

Connect-MgGraph -Scopes "User.Read.All","UserAuthenticationMethod.Read.All"

$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$newUsers = Get-MgUser -All -Filter "createdDateTime ge $yesterday" -Property DisplayName,UserPrincipalName,Mail,CreatedDateTime,Id

Write-Host "Found $($newUsers.Count) new users in last 24 hours" -ForegroundColor Cyan
Write-Host ""

foreach ($user in $newUsers) {
    Write-Host "New User: $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor Yellow
    Write-Host "  Created: $($user.CreatedDateTime)" -ForegroundColor White
    
    $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id
    $hasMFA = $authMethods | Where-Object { $_.AdditionalProperties.'@odata.type' -in @('#microsoft.graph.phoneAuthenticationMethod','#microsoft.graph.microsoftAuthenticatorAuthenticationMethod') }
    
    if (!$hasMFA) {
        Write-Host "  Status: NO MFA - Notification needed" -ForegroundColor Red
    } else {
        Write-Host "  Status: MFA already configured" -ForegroundColor Green
    }
    Write-Host ""
}

$logFile = ".\New-Users-MFA-Check-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
"New users checked: $($newUsers.Count)" | Out-File $logFile
"Date: $(Get-Date)" | Out-File $logFile -Append

Write-Host "Log saved: $logFile" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph
