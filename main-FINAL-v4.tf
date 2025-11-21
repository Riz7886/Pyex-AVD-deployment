# ================================================================
# MOVEIT AZURE FRONT DOOR + LOAD BALANCER
# Terraform Configuration - Uses Existing Resources
# Matches pyxiq Configuration Exactly
# Version: 4.0 FINAL
# ================================================================

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
  features {}
}

# ----------------------------------------------------------------
# LOCAL VARIABLES
# ----------------------------------------------------------------
locals {
  # EXISTING Resources (DO NOT CREATE)
  resource_group_name = "RG-MOVEIT"
  vnet_name           = "vnet-moveit"
  subnet_name         = "snet-moveit"
  moveit_private_ip   = "192.168.0.5"
  location            = "westus"
  
  # NEW Resources (WILL CREATE)
  frontdoor_profile_name  = "moveit-frontdoor-profile"
  frontdoor_endpoint_name = "moveit-endpoint"
  frontdoor_origin_group  = "moveit-origin-group"
  frontdoor_origin_name   = "moveit-origin"
  frontdoor_route_name    = "moveit-route"
  frontdoor_sku           = "Standard_AzureFrontDoor"
  
  waf_policy_name = "moveitWAFPolicy"
  waf_mode        = "Prevention"
  waf_sku         = "Standard_AzureFrontDoor"
  
  lb_name        = "lb-moveit-ftps"
  lb_public_ip   = "pip-moveit-ftps"
  nsg_name       = "nsg-moveit"
  
  tags = {
    Environment = "Production"
    Project     = "MOVEit"
    ManagedBy   = "Terraform"
    MatchesConfig = "pyxiq"
  }
}

# ----------------------------------------------------------------
# DATA SOURCES - EXISTING RESOURCES (DO NOT CREATE)
# ----------------------------------------------------------------

# Existing Resource Group
data "azurerm_resource_group" "existing" {
  name = local.resource_group_name
}

# Existing Virtual Network
data "azurerm_virtual_network" "existing" {
  name                = local.vnet_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

# Existing Subnet
data "azurerm_subnet" "existing" {
  name                 = local.subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = data.azurerm_resource_group.existing.name
}

# ----------------------------------------------------------------
# NETWORK SECURITY GROUP (NEW)
# ----------------------------------------------------------------
resource "azurerm_network_security_group" "moveit" {
  name                = local.nsg_name
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  tags                = local.tags
}

# NSG Rule: Allow FTPS Port 990
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
  resource_group_name         = data.azurerm_resource_group.existing.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

# NSG Rule: Allow FTPS Port 989
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
  resource_group_name         = data.azurerm_resource_group.existing.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

# NSG Rule: Allow HTTPS Port 443
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
  resource_group_name         = data.azurerm_resource_group.existing.name
  network_security_group_name = azurerm_network_security_group.moveit.name
}

# Associate NSG with Existing Subnet
resource "azurerm_subnet_network_security_group_association" "moveit" {
  subnet_id                 = data.azurerm_subnet.existing.id
  network_security_group_id = azurerm_network_security_group.moveit.id
}

# ----------------------------------------------------------------
# LOAD BALANCER FOR FTPS (NEW)
# ----------------------------------------------------------------

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_ftps" {
  name                = local.lb_public_ip
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# Load Balancer
resource "azurerm_lb" "ftps" {
  name                = local.lb_name
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "LoadBalancerFrontEnd"
    public_ip_address_id = azurerm_public_ip.lb_ftps.id
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "ftps" {
  name            = "backend-pool-lb"
  loadbalancer_id = azurerm_lb.ftps.id
}

# Backend Address Pool Address
resource "azurerm_lb_backend_address_pool_address" "moveit" {
  name                    = "moveit-backend"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ftps.id
  virtual_network_id      = data.azurerm_virtual_network.existing.id
  ip_address              = local.moveit_private_ip
}

# Health Probe
resource "azurerm_lb_probe" "ftps" {
  name            = "health-probe-ftps"
  loadbalancer_id = azurerm_lb.ftps.id
  protocol        = "Tcp"
  port            = 990
  interval_in_seconds = 15
  number_of_probes    = 2
}

# Load Balancing Rule - Port 990
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

# Load Balancing Rule - Port 989
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

# ----------------------------------------------------------------
# WAF POLICY (MATCHING PYXIQ)
# ----------------------------------------------------------------
resource "azurerm_cdn_frontdoor_firewall_policy" "moveit" {
  name                              = local.waf_policy_name
  resource_group_name               = data.azurerm_resource_group.existing.name
  sku_name                          = local.waf_sku
  enabled                           = true
  mode                              = local.waf_mode
  request_body_check_enabled        = true
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("Access Denied")
  
  tags = local.tags

  # Managed Rule Set: DefaultRuleSet 1.0 (OWASP - matching pyxiq)
  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Managed Rule Set: Bot Manager
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Custom Rule: Allow Large Uploads
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

  # Custom Rule: Allow MOVEit HTTP Methods
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

  # Custom Rule: Rate Limiting
  custom_rule {
    name                           = "RateLimitRequests"
    enabled                        = true
    priority                       = 200
    type                           = "RateLimitRule"
    action                         = "Block"
    rate_limit_duration_in_minutes = 5
    rate_limit_threshold           = 500

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0", "::/0"]
    }
  }
}

# ----------------------------------------------------------------
# AZURE FRONT DOOR (MATCHING PYXIQ)
# ----------------------------------------------------------------

# Front Door Profile
resource "azurerm_cdn_frontdoor_profile" "moveit" {
  name                = local.frontdoor_profile_name
  resource_group_name = data.azurerm_resource_group.existing.name
  sku_name            = local.frontdoor_sku
  tags                = local.tags
}

# Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "moveit" {
  name                     = local.frontdoor_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.moveit.id
  tags                     = local.tags
}

# Origin Group (MATCHING PYXIQ: 30 seconds, sample 4, success 2)
resource "azurerm_cdn_frontdoor_origin_group" "moveit" {
  name                     = local.frontdoor_origin_group
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

# Origin (MOVEit Backend)
resource "azurerm_cdn_frontdoor_origin" "moveit" {
  name                          = local.frontdoor_origin_name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id
  enabled                       = true

  certificate_name_check_enabled = false
  host_name                      = local.moveit_private_ip
  origin_host_header             = local.moveit_private_ip
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
}

# Route (Matching pyxiq)
resource "azurerm_cdn_frontdoor_route" "moveit" {
  name                          = local.frontdoor_route_name
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.moveit.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.moveit.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.moveit.id]
  
  enabled                = true
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Https"]
  
  link_to_default_domain = true
}

# Security Policy (Associate WAF with Front Door)
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

# ----------------------------------------------------------------
# MICROSOFT DEFENDER FOR CLOUD
# ----------------------------------------------------------------
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
