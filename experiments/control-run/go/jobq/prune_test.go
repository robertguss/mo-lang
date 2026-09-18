package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Change 6: the archive pruned.

var pruneEpoch = time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)

// doneJob creates a keyed job in queue, leases it, and acks it.
func doneJob(t *testing.T, q *Queue, queue, key string) Job {
	t.Helper()
	j, created := keyedCreate(t, q, queue, key, "p")
	if !created {
		t.Fatalf("key %s in %s was used", key, queue)
	}
	l := mustLease(t, q, queue, "w", 60_000)
	if l.ID != j.ID {
		t.Fatalf("leased %d, want %d", l.ID, j.ID)
	}
	a, err := q.Ack(ctx(t), j.ID, "w")
	if err != nil {
		t.Fatal(err)
	}
	return a
}

// archiveNow advances past retain and makes a look, which archives every
// done job.
func archiveNow(t *testing.T, q *Queue, clock *manualClock) {
	t.Helper()
	clock.Advance(q.retain + time.Millisecond)
	if _, err := q.Health(ctx(t)); err != nil {
		t.Fatal(err)
	}
}

// agedArchive opens dir with a minute's retain and archives two jobs, old-1
// and old-2 in queue a, at T+1m; then young-1 at T+1h. It returns the queue
// at T+1h, with a live job live-1 created at T.
func agedArchive(t *testing.T, dir string, clock *manualClock) (*Queue, *Store) {
	t.Helper()
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Minute
	keyedCreate(t, q, "live", "live-1", "p")
	doneJob(t, q, "a", "old-1")
	doneJob(t, q, "a", "old-2")
	archiveNow(t, q, clock)
	clock.Advance(time.Hour - time.Minute - 2*time.Millisecond)
	doneJob(t, q, "a", "young-1")
	archiveNow(t, q, clock)
	if len(q.archived) != 3 || len(q.jobs) != 1 {
		t.Fatalf("archived %d, live %d; want 3 and 1", len(q.archived), len(q.jobs))
	}
	return q, s
}

func TestPruneStepTakesOnlyArchivedJobsAtOrBeforeTheCutoff(t *testing.T) {
	cut := pruneEpoch.Add(time.Hour)
	archived := map[uint64]*Job{
		1: {ID: 1, ArchivedAt: cut.Add(-time.Minute)},
		2: {ID: 2, ArchivedAt: cut},
		3: {ID: 3, ArchivedAt: cut.Add(time.Millisecond)},
		4: {ID: 4, ArchivedAt: cut.Add(-time.Hour)}, // written past the prune's archive_size
	}
	offs := map[uint64]int64{1: 0, 2: 100, 3: 200, 4: 300}
	got := pruneStep(archived, offs, cut, 300)
	if len(got) != 2 || got[0] != 1 || got[1] != 2 {
		t.Errorf("pruneStep = %v, want [1 2]", got)
	}
	if got := pruneStep(archived, offs, cut, 301); len(got) != 3 {
		t.Errorf("pruneStep with the whole archive = %v, want [1 2 4]", got)
	}
}

// Jobs on each side of the cutoff; the live job, older than any of them, is
// never touched; the keys of the pruned are free; nothing comes back after a
// restart or a compaction.
func TestPruneAcrossRestartAndCompaction(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s := agedArchive(t, dir, clock)
	for _, age := range []int64{999, maxPruneMS + 1} {
		_, _, err := q.Prune(ctx(t), age)
		wantKind(t, err, "requires")
	}
	pruned, remaining, err := q.Prune(ctx(t), 30*60_000)
	if err != nil || pruned != 2 || remaining != 1 {
		t.Fatalf("Prune = %d, %d, %v; want 2, 1", pruned, remaining, err)
	}
	check := func(q *Queue, stage string) {
		t.Helper()
		for _, id := range []uint64{2, 3} {
			if _, err := q.Get(ctx(t), id); !errors.Is(err, ErrNotFound) {
				t.Errorf("%s: Get(j_%d) = %v, want not found", stage, id, err)
			}
		}
		if j, err := q.Get(ctx(t), 4); err != nil || j.ArchivedAt.IsZero() {
			t.Errorf("%s: the young job %+v %v", stage, j, err)
		}
		if j, err := q.Get(ctx(t), 1); err != nil || j.State != Queued {
			t.Errorf("%s: the live job %+v %v", stage, j, err)
		}
		h, _ := q.Health(ctx(t))
		info, _ := q.Archive(ctx(t))
		if h.Archived != 1 || info.Archived != 1 || info.Oldest == nil || *info.Oldest != "2026-09-14T01:01:00.000Z" {
			t.Errorf("%s: health %+v, archive %+v", stage, h, *info.Oldest)
		}
	}
	check(q, "after the prune")
	q, s = reopen(t, dir, q, s, clock)
	check(q, "after a restart")
	closeQueue(q, s)
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	if data := readFile(t, filepath.Join(dir, logName)); strings.Contains(data, "prune") {
		t.Errorf("compact kept a prune record: %s", data)
	}
	if data := readFile(t, filepath.Join(dir, archiveName)); strings.Contains(data, "old-") || !strings.Contains(data, "young-1") {
		t.Errorf("compact's archive: %s", data)
	}
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer closeQueue(q, s)
	check(q, "after a compaction")
	// A freed key makes a new job; a used one answers its job.
	if j, created := keyedCreate(t, q, "a", "old-1", "again"); !created || j.ID != 5 {
		t.Errorf("create with a freed key = %+v, %v", j, created)
	}
	if j, created := keyedCreate(t, q, "a", "young-1", "again"); created || j.ID != 4 {
		t.Errorf("create with a used key = %+v, %v", j, created)
	}
}

// A prune is one record, and a prune that removes nothing writes nothing.
func TestPruneWritesOneRecordOrNone(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s := agedArchive(t, dir, clock)
	defer func() { closeQueue(q, s) }()
	path := filepath.Join(dir, logName)
	before := readFile(t, path)
	if n, m, err := q.Prune(ctx(t), 2*3600_000); err != nil || n != 0 || m != 3 {
		t.Fatalf("Prune = %d %d %v", n, m, err)
	}
	if after := readFile(t, path); after != before {
		t.Errorf("a prune that removed nothing wrote %q", after[len(before):])
	}
	if _, _, err := q.Prune(ctx(t), 1000); err != nil {
		t.Fatal(err)
	}
	var prunes []record
	for _, r := range decodeAll(t, []byte(readFile(t, path))) {
		if r.Op == "prune" {
			prunes = append(prunes, r)
		}
	}
	if len(prunes) != 1 || prunes[0].Count != 2 || prunes[0].Cutoff != "2026-09-14T01:00:59.000Z" {
		t.Errorf("prune records %+v", prunes)
	}
}

// A kill mid-record leaves the prune off the disk: the jobs are there at
// open, and the torn tail is cut.
func TestPruneKilledMidRecord(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s := agedArchive(t, dir, clock)
	path := filepath.Join(dir, logName)
	before := len(readFile(t, path))
	if n, _, err := q.Prune(ctx(t), 1000); err != nil || n != 2 {
		t.Fatalf("Prune = %d %v", n, err)
	}
	closeQueue(q, s)
	whole := readFile(t, path)
	for _, cut := range []int{before + 1, before + 20, len(whole) - 1} {
		if err := os.WriteFile(path, []byte(whole[:cut]), 0o644); err != nil {
			t.Fatal(err)
		}
		q, s, err := openQueue(dir, clock)
		if err != nil {
			t.Fatalf("cut at %d: %v", cut, err)
		}
		if len(q.archived) != 3 {
			t.Errorf("cut at %d: archived %d, want 3", cut, len(q.archived))
		}
		closeQueue(q, s)
		if got := len(readFile(t, path)); got != before {
			t.Errorf("cut at %d: the log is %d bytes after open, want %d", cut, got, before)
		}
	}
	if err := os.WriteFile(path, []byte(whole), 0o644); err != nil {
		t.Fatal(err)
	}
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer closeQueue(q, s)
	if len(q.archived) != 1 {
		t.Errorf("the whole record: archived %d, want 1", len(q.archived))
	}
}

// A job archived after the prune record, with archived_at at or before its
// cutoff (the clock stepped back), is not pruned at open: the record names
// the archive's length when it was written.
func TestPruneSparesAJobArchivedAfterIt(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Hour
	doneJob(t, q, "a", "old")
	clock.Advance(30 * time.Minute)
	doneJob(t, q, "b", "late")
	clock.Advance(30*time.Minute + time.Millisecond) // old archives
	if _, err := q.Health(ctx(t)); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Second)
	if n, _, err := q.Prune(ctx(t), 1000); err != nil || n != 1 {
		t.Fatalf("Prune = %d %v", n, err)
	}
	// The clock steps back 20 minutes and retain drops: late archives with
	// an archived_at before the prune's cutoff.
	clock.Advance(-20 * time.Minute)
	q.retain = time.Millisecond
	if _, err := q.Health(ctx(t)); err != nil {
		t.Fatal(err)
	}
	if len(q.archived) != 1 || q.archived[2] == nil {
		t.Fatalf("archived %v, want [2]", sortedIDs(q.archived))
	}
	q, s = reopen(t, dir, q, s, clock)
	defer func() { closeQueue(q, s) }()
	if len(q.archived) != 1 || q.archived[2] == nil {
		t.Errorf("after the restart the archive is %v", sortedIDs(q.archived))
	}
}

func TestVerifyRefusesABadPruneRecord(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(pruneEpoch)
	q, s := agedArchive(t, dir, clock)
	closeQueue(q, s)
	log := readFile(t, filepath.Join(dir, logName))
	archive := readFile(t, filepath.Join(dir, archiveName))
	size := len(archive)
	for _, c := range []struct{ rec, want string }{
		{`{"op":"prune","cutoff":"yesterday","count":1,"archive_size":10}`, `record prune at "yesterday": a prune's cutoff is a time`},
		{`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":0,"archive_size":10}`, `a prune's count is at least 1`},
		{`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":1,"archive_size":` + itoa(size+1) + `}`, `a prune's archive_size is within the archive`},
		{`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":2}`, `a prune's archive_size is within the archive`},
		{`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":2,"archive_size":10,"from":"a"}`, `a prune has only a cutoff, a count, and an archive_size`},
		{`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":3,"archive_size":` + itoa(size) + `}`, `a replayed prune removes other than the count its record names`},
	} {
		bad := t.TempDir()
		if err := os.WriteFile(filepath.Join(bad, archiveName), []byte(archive), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(bad, logName), []byte(log+lineFor(c.rec)), 0o644); err != nil {
			t.Fatal(err)
		}
		for _, cmd := range []string{"verify", "compact"} {
			code, out, errOut := runCmd(cmd, bad)
			if code != 1 || out != "" || !strings.HasPrefix(errOut, "jobq: "+bad) || !strings.Contains(errOut, c.want) {
				t.Errorf("%s of %s = %d, %q, %q; want %q", cmd, c.rec, code, out, errOut, c.want)
			}
		}
	}
	// The same record with its true count verifies, the prune applied.
	good := t.TempDir()
	os.WriteFile(filepath.Join(good, archiveName), []byte(archive), 0o644)
	os.WriteFile(filepath.Join(good, logName), []byte(log+lineFor(`{"op":"prune","cutoff":"2026-09-14T00:30:00.000Z","count":2,"archive_size":`+itoa(size)+`}`)), 0o644)
	if code, out, errOut := runCmd("verify", good); code != 0 || !strings.HasSuffix(out, "; archived 1\n") {
		t.Errorf("verify of a good prune = %d %q %q", code, out, errOut)
	}
}

// The offline prune prints the two counts and is the same record.
func TestPruneCommand(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Now().Add(-2 * time.Hour))
	q, s := agedArchive(t, dir, clock)
	closeQueue(q, s)
	for _, args := range [][]string{
		{"prune", dir}, {"prune", dir, "--older-than-ms"}, {"prune", dir, "--older-than-ms", "999"},
		{"prune", dir, "--older-than", "1000"}, {"prune", dir, "--older-than-ms", "01000"},
	} {
		if code, _, errOut := runCmd(args...); code != 2 || strings.Count(errOut, "\n") != 1 {
			t.Errorf("jobq %q = %d %q, want 2", args, code, errOut)
		}
	}
	// The young job was archived about an hour ago, the old ones two.
	if code, out, errOut := runCmd("prune", dir, "--older-than-ms", "5400000"); code != 0 || out != "pruned 2, remaining 1\n" {
		t.Errorf("prune = %d %q %q", code, out, errOut)
	}
	if code, out, _ := runCmd("verify", dir); code != 0 || !strings.HasSuffix(out, "; archived 1\n") {
		t.Errorf("verify after prune = %d %q", code, out)
	}
	if code, out, _ := runCmd("prune", dir, "--older-than-ms", "5400000"); code != 0 || out != "pruned 0, remaining 1\n" {
		t.Errorf("second prune = %d %q", code, out)
	}
	if code, _, errOut := runCmd("prune", filepath.Join(dir, "missing"), "--older-than-ms", "1000"); code != 1 || !strings.Contains(errOut, "no such file") {
		t.Errorf("prune of a missing folder = %d %q", code, errOut)
	}
}

func TestPruneAndArchiveRoutes(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Minute})
	h.want("Bearer p", "GET", "/archive", "", 200)
	if body := h.want("Bearer p", "GET", "/archive", "", 200); strings.TrimSpace(body) != `{"archived":0,"oldest_archived_at":null,"bytes":0}` {
		t.Errorf("empty archive = %s", body)
	}
	for i, key := range []string{"k1", "k2"} {
		h.want("Bearer p", "POST", "/jobs", `{"queue":"a","key":"`+key+`","payload":"p","max_tries":1}`, 201)
		h.want("Bearer w", "POST", "/queues/a/lease", "", 200)
		h.want("Bearer w", "POST", "/jobs/j_"+itoa(i+1)+"/ack", "", 200)
	}
	h.clock.Advance(time.Minute)
	h.want("Bearer p", "GET", "/health", "", 200)
	h.clock.Advance(10 * time.Second)
	body := h.want("Bearer p", "GET", "/archive", "", 200)
	var info ArchiveInfo
	if err := json.Unmarshal([]byte(body), &info); err != nil || info.Archived != 2 || info.Bytes != int64(len(h.archive.data)) ||
		info.Oldest == nil || *info.Oldest != "2026-09-14T12:01:00.000Z" {
		t.Errorf("archive = %s", body)
	}
	for _, bad := range []string{``, `{}`, `{"older_than_ms":999}`, `{"older_than_ms":"1000"}`, `{"older_than_ms":1000,"x":1}`, `{"older_than_ms":1.5}`} {
		h.want("Bearer p", "POST", "/archive/prune", bad, 400)
	}
	h.want("-", "POST", "/archive/prune", `{"older_than_ms":1000}`, 401)
	h.want("-", "GET", "/archive", ``, 401)
	h.want("Bearer p", "GET", "/archive/prune", ``, 405)
	if body := h.want("Bearer p", "POST", "/archive/prune", `{"older_than_ms":20000}`, 200); strings.TrimSpace(body) != `{"pruned":0,"remaining":2}` {
		t.Errorf("prune of nothing = %s", body)
	}
	if body := h.want("Bearer p", "POST", "/archive/prune", `{"older_than_ms":10000}`, 200); strings.TrimSpace(body) != `{"pruned":2,"remaining":0}` {
		t.Errorf("prune = %s", body)
	}
	h.want("Bearer p", "GET", "/jobs/j_1", "", 404)
	if body := h.want("Bearer p", "GET", "/health", "", 200); !strings.Contains(body, `"archived":0`) {
		t.Errorf("health = %s", body)
	}
	if body := h.want("Bearer p", "POST", "/jobs", `{"queue":"a","key":"k1","payload":"p","max_tries":1}`, 201); !strings.Contains(body, `"id":"j_3"`) {
		t.Errorf("create with the freed key = %s", body)
	}
	// A store that refuses the write answers 503 and prunes nothing.
	h.want("Bearer w", "POST", "/queues/a/lease", "", 200)
	h.want("Bearer w", "POST", "/jobs/j_3/ack", "", 200)
	h.clock.Advance(2 * time.Minute)
	h.want("Bearer p", "GET", "/health", "", 200)
	h.clock.Advance(2 * time.Second)
	h.file.fail = func(op string) bool { return op == "write" }
	h.want("Bearer p", "POST", "/archive/prune", `{"older_than_ms":1000}`, 503)
	h.file.fail = nil
	if body := h.want("Bearer p", "GET", "/jobs/j_3", "", 200); !strings.Contains(body, "archived_at") {
		t.Errorf("after a failed prune j_3 = %s", body)
	}
	boardMatchesLog(t, h)
}

// The background prune on a fixture clock and fixture ticks: every tick
// prunes with the retention age, the same record, and a tick that finds
// nothing writes nothing.
func TestBackgroundPrune(t *testing.T) {
	ticks := make(chan time.Time)
	type result struct {
		n   int
		err error
	}
	results := make(chan result, 1)
	cfg := BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Minute, Retention: time.Hour,
		pruneTicks: ticks, onPrune: func(n int, err error) { results <- result{n, err} }}
	h := newAPIHarnessWith(t, cfg)
	tick := func() result {
		t.Helper()
		ticks <- h.clock.Now()
		return <-results
	}
	h.want("Bearer p", "POST", "/jobs", `{"queue":"a","key":"k","payload":"p","max_tries":1}`, 201)
	h.want("Bearer p", "POST", "/jobs", `{"queue":"a","payload":"live","max_tries":1}`, 201)
	h.want("Bearer w", "POST", "/queues/a/lease", "", 200)
	h.want("Bearer w", "POST", "/jobs/j_1/ack", "", 200)
	h.clock.Advance(time.Minute)
	h.want("Bearer p", "GET", "/health", "", 200) // j_1 archives at 12:01
	size := len(h.file.data)
	if r := tick(); r.n != 0 || r.err != nil {
		t.Errorf("a tick with nothing old = %+v", r)
	}
	if len(h.file.data) != size {
		t.Error("a background prune that removed nothing wrote")
	}
	h.clock.Advance(time.Hour - time.Millisecond)
	if r := tick(); r.n != 0 {
		t.Errorf("a tick a millisecond early = %+v", r)
	}
	h.clock.Advance(time.Millisecond)
	if r := tick(); r.n != 1 || r.err != nil {
		t.Errorf("a tick at the age = %+v", r)
	}
	h.want("Bearer p", "GET", "/jobs/j_1", "", 404)
	h.want("Bearer p", "GET", "/jobs/j_2", "", 200) // live, and older than the age
	if !strings.Contains(string(h.file.data), `"op":"prune"`) {
		t.Error("no prune record in the log")
	}
	boardMatchesLog(t, h)
	// The loop ends with the board.
	if err := h.board.stop(ctx(t)); err != nil {
		t.Fatal(err)
	}
	select {
	case ticks <- h.clock.Now():
		t.Error("the loop took a tick after stop")
	case <-time.After(50 * time.Millisecond):
	}
}

func TestServeTakesRetention(t *testing.T) {
	dir := t.TempDir()
	for _, c := range []struct {
		val  string
		want time.Duration
	}{{"0", 0}, {"1000", time.Second}, {"3600000", time.Hour}} {
		_, _, cfg, msg := parseServe([]string{dir, "--retention", c.val})
		if msg != "" || cfg.Retention != c.want {
			t.Errorf("--retention %s = %v %q", c.val, cfg.Retention, msg)
		}
	}
	for _, val := range []string{"999", "-1", "01000", "x", "3153600000001"} {
		if _, _, _, msg := parseServe([]string{dir, "--retention", val}); msg == "" {
			t.Errorf("--retention %s was taken", val)
		}
	}
}
