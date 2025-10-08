#Requires -Version 5.1

<#
.SYNOPSIS
    Email IAM Security Reports to Stakeholders

.DESCRIPTION
    Sends professionally formatted IAM security audit reports via email
    to configured recipients (bosses, managers, leaders).

.PARAMETER LatestReport
    Switch to automatically use the latest report

.EXAMPLE
    .\Send-IAMReport.ps1 -LatestReport
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ".\Config\email-config.json",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\IAM-Security-Reports",

    [Parameter(Mandatory = $false)]
    [switch]$LatestReport
)

Write-Host ""
Write-Host "=============================================================="
Write-Host "  IAM SECURITY REPORT EMAIL DELIVERY"
Write-Host "=============================================================="
Write-Host ""

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Email configuration not found. Creating sample..." -ForegroundColor Yellow
    
    $sampleConfig = @{
        SMTPServer = "smtp.office365.com"
        SMTPPort = 587
        SMTPUsername = "security-reports@company.com"
        SMTPPassword = "YourPasswordHere"
        EnableSSL = $true
        
        FromAddress = "security-reports@company.com"
        FromName = "IAM Security Team"
        
        ToAddresses = @(
            "ceo@company.com",
            "cio@company.com",
            "security-manager@company.com",
            "it-director@company.com"
        )
        
        CcAddresses = @(
            "security-team@company.com"
        )
        
        Subject = "IAM Security Audit Report - [DATE] - Risk Level: [RISK]"
        IncludeAttachments = $true
        MaxAttachmentSize = 25MB
        
        MaxRetries = 3
        RetryDelaySeconds = 30
    }
    
    $configDir = Split-Path $ConfigPath
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    $sampleConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8
    
    Write-Host "Sample configuration created: $ConfigPath" -ForegroundColor Green
    Write-Host "Please edit the configuration file with your email settings" -ForegroundColor Yellow
    Write-Host ""
    
    notepad $ConfigPath
    exit 0
}

Write-Host "Loading email configuration..." -ForegroundColor Cyan
$config = Get-Content $ConfigPath | ConvertFrom-Json

if ($LatestReport) {
    Write-Host "Finding latest IAM security report..." -ForegroundColor Cyan
    $latestMetadata = Get-ChildItem -Path $ReportPath -Filter "email-metadata-*.json" | 
                      Sort-Object LastWriteTime -Descending | 
                      Select-Object -First 1
    
    if (-not $latestMetadata) {
        Write-Host "No reports found. Run Audit-IAMSecurity.ps1 first." -ForegroundColor Red
        exit 1
    }
    
    $metadata = Get-Content $latestMetadata.FullName | ConvertFrom-Json
    Write-Host "Found report from: $($metadata.ReportDate)" -ForegroundColor Green
} else {
    Write-Host "ERROR: Please use -LatestReport parameter" -ForegroundColor Red
    exit 1
}

Write-Host "Preparing email..." -ForegroundColor Cyan

$reportDate = Get-Date -Format "MMMM dd, yyyy"
$subject = $config.Subject -replace "\[DATE\]", $reportDate -replace "\[RISK\]", $metadata.RiskLevel

$emailBody = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
body { font-family: Arial; padding: 20px; background: #f5f5f5; }
.header { background: #4CAF50; color: white; padding: 30px; border-radius: 10px; text-align: center; }
.alert { padding: 20px; margin: 20px 0; border-radius: 8px; text-align: center; font-weight: bold; }
.alert-critical { background: #ff4444; color: white; }
.alert-high { background: #ff8800; color: white; }
.alert-medium { background: #ffbb33; color: #333; }
.alert-low { background: #00C851; color: white; }
.summary { background: white; padding: 20px; margin: 20px 0; border-left: 4px solid #4CAF50; }
</style>
</head>
<body>
<div class="header">
<h1>IAM Security Audit Report</h1>
<p>$reportDate</p>
</div>

<div class="alert alert-$($metadata.RiskLevel.ToLower())">
Overall Security Risk Level: $($metadata.RiskLevel)<br>
Risk Score: $($metadata.RiskScore)/100
</div>

<div class="summary">
<h2>Executive Summary</h2>
<p>This automated security audit has completed a comprehensive analysis of IAM configurations.</p>
<p><strong>Critical Findings:</strong> $($metadata.CriticalCount)</p>
<p><strong>High Priority:</strong> $($metadata.HighCount)</p>
</div>

<div class="summary">
<h3>Immediate Actions Required:</h3>
<ul>
<li>Review and address $($metadata.CriticalCount) critical security findings immediately</li>
<li>Remediate $($metadata.HighCount) high-priority findings within 48 hours</li>
<li>Review attached detailed report for specific recommendations</li>
</ul>
</div>

<p style="text-align: center; color: #666;">
Complete detailed analysis is attached to this email.
</p>

<div style="margin-top: 40px; padding-top: 20px; border-top: 2px solid #ddd; color: #666; font-size: 14px;">
<p><strong>IAM Security Audit System</strong></p>
<p>This is an automated security assessment. No changes were made to production.</p>
<p>Generated by Enterprise IAM Security Audit v3.0</p>
</div>
</body>
</html>
"@

$attachments = @()

if ($config.IncludeAttachments) {
    Write-Host "Preparing attachments..." -ForegroundColor Cyan
    
    $htmlSize = (Get-Item $metadata.HtmlFile).Length
    $csvSize = (Get-Item $metadata.CsvFile).Length
    $totalSize = $htmlSize + $csvSize
    
    if ($totalSize -lt $config.MaxAttachmentSize) {
        $attachments += $metadata.HtmlFile
        $attachments += $metadata.CsvFile
        Write-Host "Attachments prepared (Total: $([Math]::Round($totalSize/1MB, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "Attachments exceed size limit" -ForegroundColor Yellow
    }
}

$emailSent = $false
$attempts = 0

while (-not $emailSent -and $attempts -lt $config.MaxRetries) {
    $attempts++
    Write-Host "Sending email (Attempt $attempts of $($config.MaxRetries))..." -ForegroundColor Cyan
    
    try {
        $smtpParams = @{
            SmtpServer = $config.SMTPServer
            Port = $config.SMTPPort
            UseSsl = $config.EnableSSL
            From = "$($config.FromName) <$($config.FromAddress)>"
            To = $config.ToAddresses
            Subject = $subject
            Body = $emailBody
            BodyAsHtml = $true
        }
        
        if ($config.CcAddresses) {
            $smtpParams.Cc = $config.CcAddresses
        }
        
        if ($attachments.Count -gt 0) {
            $smtpParams.Attachments = $attachments
        }
        
        if ($config.SMTPUsername -and $config.SMTPPassword) {
            $securePassword = ConvertTo-SecureString $config.SMTPPassword -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($config.SMTPUsername, $securePassword)
            $smtpParams.Credential = $credential
        }
        
        Send-MailMessage @smtpParams
        $emailSent = $true
        Write-Host "Email sent successfully!" -ForegroundColor Green
        
    } catch {
        Write-Host "Failed to send email: $_" -ForegroundColor Red
        
        if ($attempts -lt $config.MaxRetries) {
            Write-Host "Retrying in $($config.RetryDelaySeconds) seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $config.RetryDelaySeconds
        }
    }
}

if ($emailSent) {
    Write-Host ""
    Write-Host "=============================================================="
    Write-Host "  EMAIL SENT SUCCESSFULLY"
    Write-Host "=============================================================="
    Write-Host ""
    Write-Host "Recipients: $($config.ToAddresses.Count)"
    Write-Host "Attachments: $($attachments.Count)"
    Write-Host "Report Date: $($metadata.ReportDate)"
    Write-Host "Risk Level: $($metadata.RiskLevel)"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "FAILED TO SEND EMAIL" -ForegroundColor Red
    Write-Host "Check email configuration and try again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}