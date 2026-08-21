# Kế hoạch Triển khai: Talos Management Cluster trên Proxmox với Cluster API & Flux Operator GitOps

## 1. Mục tiêu và Kiến trúc Tổng quan (Architecture & Objectives)

Xây dựng hệ thống quản trị Kubernetes hoàn chỉnh từ tầng hạ tầng vật lý (IaaS) đến tầng điều phối cụm (CAPI Management Cluster) và tự động hóa vận hành GitOps:

1. **Tầng Hạ tầng (Infra - Terraform)**:
   - Dùng Terraform tự động tạo 1 VM trên Proxmox VE và bootstrap cụm **Talos Single-Node** đóng vai trò **Management Cluster**.
   - Provider Proxmox: [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/0.111.1) (`0.111.1`).
   - Provider Talos: [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/0.11.0) (`0.11.0`).
   - Tự động tải Talos OS image (kèm QEMU Guest Agent schematic) trực tiếp vào Proxmox storage bằng `proxmox_virtual_environment_file`.
   - Cấu hình Static IP trực tiếp qua Talos machine configuration patch.
   - Bật `cluster.allowSchedulingOnControlPlanes: true` để chạy workloads/controllers trên node đơn lẻ.
   - Xuất file `talosconfig` và `kubeconfig`.

2. **Tầng Khởi tạo (Bootstrap - CAPI & Flux Operator)**:
   - Khởi tạo **Cluster API (CAPI)** với 4 provider chính:
     - **Core Provider**: Cluster API Controller.
     - **Infrastructure Provider**: Proxmox (`capmox` - IONOS Cloud).
     - **Bootstrap Provider**: Talos (`cabpt` - Siderolabs).
     - **Control Plane Provider**: Talos (`cacppt` - Siderolabs).
     - **IPAM Provider**: In-Cluster IPAM (`capi-ipam-in-cluster`).
   - Cấu hình Kubernetes Secret chứa Proxmox API Token để CAPI giao tiếp với Proxmox VE.
   - Cài đặt **Flux Operator** ([`controlplaneio-fluxcd/flux-operator`](https://github.com/controlplaneio-fluxcd/flux-operator/releases/tag/v0.58.1) v0.58.1).
   - Thiết lập **Mozilla SOPS + Age** để mã hóa / giải mã secrets an toàn trực tiếp trong kho Git.

3. **Tầng Vận hành Khai báo (GitOps - Workload Clusters & Add-ons)**:
   - Sử dụng `FluxInstance` CRD (quản lý bởi Flux Operator) để đồng bộ repository Git.
   - Khai báo mẫu CAPI Cluster Template (gồm `Cluster`, `ProxmoxCluster`, `TalosControlPlane`, `ProxmoxMachineTemplate`, `MachineDeployment`, `InClusterIPPool`).
   - Quản lý các cụm Workload hoàn toàn qua GitOps (Commit -> Pull Request -> Merge -> CAPI tự động sinh VM trên Proxmox & bootstrap Talos).
   - Cài đặt sẵn các Add-ons cốt lõi: **Flannel CNI** và **Talos Cloud Controller Manager (CCM)**.

---

## 2. Cấu trúc Thư mục Dự án (Repository Layout)

```
talos-cluster-api/
├── PLAN.md                                 # Mục tiêu ban đầu
├── PLAN-FLUXCD.md                          # Kế hoạch chi tiết kiến trúc & GitOps
├── README.md                               # Hướng dẫn sử dụng tổng thể
├── .gitignore                              # Bỏ qua tfstate, secrets, age keys
├── .sops.yaml                              # Cấu hình mã hóa SOPS cho GitOps manifests
│
├── terraform/                              # TẦNG 1: TERRAFORM MANAGEMENT CLUSTER
│   ├── versions.tf                         # Khai báo bpg/proxmox 0.111.1 & siderolabs/talos 0.11.0
│   ├── variables.tf                        # Biến cấu hình Proxmox, VM specs, IP, versions
│   ├── terraform.tfvars.example            # File mẫu cấu hình biến
│   ├── main.tf                             # Khởi tạo provider & local resources
│   ├── image.tf                            # Tự động tải Talos OS Image vào Proxmox storage
│   ├── talos.tf                            # Sinh secrets, config patch, bootstrap single-node etcd
│   ├── vm.tf                               # Tạo VM QEMU trên Proxmox
│   ├── outputs.tf                          # Xuất kubeconfig, talosconfig và IP cluster
│   └── templates/
│       ├── controlplane.yaml.tpl           # Machine config patch cho Single Node (allow scheduling)
│       └── talos-factory.json              # Schematics cấu hình extension qemu-guest-agent
│
├── bootstrap/                              # TẦNG 2: SCRIPTS BOOTSTRAP CAPI & FLUX-OPERATOR
│   ├── clusterctl.yaml.example             # Cấu hình CAPI providers & Proxmox credentials
│   ├── 01-init-capi.sh                     # Script kiểm tra kết nối và chạy clusterctl init
│   ├── 02-setup-sops-age.sh                # Script sinh key Age và tạo Secret giải mã cho Flux
│   └── 03-install-flux-operator.sh         # Script cài đặt flux-operator v0.58.1 & apply FluxInstance
│
└── gitops/                                 # TẦNG 3: GITOPS WORKLOAD CLUSTERS & ADDONS
    ├── flux-system/
    │   ├── kustomization.yaml
    │   └── flux-instance.yaml              # Khai báo FluxInstance CRD (ControlPlane Flux Operator)
    ├── clusters/
    │   └── management/
    │       ├── kustomization.yaml
    │       ├── git-repo.yaml               # GitRepository trỏ về kho Git
    │       └── sync-workloads.yaml         # Kustomization đồng bộ thư mục workloads
    ├── templates/
    │   └── talos-proxmox-cluster/          # Template CAPI mẫu cho cụm Talos trên Proxmox
    │       ├── cluster.yaml
    │       ├── proxmox-cluster.yaml
    │       ├── control-plane.yaml
    │       ├── worker-deployment.yaml
    │       └── ipam-pool.yaml
    └── workloads/
        ├── dev-cluster/                    # Cụm workload mẫu
        │   ├── kustomization.yaml
        │   ├── cluster.yaml
        │   └── patches/
        └── addons/
            ├── ccm/
            │   └── talos-ccm.yaml          # Talos Cloud Controller Manager
            └── cni/
                └── flannel.yaml            # Flannel CNI configuration
```

---

## 3. Lộ trình Thực hiện Từng Bước (Implementation Roadmap)

### Bước 1: Xây dựng Module Terraform Management Cluster (`terraform/`)
1. **Khai báo Provider**:
   - `bpg/proxmox` (v0.111.1) với xác thực Proxmox API Token (`PVEVMAdmin` role).
   - `siderolabs/talos` (v0.11.0) để tạo machine secrets và client config.
2. **Tự động tải Image**:
   - Dùng `proxmox_virtual_environment_file` tải Talos image từ Talos Factory URL chứa schematic hỗ trợ `qemu-guest-agent`.
3. **Tạo VM Proxmox**:
   - Định nghĩa VM với CPU Type `host`, VirtIO SCSI Controller, Ballooning RAM và Disk lưu trữ trên Proxmox datastore (`local-lvm` / `local-zfs` / `ceph`).
4. **Talos Single Node Bootstrap**:
   - Áp dụng cấu hình `controlplane` kèm patch:
     - `cluster.allowSchedulingOnControlPlanes: true`.
     - Cấu hình IP tĩnh, Subnet, Gateway, DNS.
   - Kích hoạt `talos_machine_bootstrap`.
   - Xuất file `kubeconfig` và `talosconfig` ra thư mục làm việc.

---

### Bước 2: Thiết lập Tự động hóa Bootstrap CAPI (`bootstrap/`)
1. **Cấu hình `clusterctl.yaml`**:
   - Định nghĩa các providers: `infrastructure-proxmox` (CAPMOX), `bootstrap-talos` (CABPT), `control-plane-talos` (CACCPT), `ipam-in-cluster`.
   - Cung cấp biến môi trường `PROXMOX_URL`, `PROXMOX_TOKEN`, `PROXMOX_SECRET`.
2. **Script `01-init-capi.sh`**:
   - Chạy lệnh `clusterctl init` để khởi tạo các CAPI controller pods trên Management Cluster.
   - Tạo Kubernetes Secret `capmox-manager-credentials` chứa thông tin kết nối Proxmox VE.

---

### Bước 3: Thiết lập SOPS/Age & Cài đặt Flux Operator (`bootstrap/` & `gitops/flux-system/`)
1. **Mã hóa Secrets với SOPS/Age (`02-setup-sops-age.sh`)**:
   - Sinh cặp khóa Age (`age-keygen -o age.agekey`).
   - Đẩy Private key thành Secret `sops-age` vào namespace `flux-system`.
   - Cấu hình `.sops.yaml` ở thư mục gốc để các thành viên nhóm có thể mã hóa secrets trước khi git commit.
2. **Cài đặt ControlPlane Flux Operator v0.58.1 (`03-install-flux-operator.sh`)**:
   - Triển khai `flux-operator` v0.58.1 lên cụm.
   - Khởi tạo `FluxInstance` (CRD của Flux Operator) cấu hình đồng bộ từ Git và kích hoạt giải mã SOPS tự động qua secret `sops-age`.

---

### Bước 4: Thiết lập CAPI Workload Templates & Add-ons (`gitops/`)
1. **Template CAPI Proxmox + Talos (`gitops/templates/talos-proxmox-cluster/`)**:
   - `ProxmoxCluster`: Cấu hình IP/FQDN Proxmox và storage datastore cho VM.
   - `InClusterIPPool`: Định nghĩa dải IP tĩnh (Subnet, Gateway, Start/End IP) cho các VM của workload cluster.
   - `TalosControlPlane` & `TalosConfigTemplate`: Cấu hình hệ điều hành Talos cho các Control Plane và Worker nodes.
   - `ProxmoxMachineTemplate`: Quy định số vCPU, dung lượng RAM, Disk Size cho từng node type.
2. **Add-ons cho Workload Clusters (`gitops/workloads/addons/`)**:
   - `flannel.yaml`: Flannel CNI manifest tương thích với Talos.
   - `talos-ccm.yaml`: Talos Cloud Controller Manager quản lý lifecycle và IP cho nodes.

---

### Bước 5: Cụm Workload Đầu Tiên & Quy trình Vận hành GitOps
1. **Tạo cụm `dev-cluster`**:
   - Sử dụng Kustomize overlay kế thừa từ `gitops/templates/talos-proxmox-cluster/`.
   - Tùy biến số lượng replicas (ví dụ: 1 control-plane, 2 workers) và dải IP.
2. **Quy trình Vận hành**:
   - Khi cần tạo cluster mới hoặc scale worker: Chỉ cần chỉnh sửa YAML trong `gitops/workloads/` -> Git push -> Flux Operator reconcile -> CAPI tự động giao tiếp Proxmox tạo VM và cài Talos.

---

## 4. Công cụ & Phiên bản Tiêu chuẩn

| Thành phần | Phiên bản khuyến nghị / Mặc định | Ghi chú |
| :--- | :--- | :--- |
| **Proxmox VE** | 9.x+ | Hypervisor |
| **Terraform Proxmox Provider** | `bpg/proxmox` `0.111.1` | Quản lý VM, Storage, File |
| **Terraform Talos Provider** | `siderolabs/talos` `0.11.0` | Quản lý Secret, Config, Bootstrap |
| **Talos OS** | `v1.13.8` (hoặc tùy biến qua biến) | OS cho Management & Workload |
| **Kubernetes** | `v1.36.3` (hoặc tùy biến qua biến) | K8s Control Plane |
| **Cluster API (CAPI)** | `v1.14.x`| Core CAPI |
| **CAPI Proxmox Provider (CAPMOX)** | `v0.9.0` (IONOS) | Proxmox Infrastructure Provider |
| **CAPI Talos Providers** | CABPT `v0.6.12`, CACCPT `v0.5.13` | Talos Bootstrap & Control Plane |
| **Flux Operator** | `v0.58.1` (ControlPlane) | GitOps Operator |
| **Secret Encryption** | Mozilla SOPS + Age | Mã hóa Secret an toàn trong Git |
