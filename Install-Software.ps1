#Requires -Version 5.1
<#
.SYNOPSIS
    Install Reporting Software on Windows Server
.DESCRIPTION
    Installs Python, Power BI, SSMS, and other reporting tools
.EXAMPLE
    .\Install-Software.ps1
#>

param()

$ErrorActionPreference = "Continue"

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Test-Installed {
    param([string]$Name, [string]$Path)
    if (Test-Path $Path) {
        Write-Status "$Name already installed" "Green"
        return $true
    }
    return $false
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Software Installation for Reporting" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$tempDir = "C:\Temp"
if (-not (Test-Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
}

try {
    Write-Host "INSTALLING SOFTWARE..." -ForegroundColor Yellow
    Write-Host ""
    
    # Install Chocolatey
    Write-Status "Installing Chocolatey package manager..." "Cyan"
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Status "Chocolatey installed" "Green"
    } else {
        Write-Status "Chocolatey already installed" "Green"
    }
    
    Write-Host ""
    
    # Install Python
    Write-Status "Installing Python 3.11..." "Cyan"
    if (-not (Test-Installed "Python" "C:\Python311\python.exe")) {
        choco install python --version=3.11.0 -y --force
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
        Write-Status "Python installed" "Green"
    }
    
    # Install Git
    Write-Status "Installing Git..." "Cyan"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        choco install git -y --force
        Write-Status "Git installed" "Green"
    } else {
        Write-Status "Git already installed" "Green"
    }
    
    # Install PowerBI Desktop
    Write-Status "Installing Power BI Desktop..." "Cyan"
    if (-not (Test-Installed "Power BI" "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe")) {
        choco install powerbi -y --force
        Write-Status "Power BI installed" "Green"
    }
    
    # Install SQL Server Management Studio
    Write-Status "Installing SQL Server Management Studio..." "Cyan"
    if (-not (Test-Installed "SSMS" "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe")) {
        choco install sql-server-management-studio -y --force
        Write-Status "SSMS installed" "Green"
    }
    
    # Install 7-Zip
    Write-Status "Installing 7-Zip..." "Cyan"
    if (-not (Test-Installed "7-Zip" "C:\Program Files\7-Zip\7z.exe")) {
        choco install 7zip -y --force
        Write-Status "7-Zip installed" "Green"
    }
    
    # Install Notepad++
    Write-Status "Installing Notepad++..." "Cyan"
    if (-not (Test-Installed "Notepad++" "C:\Program Files\Notepad++\notepad++.exe")) {
        choco install notepadplusplus -y --force
        Write-Status "Notepad++ installed" "Green"
    }
    
    # Install Python packages
    Write-Status "Installing Python packages..." "Cyan"
    $pythonPackages = @("pandas", "openpyxl", "pyodbc", "sqlalchemy", "requests")
    foreach ($pkg in $pythonPackages) {
        python -m pip install $pkg --quiet
    }
    Write-Status "Python packages installed" "Green"
    
    # Create reporting directories
    Write-Status "Creating reporting directories..." "Cyan"
    $dirs = @("C:\Reports", "C:\Reports\Scripts", "C:\Reports\Output", "C:\Reports\Logs")
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Write-Status "Directories created" "Green"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " INSTALLATION COMPLETE!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "INSTALLED SOFTWARE:" -ForegroundColor Yellow
    Write-Host "  - Python 3.11" -ForegroundColor White
    Write-Host "  - Git" -ForegroundColor White
    Write-Host "  - Power BI Desktop" -ForegroundColor White
    Write-Host "  - SQL Server Management Studio" -ForegroundColor White
    Write-Host "  - 7-Zip" -ForegroundColor White
    Write-Host "  - Notepad++" -ForegroundColor White
    Write-Host "  - Python packages (pandas, openpyxl, etc.)" -ForegroundColor White
    Write-Host ""
    Write-Host "DIRECTORIES CREATED:" -ForegroundColor Yellow
    Write-Host "  C:\Reports" -ForegroundColor White
    Write-Host "  C:\Reports\Scripts" -ForegroundColor White
    Write-Host "  C:\Reports\Output" -ForegroundColor White
    Write-Host "  C:\Reports\Logs" -ForegroundColor White
    Write-Host ""
    Write-Host "Server is ready for reporting tasks!" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Some software may have been installed successfully." -ForegroundColor Yellow
    Write-Host ""
}
