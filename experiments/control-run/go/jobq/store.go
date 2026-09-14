package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"syscall"
)

// The store is an append-only log in <dir>/jobq.log. One line per record:
// eight hex digits of CRC-32C, a space, the record's JSON, a newline. A put
// holds a job's whole state, a del removes a job, a meta (written by compact)
// carries the id counter.

const (
	logName        = "jobq.log"
	maxRecordBytes = 512 * 1024
)

var castagnoli = crc32.MakeTable(crc32.Castagnoli)

// ErrStore is a write the store could not make durable. The queue answers 503.
var ErrStore = errors.New("store unavailable")

type record struct {
	Op     string   `json:"op"`
	Job    *jobJSON `json:"job,omitempty"`
	ID     string   `json:"id,omitempty"`
	NextID uint64   `json:"next_id,omitempty"`
}

// File is what the store needs from the file under it; the tests inject
// failures through it.
type File interface {
	WriteAt(p []byte, off int64) (int, error)
	Sync() error
	Truncate(size int64) error
	Close() error
}

// Store appends records durably. size is the length of the records known to
// be whole and synced; dirty says bytes past size may be on disk after a
// failed write and must be cut off before the next one.
type Store struct {
	f     File
	size  int64
	dirty bool
}

func encodeRecord(r record) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(r); err != nil {
		return nil, err
	}
	body := bytes.TrimSuffix(buf.Bytes(), []byte("\n"))
	return fmt.Appendf(nil, "%08x %s\n", crc32.Checksum(body, castagnoli), body), nil
}

func decodeLine(line []byte) (record, error) {
	if len(line) < 10 || line[8] != ' ' {
		return record{}, errors.New("not a record line")
	}
	sum, err := strconv.ParseUint(string(line[:8]), 16, 32)
	if err != nil {
		return record{}, errors.New("bad checksum field")
	}
	body := line[9:]
	if crc32.Checksum(body, castagnoli) != uint32(sum) {
		return record{}, errors.New("checksum mismatch")
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	dec.DisallowUnknownFields()
	var r record
	if err := dec.Decode(&r); err != nil {
		return record{}, err
	}
	return r, nil
}

// replay reads whole records from r in order and applies each. It returns
// the length of the whole records. A last line with no newline is a torn
// write and is left out; a whole line that does not decode is corruption.
func replay(r io.Reader, apply func(record) error) (int64, error) {
	br := bufio.NewReaderSize(r, maxRecordBytes)
	var size int64
	for n := 1; ; n++ {
		line, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			return size, fmt.Errorf("record %d: longer than %d bytes", n, maxRecordBytes)
		}
		if errors.Is(err, io.EOF) {
			return size, nil
		}
		if err != nil {
			return size, err
		}
		rec, err := decodeLine(line[:len(line)-1])
		if err == nil {
			err = apply(rec)
		}
		if err != nil {
			return size, fmt.Errorf("record %d: %w", n, err)
		}
		size += int64(len(line))
	}
}

// Append writes records as one write and one sync. On failure nothing is
// counted as written and the tail is cut back, now or before the next write.
func (s *Store) Append(recs ...record) error {
	var buf []byte
	for _, r := range recs {
		line, err := encodeRecord(r)
		if err != nil {
			return err
		}
		buf = append(buf, line...)
	}
	if err := s.repair(); err != nil {
		return err
	}
	n, err := s.f.WriteAt(buf, s.size)
	if err == nil && n != len(buf) {
		err = io.ErrShortWrite
	}
	if err == nil {
		err = s.f.Sync()
	}
	if err != nil {
		s.dirty = true
		_ = s.repair()
		return fmt.Errorf("%w: %v", ErrStore, err)
	}
	s.size += int64(len(buf))
	return nil
}

func (s *Store) repair() error {
	if !s.dirty {
		return nil
	}
	if err := s.f.Truncate(s.size); err != nil {
		return fmt.Errorf("%w: %v", ErrStore, err)
	}
	if err := s.f.Sync(); err != nil {
		return fmt.Errorf("%w: %v", ErrStore, err)
	}
	s.dirty = false
	return nil
}

// Close cuts any torn tail and closes the file.
func (s *Store) Close() error {
	return errors.Join(s.repair(), s.f.Close())
}

// OpenStore opens <dir>/jobq.log, creating it if missing, takes an exclusive
// lock on it, and replays it through apply.
func OpenStore(dir string, apply func(record) error) (*Store, error) {
	info, err := os.Stat(dir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", dir)
	}
	path := filepath.Join(dir, logName)
	_, statErr := os.Stat(path)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("%s is in use by another jobq: %w", path, err)
	}
	if errors.Is(statErr, fs.ErrNotExist) {
		if err := syncDir(dir); err != nil {
			f.Close()
			return nil, err
		}
	}
	size, err := replay(f, apply)
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	st, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	s := &Store{f: f, size: size, dirty: st.Size() != size}
	if err := s.repair(); err != nil {
		f.Close()
		return nil, err
	}
	return s, nil
}

func syncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	return errors.Join(d.Sync(), d.Close())
}

// Compact rewrites <dir>/jobq.log as a meta record and one put per job, by
// id, through a temporary file renamed over the log.
func Compact(dir string) error {
	q := newQueue(realClock{})
	s, err := OpenStore(dir, q.applyRecord)
	if err != nil {
		return err
	}
	defer s.Close()
	q.finishReplay(s)
	tmp := filepath.Join(dir, logName+".compact")
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	w := bufio.NewWriter(f)
	err = writeCompacted(w, q)
	if err == nil {
		err = w.Flush()
	}
	if err == nil {
		err = f.Sync()
	}
	if err = errors.Join(err, f.Close()); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, filepath.Join(dir, logName)); err != nil {
		return err
	}
	return syncDir(dir)
}

func writeCompacted(w io.Writer, q *Queue) error {
	recs := []record{{Op: "meta", NextID: q.nextID}}
	ids := make([]uint64, 0, len(q.jobs))
	for id := range q.jobs {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	for _, id := range ids {
		v := jobView(*q.jobs[id])
		recs = append(recs, record{Op: "put", Job: &v})
	}
	for _, r := range recs {
		line, err := encodeRecord(r)
		if err != nil {
			return err
		}
		if _, err := w.Write(line); err != nil {
			return err
		}
	}
	return nil
}
