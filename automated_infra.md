# Terraform Infra Pipeline — Prerequisites

Things that must exist / be configured **before** the infra pipelines can run successfully — split
across [.pipelines/PR-infra-pipelines.yml](.pipelines/PR-infra-pipelines.yml) (Plan-only, runs on PRs
into main) and [.pipelines/Publish-infra-pipelines.yml](.pipelines/Publish-infra-pipelines.yml)
(Plan + Apply, runs only on push/merge to main). None of these prerequisites are created by either
pipeline itself — they're one-time setup, done manually or via a separate bootstrap step.

---

## Stepwise walkthrough — clean-slate (nothing exists in Azure at all)

Assumes no RG/ACR/AKS/tfstate storage exists yet. See the numbered sections below for full detail on
each item.

**1. Azure/ADO groundwork (manual, one-time)**
- Ensure you have Contributor access on the target subscription.
- Create the Azure AD app registration / service principal ADO will use, with Contributor on the subscription.

**2. Bootstrap the tfstate backend storage** (manual, one-time — Terraform can't create the place it stores its own state; see [section 1](#1-backend-state-storage-bootstrap--chicken-and-egg))
- Use [scripts/prerequisite.ps1](scripts/prerequisite.ps1) to run this — it creates the RG, storage account (with blob versioning + delete retention), and the `tfstate` container in one go. Update the `$rg` / `$storageAccount` names at the top before running.

**3. Azure DevOps portal config** (see [section 2](#2-azure-devops-library-variable-group-voting-platform-infra-secrets), [section 3](#3-azure-devops-service-connection), [section 4](#4-azure-devops-environment-infra-dev))
- **Service Connection** (Project Settings → Service Connections): ARM connection using the SP from step 1.
- **Variable group** `voting-platform-infra-secrets` (Pipelines → Library): fill in `TerraformServiceConnection`, `tfStateResourceGroup`, `tfStateStorageAccount`, `tfStateContainer` with step 2's values.
- **Environment** `infra-dev` (Pipelines → Environments): create it; optionally attach a manual approval check.

**4. Set values in [envs/dev/terraform.tfvars](envs/dev/terraform.tfvars)** (see [section 5](#5-envsdevterraformtfvars))
- Since nothing pre-exists, these can be any names you want (no collision risk) — just pick real RG/ACR/AKS names and confirm `azure_region`.
- **No `terraform import` needed at all in this scenario** — that step (see [section 6](#6-existing-manually-created-infra-needs-terraform-import-first)) only applies to the existing manually-created dev resources.

**5. Open a PR touching `envs/dev/*`**
- Triggers **PR-infra-pipelines.yml** (Plan stage only). Review the `plan-summary` artifact — should show all resources to be created, nothing to destroy/change.

**6. Merge to main**
- Triggers **Publish-infra-pipelines.yml** (Plan + Apply, in the same run). Expect the known first-run snag (see [section 7](#7-first-ever-apply-into-an-empty-subscription-no-import-needed-but-still-a-gotcha)): the `helm` provider needs AKS details that don't exist yet on a from-scratch apply — may fail on `helm_release.argocd`. If so, run once locally/manually:
  ```bash
  terraform apply -target=module.aks
  ```
  then re-run the pipeline for the full apply.

**7. Verify after Apply succeeds**
```bash
az aks get-credentials -n <aks_cluster_name> -g <resource_group_name> --overwrite-existing
kubectl get nodes
kubectl get pods -n argocd
```
Get the admin password (Manualconfigurations.md section 6).

**8. Still manual after this** — see [section 8](#8-post-apply-whats-still-manual) for the full list.

---

## 1. Backend state storage (bootstrap — chicken-and-egg)

The pipeline's `terraform init -backend-config=...` only *points at* an existing Azure Storage
Account/container — it does not create it. Must exist first — run [scripts/prerequisite.ps1](scripts/prerequisite.ps1)
(update the `$rg` / `$storageAccount` values at the top first), or manually:

```bash
az storage account create -n <tfstate-storage-account> -g <rg> -l <region> --sku Standard_LRS
az storage container create -n tfstate --account-name <tfstate-storage-account>
```

State blob key used: `voting-platform/dev.tfstate`.

---

## 2. Azure DevOps Library variable group: `voting-platform-infra-secrets`

Referenced in both pipelines — [PR-infra-pipelines.yml:30](.pipelines/PR-infra-pipelines.yml#L30) and
[Publish-infra-pipelines.yml:31](.pipelines/Publish-infra-pipelines.yml#L31). Must be
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
[Publish-infra-pipelines.yml:161](.pipelines/Publish-infra-pipelines.yml#L161)) so a manual approval
check can be attached (Environments → infra-dev → Approvals and checks) — the human gate between the
Plan and Apply stages, both of which now run only in `Publish-infra-pipelines.yml` on `main`.

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

Noted at [Publish-infra-pipelines.yml:209-214](.pipelines/Publish-infra-pipelines.yml#L209-L214): the
`helm` provider in `providers.tf` reads AKS connection details from `module.aks`, which doesn't exist
yet on a truly from-scratch apply. Terraform can't always resolve this in one pass. If it fails:

```bash
terraform apply -target=module.aks
```

once, then re-run the pipeline for the full apply (including Argo CD).

---

## 8. Post-apply: what's still manual

Once `terraform apply` finishes (AKS + Argo CD running, nothing else), this is what's left —
none of it is in Terraform or any script yet:

- **Get the Argo CD admin password** (Manualconfigurations.md #6) —
  `kubectl -n argocd get secret argocd-initial-admin-secret ...` — needed for first login.
- **Register the `voting-platform-config` repo in Argo CD** — via UI or `argocd repo add`.
- **Create the Argo CD Application** pointing at `overlays/dev` (namespace `voting`,
  `CreateNamespace=true`) — this is what actually triggers the first deployment; nothing deploys
  until this exists.
- **Access the Argo CD UI** — with port-forward (Option A, recommended), this is a manual command
  every session (`kubectl port-forward svc/argocd-server -n argocd 8080:443`), not a one-time setup.
- **Networking fix in the Azure Portal (if you kept the NodePort change in `argocd.tf`):** the Helm
  `server.service.type = NodePort` value only changes the Kubernetes Service — it does **not** open
  any path in from outside the VNet. You still have to go into the **Azure Portal (or `az network
  nsg rule create`)** and add an NSG inbound rule on the AKS node pool's NSG for that NodePort
  (typically in the `30000-32767` range — check the actual port with `kubectl get svc -n argocd
  argocd-server`). No `network` module exists in this repo yet to automate this — it's a manual
  portal step every time the NodePort changes (AKS reassigns NodePorts on Service recreation unless
  pinned via `nodePort:` in the Helm values). Until this NSG rule is added, the Argo CD UI is
  **not reachable externally** even though the Service itself is NodePort.
- **Confirm the app's publish pipeline pushes a matching image tag to ACR** — not your job to
  trigger, but a dependency: until it does, pods sit in `ImagePullBackOff` (expected, self-heals
  once the tag lands — see the reconciliation-timeout note in [argocd.tf](envs/dev/argocd.tf)).
- **(Not yet addressed anywhere) Argo CD hardening** — default admin password / local auth only, no
  SSO/RBAC wired up. Fine for dev; flag as a gap before this pattern goes to staging/prod.

---

## Summary — what's a repo file vs. portal config

- **Repo file to edit:** `envs/dev/terraform.tfvars` only.
- **Portal config (not in any file):** variable group values, service connection, environment approval,
  and the one-time storage account bootstrap.
