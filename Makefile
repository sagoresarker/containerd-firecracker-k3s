.PHONY: build test clean

build:
    go build -o bin/firecracker-manager cmd/server/main.go

test:
    go test -v ./...

clean:
    rm -rf bin/
