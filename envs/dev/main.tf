module "resource_group" {
  source = "../../modules/resource-group"

  name     = var.resource_group_name
  location = var.azure_region
  tags = {
    environment = var.environment
  }
}

module "acr" {
  source = "../../modules/acr"

  name                = var.acr_name
  resource_group_name = module.resource_group.name
  location            = var.azure_region
  tags = {
    environment = var.environment
  }
}

module "aks" {
  source = "../../modules/aks"

  name                = var.aks_cluster_name
  resource_group_name = module.resource_group.name
  location            = var.azure_region
  dns_prefix          = var.aks_cluster_name
  node_count          = var.aks_node_count
  tags = {
    environment = var.environment
  }
}

# Replaces `az aks update --attach-acr` from Manualconfigurations.md
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}
