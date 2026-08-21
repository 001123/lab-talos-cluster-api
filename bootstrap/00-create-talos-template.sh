#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Step 0: Create Talos Linux VM Template on Proxmox VE for Cluster API (CAPMOX)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration defaults
PROXMOX_NODE="${PROXMOX_NODE:-pve-pc}"
PROXMOX_DISK_STORAGE="${PROXMOX_DISK_STORAGE:-local-lvm}"
PROXMOX_ISO_STORAGE="${PROXMOX_ISO_STORAGE:-local}"
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-talos-v1.13.8-template}"
TEMPLATE_TAG="${TEMPLATE_TAG:-talos}"
DISK_SIZE_GB="${DISK_SIZE_GB:-10}"
MEMORY_MB="${MEMORY_MB:-2048}"
CORES="${CORES:-2}"

# 1. Parse Proxmox credentials from clusterctl.yaml, terraform.tfvars, or ENV
PROXMOX_URL="${PROXMOX_URL:-}"
PROXMOX_TOKEN="${PROXMOX_TOKEN:-}"
PROXMOX_SECRET="${PROXMOX_SECRET:-}"

if [[ -z "${PROXMOX_URL}" ]] && [[ -f "${SCRIPT_DIR}/clusterctl.yaml" ]]; then
  PROXMOX_URL=$(grep "^PROXMOX_URL:" "${SCRIPT_DIR}/clusterctl.yaml" | awk '{print $2}' | tr -d '"' | head -n1)
  PROXMOX_TOKEN=$(grep "^PROXMOX_TOKEN:" "${SCRIPT_DIR}/clusterctl.yaml" | awk '{print $2}' | tr -d '"' | head -n1)
  PROXMOX_SECRET=$(grep "^PROXMOX_SECRET:" "${SCRIPT_DIR}/clusterctl.yaml" | awk '{print $2}' | tr -d '"' | head -n1)
fi

if [[ -z "${PROXMOX_URL}" ]] && [[ -f "${REPO_ROOT}/terraform/terraform.tfvars" ]]; then
  PROXMOX_URL=$(grep "^proxmox_endpoint" "${REPO_ROOT}/terraform/terraform.tfvars" | awk '{print $3}' | tr -d '"' | sed 's|/$||' | head -n1)
  RAW_TOKEN=$(grep "^proxmox_api_token" "${REPO_ROOT}/terraform/terraform.tfvars" | awk '{print $3}' | tr -d '"' | head -n1)
  PROXMOX_TOKEN="${RAW_TOKEN%%=*}"
  PROXMOX_SECRET="${RAW_TOKEN#*=}"
  TF_NODE=$(grep "^proxmox_node_name" "${REPO_ROOT}/terraform/terraform.tfvars" | awk '{print $3}' | tr -d '"' | head -n1)
  if [[ -n "${TF_NODE}" ]]; then PROXMOX_NODE="${TF_NODE}"; fi
fi

if [[ -z "${PROXMOX_URL}" ]] || [[ -z "${PROXMOX_TOKEN}" ]] || [[ -z "${PROXMOX_SECRET}" ]]; then
  echo "❌ Error: Missing Proxmox API connection parameters."
  echo "👉 Please provide PROXMOX_URL, PROXMOX_TOKEN, and PROXMOX_SECRET in bootstrap/clusterctl.yaml or environment variables."
  exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${PROXMOX_TOKEN}=${PROXMOX_SECRET}"

echo "=============================================================================="
echo "🚀 Creating Talos VM Template on Proxmox VE"
echo "=============================================================================="
echo "• Proxmox Endpoint: ${PROXMOX_URL}"
echo "• Target Node:      ${PROXMOX_NODE}"
echo "• Template VMID:    ${TEMPLATE_VMID}"
echo "• Template Name:    ${TEMPLATE_NAME}"
echo "• Tag:              ${TEMPLATE_TAG}"
echo "• Disk Storage:     ${PROXMOX_DISK_STORAGE}"
echo "=============================================================================="

# 2. Test connection to Proxmox API
echo "🔍 1. Testing connection to Proxmox API..."
PVE_VERSION=$(curl -k -s -f -H "${AUTH_HEADER}" "${PROXMOX_URL}/api2/json/version" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true)
if [[ -z "${PVE_VERSION}" ]]; then
  echo "❌ Failed to connect to Proxmox API at ${PROXMOX_URL} with the provided API token."
  exit 1
fi
echo "✅ Proxmox API reachable (PVE Version: ${PVE_VERSION})."

# 3. Locate Talos ISO in Proxmox ISO storage
echo "🔍 2. Locating Talos ISO file on ${PROXMOX_ISO_STORAGE} storage..."
STORAGE_CONTENT=$(curl -k -s -f -H "${AUTH_HEADER}" "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/storage/${PROXMOX_ISO_STORAGE}/content")
TALOS_ISO_VOLID=$(echo "${STORAGE_CONTENT}" | grep -o '"volid":"[^"]*talos[^"]*\.iso"' | head -n1 | cut -d'"' -f4 || true)

if [[ -z "${TALOS_ISO_VOLID}" ]]; then
  echo "❌ Could not find any Talos ISO in storage '${PROXMOX_ISO_STORAGE}' on node '${PROXMOX_NODE}'."
  echo "👉 Ensure Terraform has downloaded the Talos ISO or upload it manually via Proxmox UI."
  exit 1
fi
echo "✅ Found Talos ISO: ${TALOS_ISO_VOLID}"

# 4. Check if VM ID already exists
echo "🔍 3. Checking if VM ID ${TEMPLATE_VMID} already exists..."
VM_CHECK_STATUS=$(curl -k -s -H "${AUTH_HEADER}" "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_VMID}/status/current")
if echo "${VM_CHECK_STATUS}" | grep -q '"template":1'; then
  echo "ℹ️  VM ${TEMPLATE_VMID} already exists and is already a template."
  echo "✅ Template is ready for use by Cluster API Provider Proxmox (CAPMOX)."
  exit 0
elif echo "${VM_CHECK_STATUS}" | grep -q '"status"'; then
  echo "⚠️  VM ${TEMPLATE_VMID} exists but is not a template."
  if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]]; then
    echo "🗑️  Force deleting existing VM ${TEMPLATE_VMID}..."
    curl -k -s -X DELETE -H "${AUTH_HEADER}" "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_VMID}" > /dev/null || true
    sleep 3
  else
    echo "👉 Run with '--force' to destroy and recreate the template, or choose another TEMPLATE_VMID."
    exit 1
  fi
fi

# 5. Create the VM via Proxmox REST API
echo "🛠️  4. Creating VM ${TEMPLATE_VMID} (${TEMPLATE_NAME})..."
CREATE_RESP=$(curl -k -s -f -X POST \
  -H "${AUTH_HEADER}" \
  --data-urlencode "vmid=${TEMPLATE_VMID}" \
  --data-urlencode "name=${TEMPLATE_NAME}" \
  --data-urlencode "tags=${TEMPLATE_TAG}" \
  --data-urlencode "ostype=l26" \
  --data-urlencode "cpu=host" \
  --data-urlencode "cores=${CORES}" \
  --data-urlencode "memory=${MEMORY_MB}" \
  --data-urlencode "scsihw=virtio-scsi-pci" \
  --data-urlencode "scsi0=${PROXMOX_DISK_STORAGE}:${DISK_SIZE_GB},discard=on,ssd=1" \
  --data-urlencode "ide2=${TALOS_ISO_VOLID},media=cdrom" \
  --data-urlencode "boot=order=scsi0;ide2" \
  --data-urlencode "net0=virtio,bridge=vmbr0" \
  --data-urlencode "agent=1" \
  "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/qemu")

echo "⏳ Waiting for VM creation to finalize..."
sleep 5

# 6. Convert the VM to Template
echo "📦 5. Converting VM ${TEMPLATE_VMID} to template..."
CONVERT_RESP=$(curl -k -s -f -X POST \
  -H "${AUTH_HEADER}" \
  "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_VMID}/template")

echo "⏳ Waiting for template conversion to complete..."
sleep 3

# 7. Verification
echo "🔍 6. Verifying template configuration..."
VERIFY_CONFIG=$(curl -k -s -H "${AUTH_HEADER}" "${PROXMOX_URL}/api2/json/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_VMID}/config")
if echo "${VERIFY_CONFIG}" | grep -q '"template":1' && echo "${VERIFY_CONFIG}" | grep -q 'talos'; then
  echo "=============================================================================="
  echo "✅ Successfully created Talos VM Template ${TEMPLATE_VMID} on Proxmox VE!"
  echo "• Tags: ${TEMPLATE_TAG}"
  echo "• Cluster API Provider Proxmox (CAPMOX) can now clone VMs from this template."
  echo "=============================================================================="
else
  echo "⚠️  Warning: Could not confirm template conversion. Response:"
  echo "${VERIFY_CONFIG}"
fi
