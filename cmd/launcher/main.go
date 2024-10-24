package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/sagoresarker/containerd-firecracker-k3s/internal/config"
	"github.com/sagoresarker/containerd-firecracker-k3s/internal/vm"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

	// Load configuration
	cfg, err := config.LoadConfig("configs/config.yaml")
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Create VM manager
	manager, err := vm.NewManager(ctx, cfg)
	if err != nil {
		log.Fatalf("Failed to create VM manager: %v", err)
	}

	// Launch VM
	vmID, err := manager.LaunchVM(ctx)
	if err != nil {
		log.Fatalf("Failed to launch VM: %v", err)
	}

	log.Printf("VM launched successfully. ID: %s", vmID)
	log.Printf("You can SSH into the VM using: ssh -i %s %s@%s",
		cfg.SSH.KeyPath, cfg.SSH.User, cfg.VM.IP)

	// Wait for shutdown signal
	<-sigChan
	log.Println("Shutting down...")
}
