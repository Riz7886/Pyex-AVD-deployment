output "network_configuration" {
  description = "Existing network resources used"
  value = {
    resource_group = data.azurerm_resource_group.network.name
    vnet           = data.azurerm_virtual_network.existing.name
    subnet         = data.azurerm_subnet.existing.name
    moveit_ip      = var.moveit_private_ip
    location       = data.azurerm_resource_group.network.location
  }
}

output "deployment_configuration" {
  description = "New resources created"
  value = {
    resource_group     = azurerm_resource_group.deployment.name
    front_door_profile = azurerm_cdn_frontdoor_profile.moveit.name
    load_balancer      = azurerm_lb.ftps.name
    waf_policy         = azurerm_cdn_frontdoor_firewall_policy.moveit.name
    nsg                = azurerm_network_security_group.moveit.name
  }
}

output "ftps_endpoint" {
  description = "FTPS access information"
  value = {
    public_ip = azurerm_public_ip.lb_ftps.ip_address
    ports     = "990, 989"
    protocol  = "FTPS"
  }
}

output "https_endpoint" {
  description = "HTTPS access information"
  value = {
    url      = "https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}"
    hostname = azurerm_cdn_frontdoor_endpoint.moveit.host_name
    port     = 443
  }
}

output "security_configuration" {
  description = "Security and WAF configuration"
  value = {
    waf_mode          = var.waf_mode
    waf_rules         = "DefaultRuleSet 1.0, Bot Manager"
    defender_vm       = "Standard"
    defender_apps     = "Standard"
    defender_storage  = "Standard"
  }
}

output "cost_estimate" {
  description = "Monthly cost estimate"
  value = {
    load_balancer = "$18/month"
    front_door    = "$35/month"
    waf           = "$30/month"
    total         = "$83/month"
  }
}

output "deployment_summary" {
  description = "Complete deployment summary"
  value = <<-EOT
  
  MOVEit Front Door Deployment Complete
  
  Network: ${data.azurerm_resource_group.network.name}/${data.azurerm_virtual_network.existing.name}/${data.azurerm_subnet.existing.name}
  Deployment: ${azurerm_resource_group.deployment.name}
  MOVEit IP: ${var.moveit_private_ip}
  
  FTPS: ${azurerm_public_ip.lb_ftps.ip_address} (ports 990, 989)
  HTTPS: https://${azurerm_cdn_frontdoor_endpoint.moveit.host_name}
  
  Cost: $83/month
  EOT
}
