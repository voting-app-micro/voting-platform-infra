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
- Ensure you have Contributor (or Owner, to grant Contributor to the connection below) access on the target subscription.
- Don't create the app registration/service principal by hand first — create the **Service Connection** directly (see [section 3](#3-azure-devops-service-connection)); ADO provisions the underlying identity for you in one step.

**2. Bootstrap the tfstate backend storage** (manual, one-time — Terraform can't create the place it stores its own state; see [section 1](#1-backend-state-storage-bootstrap--chicken-and-egg))
- Use [scripts/prerequisite.ps1](scripts/prerequisite.ps1) to run this — it creates the RG, storage account (with blob versioning + delete retention), and the `tfstate` container in one go. Update the `$rg` / `$storageAccount` names at the top before running.

**3. Azure DevOps portal config** (see [section 2](#2-azure-devops-library-variable-group-voting-platform-infra-secrets), [section 3](#3-azure-devops-service-connection), [section 4](#4-azure-devops-environment-infra-dev))
- **Service Connection** (Project Settings → Service Connections → New → Azure Resource Manager → **Workload identity federation (automatic)**, Contributor on the subscription) — this is where the identity from step 1 actually gets created, in one step.
- **Variable group** `voting-platform-infra-secrets` (Pipelines → Library): fill in `TerraformServiceConnection`, `tfStateResourceGroup`, `tfStateStorageAccount`, `tfStateContainer` with step 2's values.
- **Environment** `infra-dev` (Pipelines → Environments): create it; optionally attach a manual approval check.

**4. Set values in [envs/dev/terraform.tfvars](envs/dev/terraform.tfvars)** (see [section 5](#5-envsdevterraformtfvars))
- ⚠️ **This "clean-slate" walkthrough is hypothetical for this repo's current dev environment.** The
  names already committed in `terraform.tfvars` (`voting-app-project`, `azuredevops`,
  `votingappregistry7`) are **real resources that already exist** in this subscription today
  (Manualconfigurations.md). Only proceed with these exact names via the **import path**
  ([section 6](#6-existing-manually-created-infra-needs-terraform-import-first)) — never `apply`
  against them unimported, or Terraform will try to create duplicates and fail on name collisions.
- If you genuinely want a separate, brand-new environment (e.g. a second dev cluster, or standing
  this up in a different subscription) — pick **different** RG/ACR/AKS names than the ones above,
  confirm `azure_region`, and skip the import step entirely; nothing collides.
- **No `terraform import` needed** only in that second, genuinely-new-names case.

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

Under **Project Settings → Service Connections → New service connection → Azure Resource Manager**.
Don't pre-create an app registration/SP by hand — pick the identity type ADO creates for you:

- **Recommended: Workload identity federation (automatic).** ADO creates the app registration and an
  OIDC federated credential trusting this specific pipeline — no client secret is ever generated,
  stored, or rotated. This is the current Microsoft-recommended approach and what a mature setup
  should use. Select subscription → resource group scope not required (leave at subscription level
  since this connection provisions RG/ACR/AKS themselves) → grant **Contributor** on the subscription.
- **Fallback: App registration or service principal (automatic), secret-based.** Only use this if
  your ADO organization doesn't support workload identity federation yet. This generates a real
  client secret ADO stores and uses — has an expiry you must rotate manually before it lapses.

Either way, name the connection whatever you'll put in the `TerraformServiceConnection` variable
(step 2 of the walkthrough). Same pattern as `ACRRegistryServiceConnection` used in
`voting-platform-app`, just prefer the federated option here since this connection needs Contributor
on the whole subscription (broader blast radius than a registry-scoped connection, so a
credential-less approach matters more).

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

These values point at **real, currently-running resources** (see [section 6](#6-existing-manually-created-infra-needs-terraform-import-first))
— don't run `apply` against this file as-is without importing first, and don't change these names
"just to test" without realizing you'd be pointing Terraform at a different (non-existent, or
someone else's) set of resources.

---

## 6. Existing manually-created infra needs `terraform import` first

Per [Manualconfigurations.md](Manualconfigurations.md#L125-L134), the RG/ACR/AKS/ACR-pull-role/Argo CD
were created manually before this Terraform config existed. This only applies to the current dev
environment's pre-existing resources — a from-scratch environment (nothing pre-existing) does not
need this section at all.

### Use `import {}` blocks, not ad-hoc `terraform import` CLI

A one-off `terraform import` run by a human against production-ish infra isn't how a mature pipeline
does this — it's invisible to `terraform plan`, isn't reviewable in a PR, and can't run non-interactively
in the pipeline's `AzureCLI@2` steps. Instead, add a temporary `import.tf` in `envs/dev/` with
[`import {}` blocks](https://developer.hashicorp.com/terraform/language/import) (supported since
Terraform 1.5, which this repo already requires). These show up as "N resources to import" in
`terraform plan` — reviewable in the PR pipeline's plan-summary artifact like any other change —
and apply cleanly through the normal `Publish-infra-pipelines.yml` run. Delete `import.tf` once the
first apply succeeds; it's a one-time migration aid, not permanent config.

```hcl
# envs/dev/import.tf — delete after first successful apply

import {
  to = module.resource_group.azurerm_resource_group.this
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/voting-app-project"
}

import {
  to = module.acr.azurerm_container_registry.this
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/voting-app-project/providers/Microsoft.ContainerRegistry/registries/votingappregistry7"
}

import {
  to = module.aks.azurerm_kubernetes_cluster.this
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/voting-app-project/providers/Microsoft.ContainerService/managedClusters/azuredevops"
}

import {
  to = azurerm_role_assignment.aks_acr_pull
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/voting-app-project/providers/Microsoft.ContainerRegistry/registries/votingappregistry7/providers/Microsoft.Authorization/roleAssignments/<ROLE_ASSIGNMENT_GUID>"
}
```

- The role assignment's GUID isn't guessable — look it up first:
  ```bash
  az role assignment list --scope <acr-resource-id> --query "[?roleDefinitionName=='AcrPull'].name" -o tsv
  ```

### Argo CD can't be imported this way — decide instead of importing

Your manual Argo CD was installed via raw `kubectl apply -f install.yaml`
(Manualconfigurations.md section 4), **not** `helm install`. Terraform's `helm_release.argocd`
resource tracks state through a Helm release record that only exists for charts actually installed
via Helm — there is nothing to import it into. Don't attempt an `import {}` block for it; pick one:

- **Reinstall via Helm (recommended, matches how the rest of this migration works):** delete the
  manually-installed Argo CD (`kubectl delete namespace argocd` — confirm you're fine losing its
  current app registrations first, since you'll redo [section 8](#8-post-apply-whats-still-manual)'s
  "register repo + create Application" steps afterward), then let the normal `apply`
  (with `import.tf` covering only RG/ACR/AKS/role-assignment) create it fresh via `helm_release`.
- **Or exclude it for now:** temporarily comment out/remove `argocd.tf` from this apply, import and
  reconcile just RG/ACR/AKS/role-assignment first, and handle the Argo CD Helm cutover as its own
  deliberate follow-up once the rest of the state matches reality.

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
