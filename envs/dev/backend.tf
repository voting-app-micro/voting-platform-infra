terraform {
  backend "azurerm" {
    # Values supplied via `terraform init -backend-config=...` (see README Quick Start),
    # not hardcoded here — this backend is shared infra, not environment-specific config.
    # resource_group_name  = ""
    # storage_account_name = ""
    # container_name       = "tfstate"
    # key                  = "voting-platform/dev.tfstate"
  }
}
