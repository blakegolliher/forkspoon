# Makefile for Forkspoon

# Variables
BINARY_NAME=forkspoon
GO=go
GOFLAGS=-v
LDFLAGS=-ldflags="-s -w"
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
INSTALL_PATH=/usr/local/bin

# Build variables
BUILD_DIR=build
DIST_DIR=dist
CMD_DIR=cmd
PKG_DIR=pkg

# Platform-specific
GOOS?=$(shell go env GOOS)
GOARCH?=$(shell go env GOARCH)

# Default target
.PHONY: all
all: clean build

# Build the binary
.PHONY: build
build:
	@echo "Building $(BINARY_NAME) v$(VERSION)..."
	@mkdir -p $(BUILD_DIR)
	$(GO) build $(GOFLAGS) $(LDFLAGS) \
		-ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)" \
		-o $(BUILD_DIR)/$(BINARY_NAME) \
		./cmd/forkspoon

# Build for multiple platforms
.PHONY: build-all
build-all:
	@echo "Building for all platforms..."
	@mkdir -p $(DIST_DIR)
	# Linux AMD64
	GOOS=linux GOARCH=amd64 $(GO) build $(LDFLAGS) \
		-o $(DIST_DIR)/$(BINARY_NAME)-linux-amd64 ./cmd/forkspoon
	# Linux ARM64
	GOOS=linux GOARCH=arm64 $(GO) build $(LDFLAGS) \
		-o $(DIST_DIR)/$(BINARY_NAME)-linux-arm64 ./cmd/forkspoon

# Install the binary
.PHONY: install
install: build
	@echo "Installing to $(INSTALL_PATH)..."
	@sudo cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_PATH)/
	@sudo chmod 755 $(INSTALL_PATH)/$(BINARY_NAME)
	@echo "Installation complete!"

# Uninstall the binary
.PHONY: uninstall
uninstall:
	@echo "Removing $(BINARY_NAME) from $(INSTALL_PATH)..."
	@sudo rm -f $(INSTALL_PATH)/$(BINARY_NAME)
	@echo "Uninstall complete!"

# Run tests
.PHONY: test
test:
	@echo "Running tests..."
	$(GO) test -v ./...

# Run specific tests
.PHONY: test-cache
test-cache:
	@echo "Testing cache behavior..."
	./scripts/test_cache.sh

.PHONY: test-write
test-write:
	@echo "Testing write operations..."
	./scripts/test_writes.sh

.PHONY: test-benchmark
test-benchmark:
	@echo "Running benchmarks..."
	./scripts/benchmark.sh

# Run all tests including integration
.PHONY: test-all
test-all: test test-cache test-write test-benchmark
	@echo "All tests completed!"

# Code quality checks
.PHONY: lint
lint:
	@echo "Running linter..."
	@golangci-lint run ./... || true

.PHONY: fmt
fmt:
	@echo "Formatting code..."
	$(GO) fmt ./...

.PHONY: vet
vet:
	@echo "Running go vet..."
	$(GO) vet ./...

# Pre-commit checks
.PHONY: pre-commit
pre-commit: fmt vet lint test
	@echo "Pre-commit checks passed!"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@rm -f $(BINARY_NAME)
	$(GO) clean

# Deep clean including caches
.PHONY: clean-all
clean-all: clean
	@echo "Deep cleaning..."
	@rm -rf vendor/
	@rm -f go.sum
	$(GO) clean -modcache

# Dependencies
.PHONY: deps
deps:
	@echo "Downloading dependencies..."
	$(GO) mod download
	$(GO) mod tidy

.PHONY: deps-update
deps-update:
	@echo "Updating dependencies..."
	$(GO) get -u ./...
	$(GO) mod tidy

# Development setup
.PHONY: dev-setup
dev-setup: deps
	@echo "Setting up development environment..."
	@go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@go install golang.org/x/tools/cmd/goimports@latest
	@echo "Development setup complete!"

# Docker build
.PHONY: docker-build
docker-build:
	@echo "Building Docker image..."
	docker build -t $(BINARY_NAME):$(VERSION) .

.PHONY: docker-push
docker-push:
	@echo "Pushing Docker image..."
	docker tag $(BINARY_NAME):$(VERSION) ghcr.io/yourusername/$(BINARY_NAME):$(VERSION)
	docker push ghcr.io/yourusername/$(BINARY_NAME):$(VERSION)

# Release
.PHONY: release
release: clean build-all
	@echo "Creating release $(VERSION)..."
	@mkdir -p $(DIST_DIR)/release
	# Create archives
	@cd $(DIST_DIR) && tar -czf release/$(BINARY_NAME)-$(VERSION)-linux-amd64.tar.gz $(BINARY_NAME)-linux-amd64
	@cd $(DIST_DIR) && tar -czf release/$(BINARY_NAME)-$(VERSION)-linux-arm64.tar.gz $(BINARY_NAME)-linux-arm64
	# Generate checksums
	@cd $(DIST_DIR)/release && sha256sum *.tar.gz > checksums.txt
	@echo "Release artifacts created in $(DIST_DIR)/release"

# Run the program
.PHONY: run
run: build
	$(BUILD_DIR)/$(BINARY_NAME) \
		-backend /tmp/test-backend \
		-mountpoint /tmp/test-mount \
		-cache-ttl 5m \
		-verbose

# Quick development test
.PHONY: dev
dev: build
	@./scripts/quick_test.sh

# Show help
.PHONY: help
help:
	@echo "Forkspoon Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Clean and build (default)"
	@echo "  build        - Build the binary"
	@echo "  build-all    - Build for all platforms"
	@echo "  install      - Install to system"
	@echo "  uninstall    - Remove from system"
	@echo "  test         - Run unit tests"
	@echo "  test-all     - Run all tests"
	@echo "  lint         - Run linter"
	@echo "  fmt          - Format code"
	@echo "  clean        - Remove build artifacts"
	@echo "  deps         - Download dependencies"
	@echo "  docker-build - Build Docker image"
	@echo "  release      - Create release artifacts"
	@echo "  run          - Run with test configuration"
	@echo "  help         - Show this help"

# Default target
.DEFAULT_GOAL := help