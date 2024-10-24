package vm

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"syscall"
	"time"

	"github.com/containerd/containerd"
	"github.com/containerd/containerd/cio"
	"github.com/containerd/containerd/containers"
	"github.com/containerd/containerd/namespaces"
	"github.com/containerd/containerd/oci"
	fc "github.com/firecracker-microvm/firecracker-containerd/runtime/firecrackeroci"
	"github.com/sirupsen/logrus"

	"github.com/opencontainers/runtime-spec/specs-go"

	"github.com/sagoresarker/containerd-firecracker-k3s/internal/config"
	"github.com/sagoresarker/containerd-firecracker-k3s/pkg/types"
)

type Manager struct {
	client *containerd.Client
	config *config.Config
	logger *logrus.Logger
}

// NewManager creates a new VM manager
func NewManager(ctx context.Context, cfg *config.Config) (*Manager, error) {
	client, err := containerd.New("/run/containerd/containerd.sock")
	if err != nil {
		return nil, fmt.Errorf("failed to create containerd client: %w", err)
	}

	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})

	return &Manager{
		client: client,
		config: cfg,
		logger: logger,
	}, nil
}

// cleanup function now takes pointer receiver to avoid lock copying
func (m *Manager) cleanup(ctx context.Context, task containerd.Task, container containerd.Container) {
	if task != nil {
		if err := task.Kill(ctx, syscall.SIGKILL); err != nil {
			m.logger.WithError(err).Error("Failed to kill task during cleanup")
		}
		if _, err := task.Delete(ctx, containerd.WithProcessKill); err != nil {
			m.logger.WithError(err).Error("Failed to delete task during cleanup")
		}
	}
	if container != nil {
		if err := container.Delete(ctx, containerd.WithSnapshotCleanup); err != nil {
			m.logger.WithError(err).Error("Failed to delete container during cleanup")
		}
	}
}

// LaunchVM launches a new VM
func (m *Manager) LaunchVM(ctx context.Context) (string, error) {
	ctx = namespaces.WithNamespace(ctx, "firecracker")

	if err := m.validateConfig(); err != nil {
		return "", fmt.Errorf("invalid configuration: %w", err)
	}

	image, err := m.pullImage(ctx)
	if err != nil {
		return "", err
	}

	container, err := m.client.NewContainer(
		ctx,
		m.config.VM.ID,
		containerd.WithNewSnapshot(m.config.VM.ID+"-snap", image),
		containerd.WithNewSpec(
			withVMAnnotations(m.config),
			oci.WithRootFSPath("rootfs"),
		),
		// Update runtime string to match containerd config
		containerd.WithRuntime("io.containerd.runtime.v2.aws-firecracker", nil),
	)
	if err != nil {
		return "", fmt.Errorf("failed to create container: %w", err)
	}

	task, err := container.NewTask(ctx, cio.NewCreator(
		cio.WithStdio,
		cio.WithTerminal,
	))
	if err != nil {
		m.cleanup(ctx, nil, container)
		return "", fmt.Errorf("failed to create task: %w", err)
	}

	if err := task.Start(ctx); err != nil {
		m.cleanup(ctx, task, container)
		return "", fmt.Errorf("failed to start task: %w", err)
	}

	if err := m.waitForVMReady(ctx, task); err != nil {
		m.cleanup(ctx, task, container)
		return "", fmt.Errorf("VM failed to become ready: %w", err)
	}

	m.logger.WithFields(logrus.Fields{
		"vmID":        m.config.VM.ID,
		"ip":          m.config.VM.IP,
		"cpus":        m.config.VM.CPUs,
		"memory":      m.config.VM.Memory,
		"kernel":      m.config.VM.Kernel,
		"image":       m.config.VM.Image,
		"macAddress":  m.config.VM.MacAddress,
		"nameservers": m.config.VM.Nameservers,
	}).Info("VM launched successfully")

	return m.config.VM.ID, nil
}

// validateConfig validates the VM configuration
func (m *Manager) validateConfig() error {
	if m.config.VM.ID == "" {
		return fmt.Errorf("VM ID cannot be empty")
	}
	if m.config.VM.Memory < 128 {
		return fmt.Errorf("VM memory must be at least 128MB")
	}
	if m.config.VM.CPUs < 1 {
		return fmt.Errorf("VM must have at least 1 CPU")
	}
	if m.config.VM.Kernel == "" {
		return fmt.Errorf("kernel path cannot be empty")
	}

	// Check if kernel file exists
	if _, err := os.Stat("/var/lib/firecracker-containerd/kernel/vmlinux"); err != nil {
		return fmt.Errorf("kernel file not found: %w", err)
	}

	// Check if rootfs exists
	if _, err := os.Stat("/var/lib/firecracker/rootfs/rootfs.ext4"); err != nil {
		return fmt.Errorf("rootfs not found: %w", err)
	}

	return nil
}

// waitForVMReady waits for the VM to become ready
func (m *Manager) waitForVMReady(ctx context.Context, task containerd.Task) error {
	timeout := time.After(30 * time.Second)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-timeout:
			return fmt.Errorf("timeout waiting for VM to become ready")
		case <-ticker.C:
			status, err := task.Status(ctx)
			if err != nil {
				return err
			}
			if status.Status == containerd.Running {
				return nil
			}
		}
	}
}

// pullImage pulls the VM image
func (m *Manager) pullImage(ctx context.Context) (containerd.Image, error) {
	image, err := m.client.Pull(ctx, m.config.VM.Image,
		containerd.WithPullUnpack,
		containerd.WithPullSnapshotter("overlayfs"),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to pull image: %w", err)
	}
	return image, nil
}

// StopVM stops a running VM
func (m *Manager) StopVM(ctx context.Context, vmID string) error {
	ctx = namespaces.WithNamespace(ctx, "firecracker")

	container, err := m.client.LoadContainer(ctx, vmID)
	if err != nil {
		return fmt.Errorf("failed to load container: %w", err)
	}

	task, err := container.Task(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to get task: %w", err)
	}

	if err := task.Kill(ctx, syscall.SIGTERM); err != nil {
		m.logger.WithError(err).Warn("Failed to send SIGTERM, attempting force kill")
	}

	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	exitCh, err := task.Wait(ctx)
	if err != nil {
		return fmt.Errorf("failed to wait for task: %w", err)
	}

	select {
	case <-exitCh:
		// Task exited normally
	case <-ctx.Done():
		// Force kill if timeout
		if err := task.Kill(ctx, syscall.SIGKILL); err != nil {
			m.logger.WithError(err).Error("Failed to force kill task")
		}
	}

	m.cleanup(ctx, task, container)
	m.logger.WithField("vmID", vmID).Info("VM stopped successfully")
	return nil
}

// ListVMs lists all running VMs
func (m *Manager) ListVMs(ctx context.Context) ([]types.VMState, error) {
	ctx = namespaces.WithNamespace(ctx, "firecracker")

	containers, err := m.client.Containers(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to list containers: %w", err)
	}

	var vms []types.VMState
	for _, container := range containers {
		info, err := container.Info(ctx)
		if err != nil {
			continue
		}

		vms = append(vms, types.VMState{
			ID:        container.ID(),
			CreatedAt: info.CreatedAt.Format(time.RFC3339),
			State:     "running",
		})
	}

	return vms, nil
}

// // withVMAnnotations modified for CNI networking
// func withVMAnnotations(cfg *config.Config) oci.SpecOpts {
// 	return func(_ context.Context, _ oci.Client, _ *containers.Container, s *specs.Spec) error {
// 		if s.Annotations == nil {
// 			s.Annotations = make(map[string]string)
// 		}

// 		s.Annotations[fc.VMIDAnnotationKey] = cfg.VM.ID

// 		memoryInBytes := cfg.VM.Memory * 1024 * 1024

// 		vmConfig := map[string]interface{}{
// 			"kernel":          cfg.VM.Kernel,
// 			"cpu_count":       cfg.VM.CPUs,
// 			"memory_in_bytes": memoryInBytes,
// 			"kernel_args": fmt.Sprintf(
// 				"console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw " +
// 					"root=/dev/vda1 systemd.unified_cgroup_hierarchy=0 " +
// 					"systemd.journald.forward_to_console=1 " +
// 					"ip=dhcp", // Use DHCP for network configuration
// 			),
// 			// CNI will handle networking
// 			"network": map[string]interface{}{
// 				"mode": "cni",
// 				"cni": map[string]interface{}{
// 					"path":       "/opt/cni/bin",
// 					"configPath": "/etc/cni/conf.d",
// 					"args": []string{
// 						"IgnoreUnknown=1",
// 						"K8S_POD_NAMESPACE=firecracker",
// 						fmt.Sprintf("K8S_POD_NAME=%s", cfg.VM.ID),
// 					},
// 				},
// 			},
// 		}

// 		vmConfigJSON, err := json.Marshal(vmConfig)
// 		if err != nil {
// 			return fmt.Errorf("failed to marshal VM config: %w", err)
// 		}
// 		s.Annotations["aws.firecracker.vm.config"] = string(vmConfigJSON)

// 		return nil
// 	}
// }

// withVMAnnotations for manual networking configuration
func withVMAnnotations(cfg *config.Config) oci.SpecOpts {
	return func(_ context.Context, _ oci.Client, _ *containers.Container, s *specs.Spec) error {
		if s.Annotations == nil {
			s.Annotations = make(map[string]string)
		}

		s.Annotations[fc.VMIDAnnotationKey] = cfg.VM.ID

		memoryInBytes := cfg.VM.Memory * 1024 * 1024

		vmConfig := map[string]interface{}{
			"kernel":          "/var/lib/firecracker-containerd/kernel/vmlinux", // Update kernel path
			"cpu_count":       cfg.VM.CPUs,
			"memory_in_bytes": memoryInBytes,
			"kernel_args": fmt.Sprintf(
				"console=ttyS0 noapic reboot=k panic=1 pci=off nomodules rw "+
					"ip=%s::%s:%s::eth0:off root=/dev/vda "+  // Update root device
					"systemd.unified_cgroup_hierarchy=0 systemd.journald.forward_to_console=1",
				cfg.VM.IP,
				cfg.VM.Gateway,
				cfg.VM.Netmask,
			),
			"network": map[string]interface{}{
				"tap_name":            fmt.Sprintf("tap%s", cfg.VM.ID),
				"host_dev_name":       "eth0",
				"mac_address":         cfg.VM.MacAddress,
				"ip_address":          cfg.VM.IP,
				"gateway":             cfg.VM.Gateway,
				"nameservers":         cfg.VM.Nameservers,
				"mtu":                 1500,
				"allow_mmds_requests": true,
			},
			"drives": []map[string]interface{}{
				{
					"is_root_device": true,
					"path_on_host":   "/var/lib/firecracker/rootfs/rootfs.ext4", // Update rootfs path
					"is_read_only":   false,
				},
			},
		}

		vmConfigJSON, err := json.Marshal(vmConfig)
		if err != nil {
			return fmt.Errorf("failed to marshal VM config: %w", err)
		}
		s.Annotations["aws.firecracker.vm.config"] = string(vmConfigJSON)

		return nil
	}
}
