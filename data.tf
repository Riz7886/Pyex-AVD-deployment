data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {
  subscription_id = var.target_subscription_id
}

data "azurerm_subscriptions" "available" {}

data "azurerm_app_services" "drivershealth" {
  count               = var.auto_detect_backends ? 1 : 0
  resource_group_name = var.resource_group_name

  depends_on = [azurerm_resource_group.frontdoor_rg]
}

locals {
  subscription_info = {
    name = data.azurerm_subscription.current.display_name
    id   = data.azurerm_subscription.current.subscription_id
  }

  all_app_services = var.auto_detect_backends && length(data.azurerm_app_services.drivershealth) > 0 ? [
    for app in data.azurerm_app_services.drivershealth[0].app_services : app
    if can(regex(".*drivershealth.*|.*drivers-health.*|.*dh-.*", lower(app.name)))
  ] : []

  detected_backends = length(local.all_app_services) > 0 ? [
    for idx, app in local.all_app_services : {
      name                 = replace(app.default_site_hostname, ".", "-")
      host_name            = app.default_site_hostname
      origin_host_header   = app.default_site_hostname
      priority             = 1
      weight               = 1000
      enabled              = true
      http_port            = 80
      https_port           = 443
      certificate_name_check_enabled = true
    }
  ] : []

  origins = length(local.detected_backends) > 0 ? local.detected_backends : [
    {
      name                 = replace(var.manual_backend_hostname, ".", "-")
      host_name            = var.manual_backend_hostname
      origin_host_header   = var.manual_backend_hostname
      priority             = 1
      weight               = 1000
      enabled              = true
      http_port            = 80
      https_port           = 443
      certificate_name_check_enabled = true
    }
  ]

  merged_tags = merge(
    var.tags,
    {
      Environment    = var.environment
      DeploymentDate = timestamp()
      Subscription   = local.subscription_info.name
    }
  )
}
