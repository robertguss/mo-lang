package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func logBytes(t *testing.T, dir string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestReplayReadsWholeRecordsAndSkipsATornTail(t *testing.T) {
	in := `{"op":"next","next":5}` + "\n" + `{"op":"next","next":9}` + "\n" + `{"op":"ne`
	var got []uint64
	good, err := replay(strings.NewReader(in), func(r record) error { got = append(got, r.Next); return nil })
	if err != nil || len(got) != 2 || got[1] != 9 || good != int64(strings.LastIndex(in, "\n")+1) {
		t.Errorf("got %v good %d err %v", got, good, err)
	}
}

func TestReplayRejectsACorruptMiddleLine(t *testing.T) {
	in := `{"op":"next","next":5}` + "\n" + "garbage\n" + `{"op":"next","next":9}` + "\n"
	if _, err := replay(strings.NewReader(in), func(record) error { return nil }); err == nil || !strings.Contains(err.Error(), "line 2") {
		t.Errorf("got %v", err)
	}
}

func TestLoadCutsATornTailSoTheNextAppendReplays(t *testing.T) {
	dir := t.TempDir()
	clock := newClock()
	q, st := openTestQueue(t, dir, clock)
	if _, err := q.Create(bg(), "q", "one", 1); err != nil {
		t.Fatal(err)
	}
	if err := st.close(); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(filepath.Join(dir, logName), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(`{"op":"put","next":3,"jo`); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	q2, _ := openTestQueue(t, dir, clock)
	if _, err := q2.Create(bg(), "q", "two", 1); err != nil {
		t.Fatal(err)
	}
	back := replayDir(t, dir)
	if len(back.jobs) != 2 || strings.Contains(logBytes(t, dir), `"jo{`) {
		t.Errorf("replayed %d jobs from\n%s", len(back.jobs), logBytes(t, dir))
	}
}

func TestLogRepairsAfterEachKindOfFailure(t *testing.T) {
	for name, arm := range map[string]func(*faultFile){
		"partial write":             func(ff *faultFile) { ff.writes = 1 },
		"sync":                      func(ff *faultFile) { ff.syncs = 1 },
		"sync then truncate":        func(ff *faultFile) { ff.syncs, ff.truncates = 1, 1 },
		"write then truncate twice": func(ff *faultFile) { ff.writes, ff.truncates = 1, 2 },
	} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			ff := &faultFile{}
			q := faultyQueue(t, dir, newClock(), ff)
			if _, err := q.Create(bg(), "q", "kept", 1); err != nil {
				t.Fatal(err)
			}
			before := logBytes(t, dir)
			arm(ff)
			if _, err := q.Create(bg(), "q", "lost", 1); !errors.Is(err, ErrStore) {
				t.Fatalf("got %v, want ErrStore", err)
			}
			if len(q.jobs) != 1 || q.next != 2 {
				t.Errorf("memory changed: %d jobs, next %d", len(q.jobs), q.next)
			}
			if !q.log.broken {
				if got := logBytes(t, dir); got != before {
					t.Errorf("log changed after a repaired failure:\n%s", got)
				}
			}
			// The next append repairs first; while its repair fails it is 503 too.
			j, err := q.Create(bg(), "q", "after", 1)
			for tries := 0; errors.Is(err, ErrStore) && tries < 3; tries++ {
				j, err = q.Create(bg(), "q", "after", 1)
			}
			if err != nil || j.ID != "j_2" {
				t.Fatalf("after repair: %v %v", j.ID, err)
			}
			if got := logBytes(t, dir); strings.Contains(got, "lost") || strings.Count(got, "\n") != 2 {
				t.Errorf("log after repair:\n%s", got)
			}
			if back := replayDir(t, dir); !sameJobs(snapshot(t, back), snapshot(t, q)) {
				t.Errorf("replay differs from memory")
			}
		})
	}
}

func TestCompactKeepsLiveJobsAndTheCounter(t *testing.T) {
	dir := t.TempDir()
	clock := newClock()
	q, st := openTestQueue(t, dir, clock)
	for i := 0; i < 5; i++ {
		if _, err := q.Create(bg(), "q", "p", 2); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := q.Lease(bg(), "q", "w", 1000); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(bg(), "j_5"); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(bg(), "j_3"); err != nil {
		t.Fatal(err)
	}
	want := snapshot(t, q)
	if err := st.close(); err != nil {
		t.Fatal(err)
	}
	kept, err := compact(dir, QueueConfig{Now: clock.Now})
	if err != nil || kept != 3 {
		t.Fatalf("kept %d, %v", kept, err)
	}
	if lines := strings.Count(logBytes(t, dir), "\n"); lines != 4 {
		t.Errorf("%d lines:\n%s", lines, logBytes(t, dir))
	}
	q2, _ := openTestQueue(t, dir, clock)
	if !sameJobs(snapshot(t, q2), want) {
		t.Errorf("compacted state differs")
	}
	j, err := q2.Create(bg(), "q", "p", 1)
	if err != nil || j.ID != "j_6" {
		t.Errorf("id after compact: %s %v", j.ID, err)
	}
}

func TestSecondOpenOfADirFails(t *testing.T) {
	dir := t.TempDir()
	st, err := openStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = st.close() }()
	if _, err := openStore(dir); err == nil || !strings.Contains(err.Error(), "in use") {
		t.Errorf("got %v", err)
	}
}

func TestOpenStoreRejectsMissingDirAndFile(t *testing.T) {
	if _, err := openStore(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Error("missing dir opened")
	}
	file := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := openStore(file); err == nil {
		t.Error("file opened as dir")
	}
}

func TestEveryRecordIsOneLine(t *testing.T) {
	dir := t.TempDir()
	q, _ := openTestQueue(t, dir, newClock())
	if _, err := q.Create(bg(), "q", "multi\nline\npayload", 1); err != nil {
		t.Fatal(err)
	}
	if n := bytes.Count([]byte(logBytes(t, dir)), []byte("\n")); n != 1 {
		t.Errorf("%d newlines", n)
	}
	_ = time.Second
}
