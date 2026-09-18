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
	"time"
)

// The store is an append-only log in <dir>/jobq.log. One line per record:
// eight hex digits of CRC-32C, a space, the record's JSON, a newline. A put
// holds a job's whole state, a del removes a job, a meta (written by compact)
// carries the id counter, an arch says the job left the board for the archive,
// a rename moves every job of one queue to another (see Queue.Rename), and a
// prune removes the archived jobs archived at or before its cutoff whose
// archive record lies in the archive's first archive_size bytes (see
// Queue.Prune).
//
// The archive is <dir>/jobq.archive, the same line format, append-only
// between compactions: a put holds an archived job with archived_at, a del
// is the tombstone of an archived job deleted since. It is read before the
// log, and its records win: a job the log still holds (a kill fell between
// the archive's append and the log's arch) is archived. A missing archive is
// an empty one, and the file is made at its first write.
// A log written before the tries rename still replays: decodeLine reads a
// job's old names (see storedJob), and every record written since, compact's
// included, has only the new ones.
//
// Persistence is named twice: a record is on the disk when its file is
// synced (Append), and a file is when its directory is synced after the
// file is made (openLog, lazyFile) or renamed into place (Compact,
// finishCompaction). A response is written only after both.
//
// The errors the store declares, each reached by a test named in
// REPORT-change-6.md (errors_test.go holds most):
//   - at open: a missing folder, a file where the folder should be, a folder
//     in use by another jobq, a line that is not a record, a bad checksum
//     field, a checksum mismatch, a record longer than maxRecordBytes, a
//     field no record has, an unknown op, a put without a job, an ill-formed
//     job (verify.go), a del or arch of a job the replay does not hold, a job
//     archived twice, an unknown archive op, a rename record with a bad name,
//     a prune record with a bad cutoff, count, or archive_size, a prune whose
//     count the replay does not find, a key clash, and a job whose key
//     changes;
//   - on a write (ErrStore, answered 503): a write that fails, a full disk
//     (ENOSPC), a sync that fails, and a cut of a torn tail that fails.

const (
	logName        = "jobq.log"
	archiveName    = "jobq.archive"
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
	From   string   `json:"from,omitempty"`
	To     string   `json:"to,omitempty"`
	// A prune's: the cutoff, the count of jobs it removed, and the archive's
	// length when it was written.
	Cutoff      string `json:"cutoff,omitempty"`
	Count       int    `json:"count,omitempty"`
	ArchiveSize int64  `json:"archive_size,omitempty"`
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
	var sr struct {
		Op          string     `json:"op"`
		Job         *storedJob `json:"job"`
		ID          string     `json:"id"`
		NextID      uint64     `json:"next_id"`
		From        string     `json:"from"`
		To          string     `json:"to"`
		Cutoff      string     `json:"cutoff"`
		Count       int        `json:"count"`
		ArchiveSize int64      `json:"archive_size"`
	}
	if err := dec.Decode(&sr); err != nil {
		return record{}, err
	}
	r := record{Op: sr.Op, ID: sr.ID, NextID: sr.NextID, From: sr.From, To: sr.To,
		Cutoff: sr.Cutoff, Count: sr.Count, ArchiveSize: sr.ArchiveSize}
	if sr.Job != nil {
		v, err := sr.Job.view()
		if err != nil {
			return record{}, err
		}
		r.Job = &v
	}
	return r, nil
}

// replay reads whole records from r in order and applies each. It returns
// the length of the whole records. A last line with no newline is a torn
// write and is left out; a whole line that does not decode is corruption.
func replay(r io.Reader, apply func(record) error) (int64, error) {
	return replayAt(r, func(rec record, _ int64) error { return apply(rec) })
}

// replayAt is replay with each record's offset in the file.
func replayAt(r io.Reader, apply func(rec record, off int64) error) (int64, error) {
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
			err = apply(rec, size)
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
	// Dirty until the sync returns, so a panic inside the write leaves the
	// tail to be cut as a failed write's would be.
	s.dirty = true
	n, err := s.f.WriteAt(buf, s.size)
	if err == nil && n != len(buf) {
		err = io.ErrShortWrite
	}
	if err == nil {
		err = s.f.Sync()
	}
	if err != nil {
		_ = s.repair()
		return fmt.Errorf("%w: %v", ErrStore, err)
	}
	s.dirty = false
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
	return openLog(dir, func() error { return nil }, apply)
}

// openLog is OpenStore with first run under the lock, before the replay.
func openLog(dir string, first func() error, apply func(record) error) (*Store, error) {
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
	if err := first(); err != nil {
		f.Close()
		return nil, err
	}
	s, err := loadStore(f, f, path, func(rec record, _ int64) error { return apply(rec) })
	if err != nil {
		f.Close()
		return nil, err
	}
	return s, nil
}

// loadStore replays osf through apply and returns a store over file whose
// torn tail, if any, is cut.
func loadStore(osf *os.File, file File, path string, apply func(record, int64) error) (*Store, error) {
	size, err := replayAt(osf, apply)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	st, err := osf.Stat()
	if err != nil {
		return nil, err
	}
	s := &Store{f: file, size: size, dirty: st.Size() != size}
	if err := s.repair(); err != nil {
		return nil, err
	}
	return s, nil
}

// openArchive replays <dir>/jobq.archive through apply, with each record's
// offset, when there is one. The caller holds the log's lock.
func openArchive(dir string, apply func(record, int64) error) (*Store, error) {
	path := filepath.Join(dir, archiveName)
	lf := &lazyFile{path: path, dir: dir}
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if errors.Is(err, fs.ErrNotExist) {
		return &Store{f: lf}, nil
	}
	if err != nil {
		return nil, err
	}
	lf.f = f
	s, err := loadStore(f, lf, path, apply)
	if err != nil {
		f.Close()
		return nil, err
	}
	return s, nil
}

// lazyFile is a file made at its first write, so a folder that never
// archives never gains an archive, and a read-only one still opens.
type lazyFile struct {
	path, dir string
	f         *os.File
}

func (l *lazyFile) WriteAt(p []byte, off int64) (int, error) {
	if l.f == nil {
		f, err := os.OpenFile(l.path, os.O_RDWR|os.O_CREATE, 0o644)
		if err != nil {
			return 0, err
		}
		if err := syncDir(l.dir); err != nil {
			f.Close()
			return 0, err
		}
		l.f = f
	}
	return l.f.WriteAt(p, off)
}

func (l *lazyFile) Sync() error {
	if l.f == nil {
		return nil
	}
	return l.f.Sync()
}

// Truncate with no file is a cut of a write that never made one.
func (l *lazyFile) Truncate(size int64) error {
	if l.f == nil {
		return nil
	}
	return l.f.Truncate(size)
}

func (l *lazyFile) Close() error {
	if l.f == nil {
		return nil
	}
	return l.f.Close()
}

func syncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	return errors.Join(d.Sync(), d.Close())
}

// Compact rewrites <dir>/jobq.log as a meta record and one put per job on
// the board, by id, under its current queue, then <dir>/jobq.archive as one
// put per archived job not deleted, under its current queue. Renames are
// folded into the job records, so the new log has none, and the new archive
// must replace the old one with the log: an old archive under a new log would
// lose the renames. So both new files are written and synced first, the log
// is renamed over the old one, then the archive. A kill leaves jobq.log.compact
// (nothing was replaced; the open drops both temporaries) or only
// jobq.archive.compact (the log was replaced; the open finishes the archive's
// rename). See finishCompaction.
func Compact(dir string) error {
	q, s, err := openQueue(dir, realClock{})
	if err != nil {
		return err
	}
	defer s.Close()
	defer q.closeArchive()
	_, statErr := os.Stat(filepath.Join(dir, archiveName))
	withArchive := !errors.Is(statErr, fs.ErrNotExist) || len(q.archived) > 0
	if err := writeTemp(dir, logName, func(w io.Writer) error { return writeCompacted(w, q) }); err != nil {
		return err
	}
	if withArchive {
		if err := writeTemp(dir, archiveName, func(w io.Writer) error { return writeArchive(w, q) }); err != nil {
			os.Remove(tempPath(dir, logName))
			return err
		}
	}
	if err := os.Rename(tempPath(dir, logName), filepath.Join(dir, logName)); err != nil {
		return err
	}
	crashPoint("compact-log-renamed")
	if err := syncDir(dir); err != nil {
		return err
	}
	if !withArchive {
		return nil
	}
	if err := os.Rename(tempPath(dir, archiveName), filepath.Join(dir, archiveName)); err != nil {
		return err
	}
	crashPoint("compact-archive-renamed")
	return syncDir(dir)
}

// crashPoint kills the process where JOBQ_CRASH_AT names it, so check.sh can
// kill a compaction between a file's rename and the fsync of its directory.
func crashPoint(name string) {
	if os.Getenv("JOBQ_CRASH_AT") == name {
		_ = syscall.Kill(os.Getpid(), syscall.SIGKILL)
		time.Sleep(time.Minute)
	}
}

func tempPath(dir, name string) string { return filepath.Join(dir, name+".compact") }

// finishCompaction makes a folder a killed Compact left whole: the old pair
// of files, or the new pair. The caller holds the log's lock.
func finishCompaction(dir string) error {
	logTemp, archTemp := tempPath(dir, logName), tempPath(dir, archiveName)
	_, logErr := os.Stat(logTemp)
	_, archErr := os.Stat(archTemp)
	switch {
	case logErr == nil:
		// The archive's temporary goes first: a kill between the two
		// removals still leaves the log's, which says nothing was replaced.
		if err := errors.Join(removeIfThere(archTemp), syncDir(dir)); err != nil {
			return err
		}
		if err := os.Remove(logTemp); err != nil {
			return err
		}
	case archErr == nil:
		if err := os.Rename(archTemp, filepath.Join(dir, archiveName)); err != nil {
			return err
		}
	default:
		return nil
	}
	return syncDir(dir)
}

func removeIfThere(path string) error {
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// writeTemp writes <dir>/<name>.compact with what write writes, synced.
func writeTemp(dir, name string, write func(io.Writer) error) error {
	tmp := tempPath(dir, name)
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	w := bufio.NewWriter(f)
	err = write(w)
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
	return nil
}

func writeCompacted(w io.Writer, q *Queue) error {
	recs := []record{{Op: "meta", NextID: q.nextID}}
	for _, id := range sortedIDs(q.jobs) {
		v := jobView(*q.jobs[id])
		recs = append(recs, record{Op: "put", Job: &v})
	}
	return writeRecords(w, recs)
}

func writeArchive(w io.Writer, q *Queue) error {
	recs := make([]record, 0, len(q.archived))
	for _, id := range sortedIDs(q.archived) {
		v := jobView(*q.archived[id])
		recs = append(recs, record{Op: "put", Job: &v})
	}
	return writeRecords(w, recs)
}

func sortedIDs(jobs map[uint64]*Job) []uint64 {
	ids := make([]uint64, 0, len(jobs))
	for id := range jobs {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}

func writeRecords(w io.Writer, recs []record) error {
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
