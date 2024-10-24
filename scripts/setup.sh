#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Install dependencies
apt-get update
apt-get install -y \
    containerd \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Install firecracker-containerd
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y firecracker-containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Add Firecracker runtime to containerd config
cat << EOF >> /etc/containerd/config.toml

[plugins."io.containerd.runtime.v1.linux"]
  runtime_type = "io.containerd.runtime.v1.linux"
  runtime_engine = ""
  runtime_root = ""

[plugins."io.containerd.runtime.v2.task"]
  platforms = ["linux/amd64"]

[plugins."io.containerd.runtime.v2.runsc"]
  runtime_type = "io.containerd.runsc.v1"

[plugins."aws.firecracker"]
  kernel_image_path = "/var/lib/firecracker-containerd/kernel/vmlinux"
  kernel_args = "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw"
  snapshot_mode = "Snapshot"
EOF

# Restart containerd
systemctl restart containerd

# Setup networking (CNI)
mkdir -p /etc/cni/net.d
cat << EOF > /etc/cni/net.d/firecracker.conflist
{
  "cniVersion": "0.4.0",
  "name": "firecracker",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "fcbridge0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "ranges": [
          [{
            "subnet": "172.20.0.0/24",
            "gateway": "172.20.0.1"
          }]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    }
  ]
}
EOF

# Create directories for VM resources
mkdir -p /var/lib/firecracker-containerd/kernel
mkdir -p /var/lib/firecracker-containerd/rootfs

echo "Setup completed successfully!"