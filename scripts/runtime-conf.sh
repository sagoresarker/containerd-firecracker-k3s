#!/bin/bash
set -e

# Create necessary directories
mkdir -p /var/lib/firecracker-containerd/runtime
mkdir -p /var/log/firecracker-containerd

# Create logs and metrics pipes
mkfifo /var/log/firecracker-containerd/log.fifo || true
mkfifo /var/log/firecracker-containerd/metrics.fifo || true

# Create the firecracker runtime config with proper structure
cat << EOF > /etc/containerd/firecracker-runtime.json
{
    "boot-source": {
        "kernel_image_path": "/var/lib/firecracker-containerd/kernel/vmlinux",
        "boot_args": "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw root=/dev/vda1"
    },
    "drives": [
        {
            "drive_id": "rootfs",
            "path_on_host": "/var/lib/firecracker/rootfs/rootfs.ext4",
            "is_root_device": true,
            "is_read_only": false,
            "partuuid": null
        }
    ],
    "machine-config": {
        "vcpu_count": 2,
        "mem_size_mib": 2048,
        "cpu_template": "T2"
    },
    "network-interfaces": [
        {
            "iface_id": "eth0",
            "guest_mac": "AA:FC:00:00:00:01",
            "host_dev_name": "tap0"
        }
    ],
    "firecracker_binary_path": "/usr/local/bin/firecracker",
    "log_fifo": "/var/log/firecracker-containerd/log.fifo",
    "metrics_fifo": "/var/log/firecracker-containerd/metrics.fifo",
    "log_level": "Debug",
    "jailer": {
        "runc_binary_path": "/usr/local/bin/runc",
        "uid": 0,
        "gid": 0
    }
}
EOF

# Create a default containerd runtime configuration
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

  [plugins."io.containerd.firecracker.v1"]
    kernel_image_path = "/var/lib/firecracker-containerd/kernel/vmlinux"
    kernel_args = "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw"
    snapshot_mode = "devmapper"
    cpu_template = "T2"
    log_level = "Debug"

[debug]
  level = "debug"
EOF

# Set proper permissions
chmod 644 /etc/containerd/firecracker-runtime.json
chmod 644 /etc/containerd/config.toml

# Verify files exist
echo "Verifying required files..."
for file in \
    "/usr/local/bin/firecracker" \
    "/var/lib/firecracker-containerd/kernel/vmlinux" \
    "/var/lib/firecracker/rootfs/rootfs.ext4"
do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file missing!"
    fi
done

echo "Configuration complete. Try running:"
echo "sudo firecracker --api-sock /tmp/firecracker.socket --config-file /etc/containerd/firecracker-runtime.json"

# Start logging in background
echo "Starting log collection..."
cat /var/log/firecracker-containerd/log.fifo > /var/log/firecracker-containerd/runtime.log &
cat /var/log/firecracker-containerd/metrics.fifo > /var/log/firecracker-containerd/metrics.log &