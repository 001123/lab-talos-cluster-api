#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Step 2: Setup Mozilla SOPS & Age Encryption for GitOps
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECONFIG_PATH="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"
export KUBECONFIG="${KUBECONFIG_PATH}"

# Check for required CLI tools
if ! command -v age-keygen &>/dev/null; then
  echo "❌ Missing requirement: 'age-keygen' is not installed."
  echo "👉 Install with: brew install age"
  exit 1
fi

AGE_KEY_FILE="${REPO_ROOT}/age.agekey"

echo "🔑 1. Checking Age encryption key..."
if [[ ! -f "${AGE_KEY_FILE}" ]]; then
  echo "Generating new Age key at: ${AGE_KEY_FILE}..."
  age-keygen -o "${AGE_KEY_FILE}"
  chmod 600 "${AGE_KEY_FILE}"
else
  echo "Existing Age key found at: ${AGE_KEY_FILE}"
fi

# Extract Public Key
AGE_PUBLIC_KEY="$(grep "public key:" "${AGE_KEY_FILE}" | cut -d ' ' -f 4 || true)"
if [[ -z "${AGE_PUBLIC_KEY}" ]]; then
  AGE_PUBLIC_KEY="$(age-keygen -y "${AGE_KEY_FILE}")"
fi

echo "Public Key: ${AGE_PUBLIC_KEY}"

echo "📦 2. Creating flux-system namespace and applying sops-age Secret..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey="${AGE_KEY_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "📝 3. Updating .sops.yaml with the generated Age Public Key..."
cat <<EOF > "${REPO_ROOT}/.sops.yaml"
# SOPS Configuration for GitOps Manifests
creation_rules:
  - path_regex: gitops/.*\\.sops\\.ya?ml$
    age: "${AGE_PUBLIC_KEY}"
  - path_regex: gitops/.*secret.*\\.ya?ml$
    age: "${AGE_PUBLIC_KEY}"
EOF

echo "✅ Age key and SOPS configuration completed successfully!"
echo "Secret 'sops-age' is active in namespace 'flux-system'."
echo ""
echo "Next step: Run './bootstrap/03-install-flux-operator.sh' to deploy Flux Operator."
