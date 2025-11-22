MOVEit Terraform Deployment
===========================

Professional Terraform configuration for MOVEit Front Door deployment.

STRUCTURE
---------
main.tf           - Provider and all resources
variables.tf      - Variable definitions
terraform.tfvars  - Configuration values
outputs.tf        - Deployment outputs

PREREQUISITES
-------------
1. Azure CLI installed and logged in
2. Terraform >= 1.0 installed
3. Existing resources:
   - Resource Group: rg-networking
   - Virtual Network: vnet-prod
   - Subnet: snet-moveit
   - MOVEit server at 192.168.0.5

DEPLOYMENT STEPS
----------------
1. Initialize Terraform:
   terraform init

2. Validate configuration:
   terraform validate

3. Plan deployment:
   terraform plan

4. Apply deployment:
   terraform apply

5. View outputs:
   terraform output

WHAT GETS CREATED
-----------------
Network (in rg-networking):
- Network Security Group (nsg-moveit)
- NSG Rules (ports 990, 989, 443)

Deployment (in rg-moveit):
- Resource Group (rg-moveit)
- Load Balancer (lb-moveit-ftps)
- Public IP (pip-moveit-ftps)
- Front Door Profile (moveit-frontdoor-profile)
- Front Door Endpoint (moveit-endpoint)
- WAF Policy (moveitWAFPolicy)
- Defender Plans (VMs, Apps, Storage)

CUSTOMIZATION
-------------
Edit terraform.tfvars to change:
- Resource names
- IP addresses
- Locations
- Tags

COST
----
Approximately $83/month:
- Load Balancer: $18/month
- Front Door: $35/month
- WAF: $30/month

CLEANUP
-------
To destroy all resources:
terraform destroy

NOTE: This will NOT delete existing network resources
(rg-networking, vnet-prod, snet-moveit)
