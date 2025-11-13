package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"
)

const (
	// Default cache metadata TTL
	DEFAULT_CACHE_TTL = 5 * time.Minute
)

// CacheMetrics tracks cache hit/miss statistics
type CacheMetrics struct {
	GetattrHits    uint64
	GetattrMisses  uint64
	LookupHits     uint64
	LookupMisses   uint64
	ReaddirHits    uint64
	ReaddirMisses  uint64

	// Passthrough operations (never cached)
	OpenOps        uint64
	CreateOps      uint64
	WriteOps       uint64
	ReadOps        uint64
	UnlinkOps      uint64
	RenameOps      uint64
	MkdirOps       uint64
	RmdirOps       uint64

	mu sync.RWMutex
	startTime time.Time
}

// Global configuration and metrics
var (
	cacheTTL     time.Duration
	verbose      bool
	metrics      = &CacheMetrics{startTime: time.Now()}
	transLog     *os.File
	transLogMu   sync.Mutex
)

// logTransaction logs cache hits/misses and passthrough operations
func logTransaction(op string, path string, cached bool) {
	if transLog == nil {
		return
	}

	transLogMu.Lock()
	defer transLogMu.Unlock()

	timestamp := time.Now().Format("2006-01-02 15:04:05.000")
	cacheStatus := "PASSTHROUGH"
	if cached {
		cacheStatus = "CACHE_HIT"
	} else if op == "GETATTR" || op == "LOOKUP" || op == "READDIR" {
		cacheStatus = "CACHE_MISS"
	}

	fmt.Fprintf(transLog, "%s | %-10s | %-12s | %s\n", timestamp, op, cacheStatus, path)
}

// updateMetrics updates the cache metrics
func updateMetrics(op string, hit bool) {
	switch op {
	case "GETATTR":
		if hit {
			atomic.AddUint64(&metrics.GetattrHits, 1)
		} else {
			atomic.AddUint64(&metrics.GetattrMisses, 1)
		}
	case "LOOKUP":
		if hit {
			atomic.AddUint64(&metrics.LookupHits, 1)
		} else {
			atomic.AddUint64(&metrics.LookupMisses, 1)
		}
	case "READDIR":
		if hit {
			atomic.AddUint64(&metrics.ReaddirHits, 1)
		} else {
			atomic.AddUint64(&metrics.ReaddirMisses, 1)
		}
	case "OPEN":
		atomic.AddUint64(&metrics.OpenOps, 1)
	case "CREATE":
		atomic.AddUint64(&metrics.CreateOps, 1)
	case "WRITE":
		atomic.AddUint64(&metrics.WriteOps, 1)
	case "READ":
		atomic.AddUint64(&metrics.ReadOps, 1)
	case "UNLINK":
		atomic.AddUint64(&metrics.UnlinkOps, 1)
	case "RENAME":
		atomic.AddUint64(&metrics.RenameOps, 1)
	case "MKDIR":
		atomic.AddUint64(&metrics.MkdirOps, 1)
	case "RMDIR":
		atomic.AddUint64(&metrics.RmdirOps, 1)
	}
}

// getHitRate calculates hit rate for an operation
func getHitRate(hits, misses uint64) float64 {
	total := hits + misses
	if total == 0 {
		return 0
	}
	return float64(hits) * 100 / float64(total)
}

// PrintStatistics prints cache statistics
func PrintStatistics() {
	metrics.mu.RLock()
	defer metrics.mu.RUnlock()

	elapsed := time.Since(metrics.startTime)

	fmt.Println("\n=== Cache Statistics ===")
	fmt.Printf("Uptime: %v\n", elapsed.Round(time.Second))
	fmt.Println("\nCached Operations (with hit rates):")
	fmt.Printf("  GETATTR: %d hits, %d misses (%.1f%% hit rate)\n",
		metrics.GetattrHits, metrics.GetattrMisses,
		getHitRate(metrics.GetattrHits, metrics.GetattrMisses))
	fmt.Printf("  LOOKUP:  %d hits, %d misses (%.1f%% hit rate)\n",
		metrics.LookupHits, metrics.LookupMisses,
		getHitRate(metrics.LookupHits, metrics.LookupMisses))
	fmt.Printf("  READDIR: %d hits, %d misses (%.1f%% hit rate)\n",
		metrics.ReaddirHits, metrics.ReaddirMisses,
		getHitRate(metrics.ReaddirHits, metrics.ReaddirMisses))

	fmt.Println("\nPassthrough Operations (never cached):")
	fmt.Printf("  OPEN:    %d operations\n", metrics.OpenOps)
	fmt.Printf("  CREATE:  %d operations\n", metrics.CreateOps)
	fmt.Printf("  WRITE:   %d operations\n", metrics.WriteOps)
	fmt.Printf("  READ:    %d operations\n", metrics.ReadOps)
	fmt.Printf("  UNLINK:  %d operations\n", metrics.UnlinkOps)
	fmt.Printf("  RENAME:  %d operations\n", metrics.RenameOps)
	fmt.Printf("  MKDIR:   %d operations\n", metrics.MkdirOps)
	fmt.Printf("  RMDIR:   %d operations\n", metrics.RmdirOps)

	totalCached := metrics.GetattrHits + metrics.GetattrMisses +
		metrics.LookupHits + metrics.LookupMisses +
		metrics.ReaddirHits + metrics.ReaddirMisses
	totalCacheHits := metrics.GetattrHits + metrics.LookupHits + metrics.ReaddirHits

	fmt.Printf("\nOverall Cache Hit Rate: %.1f%%\n",
		getHitRate(totalCacheHits, totalCached-totalCacheHits))
}

// SaveStatisticsJSON saves statistics to JSON file
func SaveStatisticsJSON(filename string) error {
	metrics.mu.RLock()
	defer metrics.mu.RUnlock()

	stats := map[string]interface{}{
		"timestamp": time.Now().Format(time.RFC3339),
		"uptime_seconds": time.Since(metrics.startTime).Seconds(),
		"cache_ttl_seconds": cacheTTL.Seconds(),
		"cached_operations": map[string]interface{}{
			"getattr": map[string]interface{}{
				"hits": metrics.GetattrHits,
				"misses": metrics.GetattrMisses,
				"hit_rate": getHitRate(metrics.GetattrHits, metrics.GetattrMisses),
			},
			"lookup": map[string]interface{}{
				"hits": metrics.LookupHits,
				"misses": metrics.LookupMisses,
				"hit_rate": getHitRate(metrics.LookupHits, metrics.LookupMisses),
			},
			"readdir": map[string]interface{}{
				"hits": metrics.ReaddirHits,
				"misses": metrics.ReaddirMisses,
				"hit_rate": getHitRate(metrics.ReaddirHits, metrics.ReaddirMisses),
			},
		},
		"passthrough_operations": map[string]uint64{
			"open": metrics.OpenOps,
			"create": metrics.CreateOps,
			"write": metrics.WriteOps,
			"read": metrics.ReadOps,
			"unlink": metrics.UnlinkOps,
			"rename": metrics.RenameOps,
			"mkdir": metrics.MkdirOps,
			"rmdir": metrics.RmdirOps,
		},
	}

	data, err := json.MarshalIndent(stats, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(filename, data, 0644)
}

// loopbackNode is a filesystem node that passes through to an underlying path
type loopbackNode struct {
	fs.Inode
}

// rootNode is the root of the loopback filesystem
type rootNode struct {
	fs.Inode
	rootPath string
}

// Path helpers
func (r *rootNode) path() string {
	return r.rootPath
}

func (n *loopbackNode) path() string {
	path := n.Path(n.Root())
	root := n.Root().Operations().(*rootNode)
	return filepath.Join(root.rootPath, path)
}

// ============ METADATA OPERATIONS (CACHED) ============

// Getattr for loopbackNode - CACHED
func (n *loopbackNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	p := n.path()

	// This is always a cache miss when called (kernel cache expired)
	updateMetrics("GETATTR", false)
	logTransaction("GETATTR", p, false)

	if verbose {
		log.Printf("[GETATTR] Cache miss for: %s", p)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(p, &st)
	if err != nil {
		return fs.ToErrno(err)
	}
	out.FromStat(&st)

	// Set cache timeout - this enables kernel caching
	out.SetTimeout(cacheTTL)
	if verbose {
		log.Printf("[GETATTR] Setting cache TTL to %v for: %s", cacheTTL, p)
	}

	return 0
}

// Getattr for rootNode - CACHED
func (r *rootNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	updateMetrics("GETATTR", false)
	logTransaction("GETATTR", r.rootPath, false)

	if verbose {
		log.Printf("[GETATTR] Cache miss for root: %s", r.rootPath)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(r.rootPath, &st)
	if err != nil {
		return fs.ToErrno(err)
	}
	out.FromStat(&st)

	out.SetTimeout(cacheTTL)
	if verbose {
		log.Printf("[GETATTR] Setting cache TTL to %v for root", cacheTTL)
	}

	return 0
}

// Lookup for rootNode - CACHED
func (r *rootNode) Lookup(ctx context.Context, name string, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(r.rootPath, name)

	updateMetrics("LOOKUP", false)
	logTransaction("LOOKUP", name, false)

	if verbose {
		log.Printf("[LOOKUP] Cache miss for: %s", name)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(p, &st)
	if err != nil {
		return nil, fs.ToErrno(err)
	}

	out.FromStat(&st)

	// Set cache timeouts - enables kernel caching
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	if verbose {
		log.Printf("[LOOKUP] Setting cache TTL to %v for: %s", cacheTTL, name)
	}

	node := &loopbackNode{}
	return r.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}), 0
}

// Lookup for loopbackNode - CACHED
func (n *loopbackNode) Lookup(ctx context.Context, name string, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(n.path(), name)

	updateMetrics("LOOKUP", false)
	logTransaction("LOOKUP", p, false)

	if verbose {
		log.Printf("[LOOKUP] Cache miss for: %s/%s", n.path(), name)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(p, &st)
	if err != nil {
		return nil, fs.ToErrno(err)
	}

	out.FromStat(&st)
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	if verbose {
		log.Printf("[LOOKUP] Setting cache TTL to %v for: %s", cacheTTL, name)
	}

	node := &loopbackNode{}
	return n.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}), 0
}

// Readdir - CACHED through Getattr
func (n *loopbackNode) Readdir(ctx context.Context) (fs.DirStream, syscall.Errno) {
	updateMetrics("READDIR", false)
	logTransaction("READDIR", n.path(), false)

	if verbose {
		log.Printf("[READDIR] Directory: %s", n.path())
	}

	return fs.NewLoopbackDirStream(n.path())
}

// ============ DATA OPERATIONS (PASSTHROUGH - NEVER CACHED) ============

// Open - PASSTHROUGH
func (n *loopbackNode) Open(ctx context.Context, flags uint32) (fs.FileHandle, uint32, syscall.Errno) {
	p := n.path()

	updateMetrics("OPEN", false)
	logTransaction("OPEN", p, false)

	if verbose {
		log.Printf("[OPEN] File: %s with flags: %d", p, flags)
	}

	f, err := syscall.Open(p, int(flags), 0)
	if err != nil {
		return nil, 0, fs.ToErrno(err)
	}

	return &loopbackFile{fd: f, path: p}, 0, 0
}

// Create for rootNode - PASSTHROUGH
func (r *rootNode) Create(ctx context.Context, name string, flags uint32, mode uint32, out *fuse.EntryOut) (inode *fs.Inode, fh fs.FileHandle, fuseFlags uint32, errno syscall.Errno) {
	p := filepath.Join(r.rootPath, name)

	updateMetrics("CREATE", false)
	logTransaction("CREATE", p, false)

	if verbose {
		log.Printf("[CREATE] File: %s", p)
	}

	fd, err := syscall.Open(p, int(flags)|os.O_CREATE, mode)
	if err != nil {
		return nil, nil, 0, fs.ToErrno(err)
	}

	var st syscall.Stat_t
	if err := syscall.Fstat(fd, &st); err != nil {
		syscall.Close(fd)
		return nil, nil, 0, fs.ToErrno(err)
	}

	out.FromStat(&st)
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	node := &loopbackNode{}
	return r.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}),
		&loopbackFile{fd: fd, path: p}, 0, 0
}

// Create for loopbackNode - PASSTHROUGH
func (n *loopbackNode) Create(ctx context.Context, name string, flags uint32, mode uint32, out *fuse.EntryOut) (inode *fs.Inode, fh fs.FileHandle, fuseFlags uint32, errno syscall.Errno) {
	p := filepath.Join(n.path(), name)

	updateMetrics("CREATE", false)
	logTransaction("CREATE", p, false)

	if verbose {
		log.Printf("[CREATE] File: %s/%s", n.path(), name)
	}

	fd, err := syscall.Open(p, int(flags)|os.O_CREATE, mode)
	if err != nil {
		return nil, nil, 0, fs.ToErrno(err)
	}

	var st syscall.Stat_t
	if err := syscall.Fstat(fd, &st); err != nil {
		syscall.Close(fd)
		return nil, nil, 0, fs.ToErrno(err)
	}

	out.FromStat(&st)
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	node := &loopbackNode{}
	return n.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}),
		&loopbackFile{fd: fd, path: p}, 0, 0
}

// Mkdir for rootNode - PASSTHROUGH
func (r *rootNode) Mkdir(ctx context.Context, name string, mode uint32, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(r.rootPath, name)

	updateMetrics("MKDIR", false)
	logTransaction("MKDIR", p, false)

	if verbose {
		log.Printf("[MKDIR] Directory: %s", p)
	}

	err := syscall.Mkdir(p, mode)
	if err != nil {
		return nil, fs.ToErrno(err)
	}

	var st syscall.Stat_t
	if err := syscall.Lstat(p, &st); err != nil {
		return nil, fs.ToErrno(err)
	}

	out.FromStat(&st)
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	node := &loopbackNode{}
	return r.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}), 0
}

// Mkdir for loopbackNode - PASSTHROUGH
func (n *loopbackNode) Mkdir(ctx context.Context, name string, mode uint32, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(n.path(), name)

	updateMetrics("MKDIR", false)
	logTransaction("MKDIR", p, false)

	if verbose {
		log.Printf("[MKDIR] Directory: %s/%s", n.path(), name)
	}

	err := syscall.Mkdir(p, mode)
	if err != nil {
		return nil, fs.ToErrno(err)
	}

	var st syscall.Stat_t
	if err := syscall.Lstat(p, &st); err != nil {
		return nil, fs.ToErrno(err)
	}

	out.FromStat(&st)
	out.SetEntryTimeout(cacheTTL)
	out.SetAttrTimeout(cacheTTL)

	node := &loopbackNode{}
	return n.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino}), 0
}

// Unlink for rootNode - PASSTHROUGH
func (r *rootNode) Unlink(ctx context.Context, name string) syscall.Errno {
	p := filepath.Join(r.rootPath, name)

	updateMetrics("UNLINK", false)
	logTransaction("UNLINK", p, false)

	if verbose {
		log.Printf("[UNLINK] File: %s", p)
	}

	err := syscall.Unlink(p)
	return fs.ToErrno(err)
}

// Unlink for loopbackNode - PASSTHROUGH
func (n *loopbackNode) Unlink(ctx context.Context, name string) syscall.Errno {
	p := filepath.Join(n.path(), name)

	updateMetrics("UNLINK", false)
	logTransaction("UNLINK", p, false)

	if verbose {
		log.Printf("[UNLINK] File: %s/%s", n.path(), name)
	}

	err := syscall.Unlink(p)
	return fs.ToErrno(err)
}

// Rmdir for rootNode - PASSTHROUGH
func (r *rootNode) Rmdir(ctx context.Context, name string) syscall.Errno {
	p := filepath.Join(r.rootPath, name)

	updateMetrics("RMDIR", false)
	logTransaction("RMDIR", p, false)

	if verbose {
		log.Printf("[RMDIR] Directory: %s", p)
	}

	err := syscall.Rmdir(p)
	return fs.ToErrno(err)
}

// Rmdir for loopbackNode - PASSTHROUGH
func (n *loopbackNode) Rmdir(ctx context.Context, name string) syscall.Errno {
	p := filepath.Join(n.path(), name)

	updateMetrics("RMDIR", false)
	logTransaction("RMDIR", p, false)

	if verbose {
		log.Printf("[RMDIR] Directory: %s/%s", n.path(), name)
	}

	err := syscall.Rmdir(p)
	return fs.ToErrno(err)
}

// Rename for rootNode - PASSTHROUGH
func (r *rootNode) Rename(ctx context.Context, name string, newParent fs.InodeEmbedder, newName string, flags uint32) syscall.Errno {
	oldPath := filepath.Join(r.rootPath, name)
	newPath := ""

	switch parent := newParent.(type) {
	case *rootNode:
		newPath = filepath.Join(parent.rootPath, newName)
	case *loopbackNode:
		newPath = filepath.Join(parent.path(), newName)
	}

	updateMetrics("RENAME", false)
	logTransaction("RENAME", fmt.Sprintf("%s -> %s", oldPath, newPath), false)

	if verbose {
		log.Printf("[RENAME] From: %s To: %s", oldPath, newPath)
	}

	err := syscall.Rename(oldPath, newPath)
	return fs.ToErrno(err)
}

// Rename for loopbackNode - PASSTHROUGH
func (n *loopbackNode) Rename(ctx context.Context, name string, newParent fs.InodeEmbedder, newName string, flags uint32) syscall.Errno {
	oldPath := filepath.Join(n.path(), name)
	newPath := ""

	switch parent := newParent.(type) {
	case *rootNode:
		newPath = filepath.Join(parent.rootPath, newName)
	case *loopbackNode:
		newPath = filepath.Join(parent.path(), newName)
	}

	updateMetrics("RENAME", false)
	logTransaction("RENAME", fmt.Sprintf("%s -> %s", oldPath, newPath), false)

	if verbose {
		log.Printf("[RENAME] From: %s To: %s", oldPath, newPath)
	}

	err := syscall.Rename(oldPath, newPath)
	return fs.ToErrno(err)
}

// loopbackFile represents an open file
type loopbackFile struct {
	fd   int
	path string
}

// Read - PASSTHROUGH
func (f *loopbackFile) Read(ctx context.Context, dest []byte, off int64) (fuse.ReadResult, syscall.Errno) {
	updateMetrics("READ", false)
	logTransaction("READ", f.path, false)

	n, err := syscall.Pread(f.fd, dest, off)
	if err != nil {
		return nil, fs.ToErrno(err)
	}
	return fuse.ReadResultData(dest[:n]), 0
}

// Write - PASSTHROUGH
func (f *loopbackFile) Write(ctx context.Context, data []byte, off int64) (written uint32, errno syscall.Errno) {
	updateMetrics("WRITE", false)
	logTransaction("WRITE", f.path, false)

	n, err := syscall.Pwrite(f.fd, data, off)
	return uint32(n), fs.ToErrno(err)
}

// Release closes the file
func (f *loopbackFile) Release(ctx context.Context) syscall.Errno {
	err := syscall.Close(f.fd)
	return fs.ToErrno(err)
}

// Opendir - Required for directory operations
func (n *loopbackNode) Opendir(ctx context.Context) syscall.Errno {
	if verbose {
		log.Printf("[OPENDIR] Directory: %s", n.path())
	}
	return 0
}

func main() {
	// Command-line flags
	backendPtr := flag.String("backend", "", "Path to the backend directory (required)")
	mountpointPtr := flag.String("mountpoint", "", "Path to the mount point directory (required)")
	verbosePtr := flag.Bool("verbose", false, "Enable verbose logging")
	debugPtr := flag.Bool("debug", false, "Enable FUSE debug logging")
	cacheTTLPtr := flag.Duration("cache-ttl", DEFAULT_CACHE_TTL, "Cache TTL duration (e.g., 5m, 30s)")
	allowOtherPtr := flag.Bool("allow-other", false, "Allow other users to access the mount")
	transLogPtr := flag.String("trans-log", "", "Transaction log file path")
	statsFilePtr := flag.String("stats-file", "", "Save statistics to JSON file on exit")

	flag.Parse()

	// Set global configuration
	cacheTTL = *cacheTTLPtr
	verbose = *verbosePtr

	// Validate required flags
	if *backendPtr == "" || *mountpointPtr == "" {
		fmt.Fprintf(os.Stderr, "Usage: %s -backend <dir> -mountpoint <dir> [options]\n", os.Args[0])
		flag.PrintDefaults()
		os.Exit(1)
	}

	// Check backend
	backendInfo, err := os.Stat(*backendPtr)
	if err != nil {
		log.Fatalf("Backend directory error: %v", err)
	}
	if !backendInfo.IsDir() {
		log.Fatalf("Backend path is not a directory: %s", *backendPtr)
	}

	// Create/check mountpoint
	if err := os.MkdirAll(*mountpointPtr, 0755); err != nil {
		log.Fatalf("Failed to create mountpoint: %v", err)
	}

	// Open transaction log if requested
	if *transLogPtr != "" {
		var err error
		transLog, err = os.OpenFile(*transLogPtr, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			log.Fatalf("Failed to open transaction log: %v", err)
		}
		defer transLog.Close()

		// Write header
		fmt.Fprintln(transLog, "=== FUSE Cache Transaction Log ===")
		fmt.Fprintf(transLog, "Started: %s\n", time.Now().Format(time.RFC3339))
		fmt.Fprintf(transLog, "Backend: %s\n", *backendPtr)
		fmt.Fprintf(transLog, "Mount: %s\n", *mountpointPtr)
		fmt.Fprintf(transLog, "Cache TTL: %v\n", cacheTTL)
		fmt.Fprintln(transLog, "==========================================")
		fmt.Fprintln(transLog, "Timestamp              | Operation  | Status       | Path")
		fmt.Fprintln(transLog, "---------------------- | ---------- | ------------ | ----")
	}

	// Create root node
	root := &rootNode{
		rootPath: *backendPtr,
	}

	// Mount options
	zeroTimeout := time.Duration(0)
	opts := &fs.Options{
		AttrTimeout:     &zeroTimeout,
		EntryTimeout:    &zeroTimeout,
		NegativeTimeout: cacheTTLPtr,

		MountOptions: fuse.MountOptions{
			AllowOther: *allowOtherPtr,
			FsName:     "my-cache-fs",
			Debug:      *debugPtr,
		},
	}

	// Mount filesystem
	server, err := fs.Mount(*mountpointPtr, root, opts)
	if err != nil {
		log.Fatalf("Mount failed: %v", err)
	}

	// Setup cleanup
	defer func() {
		server.Unmount()
		PrintStatistics()

		if *statsFilePtr != "" {
			if err := SaveStatisticsJSON(*statsFilePtr); err != nil {
				log.Printf("Failed to save statistics: %v", err)
			} else {
				log.Printf("Statistics saved to: %s", *statsFilePtr)
			}
		}
	}()

	log.Println("==========================================")
	log.Println("Caching FUSE Filesystem Mounted")
	log.Println("==========================================")
	log.Printf("Backend:     %s", *backendPtr)
	log.Printf("Mount:       %s", *mountpointPtr)
	log.Printf("Cache TTL:   %v", cacheTTL)
	if *transLogPtr != "" {
		log.Printf("Trans Log:   %s", *transLogPtr)
	}
	log.Println("==========================================")
	log.Println("What's Being Cached:")
	log.Println("  • File/Directory attributes (stat)")
	log.Println("  • Directory entry lookups")
	log.Println("  • Directory listings")
	log.Println("What's NOT Cached (passthrough):")
	log.Println("  • File contents (read/write)")
	log.Println("  • File modifications")
	log.Println("==========================================")
	log.Println("Press Ctrl+C to unmount and see statistics")

	// Wait for unmount
	server.Wait()
}