#!/bin/bash
set -e

# Install minimal required dependencies
apt-get update
apt-get install -y \
    debootstrap \
    containerd \
    make \
    wget \
    golang-go

# Clone if not exists, otherwise update
if [ ! -d "firecracker-containerd" ]; then
    git clone https://github.com/firecracker-microvm/firecracker-containerd.git
fi

cd firecracker-containerd

# Build components
echo "Building runtime..."
make -C runtime

echo "Building snapshotter..."
make -C snapshotter

echo "Building agent..."
make -C agent

echo "Building image-builder..."
cd tools/image-builder
mkdir -p tmp/rootfs/usr/local/bin/
# Copy the agent binary to the rootfs
cp ../../agent/agent tmp/rootfs/usr/local/bin/
make
cd ../..

# Install binaries with correct paths
echo "Installing binaries..."
echo "Checking built files..."
ls -la runtime/
ls -la snapshotter/
ls -la agent/
ls -la tools/image-builder/

echo "Installing runtime..."
install -D -m 755 runtime/containerd-shim-aws-firecracker /usr/local/bin/

echo "Installing snapshotter..."
install -D -m 755 snapshotter/demux-snapshotter /usr/local/bin/
install -D -m 755 snapshotter/http-address-resolver /usr/local/bin/

echo "Installing agent..."
install -D -m 755 agent/agent /usr/local/bin/containerd-firecracker-agent

# Copying rootfs and kernel files
echo "Copying rootfs and image files..."
install -D -m 644 tools/image-builder/rootfs.img /var/lib/firecracker-containerd/rootfs.img
install -D -m 644 tools/image-builder/rootfs-debug.img /var/lib/firecracker-containerd/rootfs-debug.img

echo "Build complete!"

# Verify installed files
echo "Verifying installed files..."
ls -l /usr/local/bin/containerd-shim-aws-firecracker
ls -l /usr/local/bin/demux-snapshotter
ls -l /usr/local/bin/http-address-resolver
ls -l /usr/local/bin/containerd-firecracker-agent
ls -l /var/lib/firecracker-containerd/rootfs.img
ls -l /var/lib/firecracker-containerd/rootfs-debug.img