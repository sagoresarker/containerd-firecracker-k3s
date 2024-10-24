package ssh

import (
	"fmt"
	"os"
	"time"

	"golang.org/x/crypto/ssh"
)

type Client struct {
	config *ssh.ClientConfig
	addr   string
}

func NewClient(user, keyPath, addr string, port int) (*Client, error) {
	key, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("unable to read private key: %v", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("unable to parse private key: %v", err)
	}

	config := &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signer),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	return &Client{
		config: config,
		addr:   fmt.Sprintf("%s:%d", addr, port),
	}, nil
}

func (c *Client) WaitForSSH(timeout time.Duration) error {
	timeoutChan := time.After(timeout)
	tick := time.NewTicker(1 * time.Second)
	defer tick.Stop()

	for {
		select {
		case <-timeoutChan:
			return fmt.Errorf("timeout waiting for SSH")
		case <-tick.C:
			client, err := ssh.Dial("tcp", c.addr, c.config)
			if err == nil {
				client.Close()
				return nil
			}
		}
	}
}

func (c *Client) ExecuteCommand(cmd string) (string, error) {
	client, err := ssh.Dial("tcp", c.addr, c.config)
	if err != nil {
		return "", fmt.Errorf("failed to dial: %v", err)
	}
	defer client.Close()

	session, err := client.NewSession()
	if err != nil {
		return "", fmt.Errorf("failed to create session: %v", err)
	}
	defer session.Close()

	output, err := session.CombinedOutput(cmd)
	if err != nil {
		return "", fmt.Errorf("failed to execute command: %v", err)
	}

	return string(output), nil
}
