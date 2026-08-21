cluster:
  allowSchedulingOnControlPlanes: ${allow_scheduling}

machine:
  install:
    disk: "/dev/sda"
    image: "${installer_image}"
  network:
    interfaces:
      - interface: eth0
        addresses:
          - "${node_ip}/${node_ip_cidr}"
        routes:
          - network: 0.0.0.0/0
            gateway: "${gateway_ip}"
    nameservers:
%{ for ns in nameservers ~}
      - "${ns}"
%{ endfor ~}
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:admin
      allowedKubernetesNamespaces:
        - kube-system
