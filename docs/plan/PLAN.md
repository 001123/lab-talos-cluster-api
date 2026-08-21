# Mục tiêu dự án

Tạo 1 cụm talos single node để làm cluster management mục đích để tạo cụm cluster talos thông qua proxmox với cluster api.

Ý tưởng từ bài viết: https://a-cup-of.coffee/blog/talos-capi-proxmox/ nhưng tôi muốn tự thực hành và custom riêng.

## Các bước thực hiện:

Sử dụng terraform để tạo và quản lý cluster management trên proxmox.

Provider proxmox dùng https://registry.terraform.io/providers/bpg/proxmox/0.111.1 
Provider talos dùng https://registry.terraform.io/providers/siderolabs/talos/0.11.0

## Tổ chức thư mục

Tổ chức thư mục hợp lý dễ bảo trì vào triển khai gitOps về sau

