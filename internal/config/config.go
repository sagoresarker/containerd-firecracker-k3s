package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	VM  VMConfig  `yaml:"vm"`
	SSH SSHConfig `yaml:"ssh"`
}

type VMConfig struct {
	ID          string   `yaml:"id"`
	Image       string   `yaml:"image"`
	Kernel      string   `yaml:"kernel"`
	CPUs        int      `yaml:"cpus"`
	Memory      int64    `yaml:"memory_mb"`
	IP          string   `yaml:"ip"`
	Gateway     string   `yaml:"gateway"`
	Netmask     string   `yaml:"netmask"`
	MacAddress  string   `yaml:"mac_address"`
	Nameservers []string `yaml:"nameservers"`
}

type SSHConfig struct {
	User    string `yaml:"user"`
	KeyPath string `yaml:"key_path"`
	Port    int    `yaml:"port"`
}

// LoadConfig loads configuration from a file
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var config Config
	err = yaml.Unmarshal(data, &config)
	if err != nil {
		return nil, err
	}

	return &config, nil
}
