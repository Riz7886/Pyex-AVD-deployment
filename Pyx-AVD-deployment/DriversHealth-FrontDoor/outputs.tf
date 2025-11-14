output "frontdoor_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

output "resource_group" {
  value = azurerm_resource_group.frontdoor.name
}

output "subscription" {
  value = data.azurerm_subscription.current.display_name
}
