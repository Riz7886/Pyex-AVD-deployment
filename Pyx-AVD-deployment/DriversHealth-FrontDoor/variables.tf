variable "project_name" {
  type    = string
  default = "DriversHealth"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "location" {
  type    = string
  default = "East US"
}

variable "backend_host_name" {
  type = string
}

variable "health_probe_path" {
  type    = string
  default = "/"
}
