package main

import (
	"bytes"
	"errors"
	"fmt"
	"hash/crc32"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

var errInjected = errors.New("injected failure")

// memFile is an in-memory File that fails when fail says so. A failed write
// leaves cut(n) of its n bytes behind.
type memFile struct {
	data []byte
	fail func(op string) bool
	cut  func(n int) int
}

func (m *memFile) failing(op string) bool { return m.fail != nil && m.fail(op) }

func (m *memFile) WriteAt(p []byte, off int64) (int, error) {
	n, err := len(p), error(nil)
	if m.failing("write") {
		n, err = 0, errInjected
		if m.cut != nil {
			n = m.cut(len(p))
		}
	}
	if end := int(off) + n; end > len(m.data) {
		m.data = append(m.data, make([]byte, end-len(m.data))...)
	}
	copy(m.data[off:], p[:n])
	return n, err
}

func (m *memFile) Sync() error {
	if m.failing("sync") {
		return errInjected
	}
	return nil
}

func (m *memFile) Truncate(size int64) error {
	if m.failing("truncate") {
		return errInjected
	}
	if int(size) <= len(m.data) {
		m.data = m.data[:size]
	}
	return nil
}

func (m *memFile) Close() error { return nil }

// newMemQueue is a queue over an in-memory store on a manual clock.
func newMemQueue() (*Queue, *Store, *memFile, *manualClock) {
	clock := newManualClock(time.Date(2026, 9, 14, 12, 0, 0, 0, time.UTC))
	f := &memFile{}
	s := &Store{f: f}
	q := newQueue(clock)
	q.finishReplay(s)
	return q, s, f, clock
}

// snapshot is every job in its stored shape, keyed by id.
func snapshot(q *Queue) map[string]jobJSON {
	out := make(map[string]jobJSON, len(q.jobs))
	for _, j := range q.jobs {
		out[formatID(j.ID)] = jobView(*j)
	}
	return out
}

func replayBytes(t *testing.T, data []byte) *Queue {
	t.Helper()
	q := newQueue(realClock{})
	if _, err := replay(bytes.NewReader(data), q.applyRecord); err != nil {
		t.Fatal(err)
	}
	return q
}

func lineFor(body string) string {
	return fmt.Sprintf("%08x %s\n", crc32.Checksum([]byte(body), castagnoli), body)
}

func sampleRecord(id uint64) record {
	v := jobView(Job{ID: id, Queue: "a", State: Queued, Payload: "p <&> \"q\"\n", MaxAttempts: 3,
		CreatedAt: time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC), UpdatedAt: time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)})
	return record{Op: "put", Job: &v}
}

func TestRecordRoundTrip(t *testing.T) {
	for _, r := range []record{sampleRecord(7), {Op: "del", ID: "j_7"}, {Op: "meta", NextID: 9}} {
		line, err := encodeRecord(r)
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Count(line, []byte("\n")) != 1 || line[len(line)-1] != '\n' {
			t.Fatalf("line %q is not one line", line)
		}
		got, err := decodeLine(line[:len(line)-1])
		if err != nil || !reflect.DeepEqual(got, r) {
			t.Errorf("decodeLine = %+v, %v; want %+v", got, err, r)
		}
	}
}

func TestDecodeLineRejects(t *testing.T) {
	good := strings.TrimSuffix(lineFor(`{"op":"meta","next_id":3}`), "\n")
	flipped := []byte(good)
	flipped[len(flipped)-2] = '4'
	for _, line := range []string{
		"", "short", "zzzzzzzz " + `{"op":"meta"}`, string(flipped),
		strings.TrimSuffix(lineFor(`{"op":"meta","extra":1}`), "\n"),
		strings.TrimSuffix(lineFor(`not json`), "\n"),
	} {
		if _, err := decodeLine([]byte(line)); err == nil {
			t.Errorf("decodeLine(%q) accepted", line)
		}
	}
}

func TestReplayLeavesOutTornTail(t *testing.T) {
	a, _ := encodeRecord(sampleRecord(1))
	b, _ := encodeRecord(sampleRecord(2))
	data := append(append(append([]byte{}, a...), b...), a[:len(a)/2]...)
	n := 0
	size, err := replay(bytes.NewReader(data), func(record) error { n++; return nil })
	if err != nil || n != 2 || size != int64(len(a)+len(b)) {
		t.Errorf("replay = %d records, size %d, %v", n, size, err)
	}
}

func TestReplayRejectsCorruptWholeLine(t *testing.T) {
	a, _ := encodeRecord(sampleRecord(1))
	data := string(a) + "00000000 {}\n" + string(a)
	_, err := replay(strings.NewReader(data), func(record) error { return nil })
	if err == nil || !strings.Contains(err.Error(), "record 2") {
		t.Errorf("replay err = %v, want record 2 rejected", err)
	}
}

func TestAppendFailureLeavesStoreUnchanged(t *testing.T) {
	cases := []struct {
		name  string
		fails map[string]bool
	}{
		{"write fails half way", map[string]bool{"write": true}},
		{"sync fails", map[string]bool{"sync": true}},
		{"write and truncate fail", map[string]bool{"write": true, "truncate": true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := &memFile{cut: func(n int) int { return n / 2 }}
			s := &Store{f: f}
			if err := s.Append(sampleRecord(1)); err != nil {
				t.Fatal(err)
			}
			before := append([]byte{}, f.data...)
			once := map[string]bool{}
			for op := range c.fails {
				once[op] = true
			}
			f.fail = func(op string) bool {
				failing := once[op]
				once[op] = false
				return failing
			}
			if err := s.Append(sampleRecord(2)); !errors.Is(err, ErrStore) {
				t.Fatalf("Append = %v, want ErrStore", err)
			}
			if s.size != int64(len(before)) || !bytes.Equal(f.data[:s.size], before) {
				t.Fatalf("durable prefix changed")
			}
			if c.fails["truncate"] != s.dirty {
				t.Fatalf("dirty = %v", s.dirty)
			}
			f.fail = nil
			if err := s.Append(sampleRecord(3)); err != nil {
				t.Fatal(err)
			}
			q := replayBytes(t, f.data)
			if len(q.jobs) != 2 || q.jobs[1] == nil || q.jobs[3] == nil {
				t.Errorf("replayed jobs %v, want j_1 and j_3", snapshot(q))
			}
		})
	}
}

func TestOpenStoreCreatesLocksReplaysAndCutsTornTail(t *testing.T) {
	dir := t.TempDir()
	s, err := OpenStore(dir, func(record) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	if _, err := OpenStore(dir, func(record) error { return nil }); err == nil || !strings.Contains(err.Error(), "in use") {
		t.Errorf("second OpenStore = %v, want in use", err)
	}
	if err := s.Append(sampleRecord(1), sampleRecord(2)); err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, logName)
	whole, _ := os.ReadFile(path)
	if err := os.WriteFile(path, append(append([]byte{}, whole...), "3a9f torn"...), 0o644); err != nil {
		t.Fatal(err)
	}
	n := 0
	s, err = OpenStore(dir, func(record) error { n++; return nil })
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if info, _ := os.Stat(path); n != 2 || info.Size() != int64(len(whole)) {
		t.Errorf("replayed %d records, file %d bytes; want 2 and %d", n, info.Size(), len(whole))
	}
}

func TestOpenStoreNeedsADirectory(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{filepath.Join(dir, "missing"), file} {
		if _, err := OpenStore(d, func(record) error { return nil }); err == nil {
			t.Errorf("OpenStore(%s) succeeded", d)
		}
	}
}

func TestCompactKeepsJobsAndTheCounter(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	for range 3 {
		if _, err := q.Create(ctx(t), "a", "x", 2); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := q.Lease(ctx(t), "a", "w", 1000); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(ctx(t), 3); err != nil {
		t.Fatal(err)
	}
	want := snapshot(q)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, logName))
	if lines := bytes.Count(data, []byte("\n")); lines != 3 {
		t.Errorf("compacted log has %d lines, want a meta and 2 puts", lines)
	}
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if got := snapshot(q); !reflect.DeepEqual(got, want) {
		t.Errorf("after compact %v, want %v", got, want)
	}
	if j, err := q.Create(ctx(t), "a", "x", 2); err != nil || j.ID != 4 {
		t.Errorf("next id = %v, %v; want j_4, never j_3 again", j.ID, err)
	}
}
