package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/sagoresarker/containerd-firecracker-k3s/internal/config"
	"github.com/sagoresarker/containerd-firecracker-k3s/internal/vm"
)

func main() {
	configPath := flag.String("config", "../configs/config.yaml", "path to config file")
	flag.Parse()

	absConfigPath, err := filepath.Abs(*configPath)
	if err != nil {
		log.Fatalf("Failed to get absolute path: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

	// Load configuration
	cfg, err := config.LoadConfig(absConfigPath)
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

	<-sigChan
	log.Println("Shutting down...")
}
