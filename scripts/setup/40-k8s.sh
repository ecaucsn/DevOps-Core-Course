#!/usr/bin/env bash
# Kubernetes-инструменты: kubectl, k3d, Helm, ArgoCD CLI, плагин Argo Rollouts, OpenBao CLI (bao).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# --- kubectl ---
if have kubectl && [ "${FORCE:-0}" != "1" ]; then
  ok "kubectl уже установлен: $(kubectl version --client 2>/dev/null | head -1)"
else
  ver="${KUBECTL_VERSION:-$(curl -fsSL --max-time 20 https://dl.k8s.io/release/stable.txt)}"
  install_direct "https://dl.k8s.io/release/${ver}/bin/linux/${ARCH}/kubectl" kubectl --version
  ok "kubectl $ver"
fi

# --- k3d ---
if have k3d && [ "${FORCE:-0}" != "1" ]; then
  ok "k3d уже установлен: $(k3d version | head -1)"
else
  install_direct \
    "https://github.com/k3d-io/k3d/releases/download/v${K3D_VERSION}/k3d-linux-${ARCH}" \
    k3d version
fi

# --- Helm ---
if have helm && [ "${FORCE:-0}" != "1" ]; then
  ok "Helm уже установлен: $(helm version --short 2>/dev/null)"
else
  install_tar_member \
    "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" \
    helm helm
  ok "Helm -> $(helm version --short 2>/dev/null)"
fi

# --- ArgoCD CLI ---
if have argocd && [ "${FORCE:-0}" != "1" ]; then
  ok "argocd уже установлен: $(argocd version --client --short 2>/dev/null || argocd version --client 2>/dev/null | head -1)"
else
  install_direct \
    "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-${ARCH}" \
    argocd version
fi

# --- Плагин kubectl argo rollouts ---
if have kubectl-argo-rollouts && [ "${FORCE:-0}" != "1" ]; then
  ok "kubectl-argo-rollouts уже установлен: $(kubectl-argo-rollouts version 2>/dev/null | head -1)"
else
  install_direct \
    "https://github.com/argoproj/argo-rollouts/releases/download/v${ARGO_ROLLOUTS_VERSION}/kubectl-argo-rollouts-linux-${ARCH}" \
    kubectl-argo-rollouts version
fi

# --- OpenBao CLI (bao) ---
if have bao && [ "${FORCE:-0}" != "1" ]; then
  ok "bao уже установлен: $(bao version 2>/dev/null | head -1)"
else
  install_tar_member \
    "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/openbao_${OPENBAO_VERSION}_linux_${ARCH}.tar.gz" \
    bao bao
  ok "bao -> $(bao version 2>/dev/null | head -1)"
fi
