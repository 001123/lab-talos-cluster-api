output "talos_management_ip" {
  description = "Static IPv4 address of the Talos Management Node"
  value       = var.node_ip
}

output "talos_management_vmid" {
  description = "VM ID on Proxmox VE"
  value       = proxmox_virtual_environment_vm.talos_management.vm_id
}

output "talos_management_cluster_name" {
  description = "Cluster Name"
  value       = var.cluster_name
}

output "talos_schematic_id" {
  description = "Talos Factory Schematic ID with QEMU Guest Agent"
  value       = talos_image_factory_schematic.talos.id
}

output "talos_installer_image" {
  description = "Talos Factory Installer Image"
  value       = data.talos_image_factory_urls.talos.urls.installer
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "talosconfig_path" {
  description = "Path to the generated talosconfig file"
  value       = local_file.talosconfig.filename
}
