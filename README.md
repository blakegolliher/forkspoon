# Forkspoon

A high-performance FUSE filesystem that provides aggressive metadata caching for slow backend storage while maintaining passthrough data operations.

[![Go Version](https://img.shields.io/badge/Go-1.21%2B-blue)](https://golang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)](https://www.kernel.org/)

## 🚀 Features

- **Aggressive Metadata Caching**: Reduces metadata operations by up to 90%
- **Passthrough Data Operations**: Zero overhead for actual file content
- **Configurable Cache TTL**: From seconds to hours based on your needs
- **Comprehensive Metrics**: Transaction logging and performance statistics
- **Production Ready**: systemd integration, monitoring, and health checks
- **Transparent Operation**: Works with any backend filesystem

## 📊 Performance

Typical performance improvements for metadata operations:

| Backend | Operation | Direct | Cached | Speedup |
|---------|-----------|--------|--------|---------|
| NFS | `ls -la` | 500ms | 50ms | **10x** |
| S3FS | `find .` | 30s | 2s | **15x** |
| HDD | `stat` | 15ms | 1ms | **15x** |

## 🎯 Use Cases

- **Slow Network Filesystems**: NFS, CIFS, S3FS
- **Development Environments**: Speed up builds and IDE operations
- **CI/CD Pipelines**: Accelerate repeated file access patterns
- **Home Directories**: Cache user profile data
- **Archive Access**: Infrequently changing data

## ⚡ Quick Start

```bash
# Install
wget -qO- https://github.com/yourusername/forkspoon/releases/latest/download/install.sh | bash

# Mount with 5-minute cache
forkspoon \
  -backend /mnt/slow-nfs \
  -mountpoint /mnt/fast-cache \
  -cache-ttl 5m

# Access files through cache
ls -la /mnt/fast-cache  # First access: Cache miss
ls -la /mnt/fast-cache  # Second access: Instant (from cache)
```

## 📦 Installation

### From Source

```bash
# Clone repository
git clone https://github.com/yourusername/forkspoon.git
cd forkspoon

# Build
make build

# Install (optional)
sudo make install
```

### Pre-built Binaries

Download from [Releases](https://github.com/yourusername/forkspoon/releases)

### Docker

```bash
docker run -v /source:/backend -v /cache:/mountpoint \
  --privileged ghcr.io/yourusername/forkspoon
```

## 🔧 Configuration

### Basic Options

```bash
forkspoon \
  -backend /source \           # Required: Backend directory
  -mountpoint /cache \          # Required: Mount point
  -cache-ttl 5m \              # Cache timeout (default: 5m)
  -verbose \                   # Enable verbose logging
  -trans-log /var/log/tx.log \ # Transaction log
  -stats-file stats.json       # Statistics output
```

### Cache TTL Guidelines

| Use Case | Recommended TTL |
|----------|-----------------|
| Development | 30s - 1m |
| Build Systems | 1m - 5m |
| Production | 5m - 10m |
| Archives | 30m - 1h |

## 📈 Monitoring

### Transaction Log

```bash
# View all operations
tail -f /var/log/cache-fuse/transactions.log

# Monitor cache misses
grep CACHE_MISS /var/log/cache-fuse/transactions.log

# Analyze patterns
awk -F'|' '{print $2, $3}' transactions.log | sort | uniq -c
```

### Statistics

```json
{
  "cache_ttl_seconds": 300,
  "cached_operations": {
    "getattr": {
      "hits": 45230,
      "misses": 1523,
      "hit_rate": 96.7
    },
    "lookup": {
      "hits": 23410,
      "misses": 892,
      "hit_rate": 96.3
    }
  },
  "passthrough_operations": {
    "read": 5234,
    "write": 1023,
    "create": 234
  }
}
```

## 🏗️ Architecture

```
┌──────────────┐
│  Application │
└──────┬───────┘
       │
┌──────▼────────────────────────┐
│     Linux VFS (Page Cache)     │
└──────┬────────────────────────┘
       │
┌──────▼────────────────────────┐
│         FUSE Kernel Module      │
└──────┬────────────────────────┘
       │
┌──────▼────────────────────────┐
│       Forkspoon Daemon      │
│  ┌─────────────┬─────────────┐ │
│  │  Metadata   │    Data      │ │
│  │  Caching    │ Passthrough  │ │
│  └─────────────┴─────────────┘ │
└──────┬────────────────────────┘
       │
┌──────▼────────────────────────┐
│        Backend Filesystem       │
└───────────────────────────────┘
```

### What Gets Cached

✅ **Cached (via kernel VFS)**:
- File attributes (size, permissions, timestamps)
- Directory entry lookups
- Directory listings

❌ **Not Cached (passthrough)**:
- File contents (read/write)
- File creation/deletion
- File modifications

## 🧪 Testing

```bash
# Run all tests
make test

# Specific tests
make test-cache      # Cache behavior
make test-write      # Write operations
make test-benchmark  # Performance comparison
```

## 🐛 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Permission denied | Add `user_allow_other` to `/etc/fuse.conf` |
| Transport endpoint not connected | `fusermount -u /mountpoint` and remount |
| High memory usage | Reduce cache TTL or clear kernel cache |
| Stale data | Reduce cache TTL for fresher data |

### Debug Mode

```bash
forkspoon \
  -backend /source \
  -mountpoint /cache \
  -verbose \
  -debug \
  -trans-log debug.log
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/yourusername/forkspoon.git

# Install development tools
make dev-setup

# Run tests before committing
make pre-commit
```

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🌟 Acknowledgments

- Built with [go-fuse](https://github.com/hanwen/go-fuse)
- Inspired by various caching filesystem implementations
- Thanks to all contributors!

## 📚 Documentation

- [Implementation Guide](IMPLEMENTATION_GUIDE.md) - Detailed setup and configuration
- [Performance Tuning](docs/TUNING.md) - Optimization strategies
- [API Reference](docs/API.md) - Programming interface
- [Benchmarks](benchmarks/README.md) - Performance tests

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/forkspoon/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/forkspoon/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/forkspoon/wiki)

---

**Star ⭐ this repo if you find it useful!**