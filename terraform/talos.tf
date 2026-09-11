# ==============================================================================
# Talos Machine Secrets & Configuration
# ==============================================================================

# 1. Generate cryptographic secrets for the Talos cluster
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# 2. Generate Control Plane machine configuration with custom patches
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${var.node_ip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = [
    templatefile("${path.module}/templates/controlplane.yaml.tpl", {
      allow_scheduling = var.allow_scheduling_on_control_planes
      node_ip          = var.node_ip
      node_ip_cidr     = var.node_ip_cidr
      gateway_ip       = var.gateway_ip
      nameservers      = var.nameservers
      installer_image  = data.talos_image_factory_urls.talos.urls.installer
    })
  ]
}

# 3. Generate Talos Client Configuration (talosconfig)
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [var.node_ip]
  endpoints            = [var.node_ip]
}

locals {
  # When the VM boots from ISO in maintenance mode, it receives a DHCP IP.
  # If reported by the QEMU Guest Agent, we use it as the initial apply endpoint,
  # otherwise fallback to var.node_ip.
  vm_initial_ip = try(
    [for ip in flatten(proxmox_virtual_environment_vm.talos_management.ipv4_addresses) : ip if !startswith(ip, "127.") && !startswith(ip, "169.254.")][0],
    var.node_ip
  )
}

# 4. Apply Machine Configuration to the VM
resource "talos_machine_configuration_apply" "controlplane" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_management]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.vm_initial_ip
  endpoint                    = local.vm_initial_ip
}

# 5. Bootstrap Single-Node etcd
resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
  endpoint             = var.node_ip
}

# 6. Retrieve Kubernetes Admin Kubeconfig
resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
  endpoint             = var.node_ip
}

# 7. Write kubeconfig and talosconfig locally
resource "local_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${var.output_directory}/kubeconfig"
  file_permission = "0600"
}

resource "local_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${var.output_directory}/talosconfig"
  file_permission = "0600"
}
