# ==============================================================================
# Talos OS Custom Image with QEMU Guest Agent Extension
# ==============================================================================

# Define the Image Factory Schematic containing QEMU Guest Agent
resource "talos_image_factory_schematic" "talos" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent"
        ]
      }
    }
  })
}

# Fetch the ISO and Installer URLs for the specified Talos version & schematic
data "talos_image_factory_urls" "talos" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.talos.id
  platform      = "nocloud"
  architecture  = "amd64"
}

# Download Talos ISO directly to Proxmox VE ISO storage
resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore_id
  node_name    = var.proxmox_node_name
  url          = data.talos_image_factory_urls.talos.urls.iso
  file_name    = "talos-${var.talos_version}-${talos_image_factory_schematic.talos.id}.iso"
}
