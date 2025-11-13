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
	DEFAULT_CACHE_TTL = 30 * time.Second // Changed to 30s for easier testing
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

// DirCacheEntry holds cached directory entries
type DirCacheEntry struct {
	entries []fuse.DirEntry
	expiry  time.Time
}

// DirCache is our in-memory directory cache
type DirCache struct {
	mu      sync.RWMutex
	entries map[string]*DirCacheEntry
}

// LookupCacheEntry holds cached lookup results
type LookupCacheEntry struct {
	inode  *fs.Inode
	entry  fuse.EntryOut
	expiry time.Time
}

// LookupCache caches LOOKUP operations
type LookupCache struct {
	mu      sync.RWMutex
	entries map[string]*LookupCacheEntry
}

// AttrCacheEntry holds cached getattr results
type AttrCacheEntry struct {
	attr   fuse.AttrOut
	expiry time.Time
}

// AttrCache caches GETATTR operations
type AttrCache struct {
	mu      sync.RWMutex
	entries map[string]*AttrCacheEntry
}

// Global configuration and metrics
var (
	cacheTTL     time.Duration
	verbose      bool
	metrics      = &CacheMetrics{startTime: time.Now()}
	transLog     *os.File
	transLogMu   sync.Mutex
	cacheLog     *RotatingLogger
	dirCache     = &DirCache{entries: make(map[string]*DirCacheEntry)}
	lookupCache  = &LookupCache{entries: make(map[string]*LookupCacheEntry)}
	attrCache    = &AttrCache{entries: make(map[string]*AttrCacheEntry)}
)

// Get retrieves cached directory entries if not expired
func (dc *DirCache) Get(path string) ([]fuse.DirEntry, bool) {
	dc.mu.RLock()
	defer dc.mu.RUnlock()

	entry, exists := dc.entries[path]
	if !exists {
		return nil, false
	}

	if time.Now().After(entry.expiry) {
		// Expired, remove it
		go dc.Remove(path)
		return nil, false
	}

	return entry.entries, true
}

// Put stores directory entries in cache
func (dc *DirCache) Put(path string, entries []fuse.DirEntry, ttl time.Duration) {
	dc.mu.Lock()
	defer dc.mu.Unlock()

	dc.entries[path] = &DirCacheEntry{
		entries: entries,
		expiry:  time.Now().Add(ttl),
	}
}

// Remove deletes a cache entry
func (dc *DirCache) Remove(path string) {
	dc.mu.Lock()
	defer dc.mu.Unlock()
	delete(dc.entries, path)
}

// Get retrieves cached lookup result
func (lc *LookupCache) Get(key string) (*LookupCacheEntry, bool) {
	lc.mu.RLock()
	defer lc.mu.RUnlock()

	entry, exists := lc.entries[key]
	if !exists {
		return nil, false
	}

	if time.Now().After(entry.expiry) {
		go lc.Remove(key)
		return nil, false
	}

	return entry, true
}

// Put stores lookup result in cache
func (lc *LookupCache) Put(key string, inode *fs.Inode, entry fuse.EntryOut, ttl time.Duration) {
	lc.mu.Lock()
	defer lc.mu.Unlock()

	lc.entries[key] = &LookupCacheEntry{
		inode:  inode,
		entry:  entry,
		expiry: time.Now().Add(ttl),
	}
}

// Remove deletes a lookup cache entry
func (lc *LookupCache) Remove(key string) {
	lc.mu.Lock()
	defer lc.mu.Unlock()
	delete(lc.entries, key)
}

// Get retrieves cached attr result
func (ac *AttrCache) Get(path string) (*fuse.AttrOut, bool) {
	ac.mu.RLock()
	defer ac.mu.RUnlock()

	entry, exists := ac.entries[path]
	if !exists {
		return nil, false
	}

	if time.Now().After(entry.expiry) {
		go ac.Remove(path)
		return nil, false
	}

	return &entry.attr, true
}

// Put stores attr result in cache
func (ac *AttrCache) Put(path string, attr fuse.AttrOut, ttl time.Duration) {
	ac.mu.Lock()
	defer ac.mu.Unlock()

	ac.entries[path] = &AttrCacheEntry{
		attr:   attr,
		expiry: time.Now().Add(ttl),
	}
}

// Remove deletes an attr cache entry
func (ac *AttrCache) Remove(path string) {
	ac.mu.Lock()
	defer ac.mu.Unlock()
	delete(ac.entries, path)
}

// logTransaction logs cache hits/misses and passthrough operations
func logTransaction(op string, path string, cached bool) {
	timestamp := time.Now().Format("2006-01-02 15:04:05.000")

	// Determine cache status
	cacheStatus := "PASSTHROUGH"
	if op == "GETATTR" || op == "LOOKUP" || op == "READDIR" {
		if cached {
			cacheStatus = "CACHE_HIT"
		} else {
			cacheStatus = "CACHE_MISS"
		}
	}

	// Log to rotating cache log
	if cacheLog != nil && (op == "GETATTR" || op == "LOOKUP" || op == "READDIR") {
		cacheLog.Write("%s | %-10s | %-12s | %s", timestamp, op, cacheStatus, path)
	}

	// Log everything to transaction log if enabled
	if transLog != nil {
		transLogMu.Lock()
		defer transLogMu.Unlock()
		fmt.Fprintf(transLog, "%s | %-10s | %-12s | %s\n", timestamp, op, cacheStatus, path)
	}
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

// Getattr for loopbackNode - NOW WITH CACHING!
func (n *loopbackNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	p := n.path()

	// Check cache first
	if cached, hit := attrCache.Get(p); hit {
		// Cache HIT!
		updateMetrics("GETATTR", true)
		logTransaction("GETATTR", p, true)

		if verbose {
			log.Printf("[GETATTR] CACHE HIT for: %s", p)
		}

		*out = *cached
		return 0
	}

	// Cache MISS - do actual getattr
	updateMetrics("GETATTR", false)
	logTransaction("GETATTR", p, false)

	if verbose {
		log.Printf("[GETATTR] CACHE MISS for: %s", p)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(p, &st)
	if err != nil {
		return fs.ToErrno(err)
	}
	out.FromStat(&st)

	// Set cache timeout - this enables kernel caching
	out.SetTimeout(cacheTTL)

	// Store in our cache
	attrCache.Put(p, *out, cacheTTL)

	if verbose {
		log.Printf("[GETATTR] Cached attributes for: %s (TTL: %v)", p, cacheTTL)
	}

	return 0
}

// Getattr for rootNode - NOW WITH CACHING!
func (r *rootNode) Getattr(ctx context.Context, f fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	// Check cache first
	if cached, hit := attrCache.Get(r.rootPath); hit {
		// Cache HIT!
		updateMetrics("GETATTR", true)
		logTransaction("GETATTR", r.rootPath, true)

		if verbose {
			log.Printf("[GETATTR] CACHE HIT for root: %s", r.rootPath)
		}

		*out = *cached
		return 0
	}

	// Cache MISS - do actual getattr
	updateMetrics("GETATTR", false)
	logTransaction("GETATTR", r.rootPath, false)

	if verbose {
		log.Printf("[GETATTR] CACHE MISS for root: %s", r.rootPath)
	}

	var st syscall.Stat_t
	err := syscall.Lstat(r.rootPath, &st)
	if err != nil {
		return fs.ToErrno(err)
	}
	out.FromStat(&st)

	out.SetTimeout(cacheTTL)

	// Store in our cache
	attrCache.Put(r.rootPath, *out, cacheTTL)

	if verbose {
		log.Printf("[GETATTR] Cached attributes for root (TTL: %v)", cacheTTL)
	}

	return 0
}

// Lookup for rootNode - NOW WITH CACHING!
func (r *rootNode) Lookup(ctx context.Context, name string, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(r.rootPath, name)
	cacheKey := p

	// Check cache first
	if cached, hit := lookupCache.Get(cacheKey); hit {
		// Cache HIT!
		updateMetrics("LOOKUP", true)
		logTransaction("LOOKUP", name, true)

		if verbose {
			log.Printf("[LOOKUP] CACHE HIT for: %s", name)
		}

		// Use cached attributes
		*out = cached.entry
		return cached.inode, 0
	}

	// Cache MISS - do actual lookup
	updateMetrics("LOOKUP", false)
	logTransaction("LOOKUP", name, false)

	if verbose {
		log.Printf("[LOOKUP] CACHE MISS for: %s", name)
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
		log.Printf("[LOOKUP] Caching entry for: %s (TTL: %v)", name, cacheTTL)
	}

	node := &loopbackNode{}
	inode := r.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino})

	// Store in cache
	lookupCache.Put(cacheKey, inode, *out, cacheTTL)

	return inode, 0
}

// Lookup for loopbackNode - NOW WITH CACHING!
func (n *loopbackNode) Lookup(ctx context.Context, name string, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := filepath.Join(n.path(), name)
	cacheKey := p

	// Check cache first
	if cached, hit := lookupCache.Get(cacheKey); hit {
		// Cache HIT!
		updateMetrics("LOOKUP", true)
		logTransaction("LOOKUP", p, true)

		if verbose {
			log.Printf("[LOOKUP] CACHE HIT for: %s/%s", n.path(), name)
		}

		// Use cached attributes
		*out = cached.entry
		return cached.inode, 0
	}

	// Cache MISS - do actual lookup
	updateMetrics("LOOKUP", false)
	logTransaction("LOOKUP", p, false)

	if verbose {
		log.Printf("[LOOKUP] CACHE MISS for: %s/%s", n.path(), name)
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
		log.Printf("[LOOKUP] Caching entry for: %s (TTL: %v)", name, cacheTTL)
	}

	node := &loopbackNode{}
	inode := n.NewInode(ctx, node, fs.StableAttr{Mode: st.Mode, Ino: st.Ino})

	// Store in cache
	lookupCache.Put(cacheKey, inode, *out, cacheTTL)

	return inode, 0
}

// CachedDirStream wraps directory entries for caching
type CachedDirStream struct {
	entries []fuse.DirEntry
	index   int
}

func (s *CachedDirStream) HasNext() bool {
	return s.index < len(s.entries)
}

func (s *CachedDirStream) Next() (fuse.DirEntry, syscall.Errno) {
	if !s.HasNext() {
		return fuse.DirEntry{}, syscall.ENOENT
	}
	entry := s.entries[s.index]
	s.index++
	return entry, 0
}

func (s *CachedDirStream) Close() {}

// Readdir - NOW WITH ACTUAL CACHING!
func (n *loopbackNode) Readdir(ctx context.Context) (fs.DirStream, syscall.Errno) {
	dirPath := n.path()

	// Check cache first
	if cachedEntries, hit := dirCache.Get(dirPath); hit {
		// Cache HIT!
		updateMetrics("READDIR", true)
		logTransaction("READDIR", dirPath, true)

		if verbose {
			log.Printf("[READDIR] CACHE HIT for: %s", dirPath)
		}

		// Return cached entries
		return &CachedDirStream{entries: cachedEntries}, 0
	}

	// Cache MISS - read from filesystem
	updateMetrics("READDIR", false)
	logTransaction("READDIR", dirPath, false)

	if verbose {
		log.Printf("[READDIR] CACHE MISS for: %s", dirPath)
	}

	// Read directory entries
	f, err := os.Open(dirPath)
	if err != nil {
		return nil, fs.ToErrno(err)
	}
	defer f.Close()

	entries, err := f.Readdir(-1)
	if err != nil {
		return nil, fs.ToErrno(err)
	}

	// Convert to fuse.DirEntry and cache
	fuseEntries := make([]fuse.DirEntry, 0, len(entries))
	for _, e := range entries {
		var stat syscall.Stat_t
		if err := syscall.Lstat(filepath.Join(dirPath, e.Name()), &stat); err == nil {
			fuseEntries = append(fuseEntries, fuse.DirEntry{
				Name: e.Name(),
				Mode: uint32(stat.Mode),
				Ino:  stat.Ino,
			})
		}
	}

	// Store in cache
	dirCache.Put(dirPath, fuseEntries, cacheTTL)

	if verbose {
		log.Printf("[READDIR] Cached %d entries for: %s (TTL: %v)", len(fuseEntries), dirPath, cacheTTL)
	}

	return &CachedDirStream{entries: fuseEntries}, 0
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

	// Initialize rotating cache log
	// Use home directory if /opt/forkspoon is not writable
	logPath := "/opt/forkspoon/forkspoon.log"
	if _, err := os.Stat("/opt/forkspoon"); os.IsNotExist(err) {
		// Try to create the directory
		if err := os.MkdirAll("/opt/forkspoon", 0755); err != nil {
			// Fall back to home directory
			homeDir, _ := os.UserHomeDir()
			logPath = filepath.Join(homeDir, "forkspoon.log")
			log.Printf("Using fallback log location: %s", logPath)
		}
	}
	cacheLog, err = NewRotatingLogger(logPath)
	if err != nil {
		log.Printf("Warning: Failed to create rotating cache log: %v", err)
		// Continue without rotating log
	} else {
		defer cacheLog.Close()
		cacheLog.WriteHeader(*backendPtr, *mountpointPtr, cacheTTL)
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

	// Mount options - CRITICAL: Set non-zero defaults to enable caching
	opts := &fs.Options{
		// These are the DEFAULT timeouts. Individual operations can override them.
		// Setting these to non-zero enables kernel caching!
		AttrTimeout:     &cacheTTL,
		EntryTimeout:    &cacheTTL,
		NegativeTimeout: &cacheTTL,

		MountOptions: fuse.MountOptions{
			AllowOther: *allowOtherPtr,
			FsName:     "forkspoon-cache",
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
	log.Println("Forkspoon Caching FUSE Filesystem v2.0")
	log.Printf("Built: %s", time.Now().Format("2006-01-02 15:04:05"))
	log.Println("==========================================")
	log.Printf("Backend:     %s", *backendPtr)
	log.Printf("Mount:       %s", *mountpointPtr)
	log.Printf("Cache TTL:   %v", cacheTTL)
	log.Printf("Cache Log:   %s", logPath)
	if *transLogPtr != "" {
		log.Printf("Trans Log:   %s", *transLogPtr)
	}
	log.Println("==========================================")
	log.Println("Caching Strategy:")
	log.Println("  • LOOKUP: In-memory cache (fixes wildcard issue!)")
	log.Println("  • GETATTR: In-memory cache")
	log.Println("  • READDIR: In-memory cache")
	log.Println("  • All cache hits/misses are logged!")
	log.Println("==========================================")

	// Start metrics reporter
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			totalHits := metrics.GetattrHits + metrics.LookupHits + metrics.ReaddirHits
			totalMisses := metrics.GetattrMisses + metrics.LookupMisses + metrics.ReaddirMisses
			total := totalHits + totalMisses

			if total > 0 {
				hitRate := float64(totalHits) * 100 / float64(total)
				log.Printf("Cache Stats: %d ops (%.1f%% hit rate) | Hits: %d | Misses: %d | READDIR H:%d/M:%d",
					total, hitRate, totalHits, totalMisses,
					metrics.ReaddirHits, metrics.ReaddirMisses)
			}
		}
	}()

	log.Println("Press Ctrl+C to unmount and see statistics")

	// Wait for unmount
	server.Wait()
}