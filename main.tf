terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_resource_group" "network" {
  name = var.network_resource_group
}

data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

data "azurerm_subnet" "existing" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = data.azurerm_resource_group.network.name
}

resource "azurerm_resource_group" "deployment" {
  name     = var.deployment_resource_group
  location = var.location
  tags     = var.tags
}

resource "azurerm_network_security_group" "moveit" {
  name                = var.nsg_name
  location            = data.azurerm_resource_group.network.location
  resource_group_name = data.azurerm_resource_group.network.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "allow_ftps_990" {
  name                        = "Allow-FTPS-990"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "990"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

resource "azurerm_network_security_rule" "allow_ftps_989" {
  name                        = "Allow-FTPS-989"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "989"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

resource "azurerm_network_security_rule" "allow_https_443" {
  name                        = "Allow-HTTPS-443"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

resource "azurerm_subnet_network_security_group_association" "moveit" {
  subnet_id                 = data.azurerm_subnet.existing.id
  network_security_group_id = azurerm_network_security_group.moveit.id
}

resource "azurerm_public_ip" "lb_ftps" {
  name                = var.lb_public_ip_name
  location            = azurerm_resource_group.deployment.location
  resource_group_name = azurerm_resource_group.deployment.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_lb" "ftps" {
  name                = var.lb_name
  location            = azurerm_resource_group.deployment.location
  resource_group_name = azurerm_resource_group.deployment.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "LoadBalancerFrontEnd"
    public_ip_address_id = azurerm_public_ip.lb_ftps.id
  }
}

resource "azurerm_lb_backend_address_pool" "ftps" {
  name            = "backend-pool-lb"
  loadbalancer_id = azurerm_lb.ftps.id
}

resource "azurerm_lb_backend_address_pool_address" "moveit" {
  name                    = "moveit-backend"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ftps.id
  virtual_network_id      = data.azurerm_virtual_network.existing.id
  ip_address              = var.moveit_private_ip
}

resource "azurerm_lb_probe" "ftps" {
  name                = "health-probe-ftps"
  loadbalancer_id     = azurerm_lb.ftps.id
  protocol            = "Tcp"
  port                = 990
  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "ftps_990" {
  name                           = "lb-rule-990"
  loadbalancer_id                = azurerm_lb.ftps.id
  protocol                       = "Tcp"
  frontend_port                  = 990
  backend_port                   = 990
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ftps.id]
  probe_id                       = azurerm_lb_probe.ftps.id
  idle_timeout_in_minutes        = 15
  enable_tcp_reset               = true
}

resource "azurerm_lb_rule" "ftps_989" {
  name                           = "lb-rule-989"
  loadbalancer_id                = azurerm_lb.ftps.id
  protocol                       = "Tcp"
  frontend_port                  = 989
  backend_port                   = 989
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ftps.id]
  probe_id                       = azurerm_lb_probe.ftps.id
  idle_timeout_in_minutes        = 15
  enable_tcp_reset               = true
}

resource "azurerm_cdn_frontdoor_firewall_policy" "moveit" {
  name                              = var.waf_policy_name
  resource_group_name               = azurerm_resource_group.deployment.name
  sku_name                          = var.frontdoor_sku
  enabled                           = true
  mode                              = var.waf_mode
  request_body_check_enabled        = true
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("Access Denied")
  tags                              = var.tags

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  custom_rule {
    name                           = "AllowLargeUploads"
    enabled                        = true
    priority                       = 100
    type                           = "MatchRule"
    action                         = "Allow"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100

    match_condition {
      match_variable     = "RequestMethod"
      operator           = "Equal"
      negation_condition = false
      match_values       = ["POST", "PUT", "PATCH"]
    }
  }

  custom_rule {
    name                           = "AllowMOVEitMethods"
    enabled                        = true
    priority                       = 110
    type                           = "MatchRule"
    action                         = "Allow"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100

    match_condition {
      match_variable     = "RequestMethod"
      operator           = "Equal"
      negation_condition = false
      match_values       = ["GET", "POST", "HEAD", "OPTIONS", "PUT", "PATCH", "DELETE"]
    }
  }
}

resource "azurerm_cdn_frontdoor_profile" "moveit" {
  name                = var.frontdoor_profile_name
  resource_group_name = azurerm_resource_group.deployment.name
  sku_name            = var.frontdoor_sku
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "moveit" {
  name                     = var.frontdoor_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "moveit" {
  name                     = var.frontdoor_origin_group_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id
  session_affinity_enabled = false

  health_probe {
    protocol            = "Https"
    request_type        = "GET"
    path                = "/"
    interval_in_seconds = 30
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 2
    additional_latency_in_milliseconds = 0
  }
}

resource "azurerm_cdn_frontdoor_origin" "moveit" {
  name                          = var.frontdoor_origin_name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id
  enabled                       = true
  certificate_name_check_enabled = false
  host_name                      = var.moveit_private_ip
  origin_host_header             = var.moveit_private_ip
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
}

resource "azurerm_cdn_frontdoor_route" "moveit" {
  name                          = var.frontdoor_route_name
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.moveit.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.moveit.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Https"]
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_security_policy" "moveit" {
  name                     = "moveit-waf-security"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.moveit.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.moveit.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_security_center_subscription_pricing" "vm" {
  tier          = "Standard"
  resource_type = "VirtualMachines"
}

resource "azurerm_security_center_subscription_pricing" "appservices" {
  tier          = "Standard"
  resource_type = "AppServices"
}

resource "azurerm_security_center_subscription_pricing" "storage" {
  tier          = "Standard"
  resource_type = "StorageAccounts"
}
