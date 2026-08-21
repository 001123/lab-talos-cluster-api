# Talos Management Cluster trên Proxmox với Cluster API & Flux Operator GitOps

Dự án tự động hóa triển khai hạ tầng Kubernetes từ tầng Bare-Metal/Virtualization (Proxmox VE), khởi tạo **Talos Single-Node Management Cluster**, cài đặt **Cluster API (CAPI)** với Proxmox Provider (CAPMOX v1alpha2) và vận hành GitOps an toàn thông qua **ControlPlane Flux Operator** (v0.58.1) kết hợp **Mozilla SOPS + Age**.

---

## 🏗️ Kiến trúc Tổng quan (Architecture)

```
                                  +----------------------------------------------------+
                                  |                    Proxmox VE                      |
                                  |                                                    |
                                  |  +----------------------------------------------+  |
                                  |  |     Talos Management Cluster (Node 800)      |  |
                                  |  |     - Talos OS v1.13.8/v1.13.9 (QEMU Agent)  |  |
                                  |  |     - K8s v1.36.3 Control Plane              |  |
                                  |  |     - Core CAPI Controllers (v1beta1)        |  |
                                  |  |     - CAPMOX (Proxmox Provider v1alpha2)     |  |
                                  |  |     - CABPT & CACCPT (Talos v1alpha3)        |  |
                                  |  |     - In-Cluster IPAM Provider (v1alpha2)    |  |
                                  |  |     - Flux Operator (v0.58.1) + SOPS (Age)   |  |
                                  |  +----------------------+-----------------------+  |
                                  |                         |                          |
                                  |  +----------------------v-----------------------+  |
                                  |  |  Talos Base VM Template (ID 9000, Tag: talos)|  |
                                  |  |  - UEFI (OVMF) + Q35 + EFI Disk + QEMU Agent |  |
                                  |  +----------------------+-----------------------+  |
                                  +-------------------------|--------------------------+
                                                            |
                                            [CAPI + CAPMOX Reconcile & Clone]
                                                            |
                                                            v
                                  +----------------------------------------------------+
                                  |             Workload Cluster (e.g. dev)            |
                                  |  +-----------------------+  +-------------------+  |
                                  |  |  Control Plane VM(s)  |  |    Worker VMs     |  |
                                  |  |  - Talos OS v1.13.9   |  |  - Talos v1.13.9  |  |
                                  |  |  - Static VIP (eth0)  |  |  - Flannel CNI    |  |
                                  |  |  - Flannel CNI        |  |  - Talos CCM      |  |
                                  |  +-----------------------+  +-------------------+  |
                                  +----------------------------------------------------+
```

---

## 📁 Cấu trúc Thư mục Dự án

```
talos-cluster-api/
├── .gitignore                              # Danh sách bỏ qua credentials, state, keys, kubeconfig
├── .sops.yaml                              # Cấu hình mã hóa SOPS cho GitOps manifests
├── LICENSE                                 # Giấy phép mã nguồn mở MIT
├── README.md                               # Hướng dẫn chi tiết sử dụng và vận hành
│
├── docs/                                   # Tài liệu quy hoạch & kế hoạch kiến trúc
│   └── plan/
│       ├── PLAN.md                         # Quy hoạch tổng thể hạ tầng
│       ├── PLAN-FLUXCD.md                  # Thiết kế chi tiết luồng FluxCD & GitOps
│       └── PLAN-K3S.MD                     # So sánh & phương án kiến trúc K3s/Talos
│
├── terraform/                              # TẦNG 1: TERRAFORM MANAGEMENT CLUSTER
│   ├── versions.tf                         # Khai báo bpg/proxmox (0.111.1) & siderolabs/talos (0.11.0)
│   ├── variables.tf                        # Định nghĩa biến kết nối PVE, VM specs, Talos
│   ├── terraform.tfvars.example            # File mẫu cấu hình biến
│   ├── main.tf                             # Cấu hình Proxmox & Talos providers
│   ├── image.tf                            # Tự động tải Talos ISO kèm QEMU Guest Agent vào PVE
│   ├── vm.tf                               # Khởi tạo máy ảo Management Node trên Proxmox VE
│   ├── talos.tf                            # Sinh secrets, config patch, bootstrap single-node etcd
│   ├── outputs.tf                          # Xuất IP, kubeconfig, talosconfig
│   └── templates/
│       └── controlplane.yaml.tpl           # Template patch cho single-node (allow scheduling, static IP)
│
├── bootstrap/                              # TẦNG 2: BOOTSTRAP TEMPLATES, CAPI & FLUX OPERATOR
│   ├── 00-create-talos-template.sh         # [Option A] Tạo Talos VM Template trên PVE qua REST API
│   ├── create-talos-template-pve.sh        # [Option B] Tạo Talos VM Template chạy trực tiếp trên PVE Shell
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
    │       ├── cluster.yaml                # Cluster resource (v1beta1)
    │       ├── proxmox-cluster.yaml        # ProxmoxCluster (CAPMOX v1alpha2)
    │       ├── control-plane.yaml          # TalosControlPlane & CP Machine Template
    │       ├── worker-deployment.yaml      # MachineDeployment & Worker Machine Template
    │       └── ipam-pool.yaml              # InClusterIPPool quản lý IP tĩnh cho node
    └── workloads/
        ├── dev-cluster/                    # Cụm workload dev mẫu (1 Control Plane + 2 Workers)
        │   ├── kustomization.yaml
        │   └── patches/
        │       └── cluster-patch.yaml      # Patch VIP eth0, dải IPAM pool và số node
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
- Ghi lại **Secret Value** (UUID) để điền vào `terraform.tfvars` và `bootstrap/clusterctl.yaml`.

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

4. Sau khi hoàn tất, 2 file cấu hình sẽ được xuất ra:
   - `kubeconfig`: File kết nối `kubectl` tới cụm Management.
   - `talosconfig`: File cấu hình `talosctl` quản trị node OS.

5. Kiểm tra trạng thái cụm Management:
   ```bash
   export KUBECONFIG="$(pwd)/../kubeconfig"
   kubectl get nodes -o wide
   ```

---

### Bước 2: Chuẩn bị Talos VM Template trên Proxmox VE

Cluster API Provider Proxmox (**CAPMOX**) yêu cầu một VM Template mẫu gắn tag `talos` trên Proxmox để thực hiện nhân bản (Full Clone) khi tạo các node Workload. Bạn có thể chọn 1 trong 2 cách sau:

#### Cách A: Tạo Template từ xa qua REST API (Chạy trên máy trạm)
Script sẽ tự động đọc token từ `terraform.tfvars` hoặc `bootstrap/clusterctl.yaml`, tìm file Talos ISO đã tải và tạo VM Template (ID: 9000):
```bash
cd ..
./bootstrap/00-create-talos-template.sh
```

#### Cách B: Tạo Template chuẩn từ Talos Image Factory (Khuyến nghị - Chạy trực tiếp trên Proxmox Host)
Copy file `bootstrap/create-talos-template-pve.sh` lên Proxmox host qua SSH hoặc chạy trong Web Shell của Proxmox:
```bash
# Trên Proxmox VE Host:
bash /path/to/create-talos-template-pve.sh
```
*Script này sẽ tải disk image `nocloud-amd64` v1.13.9 kèm extension `siderolabs/qemu-guest-agent`, cấu hình OVMF UEFI BIOS, Q35 machine type, gắn EFI disk và chuyển đổi thành VM Template `9000` với tag `talos`.*

---

### Bước 3: Khởi tạo Cluster API (CAPI)

1. Cấu hình thông tin kết nối Proxmox cho CAPI bằng cách sao chép file mẫu:
   ```bash
   cp bootstrap/clusterctl.yaml.example bootstrap/clusterctl.yaml
   # Điền PROXMOX_URL, PROXMOX_TOKEN, PROXMOX_SECRET
   ```

2. Chạy script khởi tạo CAPI Core và các Provider:
   ```bash
   ./bootstrap/01-init-capi.sh
   ```

Script sẽ tự động:
- Kiểm tra kết nối tới cụm Management.
- Khởi tạo `clusterctl init` với:
  - `--infrastructure proxmox` (CAPMOX v1alpha2)
  - `--control-plane talos` (CACCPT v1alpha3)
  - `--bootstrap talos` (CABPT v1alpha3)
  - `--ipam in-cluster` (In-Cluster IPAM v1alpha2)
- Chờ các controller pods sẵn sàng trong namespace `capi-system`, `capmox-system`, `cabpt-system`, `cacppt-system`, `capi-in-cluster-ipam-system`.

---

### Bước 4: Cấu hình Mã hóa Bí mật với Mozilla SOPS & Age

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

### Bước 5: Cài đặt ControlPlane Flux Operator v0.58.1

Chạy script triển khai Flux Operator:
```bash
./bootstrap/03-install-flux-operator.sh
```

Sau khi hoàn tất:
- Flux Operator v0.58.1 được cài đặt qua Helm OCI.
- Resource `FluxInstance` được kích hoạt để bắt đầu quản lý vòng đời GitOps.
- Bật Dashboard giao diện web của Flux Operator (Flux Status Page):
  ```bash
  kubectl -n flux-system port-forward svc/flux-operator 9080:9080
  # Mở trình duyệt tại: http://localhost:9080
  ```

---

## 🔄 Vận hành Cụm Workload qua GitOps

### 1. Cấu hình Git Repository của bạn
Chỉnh sửa URL Git repository trong:
- `gitops/flux-system/flux-instance.yaml`
- `gitops/clusters/management/git-repo.yaml`

Cập nhật URL kho Git thực tế của bạn (ví dụ: `https://github.com/your-username/talos-cluster-api.git`).

### 2. Triển khai Cụm Workload Mẫu (`dev-cluster`)
Cụm `dev-cluster` đã được định nghĩa sẵn trong `gitops/workloads/dev-cluster/`:
- **1 Control Plane Node**: Cấu hình Static Virtual IP `192.168.100.160` trên card mạng `eth0` qua Talos strategic merge patch.
- **2 Worker Nodes**: Quản lý bằng `MachineDeployment`.
- **IPAM Pool**: Cấp phát IP tự động trong dải `192.168.100.161-192.168.100.175`.

Đẩy cấu hình lên Git để Flux đồng bộ:
```bash
git add gitops/
git commit -m "feat: sync dev-cluster via GitOps"
git push origin main
```

### 3. Kiểm tra Trạng thái Cụm Workload
Theo dõi quá trình CAPI và CAPMOX tự động tạo máy ảo trên Proxmox:
```bash
# Kiểm tra tài nguyên CAPI
kubectl get clusters
kubectl get proxmoxclusters
kubectl get machines
kubectl get taloscontrolplanes
kubectl get machinedeployments

# Xem log đồng bộ Flux GitOps
flux get kustomizations
flux get sources git
```

### 4. Lấy Kubeconfig và Quản trị Cụm Workload
Sau khi cụm chuyển sang trạng thái `Provisioned` và Control Plane sẵn sàng:
```bash
# Lấy file Kubeconfig của Workload cluster
clusterctl get kubeconfig dev-talos-cluster-template > dev-cluster.kubeconfig

# Kiểm tra các node trong cụm workload
kubectl --kubeconfig=dev-cluster.kubeconfig get nodes -o wide

# Kiểm tra pods hệ thống (Flannel CNI, Talos CCM, CoreDNS)
kubectl --kubeconfig=dev-cluster.kubeconfig get pods -A
```

---

## 📊 Bảng Lệnh Tiện ích (Cheat Sheet)

| Mục đích | Lệnh thực thi |
| :--- | :--- |
| **Kiểm tra Node Management** | `kubectl get nodes -o wide` |
| **Quản trị OS qua Talos** | `talosctl --talosconfig=talosconfig -n <NODE_IP> dashboard` |
| **Xem trạng thái CAPI Clusters** | `kubectl get cluster,machinedeployment,machine` |
| **Lấy Kubeconfig Workload** | `clusterctl get kubeconfig <cluster-name> > <cluster-name>.kubeconfig` |
| **Xem Kustomization Flux** | `flux get kustomizations` |
| **Mở Flux UI Dashboard** | `kubectl -n flux-system port-forward svc/flux-operator 9080:9080` |
| **Mã hóa file bí mật SOPS** | `sops --encrypt --in-place <file.sops.yaml>` |
| **Giải mã kiểm tra file SOPS** | `sops --decrypt <file.sops.yaml>` |

---

## 🔒 Quản lý Secrets và Bảo mật

- **Tuyệt đối không commit các file nhạy cảm lên Git**: `age.agekey`, `kubeconfig`, `talosconfig`, `*.kubeconfig`, `terraform.tfstate` (đã được cấu hình trong `.gitignore`).
- Mọi Kubernetes Secret cần lưu trên Git phải được đặt tên theo mẫu `*.sops.yaml` và mã hóa bằng lệnh `sops -e -i <file>`.
- Flux Kustomization controller sẽ tự động dùng private key trong secret `sops-age` để giải mã khi đồng bộ vào cụm.

