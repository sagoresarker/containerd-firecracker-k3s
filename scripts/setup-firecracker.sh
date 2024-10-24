#!/bin/bash
set -e

# Create necessary directories
mkdir -p /usr/local/bin
mkdir -p /var/lib/firecracker-containerd/kernel
mkdir -p /var/lib/firecracker/rootfs

echo "Checking and downloading required components..."

# 1. Check and download Firecracker binary
echo "Checking Firecracker binary..."
if [ ! -f "/usr/local/bin/firecracker" ]; then
    echo "Downloading Firecracker binary..."
    ARCH="$(uname -m)"
    release_url="https://github.com/firecracker-microvm/firecracker/releases"
    latest=$(basename $(curl -fsSLI -o /dev/null -w  %{url_effective} ${release_url}/latest))
    curl -L ${release_url}/download/${latest}/firecracker-${latest}-${ARCH}.tgz \
    | tar -xz

    # Rename the binary to "firecracker"
    mv release-${latest}-$(uname -m)/firecracker-${latest}-${ARCH} firecracker
else
    echo "Firecracker binary already exists"
fi

# 2. Check and download kernel
echo "Checking kernel..."
if [ ! -f "/var/lib/firecracker-containerd/kernel/vmlinux" ]; then
    echo "Downloading kernel..."
    wget https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin \
        -O /var/lib/firecracker-containerd/kernel/vmlinux
else
    echo "Kernel already exists"
fi

# 3. Create root filesystem
echo "Checking root filesystem..."
if [ ! -f "/var/lib/firecracker/rootfs/rootfs.ext4" ]; then
    echo "Creating root filesystem..."

    # Install required packages
    apt-get update
    apt-get install -y debootstrap

    # Create a temporary directory for the root filesystem
    TMPDIR=$(mktemp -d)

    # Create minimal Debian root filesystem
    debootstrap --variant=minbase \
        --include="systemd,systemd-sysv,procps,netplan.io,iproute2,iptables,net-tools,openssh-server" \
        bullseye "$TMPDIR"

    # Create ext4 filesystem image
    truncate -s 5G /var/lib/firecracker/rootfs/rootfs.ext4
    mkfs.ext4 /var/lib/firecracker/rootfs/rootfs.ext4

    # Mount the image and copy files
    mkdir -p /mnt/rootfs
    mount /var/lib/firecracker/rootfs/rootfs.ext4 /mnt/rootfs
    cp -a "$TMPDIR"/* /mnt/rootfs/

    # Configure root password and SSH
    chroot /mnt/rootfs /bin/bash -c "echo 'root:root' | chpasswd"
    chroot /mnt/rootfs /bin/bash -c "systemctl enable ssh"

    # Network configuration
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

    # Unmount and cleanup
    umount /mnt/rootfs
    rm -rf "$TMPDIR"
else
    echo "Root filesystem already exists"
fi

# Verify components
echo "Verifying components..."
echo "1. Firecracker binary:"
ls -l /usr/local/bin/firecracker
echo "2. Kernel:"
ls -l /var/lib/firecracker-containerd/kernel/vmlinux
echo "3. Root filesystem:"
ls -l /var/lib/firecracker/rootfs/rootfs.ext4

# Update runtime config with correct paths
cat << EOF > /etc/containerd/firecracker-runtime.json
{
    "firecracker_binary_path": "/usr/local/bin/firecracker",
    "kernel_image_path": "/var/lib/firecracker-containerd/kernel/vmlinux",
    "root_drive": "/var/lib/firecracker/rootfs/rootfs.ext4",
    "cpu_template": "T2",
    "vcpu_count": 2,
    "mem_size_mib": 2048,
    "jailer": {
        "runc_binary_path": "/usr/local/bin/runc",
        "uid": 0,
        "gid": 0
    },
    "network": {
        "mode": "tap",
        "tap_device": {
            "name": "tap0",
            "ip": "172.20.0.1",
            "netmask": "255.255.255.0",
            "mac": "AA:FC:00:00:00:01"
        }
    }
}
EOF

echo "Setup complete! Component locations:"
echo "firecracker_binary_path: /usr/local/bin/firecracker"
echo "kernel_image_path: /var/lib/firecracker-containerd/kernel/vmlinux"
echo "root_drive: /var/lib/firecracker/rootfs/rootfs.ext4"