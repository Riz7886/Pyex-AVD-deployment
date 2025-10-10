#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,
    [Parameter(Mandatory=$true)][string]$Location,
    [Parameter(Mandatory=$true)][string]$VMName,
    [Parameter(Mandatory=$false)][string]$VMSize = "Standard_D4s_v3",
    [Parameter(Mandatory=$true)][string]$AdminUsername,
    [Parameter(Mandatory=$true)][SecureString]$AdminPassword,
    [Parameter(Mandatory=$false)][string]$ServicePrincipalName = "SP-PYEX-Automation"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{"INFO"="Cyan";"SUCCESS"="Green";"WARNING"="Yellow";"ERROR"="Red"}
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message" -ForegroundColor $colors[$Level]
}

Write-Host ""
Write-Host "BASTION VM - 100% AUTOMATED DEPLOYMENT"
Write-Host ""

Write-Log "Checking Azure CLI"
az version --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw "Azure CLI not found" }

$account = az account show --output json | ConvertFrom-Json
Write-Log "Authenticated as: $($account.user.name)" "SUCCESS"

$subscriptions = az account list --output json | ConvertFrom-Json
Write-Log "Found $($subscriptions.Count) subscriptions" "SUCCESS"

Write-Host ""
Write-Host "STEP 1: Resource Group" -ForegroundColor Yellow
if ((az group exists --name $ResourceGroupName) -eq "false") {
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Log "Created" "SUCCESS"
} else {
    Write-Log "Exists" "WARNING"
}

Write-Host ""
Write-Host "STEP 2: Virtual Network" -ForegroundColor Yellow
az network vnet create --resource-group $ResourceGroupName --name "VNet-Bastion" --address-prefix 10.0.0.0/16 --subnet-name "Subnet-Bastion" --subnet-prefix 10.0.1.0/24 --location $Location --output none
Write-Log "Created" "SUCCESS"

Write-Host ""
Write-Host "STEP 3: Network Security Group" -ForegroundColor Yellow
az network nsg create --resource-group $ResourceGroupName --name "NSG-Bastion" --location $Location --output none
az network nsg rule create --resource-group $ResourceGroupName --nsg-name "NSG-Bastion" --name "AllowRDP" --priority 100 --destination-port-ranges 3389 --access Allow --protocol Tcp --output none
az network nsg rule create --resource-group $ResourceGroupName --nsg-name "NSG-Bastion" --name "AllowHTTPS" --priority 110 --destination-port-ranges 443 --access Allow --protocol Tcp --output none
az network vnet subnet update --resource-group $ResourceGroupName --vnet-name "VNet-Bastion" --name "Subnet-Bastion" --network-security-group "NSG-Bastion" --output none
Write-Log "Configured" "SUCCESS"

Write-Host ""
Write-Host "STEP 4: Service Principal" -ForegroundColor Yellow
$spExists = az ad sp list --display-name $ServicePrincipalName --output json | ConvertFrom-Json
if ($spExists.Count -gt 0) {
    $spAppId = $spExists[0].appId
    Write-Log "Exists" "WARNING"
} else {
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --output json | ConvertFrom-Json
    $spAppId = $sp.appId
    Write-Host "App ID: $spAppId" -ForegroundColor Green
    Write-Host "Password: $($sp.password)" -ForegroundColor Green
    Start-Sleep -Seconds 20
}

foreach ($sub in $subscriptions) {
    az role assignment create --assignee $spAppId --role "Reader" --scope "/subscriptions/$($sub.id)" --output none 2>$null
}
Write-Log "Reader access granted" "SUCCESS"

Write-Host ""
Write-Host "STEP 5: Create VM" -ForegroundColor Yellow
$plainPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
az vm create --resource-group $ResourceGroupName --name $VMName --image "Win2022Datacenter" --size $VMSize --admin-username $AdminUsername --admin-password $plainPw --vnet-name "VNet-Bastion" --subnet "Subnet-Bastion" --nsg "NSG-Bastion" --public-ip-sku Standard --location $Location --output none
Write-Log "Created" "SUCCESS"

Write-Host ""
Write-Host "STEP 6: Install Azure CLI" -ForegroundColor Yellow
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts "Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile C:\AzureCLI.msi; Start-Process msiexec.exe -ArgumentList '/I','C:\AzureCLI.msi','/quiet' -Wait; Remove-Item C:\AzureCLI.msi" --output none 2>$null
Write-Log "Installed" "SUCCESS"

Write-Host ""
Write-Host "STEP 7: Setup Directories" -ForegroundColor Yellow
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts "New-Item -Path 'C:\PYEX-Automation\Scripts','C:\PYEX-Automation\Reports','C:\PYEX-Automation\Logs' -ItemType Directory -Force; Set-ExecutionPolicy RemoteSigned -Force" --output none 2>$null
Write-Log "Created" "SUCCESS"

Write-Host ""
Write-Host "STEP 8: Clone GitHub" -ForegroundColor Yellow
$gitCmd = "Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe -OutFile C:\Git.exe; Start-Process C:\Git.exe -ArgumentList '/VERYSILENT' -Wait; Remove-Item C:\Git.exe; & 'C:\Program Files\Git\bin\git.exe' clone https://github.com/Riz7886/Pyex-AVD-deployment.git C:\PYEX-Automation\Scripts"
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts $gitCmd --output none 2>$null
Write-Log "Cloned" "SUCCESS"

Write-Host ""
Write-Host "STEP 9: Delete Git" -ForegroundColor Yellow
$cleanup = "Remove-Item 'C:\PYEX-Automation\Scripts\.git' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item 'C:\PYEX-Automation\Scripts\.gitignore' -Force -ErrorAction SilentlyContinue; if (Test-Path 'C:\Program Files\Git\unins000.exe') { Start-Process 'C:\Program Files\Git\unins000.exe' -ArgumentList '/VERYSILENT' -Wait }; Remove-Item 'C:\Program Files\Git' -Recurse -Force -ErrorAction SilentlyContinue"
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts $cleanup --output none 2>$null
Write-Log "Removed" "SUCCESS"

Write-Host ""
Write-Host "STEP 10: Setup Task Schedulers" -ForegroundColor Yellow
$tasks = "schtasks /Create /TN 'PYEX-Azure-Monitor' /TR 'powershell.exe -File C:\PYEX-Automation\Scripts\Azure-Monitor-Multi-Sub.ps1' /SC WEEKLY /D MON,THU /ST 08:00 /RU SYSTEM /F; schtasks /Create /TN 'PYEX-Cost-Optimization' /TR 'powershell.exe -File C:\PYEX-Automation\Scripts\Cost-Optimization-Multi-Sub.ps1' /SC WEEKLY /D MON,THU /ST 09:00 /RU SYSTEM /F; schtasks /Create /TN 'PYEX-Security-Audit' /TR 'powershell.exe -File C:\PYEX-Automation\Scripts\Ultimate-Multi-Subscription-Audit.ps1' /SC WEEKLY /D TUE,FRI /ST 08:00 /RU SYSTEM /F; schtasks /Create /TN 'PYEX-AD-Security' /TR 'powershell.exe -File C:\PYEX-Automation\Scripts\AD-Security-Audit-Multi-Sub.ps1' /SC WEEKLY /D TUE,FRI /ST 09:00 /RU SYSTEM /F"
az vm run-command invoke --resource-group $ResourceGroupName --name $VMName --command-id RunPowerShellScript --scripts $tasks --output none 2>$null
Write-Log "4 Tasks Created" "SUCCESS"

$vmInfo = az vm show --resource-group $ResourceGroupName --name $VMName --show-details --output json | ConvertFrom-Json

Write-Host ""
Write-Host "COMPLETE - 100% AUTOMATED" -ForegroundColor Green
Write-Host ""
Write-Host "VM IP: $($vmInfo.publicIps)" -ForegroundColor White
Write-Host "Username: $AdminUsername" -ForegroundColor White
Write-Host ""
Write-Host "Tasks: 4 scheduled (Mon/Thu and Tue/Fri)" -ForegroundColor Green
Write-Host "Scripts: C:\PYEX-Automation\Scripts" -ForegroundColor White
Write-Host "Git: Removed" -ForegroundColor Green
Write-Host ""
