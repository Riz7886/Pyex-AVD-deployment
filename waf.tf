resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  count               = var.create_new_frontdoor ? 1 : 0
  name                = "${var.service_name}${var.environment}wafpolicy"
  resource_group_name = azurerm_resource_group.frontdoor_rg.name
  sku_name            = var.frontdoor_sku
  enabled             = true
  mode                = var.waf_mode
  tags                = local.merged_tags

  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode(jsonencode({
    "error" = {
      "code"    = "AccessDenied"
      "message" = "Access denied by WAF policy for Drivers Health"
    }
  }))

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"

    exclusion {
      match_variable = "RequestHeaderNames"
      operator       = "Equals"
      selector       = "User-Agent"
    }

    override {
      rule_group_name = "PROTOCOL-ATTACK"

      rule {
        rule_id = "944240"
        enabled = true
        action  = "Block"
      }
    }
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
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0"]
    }
  }

  custom_rule {
    name     = "GeoBlockingRule"
    enabled  = false
    priority = 200
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "GeoMatch"
      negation_condition = true
      match_values       = ["US", "CA"]
    }
  }

  custom_rule {
    name     = "BlockSQLInjection"
    enabled  = true
    priority = 300
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "QueryString"
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "union",
        "select",
        "insert",
        "drop",
        "delete",
        "update",
        "exec"
      ]
      transforms = ["Lowercase"]
    }
  }

  lifecycle {
    ignore_changes = [tags["DeploymentDate"]]
  }
}
