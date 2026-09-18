package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"
)

// Change 5: a queue renamed with jobs in flight. One record in the log; every
// job of the queue, in every state, on the board or archived, moves with its
// key; a lease moves untouched.

// busyQueue fills queue a with a job in every state, each keyed, one of
// them archived and one leased to w1 until well after now, and a job in b.
func busyQueue(t *testing.T) (*Queue, *memFile, *manualClock, map[State]uint64) {
	t.Helper()
	q, _, f, clock := newMemQueue()
	q.retain = time.Hour
	ids := map[State]uint64{}
	create := func(key string, maxTries int, delayMS int64) Job {
		j, _, err := q.Create(ctx(t), "a", key, "p", maxTries, delayMS, 0)
		if err != nil {
			t.Fatal(err)
		}
		return j
	}
	// done, then archived an hour later
	archived := create("k-arch", 1, 0)
	mustLease(t, q, "a", "w0", 1_000)
	if _, err := q.Ack(ctx(t), archived.ID, "w0"); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Hour)
	create("k-dead", 1, 0)
	mustLease(t, q, "a", "w0", 100)
	clock.Advance(time.Second) // runs out on its last try: dead
	ids[Dead] = 2
	ids[Done] = create("k-done", 1, 0).ID
	mustLease(t, q, "a", "w0", 1_000)
	if _, err := q.Ack(ctx(t), ids[Done], "w0"); err != nil {
		t.Fatal(err)
	}
	ids[Leased] = create("k-leased", 2, 0).ID
	mustLease(t, q, "a", "w1", 60_000)
	ids[Queued] = create("k-queued", 2, 0).ID
	ids[Scheduled] = create("k-sched", 2, 60_000).ID
	if _, _, err := q.Create(ctx(t), "b", "k-queued", "other", 1, 0, 0); err != nil {
		t.Fatal(err)
	}
	if _, err := q.Get(ctx(t), archived.ID); err != nil || q.archived[archived.ID] == nil {
		t.Fatalf("job %d not archived: %v", archived.ID, err)
	}
	for st, id := range ids {
		if q.jobs[id].State != st {
			t.Fatalf("j_%d is %s, want %s", id, q.jobs[id].State, st)
		}
	}
	ids["archived"] = archived.ID
	return q, f, clock, ids
}

func queueOf(q *Queue) map[uint64]string {
	out := map[uint64]string{}
	for _, jobs := range []map[uint64]*Job{q.jobs, q.archived} {
		for id, j := range jobs {
			out[id] = j.Queue
		}
	}
	return out
}

func TestRenameMovesEveryJobWithItsKey(t *testing.T) {
	q, f, clock, ids := busyQueue(t)
	leased := *q.jobs[ids[Leased]]
	before := len(f.data)
	moved, err := q.Rename(ctx(t), "a", "c")
	if err != nil || moved != 6 {
		t.Fatalf("Rename = %d, %v; want 6 moved", moved, err)
	}
	if recs := decodeAll(t, f.data[before:]); len(recs) != 1 || recs[0].Op != "rename" || recs[0].From != "a" || recs[0].To != "c" {
		t.Fatalf("the rename wrote %+v, want one rename record", recs)
	}
	for id, name := range queueOf(q) {
		if want := "c"; id == 7 {
			want = "b"
			if name != want {
				t.Errorf("j_%d is in %s, want %s", id, name, want)
			}
		} else if name != want {
			t.Errorf("j_%d is in %s, want %s", id, name, want)
		}
	}
	// The lease is the same lease: worker, lease_until, tries.
	if got := *q.jobs[ids[Leased]]; got.Worker != leased.Worker || !got.LeaseUntil.Equal(leased.LeaseUntil) ||
		got.Tries != leased.Tries || got.State != Leased {
		t.Errorf("the lease in flight became %+v, was %+v", got, leased)
	}
	// Keys: used in c, free in a; b's own key is untouched.
	for _, key := range []string{"k-arch", "k-dead", "k-done", "k-leased", "k-queued", "k-sched"} {
		if got, err := q.List(ctx(t), "c", "", key); err != nil || len(got) != 1 {
			t.Errorf("key %s in c = %v, %v", key, got, err)
		}
		if got, _ := q.List(ctx(t), "a", "", key); len(got) != 0 {
			t.Errorf("key %s still used in a: %v", key, got)
		}
	}
	if got, _ := q.List(ctx(t), "b", "", "k-queued"); len(got) != 1 || got[0].ID != 7 {
		t.Errorf("b's key = %v", got)
	}
	qs, _ := q.Queues(ctx(t))
	if len(qs) != 2 || qs[0].Name != "b" || qs[1] != (QueueCounts{Name: "c", Queued: 1, Scheduled: 1, Leased: 1, Done: 1, Dead: 1}) {
		t.Errorf("queues after the rename = %+v", qs)
	}
	if _, ok, err := q.Lease(ctx(t), "a", "w2", 1_000); ok || err != nil {
		t.Errorf("a lease on the old name = %v, %v; want nothing", ok, err)
	}
	clock.Advance(time.Second)
	if d, err := q.Ack(ctx(t), ids[Leased], "w1"); err != nil || d.State != Done || d.Queue != "c" {
		t.Errorf("ack of the lease in flight = %+v, %v", d, err)
	}
	if l := mustLease(t, q, "c", "w2", 1_000); l.ID != ids[Queued] {
		t.Errorf("a lease on the new name gave j_%d", l.ID)
	}
	// Replayed, the log says the same.
	if got, want := snapshot(replayBoth(t, q.archive.f.(*memFile).data, f.data)), snapshot(q); !reflect.DeepEqual(got, want) {
		t.Errorf("replay differs:\n%v\n%v", got, want)
	}
}

func TestRenameBackRestoresEverything(t *testing.T) {
	q, _, _, _ := busyQueue(t)
	want, keys := snapshot(q), fmt.Sprint(sortedKeys(q.keys))
	if _, err := q.Rename(ctx(t), "a", "c"); err != nil {
		t.Fatal(err)
	}
	if n, err := q.Rename(ctx(t), "c", "a"); err != nil || n != 6 {
		t.Fatalf("rename back = %d, %v", n, err)
	}
	if got := snapshot(q); !reflect.DeepEqual(got, want) {
		t.Errorf("after renaming back:\n%v\nwant\n%v", got, want)
	}
	if got := fmt.Sprint(sortedKeys(q.keys)); got != keys {
		t.Errorf("keys after renaming back = %s, want %s", got, keys)
	}
	// A name freed by a rename is a fresh queue, and can be renamed onto.
	if _, err := q.Rename(ctx(t), "a", "c"); err != nil {
		t.Fatal(err)
	}
	fresh, created, err := q.Create(ctx(t), "a", "k-queued", "new", 1, 0, 0)
	if err != nil || !created || fresh.Queue != "a" {
		t.Fatalf("keyed create into the freed name = %+v, %v, %v", fresh, created, err)
	}
	if _, err := q.Rename(ctx(t), "c", "a"); !errors.Is(err, ErrConflict) {
		t.Errorf("rename onto the fresh queue = %v, want 409", err)
	}
	if n, err := q.Rename(ctx(t), "a", "d"); err != nil || n != 1 {
		t.Errorf("rename of the fresh queue = %d, %v", n, err)
	}
}

func sortedKeys(keys map[keyRef]uint64) []string {
	var out []string
	for ref, id := range keys {
		out = append(out, fmt.Sprintf("%s/%s=%d", ref.queue, ref.key, id))
	}
	sort.Strings(out)
	return out
}

func TestRenameStatuses(t *testing.T) {
	q, _, clock, ids := busyQueue(t)
	for name, c := range map[string]struct {
		from, to string
		want     error
	}{
		"an unknown queue":           {"nope", "c", ErrNotFound},
		"onto a live queue":          {"a", "b", ErrConflict},
		"onto itself":                {"a", "a", ErrConflict},
		"onto a queue only archived": {"b", "a", ErrConflict},
	} {
		if name == "onto a queue only archived" {
			// Leave a with its archived job only.
			for st, id := range ids {
				if st == "archived" {
					continue
				}
				if st == Leased {
					if _, err := q.Ack(ctx(t), id, "w1"); err != nil {
						t.Fatal(err)
					}
				}
				if err := q.Delete(ctx(t), id); err != nil {
					t.Fatal(err)
				}
			}
		}
		_, err := q.Rename(ctx(t), c.from, c.to)
		if !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
		if c.want == ErrConflict && !strings.Contains(err.Error(), "exists") {
			t.Errorf("%s: %q does not say exists", name, err)
		}
	}
	for _, c := range [][2]string{{"a b", "c"}, {"a", ""}, {"a", "c/d"}, {"a", strings.Repeat("q", 65)}} {
		_, err := q.Rename(ctx(t), c[0], c[1])
		wantKind(t, err, "requires")
	}
	// A queue whose only job is archived is a queue: it renames.
	clock.Advance(time.Second)
	if n, err := q.Rename(ctx(t), "a", "c"); err != nil || n != 1 || q.archived[ids["archived"]].Queue != "c" {
		t.Errorf("rename of an archived-only queue = %d, %v", n, err)
	}
}

// The key map's rename is a pure step. A key already used in the target
// would name two jobs there, and the step says so; Rename needs no code for
// that case, because it refuses any target holding a job, and every key in
// the map names a job that is held (a delete frees its key).
func TestRenameKeysStep(t *testing.T) {
	keys := map[keyRef]uint64{{"a", "x"}: 1, {"a", "y"}: 2, {"b", "x"}: 3}
	got, err := renameKeys(keys, "a", "c")
	want := map[keyRef]uint64{{"c", "x"}: 1, {"c", "y"}: 2, {"b", "x"}: 3}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("renameKeys = %v, %v", got, err)
	}
	if len(keys) != 3 || keys[keyRef{"a", "x"}] != 1 {
		t.Errorf("renameKeys changed its argument: %v", keys)
	}
	_, err = renameKeys(keys, "a", "b")
	wantKind(t, err, "never")
	j := Job{ID: 1, Queue: "a", Key: "x", State: Leased, Worker: "w", Tries: 1}
	if n, ok := renameStep(j, "a", "c"); !ok || n.Queue != "c" || n.Worker != "w" || n.Key != "x" || n.Tries != 1 {
		t.Errorf("renameStep = %+v, %v", n, ok)
	}
	if n, ok := renameStep(j, "b", "c"); ok || n != j {
		t.Errorf("renameStep of another queue = %+v, %v", n, ok)
	}
}

// A job created into the old name after the rename record stays there; one
// created before it moved.
func TestReplayWithARenameBetweenJobRecords(t *testing.T) {
	q, _, f, _ := newMemQueue()
	mustCreate(t, q, "a", 1)
	if _, err := q.Rename(ctx(t), "a", "b"); err != nil {
		t.Fatal(err)
	}
	mustCreate(t, q, "a", 1)
	mustLease(t, q, "b", "w", 1_000)
	r := replayBytes(t, f.data)
	if r.jobs[1].Queue != "b" || r.jobs[2].Queue != "a" || r.jobs[1].State != Leased {
		t.Errorf("replayed %+v %+v", r.jobs[1], r.jobs[2])
	}
	if !reflect.DeepEqual(snapshot(r), snapshot(q)) {
		t.Error("replay differs from memory")
	}
}

// jobLine is a job record for a hand-written log.
func jobLine(id, queue, state, extra string) string {
	return fmt.Sprintf(`{"op":"put","job":{"id":"%s","queue":"%s","state":"%s","payload":"p","tries":%d,"max_tries":1,"backoff_ms":0,`+
		`"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:01.000Z"%s}}`, id, queue, state, map[bool]int{true: 1}[state != "queued"], extra)
}

func TestVerifyRefusesABadRenameRecord(t *testing.T) {
	for _, c := range []struct {
		rename, want string
	}{
		{`{"op":"rename","from":"a b","to":"c","next_id":2}`, `record rename "a b" to "c": a rename's from and to are 1 to 64 bytes`},
		{`{"op":"rename","from":"a","to":"","next_id":2}`, `record rename "a" to "": a rename's from and to are 1 to 64 bytes`},
		{`{"op":"rename","from":"a","to":"a","next_id":2}`, `record rename "a" to "a": a rename's from and to differ`},
		{`{"op":"rename","from":"a","to":"c"}`, `record rename "a" to "c": a rename has next_id`},
		{`{"op":"rename","from":"a","to":"c","next_id":2,"id":"j_1"}`, `a rename has no job and no id`},
	} {
		dir := t.TempDir()
		writeLines(t, filepath.Join(dir, logName), jobLine("j_1", "a", "queued", ""), c.rename)
		for _, cmd := range []string{"verify", "compact", "serve"} {
			code, out, errOut := runCmd(cmd, dir)
			if code != 1 || out != "" || !strings.HasPrefix(errOut, "jobq: "+dir+": ") || !strings.Contains(errOut, c.want) {
				t.Errorf("%s of %s = %d, %q, %q; want %q", cmd, c.rename, code, out, errOut, c.want)
			}
		}
	}
	// A good one verifies and counts the job once.
	dir := t.TempDir()
	writeLines(t, filepath.Join(dir, logName), jobLine("j_1", "a", "queued", ""), `{"op":"rename","from":"a","to":"c","next_id":2}`)
	if code, out, _ := runCmd("verify", dir); code != 0 || !strings.HasPrefix(out, "1 jobs: queued 1,") {
		t.Errorf("verify of a good rename = %d %q", code, out)
	}
}

// The archive is not rewritten by a rename: an archived job's queue is the
// log's renames applied to its archive record, and only the renames written
// after the job was archived. Compact folds them all in.
func TestCompactFoldsTwoRenamesAndTheArchive(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Minute
	done := func(queue, key string) uint64 {
		j, _, err := q.Create(ctx(t), queue, key, "p", 1, 0, 0)
		if err != nil {
			t.Fatal(err)
		}
		mustLease(t, q, queue, "w", 1_000)
		if _, err := q.Ack(ctx(t), j.ID, "w"); err != nil {
			t.Fatal(err)
		}
		return j.ID
	}
	old := done("a", "k1") // archived under a, before both renames
	i := done("x", "")     // x, then renamed to y before j is archived
	j := done("b", "")     // b, then renamed to x, then archived under x
	clock.Advance(time.Minute)
	if _, err := q.Get(ctx(t), old); err != nil || len(q.archived) != 3 {
		t.Fatalf("archived %d, %v", len(q.archived), err)
	}
	live := mustCreate(t, q, "a", 1).ID
	q, s = reopen(t, dir, q, s, clock)
	q.retain = time.Minute
	// i2 and j2 are live through the first renames and archived after them.
	i2 := done("x", "")
	j2 := done("b", "")
	for _, r := range [][2]string{{"x", "y"}, {"a", "c"}, {"c", "d"}} {
		if _, err := q.Rename(ctx(t), r[0], r[1]); err != nil {
			t.Fatal(err)
		}
	}
	clock.Advance(time.Minute)
	if _, err := q.Get(ctx(t), i2); err != nil || q.archived[i2] == nil || q.archived[j2] == nil {
		t.Fatalf("i2, j2 not archived: %v", err)
	}
	// The archive still holds old under its old name.
	if arch := readFile(t, filepath.Join(dir, archiveName)); !strings.Contains(arch, `"queue":"a"`) {
		t.Fatalf("the archive was rewritten by a rename:\n%s", arch)
	}
	if _, err := q.Rename(ctx(t), "b", "z"); err != nil { // after j2's archive record
		t.Fatal(err)
	}
	want := map[uint64]string{old: "d", i: "y", j: "z", live: "d", i2: "y", j2: "z"}
	check := func(when string, q *Queue) {
		t.Helper()
		if got := queueOf(q); !reflect.DeepEqual(got, want) {
			t.Errorf("%s: queues %v, want %v", when, got, want)
		}
		if got, _ := q.List(ctx(t), "d", "", "k1"); len(got) != 1 || got[0].ID != old {
			t.Errorf("%s: key k1 in d = %v", when, got)
		}
	}
	check("live", q)
	q, s = reopen(t, dir, q, s, clock)
	check("reopened", q)
	closeQueue(q, s)
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	log, arch := readFile(t, filepath.Join(dir, logName)), readFile(t, filepath.Join(dir, archiveName))
	if strings.Contains(log, "rename") || strings.Contains(arch, `"queue":"a"`) || strings.Contains(arch, `"queue":"b"`) ||
		strings.Contains(arch, `"queue":"x"`) {
		t.Errorf("compact left a rename or an old name:\n%s\n%s", log, arch)
	}
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer closeQueue(q, s)
	check("compacted", q)
}

// The case a count of ids alone gets wrong: j is archived under the name a
// that another queue had before a rename, so that rename must not touch it.
func TestAnArchiveRecordWrittenAfterARenameKeepsItsName(t *testing.T) {
	q, _, f, clock := newMemQueue()
	q.retain = time.Minute
	i := mustCreate(t, q, "a", 1).ID
	j := mustCreate(t, q, "b", 1).ID
	if _, err := q.Rename(ctx(t), "a", "c"); err != nil {
		t.Fatal(err)
	}
	if _, err := q.Rename(ctx(t), "b", "a"); err != nil {
		t.Fatal(err)
	}
	mustLease(t, q, "a", "w", 1_000)
	if _, err := q.Ack(ctx(t), j, "w"); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Minute)
	later := mustCreate(t, q, "c-new", 1).ID // the arch record goes with this write
	if q.archived[j] == nil || q.archived[j].Queue != "a" {
		t.Fatalf("j = %+v", q.archived[j])
	}
	arch := q.archive.f.(*memFile).data
	r := replayBoth(t, arch, f.data)
	if got, want := queueOf(r), map[uint64]string{i: "c", j: "a", later: "c-new"}; !reflect.DeepEqual(got, want) {
		t.Errorf("replayed %v, want %v", got, want)
	}
	// A kill after the archive's write and before the log's: the log has
	// j's puts and no arch. The open archives j under its record's name,
	// and the next write gives the log its arch, so a later rename moves j.
	cut := bytes.LastIndex(f.data[:len(f.data)-1], []byte("\n")) + 1
	for cut > 0 && !bytes.Contains(f.data[cut:], []byte(`"arch"`)) {
		cut = bytes.LastIndex(f.data[:cut-1], []byte("\n")) + 1
	}
	killed := append([]byte{}, f.data[:cut]...)
	nf, na := &memFile{data: killed}, &memFile{data: append([]byte{}, arch...)}
	b := newMemBoard(t, nf, na, clock, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Minute})
	h := &apiHarness{t: t, api: &API{b: b}, board: b, file: nf, archive: na, clock: clock}
	if got := queueOf(h.q()); got[j] != "a" || got[i] != "c" {
		t.Fatalf("after the kill: %v", got)
	}
	if len(h.q().unlogged) != 1 {
		t.Fatalf("unlogged after the open = %v", h.q().unlogged)
	}
	h.want(w1, "POST", "/queues/a/rename", `{"to":"e"}`, 200)
	boardMatchesLog(t, h)
	if got := queueOf(replayBoth(t, na.data, nf.data)); got[j] != "e" {
		t.Errorf("the rename after the kill: %v", got)
	}
}

// A kill inside compact leaves the old pair or the new pair, never a new
// log with an old archive.
func TestAKilledCompactOpensWhole(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	q.retain = time.Minute
	mustCreate(t, q, "a", 1)
	mustLease(t, q, "a", "w", 1_000)
	if _, err := q.Ack(ctx(t), 1, "w"); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Minute)
	mustCreate(t, q, "b", 1)
	if _, err := q.Rename(ctx(t), "a", "c"); err != nil {
		t.Fatal(err)
	}
	closeQueue(q, s)
	logPath, archPath := filepath.Join(dir, logName), filepath.Join(dir, archiveName)
	oldLog, oldArch := readFile(t, logPath), readFile(t, archPath)
	want := map[uint64]string{1: "c", 2: "b"}
	opens := func(when string) {
		t.Helper()
		q, s, err := openQueue(dir, clock)
		if err != nil {
			t.Fatalf("%s: %v", when, err)
		}
		defer closeQueue(q, s)
		if got := queueOf(q); !reflect.DeepEqual(got, want) {
			t.Errorf("%s: %v", when, got)
		}
		for _, name := range []string{logName, archiveName} {
			if _, err := os.Stat(tempPath(dir, name)); err == nil {
				t.Errorf("%s: %s.compact left behind", when, name)
			}
		}
	}
	// Killed before the log's rename: both temporaries, one torn.
	if err := os.WriteFile(tempPath(dir, logName), []byte("torn"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tempPath(dir, archiveName), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	opens("before the log's rename")
	if readFile(t, logPath) != oldLog || readFile(t, archPath) != oldArch {
		t.Error("the old pair changed")
	}
	// Killed between the two renames: the new log in place, the new
	// archive still a temporary.
	if err := Compact(dir); err != nil {
		t.Fatal(err)
	}
	newArch := readFile(t, archPath)
	if err := os.WriteFile(archPath, []byte(oldArch), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(tempPath(dir, archiveName), []byte(newArch), 0o644); err != nil {
		t.Fatal(err)
	}
	opens("between the renames")
	if readFile(t, archPath) != newArch {
		t.Errorf("the archive's rename was not finished:\n%s", readFile(t, archPath))
	}
}

// The rename's write fails: 503, nothing moved; the chaos switch fails it
// after the disk has it: the board restarts with the rename in place.
func TestRenameWriteFailing(t *testing.T) {
	q, _, f, _ := newMemQueue()
	mustCreate(t, q, "a", 1)
	pre := snapshot(q)
	f.fail = func(op string) bool { return op == "sync" }
	if _, err := q.Rename(ctx(t), "a", "b"); !errors.Is(err, ErrStore) {
		t.Fatalf("rename with a failing sync = %v", err)
	}
	f.fail = nil
	if !reflect.DeepEqual(snapshot(q), pre) || len(f.data) != int(q.store.(*Store).size) {
		t.Errorf("a failed rename changed something: %v", snapshot(q))
	}
	if _, ok, _ := q.Lease(ctx(t), "a", "w", 1_000); !ok {
		t.Error("the job left a after a failed rename")
	}

	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, CrashEvery: 3})
	h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k","payload":"p","max_tries":2}`, 201)
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":5000}`, 200)
	h.want(w1, "POST", "/queues/a/rename", `{"to":"b"}`, 503)
	h.q() // wait out the restart
	boardMatchesLog(t, h)
	if got := decodeJob(t, h.want(w1, "GET", "/jobs/j_1", "", 200)); got.Queue != "b" || *got.Worker != "w1" {
		t.Errorf("after the failed rename's restart: %+v", got)
	}
	h.want(w1, "GET", "/jobs?queue=b&key=k", "", 200)
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
}

func TestRenameThroughTheAPI(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","key":"k","payload":"p","max_tries":2}`, 201)
	h.want(w1, "POST", "/jobs", `{"queue":"b","payload":"p","max_tries":2}`, 201)
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":5000}`, 200)
	if got := h.want(w1, "POST", "/queues/a/rename", `{"to":"c"}`, 200); got != `{"queue":"c","moved":1}`+"\n" {
		t.Errorf("rename body = %q", got)
	}
	if got := h.want(w1, "GET", "/queues", "", 200); !strings.Contains(got, `"name":"c","queued":0,"scheduled":0,"leased":1`) ||
		strings.Contains(got, `"name":"a"`) {
		t.Errorf("queues = %s", got)
	}
	if got := h.want(w1, "GET", "/jobs?queue=c&key=k", "", 200); !strings.Contains(got, `"id":"j_1"`) {
		t.Errorf("key in c = %s", got)
	}
	h.want(w1, "GET", "/jobs?queue=a&key=k", "", 200)
	h.want(w1, "POST", "/queues/a/lease", "", 204)
	h.want(w1, "POST", "/queues/a/rename", `{"to":"d"}`, 404)
	if got := h.want(w1, "POST", "/queues/c/rename", `{"to":"b"}`, 409); !strings.Contains(got, "exists") {
		t.Errorf("409 body = %s", got)
	}
	h.want(w1, "POST", "/queues/c/rename", `{"to":"c"}`, 409)
	h.want(w1, "POST", "/queues/c/rename", `{"to":"bad name"}`, 400)
	h.want(w1, "POST", "/queues/c/rename", `{}`, 400)
	h.want(w1, "POST", "/queues/c/rename", ``, 400)
	h.want(w1, "POST", "/queues/bad%20name/rename", `{"to":"e"}`, 400)
	h.want("-", "POST", "/queues/c/rename", `{"to":"e"}`, 401)
	h.want(w1, "GET", "/queues/c/rename", "", 405)
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
	boardMatchesLog(t, h)
}

// A kill at every write of a run with renames, leases, acks, keyed creates,
// and handoffs: every point opens, every job is in one queue, every key
// names one job in its queue (checkApart), no record holds two workers, and
// every write answered before the point is in it.
func TestKillAtEveryWriteOfARenameRun(t *testing.T) {
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	type point struct {
		arch, log []byte
		acked     map[string]string // job id -> the state an answer reported
		created   map[string]bool
	}
	var points []point
	acked, created := map[string]string{}, map[string]bool{}
	f, a := &memFile{}, &memFile{}
	snap := func(string) bool {
		points = append(points, point{append([]byte{}, a.data...), append([]byte{}, f.data...), clone(acked), cloneSet(created)})
		return false
	}
	f.fail, a.fail = snap, snap
	b := newMemBoard(t, f, a, clock, BoardConfig{MaxRestarts: 5, Window: time.Minute, Retain: time.Second})
	h := &apiHarness{t: t, api: &API{b: b}, board: b, file: f, archive: a, clock: clock}
	where := map[string]string{"a": "a", "b": "b"} // logical queue -> its current name
	free := "c"
	for i := range 60 {
		lq := []string{"a", "b"}[i%2]
		_, body, _ := h.do(w1, "POST", "/jobs", fmt.Sprintf(`{"queue":%q,"key":"k%d","payload":"p","max_tries":2}`, where[lq], i%5))
		created[decodeJob(t, body).ID] = true
		if code, body, _ := h.do("Bearer w1", "POST", "/queues/"+where[lq]+"/lease", ""); code == 200 {
			v := decodeJob(t, body)
			to := "w2"
			if i%3 == 0 {
				h.want("Bearer w1", "POST", "/jobs/"+v.ID+"/handoff", `{"to":"w2"}`, 200)
			} else {
				to = "w1"
			}
			if i%4 != 0 {
				done := decodeJob(t, h.want("Bearer "+to, "POST", "/jobs/"+v.ID+"/ack", "", 200))
				acked[v.ID] = string(done.State)
			}
		}
		if i%7 == 3 {
			h.want(w1, "POST", "/queues/"+where[lq]+"/rename", fmt.Sprintf(`{"to":%q}`, free), 200)
			where[lq], free = free, where[lq]
		}
		clock.Advance(400 * time.Millisecond)
	}
	snap("")
	renames := 0
	for n, p := range points {
		if bytes.Contains(p.log, []byte(`"op":"rename"`)) {
			renames++
		}
		q := newQueue(clock)
		if _, err := replayAt(bytes.NewReader(p.arch), q.applyArchived); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		if _, err := replay(bytes.NewReader(p.log), q.applyRecord); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		if err := q.checkApart(); err != nil {
			t.Fatalf("point %d: %v", n, err)
		}
		for id, state := range p.acked {
			if j := q.lookup(mustID(id)); j == nil || string(j.State) != state {
				t.Fatalf("point %d: acknowledged %s %s is %+v", n, id, state, j)
			}
		}
		for id := range p.created {
			if q.lookup(mustID(id)) == nil {
				t.Fatalf("point %d: created %s lost", n, id)
			}
		}
		for _, j := range q.jobs {
			if (j.State == Leased) != (j.Worker != "") {
				t.Fatalf("point %d: %+v", n, j)
			}
		}
	}
	if renames == 0 {
		t.Fatal("no point held a rename")
	}
	// No record anywhere carries two workers, by the record's shape: one
	// worker field.
	for _, rec := range decodeAll(t, f.data) {
		if rec.Op == "rename" && (rec.Job != nil || rec.ID != "") {
			t.Fatalf("a rename record carries a job: %+v", rec)
		}
	}
	// The live board is the full replay.
	boardMatchesLog(t, h)
	final := queueOf(h.q())
	for id := range final {
		if n := final[id]; n != where["a"] && n != where["b"] {
			t.Errorf("j_%d is in %q, not a live name %v", id, n, where)
		}
	}
}

func cloneSet(m map[string]bool) map[string]bool {
	out := make(map[string]bool, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

func clone(m map[string]string) map[string]string {
	out := make(map[string]string, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// A job created into a freed name after the rename, and archived under it,
// is not moved by that rename at the next open: its id is past the rename's
// next_id.
func TestAJobCreatedAfterARenameIsNotMovedByIt(t *testing.T) {
	q, _, f, clock := newMemQueue()
	q.retain = time.Minute
	mustCreate(t, q, "a", 1)
	if _, err := q.Rename(ctx(t), "a", "b"); err != nil {
		t.Fatal(err)
	}
	fresh := mustCreate(t, q, "a", 1).ID
	mustLease(t, q, "a", "w", 1_000)
	if _, err := q.Ack(ctx(t), fresh, "w"); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Minute)
	mustCreate(t, q, "c", 1)
	if q.archived[fresh] == nil {
		t.Fatal("not archived")
	}
	r := replayBoth(t, q.archive.f.(*memFile).data, f.data)
	if got, want := queueOf(r), queueOf(q); !reflect.DeepEqual(got, want) || got[fresh] != "a" {
		t.Errorf("replayed %v, want %v", got, want)
	}
}
