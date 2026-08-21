#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Step 3: Install ControlPlane Flux Operator & Initialize FluxInstance
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"
export KUBECONFIG="${KUBECONFIG_PATH}"

# Check for required CLI tools
for tool in helm kubectl; do
  if ! command -v "${tool}" &>/dev/null; then
    echo "❌ Missing requirement: '${tool}' is not installed."
    exit 1
  fi
done

FLUX_OPERATOR_VERSION="0.58.1"

echo "🚢 1. Installing Flux Operator v${FLUX_OPERATOR_VERSION} via Helm OCI..."
helm upgrade --install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --version "${FLUX_OPERATOR_VERSION}" \
  --namespace flux-system \
  --create-namespace \
  --wait

echo "⏳ 2. Waiting for Flux Operator to be ready..."
kubectl -n flux-system wait --for=condition=Available deployment/flux-operator --timeout=120s

echo "🚀 3. Applying FluxInstance GitOps manifests..."
kubectl apply -k "${REPO_ROOT}/gitops/flux-system"

echo "✅ Flux Operator and FluxInstance deployed successfully!"
echo "Flux Web UI status page is accessible via:"
echo "  kubectl -n flux-system port-forward svc/flux-operator 9080:9080"
echo "  Open http://localhost:9080 in your browser."
