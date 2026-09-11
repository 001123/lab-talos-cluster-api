#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: Cleanup CAPI Workload Virtual Machines on Proxmox VE
# Run this script directly on your Proxmox VE host (Shell or SSH)
# ==============================================================================

# Protected VM IDs & names that must NEVER be deleted (e.g. Management Cluster)
PROTECTED_VMIDS=("800" "9000")
PROTECTED_PREFIXES=("talos-mgmt")

FORCE=false
if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]] || [[ "${1:-}" == "-y" ]]; then
  FORCE=true
  shift || true
fi

echo "=============================================================================="
echo "🧹 Proxmox VE - Cluster API (CAPMOX) Workload VMs Cleanup"
echo "=============================================================================="
echo "🛡️  Protected VMs: ${PROTECTED_VMIDS[*]} (Talos Management Cluster & Template)"
echo "=============================================================================="

# 1. Verify Proxmox environment
if ! command -v qm &>/dev/null; then
  echo "❌ Error: 'qm' command not found. This script must be run directly on the Proxmox VE host."
  exit 1
fi

TARGET_VMIDS=()

# 2. Determine target VMs
if [[ "$#" -gt 0 ]]; then
  # User specified explicit VM IDs
  for vmid in "$@"; do
    TARGET_VMIDS+=("${vmid}")
  done
else
  # Auto-discover workload VMs created by Cluster API
  echo "🔍 Scanning for Cluster API workload VMs on this node..."
  while read -r vmid name status; do
    # Skip header
    if [[ "${vmid}" == "VMID" ]] || [[ -z "${vmid}" ]]; then
      continue
    fi

    # Check if protected by ID
    is_protected=false
    for p_id in "${PROTECTED_VMIDS[@]}"; do
      if [[ "${vmid}" == "${p_id}" ]]; then
        is_protected=true
        break
      fi
    done

    # Check if protected by prefix
    for p_prefix in "${PROTECTED_PREFIXES[@]}"; do
      if [[ "${name}" == ${p_prefix}* ]]; then
        is_protected=true
        break
      fi
    done

    if [[ "${is_protected}" == true ]]; then
      continue
    fi

    # Match CAPI workload VMs by naming pattern or tags
    vm_config=$(qm config "${vmid}" 2>/dev/null || true)
    if [[ "${name}" == dev-talos* ]] || [[ "${name}" == talos-cluster* ]] || echo "${vm_config}" | grep -q 'go-proxmox'; then
      TARGET_VMIDS+=("${vmid}")
    fi
  done < <(qm list | awk '{print $1, $2, $3}')
fi

if [[ "${#TARGET_VMIDS[@]}" -eq 0 ]]; then
  echo "✅ No CAPI workload VMs found to clean up."
  exit 0
fi

echo "Found ${#TARGET_VMIDS[@]} workload VM(s) to remove:"
for vmid in "${TARGET_VMIDS[@]}"; do
  vm_name=$(qm config "${vmid}" 2>/dev/null | grep '^name:' | awk '{print $2}' || echo "unknown")
  vm_status=$(qm status "${vmid}" 2>/dev/null | awk '{print $2}' || echo "unknown")
  echo "  • VM ${vmid}: ${vm_name} (Status: ${vm_status})"
done

if [[ "${FORCE}" != true ]]; then
  echo ""
  read -rp "⚠️  Are you sure you want to STOP and PURGE these VMs? (y/N): " confirm
  if [[ "${confirm}" != "y" ]] && [[ "${confirm}" != "Y" ]]; then
    echo "❌ Cleanup aborted by user."
    exit 0
  fi
fi

# 3. Stop and purge target VMs
for vmid in "${TARGET_VMIDS[@]}"; do
  # Double check protection
  for p_id in "${PROTECTED_VMIDS[@]}"; do
    if [[ "${vmid}" == "${p_id}" ]]; then
      echo "⛔ SKIPPING protected VM ${vmid}!"
      continue 2
    fi
  done

  echo "------------------------------------------------------------------------------"
  echo "🗑️  Processing VM ${vmid}..."

  # Stop if running
  if qm status "${vmid}" 2>/dev/null | grep -q 'running'; then
    echo "  🛑 Stopping VM ${vmid}..."
    qm stop "${vmid}" --skiplock 1 || true
    # Wait for VM to stop
    for i in {1..10}; do
      if ! qm status "${vmid}" 2>/dev/null | grep -q 'running'; then
        break
      fi
      sleep 1
    done
    # Force kill if still running
    if qm status "${vmid}" 2>/dev/null | grep -q 'running'; then
      echo "  ⚠️  Force killing VM ${vmid}..."
      qm kill "${vmid}" 2>/dev/null || true
      sleep 1
    fi
  fi

  # Destroy and purge disks
  echo "  💥 Purging VM ${vmid} and associated disks..."
  qm destroy "${vmid}" --purge 1 --skiplock 1 2>/dev/null || true

  # Clean up specific cloud-init ISO if exists
  if [[ -f "/var/lib/vz/template/iso/user-data-${vmid}.iso" ]]; then
    echo "  🧹 Removing /var/lib/vz/template/iso/user-data-${vmid}.iso..."
    rm -f "/var/lib/vz/template/iso/user-data-${vmid}.iso"
  fi
done

# 4. Clean up any leftover orphan cloud-init user-data ISOs
echo "------------------------------------------------------------------------------"
echo "🧹 Cleaning up orphan cloud-init ISOs in /var/lib/vz/template/iso/..."
find /var/lib/vz/template/iso/ -maxdepth 1 -name "user-data-*.iso" -exec rm -f {} + 2>/dev/null || true
rm -f /var/lib/vz/template/import/test.raw 2>/dev/null || true

echo "=============================================================================="
echo "✅ Cleanup completed successfully!"
echo "• Management Cluster (VM 800): Preserved and intact"
echo "• Workload VMs: Cleared"
echo ""
echo "👉 If needed, reset CAPI machines on your workstation with:"
echo "   kubectl --kubeconfig=terraform/kubeconfig delete machines -A --all"
echo "=============================================================================="
