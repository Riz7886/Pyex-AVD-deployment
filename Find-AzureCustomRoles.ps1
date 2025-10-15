# Find-AzureCustomRoles.ps1
# Script to find custom Azure roles created for Data Engineers
# Created to detect roles potentially created via Jira ticket by Robert Schroedle

param(
    [string]$SubscriptionId = "",
    [string]$OutputPath = "./role-audit-results.json",
    [switch]$ExportCSV
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Azure Custom Role Finder" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is installed
try {
    $azVersion = az version 2>$null
    if (-not $azVersion) {
        throw "Azure CLI not found"
    }
} catch {
    Write-Host "ERROR: Azure CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
    exit 1
}

# Login check
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Please login to Azure..." -ForegroundColor Yellow
    az login --scope https://management.core.windows.net//.default
    $account = az account show | ConvertFrom-Json
}

Write-Host "Connected to subscription: $($account.name)" -ForegroundColor Green
Write-Host ""

if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
}

$rolePatterns = @(
    "*Data Engineer*",
    "*data*engineer*high*",
    "*data*engineer*limit*",
    "*data*engineer*read*"
)

Write-Host "Searching for custom roles..." -ForegroundColor Yellow
Write-Host ""

$customRoles = az role definition list --custom-role-only true | ConvertFrom-Json
$foundRoles = @()

foreach ($role in $customRoles) {
    foreach ($pattern in $rolePatterns) {
        if ($role.roleName -like $pattern) {
            $foundRoles += $role
            break
        }
    }
}

if ($foundRoles.Count -eq 0) {
    Write-Host "No Data Engineer custom roles found." -ForegroundColor Yellow
} else {
    Write-Host "Found $($foundRoles.Count) matching custom role(s):" -ForegroundColor Green
    Write-Host ""
    
    $results = @()
    
    foreach ($role in $foundRoles) {
        Write-Host "Role Name: $($role.roleName)" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "Role ID: $($role.name)" -ForegroundColor Gray
        Write-Host "Description: $($role.description)" -ForegroundColor White
        
        Write-Host "`nChecking role assignments..." -ForegroundColor Yellow
        $assignments = az role assignment list --role $role.name | ConvertFrom-Json
        
        $assignmentDetails = @()
        if ($assignments.Count -gt 0) {
            Write-Host "Assigned to $($assignments.Count) principal(s):" -ForegroundColor Green
            foreach ($assignment in $assignments) {
                $principalName = $assignment.principalName
                if (-not $principalName) { $principalName = "N/A" }
                
                Write-Host "  - $principalName ($($assignment.principalType))" -ForegroundColor White
                
                $assignmentDetails += @{
                    PrincipalName = $principalName
                    PrincipalType = $assignment.principalType
                    Scope = $assignment.scope
                    CreatedOn = $assignment.createdOn
                    CreatedBy = $assignment.createdBy
                }
            }
        }
        
        $robertAssignment = $assignments | Where-Object { 
            $_.createdBy -like "*Robert*Schroedle*" -or 
            $_.createdBy -like "*Schroedle*" -or
            $_.principalName -like "*Robert*Schroedle*"
        }
        
        if ($robertAssignment) {
            Write-Host "`n*** Role associated with Robert Schroedle ***" -ForegroundColor Magenta
        }
        
        $results += @{
            RoleName = $role.roleName
            RoleId = $role.name
            Description = $role.description
            Assignments = $assignmentDetails
            AssociatedWithRobertSchroedle = ($null -ne $robertAssignment)
        }
    }
    
    Write-Host "`nExporting results to: $OutputPath" -ForegroundColor Yellow
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Results exported successfully!" -ForegroundColor Green
    
    if ($ExportCSV) {
        $csvPath = $OutputPath -replace '\.json$', '.csv'
        $csvData = $results | ForEach-Object {
            [PSCustomObject]@{
                RoleName = $_.RoleName
                RoleId = $_.RoleId
                Description = $_.Description
                AssignmentCount = $_.Assignments.Count
                AssociatedWithRobertSchroedle = $_.AssociatedWithRobertSchroedle
            }
        }
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "CSV exported to: $csvPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Scan Complete!" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
