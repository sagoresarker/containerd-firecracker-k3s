package types

type VMState struct {
	ID        string
	IP        string
	State     string
	CreatedAt string
}

type NetworkConfig struct {
	IPAddress   string
	MacAddress  string
	Gateway     string
	Netmask     string
	Nameservers []string
}

type VMConfig struct {
	VCPU   int64
	Memory int64
	Kernel string
	RootFS string
}
