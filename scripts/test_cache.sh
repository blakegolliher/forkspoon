#!/bin/bash

# Test script for the metadata-caching FUSE filesystem
# This script demonstrates the caching behavior of the filesystem

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKEND_DIR="/tmp/test-backend"
MOUNT_DIR="/tmp/test-mount"
TEST_FILE="testfile1.txt"
TEST_DIR="testdir1"

echo -e "${BLUE}=== Metadata-Caching FUSE Filesystem Test ===${NC}"
echo

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"

    # Unmount if mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        echo "Unmounting $MOUNT_DIR..."
        fusermount -u "$MOUNT_DIR" 2>/dev/null || sudo umount "$MOUNT_DIR" 2>/dev/null || true
        sleep 1
    fi

    # Remove test directories
    [ -d "$MOUNT_DIR" ] && rmdir "$MOUNT_DIR" 2>/dev/null || true
    [ -d "$BACKEND_DIR" ] && rm -rf "$BACKEND_DIR" 2>/dev/null || true

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set up cleanup on exit
trap cleanup EXIT INT TERM

# Step 1: Create test directories and files
echo -e "${GREEN}Step 1: Setting up test environment${NC}"
echo "Creating backend directory: $BACKEND_DIR"
mkdir -p "$BACKEND_DIR"

echo "Creating mount point: $MOUNT_DIR"
mkdir -p "$MOUNT_DIR"

echo "Creating test files in backend..."
echo "This is a test file" > "$BACKEND_DIR/$TEST_FILE"
mkdir -p "$BACKEND_DIR/$TEST_DIR"
echo "File in subdirectory" > "$BACKEND_DIR/$TEST_DIR/subfile.txt"

# Create multiple files for testing
for i in {1..5}; do
    echo "Test content $i" > "$BACKEND_DIR/file$i.txt"
done

echo -e "${GREEN}✓ Test environment created${NC}\n"

# Step 2: Build the FUSE filesystem
echo -e "${GREEN}Step 2: Building the FUSE filesystem${NC}"
if command -v go &> /dev/null; then
    echo "Building forkspoon..."
    go build -o forkspoon main.go
    echo -e "${GREEN}✓ Build successful${NC}\n"
else
    echo -e "${RED}Go is not installed. Please install Go and run: go build -o forkspoon main.go${NC}"
    echo "Assuming binary already exists..."
fi

# Step 3: Mount the filesystem
echo -e "${GREEN}Step 3: Mounting the filesystem${NC}"
echo "Running: ./forkspoon -backend $BACKEND_DIR -mountpoint $MOUNT_DIR -verbose"

# Start the FUSE daemon in background
./forkspoon -backend "$BACKEND_DIR" -mountpoint "$MOUNT_DIR" -verbose &
FUSE_PID=$!

# Wait for mount to complete
sleep 2

# Check if mount succeeded
if ! mountpoint -q "$MOUNT_DIR"; then
    echo -e "${RED}Mount failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Filesystem mounted successfully${NC}"
echo "FUSE daemon PID: $FUSE_PID"
echo

# Step 4: Test cache behavior
echo -e "${GREEN}Step 4: Testing cache behavior${NC}"
echo

# Test 1: First access (cache miss)
echo -e "${YELLOW}Test 1: First access - Cache MISS expected${NC}"
echo "Running: ls -la $MOUNT_DIR"
echo "Watch the daemon output for [GETATTR] and [LOOKUP] cache miss messages..."
time ls -la "$MOUNT_DIR"
echo

sleep 2

# Test 2: Second access (cache hit)
echo -e "${YELLOW}Test 2: Immediate second access - Cache HIT expected${NC}"
echo "Running: ls -la $MOUNT_DIR (again)"
echo "You should see NO new [GETATTR] or [LOOKUP] messages in daemon output..."
time ls -la "$MOUNT_DIR"
echo

sleep 2

# Test 3: Access specific file
echo -e "${YELLOW}Test 3: Access specific file - Mixed cache behavior${NC}"
echo "Running: stat $MOUNT_DIR/$TEST_FILE"
echo "First stat should show cache miss for the file..."
stat "$MOUNT_DIR/$TEST_FILE"
echo

sleep 1

echo "Running stat again - should be served from cache..."
stat "$MOUNT_DIR/$TEST_FILE"
echo

# Test 4: Directory listing
echo -e "${YELLOW}Test 4: Directory operations${NC}"
echo "Running: ls -la $MOUNT_DIR/$TEST_DIR"
ls -la "$MOUNT_DIR/$TEST_DIR"
echo

# Test 5: Read file content (passthrough, not cached)
echo -e "${YELLOW}Test 5: File read operations (passthrough)${NC}"
echo "Running: cat $MOUNT_DIR/$TEST_FILE"
cat "$MOUNT_DIR/$TEST_FILE"
echo

# Test 6: Write operation (passthrough)
echo -e "${YELLOW}Test 6: Write operations (passthrough)${NC}"
echo "Creating new file: $MOUNT_DIR/newfile.txt"
echo "New content" > "$MOUNT_DIR/newfile.txt"
echo "File created. Listing directory again..."
ls -la "$MOUNT_DIR"
echo

# Test 7: Performance comparison
echo -e "${YELLOW}Test 7: Performance comparison${NC}"
echo "Timing 100 consecutive ls operations..."
echo

echo -e "${BLUE}With caching (after initial cache population):${NC}"
# Populate cache
ls "$MOUNT_DIR" > /dev/null 2>&1
# Time 100 operations
time for i in {1..100}; do
    ls "$MOUNT_DIR" > /dev/null 2>&1
done
echo

# Final summary
echo -e "${GREEN}=== Test Complete ===${NC}"
echo
echo "Summary:"
echo "- The filesystem is mounted at: $MOUNT_DIR"
echo "- Backend directory: $BACKEND_DIR"
echo "- Cache TTL is set to 5 minutes by default"
echo
echo "To test cache expiry:"
echo "  1. Wait 5 minutes"
echo "  2. Run: ls -la $MOUNT_DIR"
echo "  3. You should see new [GETATTR] and [LOOKUP] messages"
echo
echo "To unmount manually: fusermount -u $MOUNT_DIR"
echo "Or press Ctrl+C to stop the test and cleanup"
echo

# Keep the script running
echo -e "${YELLOW}Press Enter to unmount and cleanup, or Ctrl+C to exit${NC}"
read

# Cleanup will be triggered by trap