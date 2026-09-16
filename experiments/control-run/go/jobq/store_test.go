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
	q.archive = &Store{f: &memFile{}}
	q.finishReplay(s)
	return q, s, f, clock
}

// snapshot is every job in its stored shape, keyed by id, on the board or
// archived; an archived job is marked by its archived_at.
func snapshot(q *Queue) map[string]jobJSON {
	out := make(map[string]jobJSON, len(q.jobs)+len(q.archived))
	for _, j := range q.jobs {
		out[formatID(j.ID)] = jobView(*j)
	}
	for _, j := range q.archived {
		out[formatID(j.ID)] = jobView(*j)
	}
	return out
}

// replayBoth replays an archive, then a log, as an open does.
func replayBoth(t *testing.T, archive, log []byte) *Queue {
	t.Helper()
	q := newQueue(realClock{})
	if _, err := replay(bytes.NewReader(archive), q.applyArchived); err != nil {
		t.Fatal(err)
	}
	if _, err := replay(bytes.NewReader(log), q.applyRecord); err != nil {
		t.Fatal(err)
	}
	if err := q.checkApart(); err != nil {
		t.Fatal(err)
	}
	return q
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
	v := jobView(Job{ID: id, Queue: "a", State: Queued, Payload: "p <&> \"q\"\n", MaxTries: 3,
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

// oldJob is a record in the shape the service wrote before the rename.
func oldJob(id, state, extra string, tries, maxTries int) string {
	const at = "2026-09-14T00:00:00.000Z"
	return fmt.Sprintf(`{"op":"put","job":{"id":%q,"queue":"a","state":%q,"payload":"p","attempts":%d,`+
		`"max_attempts":%d,"created_at":%q,"updated_at":%q%s}}`, id, state, tries, maxTries, at, at, extra)
}

// A record that says attempts and max_attempts is read as tries and
// max_tries, and one without backoff_ms has a backoff of 0.
func TestReplayReadsTheOldNames(t *testing.T) {
	data := lineFor(oldJob("j_1", "queued", "", 1, 3)) +
		lineFor(oldJob("j_2", "leased", `,"worker":"w1","lease_until":"2026-09-14T00:01:00.000Z"`, 1, 3)) +
		lineFor(oldJob("j_3", "done", `,"reason":"ok"`, 2, 3)) +
		lineFor(oldJob("j_4", "dead", "", 3, 3)) +
		lineFor(`{"op":"del","id":"j_4"}`)
	q := replayBytes(t, []byte(data))
	if len(q.jobs) != 3 || q.nextID != 5 { // j_4 was created, then deleted
		t.Fatalf("replayed %v, next id %d", snapshot(q), q.nextID)
	}
	for id, want := range map[uint64]struct {
		state State
		tries int
	}{1: {Queued, 1}, 2: {Leased, 1}, 3: {Done, 2}} {
		j := q.jobs[id]
		if j.State != want.state || j.Tries != want.tries || j.MaxTries != 3 || j.BackoffMS != 0 || !j.RunAt.IsZero() {
			t.Errorf("j_%d = %+v", id, j)
		}
	}
	for _, body := range []string{
		`{"op":"put","job":{"id":"j_1","queue":"a","state":"queued","payload":"","attempts":0,"tries":0,"max_tries":1,"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:00.000Z"}}`,
		`{"op":"put","job":{"id":"j_1","queue":"a","state":"queued","payload":"","max_tries":1,"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:00.000Z"}}`,
	} {
		if _, err := decodeLine([]byte(strings.TrimSuffix(lineFor(body), "\n"))); err == nil {
			t.Errorf("decodeLine(%s) accepted", body)
		}
	}
}

// A folder the previous version served opens, replays, and keeps every job;
// after compact the log holds no old name.
func TestServesAFolderTheOldVersionWrote(t *testing.T) {
	log, err := os.ReadFile(filepath.Join("testdata", "v1", logName))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(log, []byte(`"max_attempts"`)) {
		t.Fatal("testdata/v1 is not a log in the old shape")
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, logName), log, 0o644); err != nil {
		t.Fatal(err)
	}
	// After the old service stopped, j_5 and j_6 were leased until 00:01:10.
	clock := newManualClock(time.Date(2026, 9, 14, 0, 2, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatalf("opening a folder the old version wrote: %v", err)
	}
	want := map[uint64]struct {
		state State
		tries int
	}{
		1: {Done, 2},   // acked
		2: {Dead, 1},   // failed on its last try
		4: {Queued, 1}, // failed with tries left
		5: {Queued, 1}, // its lease ran out, no backoff
		6: {Dead, 1},   // its lease ran out on its last try
		7: {Queued, 0},
	}
	if _, err := q.Health(ctx(t)); err != nil { // one look: the leases ran out
		t.Fatal(err)
	}
	for id, w := range want {
		j, err := q.Get(ctx(t), id)
		if err != nil || j.State != w.state || j.Tries != w.tries || j.BackoffMS != 0 {
			t.Errorf("j_%d = %+v, %v; want %s with %d tries", id, j, err, w.state, w.tries)
		}
	}
	for _, id := range []uint64{3, 8} { // deleted by the old service
		if _, err := q.Get(ctx(t), id); !errors.Is(err, ErrNotFound) {
			t.Errorf("j_%d = %v, want gone", id, err)
		}
	}
	if j, _, err := q.Create(ctx(t), "a", "", "p", 1, 0, 0); err != nil || j.ID != 9 {
		t.Errorf("create after replay = %+v, %v; want j_9", j, err)
	}
	before := snapshot(q)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadFile(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(after, []byte("attempts")) {
		t.Error("compact left an old name in the log")
	}
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if got := snapshot(q); !reflect.DeepEqual(got, before) {
		t.Errorf("after compact %v, want %v", got, before)
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
		if _, _, err := q.Create(ctx(t), "a", "", "x", 2, 0, 0); err != nil {
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
	if j, _, err := q.Create(ctx(t), "a", "", "x", 2, 0, 0); err != nil || j.ID != 4 {
		t.Errorf("next id = %v, %v; want j_4, never j_3 again", j.ID, err)
	}
}
