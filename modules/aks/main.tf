resource "azurerm_log_analytics_workspace" "aks" {
  name                = "${var.name}-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix

  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled

  # No-cost Checkov hardening (CKV_AZURE_171, CKV_AZURE_116) — plain config flags, no
  # extra resources or architecture impact.
  automatic_channel_upgrade = "patch"
  azure_policy_enabled      = true

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
    # CKV_AZURE_168 — safe to set now since this is a from-scratch create (cluster was
    # torn down); max_pods forces node pool replacement if changed on an existing cluster.
    max_pods = 50
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    # CKV_AZURE_7 — no cost, works out of the box with the Azure CNI plugin above.
    network_policy = "azure"
  }

  # CKV_AZURE_172 — enables the free Secrets Store CSI driver add-on with autorotation.
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # CKV_AZURE_4 — ships container/node logs to the Log Analytics workspace above
  # (within its free 5GB/day ingestion tier for a dev-sized cluster).
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  }

  tags = var.tags
}
