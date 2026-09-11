# ==============================================================================
# Proxmox Virtual Machine for Talos Management Node
# ==============================================================================

resource "proxmox_virtual_environment_vm" "talos_management" {
  node_name   = var.proxmox_node_name
  vm_id       = var.vm_id
  name        = var.vm_name
  description = "Talos Linux Management Cluster - Managed by Terraform"

  cpu {
    cores = var.vm_cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  agent {
    enabled = true
    timeout = "10m"
  }

  bios    = "ovmf"
  machine = "q35"

  efi_disk {
    datastore_id      = var.proxmox_disk_datastore_id
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  operating_system {
    type = "l26" # Linux 2.6 - 6.X kernel
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  disk {
    datastore_id = var.proxmox_disk_datastore_id
    interface    = "scsi0"
    size         = var.vm_disk_size_gb
    file_format  = "raw"
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge  = var.vm_network_bridge
    vlan_id = var.vm_network_vlan_id
    model   = "virtio"
  }

  boot_order = ["scsi0", "ide2"]

  started = true

  lifecycle {
    ignore_changes = [
      cdrom,
      boot_order
    ]
  }
}
