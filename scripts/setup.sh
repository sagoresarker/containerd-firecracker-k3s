#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y \
    containerd \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    make \
    gcc \
    libc-dev \
    binutils \
    dmsetup \
    pkg-config \
    libseccomp-dev \
    protobuf-compiler \
    libprotobuf-dev \
    wget


# Handle existing firecracker-containerd directory
echo "Checking firecracker-containerd directory..."
if [ -d "firecracker-containerd" ]; then
    echo "Directory exists, updating repository..."
    cd firecracker-containerd
    git fetch
    git reset --hard origin/main
    git clean -fdx  # Clean untracked files
    # Clear Go module cache for this project
    go clean -modcache
else
    echo "Cloning repository..."
    git clone https://github.com/firecracker-microvm/firecracker-containerd.git
    cd firecracker-containerd
fi

# Update Go modules
echo "Updating Go modules..."
go mod tidy
go mod download

# Build and install firecracker-containerd components
echo "Building components..."

echo "Building runtime..."
cd runtime
go mod tidy
go mod download
make
cd ..

echo "Building snapshotter..."
cd snapshotter
go mod tidy
go mod download
make
cd ..

echo "Building agent..."
cd agent
go mod tidy
go mod download
make
cd ..

echo "Building image-builder..."
cd tools/image-builder
go mod tidy
go mod download


mkdir -p tmp/rootfs
make
cd ../..

echo "Installing binaries..."
# Update the installation path and name to match containerd's expectation
install -D -m 755 runtime/containerd-shim-aws-firecracker /usr/local/bin/containerd-shim-aws-firecracker
# Add symlink with the expected name
ln -sf /usr/local/bin/containerd-shim-aws-firecracker /usr/local/bin/containerd-shim-v2-aws-firecracker
install -D -m 755 snapshotter/containerd-firecracker-snapshotter /usr/local/bin/containerd-firecracker-snapshotter
install -D -m 755 agent/containerd-firecracker-agent /usr/local/bin/containerd-firecracker-agent
install -D -m 755 tools/image-builder/containerd-firecracker-image-builder /usr/local/bin/containerd-firecracker-image-builder

cd ..

# Download Firecracker binary if not exists
if [ ! -f "/usr/local/bin/firecracker" ]; then
    echo "Downloading Firecracker binary..."
    release_url="https://github.com/firecracker-microvm/firecracker/releases/download/v1.4.0/firecracker-v1.4.0-x86_64.tgz"
    curl -L ${release_url} | tar -xz
    mv release-v1.4.0-x86_64/firecracker-v1.4.0-x86_64 /usr/local/bin/firecracker
    chmod +x /usr/local/bin/firecracker
fi

# Download kernel image if not exists
if [ ! -f "/var/lib/firecracker-containerd/kernel/vmlinux" ]; then
    echo "Downloading kernel image..."
    mkdir -p /var/lib/firecracker-containerd/kernel
    wget https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin -O /var/lib/firecracker-containerd/kernel/vmlinux
fi

# Download rootfs if not exists
if [ ! -f "/var/lib/firecracker/rootfs/rootfs.ext4" ]; then
    echo "Downloading rootfs..."
    mkdir -p /var/lib/firecracker/rootfs
    wget https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/rootfs/bionic.rootfs.ext4 -O /var/lib/firecracker/rootfs/rootfs.ext4
fi

echo "Setup completed! Verifying installation..."

# Verify Go version
echo "Go version:"
go version

# Verify installation
if [ -f "/usr/local/bin/containerd-shim-aws-firecracker" ]; then
    echo "✓ containerd-shim-aws-firecracker installed"
else
    echo "✗ containerd-shim-aws-firecracker missing"
fi

if [ -f "/usr/local/bin/firecracker" ]; then
    echo "✓ firecracker installed"
else
    echo "✗ firecracker missing"
fi

if [ -f "/var/lib/firecracker-containerd/kernel/vmlinux" ]; then
    echo "✓ kernel image found"
else
    echo "✗ kernel image missing"
fi

echo "Installation complete. Please check above output for any errors."

echo "Verifying shim binary installation..."
if [ -f "/usr/local/bin/containerd-shim-v2-aws-firecracker" ]; then
    echo "✓ containerd-shim-v2-aws-firecracker installed"
else
    echo "✗ containerd-shim-v2-aws-firecracker missing"
    echo "Creating symlink..."
    ln -sf /usr/local/bin/containerd-shim-aws-firecracker /usr/local/bin/containerd-shim-v2-aws-firecracker
fi

# Verify the symlink
ls -l /usr/local/bin/containerd-shim-v2-aws-firecracker
