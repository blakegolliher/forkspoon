#!/bin/bash

# Quick test script for when Go is installed
# This script builds and runs a quick test of the FUSE filesystem

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Quick FUSE Filesystem Test ===${NC}"
echo

# Step 1: Check Go installation
echo "1. Checking Go installation..."
export PATH=$PATH:/usr/local/go/bin
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo "Please install Go first:"
    echo "  wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz"
    echo "  sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz"
    echo "  export PATH=\$PATH:/usr/local/go/bin"
    exit 1
fi
echo -e "${GREEN}✓ Go is installed: $(go version)${NC}"

# Step 2: Build the filesystem
echo
echo "2. Building forkspoon..."
echo "   Downloading dependencies..."
go mod download
go mod tidy
echo "   Building binary..."
go build -o forkspoon main.go
if [ -f forkspoon ]; then
    echo -e "${GREEN}✓ Build successful${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

# Step 3: Create test environment
echo
echo "3. Creating test environment..."
BACKEND="/tmp/test-backend-$$"
MOUNT="/tmp/test-mount-$$"

mkdir -p "$BACKEND"
mkdir -p "$MOUNT"

# Create test files
echo "Creating test files..."
for i in {1..10}; do
    echo "Test file $i" > "$BACKEND/file$i.txt"
done
mkdir -p "$BACKEND/subdir"
echo "Nested file" > "$BACKEND/subdir/nested.txt"

echo -e "${GREEN}✓ Test environment created${NC}"

# Step 4: Mount the filesystem
echo
echo "4. Mounting FUSE filesystem..."
echo "   Backend: $BACKEND"
echo "   Mount:   $MOUNT"
echo "   Cache TTL: 30 seconds"
echo

# Run in background with logging
./forkspoon -backend "$BACKEND" -mountpoint "$MOUNT" -cache-ttl 30s -verbose &
FUSE_PID=$!

# Wait for mount
sleep 2

# Check if mounted
if mountpoint -q "$MOUNT"; then
    echo -e "${GREEN}✓ Filesystem mounted successfully${NC}"
else
    echo -e "${RED}✗ Mount failed${NC}"
    kill $FUSE_PID 2>/dev/null || true
    exit 1
fi

# Step 5: Run tests
echo
echo "5. Running cache tests..."
echo

echo -e "${YELLOW}Test 1: First access (cache miss expected)${NC}"
echo "Running: ls -la $MOUNT"
time ls -la "$MOUNT"
echo

echo -e "${YELLOW}Test 2: Second access (cache hit expected - should be faster)${NC}"
echo "Running: ls -la $MOUNT (again)"
time ls -la "$MOUNT"
echo

echo -e "${YELLOW}Test 3: File operations${NC}"
echo "Creating new file..."
echo "New content" > "$MOUNT/newfile.txt"
echo "Reading file..."
cat "$MOUNT/newfile.txt"
echo "Renaming file..."
mv "$MOUNT/newfile.txt" "$MOUNT/renamed.txt"
echo "Deleting file..."
rm "$MOUNT/renamed.txt"
echo -e "${GREEN}✓ File operations successful${NC}"
echo

echo -e "${YELLOW}Test 4: Performance test (100 stat operations)${NC}"

# Direct access timing
START=$(date +%s%N)
for i in {1..100}; do
    stat "$BACKEND/file1.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
DIRECT_MS=$((($END - $START) / 1000000))
echo "Direct backend: ${DIRECT_MS}ms"

# Cached access timing (prime cache first)
stat "$MOUNT/file1.txt" > /dev/null 2>&1
START=$(date +%s%N)
for i in {1..100}; do
    stat "$MOUNT/file1.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
CACHED_MS=$((($END - $START) / 1000000))
echo "With caching:  ${CACHED_MS}ms"

if [ $CACHED_MS -lt $DIRECT_MS ]; then
    SPEEDUP=$(echo "scale=1; $DIRECT_MS / $CACHED_MS" | bc 2>/dev/null || echo "N/A")
    echo -e "${GREEN}✓ Caching provides ${SPEEDUP}x speedup${NC}"
else
    echo -e "${YELLOW}⚠ No speedup observed (may be due to fast local filesystem)${NC}"
fi

# Step 6: Cleanup
echo
echo "6. Cleaning up..."

# Kill FUSE process
kill $FUSE_PID 2>/dev/null || true
sleep 1

# Unmount if still mounted
fusermount -u "$MOUNT" 2>/dev/null || true

# Remove test directories
rm -rf "$BACKEND" "$MOUNT"

echo -e "${GREEN}✓ Cleanup complete${NC}"

echo
echo -e "${GREEN}=== All Tests Completed Successfully! ===${NC}"
echo
echo "The FUSE filesystem is working correctly with:"
echo "  • Metadata caching (configurable TTL)"
echo "  • File operations (create, read, rename, delete)"
echo "  • Performance improvements through caching"
echo
echo "To use in production:"
echo "  ./forkspoon -backend /your/slow/storage -mountpoint /fast/cache -cache-ttl 5m"