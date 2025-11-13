#!/bin/bash

# Build script for forkspoon

set -e

echo "Building metadata-caching FUSE filesystem..."

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed."
    echo "Please install Go from https://golang.org/dl/"
    exit 1
fi

# Display Go version
echo "Go version: $(go version)"

# Clean previous build
rm -f forkspoon

# Download dependencies
echo "Downloading dependencies..."
go mod download

# Build the binary
echo "Building forkspoon..."
go build -o forkspoon main.go

if [ -f forkspoon ]; then
    echo "Build successful!"
    echo "Binary created: ./forkspoon"
    echo
    echo "Usage:"
    echo "  ./forkspoon -backend <backend-dir> -mountpoint <mount-dir>"
    echo
    echo "Example:"
    echo "  ./forkspoon -backend /mnt/nfs-real -mountpoint /mnt/nfs-cached -verbose"
else
    echo "Build failed!"
    exit 1
fi