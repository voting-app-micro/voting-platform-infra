variable "name" {
  description = "ACR name (globally unique, alphanumeric only)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to place the registry in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "sku" {
  description = "Registry SKU: Basic, Standard, or Premium"
  type        = string
  default     = "Basic"
}

variable "admin_enabled" {
  description = "Enable the ACR admin user (used for initial manual setup; not needed once AKS pulls via managed identity)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the registry"
  type        = map(string)
  default     = {}
}
