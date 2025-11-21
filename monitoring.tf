resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                = "law-${var.frontdoor_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.merged_tags

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "frontdoor" {
  count                      = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                       = "DriversHealth-FrontDoor-Diagnostics"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

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

resource "azurerm_monitor_diagnostic_setting" "waf" {
  count                      = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                       = "DriversHealth-WAF-Diagnostics"
  target_resource_id         = azurerm_cdn_frontdoor_firewall_policy.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_action_group" "drivershealth" {
  count               = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                = "${var.naming_prefix}-action-group"
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  short_name          = "DH-Alert"
  tags                = local.merged_tags

  email_receiver {
    name                    = "DriversHealthTeam"
    email_address           = "ops@pyxhealth.com"
    use_common_alert_schema = true
  }

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

resource "azurerm_monitor_metric_alert" "high_latency" {
  count               = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                = "DH-High-Latency-Alert"
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  scopes              = [azurerm_cdn_frontdoor_profile.main[0].id]
  description         = "Drivers Health - Alert when latency exceeds threshold"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.merged_tags

  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "TotalLatency"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 1000
  }

  action {
    action_group_id = azurerm_monitor_action_group.drivershealth[0].id
  }

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

resource "azurerm_monitor_metric_alert" "high_error_rate" {
  count               = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                = "DH-High-Error-Rate-Alert"
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  scopes              = [azurerm_cdn_frontdoor_profile.main[0].id]
  description         = "Drivers Health - Alert when error rate is high"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.merged_tags

  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "RequestCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 100

    dimension {
      name     = "HttpStatusCode"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.drivershealth[0].id
  }

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}

resource "azurerm_monitor_metric_alert" "origin_health" {
  count               = var.enable_diagnostics && var.create_new_frontdoor ? 1 : 0
  name                = "DH-Origin-Health-Alert"
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  scopes              = [azurerm_cdn_frontdoor_profile.main[0].id]
  description         = "Drivers Health - Alert when origins are unhealthy"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.merged_tags

  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = "HealthProbeStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 50
  }

  action {
    action_group_id = azurerm_monitor_action_group.drivershealth[0].id
  }

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}
