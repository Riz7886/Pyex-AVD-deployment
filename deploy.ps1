#Requires -Version 7.0

<#
.SYNOPSIS
    Drivers Health - Azure Front Door Terraform Deployment
.DESCRIPTION
    Automated deployment script for Azure Front Door Premium
    with complete configuration and DH naming convention
.NOTES
    Author: Syed Rizvi
    Company: Pyx Health
    Service: Drivers Health
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  DRIVERS HEALTH - AZURE FRONT DOOR TERRAFORM DEPLOYMENT" -ForegroundColor Cyan
Write-Host "  Automated Front Door Premium Deployment with DH Naming" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    Write-Host ""
    
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Azure CLI is not installed" -ForegroundColor Red
        Write-Host "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Azure CLI: OK" -ForegroundColor Green
    
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Terraform is not installed" -ForegroundColor Red
        Write-Host "Install from: https://www.terraform.io/downloads" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Terraform: OK" -ForegroundColor Green
    
    $terraformVersion = (terraform version) -split "`n" | Select-Object -First 1
    Write-Host "Terraform Version: $terraformVersion" -ForegroundColor Cyan
    Write-Host ""
}

function Connect-AzureAccount {
    Write-Host "Checking Azure login..." -ForegroundColor Cyan
    
    try {
        $context = Get-AzContext -ErrorAction Stop
        if ($context) {
            Write-Host "Already logged into Azure as: $($context.Account.Id)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Not logged into Azure. Logging in..." -ForegroundColor Yellow
        Connect-AzAccount | Out-Null
    }
    Write-Host ""
}

function Select-AzureSubscription {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  STEP 1: SELECT AZURE SUBSCRIPTION" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    if (Test-Path "terraform.tfvars") {
        Write-Host "terraform.tfvars already exists." -ForegroundColor Yellow
        $useExisting = Read-Host "Use existing configuration? (yes/no)"
        
        if ($useExisting -eq "yes") {
            Write-Host "Using existing terraform.tfvars" -ForegroundColor Green
            Write-Host ""
            return
        }
    }
    
    Write-Host "Running subscription selector..." -ForegroundColor Cyan
    & ".\select-subscription.ps1"
    Write-Host ""
}

function Initialize-Terraform {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  STEP 2: INITIALIZE TERRAFORM" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Running terraform init..." -ForegroundColor Cyan
    terraform init
    Write-Host ""
}

function New-DeploymentPlan {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  STEP 3: REVIEW DEPLOYMENT PLAN" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Running terraform plan..." -ForegroundColor Cyan
    terraform plan -out=tfplan
    Write-Host ""
}

function Confirm-Deployment {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  STEP 4: CONFIRM DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Terraform will create:" -ForegroundColor White
    Write-Host "- Resource Group for Drivers Health" -ForegroundColor Gray
    Write-Host "- Azure Front Door Premium (fdh-prod)" -ForegroundColor Gray
    Write-Host "- Front Door Endpoint" -ForegroundColor Gray
    Write-Host "- Origin Group with health probes" -ForegroundColor Gray
    Write-Host "- Auto-detected or manual origins" -ForegroundColor Gray
    Write-Host "- Routes with HTTPS redirect" -ForegroundColor Gray
    Write-Host "- WAF Policy with managed rules (Prevention mode)" -ForegroundColor Gray
    Write-Host "- Bot protection and rate limiting" -ForegroundColor Gray
    Write-Host "- System-assigned managed identity" -ForegroundColor Gray
    Write-Host "- Log Analytics workspace" -ForegroundColor Gray
    Write-Host "- Diagnostic settings" -ForegroundColor Gray
    Write-Host "- 3 metric alerts" -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Proceed with deployment? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Host ""
        Write-Host "Deployment cancelled" -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
    Write-Host ""
}

function Start-DeploymentProcess {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  STEP 5: DEPLOYING DRIVERS HEALTH FRONT DOOR" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Deploying infrastructure..." -ForegroundColor Cyan
    terraform apply tfplan
    Write-Host ""
}

function Show-DeploymentResults {
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host ""
    
    try {
        $accessInstructions = terraform output -raw access_instructions
        Write-Host $accessInstructions -ForegroundColor White
    }
    catch {
        Write-Host "Deployment successful! Use 'terraform output' to view details." -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "View all outputs:" -ForegroundColor Cyan
    Write-Host "  terraform output" -ForegroundColor White
    Write-Host ""
    Write-Host "View specific output:" -ForegroundColor Cyan
    Write-Host "  terraform output endpoint_url" -ForegroundColor White
    Write-Host ""
}

function Save-DeploymentReport {
    $reportFile = "DriversHealth-FrontDoor-Deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    
    $report = @"
================================================================
DRIVERS HEALTH - AZURE FRONT DOOR DEPLOYMENT REPORT
================================================================

Deployment Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Deployed By: $env:USERNAME
Terraform Version: $(terraform version | Select-Object -First 1)

DEPLOYMENT OUTPUTS:
-------------------

$(terraform output 2>$null)

CONFIGURATION:
--------------

$(Get-Content terraform.tfvars -ErrorAction SilentlyContinue)

================================================================
"@
    
    $report | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Host "Deployment report saved: $reportFile" -ForegroundColor Green
    Write-Host ""
}

function Main {
    try {
        Test-Prerequisites
        Connect-AzureAccount
        Select-AzureSubscription
        Initialize-Terraform
        New-DeploymentPlan
        Confirm-Deployment
        Start-DeploymentProcess
        Show-DeploymentResults
        Save-DeploymentReport
        
        Write-Host ""
        Write-Host "======================================================================" -ForegroundColor Green
        Write-Host "  DRIVERS HEALTH FRONT DOOR DEPLOYMENT COMPLETE!" -ForegroundColor Green
        Write-Host "======================================================================" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "======================================================================" -ForegroundColor Red
        Write-Host "  DEPLOYMENT FAILED!" -ForegroundColor Red
        Write-Host "======================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Check the error message above and try again." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

Main
