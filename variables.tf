variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "DriversHealth"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
}

variable "backend_host_name" {
  description = "Backend origin server hostname"
  type        = string
}

variable "health_probe_path" {
  description = "Path for health probe checks"
  type        = string
  default     = "/"
}

variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "devops@drivershealth.com"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
