# ================================================================
# AZURE + TERRAFORM COMPLETE INSTALLATION SCRIPT
# Run this on your work laptop as Administrator
# ================================================================

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "AZURE + TERRAFORM - COMPLETE INSTALLATION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Please run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "Running as Administrator: OK" -ForegroundColor Green
Write-Host ""

# Install Chocolatey
Write-Host "STEP 1: Installing Chocolatey..." -ForegroundColor Yellow
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Write-Host "  Chocolatey installed!" -ForegroundColor Green
} else {
    Write-Host "  Chocolatey already installed" -ForegroundColor Green
}
Write-Host ""

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Install Azure CLI
Write-Host "STEP 2: Installing Azure CLI..." -ForegroundColor Yellow
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "  Downloading Azure CLI (this takes 2-3 minutes)..."
    choco install azure-cli -y
    Write-Host "  Azure CLI installed!" -ForegroundColor Green
} else {
    Write-Host "  Azure CLI already installed" -ForegroundColor Green
}
Write-Host ""

# Install Terraform
Write-Host "STEP 3: Installing Terraform..." -ForegroundColor Yellow
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "  Downloading Terraform..."
    choco install terraform -y
    Write-Host "  Terraform installed!" -ForegroundColor Green
} else {
    Write-Host "  Terraform already installed" -ForegroundColor Green
}
Write-Host ""

# Install Git
Write-Host "STEP 4: Installing Git..." -ForegroundColor Yellow
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  Downloading Git..."
    choco install git -y
    Write-Host "  Git installed!" -ForegroundColor Green
} else {
    Write-Host "  Git already installed" -ForegroundColor Green
}
Write-Host ""

# Refresh PATH again
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Install PowerShell Modules
Write-Host "STEP 5: Installing PowerShell Azure Modules..." -ForegroundColor Yellow
Write-Host "  (This may take 5-10 minutes, please wait...)" -ForegroundColor Yellow

if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "  Installing Az module..."
    Install-Module -Name Az -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck
    Write-Host "  Az module installed!" -ForegroundColor Green
} else {
    Write-Host "  Az module already installed" -ForegroundColor Green
}

if (-not (Get-Module -ListAvailable -Name AzureAD)) {
    Write-Host "  Installing AzureAD module..."
    Install-Module -Name AzureAD -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
    Write-Host "  AzureAD module installed!" -ForegroundColor Green
} else {
    Write-Host "  AzureAD module already installed" -ForegroundColor Green
}
Write-Host ""

# Configure PATH
Write-Host "STEP 6: Configuring System PATH..." -ForegroundColor Yellow
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$pathsToAdd = @(
    "C:\ProgramData\chocolatey\bin",
    "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin",
    "C:\Program Files\Git\cmd"
)

foreach ($path in $pathsToAdd) {
    if ($machinePath -notlike "*$path*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$path", "Machine")
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    }
}
Write-Host "  PATH configured!" -ForegroundColor Green
Write-Host ""

# Configure Terraform
Write-Host "STEP 7: Configuring Terraform..." -ForegroundColor Yellow
$tfPluginDir = "$env:APPDATA\terraform.d\plugin-cache"
if (-not (Test-Path $tfPluginDir)) {
    New-Item -ItemType Directory -Path $tfPluginDir -Force | Out-Null
}
$terraformrcContent = @"
plugin_cache_dir = "$($tfPluginDir -replace '\\', '/')"
disable_checkpoint = true
"@
$terraformrcPath = "$env:APPDATA\terraform.rc"
$terraformrcContent | Out-File -FilePath $terraformrcPath -Encoding UTF8 -Force
Write-Host "  Terraform configured!" -ForegroundColor Green
Write-Host ""

# Set PowerShell Execution Policy
Write-Host "STEP 8: Configuring PowerShell..." -ForegroundColor Yellow
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Write-Host "  PowerShell configured!" -ForegroundColor Green
Write-Host ""

# Verify
Write-Host "STEP 9: Verifying installations..." -ForegroundColor Yellow
$allGood = $true

if (Get-Command az -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ Azure CLI: INSTALLED" -ForegroundColor Green
} else {
    Write-Host "  ✗ Azure CLI: FAILED" -ForegroundColor Red
    $allGood = $false
}

if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ Terraform: INSTALLED" -ForegroundColor Green
} else {
    Write-Host "  ✗ Terraform: FAILED" -ForegroundColor Red
    $allGood = $false
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ Git: INSTALLED" -ForegroundColor Green
} else {
    Write-Host "  ✗ Git: FAILED" -ForegroundColor Red
    $allGood = $false
}

if (Get-Module -ListAvailable -Name Az) {
    Write-Host "  ✓ Az Module: INSTALLED" -ForegroundColor Green
} else {
    Write-Host "  ✗ Az Module: FAILED" -ForegroundColor Red
    $allGood = $false
}
Write-Host ""

# Summary
Write-Host "================================================================" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "INSTALLATION COMPLETE - ALL TOOLS READY!" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. CLOSE this PowerShell window" -ForegroundColor White
    Write-Host "  2. OPEN a NEW PowerShell (as Administrator)" -ForegroundColor White
    Write-Host "  3. Run these commands:" -ForegroundColor White
    Write-Host ""
    Write-Host "     cd C:\Projects" -ForegroundColor Cyan
    Write-Host "     git clone https://github.com/Riz7886/Pyex-AVD-deployment.git" -ForegroundColor Cyan
    Write-Host "     cd Pyex-AVD-deployment\Pyx-AVD-deployment\DriversHealth-FrontDoor" -ForegroundColor Cyan
    Write-Host "     .\Deploy-Ultimate.ps1" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "INSTALLATION COMPLETE - SOME TOOLS NEED RESTART" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please CLOSE PowerShell and REOPEN as Administrator" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Press ENTER to exit..."
Read-Host
