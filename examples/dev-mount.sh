#!/bin/bash

# Example: Development environment with fast metadata caching
# Speeds up IDE operations, builds, and file browsing

# Configuration
PROJECT_DIR="$HOME/projects/large-codebase"
CACHE_DIR="/tmp/dev-cache"
CACHE_TTL="30s"  # Short TTL for development

# Check if project exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Create cache directory
mkdir -p "$CACHE_DIR"

# Mount with development-optimized settings
echo "Mounting development cache..."
forkspoon \
    -backend "$PROJECT_DIR" \
    -mountpoint "$CACHE_DIR" \
    -cache-ttl "$CACHE_TTL" \
    -verbose

echo "================================"
echo "Development cache mounted!"
echo "Original:  $PROJECT_DIR"
echo "Cached:    $CACHE_DIR"
echo "Cache TTL: $CACHE_TTL"
echo "================================"
echo ""
echo "Usage examples:"
echo "  cd $CACHE_DIR"
echo "  find . -name '*.go'  # Fast repeated searches"
echo "  git status           # Cached stat operations"
echo "  make build           # Faster dependency checks"
echo ""
echo "Note: Changes are immediately visible but metadata is cached for $CACHE_TTL"