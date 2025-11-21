#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "======================================================================"
echo "  DRIVERS HEALTH - AZURE FRONT DOOR TERRAFORM DEPLOYMENT"
echo "  Automated Front Door Premium Deployment with DH Naming"
echo "======================================================================"
echo ""

check_prerequisites() {
    echo "Checking prerequisites..."
    echo ""
    
    if ! command -v az &> /dev/null; then
        echo "ERROR: Azure CLI is not installed"
        echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    echo "Azure CLI: OK"
    
    if ! command -v terraform &> /dev/null; then
        echo "ERROR: Terraform is not installed"
        echo "Install from: https://www.terraform.io/downloads"
        exit 1
    fi
    echo "Terraform: OK"
    
    TERRAFORM_VERSION=$(terraform version | head -n1 | cut -d'v' -f2)
    echo "Terraform Version: $TERRAFORM_VERSION"
    echo ""
}

login_azure() {
    echo "Checking Azure login..."
    az account show &> /dev/null
    if [ $? -ne 0 ]; then
        echo "Not logged into Azure. Logging in..."
        az login
    else
        echo "Already logged into Azure"
    fi
    echo ""
}

select_subscription() {
    echo "======================================================================"
    echo "  STEP 1: SELECT AZURE SUBSCRIPTION"
    echo "======================================================================"
    echo ""
    
    if [ ! -f "terraform.tfvars" ]; then
        echo "Running subscription selector..."
        chmod +x select-subscription.sh
        ./select-subscription.sh
    else
        echo "terraform.tfvars already exists."
        read -p "Use existing configuration? (yes/no): " use_existing
        if [ "$use_existing" != "yes" ]; then
            chmod +x select-subscription.sh
            ./select-subscription.sh
        else
            echo "Using existing terraform.tfvars"
        fi
    fi
    echo ""
}

initialize_terraform() {
    echo "======================================================================"
    echo "  STEP 2: INITIALIZE TERRAFORM"
    echo "======================================================================"
    echo ""
    
    echo "Running terraform init..."
    terraform init
    echo ""
}

plan_deployment() {
    echo "======================================================================"
    echo "  STEP 3: REVIEW DEPLOYMENT PLAN"
    echo "======================================================================"
    echo ""
    
    echo "Running terraform plan..."
    terraform plan -out=tfplan
    echo ""
}

confirm_deployment() {
    echo "======================================================================"
    echo "  STEP 4: CONFIRM DEPLOYMENT"
    echo "======================================================================"
    echo ""
    
    echo "Terraform will create:"
    echo "- Resource Group for Drivers Health"
    echo "- Azure Front Door Premium (fdh-prod)"
    echo "- Front Door Endpoint"
    echo "- Origin Group with health probes"
    echo "- Auto-detected or manual origins"
    echo "- Routes with HTTPS redirect"
    echo "- WAF Policy with managed rules (Prevention mode)"
    echo "- Bot protection and rate limiting"
    echo "- System-assigned managed identity"
    echo "- Log Analytics workspace"
    echo "- Diagnostic settings"
    echo "- 3 metric alerts"
    echo ""
    
    read -p "Proceed with deployment? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo ""
        echo "Deployment cancelled"
        echo ""
        exit 0
    fi
    echo ""
}

deploy_infrastructure() {
    echo "======================================================================"
    echo "  STEP 5: DEPLOYING DRIVERS HEALTH FRONT DOOR"
    echo "======================================================================"
    echo ""
    
    echo "Deploying infrastructure..."
    terraform apply tfplan
    echo ""
}

display_results() {
    echo ""
    echo "======================================================================"
    echo "  DEPLOYMENT COMPLETE!"
    echo "======================================================================"
    echo ""
    
    terraform output -raw access_instructions 2>/dev/null || true
    
    echo ""
    echo "View all outputs:"
    echo "  terraform output"
    echo ""
    echo "View specific output:"
    echo "  terraform output endpoint_url"
    echo ""
    echo "Deployment report saved to terraform state"
    echo ""
}

save_deployment_report() {
    REPORT_FILE="DriversHealth-FrontDoor-Deployment-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" <<EOF
================================================================
DRIVERS HEALTH - AZURE FRONT DOOR DEPLOYMENT REPORT
================================================================

Deployment Date: $(date +"%Y-%m-%d %H:%M:%S")
Deployed By: $(whoami)
Terraform Version: $(terraform version | head -n1)

DEPLOYMENT OUTPUTS:
-------------------

$(terraform output 2>/dev/null)

CONFIGURATION:
--------------

$(cat terraform.tfvars 2>/dev/null)

================================================================
EOF
    
    echo "Deployment report saved: $REPORT_FILE"
}

main() {
    check_prerequisites
    login_azure
    select_subscription
    initialize_terraform
    plan_deployment
    confirm_deployment
    deploy_infrastructure
    display_results
    save_deployment_report
    
    echo ""
    echo "======================================================================"
    echo "  DRIVERS HEALTH FRONT DOOR DEPLOYMENT COMPLETE!"
    echo "======================================================================"
    echo ""
}

main
