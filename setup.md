# Firecracker Containerd Setup Guide

## Prerequisites

```bash
apt-get update
apt-get install -y \
    containerd \
    debootstrap \
    wget \
    curl \
    make \
    git \
    golang-go
```

## Directory Structure
```bash
mkdir -p /usr/local/bin
mkdir -p /var/lib/firecracker-containerd/kernel
mkdir -p /var/lib/firecracker/rootfs
mkdir -p /var/log/firecracker-containerd
mkdir -p /etc/containerd
```

## Setup Steps

### 1. Create Setup Script

Save this as `setup-firecracker.sh`:

```bash
#!/bin/bash
set -e

# Download Firecracker binary
echo "Downloading Firecracker binary..."
ARCH="$(uname -m)"
release_url="https://github.com/firecracker-microvm/firecracker/releases"
latest=$(basename $(curl -fsSLI -o /dev/null -w  %{url_effective} ${release_url}/latest))
curl -L ${release_url}/download/${latest}/firecracker-${latest}-${ARCH}.tgz | tar -xz
mv release-${latest}-$(uname -m)/firecracker-${latest}-${ARCH} /usr/local/bin/firecracker
chmod +x /usr/local/bin/firecracker

# Download kernel
echo "Downloading kernel..."
wget https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin \
    -O /var/lib/firecracker-containerd/kernel/vmlinux

# Create root filesystem
echo "Creating root filesystem..."
if [ ! -f "/var/lib/firecracker/rootfs/rootfs.ext4" ]; then
    TMPDIR=$(mktemp -d)

    # Create minimal Debian root filesystem
    debootstrap --variant=minbase \
        --include="systemd,systemd-sysv,procps,netplan.io,iproute2,iptables,net-tools,openssh-server" \
        bullseye "$TMPDIR"

    # Create and format filesystem
    truncate -s 5G /var/lib/firecracker/rootfs/rootfs.ext4
    mkfs.ext4 /var/lib/firecracker/rootfs/rootfs.ext4

    # Mount and populate
    mkdir -p /mnt/rootfs
    mount /var/lib/firecracker/rootfs/rootfs.ext4 /mnt/rootfs
    cp -a "$TMPDIR"/* /mnt/rootfs/

    # Configure root password and SSH
    chroot /mnt/rootfs /bin/bash -c "echo 'root:firecracker' | chpasswd"
    chroot /mnt/rootfs /bin/bash -c "systemctl enable ssh"

    # Configure networking
    cat > /mnt/rootfs/etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [172.20.0.2/24]
      gateway4: 172.20.0.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

    umount /mnt/rootfs
    rm -rf "$TMPDIR"
fi

# Create log FIFOs
mkfifo /var/log/firecracker-containerd/log.fifo || true
mkfifo /var/log/firecracker-containerd/metrics.fifo || true

# Create Firecracker runtime config
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
            "is_read_only": false
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
    "log_fifo": "/var/log/firecracker-containerd/log.fifo",
    "metrics_fifo": "/var/log/firecracker-containerd/metrics.fifo",
    "log_level": "Debug"
}
EOF

# Create containerd config
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

# Setup networking
ip tuntap add tap0 mode tap || true
ip link set tap0 up || true

# Start logging
cat /var/log/firecracker-containerd/log.fifo > /var/log/firecracker-containerd/runtime.log &
cat /var/log/firecracker-containerd/metrics.fifo > /var/log/firecracker-containerd/metrics.log &

# Restart containerd
systemctl restart containerd

echo "Setup complete!"
```

### 2. Run Setup

```bash
chmod +x setup-firecracker.sh
sudo ./setup-firecracker.sh
```

### 3. Verify Installation

```bash
# Check Firecracker binary
firecracker --version

# Check files
ls -l /usr/local/bin/firecracker
ls -l /var/lib/firecracker-containerd/kernel/vmlinux
ls -l /var/lib/firecracker/rootfs/rootfs.ext4

# Check containerd
systemctl status containerd
```

### 4. Run Firecracker

```bash
sudo firecracker --api-sock /tmp/firecracker.socket --config-file /etc/containerd/firecracker-runtime.json
```

## VM Details

- IP Address: 172.20.0.2
- Gateway: 172.20.0.1
- Root Password: firecracker
- SSH: `ssh root@172.20.0.2`

## Troubleshooting

1. Check logs:
```bash
tail -f /var/log/firecracker-containerd/runtime.log
```

2. Check containerd status:
```bash
journalctl -u containerd -n 50
```

3. Check network:
```bash
ip link show tap0
ip addr show tap0
```

4. Verify configurations:
```bash
cat /etc/containerd/firecracker-runtime.json
cat /etc/containerd/config.toml
```