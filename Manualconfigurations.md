# Manual Configuration Steps — Infra & Argo CD Setup

Manual (non-Terraform) steps followed to stand up the environment for the voting platform.
This is the "get it working" path; provisioning will move to Terraform in a later phase.

**Resources referenced here**
- Resource group: `voting-app-project`
- AKS cluster: `azuredevops`
- ACR: `votingappregistry7`

---

## Overview

1. Create ACR
2. Create Kubernetes (AKS) cluster
3. Install & configure Argo CD on the cluster
4. Expose the Argo CD UI
5. (Next) Shell script to update the K8s manifests

---

## 1. Azure login

```bash
az logout

az login --tenant "ee1ef095-fc21-4d1f-8d7a-104a597df771" \
  --scope "https://management.core.windows.net//.default"
```

## 2. Provision resources

- Create the **ACR** (`votingappregistry7`).
- Create the **AKS cluster** (`azuredevops`) in resource group `voting-app-project`.

> Done manually via portal / `az` for now. To avoid ImagePullBackOff, attach the ACR to AKS
> so the kubelet identity can pull without secrets:
> ```bash
> az aks update -n azuredevops -g voting-app-project --attach-acr votingappregistry7
> ```

## 3. Connect kubectl to the cluster

```bash
az aks get-credentials --name azuredevops --resource-group voting-app-project --overwrite-existing

# verify connectivity
kubectl get nodes -o wide
kubectl get pods
```

---

## 4. Install Argo CD

```bash
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait until all pods are Running
kubectl get pods -n argocd
```

---

## 5. Access the Argo CD UI

### Option A — Port-forward (used ✅, recommended)

No cluster changes, no public exposure. Keep this terminal open while using the UI.

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open **https://localhost:8080** (accept the self-signed cert warning).

### Option B — NodePort (public access, alternative)

```bash
kubectl get svc -n argocd
kubectl edit svc argocd-server -n argocd
# change spec.type from ClusterIP to NodePort
```

Then, to reach it from outside:
- Get a node's external IP: `kubectl get node -o wide`
- On the cluster's VM/VMSS, open the **NSG inbound rule** for the NodePort.

> ⚠️ Option B exposes Argo CD to the internet without TLS/ingress hardening — fine for a quick
> demo only. Prefer Option A (port-forward) for day-to-day work.

---

## 6. Get the initial admin password

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" `
  | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

Login: user `admin` + the decoded password above.

<details>
<summary>Manual decode alternative</summary>

```bash
kubectl get secrets -n argocd
kubectl edit secret argocd-initial-admin-secret -n argocd
echo <base64-value> | base64 --decode
```
</details>

---
# By default argo cd takes 180 sec to reflect changes and to fix or update this we can edit argo cd config map

kubectl edit cm argocd-cm -n argocd
```
data:
  timeout.reconciliation: 10s
```
## Next steps

- [ ] Register the `voting-platform-config` repo in Argo CD.
- [ ] Create an Argo CD Application pointing at `overlays/dev` (namespace `voting`, `CreateNamespace=true`).
- [ ] Shell script (in `voting-platform-app`) to update the K8s manifests / image tags in the config repo.
- [x] Later: replace this manual setup with Terraform in `voting-platform-infra`. See `P1.Documentations/plan.md`
      for scope/design and `modules/` + `envs/dev/` in this repo for the implementation. Steps 1–2, 4, and 6
      (RG, ACR, AKS, ACR↔AKS pull access, Argo CD install + reconciliation timeout) are now covered by Terraform;
      the resources above still need `terraform import` against the existing manually-created infra before the
      first `apply` to avoid duplicates.
