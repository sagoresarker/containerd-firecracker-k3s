#!/bin/bash
set -e

echo "Cleaning up existing devmapper setup..."
dmsetup remove_all || true
losetup -D

echo "Creating devmapper files..."
mkdir -p /var/lib/containerd/devmapper
rm -f /var/lib/containerd/devmapper/data
rm -f /var/lib/containerd/devmapper/meta

# Create data and meta files
truncate -s 100G /var/lib/containerd/devmapper/data
truncate -s 2G /var/lib/containerd/devmapper/meta

echo "Setting up loop devices..."
DATA_LOOP=$(losetup --find --show /var/lib/containerd/devmapper/data)
META_LOOP=$(losetup --find --show /var/lib/containerd/devmapper/meta)
echo "Using loop devices: ${DATA_LOOP} and ${META_LOOP}"

# Initialize metadata device
echo "Initializing metadata device..."
dd if=/dev/zero of=${META_LOOP} bs=4096 count=1 > /dev/null 2>&1

# # Create thin-pool
# echo "Creating thin-pool..."
# dmsetup create fc-dev-thinpool \
#     --table "0 20971520 thin-pool ${DATA_LOOP} ${META_LOOP} 512 8192 1 skip_block_zeroing"

# Wait for device to be ready
sleep 2

echo "Verifying setup..."
echo "Loop devices:"
losetup -l
echo "Devmapper status:"
dmsetup ls
echo "Thin-pool status:"
dmsetup status fc-dev-thinpool

# Rest of your script remains the same...
# Create containerd config
mkdir -p /etc/containerd
cat << EOF > /etc/containerd/config.toml
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    disable_tcp_service = true
    stream_server_address = "127.0.0.1"
    stream_server_port = "0"
    enable_selinux = false
    sandbox_image = "k8s.gcr.io/pause:3.1"
    stats_collect_period = 10
    enable_tls_streaming = false
    max_container_log_line_size = 16384

  [plugins."io.containerd.runtime.v1.linux"]
    shim_debug = true

  [plugins."io.containerd.runtime.v2.task"]
    platforms = ["linux/amd64"]

  [plugins."io.containerd.snapshotter.v1.devmapper"]
    root_path = "/var/lib/containerd/devmapper"
    pool_name = "fc-dev-thinpool"
    base_image_size = "10GB"

  [plugins."io.containerd.runtime.v2.aws-firecracker"]
    kernel_image_path = "/var/lib/firecracker-containerd/kernel/vmlinux"
    kernel_args = "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw"
    snapshot_mode = "devmapper"
    cpu_template = "T2"
    log_level = "Debug"
    shim_debug = true
    debug = true

[debug]
  level = "debug"
EOF

# Setup networking
ip link add fcbridge0 type bridge 2>/dev/null || true
ip addr add 172.20.0.1/24 dev fcbridge0 2>/dev/null || true
ip link set fcbridge0 up

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Setup NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -i fcbridge0 -o eth0 -j ACCEPT 2>/dev/null || true

# Make IP forwarding persistent
cat << EOF > /etc/sysctl.d/99-firecracker.conf
net.ipv4.ip_forward = 1
EOF

sysctl -p /etc/sysctl.d/99-firecracker.conf

# Restart containerd
systemctl restart containerd

echo "Setup complete! Checking containerd status..."
systemctl status containerd --no-pager

echo "Checking devmapper status..."
dmsetup status fc-dev-thinpool
