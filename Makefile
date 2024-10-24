.PHONY: build test clean

build:
	@ go build -o bin/firecracker-launcher cmd/launcher/main.go

test:
	@ go test -v ./...

clean:
	@ rm -rf bin/
