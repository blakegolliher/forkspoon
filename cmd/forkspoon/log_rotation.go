package main

import (
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	MAX_LOG_SIZE   = 2 * 1024 * 1024 * 1024 // 2GB
	MAX_OLD_FILES  = 6
	LOG_CHECK_INTERVAL = 30 * time.Second
)

type RotatingLogger struct {
	mu          sync.Mutex
	file        *os.File
	path        string
	currentSize int64
	maxSize     int64
	maxBackups  int
}

func NewRotatingLogger(path string) (*RotatingLogger, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create log directory: %v", err)
	}

	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file: %v", err)
	}

	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, fmt.Errorf("failed to stat log file: %v", err)
	}

	logger := &RotatingLogger{
		file:        file,
		path:        path,
		currentSize: info.Size(),
		maxSize:     MAX_LOG_SIZE,
		maxBackups:  MAX_OLD_FILES,
	}

	// Start rotation checker
	go logger.rotationChecker()

	return logger, nil
}

func (l *RotatingLogger) Write(format string, args ...interface{}) error {
	l.mu.Lock()
	defer l.mu.Unlock()

	msg := fmt.Sprintf(format, args...)
	if !strings.HasSuffix(msg, "\n") {
		msg += "\n"
	}

	n, err := l.file.WriteString(msg)
	if err != nil {
		return err
	}

	l.currentSize += int64(n)

	// Check if rotation needed
	if l.currentSize >= l.maxSize {
		if err := l.rotate(); err != nil {
			return fmt.Errorf("failed to rotate log: %v", err)
		}
	}

	return nil
}

func (l *RotatingLogger) rotate() error {
	// Close current file
	l.file.Close()

	// Generate new filename with timestamp
	timestamp := time.Now().Format("20060102-150405")
	newName := fmt.Sprintf("%s.%s", l.path, timestamp)

	// Rename current file
	if err := os.Rename(l.path, newName); err != nil {
		return err
	}

	// Compress the rotated file
	go l.compressFile(newName)

	// Clean up old files
	go l.cleanupOldFiles()

	// Open new file
	file, err := os.OpenFile(l.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}

	l.file = file
	l.currentSize = 0

	return nil
}

func (l *RotatingLogger) compressFile(path string) error {
	source, err := os.Open(path)
	if err != nil {
		return err
	}
	defer source.Close()

	destPath := path + ".gz"
	dest, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer dest.Close()

	gzWriter := gzip.NewWriter(dest)
	defer gzWriter.Close()

	if _, err := io.Copy(gzWriter, source); err != nil {
		return err
	}

	// Remove original file after successful compression
	return os.Remove(path)
}

func (l *RotatingLogger) cleanupOldFiles() error {
	// Find all backup files
	dir := filepath.Dir(l.path)
	base := filepath.Base(l.path)

	files, err := filepath.Glob(filepath.Join(dir, base+".*.gz"))
	if err != nil {
		return err
	}

	if len(files) <= l.maxBackups {
		return nil
	}

	// Sort by modification time
	sort.Slice(files, func(i, j int) bool {
		fiInfo, _ := os.Stat(files[i])
		fjInfo, _ := os.Stat(files[j])
		return fiInfo.ModTime().Before(fjInfo.ModTime())
	})

	// Remove oldest files
	toRemove := len(files) - l.maxBackups
	for i := 0; i < toRemove; i++ {
		os.Remove(files[i])
	}

	return nil
}

func (l *RotatingLogger) rotationChecker() {
	ticker := time.NewTicker(LOG_CHECK_INTERVAL)
	defer ticker.Stop()

	for range ticker.C {
		l.mu.Lock()
		info, err := l.file.Stat()
		if err == nil {
			l.currentSize = info.Size()
			if l.currentSize >= l.maxSize {
				l.rotate()
			}
		}
		l.mu.Unlock()
	}
}

func (l *RotatingLogger) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.file.Close()
}

// WriteHeader writes a formatted header to the log
func (l *RotatingLogger) WriteHeader(backend, mount string, ttl time.Duration) error {
	return l.Write("=== FORKSPOON CACHE LOG ===\nStarted: %s\nBackend: %s\nMount: %s\nCache TTL: %v\n==========================================",
		time.Now().Format(time.RFC3339), backend, mount, ttl)
}