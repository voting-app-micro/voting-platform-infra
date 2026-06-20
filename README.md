# Voting Platform Infrastructure

Terraform infrastructure-as-code for provisioning the voting platform on Azure.

## Overview

This repository contains reusable Terraform modules for deploying a production-grade GitOps platform on Azure Kubernetes Service (AKS). Infrastructure spans compute, networking, container registry, secrets management, and observability.

## Repository Structure

```
voting-platform-infra/
├── modules/
│   ├── aks/           (AKS cluster with OIDC issuer, Workload Identity)
│   ├── acr/           (Azure Container Registry)
│   ├── network/       (VNet, subnets, NSG, Network Policies)
│   ├── keyvault/      (Azure Key Vault for secrets)
│   └── monitoring/    (Azure Monitor, Prometheus, Grafana)
├── envs/
│   ├── dev/           (Development environment)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   ├── staging/       (Staging environment)
│   └── prod/          (Production environment)
├── .terraform-version (Terraform version constraint)
└── README.md
```

## Modules

### AKS Module
Provisions Azure Kubernetes Service cluster with:
- OIDC issuer enabled (for Workload Identity)
- Workload Identity enabled
- Multiple node pools (optional)
- System-assigned managed identity
- Network plugin: Azure CNI

### ACR Module
Provisions Azure Container Registry with:
- Registry tier: Basic/Standard/Premium
- Admin user (for initial setup)
- Attached to AKS for image pull (no imagePullSecrets)

### Network Module
Provisions Virtual Network with:
- VNet with configurable CIDR
- Subnets (control plane, worker nodes, etc.)
- Network Security Groups (NSG) with rules
- Network Policies for pod-to-pod communication

### Key Vault Module
Provisions Azure Key Vault with:
- Soft-delete & purge protection enabled
- RBAC-based access control
- Secrets for app credentials
- Federated credentials for Workload Identity

### Monitoring Module
Provisions observability stack:
- Azure Monitor managed Prometheus
- Azure Monitor managed Grafana
- Alert rules and dashboards

## Prerequisites

```bash
# Install Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads.html

# Install Azure CLI
brew install azure-cli  # macOS
# or download from https://learn.microsoft.com/en-us/cli/azure/

# Authenticate to Azure
az login
az account set --subscription "<subscription-id>"

# Terraform version
terraform version  # 1.5.0+
```

## Quick Start

### 1. Initialize Terraform State Backend

```bash
# Create Azure Storage Account for Terraform state
az storage account create \
  -n <unique-tfstate-name> \
  -g <resource-group> \
  -l <region> \
  --sku Standard_LRS

az storage container create \
  -n tfstate \
  --account-name <unique-tfstate-name>
```

### 2. Deploy to Dev Environment

```bash
cd envs/dev

terraform init \
  -backend-config="resource_group_name=<rg>" \
  -backend-config="storage_account_name=<tfstate-name>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=voting-platform/dev.tfstate"

terraform plan -var-file=terraform.tfvars

terraform apply
```

### 3. Get AKS Credentials

```bash
az aks get-credentials \
  -n <aks-cluster-name> \
  -g <resource-group> \
  --overwrite-existing

kubectl get nodes
```

## Environment Variables

Each environment (dev/staging/prod) requires:

```hcl
# terraform.tfvars
azure_region            = "eastus"
environment             = "dev"
aks_cluster_name        = "voting-platform-dev"
aks_node_count          = 2
acr_name                = "votingplatformdev"
keyvault_name           = "voting-platform-dev-kv"
```

## Outputs

After `terraform apply`, outputs include:

```
aks_cluster_name       = AKS cluster name for kubectl access
acr_login_server       = ACR login server for docker push
keyvault_id            = Key Vault ID for Workload Identity
keyvault_uri           = Key Vault URI for secret access
```

## State Management

Terraform state is stored in Azure Storage Account with:
- Remote state backend (no local state committed)
- State locking via Blob lease
- Encryption at rest (Azure managed)

**Never commit `.tfstate` files to Git.**

## Phase Integration

This infrastructure supports the GitOps platform phases:

- **Phase 0:** Throwaway cluster for K8s learning
- **Phase 1:** Core platform (AKS, ACR, Key Vault, networking)
- **Phase 2:** Hardening (monitoring, admission control, secrets rotation)
- **Phase 3:** AI operations (Workload Identity for agent access)

## Related Repositories

- **voting-platform-app:** Application source code
- **voting-platform-config:** Kustomize manifests & Argo CD configurations

## Terraform Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
