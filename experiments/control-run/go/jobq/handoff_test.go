package main

import (
	"bytes"
	"errors"
	"os"
	"testing"
	"time"
)

// Change 5: a lease handed to another worker. requires: the caller holds a
// live lease. ensures: the job is leased to the new worker with the same
// lease_until and tries.

func TestHandoffFromTheHolder(t *testing.T) {
	q, _, f, clock := newMemQueue()
	mustCreate(t, q, "a", 3)
	held := mustLease(t, q, "a", "w1", 10_000)
	clock.Advance(time.Second)
	got, err := q.Handoff(ctx(t), held.ID, "w1", "w2")
	if err != nil {
		t.Fatal(err)
	}
	if got.State != Leased || got.Worker != "w2" || got.Tries != held.Tries || !got.LeaseUntil.Equal(held.LeaseUntil) ||
		!got.UpdatedAt.Equal(clock.Now()) {
		t.Fatalf("handed off %+v, was %+v", got, held)
	}
	// The old worker is a stranger now; the new one is the holder.
	if _, err := q.Ack(ctx(t), held.ID, "w1"); !errors.Is(err, ErrConflict) {
		t.Errorf("old worker's ack = %v, want 409", err)
	}
	if _, err := q.Fail(ctx(t), held.ID, "w1", "x"); !errors.Is(err, ErrConflict) {
		t.Errorf("old worker's fail = %v, want 409", err)
	}
	if _, err := q.Handoff(ctx(t), held.ID, "w1", "w3"); !errors.Is(err, ErrConflict) {
		t.Errorf("old worker's handoff = %v, want 409", err)
	}
	if h, _ := q.Health(ctx(t)); h.Leased != 1 {
		t.Errorf("health after a handoff = %+v", h)
	}
	if d, err := q.Ack(ctx(t), held.ID, "w2"); err != nil || d.State != Done {
		t.Fatalf("new worker's ack = %+v, %v", d, err)
	}
	replayed := replayBytes(t, f.data)
	if j := replayed.jobs[held.ID]; j == nil || j.State != Done {
		t.Errorf("replayed %+v", j)
	}
}

func TestHandoffStatuses(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreate(t, q, "a", 3)
	held := mustLease(t, q, "a", "w1", 1_000)
	for name, c := range map[string]struct {
		worker, to string
		want       error
	}{
		"from a stranger":   {"w9", "w2", ErrConflict},
		"of an unknown job": {"w1", "w2", ErrNotFound},
	} {
		id := held.ID
		if c.want == ErrNotFound {
			id = 99
		}
		if _, err := q.Handoff(ctx(t), id, c.worker, c.to); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
	for _, to := range []string{"", "a b", "tab\t", string(make([]byte, 257))} {
		_, err := q.Handoff(ctx(t), held.ID, "w1", to)
		wantKind(t, err, "requires")
	}
	// To the holder itself: 200, and nothing changes.
	same, err := q.Handoff(ctx(t), held.ID, "w1", "w1")
	if err != nil || same != *q.jobs[held.ID] || same.UpdatedAt != held.UpdatedAt {
		t.Errorf("handoff to itself = %+v, %v; was %+v", same, err, held)
	}
	// After the lease ran out the caller holds nothing.
	clock.Advance(time.Second)
	if _, err := q.Handoff(ctx(t), held.ID, "w1", "w2"); !errors.Is(err, ErrConflict) {
		t.Errorf("handoff after the lease ran out = %v, want 409", err)
	}
	if j := q.jobs[held.ID]; j.State != Queued || j.Worker != "" {
		t.Errorf("the run-out lease: %+v", j)
	}
}

func TestHandoffTwiceInARow(t *testing.T) {
	q, _, _, _ := newMemQueue()
	mustCreate(t, q, "a", 3)
	held := mustLease(t, q, "a", "A", 10_000)
	for _, step := range [][2]string{{"A", "B"}, {"B", "C"}} {
		if _, err := q.Handoff(ctx(t), held.ID, step[0], step[1]); err != nil {
			t.Fatalf("%s to %s: %v", step[0], step[1], err)
		}
	}
	for _, w := range []string{"A", "B"} {
		if _, err := q.Ack(ctx(t), held.ID, w); !errors.Is(err, ErrConflict) {
			t.Errorf("%s's ack = %v, want 409", w, err)
		}
	}
	if d, err := q.Ack(ctx(t), held.ID, "C"); err != nil || d.State != Done || d.Tries != held.Tries {
		t.Errorf("C's ack = %+v, %v", d, err)
	}
}

// The handoff is a write: across a stop and start the job is leased to the
// new worker, with the same lease_until, and the lease still runs out then.
func TestHandoffAcrossARestart(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	mustCreate(t, q, "a", 2)
	held := mustLease(t, q, "a", "w1", 5_000)
	if _, err := q.Handoff(ctx(t), held.ID, "w1", "w2"); err != nil {
		t.Fatal(err)
	}
	q, s = reopen(t, dir, q, s, clock)
	j := q.jobs[held.ID]
	if j.State != Leased || j.Worker != "w2" || !j.LeaseUntil.Equal(held.LeaseUntil) || j.Tries != held.Tries {
		t.Fatalf("after the restart %+v", j)
	}
	if _, err := q.Ack(ctx(t), held.ID, "w1"); !errors.Is(err, ErrConflict) {
		t.Errorf("old worker's ack after the restart = %v", err)
	}
	clock.Advance(5 * time.Second)
	if got, _ := q.Get(ctx(t), held.ID); got.State != Queued || got.Reason == nil {
		t.Errorf("the handed-off lease did not run out on time: %+v", got)
	}
	closeQueue(q, s)
	if code, out, errOut := runCmd("verify", dir); code != 0 {
		t.Errorf("verify = %d %s %s", code, out, errOut)
	}
}

func TestHandoffThroughTheAPIAndTheBoard(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, CrashEvery: 3})
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	held := decodeJob(t, h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":5000}`, 200))
	// The third write is the handoff; it is on disk and answered 503.
	h.want(w1, "POST", "/jobs/j_1/handoff", `{"to":"w2"}`, 503)
	h.q() // wait out the restart
	after := decodeJob(t, h.want("Bearer w2", "GET", "/jobs/j_1", "", 200))
	if *after.Worker != "w2" || *after.LeaseUntil != *held.LeaseUntil || after.Tries != held.Tries {
		t.Fatalf("after the failed handoff's restart: %+v", after)
	}
	boardMatchesLog(t, h)
	h.want(w1, "POST", "/jobs/j_1/handoff", `{"to":"w3"}`, 409)
	h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{"to":"w2"}`, 200)
	h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{}`, 400)
	h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{"to":""}`, 400)
	h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{"to":"x y"}`, 400)
	h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{"to":"x","other":1}`, 400)
	h.want("Bearer w2", "POST", "/jobs/j_9/handoff", `{"to":"x"}`, 404)
	h.want("Bearer w2", "POST", "/jobs/bad/handoff", `{"to":"x"}`, 404)
	h.want("-", "POST", "/jobs/j_1/handoff", `{"to":"x"}`, 401)
	if code, _, hdr := h.do("Bearer w2", "GET", "/jobs/j_1/handoff", ""); code != 405 || hdr.Get("Allow") != "POST" {
		t.Errorf("GET handoff = %d, Allow %q", code, hdr.Get("Allow"))
	}
	got := decodeJob(t, h.want("Bearer w2", "POST", "/jobs/j_1/handoff", `{"to":"w3"}`, 200))
	if *got.Worker != "w3" {
		t.Errorf("handoff body %+v", got)
	}
	h.want("Bearer w3", "POST", "/jobs/j_1/fail", `{"reason":"r"}`, 200)
	boardMatchesLog(t, h)
}

// The never: a leased job taken by another worker is refused unless it is a
// handoff, and a handoff that changes lease_until or tries is not one.
func TestHandoffNevers(t *testing.T) {
	now := time.Date(2026, 9, 14, 0, 0, 10, 0, time.UTC)
	live := &Job{Queue: "a", State: Leased, Worker: "w1", Tries: 1, MaxTries: 3, LeaseUntil: now.Add(time.Second)}
	moved := func(edit func(*Job)) *Job {
		n := handoffStep(*live, "w2", now)
		edit(&n)
		return &n
	}
	if err := checkNevers(change{old: live, new: moved(func(*Job) {})}, now); err != nil {
		t.Errorf("a handoff: %v", err)
	}
	for name, n := range map[string]*Job{
		"a longer lease":        moved(func(j *Job) { j.LeaseUntil = j.LeaseUntil.Add(time.Second) }),
		"a try more":            moved(func(j *Job) { j.Tries++ }),
		"a try less":            moved(func(j *Job) { j.Tries-- }),
		"another queue":         moved(func(j *Job) { j.Queue = "b" }),
		"a second worker lease": {Queue: "a", State: Leased, Worker: "w2", Tries: 2, MaxTries: 3, LeaseUntil: now.Add(time.Minute)},
	} {
		t.Run(name, func(t *testing.T) { wantKind(t, checkNevers(change{old: live, new: n}, now), "never") })
	}
	if err := ensureHandedOff(*live, *moved(func(*Job) {}), "w2"); err != nil {
		t.Errorf("ensure on a handoff: %v", err)
	}
	wantKind(t, ensureHandedOff(*live, *moved(func(j *Job) { j.Tries++ }), "w2"), "ensures")
	wantKind(t, ensureHandedOff(*live, *live, "w2"), "ensures")
}

// A record in the log never carries two workers: the handoff is one put
// with the new worker.
func TestHandoffRecordHasOneWorker(t *testing.T) {
	q, _, f, _ := newMemQueue()
	mustCreate(t, q, "a", 1)
	mustLease(t, q, "a", "w1", 1_000)
	before := len(f.data)
	if _, err := q.Handoff(ctx(t), 1, "w1", "w2"); err != nil {
		t.Fatal(err)
	}
	recs := decodeAll(t, f.data[before:])
	if len(recs) != 1 || recs[0].Op != "put" || *recs[0].Job.Worker != "w2" {
		t.Fatalf("handoff wrote %+v", recs)
	}
}

func decodeAll(t *testing.T, data []byte) []record {
	t.Helper()
	var out []record
	if _, err := replay(bytes.NewReader(data), func(r record) error { out = append(out, r); return nil }); err != nil {
		t.Fatal(err)
	}
	return out
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
