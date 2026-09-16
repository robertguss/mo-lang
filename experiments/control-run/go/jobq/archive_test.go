package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Change 4: idempotent creates and the archive.

func TestValidKey(t *testing.T) {
	for _, k := range []string{"a", "order-1", "A_b-9", strings.Repeat("k", 64)} {
		if !validKey(k) {
			t.Errorf("validKey(%q) = false", k)
		}
	}
	for _, k := range []string{"", "a b", "é", "a/b", "a.b", strings.Repeat("k", 65), "a\n"} {
		if validKey(k) {
			t.Errorf("validKey(%q) = true", k)
		}
	}
}

func openDir(t *testing.T, dir string, clock Clock, retain time.Duration) *Queue {
	t.Helper()
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = retain
	t.Cleanup(func() { closeQueue(q, s) })
	return q
}

func closeQueue(q *Queue, s *Store) {
	_ = s.Close()
	_ = q.closeArchive()
}

func reopen(t *testing.T, dir string, q *Queue, s *Store, clock Clock) (*Queue, *Store) {
	t.Helper()
	if err := errors.Join(s.Close(), q.closeArchive()); err != nil {
		t.Fatal(err)
	}
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	return q, s
}

func keyedCreate(t *testing.T, q *Queue, queue, key, payload string) (Job, bool) {
	t.Helper()
	j, created, err := q.Create(ctx(t), queue, key, payload, 1, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	return j, created
}

// The second create answers the first job, whatever state it is in.
func TestSecondCreateAnswersTheFirstJobInEveryState(t *testing.T) {
	q, _, _, clock := newMemQueue()
	q.retain = time.Minute
	// Each state has its own queue, so a lease takes that state's job.
	setup := map[string]func(){
		"queued": func() {},
		"scheduled": func() {
			if _, _, err := q.Create(ctx(t), "q-scheduled", "scheduled", "p", 1, 1000, 0); err != nil {
				t.Fatal(err)
			}
		},
		"leased": func() { mustLease(t, q, "q-leased", "w", 60_000) },
		"done": func() {
			j := mustLease(t, q, "q-done", "w", 60_000)
			if _, err := q.Ack(ctx(t), j.ID, "w"); err != nil {
				t.Fatal(err)
			}
		},
		"dead": func() {
			j := mustLease(t, q, "q-dead", "w", 60_000)
			if _, err := q.Fail(ctx(t), j.ID, "w", "no"); err != nil {
				t.Fatal(err)
			}
		},
	}
	for _, state := range []string{"queued", "scheduled", "leased", "done", "dead"} {
		queue := "q-" + state
		var first Job
		if state != "scheduled" {
			var created bool
			if first, created = keyedCreate(t, q, queue, state, "first"); !created {
				t.Fatalf("%s: first create not created", state)
			}
		}
		setup[state]()
		if state == "scheduled" {
			first, _ = keyedCreate(t, q, queue, state, "ignored")
		}
		got, created := keyedCreate(t, q, queue, state, "second")
		if created || got.ID == 0 || string(got.State) != state || got.Payload == "second" {
			t.Errorf("%s: second create = %+v, created %v", state, got, created)
		}
		if first.ID != got.ID {
			t.Errorf("%s: second create answered %d, first made %d", state, got.ID, first.ID)
		}
	}
	// The rest of the body is not looked at on a second create.
	if j, created, err := q.Create(ctx(t), "q-queued", "queued", strings.Repeat("x", maxPayloadBytes+1), 0, -1, -1); err != nil || created || j.Payload != "first" {
		t.Errorf("second create with bad fields = %+v, %v, %v", j, created, err)
	}
	// The same key in another queue is another job.
	if _, created := keyedCreate(t, q, "other", "queued", "p"); !created {
		t.Error("a key in another queue was not a new job")
	}
	// Archived: the done and dead jobs leave the board and still answer.
	clock.Advance(2 * time.Minute)
	for _, state := range []string{"done", "dead"} {
		got, created := keyedCreate(t, q, "q-"+state, state, "third")
		if created || got.ArchivedAt.IsZero() || string(got.State) != state {
			t.Errorf("archived %s: create = %+v, created %v", state, got, created)
		}
	}
	if n := len(q.archived); n != 2 {
		t.Fatalf("%d archived, want 2", n)
	}
	// A delete frees the key, on the board and in the archive.
	for _, state := range []string{"queued", "done"} {
		j, _ := keyedCreate(t, q, "q-"+state, state, "x")
		if err := q.Delete(ctx(t), j.ID); err != nil {
			t.Fatal(err)
		}
		again, created := keyedCreate(t, q, "q-"+state, state, "after delete")
		if !created || again.ID == j.ID || again.Payload != "after delete" {
			t.Errorf("%s: create after delete = %+v, created %v", state, again, created)
		}
	}
}

func TestKeyedListAndBadKeys(t *testing.T) {
	h := newAPIHarness(t)
	body := h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k1","payload":"p","max_tries":1}`, 201)
	if v := decodeJob(t, body); v.Key == nil || *v.Key != "k1" {
		t.Errorf("created %s", body)
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k1","payload":"q","max_tries":1}`, 200)
	for _, b := range []string{
		`{"queue":"a","key":"","payload":"p","max_tries":1}`,
		`{"queue":"a","key":"a b","payload":"p","max_tries":1}`,
		`{"queue":"a","key":7,"payload":"p","max_tries":1}`,
		`{"queue":"a","key":null,"payload":"p","max_tries":0}`,
		`{"queue":"a","key":"k1","payload":"p"}`,
	} {
		h.want(w1, "POST", "/jobs", b, 400)
	}
	for path, want := range map[string]string{
		"/jobs?queue=a&key=k1":              `"id":"j_1"`,
		"/jobs?queue=a&key=k2":              `{"jobs":[]}`,
		"/jobs?queue=b&key=k1":              `{"jobs":[]}`,
		"/jobs?queue=a&key=k1&state=done":   `{"jobs":[]}`,
		"/jobs?queue=a&key=k1&state=queued": `"id":"j_1"`,
	} {
		if got := h.want(w1, "GET", path, "", 200); !strings.Contains(got, want) {
			t.Errorf("GET %s = %s, want %s", path, got, want)
		}
	}
	for _, path := range []string{"/jobs?key=k1", "/jobs?queue=a&key=", "/jobs?queue=a&key=a%20b", "/jobs?queue=a&key=k1&key=k2"} {
		h.want(w1, "GET", path, "", 400)
	}
}

// The key map is rebuilt by the replay: after a stop and start, after a
// compaction, and after the board's own restart.
func TestKeyMapSurvivesRestartAndCompaction(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Minute
	done, _ := keyedCreate(t, q, "a", "archived", "p")
	j := mustLease(t, q, "a", "w", 60_000)
	if _, err := q.Ack(ctx(t), j.ID, "w"); err != nil || j.ID != done.ID {
		t.Fatal(err, j.ID)
	}
	first, _ := keyedCreate(t, q, "a", "live", "p")
	gone, _ := keyedCreate(t, q, "a", "freed", "p")
	if err := q.Delete(ctx(t), gone.ID); err != nil {
		t.Fatal(err)
	}
	clock.Advance(2 * time.Minute)
	if _, err := q.Health(ctx(t)); err != nil { // the look archives
		t.Fatal(err)
	}
	if q.archived[done.ID] == nil {
		t.Fatal("not archived")
	}
	check := func(when string, q *Queue) {
		t.Helper()
		for key, want := range map[string]uint64{"live": first.ID, "archived": done.ID} {
			if got, created := keyedCreate(t, q, "a", key, "again"); created || got.ID != want {
				t.Errorf("%s: key %s = %+v, created %v; want %d", when, key, got, created, want)
			}
		}
	}
	check("before", q)
	q, s = reopen(t, dir, q, s, clock)
	check("after a restart", q)
	if err := errors.Join(s.Close(), q.closeArchive()); err != nil {
		t.Fatal(err)
	}
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	log, _ := os.ReadFile(filepath.Join(dir, logName))
	if bytes.Contains(log, []byte(`"archived"`)) || bytes.Contains(log, []byte(`"arch"`)) {
		t.Errorf("the compacted log still names the archived job:\n%s", log)
	}
	q = openDir(t, dir, clock, time.Minute)
	check("after a compaction", q)
	// The freed key makes a new job, and that holds after a reopen too.
	if _, created := keyedCreate(t, q, "a", "freed", "p"); !created {
		t.Error("a deleted job's key was not freed")
	}

	// The board's own restart replays the same way.
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k","payload":"p","max_tries":1}`, 201)
	h.board.crashNext()
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"other","max_tries":1}`, 503)
	if h.restarts() != 1 {
		t.Fatal("no restart")
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k","payload":"p","max_tries":1}`, 200)
}

// A record's key is checked at open, and two jobs with one key refuse the
// folder.
func TestKeysAreCheckedAtOpen(t *testing.T) {
	job := func(id, key string) string {
		return `{"op":"put","job":{"id":"` + id + `","queue":"a","key":"` + key + `","state":"queued","payload":"p","tries":0,"max_tries":1,` +
			`"backoff_ms":0,"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:00.000Z"}}`
	}
	for _, c := range []struct {
		lines []string
		want  string
	}{
		{[]string{job("j_1", "a b")}, "record j_1: key is 1 to 64 bytes"},
		{[]string{job("j_1", "")}, "record j_1: key is 1 to 64 bytes"},
		{[]string{job("j_1", "k"), job("j_2", "k")}, "a key names two jobs in one queue at once"},
		{[]string{job("j_1", "k"), job("j_1", "l")}, "a job's key changes"},
	} {
		dir := t.TempDir()
		writeLines(t, filepath.Join(dir, logName), c.lines...)
		if _, _, err := openQueue(dir, realClock{}); err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("open of %v = %v, want %q", c.lines, err, c.want)
		}
	}
}

func writeLines(t *testing.T, path string, bodies ...string) {
	t.Helper()
	var b strings.Builder
	for _, body := range bodies {
		b.WriteString(lineFor(body))
	}
	if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}
}

// The archive move is a pure step over one job.
func TestArchiveStep(t *testing.T) {
	now := time.Date(2026, 9, 14, 12, 0, 0, 0, time.UTC)
	retain := time.Hour
	for _, c := range []struct {
		state   State
		updated time.Time
		due     bool
	}{
		{Done, now.Add(-retain), true},
		{Dead, now.Add(-2 * retain), true},
		{Done, now.Add(-retain + time.Millisecond), false},
		{Queued, now.Add(-2 * retain), false},
		{Scheduled, now.Add(-2 * retain), false},
		{Leased, now.Add(-2 * retain), false},
	} {
		j := Job{ID: 1, State: c.state, UpdatedAt: c.updated}
		got, due := archiveStep(j, now, retain)
		if due != c.due || (due && (!got.ArchivedAt.Equal(now) || got.State != c.state || !got.UpdatedAt.Equal(c.updated))) {
			t.Errorf("archiveStep(%s at %v) = %+v, %v", c.state, c.updated, got, due)
		}
	}
}

// A fixture clock past retain: the next look moves the job, the archive
// holds its record with archived_at, the log its arch, and both replay to
// memory. Listings and counts leave it out; a read by id finds it.
func TestTheLookArchivesOldJobs(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: 10 * time.Second})
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"q","max_tries":1}`, 201)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"r","max_tries":1}`, 201)
	h.want(w1, "POST", "/queues/a/lease", "", 200)
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":1000}`, 200)
	h.clock.Advance(9 * time.Second) // j_2's lease ran out at 1 s: dead at 9 s
	h.want(w1, "GET", "/health", "", 200)
	h.clock.Advance(time.Second) // j_1 is 10 s old; j_2 1 s
	if len(h.archive.data) != 0 {
		t.Fatal("archived before a look")
	}
	health := h.want("-", "GET", "/health", "", 200)
	if !strings.Contains(health, `"queued":1,"scheduled":0,"leased":0,"done":0,"dead":1,"archived":1,`) {
		t.Errorf("health = %s", health)
	}
	arch := string(h.archive.data)
	if strings.Count(arch, "\n") != 1 || !strings.Contains(arch, `"id":"j_1"`) || !strings.Contains(arch, `"archived_at":"2026-09-14T12:00:10.000Z"`) {
		t.Errorf("archive = %s", arch)
	}
	if !strings.Contains(string(h.file.data), `{"op":"arch","id":"j_1"}`) {
		t.Errorf("the log has no arch record:\n%s", h.file.data)
	}
	boardMatchesLog(t, h)
	v := decodeJob(t, h.want(w1, "GET", "/jobs/j_1", "", 200))
	if v.State != Done || v.ArchivedAt == nil || *v.ArchivedAt != "2026-09-14T12:00:10.000Z" {
		t.Errorf("archived read = %+v", v)
	}
	for _, path := range []string{"/jobs", "/jobs?queue=a", "/jobs?state=done", "/queues"} {
		if body := h.want(w1, "GET", path, "", 200); strings.Contains(body, "j_1") || strings.Contains(body, `"done":1`) {
			t.Errorf("GET %s shows the archived job: %s", path, body)
		}
	}
	if body := h.want(w1, "POST", "/jobs/j_1/retry", "", 409); !strings.Contains(body, "archived") {
		t.Errorf("retry of archived = %s", body)
	}
	h.want(w1, "POST", "/jobs/j_1/ack", "", 409)
	h.clock.Advance(time.Second)
	h.want(w1, "POST", "/jobs/j_2/retry", "", 200) // dead 2 s: not yet archived
	h.want(w1, "DELETE", "/jobs/j_1", "", 204)
	h.want(w1, "GET", "/jobs/j_1", "", 404)
	h.want(w1, "DELETE", "/jobs/j_1", "", 404)
	if !strings.HasSuffix(string(h.archive.data), `{"op":"del","id":"j_1"}`+"\n") {
		t.Errorf("no tombstone:\n%s", h.archive.data)
	}
	boardMatchesLog(t, h)
	if body := h.want("-", "GET", "/health", "", 200); !strings.Contains(body, `"archived":0`) {
		t.Errorf("health after the delete = %s", body)
	}
}

// A kill between the archive's append and the log's arch leaves the job in
// both files: the open archives it, counts it once, and compact drops it
// from the log.
func TestOpenWithAJobInBothFiles(t *testing.T) {
	dir := t.TempDir()
	put := `{"op":"put","job":{"id":"j_1","queue":"a","key":"k","state":"done","payload":"p","tries":1,"max_tries":1,"backoff_ms":0,` +
		`"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:01.000Z"%s}}`
	live := strings.Replace(put, "%s", "", 1)
	archived := strings.Replace(put, "%s", `,"archived_at":"2026-09-15T00:00:01.000Z"`, 1)
	writeLines(t, filepath.Join(dir, logName), live)
	writeLines(t, filepath.Join(dir, archiveName), archived)
	code, out, errOut := runCmd("verify", dir)
	if code != 0 || out != "0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_2; archived 1\n" {
		t.Errorf("verify = %d, %q, %q", code, out, errOut)
	}
	q := openDir(t, dir, realClock{}, time.Hour)
	h, err := q.Health(ctx(t))
	if err != nil || h.Done != 0 || h.Archived != 1 || len(q.jobs) != 0 {
		t.Errorf("health = %+v, %v", h, err)
	}
	if j, created := keyedCreate(t, q, "a", "k", "p"); created || j.ID != 1 {
		t.Errorf("key after open = %+v, %v", j, created)
	}
	closeQueue(q, q.store.(*Store))
	if code, _, errOut := runCmd("compact", dir); code != 0 {
		t.Fatal(errOut)
	}
	log, _ := os.ReadFile(filepath.Join(dir, logName))
	if want := lineFor(`{"op":"meta","next_id":2}`); string(log) != want {
		t.Errorf("compacted log = %q, want %q", log, want)
	}
	arch, _ := os.ReadFile(filepath.Join(dir, archiveName))
	if want := lineFor(archived); string(arch) != want {
		t.Errorf("compacted archive = %q, want %q", arch, want)
	}
	// A tombstone is dropped by the next compaction, with its job.
	q, s, err := openQueue(dir, realClock{})
	if err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(ctx(t), 1); err != nil {
		t.Fatal(err)
	}
	closeQueue(q, s)
	if code, _, errOut := runCmd("compact", dir); code != 0 {
		t.Fatal(errOut)
	}
	if arch, _ := os.ReadFile(filepath.Join(dir, archiveName)); len(arch) != 0 {
		t.Errorf("archive after compacting a tombstone = %q", arch)
	}
	if code, out, _ := runCmd("verify", dir); code != 0 || !strings.HasSuffix(out, "next id j_2; archived 0\n") {
		t.Errorf("verify = %d %q", code, out)
	}
}

// Every write boundary of a load of short-lived jobs, the move's two writes
// included, is a place a kill can fall. Opening the files as they stood
// there loses no job, never shows one twice, and never brings an archived
// one back.
func TestKillAtEveryWriteOfTheMove(t *testing.T) {
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	type point struct{ arch, log []byte }
	var points []point
	f, a := &memFile{}, &memFile{}
	snap := func(string) bool {
		points = append(points, point{append([]byte{}, a.data...), append([]byte{}, f.data...)})
		return false
	}
	f.fail, a.fail = snap, snap // called before each write, sync, and truncate
	b := newMemBoard(t, f, a, clock, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Second})
	h := &apiHarness{t: t, api: &API{b: b}, board: b, file: f, archive: a, clock: clock}
	for i := range 40 {
		queue := "a"
		if i%3 == 0 {
			queue = "b"
		}
		h.want(w1, "POST", "/jobs", `{"queue":"`+queue+`","payload":"p","max_tries":1}`, 201)
		if i%3 == 0 {
			h.want(w1, "POST", "/queues/b/lease", "", 200)
			h.want(w1, "POST", "/jobs/j_"+itoa(i+1)+"/ack", "", 200)
		}
		clock.Advance(300 * time.Millisecond)
	}
	snap("")
	if len(h.q().archived) == 0 {
		t.Fatal("nothing was archived")
	}
	archivedBy := map[uint64]int{} // the first point that holds each archived job
	for n, p := range points {
		q := newQueue(clock)
		if _, err := replay(bytes.NewReader(p.arch), q.applyArchived); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		if _, err := replay(bytes.NewReader(p.log), q.applyRecord); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		if err := q.checkApart(); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		counted := 0
		for _, c := range q.counts {
			counted += c
		}
		if counted != len(q.jobs) {
			t.Fatalf("point %d: the board counts %d of its %d jobs", n, counted, len(q.jobs))
		}
		for id := range q.archived {
			if _, ok := archivedBy[id]; !ok {
				archivedBy[id] = n
			}
		}
		for id, first := range archivedBy {
			if first < n && q.archived[id] == nil {
				t.Fatalf("point %d: j_%d came back from the archive", n, id)
			}
		}
		// Every job created before this point is here, on the board or
		// archived.
		for id := uint64(1); id < q.nextID; id++ {
			if q.lookup(id) == nil {
				t.Fatalf("point %d: j_%d lost", n, id)
			}
		}
	}
	split := 0
	for n := 1; n < len(points); n++ {
		if len(points[n].arch) > len(points[n-1].arch) && bytes.Equal(points[n].log, points[n-1].log) {
			split++
		}
	}
	if split == 0 {
		t.Error("no point fell between the archive's append and the log's")
	}
}

func itoa(n int) string { return formatID(uint64(n))[2:] }

// A failed archive write moves nothing; a failed log write after the
// archive's leaves the job archived, and the arch record goes with the next
// write the log takes.
func TestTheMovesWritesFailingBetween(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Second})
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	h.want(w1, "POST", "/queues/a/lease", "", 200)
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
	h.clock.Advance(time.Second)

	h.archive.fail = func(string) bool { return true }
	if body := h.want("-", "GET", "/health", "", 200); !strings.Contains(body, `"done":1,"dead":0,"archived":0`) {
		t.Errorf("health with the archive failing = %s", body)
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"q","max_tries":1}`, 201)
	boardMatchesLog(t, h)
	h.archive.fail = nil

	h.file.fail = func(string) bool { return true }
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"r","max_tries":1}`, 503)
	if body := h.want("-", "GET", "/health", "", 200); !strings.Contains(body, `"done":0,"dead":0,"archived":1`) {
		t.Errorf("health with the log failing = %s", body)
	}
	if bytes.Contains(h.file.data, []byte(`"arch"`)) {
		t.Fatal("arch written through a failing log")
	}
	boardMatchesLog(t, h) // the archive's record wins
	h.file.fail = nil
	h.want("-", "GET", "/health", "", 200)
	if !bytes.Contains(h.file.data, []byte(`{"op":"arch","id":"j_1"}`)) {
		t.Errorf("the arch record was never written:\n%s", h.file.data)
	}
	// A failed tombstone deletes nothing.
	h.archive.fail = func(string) bool { return true }
	h.want(w1, "DELETE", "/jobs/j_1", "", 503)
	h.archive.fail = nil
	h.want(w1, "GET", "/jobs/j_1", "", 200)
	boardMatchesLog(t, h)
}

// verify checks every archive record and refuses the folder on a bad one,
// as serve and compact do.
func TestVerifyRefusesABadArchiveRecord(t *testing.T) {
	base := `{"id":"j_1","queue":"a","state":"%s","payload":"p","tries":1,"max_tries":1,"backoff_ms":0,` +
		`"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:01.000Z"%s}`
	job := func(state, extra string) string {
		return `{"op":"put","job":` + strings.Replace(strings.Replace(base, "%s", state, 1), "%s", extra, 1) + `}`
	}
	at := `,"archived_at":"2026-09-14T00:00:02.000Z"`
	for _, c := range []struct {
		lines []string
		want  string
	}{
		{[]string{job("leased", at+`,"worker":"w","lease_until":"2026-09-14T00:00:09.000Z"`)}, "archive record j_1: an archived job is done or dead"},
		{[]string{job("done", "")}, "archive record j_1: an archived job has archived_at"},
		{[]string{job("done", `,"archived_at":"2026-09-14T00:00:00.500Z"`)}, "archive record j_1: an archived job's archived_at is at or after its updated_at"},
		{[]string{job("dead", at+`,"key":"a b"`)}, "archive record j_1: key is 1 to 64 bytes"},
		{[]string{job("done", at), job("done", at)}, "job j_1 is archived twice"},
		{[]string{`{"op":"del","id":"j_1"}`}, "del of unknown archived job"},
		{[]string{`{"op":"meta","next_id":3}`}, "unknown archive op"},
	} {
		dir := t.TempDir()
		writeLines(t, filepath.Join(dir, archiveName), c.lines...)
		for _, cmd := range []string{"verify", "compact", "serve"} {
			code, out, errOut := runCmd(cmd, dir)
			if code != 1 || out != "" || !strings.HasPrefix(errOut, "jobq: ") || !strings.Contains(errOut, c.want) {
				t.Errorf("%s of %v = %d, %q, %q; want %q", cmd, c.lines, code, out, errOut, c.want)
			}
		}
	}
	// A live record with archived_at is refused too, and an arch for a job
	// the archive does not hold.
	dir := t.TempDir()
	writeLines(t, filepath.Join(dir, logName), job("done", at))
	if code, _, errOut := runCmd("verify", dir); code != 1 || errOut != "jobq: "+dir+": record j_1: a live job has no archived_at\n" {
		t.Errorf("verify = %d %q", code, errOut)
	}
	writeLines(t, filepath.Join(dir, logName), job("done", ""), `{"op":"arch","id":"j_1"}`)
	if code, _, errOut := runCmd("verify", dir); code != 1 || !strings.Contains(errOut, "arch of a job not in the archive") {
		t.Errorf("verify = %d %q", code, errOut)
	}
	// A torn last archive line is cut like the log's.
	dir = t.TempDir()
	good := lineFor(job("done", at))
	if err := os.WriteFile(filepath.Join(dir, archiveName), []byte(good+good[:len(good)/2]), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, out, errOut := runCmd("verify", dir); code != 0 || !strings.HasSuffix(out, "next id j_2; archived 1\n") {
		t.Errorf("verify of a torn archive = %d %q %q", code, out, errOut)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, archiveName)); string(data) != good {
		t.Errorf("torn archive not cut: %q", data)
	}
	// No archive file is an empty archive, and opening makes none.
	dir = t.TempDir()
	if code, out, _ := runCmd("verify", dir); code != 0 || !strings.HasSuffix(out, "; archived 0\n") {
		t.Errorf("verify of an empty folder = %d %q", code, out)
	}
	if _, err := os.Stat(filepath.Join(dir, archiveName)); err == nil {
		t.Error("verify made an archive file")
	}
}

func TestRetainOption(t *testing.T) {
	for _, c := range []struct {
		args []string
		want time.Duration
		ok   bool
	}{
		{[]string{"d"}, 24 * time.Hour, true},
		{[]string{"d", "--retain-ms", "1000"}, time.Second, true},
		{[]string{"d", "--retain-ms", "2678400000"}, 31 * 24 * time.Hour, true},
		{[]string{"d", "--retain-ms", "999"}, 0, false},
		{[]string{"d", "--retain-ms", "2678400001"}, 0, false},
		{[]string{"d", "--retain-ms", "01000"}, 0, false},
		{[]string{"d", "--retain-ms", "1000", "--retain-ms", "1000"}, 0, false},
	} {
		_, _, cfg, msg := parseServe(c.args)
		if (msg == "") != c.ok || (c.ok && cfg.retain() != c.want) {
			t.Errorf("parseServe(%q) = %v, %q", c.args, cfg.Retain, msg)
		}
	}
	// The served board archives after the configured retain.
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	b, err := openBoard(dir, clock, BoardConfig{MaxRestarts: 1, Window: time.Minute, Retain: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	defer b.stop(ctx(t))
	h := &apiHarness{t: t, api: &API{b: b}, board: b, clock: clock}
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	h.want(w1, "POST", "/queues/a/lease", "", 200)
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
	clock.Advance(5 * time.Second)
	var got Health
	if err := json.Unmarshal([]byte(h.want("-", "GET", "/health", "", 200)), &got); err != nil || got.Archived != 1 {
		t.Errorf("health = %+v, %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(dir, archiveName)); err != nil {
		t.Error(err)
	}
}
