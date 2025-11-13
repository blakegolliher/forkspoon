#!/bin/bash

# Script to initialize the Cache-FUSE-FS GitHub repository

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Cache-FUSE-FS Repository Initialization ===${NC}"
echo

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}Git is not installed. Please install git first.${NC}"
    exit 1
fi

# Initialize git repository
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    echo -e "${GREEN}✓ Repository initialized${NC}"
else
    echo -e "${YELLOW}Repository already initialized${NC}"
fi

# Add all files
echo "Adding files to repository..."
git add .
echo -e "${GREEN}✓ Files added${NC}"

# Create initial commit
echo "Creating initial commit..."
git commit -m "Initial commit: Cache-FUSE-FS - Metadata caching filesystem

- High-performance FUSE filesystem implementation
- Aggressive metadata caching with configurable TTL
- Full read/write support with passthrough data operations
- Comprehensive metrics and transaction logging
- Production-ready with systemd integration" || echo "Already committed"

echo -e "${GREEN}✓ Initial commit created${NC}"

# Instructions for GitHub
echo
echo -e "${BLUE}=== Next Steps ===${NC}"
echo
echo "1. Create a new repository on GitHub:"
echo "   https://github.com/new"
echo "   Name: cache-fuse-fs"
echo "   Description: High-performance FUSE filesystem with metadata caching"
echo
echo "2. Add the remote repository:"
echo -e "${YELLOW}   git remote add origin https://github.com/YOUR_USERNAME/cache-fuse-fs.git${NC}"
echo
echo "3. Push to GitHub:"
echo -e "${YELLOW}   git branch -M main"
echo "   git push -u origin main${NC}"
echo
echo "4. Create a release:"
echo -e "${YELLOW}   git tag -a v1.0.0 -m \"Initial release\""
echo "   git push origin v1.0.0${NC}"
echo
echo "5. Enable GitHub Actions for CI/CD (optional):"
echo "   - Go to Settings > Actions > General"
echo "   - Enable Actions for this repository"
echo
echo "6. Set up GitHub Pages for documentation (optional):"
echo "   - Go to Settings > Pages"
echo "   - Source: Deploy from a branch"
echo "   - Branch: main, folder: /docs"
echo
echo -e "${GREEN}Repository structure ready for GitHub!${NC}"

# Show repository structure
echo
echo -e "${BLUE}=== Repository Structure ===${NC}"
tree -L 2 -I 'go.sum|*.log' . 2>/dev/null || find . -maxdepth 2 -type f | head -20