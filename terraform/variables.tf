# ==============================================================================
# Proxmox VE Connection Variables
# ==============================================================================

variable "proxmox_endpoint" {
  description = "The Proxmox VE API endpoint URL (e.g. https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "The Proxmox VE API Token in format USER@REALM!TOKENID=UUID"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Allow insecure TLS connections to Proxmox VE API"
  type        = bool
  default     = true
}

variable "proxmox_node_name" {
  description = "Target Proxmox VE node name (e.g. pve)"
  type        = string
  default     = "pve"
}

variable "proxmox_iso_datastore_id" {
  description = "Proxmox storage ID for storing Talos ISO images (e.g. local)"
  type        = string
  default     = "local"
}

variable "proxmox_disk_datastore_id" {
  description = "Proxmox storage ID for VM disks (e.g. local-lvm, local-zfs, ceph)"
  type        = string
  default     = "local-lvm"
}

# ==============================================================================
# Virtual Machine Hardware Specs
# ==============================================================================

variable "vm_id" {
  description = "VM ID for the Talos Management Node in Proxmox"
  type        = number
  default     = 800
}

variable "vm_name" {
  description = "Name for the Talos Management VM"
  type        = string
  default     = "talos-mgmt-cp-01"
}

variable "vm_cpu_cores" {
  description = "Number of vCPU cores allocated to the VM"
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Memory in MB allocated to the VM"
  type        = number
  default     = 4096
}

variable "vm_disk_size_gb" {
  description = "Disk size in GB for the Talos OS disk"
  type        = number
  default     = 40
}

variable "vm_network_bridge" {
  description = "Proxmox network bridge for the VM interface"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_vlan_id" {
  description = "Optional VLAN tag for the VM network interface"
  type        = number
  default     = null
}

# ==============================================================================
# Talos OS & Kubernetes Cluster Settings
# ==============================================================================

variable "cluster_name" {
  description = "Name of the Talos Management Cluster"
  type        = string
  default     = "talos-mgmt"
}

variable "talos_version" {
  description = "Talos OS version (e.g. v1.14.0)"
  type        = string
  default     = "v1.14.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version deployed by Talos (e.g. v1.37.0)"
  type        = string
  default     = "v1.37.0"
}

variable "node_ip" {
  description = "Static IPv4 address for the Talos Management node (e.g. 192.168.1.50)"
  type        = string
}

variable "node_ip_cidr" {
  description = "Subnet mask prefix in CIDR notation (e.g. 24 for 255.255.255.0)"
  type        = number
  default     = 24
}

variable "gateway_ip" {
  description = "Default gateway IPv4 address for the network (e.g. 192.168.1.1)"
  type        = string
}

variable "nameservers" {
  description = "List of DNS nameservers for the Talos node"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "allow_scheduling_on_control_planes" {
  description = "Allow running workloads directly on control plane node (required for single-node cluster)"
  type        = bool
  default     = true
}

variable "output_directory" {
  description = "Local directory where kubeconfig and talosconfig files will be saved"
  type        = string
  default     = "."
}
