#!/bin/bash

# Script to install Go for building the FUSE filesystem

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

GO_VERSION="1.21.5"
GO_ARCH="linux-amd64"
GO_URL="https://go.dev/dl/go${GO_VERSION}.${GO_ARCH}.tar.gz"
GO_TAR="go${GO_VERSION}.${GO_ARCH}.tar.gz"

echo -e "${BLUE}=== Go Installation Script ===${NC}"
echo

# Check if Go is already installed
if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | awk '{print $3}')
    echo -e "${YELLOW}Go is already installed: $CURRENT_VERSION${NC}"
    echo "Do you want to continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Check for required tools
echo "Checking prerequisites..."
for tool in wget tar; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}Error: $tool is not installed${NC}"
        echo "Please install $tool first:"
        echo "  sudo yum install $tool  # For RHEL/CentOS"
        echo "  sudo apt install $tool  # For Ubuntu/Debian"
        exit 1
    fi
done
echo -e "${GREEN}✓ Prerequisites met${NC}"

# Download Go
echo
echo "Downloading Go ${GO_VERSION}..."
if [ -f "$GO_TAR" ]; then
    echo -e "${YELLOW}Using existing download: $GO_TAR${NC}"
else
    wget "$GO_URL" -O "$GO_TAR"
    echo -e "${GREEN}✓ Download complete${NC}"
fi

# Verify download
if [ ! -f "$GO_TAR" ]; then
    echo -e "${RED}Error: Download failed${NC}"
    exit 1
fi

# Install Go
echo
echo "Installing Go to /usr/local/go..."
echo "This requires sudo access."

# Remove old installation if exists
if [ -d /usr/local/go ]; then
    echo "Removing old Go installation..."
    sudo rm -rf /usr/local/go
fi

# Extract new installation
sudo tar -C /usr/local -xzf "$GO_TAR"
echo -e "${GREEN}✓ Go installed to /usr/local/go${NC}"

# Set up PATH
echo
echo "Setting up PATH..."

# Detect shell
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    bash)
        RC_FILE="$HOME/.bashrc"
        ;;
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    *)
        RC_FILE="$HOME/.profile"
        ;;
esac

# Add Go to PATH if not already there
if ! grep -q "/usr/local/go/bin" "$RC_FILE" 2>/dev/null; then
    echo >> "$RC_FILE"
    echo "# Go programming language" >> "$RC_FILE"
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "$RC_FILE"
    echo 'export GOPATH=$HOME/go' >> "$RC_FILE"
    echo 'export PATH=$PATH:$GOPATH/bin' >> "$RC_FILE"
    echo -e "${GREEN}✓ Added Go to PATH in $RC_FILE${NC}"
else
    echo -e "${YELLOW}Go already in PATH${NC}"
fi

# Create Go workspace
mkdir -p "$HOME/go/"{bin,src,pkg}

# Export for current session
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Verify installation
echo
echo "Verifying installation..."
if /usr/local/go/bin/go version &> /dev/null; then
    echo -e "${GREEN}✓ Go installation successful!${NC}"
    echo
    /usr/local/go/bin/go version
    echo
    echo "Go workspace: $HOME/go"
    echo
    echo -e "${GREEN}Installation complete!${NC}"
    echo
    echo "To use Go in the current session, run:"
    echo -e "${YELLOW}  source $RC_FILE${NC}"
    echo
    echo "Or start a new terminal session."
    echo
    echo "To build the FUSE filesystem:"
    echo -e "${YELLOW}  source $RC_FILE${NC}"
    echo -e "${YELLOW}  go build -o forkspoon main.go${NC}"
    echo -e "${YELLOW}  ./quick_test.sh${NC}"
else
    echo -e "${RED}Error: Go installation verification failed${NC}"
    exit 1
fi

# Clean up
rm -f "$GO_TAR"