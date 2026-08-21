# Talos Management Cluster trên Proxmox với Cluster API & Flux Operator GitOps

Dự án tự động hóa triển khai hạ tầng Kubernetes từ tầng Bare-Metal/Virtualization (Proxmox VE), khởi tạo **Talos Single-Node Management Cluster**, cài đặt **Cluster API (CAPI)** và vận hành GitOps an toàn thông qua **ControlPlane Flux Operator** (v0.58.1) kết hợp **Mozilla SOPS + Age**.

---

## 🏗️ Kiến trúc Tổng quan (Architecture)

```
                                  +----------------------------------------------+
                                  |                Proxmox VE                    |
                                  |                                              |
                                  |  +----------------------------------------+  |
                                  |  |   Talos Management Cluster (Node 800)  |  |
                                  |  |   - Talos OS v1.13.8 (QEMU Agent)      |  |
                                  |  |   - K8s v1.36.3 Control Plane          |  |
                                  |  |   - Core CAPI Controllers              |  |
                                  |  |   - CAPMOX (Proxmox Provider)          |  |
                                  |  |   - CABPT & CACCPT (Talos Providers)   |  |
                                  |  |   - In-Cluster IPAM Provider           |  |
                                  |  |   - Flux Operator (v0.58.1) + SOPS     |  |
                                  |  +-------------------+--------------------+  |
                                  +----------------------|-----------------------+
                                                         |
                                    [CAPI + CAPMOX Reconcile & Provision]
                                                         |
                                                         v
                                  +----------------------------------------------+
                                  |            Workload Cluster (e.g. dev)       |
                                  |  +------------------+  +------------------+  |
                                  |  | Control Plane VM |  |   Worker VMs     |  |
                                  |  | (Talos + Flannel)|  | (Talos + Flannel)|  |
                                  |  +------------------+  +------------------+  |
                                  +----------------------------------------------+
```

---

## 📁 Cấu trúc Thư mục Dự án

```
talos-cluster-api/
├── .gitignore                              # Danh sách bỏ qua credentials, state, keys
├── .sops.yaml                              # Cấu hình mã hóa SOPS cho GitOps manifests
├── README.md                               # Hướng dẫn chi tiết sử dụng và vận hành
│
├── terraform/                              # TẦNG 1: TERRAFORM MANAGEMENT CLUSTER
│   ├── versions.tf                         # Khai báo bpg/proxmox (0.111.1) & siderolabs/talos (0.11.0)
│   ├── variables.tf                        # Định nghĩa biến kết nối PVE, VM specs, Talos
│   ├── terraform.tfvars.example            # File mẫu cấu hình biến
│   ├── main.tf                             # Cấu hình Proxmox & Talos providers
│   ├── image.tf                            # Tự động tải Talos ISO kèm QEMU Guest Agent vào PVE
│   ├── vm.tf                               # Khởi tạo máy ảo trên Proxmox VE
│   ├── talos.tf                            # Sinh secrets, config patch, bootstrap single-node etcd
│   ├── outputs.tf                          # Xuất IP, kubeconfig, talosconfig
│   └── templates/
│       └── controlplane.yaml.tpl           # Template patch cho single-node (allow scheduling, static IP)
│
├── bootstrap/                              # TẦNG 2: BOOTSTRAP CAPI & FLUX OPERATOR
│   ├── clusterctl.yaml.example             # Cấu hình mẫu providers và Proxmox credentials cho CAPI
│   ├── 01-init-capi.sh                     # Script khởi tạo CAPI Core + Proxmox + Talos + IPAM
│   ├── 02-setup-sops-age.sh                # Script sinh Age key, cấu hình .sops.yaml và tạo Secret
│   └── 03-install-flux-operator.sh         # Script cài đặt Flux Operator v0.58.1 và apply FluxInstance
│
└── gitops/                                 # TẦNG 3: GITOPS WORKLOAD CLUSTERS & ADDONS
    ├── flux-system/
    │   ├── kustomization.yaml
    │   └── flux-instance.yaml              # FluxInstance CRD (ControlPlane Flux Operator)
    ├── clusters/
    │   └── management/
    │       ├── kustomization.yaml
    │       ├── git-repo.yaml               # GitRepository trỏ về kho Git
    │       └── sync-workloads.yaml         # Kustomization đồng bộ thư mục workloads kèm giải mã SOPS
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

## 🛠️ Yêu cầu Chuẩn bị (Prerequisites)

### 1. Công cụ Quản trị trên Máy trạm (Workstation CLI)
Cài đặt các CLI cần thiết qua Homebrew trên macOS:
```bash
brew install terraform talosctl kubectl helm clusterctl age sops fluxcd/tap/flux
```

### 2. Proxmox VE API Token
Tạo API Token trên Proxmox VE với quyền `PVEVMAdmin` hoặc Administrator:
- User: `root@pam` (hoặc tạo user riêng `talos@pve`)
- Token ID: `talos`
- Ghi lại **Secret Value** (UUID) để điền vào `terraform.tfvars`.

---

## 🚀 Hướng dẫn Triển khai Từng Bước

### Bước 1: Khởi tạo Management Cluster qua Terraform

1. Di chuyển vào thư mục `terraform/` và sao chép cấu hình mẫu:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Chỉnh sửa `terraform.tfvars` với thông số môi trường của bạn (IP Proxmox, API token, Node name, Datastore, IP tĩnh cho node):
   ```hcl
   proxmox_endpoint  = "https://192.168.1.10:8006/"
   proxmox_api_token = "root@pam!talos=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   proxmox_node_name = "pve"
   proxmox_iso_datastore_id  = "local"
   proxmox_disk_datastore_id = "local-lvm"

   node_ip      = "192.168.1.50"
   gateway_ip   = "192.168.1.1"
   nameservers  = ["1.1.1.1", "8.8.8.8"]
   ```

3. Thực thi Terraform:
   ```bash
   terraform init
   terraform apply
   ```

4. Sau khi hoàn tất, 2 file cấu hình sẽ được tạo tại thư mục gốc:
   - `kubeconfig`: File kết nối `kubectl` tới cụm.
   - `talosconfig`: File cấu hình `talosctl` quản trị hệ điều hành node.

5. Kiểm tra trạng thái cụm:
   ```bash
   export KUBECONFIG="$(pwd)/../kubeconfig"
   kubectl get nodes -o wide
   ```

---

### Bước 2: Khởi tạo Cluster API (CAPI)

Chạy script tự động khởi tạo CAPI Core và các provider liên quan:
```bash
cd ..
./bootstrap/01-init-capi.sh
```

Script sẽ tự động:
- Kiểm tra kết nối tới cụm Management.
- Thực thi `clusterctl init` với các providers:
  - `--infrastructure proxmox` (CAPMOX)
  - `--control-plane talos` (CACCPT)
  - `--bootstrap talos` (CABPT)
  - `--ipam in-cluster` (In-Cluster IPAM)
- Chờ các controller pods sẵn sàng trong namespace `capi-system`, `capmox-system`, `cabpt-system`, `cacppt-system`.

---

### Bước 3: Cấu hình Mã hóa Bí mật với Mozilla SOPS & Age

Chạy script tạo khóa bí mật Age và áp dụng vào cụm:
```bash
./bootstrap/02-setup-sops-age.sh
```

Script sẽ:
1. Sinh file khóa `age.agekey` tại thư mục gốc (nếu chưa có).
2. Tạo Secret `sops-age` trong namespace `flux-system`.
3. Tự động cập nhật Public Key vào `.sops.yaml`.

> [!TIP]
> **Cách mã hóa Secret bằng SOPS**:
> ```bash
> sops --encrypt --in-place gitops/workloads/dev-cluster/my-secret.sops.yaml
> ```

---

### Bước 4: Cài đặt ControlPlane Flux Operator v0.58.1

Chạy script triển khai Flux Operator:
```bash
./bootstrap/03-install-flux-operator.sh
```

Sau khi hoàn tất:
- Flux Operator v0.58.1 được cài đặt qua Helm OCI.
- `FluxInstance` được kích hoạt để bắt đầu đồng bộ cấu hình từ Git.
- Bạn có thể xem trang trạng thái giao diện web (Flux Status Page):
  ```bash
  kubectl -n flux-system port-forward svc/flux-operator 9080:9080
  # Mở trình duyệt tại http://localhost:9080
  ```

---

## 🔄 Vận hành Cụm Workload qua GitOps

### 1. Cấu hình Git Repository của bạn
Chỉnh sửa URL Git repository trong:
- `gitops/flux-system/flux-instance.yaml`
- `gitops/clusters/management/git-repo.yaml`

Cập nhật URL kho Git thực tế của bạn (ví dụ: `https://github.com/your-username/talos-cluster-api.git`).

### 2. Tạo hoặc Mở rộng Cụm Workload
Để tạo thêm cụm hoặc thay đổi số lượng Worker:
1. Tạo thư mục mới trong `gitops/workloads/` (ví dụ `gitops/workloads/prod-cluster/`) dựa trên `gitops/workloads/dev-cluster/`.
2. Thay đổi số `replicas` hoặc dải IP trong `patches/cluster-patch.yaml`.
3. Commit và Push lên Git:
   ```bash
   git add gitops/workloads/
   git commit -m "feat: deploy dev-cluster via GitOps"
   git push origin main
   ```
4. Flux Operator và CAPI sẽ tự động phát hiện thay đổi, tương tác với Proxmox API để tạo máy ảo, bootstrap Talos OS và tạo cụm Kubernetes hoàn chỉnh.

---

## 🔒 Quản lý Secrets và Bảo mật

- **Không bao giờ commit file `age.agekey`, `kubeconfig`, `talosconfig` hay `terraform.tfstate` lên Git** (đã được bảo vệ trong `.gitignore`).
- Mọi Kubernetes Secret cần commit lên Git phải được đặt tên `*.sops.yaml` và mã hóa bằng lệnh `sops -e -i <file>`.
- Flux Kustomization controller sẽ tự động dùng private key trong secret `sops-age` để giải mã khi apply vào cụm.
