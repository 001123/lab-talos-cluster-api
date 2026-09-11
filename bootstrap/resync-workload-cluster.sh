#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: Resync / Recreate CAPI Workload Cluster via Management Cluster GitOps
# Run this script whenever workload VMs are deleted or out of sync.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Kubeconfig resolution
if [[ -f "${REPO_ROOT}/terraform/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/terraform/kubeconfig"
elif [[ -f "${REPO_ROOT}/kubeconfig" ]]; then
  export KUBECONFIG="${REPO_ROOT}/kubeconfig"
fi

if [[ -z "${KUBECONFIG:-}" ]] || [[ ! -f "${KUBECONFIG}" ]]; then
  echo "❌ Error: Kubeconfig not found for Management Cluster."
  echo "👉 Ensure terraform/kubeconfig or kubeconfig exists in the repo root."
  exit 1
fi

CLUSTER_NAME="${1:-dev-talos-cluster-template}"
NAMESPACE="${2:-default}"

echo "=============================================================================="
echo "🔄 Resyncing Workload Cluster: '${CLUSTER_NAME}' (namespace: ${NAMESPACE})"
echo "=============================================================================="
echo "• Management Kubeconfig: ${KUBECONFIG}"
echo "=============================================================================="

# 1. Check required tools
if ! command -v kubectl &>/dev/null; then
  echo "❌ Error: 'kubectl' is required but not installed."
  exit 1
fi

# 2. Verify connection to Management Cluster
echo "🔍 1. Checking connection to Management Cluster..."
if ! kubectl cluster-info --request-timeout=5s &>/dev/null; then
  echo "❌ Error: Cannot connect to Kubernetes Management Cluster."
  exit 1
fi
echo "✅ Management Cluster is reachable."

# 3. Temporarily suspend Flux Kustomization to prevent race conditions during cleanup
echo "⏸️  2. Temporarily suspending Flux Kustomization 'sync-workloads'..."
if command -v flux &>/dev/null; then
  flux suspend kustomization sync-workloads -n flux-system &>/dev/null || true
else
  kubectl -n flux-system patch kustomization sync-workloads --type=merge -p '{"spec":{"suspend":true}}' &>/dev/null || true
fi
echo "✅ Flux synchronization paused."

# 4. Cleanup stuck CAPI and IPAM resources
echo "🧹 3. Cleaning up old CAPI and IPAM states for '${CLUSTER_NAME}'..."

# Trigger cluster deletion non-blocking
kubectl delete cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" --wait=false &>/dev/null || true

# Strip finalizers from stuck ProxmoxMachines
echo "   • Releasing ProxmoxMachine finalizers..."
for pm in $(kubectl get proxmoxmachines -n "${NAMESPACE}" -l "cluster.x-k8s.io/cluster-name=${CLUSTER_NAME}" -o name 2>/dev/null || true); do
  kubectl patch "${pm}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":null}}' --type=merge &>/dev/null || true
done

# Strip finalizers from stuck Machines
echo "   • Releasing Machine finalizers..."
for m in $(kubectl get machines -n "${NAMESPACE}" -l "cluster.x-k8s.io/cluster-name=${CLUSTER_NAME}" -o name 2>/dev/null || true); do
  kubectl patch "${m}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":null}}' --type=merge &>/dev/null || true
done

# Strip finalizers from Cluster object if still terminating
kubectl patch cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":null}}' --type=merge &>/dev/null || true

# Cleanup IPAM claims and protect finalizers on IPAddresses
echo "   • Freeing InCluster IPAM pool addresses..."
for ip in $(kubectl get ipaddress.ipam.cluster.x-k8s.io -n "${NAMESPACE}" -o name 2>/dev/null || true); do
  kubectl patch "${ip}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":null}}' --type=merge &>/dev/null || true
  kubectl delete "${ip}" -n "${NAMESPACE}" --wait=false &>/dev/null || true
done

for ipc in $(kubectl get ipaddressclaim.ipam.cluster.x-k8s.io -n "${NAMESPACE}" -o name 2>/dev/null || true); do
  kubectl patch "${ipc}" -n "${NAMESPACE}" -p '{"metadata":{"finalizers":null}}' --type=merge &>/dev/null || true
  kubectl delete "${ipc}" -n "${NAMESPACE}" --wait=false &>/dev/null || true
done

# Remove any stale legacy IP pools if exist
kubectl delete inclusterippool "${CLUSTER_NAME}-v4-icip" -n "${NAMESPACE}" --wait=false &>/dev/null || true

# Cleanup workload secrets in namespace
echo "   • Removing old workload secrets..."
for s in $(kubectl get secrets -n "${NAMESPACE}" -o name 2>/dev/null | grep "${CLUSTER_NAME}" || true); do
  kubectl delete "${s}" -n "${NAMESPACE}" --wait=false &>/dev/null || true
done

echo "✅ Old state successfully wiped."

# 5. Resume and trigger Flux reconciliation
echo "🚀 4. Resuming Flux GitOps and triggering immediate reconciliation..."
if command -v flux &>/dev/null; then
  flux resume kustomization sync-workloads -n flux-system &>/dev/null || true
  flux reconcile kustomization sync-workloads -n flux-system --with-source &>/dev/null || true
else
  kubectl -n flux-system patch kustomization sync-workloads --type=merge -p '{"spec":{"suspend":false}}' &>/dev/null || true
  kubectl apply -k "${REPO_ROOT}/gitops/workloads/dev-cluster"
fi
echo "✅ GitOps manifests applied successfully."

# 6. Monitor provisioning progress
echo ""
echo "=============================================================================="
echo "⏳ 5. Waiting for Cluster API and CAPMOX to spawn fresh VMs from Template..."
echo "=============================================================================="

for i in {1..30}; do
  MACHINES_COUNT=$(kubectl get machines -n "${NAMESPACE}" -l "cluster.x-k8s.io/cluster-name=${CLUSTER_NAME}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${MACHINES_COUNT}" -ge 4 ]]; then
    echo "✅ Discovered ${MACHINES_COUNT} VMs requested by CAPI."
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

kubectl get machines -n "${NAMESPACE}" -l "cluster.x-k8s.io/cluster-name=${CLUSTER_NAME}" -o wide || true

echo ""
echo "=============================================================================="
echo "🎉 Re-sync complete! CAPI is now cloning and bootstrapping your Workload Cluster."
echo ""
echo "👉 Helpful monitoring commands:"
echo "• Watch CAPI machines:    kubectl get machines -w"
echo "• Watch workload nodes:   kubectl --kubeconfig <(kubectl get secret ${CLUSTER_NAME}-kubeconfig -o jsonpath='{.data.value}' | base64 -d) get nodes -w"
echo "=============================================================================="
