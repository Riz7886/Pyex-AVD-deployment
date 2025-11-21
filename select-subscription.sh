#!/bin/bash

echo "======================================================================"
echo "  AZURE SUBSCRIPTION SELECTOR - DRIVERS HEALTH"
echo "======================================================================"
echo ""

az account show &> /dev/null
if [ $? -ne 0 ]; then
    echo "Not logged into Azure. Please login..."
    az login
fi

echo "Searching for Drivers Health subscriptions..."
echo ""

subscriptions=$(az account list --query "[].{Name:name, ID:id}" -o tsv)

echo "Available Azure Subscriptions:"
echo "---------------------------------------------------------------------"

counter=0
while IFS=$'\t' read -r name id; do
    echo "[$counter] $name"
    echo "    ID: $id"
    counter=$((counter + 1))
done <<< "$subscriptions"

echo ""
echo "---------------------------------------------------------------------"
echo ""

read -p "Enter subscription number to use for Drivers Health Front Door: " choice

selected_sub=$(echo "$subscriptions" | sed -n "$((choice + 1))p")
sub_name=$(echo "$selected_sub" | cut -f1)
sub_id=$(echo "$selected_sub" | cut -f2)

echo ""
echo "Selected Subscription: $sub_name"
echo "Subscription ID: $sub_id"
echo ""

az account set --subscription "$sub_id"

cat > terraform.tfvars <<EOF
target_subscription_id = "$sub_id"
subscription_name = "$sub_name"
EOF

echo "Subscription configuration saved to terraform.tfvars"
echo ""
echo "Run: terraform init && terraform plan"
echo ""
