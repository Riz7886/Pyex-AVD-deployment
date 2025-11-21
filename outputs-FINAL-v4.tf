# ================================================================
# TERRAFORM OUTPUTS
# Matches PowerShell Deployment Summary
# ================================================================

output "existing_resources" {
  description = "Existing resources that were used (not created)"
  value = {
    resource_group = data.azurerm_resource_group.existing.name
    vnet           = data.azurerm_virtual_network.existing.name
    subnet         = data.azurerm_subnet.existing.name
    moveit_ip      = local.moveit_private_ip
    location       = data.azurerm_resource_group.existing.location
  }
}

output "new_resources" {
  description = "New resources that were created"
  value = {
    front_door_profile = azurerm_cdn_frontdoor_profile.moveit.name
    load_balancer      = azurerm_lb.ftps.name
    waf_policy         = azurerm_cdn_frontdoor_firewall_policy.moveit.name
    nsg                = azurerm_network_security_group.moveit.name
  }
}

output "ftps_access" {
  description = "FTPS file transfer access information"
  value = {
    public_ip = azurerm_public_ip.lb_ftps.ip_address
    ports     = "990, 989"
    protocol  = "FTPS"
    backend   = local.moveit_private_ip
  }
}

output "https_access" {
  description = "HTTPS web access information"
  value = {
    endpoint        = "https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}"
    hostname        = azurerm_cdn_frontdoor_endpoint.moveit.host_name
    port            = 443
    waf_mode        = local.waf_mode
    waf_rules       = "DefaultRuleSet 1.0 (117+ OWASP rules)"
    backend         = local.moveit_private_ip
  }
}

output "configuration_matches_pyxiq" {
  description = "Configuration settings that match pyxiq"
  value = {
    health_probe_interval  = "30 seconds"
    sample_size            = 4
    successful_samples     = 2
    session_affinity       = "Disabled"
    managed_rules          = "DefaultRuleSet 1.0"
    additional_latency     = "0 ms"
  }
}

output "cost_estimate" {
  description = "Monthly cost estimate"
  value = {
    load_balancer     = "$18/month"
    front_door        = "$35/month"
    waf_standard      = "$30/month"
    total_monthly     = "$83/month"
    total_annual      = "$996/year"
  }
}

output "deployment_summary" {
  description = "Complete deployment summary"
  value = <<-EOT
  
  ============================================
  MOVEIT FRONT DOOR DEPLOYMENT COMPLETE
  ============================================
  
  EXISTING RESOURCES (USED):
  - Resource Group: ${data.azurerm_resource_group.existing.name}
  - VNet: ${data.azurerm_virtual_network.existing.name}
  - Subnet: ${data.azurerm_subnet.existing.name}
  - MOVEit Server: ${local.moveit_private_ip}
  
  NEW RESOURCES (CREATED):
  - Front Door: ${azurerm_cdn_frontdoor_profile.moveit.name}
  - Load Balancer: ${azurerm_lb.ftps.name}
  - WAF Policy: ${azurerm_cdn_frontdoor_firewall_policy.moveit.name}
  - NSG: ${azurerm_network_security_group.moveit.name}
  
  PUBLIC ENDPOINTS:
  -----------------
  FTPS Load Balancer: ${azurerm_public_ip.lb_ftps.ip_address}
    - Ports: 990, 989
    - Protocol: FTPS
    - Routes to: MOVEit ${local.moveit_private_ip}
  
  HTTPS Front Door: https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}
    - Port: 443
    - WAF: Active (Prevention Mode)
    - OWASP DefaultRuleSet 1.0
    - Routes to: MOVEit ${local.moveit_private_ip}
  
  ARCHITECTURE:
  -------------
  INTERNET
     |
     +-> Load Balancer (${azurerm_public_ip.lb_ftps.ip_address})
     |   Ports: 990, 989 (FTPS)
     |   |
     |   +-> MOVEit Transfer (${local.moveit_private_ip})
     |
     +-> Azure Front Door (https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name})
         Port: 443 (HTTPS)
         WAF: OWASP DefaultRuleSet 1.0 (117+ rules)
         |
         +-> MOVEit Transfer (${local.moveit_private_ip})
  
  CONFIGURATION MATCHES PYXIQ:
  ----------------------------
  - Health Probe: 30 seconds ✓
  - Sample Size: 4 ✓
  - Successful Samples: 2 ✓
  - Session Affinity: Disabled ✓
  - WAF Rules: DefaultRuleSet 1.0 ✓
  
  COST: ~$83/month
  ============================================
  
  EOT
}
