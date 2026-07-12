# Values match the resources already running per Manualconfigurations.md.
# azure_region is NOT confirmed against the actual deployed resources yet —
# verify with `az group show -n voting-app-project --query location` before
# the first plan/import, or the plan will show a spurious diff.
azure_region = "eastus"
environment  = "dev"

resource_group_name = "voting-app-project"
aks_cluster_name    = "azuredevops"
acr_name            = "votingappregistry7"
aks_node_count      = 2
