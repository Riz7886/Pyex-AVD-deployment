terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_subscriptions" "available" {}
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {
  subscription_id = data.azurerm_client_config.current.subscription_id
}

resource "azurerm_resource_group" "frontdoor" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_log_analytics_workspace" "frontdoor" {
  name                = "law-fdh-${var.environment}"
  location            = azurerm_resource_group.frontdoor.location
  resource_group_name = azurerm_resource_group.frontdoor.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "fdh-${var.environment}"
  resource_group_name = azurerm_resource_group.frontdoor.name
  sku_name            = "Premium_AzureFrontDoor"
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "afd-${lower(var.project_name)}-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "dh-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
  health_probe {
    path                = var.health_probe_path
    protocol            = "Https"
    interval_in_seconds = 100
    request_type        = "HEAD"
  }
}

resource "azurerm_cdn_frontdoor_origin" "main" {
  name                          = "dh-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                        = true
  host_name                      = var.backend_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header            = var.backend_host_name
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "dh-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.main.id]
  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true
}

resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                              = "${lower(replace(var.project_name, " ", ""))}${var.environment}wafpolicy"
  resource_group_name               = azurerm_resource_group.frontdoor.name
  sku_name                          = azurerm_cdn_frontdoor_profile.main.sku_name
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403
  
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
  
  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }
  
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 100
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                           = "RateLimitRule"
    action                         = "Block"
    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      match_values       = ["/"]
      transforms         = ["Lowercase"]
      negation_condition = false
    }
  }
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "dh-security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id
      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  name                       = "fd-diagnostics"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.frontdoor.id
  enabled_log {
    category = "FrontDoorAccessLog"
  }
  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }
  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
