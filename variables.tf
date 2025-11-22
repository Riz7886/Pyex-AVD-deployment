variable "network_resource_group" {
  description = "Existing resource group containing the virtual network"
  type        = string
}

variable "deployment_resource_group" {
  description = "Resource group for new deployments (Load Balancer, Front Door, WAF)"
  type        = string
}

variable "location" {
  description = "Azure region for deployments"
  type        = string
}

variable "vnet_name" {
  description = "Existing virtual network name"
  type        = string
}

variable "subnet_name" {
  description = "Existing subnet name for MOVEit"
  type        = string
}

variable "moveit_private_ip" {
  description = "Private IP address of MOVEit Transfer server"
  type        = string
}

variable "nsg_name" {
  description = "Network Security Group name"
  type        = string
}

variable "lb_name" {
  description = "Load Balancer name for FTPS"
  type        = string
}

variable "lb_public_ip_name" {
  description = "Public IP name for Load Balancer"
  type        = string
}

variable "frontdoor_profile_name" {
  description = "Azure Front Door profile name"
  type        = string
}

variable "frontdoor_endpoint_name" {
  description = "Azure Front Door endpoint name"
  type        = string
}

variable "frontdoor_origin_group_name" {
  description = "Azure Front Door origin group name"
  type        = string
}

variable "frontdoor_origin_name" {
  description = "Azure Front Door origin name"
  type        = string
}

variable "frontdoor_route_name" {
  description = "Azure Front Door route name"
  type        = string
}

variable "frontdoor_sku" {
  description = "Azure Front Door SKU"
  type        = string
}

variable "waf_policy_name" {
  description = "WAF policy name"
  type        = string
}

variable "waf_mode" {
  description = "WAF mode (Detection or Prevention)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
