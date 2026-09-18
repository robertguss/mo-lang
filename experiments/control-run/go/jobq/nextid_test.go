package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Change 6: the rename rule corrected. A rename record carries next_id, and
// moves only jobs below it.

// A job created into the old name after the rename, and archived later,
// stays in the old name: at open, after a compaction, and after one more
// rename and a stop (the generation-five bug's sequence).
func TestRenameSparesAJobCreatedAfterItAndArchivedLater(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Minute
	doneJob(t, q, "a", "k1") // j_1, archived before the rename
	archiveNow(t, q, clock)
	keyedCreate(t, q, "a", "k2", "p") // j_2, live at the rename
	if _, err := q.Rename(ctx(t), "a", "b"); err != nil {
		t.Fatal(err)
	}
	doneJob(t, q, "a", "k1") // j_3: the old name, a fresh queue, a freed key
	archiveNow(t, q, clock)
	want := map[uint64]string{1: "b", 2: "b", 3: "a"}
	check := func(q *Queue, stage string) {
		t.Helper()
		for id, queue := range want {
			if j := q.lookup(id); j == nil || j.Queue != queue {
				t.Errorf("%s: j_%d is %+v, want in %s", stage, id, j, queue)
			}
		}
		for _, ref := range []keyRef{{"b", "k1"}, {"b", "k2"}, {"a", "k1"}} {
			if _, ok := q.keys[ref]; !ok {
				t.Errorf("%s: key %v is free", stage, ref)
			}
		}
	}
	check(q, "live")
	if !strings.Contains(readFile(t, filepath.Join(dir, logName)), `"next_id":3`) {
		t.Error("the rename record has no next_id 3")
	}
	q, s = reopen(t, dir, q, s, clock)
	check(q, "reopened")
	closeQueue(q, s)
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	check(q, "compacted")
	// One more rename after the compaction, and a stop: the folder opens.
	if _, err := q.Rename(ctx(t), "a", "c"); err != nil {
		t.Fatal(err)
	}
	want[3] = "c"
	q, s = reopen(t, dir, q, s, clock)
	defer func() { closeQueue(q, s) }()
	for id, queue := range want {
		if j := q.lookup(id); j == nil || j.Queue != queue {
			t.Errorf("after the second rename: j_%d is %+v, want in %s", id, j, queue)
		}
	}
	if code, out, errOut := runCmd("verify", dir); code == 0 {
		t.Errorf("verify ran while the folder was open: %q", out)
	} else if !strings.Contains(errOut, "in use") {
		t.Errorf("verify = %d %q", code, errOut)
	}
}

// A change-5 rename record without next_id applies to every job the live log
// has named so far, archived or not; a job created after it keeps the old
// name.
func TestChange5RenameRecordWithoutNextID(t *testing.T) {
	dir := t.TempDir()
	arch := jobLine("j_1", "a", "done", `,"archived_at":"2026-09-14T00:00:02.000Z"`)
	writeLines(t, filepath.Join(dir, archiveName), arch)
	writeLines(t, filepath.Join(dir, logName),
		jobLine("j_1", "a", "done", ""), `{"op":"arch","id":"j_1"}`,
		jobLine("j_2", "a", "queued", ""),
		`{"op":"rename","from":"a","to":"b"}`,
		jobLine("j_3", "a", "queued", ""))
	code, out, errOut := runCmd("verify", dir)
	if code != 0 || out != "2 jobs: queued 2, scheduled 0, leased 0, done 0, dead 0; next id j_4; archived 1\n" {
		t.Fatalf("verify = %d %q %q", code, out, errOut)
	}
	q, s, err := openQueue(dir, realClock{})
	if err != nil {
		t.Fatal(err)
	}
	got := map[uint64]string{1: q.lookup(1).Queue, 2: q.lookup(2).Queue, 3: q.lookup(3).Queue}
	closeQueue(q, s)
	if got[1] != "b" || got[2] != "b" || got[3] != "a" {
		t.Errorf("queues %v, want j_1 and j_2 in b, j_3 in a", got)
	}
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	if data := readFile(t, filepath.Join(dir, archiveName)); !strings.Contains(data, `"queue":"b"`) {
		t.Errorf("the compacted archive: %s", data)
	}
}
