package main

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// Change 6: every error the store declares (see the list in store.go) is
// reached here, by name, with the message an operator reads.

// TestEveryDeclaredOpenErrorIsReached builds a folder for each error an open
// declares and runs verify on it: exit 1 and the message.
func TestEveryDeclaredOpenErrorIsReached(t *testing.T) {
	job := func(id, queue, key, state string) string {
		return jobLine(id, queue, state, `,"key":"`+key+`"`)
	}
	archived := func(id, queue, key string) string {
		return jobLine(id, queue, "done", `,"key":"`+key+`","archived_at":"2026-09-14T00:00:02.000Z"`)
	}
	for _, c := range []struct {
		name         string
		log, archive string // record bodies, one per line, each given its checksum
		rawLog       string // the log's bytes as they are
		want         string
	}{
		{name: "not a record line", rawLog: "garbage here\n", want: "record 1: not a record line"},
		{name: "bad checksum field", rawLog: "zzzzzzzz {}\n", want: "record 1: bad checksum field"},
		{name: "checksum mismatch", rawLog: "00000000 {\"op\":\"meta\"}\n", want: "record 1: checksum mismatch"},
		{name: "a record too long", rawLog: strings.Repeat("x", maxRecordBytes+10) + "\n", want: "record 1: longer than 524288 bytes"},
		{name: "a field no record has", log: `{"op":"meta","next_id":2,"extra":1}`, want: `unknown field "extra"`},
		{name: "an unknown op", log: `{"op":"mystery"}`, want: `unknown op "mystery"`},
		{name: "a put without a job", log: `{"op":"put"}`, want: "put without a job"},
		{name: "a bad record (ill-formed job)", log: job("j_1", "a", "k", "leased"), want: "record j_1: a leased job has a worker"},
		{name: "a del of an unknown job", log: `{"op":"del","id":"j_9"}`, want: `del of unknown job "j_9"`},
		{name: "an arch of a job not archived", log: `{"op":"arch","id":"j_9"}`, want: `arch of a job not in the archive "j_9"`},
		{name: "a rename record with a bad name", log: `{"op":"rename","from":"a b","to":"c","next_id":2}`, want: `a rename's from and to are 1 to 64 bytes`},
		{name: "a prune record with a bad cutoff", archive: archived("j_1", "a", "k"),
			log: `{"op":"prune","cutoff":"soon","count":1,"archive_size":10}`, want: "a prune's cutoff is a time"},
		{name: "a key clash", log: job("j_1", "a", "k", "queued") + "\n" + job("j_2", "a", "k", "queued"),
			want: "a key names two jobs in one queue at once"},
		{name: "a job's key changes", log: job("j_1", "a", "k", "queued") + "\n" + job("j_1", "a", "other", "queued"),
			want: "a job's key changes"},
		{name: "an archived job twice", archive: archived("j_1", "a", "k") + "\n" + archived("j_1", "a", "k"),
			want: "job j_1 is archived twice"},
		{name: "a del of an unknown archived job", archive: `{"op":"del","id":"j_9"}`, want: `del of unknown archived job "j_9"`},
		{name: "an unknown archive op", archive: `{"op":"arch","id":"j_1"}`, want: `unknown archive op "arch"`},
		{name: "a bad archive record", archive: job("j_1", "a", "k", "queued"), want: "archive record j_1: an archived job is done or dead"},
	} {
		dir := t.TempDir()
		write := func(name, bodies string) {
			if bodies == "" {
				return
			}
			writeLines(t, filepath.Join(dir, name), strings.Split(bodies, "\n")...)
		}
		write(logName, c.log)
		write(archiveName, c.archive)
		if c.rawLog != "" {
			if err := os.WriteFile(filepath.Join(dir, logName), []byte(c.rawLog), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		code, out, errOut := runCmd("verify", dir)
		if code != 1 || out != "" || !strings.HasPrefix(errOut, "jobq: "+dir) || !strings.Contains(errOut, c.want) {
			t.Errorf("%s: verify = %d %q %q; want 1 and %q", c.name, code, out, errOut, c.want)
		}
	}
}

func TestOpenErrorsOfTheFolderItself(t *testing.T) {
	dir := t.TempDir()
	missing := filepath.Join(dir, "missing")
	if code, _, errOut := runCmd("verify", missing); code != 1 || !strings.Contains(errOut, "no such file or directory") {
		t.Errorf("a missing folder: %d %q", code, errOut)
	}
	file := filepath.Join(dir, "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, errOut := runCmd("verify", file); code != 1 || !strings.Contains(errOut, "is not a directory") {
		t.Errorf("a file for a folder: %d %q", code, errOut)
	}
	q, s, err := openQueue(dir, realClock{})
	if err != nil {
		t.Fatal(err)
	}
	defer closeQueue(q, s)
	if code, _, errOut := runCmd("verify", dir); code != 1 || !strings.Contains(errOut, "is in use by another jobq") {
		t.Errorf("a folder in use: %d %q", code, errOut)
	}
}

// fullDisk writes half of what it is given and fails with ENOSPC while full.
type fullDisk struct {
	memFile
	full bool
}

func (f *fullDisk) WriteAt(p []byte, off int64) (int, error) {
	if !f.full {
		return f.memFile.WriteAt(p, off)
	}
	n, _ := f.memFile.WriteAt(p[:len(p)/2], off)
	return n, syscall.ENOSPC
}

// A full disk and a write that fails: the change is answered 503, the torn
// half is cut, memory is as it was, and the next write lands.
func TestAFullDiskAndAFailingWrite(t *testing.T) {
	clock := newManualClock(pruneEpoch)
	disk := &fullDisk{}
	q := newQueue(clock)
	q.archive = &Store{f: &memFile{}}
	s := &Store{f: disk}
	q.finishReplay(s)
	mustCreate(t, q, "a", 1)
	before := len(disk.data)
	disk.full = true
	_, _, err := q.Create(ctx(t), "a", "", "p", 1, 0, 0)
	if !errors.Is(err, ErrStore) || !strings.Contains(err.Error(), "no space left on device") || errorStatus(err) != http.StatusServiceUnavailable {
		t.Fatalf("create on a full disk = %v", err)
	}
	if len(disk.data) != before || len(q.jobs) != 1 {
		t.Errorf("after the full disk: %d bytes (want %d), %d jobs", len(disk.data), before, len(q.jobs))
	}
	disk.full = false
	for _, op := range []string{"write", "sync"} {
		disk.fail = func(o string) bool { return o == op }
		if _, _, err := q.Create(ctx(t), "a", "", "p", 1, 0, 0); !errors.Is(err, ErrStore) || !strings.Contains(err.Error(), "injected failure") {
			t.Errorf("a %s that fails = %v", op, err)
		}
	}
	// A cut that fails too leaves the store dirty; the next write cuts first.
	disk.fail = func(o string) bool { return o == "sync" || o == "truncate" }
	if _, _, err := q.Create(ctx(t), "a", "", "p", 1, 0, 0); !errors.Is(err, ErrStore) {
		t.Errorf("a sync and a cut that fail = %v", err)
	}
	if !s.dirty {
		t.Error("the store is not dirty after a failed cut")
	}
	disk.fail = nil
	j := mustCreate(t, q, "a", 1)
	if j.ID != 6 || len(q.jobs) != 2 {
		t.Errorf("after the disk came back: %+v, %d jobs", j, len(q.jobs))
	}
	r := replayBytes(t, disk.data)
	if len(r.jobs) != 2 || r.jobs[6] == nil {
		t.Errorf("replayed %v", sortedIDs(r.jobs))
	}
}

// An archive write that fails (here a full disk) moves nothing, and an
// archived delete answers 503 and deletes nothing.
func TestAFullDiskUnderTheArchive(t *testing.T) {
	clock := newManualClock(pruneEpoch)
	disk := &fullDisk{}
	q := newQueue(clock)
	q.archive = &Store{f: disk}
	q.finishReplay(&Store{f: &memFile{}})
	q.retain = time.Minute
	doneJob(t, q, "a", "k")
	disk.full = true
	archiveNow(t, q, clock)
	if len(q.archived) != 0 || len(disk.data) != 0 {
		t.Fatalf("the move on a full disk archived %d, wrote %d bytes", len(q.archived), len(disk.data))
	}
	disk.full = false
	if _, err := q.Health(ctx(t)); err != nil || len(q.archived) != 1 {
		t.Fatalf("the move after: %v, archived %d", err, len(q.archived))
	}
	disk.full = true
	if err := q.Delete(ctx(t), 1); !errors.Is(err, ErrStore) || q.archived[1] == nil {
		t.Errorf("an archived delete on a full disk = %v, archived %v", err, q.archived[1] != nil)
	}
}

// An archive record whose job the board holds under another key: an open
// never gets one (the archive is read before the log), but an incremental
// replay (the simulation's mirror) can.
func TestAnArchiveRecordThatChangesAKey(t *testing.T) {
	q := newQueue(realClock{})
	if _, err := replay(strings.NewReader(lineFor(jobLine("j_1", "a", "done", `,"key":"k"`))), q.applyRecord); err != nil {
		t.Fatal(err)
	}
	rec, err := decodeLine([]byte(strings.TrimSuffix(lineFor(jobLine("j_1", "a", "done", `,"key":"other","archived_at":"2026-09-14T00:00:02.000Z"`)), "\n")))
	if err != nil {
		t.Fatal(err)
	}
	if err := q.applyArchived(rec, 0); err == nil || !strings.Contains(err.Error(), "a job's key changes") {
		t.Errorf("applyArchived = %v", err)
	}
}

// checkApart's first never cannot be reached from a folder: the archive is
// read first, and the log's put of an archived job is stale. It is reached
// here on a queue built by hand.
func TestCheckApartRefusesAJobInBothPlaces(t *testing.T) {
	q := newQueue(realClock{})
	j := Job{ID: 1, Queue: "a", State: Done, MaxTries: 1}
	q.jobs[1] = &j
	a := j
	q.archived[1] = &a
	err := q.checkApart()
	if err == nil || !strings.Contains(err.Error(), "a job is on the live board and in the archive at once") {
		t.Errorf("checkApart = %v", err)
	}
}
