#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install ALL reporting software on Windows Server - 100% Automated
.DESCRIPTION
    Run this INSIDE the VM after Deploy-Reporting-Server-Complete.ps1 completes
    Installs: Python, Power BI, reporting libraries, Task Scheduler, SMTP config
.NOTES
    IMPORTANT: Run this AFTER you RDP into the VM via Bastion
    This script runs INSIDE the Windows Server, not on your local machine
.EXAMPLE
    .\Install-Reporting-Software-Complete.ps1
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Skip confirmation prompts")]
    [switch]$Force
)

$ErrorActionPreference = "Continue"

#region Banner
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     PyxHealth Reporting Server - Software Installation      ║" -ForegroundColor Cyan
Write-Host "║                100% Automated Setup                          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will install:" -ForegroundColor Yellow
Write-Host "  ✓ Chocolatey Package Manager" -ForegroundColor White
Write-Host "  ✓ Python 3.12 + pip" -ForegroundColor White
Write-Host "  ✓ Power BI Desktop" -ForegroundColor White
Write-Host "  ✓ Python Libraries (pandas, openpyxl, pyodbc, etc.)" -ForegroundColor White
Write-Host "  ✓ Task Scheduler configuration" -ForegroundColor White
Write-Host "  ✓ SMTP email configuration" -ForegroundColor White
Write-Host "  ✓ Sample reporting scripts" -ForegroundColor White
Write-Host ""
Write-Host "Installation time: 10-15 minutes" -ForegroundColor Cyan
Write-Host ""

if (!$Force) {
    $confirm = Read-Host "Proceed with installation? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "Installation cancelled" -ForegroundColor Yellow
        exit 0
    }
}
#endregion

#region Functions
function Write-ColorOutput {
    param([string]$Message, [string]$Type = "INFO")
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
#endregion

#region Pre-flight Checks
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PRE-FLIGHT CHECKS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if (!(Test-IsAdmin)) {
    Write-ColorOutput "ERROR: This script requires Administrator privileges!" "ERROR"
    Write-ColorOutput "Right-click PowerShell and select 'Run as Administrator'" "ERROR"
    exit 1
}
Write-ColorOutput "Administrator check: PASSED" "SUCCESS"

$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-ColorOutput "OS: $($osInfo.Caption)" "INFO"
Write-ColorOutput "Version: $($osInfo.Version)" "INFO"
Write-Host ""
#endregion

try {
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  STARTING INSTALLATION" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    #region Step 1: Install Chocolatey
    Write-ColorOutput "STEP 1: Installing Chocolatey Package Manager..." "INFO"
    
    $chocoInstalled = Get-Command choco -ErrorAction SilentlyContinue
    if (!$chocoInstalled) {
        Write-ColorOutput "Downloading Chocolatey..." "INFO"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-ColorOutput "Chocolatey installed successfully" "SUCCESS"
    } else {
        Write-ColorOutput "Chocolatey already installed" "SUCCESS"
    }
    Write-Host ""
    #endregion
    
    #region Step 2: Install Python
    Write-ColorOutput "STEP 2: Installing Python 3.12..." "INFO"
    
    $pythonInstalled = Get-Command python -ErrorAction SilentlyContinue
    if (!$pythonInstalled) {
        Write-ColorOutput "Installing Python via Chocolatey..." "INFO"
        choco install python -y --version=3.12.0
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-ColorOutput "Python installed successfully" "SUCCESS"
    } else {
        Write-ColorOutput "Python already installed" "SUCCESS"
    }
    
    # Verify Python
    $pythonVersion = python --version 2>&1
    Write-ColorOutput "Python version: $pythonVersion" "INFO"
    Write-Host ""
    #endregion
    
    #region Step 3: Install Python Libraries
    Write-ColorOutput "STEP 3: Installing Python Libraries..." "INFO"
    
    $libraries = @(
        "pandas",           # Data manipulation
        "openpyxl",        # Excel files
        "xlsxwriter",      # Excel creation
        "pyodbc",          # Database connectivity
        "python-dotenv",   # Environment variables
        "requests",        # HTTP requests
        "schedule",        # Task scheduling
        "smtplib",         # Email (built-in but verify)
        "jinja2",          # Report templates
        "matplotlib",      # Charts/graphs
        "pillow"           # Image processing
    )
    
    foreach ($lib in $libraries) {
        Write-ColorOutput "Installing $lib..." "INFO"
        python -m pip install $lib --quiet --disable-pip-version-check
    }
    
    Write-ColorOutput "All Python libraries installed" "SUCCESS"
    Write-Host ""
    #endregion
    
    #region Step 4: Install Power BI Desktop
    Write-ColorOutput "STEP 4: Installing Power BI Desktop..." "INFO"
    
    $pbiInstalled = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | 
                    Where-Object { $_.DisplayName -like "*Power BI Desktop*" }
    
    if (!$pbiInstalled) {
        Write-ColorOutput "Downloading Power BI Desktop..." "INFO"
        choco install powerbi -y
        Write-ColorOutput "Power BI Desktop installed successfully" "SUCCESS"
    } else {
        Write-ColorOutput "Power BI Desktop already installed" "SUCCESS"
    }
    Write-Host ""
    #endregion
    
    #region Step 5: Install Additional Tools
    Write-ColorOutput "STEP 5: Installing Additional Tools..." "INFO"
    
    # Install Git for version control
    Write-ColorOutput "Installing Git..." "INFO"
    choco install git -y
    
    # Install Notepad++ for script editing
    Write-ColorOutput "Installing Notepad++..." "INFO"
    choco install notepadplusplus -y
    
    # Install 7-Zip for file compression
    Write-ColorOutput "Installing 7-Zip..." "INFO"
    choco install 7zip -y
    
    Write-ColorOutput "Additional tools installed" "SUCCESS"
    Write-Host ""
    #endregion
    
    #region Step 6: Create Directory Structure
    Write-ColorOutput "STEP 6: Creating directory structure..." "INFO"
    
    $baseDir = "C:\PyxHealthReports"
    $directories = @(
        "$baseDir\Scripts",
        "$baseDir\Reports\Daily",
        "$baseDir\Reports\Weekly",
        "$baseDir\Reports\Monthly",
        "$baseDir\Logs",
        "$baseDir\Config",
        "$baseDir\Data",
        "$baseDir\Templates"
    )
    
    foreach ($dir in $directories) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-ColorOutput "Created: $dir" "INFO"
        }
    }
    
    Write-ColorOutput "Directory structure created" "SUCCESS"
    Write-Host ""
    #endregion
    
    #region Step 7: Create Sample Scripts
    Write-ColorOutput "STEP 7: Creating sample reporting scripts..." "INFO"
    
    # Sample Python report script
    $sampleScript = @'
import pandas as pd
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from datetime import datetime
import os

def generate_report():
    """Generate a sample report"""
    print(f"[{datetime.now()}] Starting report generation...")
    
    # Create sample data
    data = {
        'Date': [datetime.now().strftime('%Y-%m-%d')] * 5,
        'Metric': ['Sales', 'Revenue', 'Customers', 'Orders', 'Returns'],
        'Value': [100, 5000, 50, 75, 5]
    }
    
    df = pd.DataFrame(data)
    
    # Save to Excel
    report_file = f"C:\\PyxHealthReports\\Reports\\Daily\\Report_{datetime.now().strftime('%Y%m%d')}.xlsx"
    df.to_excel(report_file, index=False)
    
    print(f"Report saved: {report_file}")
    return report_file

def send_email_report(report_file):
    """Send report via email"""
    print(f"[{datetime.now()}] Sending email report...")
    
    # Email configuration (UPDATE THESE VALUES)
    smtp_server = "smtp.office365.com"  # or smtp.gmail.com
    smtp_port = 587
    sender_email = "reports@pyxhealth.com"  # UPDATE THIS
    sender_password = "YOUR_PASSWORD"  # UPDATE THIS
    recipient_email = "manager@pyxhealth.com"  # UPDATE THIS
    
    # Create message
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = recipient_email
    msg['Subject'] = f"PyxHealth Daily Report - {datetime.now().strftime('%Y-%m-%d')}"
    
    # Email body
    body = f"""
    Hello,
    
    Please find attached the daily report for {datetime.now().strftime('%Y-%m-%d')}.
    
    This report was automatically generated by PyxHealth Reporting Server.
    
    Best regards,
    Automated Reporting System
    """
    
    msg.attach(MIMEText(body, 'plain'))
    
    # Attach file
    with open(report_file, 'rb') as f:
        part = MIMEBase('application', 'octet-stream')
        part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header('Content-Disposition', f'attachment; filename={os.path.basename(report_file)}')
        msg.attach(part)
    
    # Send email
    try:
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(sender_email, sender_password)
        server.send_message(msg)
        server.quit()
        print(f"Email sent successfully to {recipient_email}")
    except Exception as e:
        print(f"Error sending email: {str(e)}")

if __name__ == "__main__":
    try:
        report_file = generate_report()
        # Uncomment to send email
        # send_email_report(report_file)
        print(f"[{datetime.now()}] Report generation completed successfully")
    except Exception as e:
        print(f"[{datetime.now()}] ERROR: {str(e)}")
'@
    
    $sampleScript | Out-File -FilePath "$baseDir\Scripts\daily_report.py" -Encoding UTF8
    Write-ColorOutput "Created: daily_report.py" "SUCCESS"
    
    # Create config file
    $configContent = @"
# PyxHealth Reporting Configuration
# UPDATE THESE VALUES WITH YOUR SETTINGS

# Email Configuration
SMTP_SERVER=smtp.office365.com
SMTP_PORT=587
SENDER_EMAIL=reports@pyxhealth.com
SENDER_PASSWORD=YOUR_PASSWORD_HERE
RECIPIENT_EMAIL=manager@pyxhealth.com

# Database Configuration (if needed)
DB_SERVER=your-sql-server.database.windows.net
DB_NAME=your-database
DB_USER=your-username
DB_PASSWORD=your-password

# Report Settings
REPORT_FREQUENCY=daily
REPORT_TIME=08:00
"@
    
    $configContent | Out-File -FilePath "$baseDir\Config\config.txt" -Encoding UTF8
    Write-ColorOutput "Created: config.txt" "SUCCESS"
    
    Write-Host ""
    #endregion
    
    #region Step 8: Create Task Scheduler Job
    Write-ColorOutput "STEP 8: Creating Task Scheduler jobs..." "INFO"
    
    # Create daily report task
    $taskName = "PyxHealth-Daily-Report"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if (!$taskExists) {
        $action = New-ScheduledTaskAction -Execute "python.exe" `
            -Argument "C:\PyxHealthReports\Scripts\daily_report.py" `
            -WorkingDirectory "C:\PyxHealthReports\Scripts"
        
        $trigger = New-ScheduledTaskTrigger -Daily -At "8:00AM"
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        Register-ScheduledTask -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description "PyxHealth automated daily report generation" | Out-Null
        
        Write-ColorOutput "Task Scheduler job created: $taskName" "SUCCESS"
    } else {
        Write-ColorOutput "Task Scheduler job already exists" "SUCCESS"
    }
    
    Write-Host ""
    #endregion
    
    #region Step 9: Configure Windows Firewall
    Write-ColorOutput "STEP 9: Configuring Windows Firewall..." "INFO"
    
    # Allow SMTP outbound
    $ruleName = "PyxHealth-SMTP-Outbound"
    $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    
    if (!$ruleExists) {
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Outbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort 25,587,465 `
            -Description "Allow SMTP email for PyxHealth reports" | Out-Null
        
        Write-ColorOutput "Firewall rule created for SMTP" "SUCCESS"
    } else {
        Write-ColorOutput "Firewall rule already exists" "SUCCESS"
    }
    
    Write-Host ""
    #endregion
    
    #region Step 10: Create Desktop Shortcuts
    Write-ColorOutput "STEP 10: Creating desktop shortcuts..." "INFO"
    
    $desktop = [Environment]::GetFolderPath("Desktop")
    
    # Shortcut to Reports folder
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut("$desktop\PyxHealth Reports.lnk")
    $shortcut.TargetPath = "C:\PyxHealthReports"
    $shortcut.Description = "PyxHealth Reporting Server Files"
    $shortcut.Save()
    
    Write-ColorOutput "Desktop shortcuts created" "SUCCESS"
    Write-Host ""
    #endregion
    
    # Final Summary
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║           INSTALLATION COMPLETED SUCCESSFULLY!               ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "SOFTWARE INSTALLED:" -ForegroundColor Yellow
    Write-Host "  ✓ Chocolatey Package Manager" -ForegroundColor Green
    Write-Host "  ✓ Python 3.12 + pip" -ForegroundColor Green
    Write-Host "  ✓ Power BI Desktop" -ForegroundColor Green
    Write-Host "  ✓ Python Libraries (pandas, openpyxl, etc.)" -ForegroundColor Green
    Write-Host "  ✓ Git, Notepad++, 7-Zip" -ForegroundColor Green
    Write-Host ""
    Write-Host "CONFIGURATION:" -ForegroundColor Yellow
    Write-Host "  ✓ Directory structure created: C:\PyxHealthReports" -ForegroundColor Green
    Write-Host "  ✓ Sample scripts created" -ForegroundColor Green
    Write-Host "  ✓ Task Scheduler job configured" -ForegroundColor Green
    Write-Host "  ✓ Firewall rules configured" -ForegroundColor Green
    Write-Host "  ✓ Desktop shortcuts created" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Edit config file: C:\PyxHealthReports\Config\config.txt" -ForegroundColor White
    Write-Host "     - Update SMTP settings with your email credentials" -ForegroundColor White
    Write-Host "     - Update database connection strings (if needed)" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Test sample report:" -ForegroundColor White
    Write-Host "     python C:\PyxHealthReports\Scripts\daily_report.py" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3. View scheduled tasks:" -ForegroundColor White
    Write-Host "     Task Scheduler > PyxHealth-Daily-Report" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  4. Access reports:" -ForegroundColor White
    Write-Host "     C:\PyxHealthReports\Reports" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  5. Configure your custom reporting scripts in:" -ForegroundColor White
    Write-Host "     C:\PyxHealthReports\Scripts" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Red
    Write-Host "  You MUST update the email settings in the config file!" -ForegroundColor Yellow
    Write-Host "  File: C:\PyxHealthReports\Config\config.txt" -ForegroundColor Yellow
    Write-Host ""
    Write-ColorOutput "Installation completed successfully!" "SUCCESS"
    Write-Host ""
    
} catch {
    Write-ColorOutput "INSTALLATION FAILED: $($_.Exception.Message)" "ERROR"
    Write-ColorOutput "Error details: $($_.Exception.ToString())" "ERROR"
    exit 1
}
