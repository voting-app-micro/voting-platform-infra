variable "name" {
  description = "AKS cluster name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to place the cluster in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the cluster (must be unique per region)"
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "oidc_issuer_enabled" {
  description = "Enable the OIDC issuer (required for Workload Identity). Off by default — not used by the current manual setup, needed for Phase 3 (AI agent workload identity)."
  type        = bool
  default     = false
}

variable "workload_identity_enabled" {
  description = "Enable Workload Identity. Off by default, same reasoning as oidc_issuer_enabled."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the cluster"
  type        = map(string)
  default     = {}
}
