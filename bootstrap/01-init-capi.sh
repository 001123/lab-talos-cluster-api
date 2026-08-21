#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Step 1: Initialize Cluster API (CAPI) on Talos Management Cluster
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Determine kubeconfig path
KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "❌ Error: Kubeconfig file not found at: ${KUBECONFIG_PATH}"
  echo "👉 Please run Terraform first ('terraform -chdir=terraform apply') to generate the cluster & kubeconfig."
  exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

# Check for required CLI tools
for tool in kubectl clusterctl; do
  if ! command -v "${tool}" &>/dev/null; then
    echo "❌ Missing requirement: '${tool}' is not installed or not in PATH."
    if [[ "${tool}" == "clusterctl" ]]; then
      echo "👉 Install clusterctl with: brew install clusterctl"
    fi
    exit 1
  fi
done

echo "🔍 1. Verifying connection to Talos Management Cluster..."
kubectl cluster-info --request-timeout=10s

# Optional clusterctl config override
if [[ -f "${SCRIPT_DIR}/clusterctl.yaml" ]]; then
  export CLUSTERCTL_CONFIG="${SCRIPT_DIR}/clusterctl.yaml"
  echo "ℹ️  Using custom clusterctl config: ${CLUSTERCTL_CONFIG}"
fi

echo "🚀 2. Initializing Cluster API with Proxmox, Talos & In-Cluster IPAM providers..."
clusterctl init \
  --infrastructure proxmox \
  --control-plane talos \
  --bootstrap talos \
  --ipam in-cluster

echo "⏳ 3. Waiting for CAPI core controllers to become ready..."
kubectl -n capi-system wait --for=condition=Available deployment/capi-controller-manager --timeout=180s || true

echo "✅ Cluster API initialized successfully!"
echo ""
echo "Next step: Run './bootstrap/02-setup-sops-age.sh' to setup GitOps secrets encryption."
