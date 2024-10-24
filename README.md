# Containerd Firecracker K3s

Launch a Firecracker microVM with firecracker-containerd.

## Prerequisites

- Linux host with KVM support
- containerd (v1.7+)
- Firecracker-containerd
- Go 1.22+
- Root privileges for VM operations

## System Requirements

- x86_64 architecture
- Linux kernel 4.14+ (5.10+ recommended)
- At least 512MB RAM
- KVM enabled (`/dev/kvm` must exist)

## Installation

1. Clone the repository:

```bash
git clone https://github.com/sagoresarker/containerd-firecracker-k3s.git

cd containerd-firecracker-k3s
```

2. Run the setup script (requires root privileges):

```bash
sudo ./scripts/setup.sh
```

This script will:
- Install containerd and firecracker-containerd
- Configure containerd with Firecracker runtime
- Set up CNI networking
- Create necessary directories

3. Build the project:

```bash
make build
```

## Configuration

1. Create or modify the configuration file at `configs/config.yaml`:

```yaml
vm:
    id: "microvm-01"
    image: "docker.io/library/ubuntu:20.04"
    kernel: "/var/lib/firecracker-containerd/kernel/vmlinux"
    cpus: 2
    memory_mb: 2048
    ip: "172.20.0.2"
    gateway: "172.20.0.1"
    netmask: "255.255.255.0"
    mac_address: "AA:FC:00:00:00:01"
    nameservers:
    "8.8.8.8"
    "8.8.4.4"
    ssh:
    user: "ubuntu"
    key_path: "/path/to/your/ssh/key"
    port: 22
```


2. Prepare the kernel and rootfs:

Download a Linux kernel built for Firecracker
```bash
sudo wget https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin \
-O /var/lib/firecracker-containerd/kernel/vmlinux
```

Create a root filesystem (example using Ubuntu cloud image)

```bash
sudo wget https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img \
-O /var/lib/firecracker/rootfs.ext4
```


## Usage

1. Launch a VM:

```bash
sudo ./bin/firecracker-manager
```

```bash
sudo ./bin/firecracker-manager
```


The program will:
- Load the configuration from `configs/config.yaml`
- Pull the specified container image
- Launch a Firecracker microVM
- Configure networking
- Print SSH connection details

2. SSH into the VM:

```bash
ssh -i /path/to/your/ssh/key ubuntu@172.20.0.2
```
