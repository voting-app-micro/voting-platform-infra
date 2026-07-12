# Terraform Infra Pipeline — Prerequisites

Things that must exist / be configured **before** `Terraform-infra-pipeline.yml` can run successfully.
None of these are created by the pipeline itself — they're one-time setup, done manually or via a
separate bootstrap step.

---

## 1. Backend state storage (bootstrap — chicken-and-egg)

The pipeline's `terraform init -backend-config=...` only *points at* an existing Azure Storage
Account/container — it does not create it. Must exist first:

```bash
az storage account create -n <tfstate-storage-account> -g <rg> -l <region> --sku Standard_LRS
az storage container create -n tfstate --account-name <tfstate-storage-account>
```

State blob key used: `voting-platform/dev.tfstate`.

---

## 2. Azure DevOps Library variable group: `voting-platform-infra-secrets`

Referenced at [Terraform-infra-pipeline.yml:42](.pipelines/Terraform-infra-pipeline.yml#L42). Must be
created under **Pipelines → Library** with these 4 variables filled in (currently the values must
point at the storage account from step 1):

| Variable | Purpose |
|---|---|
| `TerraformServiceConnection` | Name of the ARM service connection (step 3) |
| `tfStateResourceGroup` | RG holding the tfstate storage account |
| `tfStateStorageAccount` | Storage account name from step 1 |
| `tfStateContainer` | Container name from step 1 (`tfstate`) |

First pipeline run using this VG may prompt to **"authorize resource"** — approve it, or pre-authorize
under the VG's *Pipeline permissions* tab, to avoid the run stalling on approval.

---

## 3. Azure DevOps Service Connection

Under **Project Settings → Service Connections**: an ARM service connection (Contributor on the
subscription) whose name matches the `TerraformServiceConnection` value above. Same pattern as
`ACRRegistryServiceConnection` used in `voting-platform-app`.

---

## 4. Azure DevOps Environment: `infra-dev`

Under **Pipelines → Environments**, create `infra-dev` (referenced at
[Terraform-infra-pipeline.yml:172](.pipelines/Terraform-infra-pipeline.yml#L172)) so a manual approval
check can be attached (Environments → infra-dev → Approvals and checks) — the human gate between the
Plan and Apply stages on `main`.

---

## 5. `envs/dev/terraform.tfvars`

The only in-repo file with concrete values, loaded automatically (no `-var-file` flag needed):

```hcl
azure_region        = "eastus"
environment         = "dev"
resource_group_name = "voting-app-project"
aks_cluster_name    = "azuredevops"
acr_name            = "votingappregistry7"
aks_node_count      = 2
```

`azure_region` is **not confirmed** against the actual deployed resource group — verify with
`az group show -n voting-app-project --query location` before the first plan/import, or the plan
will show a spurious diff.

---

## 6. Existing manually-created infra needs `terraform import` first

Per [Manualconfigurations.md](Manualconfigurations.md#L125-L134), the RG/ACR/AKS/ACR-pull-role/Argo CD
were created manually before this Terraform config existed. There is **no `import {}` block or import
script in this repo** — before the first real `apply` against them, each resource must be imported by
hand (e.g. `terraform import module.resource_group.azurerm_resource_group.this ...`), otherwise
`apply` will try to create duplicates and fail on name collisions.

This only applies to the current dev environment's pre-existing resources — a from-scratch
environment (nothing pre-existing) does not need this step.

---

## 7. First-ever apply into an *empty* subscription (no import needed, but still a gotcha)

Noted at [Terraform-infra-pipeline.yml:220-225](.pipelines/Terraform-infra-pipeline.yml#L220-L225): the
`helm` provider in `providers.tf` reads AKS connection details from `module.aks`, which doesn't exist
yet on a truly from-scratch apply. Terraform can't always resolve this in one pass. If it fails:

```bash
terraform apply -target=module.aks
```

once, then re-run the pipeline for the full apply (including Argo CD).

---

## Summary — what's a repo file vs. portal config

- **Repo file to edit:** `envs/dev/terraform.tfvars` only.
- **Portal config (not in any file):** variable group values, service connection, environment approval,
  and the one-time storage account bootstrap.
