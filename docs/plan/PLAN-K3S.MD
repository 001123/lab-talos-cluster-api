# Kế hoạch Triển khai K3s Management Cluster & Talos Workload Clusters trên Proxmox

Tài liệu thiết kế kiến trúc và hướng dẫn chuyển đổi cụm **Management Cluster** từ Talos SNO sang **K3s (Debian 12 Minimal Cloud-Init VM)**, kết hợp **Cluster API (CAPI)** để tự động hóa khởi tạo và quản lý các cụm **Talos Workload Clusters** trên Proxmox VE cùng hệ thống **GitOps Flux Operator + SOPS**.

---

## 📌 1. Mục tiêu & Lý do Thiết kế (Objective & Rationale)

1. **Tối ưu hóa tài nguyên phần cứng (Resource Efficiency):**
   - Management Cluster chỉ đóng vai trò làm Controller Plane (chạy CAPI controllers, Flux controllers, SOPS decryptor), không chạy application workloads.
   - K3s sử dụng SQLite/Kine và gói gọn trong 1 single binary giúp giảm mức chiếm dụng RAM từ **~2.5GB - 3.5GB** (của full K8s + etcd) xuống chỉ còn **~800MB - 1.2GB RAM**.
2. **Khởi động và Bootstrap cực nhanh:**
   - K3s khởi động hoàn tất trong < 45 giây sau khi VM boot.
3. **Giữ nguyên 100% tính năng & kiến trúc Workload Clusters:**
   - Các cụm Workload thực tế phục vụ ứng dụng vẫn là **Talos Linux** (bảo mật, bất biến - immutable, API-driven) được tạo tự động thông qua các CAPI Providers: **CAPMOX** (Proxmox), **CABPT** (Talos Bootstrap), **CACCPT** (Talos Control Plane).

---

## 🏗️ 2. Kiến trúc Tổng quan (Hybrid Architecture)

```
                                  +--------------------------------------------------+
                                  |                   Proxmox VE                     |
                                  |                                                  |
                                  |  +--------------------------------------------+  |
                                  |  |   K3s Management Cluster (Debian 12 VM)    |  |
                                  |  |   - Specs: 2 vCPU, 2GB RAM, 20GB Disk      |  |
                                  |  |   - K3s v1.31+ (Disable Traefik/ServiceLB) |  |
                                  |  |   - Core CAPI Controllers                  |  |
                                  |  |   - CAPMOX (Proxmox Infrastructure)        |  |
                                  |  |   - CABPT & CACCPT (Talos Bootstrap & CP)  |  |
                                  |  |   - In-Cluster IPAM Provider               |  |
                                  |  |   - Flux Operator (v0.60.0) + SOPS (Age)   |  |
                                  |  +---------------------+----------------------+  |
                                  +------------------------|-------------------------+
                                                           |
                                      [CAPI + CAPMOX Reconcile & Provision]
                                                           |
                                                           v
                                  +--------------------------------------------------+
                                  |          Talos Workload Cluster (e.g. dev)       |
                                  |  +--------------------+  +--------------------+  |
                                  |  | Control Plane VM   |  | Worker VMs         |  |
                                  |  | (Talos + Flannel)  |  | (Talos + Flannel)  |  |
                                  |  +--------------------+  +--------------------+  |
                                  +--------------------------------------------------+
```

---

## 📊 3. Bảng So Sánh Kỹ Thuật: K3s vs Talos SNO (Management Node)

| Tiêu chí | Talos SNO Management | K3s trên Debian 12 Management |
| :--- | :--- | :--- |
| **Mức tiêu thụ RAM tối thiểu** | ~2.5 GB - 3.5 GB (Full K8s + etcd) | **~800 MB - 1.2 GB (SQLite/Kine + K3s)** |
| **Thời gian Boot & Ready** | ~2 - 3 phút | **~30 - 45 giây** |
| **Quản trị OS nền** | Không có SSH/Shell (API `talosctl`) | SSH chuẩn Linux, Cloud-Init, `systemctl` |
| **Tương thích CAPI & Flux** | 100% | **100%** (CAPI và Flux chạy Pod chuẩn) |
| **Cài đặt & Tự động hóa** | Terraform Siderolabs Provider | **Terraform Cloud-Init Snippet** |
| **Workload Cluster tạo ra** | Talos Linux | **Talos Linux (Không thay đổi)** |

---

## 📁 4. Cấu trúc Thư mục Dự kiến

```
talos-cluster-api/
├── .gitignore                              # Bỏ qua credentials, state, keys, kubeconfig
├── .sops.yaml                              # Cấu hình mã hóa SOPS cho GitOps manifests
├── README.md                               # Hướng dẫn chi tiết sử dụng và vận hành
├── PLAN-K3S.MD                             # Kế hoạch và thiết kế chi tiết kiến trúc K3s
│
├── terraform/                              # TẦNG 1: TERRAFORM MANAGEMENT CLUSTER (K3S)
│   ├── versions.tf                         # Khai báo bpg/proxmox (>= 0.111.1)
│   ├── variables.tf                        # Biến Proxmox, Debian image URL, SSH key, specs
│   ├── terraform.tfvars.example            # Mẫu cấu hình
│   ├── main.tf                             # Provider Proxmox VE
│   ├── image.tf                            # Tự động tải Debian 12 Cloud Image (.qcow2)
│   ├── cloud_init.tf                       # Sinh Cloud-init Snippet (user_data) cài đặt K3s tự động
│   ├── vm.tf                               # Khởi tạo VM K3s Management trên Proxmox
│   └── outputs.tf                          # Xuất IP, SSH command, kubeconfig helper info
│
├── bootstrap/                              # TẦNG 2: BOOTSTRAP CAPI & FLUX OPERATOR
│   ├── 00-get-kubeconfig.sh                # Script tự động kéo /etc/rancher/k3s/k3s.yaml về máy trạm
│   ├── clusterctl.yaml.example             # Cấu hình CAPI providers & Proxmox credentials
│   ├── 01-init-capi.sh                     # Script init CAPI Core + Proxmox + Talos + IPAM
│   ├── 02-setup-sops-age.sh                # Script sinh Age key & tạo Secret cho SOPS
│   └── 03-install-flux-operator.sh         # Script cài đặt Flux Operator v0.60.0 & apply FluxInstance
│
└── gitops/                                 # TẦNG 3: GITOPS WORKLOAD CLUSTERS & ADDONS
    ├── flux-system/
    │   ├── kustomization.yaml
    │   └── flux-instance.yaml              # FluxInstance CRD
    ├── clusters/
    │   └── management/
    │       ├── kustomization.yaml
    │       ├── git-repo.yaml               # GitRepository trỏ về kho Git
    │       └── sync-workloads.yaml         # Kustomization đồng bộ workloads kèm giải mã SOPS
    ├── templates/
    │   └── talos-proxmox-cluster/          # CAPI Templates chuẩn cho cụm Talos trên Proxmox
    │       ├── kustomization.yaml
    │       ├── cluster.yaml                # Cluster resource
    │       ├── proxmox-cluster.yaml        # ProxmoxCluster (CAPMOX)
    │       ├── control-plane.yaml          # TalosControlPlane & CP Machine Template
    │       ├── worker-deployment.yaml      # MachineDeployment & Worker Machine Template
    │       └── ipam-pool.yaml              # InClusterIPPool quản lý IP tĩnh
    └── workloads/
        ├── dev-cluster/                    # Cụm workload mẫu
        │   ├── kustomization.yaml
        │   └── patches/
        │       └── cluster-patch.yaml      # Patch tài nguyên, số node và dải IP
        └── addons/
            ├── ccm/
            │   └── talos-ccm.yaml          # Talos Cloud Controller Manager
            └── cni/
                └── flannel.yaml            # Flannel CNI
```

---

## 🛠️ 5. Chi tiết Thiết kế Kỹ thuật (Technical Implementation)

### 🔹 Tầng 1: Terraform Cloud-Init & K3s VM

#### 1. Image Download (`image.tf`)
- Sử dụng Debian 12 GenericCloud image:
  `https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2`
- Lưu vào Proxmox storage `local:iso` dưới dạng file image qcow2.

#### 2. Cloud-Init Snippet (`cloud_init.tf`)
- Tạo file Cloud-Init User-Data tải lên storage `local:snippets`:
```yaml
#cloud-config
hostname: k3s-mgmt
manage_etc_hosts: true
users:
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
packages:
  - qemu-guest-agent
  - curl
  - ca-certificates

runcmd:
  - systemctl enable --now qemu-guest-agent
  - |
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
      --tls-san ${node_ip} \
      --disable traefik \
      --disable servicelb \
      --write-kubeconfig-mode 644" sh -
```

#### 3. Cấu hình VM (`vm.tf`)
- **VM Specs:** 2 vCPU, 2048 MB RAM, 20GB Disk (SCSI, iothread).
- **Mạng:** Static IP qua cấu hình IPConfig Cloud-Init (`ip=${node_ip}/${cidr},gw=${gateway}`).
- Gắn file snippet User-Data vào thuộc tính `initialization.user_data_file_id`.

---

### 🔹 Tầng 2: Bootstrap CAPI & Flux Operator

#### 1. Lấy Kubeconfig (`00-get-kubeconfig.sh`)
- Tự động SSH hoặc sử dụng `scp` tải `/etc/rancher/k3s/k3s.yaml` từ `debian@<NODE_IP>` về `./kubeconfig` (hoặc `terraform/kubeconfig`).
- Tự động thay thế `server: https://127.0.0.1:6443` thành `server: https://<NODE_IP>:6443`.
- Thiết lập quyền `chmod 600 kubeconfig`.

#### 2. Khởi tạo CAPI Providers (`01-init-capi.sh`)
- Sử dụng `clusterctl init` để cài đặt vào cụm K3s:
  - **Core CAPI**: `cluster-api`
  - **Infrastructure Provider**: `proxmox` (CAPMOX)
  - **Bootstrap Provider**: `talos` (CABPT)
  - **Control Plane Provider**: `talos` (CACCPT)
  - **IPAM Provider**: `in-cluster`

#### 3. Thiết lập SOPS & Flux Operator (`02-setup-sops-age.sh` & `03-install-flux-operator.sh`)
- Sinh khóa Age, tạo Kubernetes Secret `sops-age` trên K3s.
- Cài đặt Helm chart ControlPlane Flux Operator (v0.60.0).
- Apply `gitops/flux-system/flux-instance.yaml` để kích hoạt Flux controllers trên K3s.

---

### 🔹 Tầng 3: GitOps Workload Clusters (Talos)

- Flux Kustomization (`sync-workloads.yaml`) tự động quét thư mục `gitops/workloads/` và apply các tài nguyên CAPI:
  - `ProxmoxCluster` & `Cluster`
  - `TalosControlPlane` & `TalosConfigTemplate`
  - `MachineDeployment` & `ProxmoxMachineTemplate`
  - `InClusterIPPool`
- CAPI controllers trên K3s Management Cluster sẽ gọi Proxmox API để clone/tạo các VM Talos Linux, inject Talos Machine Config, bootstrap etcd và khởi chạy Flannel CNI cho cụm Workload hoàn toàn tự động.

---

## 🚀 6. Checklist Các Bước Triển Khai Thực Tế

- [ ] **Bước 1:** Cập nhật các file Terraform (`terraform/image.tf`, `terraform/cloud_init.tf`, `terraform/vm.tf`, `terraform/variables.tf`, `terraform/outputs.tf`).
- [ ] **Bước 2:** Chạy `terraform apply` để tạo máy ảo K3s Management trên Proxmox.
- [ ] **Bước 3:** Chạy script `bootstrap/00-get-kubeconfig.sh` để tải file `kubeconfig`.
- [ ] **Bước 4:** Chạy `bootstrap/01-init-capi.sh` để khởi tạo CAPI trên K3s.
- [ ] **Bước 5:** Chạy `bootstrap/02-setup-sops-age.sh` và `bootstrap/03-install-flux-operator.sh` để khởi động GitOps.
- [ ] **Bước 6:** Push mã nguồn lên Git và kiểm tra Flux tự động tạo cụm Talos Workload Cluster trên Proxmox.
