# Replaces the manual `kubectl create namespace argocd` + `kubectl apply -f install.yaml`
# steps in Manualconfigurations.md. The reconciliation timeout tweak (previously a manual
# `kubectl edit cm argocd-cm`) is set here as a chart value instead.

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.argocd_namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version != "" ? var.argocd_chart_version : null

  set {
    name  = "configs.cm.timeout\\.reconciliation"
    value = "10s"
  }

  depends_on = [module.aks]
}
