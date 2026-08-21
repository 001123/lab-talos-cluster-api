#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: Create Talos Linux VM Template on Proxmox VE from Disk Image
# Run this script directly on your Proxmox VE host (Shell or SSH)
# ==============================================================================

# Configurable Parameters (can be overridden via environment variables)
TALOS_VERSION="${TALOS_VERSION:-v1.13.9}"
# Talos factory schematic ID containing siderolabs/qemu-guest-agent extension:
TALOS_SCHEMATIC_ID="${TALOS_SCHEMATIC_ID:-376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba}"
PROXMOX_DISK_STORAGE="${PROXMOX_DISK_STORAGE:-local-lvm}"
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-talos-${TALOS_VERSION}-template}"
TEMPLATE_TAG="${TEMPLATE_TAG:-talos}"
MEMORY_MB="${MEMORY_MB:-2048}"
CORES="${CORES:-2}"
NETWORK_BRIDGE="${NETWORK_BRIDGE:-vmbr0}"

echo "=============================================================================="
echo "🚀 Creating Talos VM Template from Disk Image (Proxmox VE)"
echo "=============================================================================="
echo "• Template VMID:    ${TEMPLATE_VMID}"
echo "• Template Name:    ${TEMPLATE_NAME}"
echo "• Talos Version:    ${TALOS_VERSION}"
echo "• Schematic ID:     ${TALOS_SCHEMATIC_ID}"
echo "• Storage:          ${PROXMOX_DISK_STORAGE}"
echo "• Bridge:           ${NETWORK_BRIDGE}"
echo "• Memory / Cores:   ${MEMORY_MB} MB / ${CORES} vCPUs"
echo "=============================================================================="

# 1. Check if running on Proxmox VE host
if ! command -v qm &>/dev/null; then
  echo "❌ Error: 'qm' command not found. This script must be run directly on the Proxmox VE host."
  exit 1
fi

TMP_DIR="/tmp/talos-template-${TEMPLATE_VMID}"
RAW_GZ_FILE="${TMP_DIR}/talos.raw.gz"
RAW_FILE="${TMP_DIR}/talos.raw"
IMAGE_URL="https://factory.talos.dev/image/${TALOS_SCHEMATIC_ID}/${TALOS_VERSION}/nocloud-amd64.raw.gz"

# 2. Cleanup old VM/Template if it exists
if qm status "${TEMPLATE_VMID}" &>/dev/null; then
  echo "⚠️  VM/Template ${TEMPLATE_VMID} already exists. Destroying previous instance..."
  qm destroy "${TEMPLATE_VMID}" --purge || true
fi

# 3. Download Talos raw.gz image
echo "📥 1. Downloading Talos Disk Image from Image Factory..."
mkdir -p "${TMP_DIR}"
curl -f -sSL -o "${RAW_GZ_FILE}" "${IMAGE_URL}"

# 4. Decompress raw image
echo "📦 2. Decompressing raw disk image..."
gzip -df "${RAW_GZ_FILE}"

# 5. Create base VM configuration
echo "🛠️  3. Creating VM ${TEMPLATE_VMID}..."
qm create "${TEMPLATE_VMID}" \
  --name "${TEMPLATE_NAME}" \
  --memory "${MEMORY_MB}" \
  --cores "${CORES}" \
  --cpu host \
  --bios ovmf \
  --machine q35 \
  --efidisk0 "${PROXMOX_DISK_STORAGE}:0,efitype=4m,pre-enrolled-keys=0" \
  --net0 "virtio,bridge=${NETWORK_BRIDGE}" \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --tags "${TEMPLATE_TAG}" \
  --agent 1

# 6. Import disk into Proxmox storage
echo "💾 4. Importing disk image into ${PROXMOX_DISK_STORAGE}..."
qm importdisk "${TEMPLATE_VMID}" "${RAW_FILE}" "${PROXMOX_DISK_STORAGE}"

# 7. Attach disk and set boot order
echo "🔗 5. Attaching disk to scsi0 and setting boot order..."
IMPORTED_DISK=$(qm config "${TEMPLATE_VMID}" | grep '^unused[0-9]:' | awk '{print $2}' | head -n1)
if [[ -n "${IMPORTED_DISK}" ]]; then
  qm set "${TEMPLATE_VMID}" --scsihw virtio-scsi-pci --scsi0 "${IMPORTED_DISK},discard=on,ssd=1"
else
  echo "❌ Error: Could not locate imported disk for VM ${TEMPLATE_VMID}"
  exit 1
fi
qm set "${TEMPLATE_VMID}" --boot order=scsi0

# 8. Convert to Proxmox Template
echo "📦 6. Converting VM ${TEMPLATE_VMID} to template..."
qm template "${TEMPLATE_VMID}"

# 9. Clean up temporary files
echo "🧹 7. Cleaning up temporary files..."
rm -rf "${TMP_DIR}"

echo "=============================================================================="
echo "✅ Successfully created Talos Disk-Image Template (${TEMPLATE_VMID})!"
echo "• Tag:     ${TEMPLATE_TAG}"
echo "• Name:    ${TEMPLATE_NAME}"
echo "• Status:  Ready for Cluster API Provider Proxmox (CAPMOX)!"
echo "=============================================================================="
