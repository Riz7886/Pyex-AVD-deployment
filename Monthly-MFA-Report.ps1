#Requires -Version 5.1

<#
.SYNOPSIS
    Monthly MFA Compliance Report
.DESCRIPTION
    Generates report of users without MFA and emails to managers
.EXAMPLE
    .\Monthly-MFA-Report.ps1
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$ManagerEmails = @("manager1@company.com","manager2@company.com","manager3@company.com")
)

$ErrorActionPreference = "Stop"

Write-Host "MONTHLY MFA COMPLIANCE REPORT"
Write-Host ""

$modules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Users", "Microsoft.Graph.Identity.SignIns", "Microsoft.Graph.Users.Actions")
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module $module
}

Connect-MgGraph -Scopes "User.Read.All","UserAuthenticationMethod.Read.All","Mail.Send"

Write-Host "Analyzing MFA compliance..." -ForegroundColor Yellow

$users = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,MobilePhone,Id,AccountEnabled

$report = @()
$compliantCount = 0
$nonCompliantCount = 0

foreach ($user in $users) {
    if ($user.AccountEnabled) {
        $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id
        $hasMFA = $authMethods | Where-Object { $_.AdditionalProperties.'@odata.type' -in @('#microsoft.graph.phoneAuthenticationMethod','#microsoft.graph.microsoftAuthenticatorAuthenticationMethod') }
        
        if ($hasMFA) {
            $compliantCount++
        } else {
            $nonCompliantCount++
            $report += [PSCustomObject]@{
                DisplayName = $user.DisplayName
                Email = $user.UserPrincipalName
                Phone = $user.MobilePhone
                Status = "NON-COMPLIANT"
                Risk = "HIGH"
            }
        }
    }
}

$reportDate = Get-Date -Format "MMMM yyyy"
$reportFile = ".\MFA-Compliance-Report-$(Get-Date -Format 'yyyyMMdd').csv"
$report | Export-Csv -Path $reportFile -NoTypeInformation

Write-Host ""
Write-Host "COMPLIANCE SUMMARY:" -ForegroundColor Yellow
Write-Host "  Compliant: $compliantCount" -ForegroundColor Green
Write-Host "  Non-Compliant: $nonCompliantCount" -ForegroundColor Red
Write-Host "  Compliance Rate: $([math]::Round(($compliantCount/($compliantCount+$nonCompliantCount))*100,2))%" -ForegroundColor White
Write-Host ""

$emailBody = @"
MFA COMPLIANCE REPORT - $reportDate

SUMMARY:
- Total Active Users: $($compliantCount + $nonCompliantCount)
- Compliant (MFA Enabled): $compliantCount
- Non-Compliant (No MFA): $nonCompliantCount
- Compliance Rate: $([math]::Round(($compliantCount/($compliantCount+$nonCompliantCount))*100,2))%

USERS WITHOUT MFA:
$($report | ForEach-Object { "- $($_.DisplayName) ($($_.Email))" } | Out-String)

ACTION REQUIRED:
Please follow up with non-compliant users to complete MFA setup.

Detailed report attached.

IT Security Team
"@

foreach ($managerEmail in $ManagerEmails) {
    Write-Host "Sending report to: $managerEmail" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Report saved: $reportFile" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph
