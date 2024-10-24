#!/bin/bash
set -e

# Create mount point for rootfs
MOUNT_POINT="/mnt/rootfs"
mkdir -p ${MOUNT_POINT}

# Mount the rootfs
echo "Mounting rootfs..."
mount -o loop /var/lib/firecracker/rootfs/rootfs.ext4 ${MOUNT_POINT}

# Create SSH directory and set permissions
mkdir -p ${MOUNT_POINT}/root/.ssh
chmod 700 ${MOUNT_POINT}/root/.ssh

# Generate new SSH key pair if it doesn't exist
if [ ! -f ~/.ssh/fc_vm_key ]; then
    echo "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/fc_vm_key -N ""
fi

# Copy SSH public key to VM
echo "Adding SSH key to VM..."
cat ~/.ssh/fc_vm_key.pub > ${MOUNT_POINT}/root/.ssh/authorized_keys
chmod 600 ${MOUNT_POINT}/root/.ssh/authorized_keys

# Configure network in VM
cat > ${MOUNT_POINT}/etc/systemd/network/20-wired.network << EOF
[Match]
Name=eth0

[Network]
Address=172.20.0.2/24
Gateway=172.20.0.1
DNS=8.8.8.8
EOF

# Set root password (optional)
echo "Setting root password..."
chroot ${MOUNT_POINT} /bin/bash -c "echo 'root:firecracker' | chpasswd"

# Unmount rootfs
echo "Unmounting rootfs..."
umount ${MOUNT_POINT}

echo "Setup complete!"
echo
echo "VM Network Details:"
echo "IP Address: 172.20.0.2"
echo "Gateway: 172.20.0.1"
echo "Network: 172.20.0.0/24"
echo
echo "SSH Access:"
echo "Private key: ~/.ssh/fc_vm_key"
echo "Command to SSH into VM:"
echo "ssh -i ~/.ssh/fc_vm_key root@172.20.0.2"
echo
echo "Root password: firecracker"