package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
)

// The store is an append-only log in <dir>/jobq.log: one JSON record per
// line, each a whole job under its id, a deletion, or the id counter.
const (
	logName  = "jobq.log"
	lockName = "jobq.lock"
)

const (
	opPut  = "put"
	opDel  = "del"
	opNext = "next"
)

type record struct {
	Op   string `json:"op"`
	Next uint64 `json:"next"`
	ID   string `json:"id,omitempty"`
	Job  *Job   `json:"job,omitempty"`
}

// File is what the log needs of a file opened for append; tests wrap it to
// inject failures.
type File interface {
	Write(p []byte) (int, error)
	Sync() error
	Truncate(size int64) error
}

// Log appends records durably: a record counts only once it is written and
// synced. A failed append is cut off the file again before the next one, so
// a failed write never leaves a record behind that was answered 503.
type Log struct {
	f       File
	size    int64
	broken  bool
	records int
}

// NewLog appends to f, whose first size bytes are whole records.
func NewLog(f File, size int64) *Log { return &Log{f: f, size: size} }

// Records counts the records appended through this Log.
func (l *Log) Records() int { return l.records }

// Append writes one line and syncs it.
func (l *Log) Append(line []byte) error {
	if l.broken {
		if err := l.repair(); err != nil {
			return fmt.Errorf("repairing the log: %w", err)
		}
	}
	n, err := l.f.Write(line)
	if err == nil && n != len(line) {
		err = io.ErrShortWrite
	}
	if err == nil {
		err = l.f.Sync()
	}
	if err != nil {
		l.broken = true
		if rerr := l.repair(); rerr != nil {
			return errors.Join(err, rerr)
		}
		return err
	}
	l.size += int64(n)
	l.records++
	return nil
}

func (l *Log) repair() error {
	if err := l.f.Truncate(l.size); err != nil {
		return err
	}
	if err := l.f.Sync(); err != nil {
		return err
	}
	l.broken = false
	return nil
}

// replay calls fn for every whole record in r and returns the length of the
// whole records. A last line without its newline is a torn write and is not
// a record; any other line that is not a record is an error.
func replay(r io.Reader, fn func(record) error) (int64, error) {
	br := bufio.NewReaderSize(r, 1<<20)
	var good int64
	for lineNo := 1; ; lineNo++ {
		line, err := br.ReadBytes('\n')
		if errors.Is(err, io.EOF) {
			return good, nil // a torn tail, if any, is ignored
		}
		if err != nil {
			return good, err
		}
		dec := json.NewDecoder(bytes.NewReader(line))
		dec.DisallowUnknownFields()
		var rec record
		if err := dec.Decode(&rec); err != nil {
			return good, fmt.Errorf("%s line %d: %w", logName, lineNo, err)
		}
		if err := fn(rec); err != nil {
			return good, fmt.Errorf("%s line %d: %w", logName, lineNo, err)
		}
		good += int64(len(line))
	}
}

// store is an opened, locked <dir>.
type store struct {
	dir  string
	lock *os.File
	file *os.File
}

// openStore takes <dir>'s lock and opens its log for reading and appending.
// The lock does not wait: a second service on the same dir fails at once.
func openStore(dir string) (*store, error) {
	info, err := os.Stat(dir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", dir)
	}
	lock, err := os.OpenFile(filepath.Join(dir, lockName), os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return nil, errors.Join(fmt.Errorf("%s is in use by another jobq: %w", dir, err), lock.Close())
	}
	file, err := os.OpenFile(filepath.Join(dir, logName), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		return nil, errors.Join(err, lock.Close())
	}
	if err := syncDir(dir); err != nil {
		return nil, errors.Join(err, file.Close(), lock.Close())
	}
	return &store{dir: dir, lock: lock, file: file}, nil
}

func (s *store) close() error {
	return errors.Join(s.file.Close(), s.lock.Close())
}

func syncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	return errors.Join(d.Sync(), d.Close())
}

// loadQueue replays s's log into a new queue and cuts off a torn tail.
func loadQueue(s *store, cfg QueueConfig) (*Queue, error) {
	q := newQueue(cfg)
	if _, err := s.file.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	good, err := replay(s.file, q.replayRecord)
	if err != nil {
		return nil, err
	}
	if err := s.file.Truncate(good); err != nil {
		return nil, err
	}
	q.log = NewLog(s.file, good)
	return q, nil
}

// compact rewrites <dir>'s log to one line per live job, in id order, then
// the id counter, through a temporary file renamed over the log. It returns
// how many jobs it kept.
func compact(dir string, cfg QueueConfig) (int, error) {
	s, err := openStore(dir)
	if err != nil {
		return 0, err
	}
	defer func() { _ = s.close() }() // the rename below is what matters
	q, err := loadQueue(s, cfg)
	if err != nil {
		return 0, err
	}
	tmpPath := filepath.Join(dir, logName+".compact")
	tmp, err := os.OpenFile(tmpPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return 0, err
	}
	w := bufio.NewWriter(tmp)
	kept, werr := q.writeCompact(w)
	if werr == nil {
		werr = w.Flush()
	}
	if werr == nil {
		werr = tmp.Sync()
	}
	if err := errors.Join(werr, tmp.Close()); err != nil {
		return 0, errors.Join(err, os.Remove(tmpPath))
	}
	if err := os.Rename(tmpPath, filepath.Join(dir, logName)); err != nil {
		return 0, err
	}
	return kept, syncDir(dir)
}
