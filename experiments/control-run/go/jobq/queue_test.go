package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"controlrun/contract"
)

func ctx(t *testing.T) context.Context { return t.Context() }

func wantKind(t *testing.T, err error, kind string) {
	t.Helper()
	var v *contract.Violation
	if !errors.As(err, &v) || v.Kind != kind {
		t.Errorf("err = %v, want a %s violation", err, kind)
	}
}

func mustCreate(t *testing.T, q *Queue, queue string, maxAttempts int) Job {
	t.Helper()
	j, err := q.Create(ctx(t), queue, "payload", maxAttempts)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

func mustLease(t *testing.T, q *Queue, queue, worker string, ms int64) Job {
	t.Helper()
	j, ok, err := q.Lease(ctx(t), queue, worker, ms)
	if err != nil || !ok {
		t.Fatalf("Lease(%s, %s) = %v, %v", queue, worker, ok, err)
	}
	return j
}

func TestCreateLeaseAck(t *testing.T) {
	q, _, _, clock := newMemQueue()
	j := mustCreate(t, q, "emails", 3)
	if j.ID != 1 || j.State != Queued || j.Attempts != 0 {
		t.Fatalf("created %+v", j)
	}
	l := mustLease(t, q, "emails", "w1", 30_000)
	if l.State != Leased || l.Worker != "w1" || l.Attempts != 1 || !l.LeaseUntil.Equal(clock.Now().Add(30*time.Second)) {
		t.Fatalf("leased %+v", l)
	}
	d, err := q.Ack(ctx(t), 1, "w1")
	if err != nil || d.State != Done || d.Worker != "" {
		t.Fatalf("acked %+v, %v", d, err)
	}
	h, err := q.Health(ctx(t))
	if err != nil || h != (Health{Done: 1}) {
		t.Errorf("health %+v, %v", h, err)
	}
}

func TestLeaseHandsOutOldestFirst(t *testing.T) {
	q, _, _, _ := newMemQueue()
	mustCreate(t, q, "a", 3)
	mustCreate(t, q, "b", 3)
	mustCreate(t, q, "a", 3)
	if j := mustLease(t, q, "a", "w", 1000); j.ID != 1 {
		t.Errorf("first lease on a got j_%d", j.ID)
	}
	mustCreate(t, q, "a", 3)
	if _, err := q.Fail(ctx(t), 1, "w", "retry"); err != nil {
		t.Fatal(err)
	}
	for _, want := range []uint64{1, 3, 4} {
		if j := mustLease(t, q, "a", "w", 1000); j.ID != want {
			t.Errorf("lease on a got j_%d, want j_%d", j.ID, want)
		}
	}
	if _, ok, err := q.Lease(ctx(t), "a", "w", 1000); ok || err != nil {
		t.Errorf("empty queue leased: %v, %v", ok, err)
	}
	if j := mustLease(t, q, "b", "w", 1000); j.ID != 2 {
		t.Errorf("lease on b got j_%d", j.ID)
	}
}

func TestFailRequeuesThenDead(t *testing.T) {
	q, _, _, _ := newMemQueue()
	mustCreate(t, q, "a", 2)
	mustLease(t, q, "a", "w", 1000)
	j, err := q.Fail(ctx(t), 1, "w", "boom")
	if err != nil || j.State != Queued || j.Attempts != 1 || j.Reason == nil || *j.Reason != "boom" {
		t.Fatalf("first fail %+v, %v", j, err)
	}
	mustLease(t, q, "a", "w", 1000)
	if j, err = q.Fail(ctx(t), 1, "w", "boom again"); err != nil || j.State != Dead || j.Attempts != 2 {
		t.Fatalf("second fail %+v, %v", j, err)
	}
	if _, ok, _ := q.Lease(ctx(t), "a", "w", 1000); ok {
		t.Error("a dead job was leased")
	}
}

func TestLeaseRunsOutAndIsLeasedAgain(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreate(t, q, "a", 3)
	mustLease(t, q, "a", "w1", 100)
	clock.Advance(100 * time.Millisecond)
	j := mustLease(t, q, "a", "w2", 100)
	if j.ID != 1 || j.Attempts != 2 || j.Worker != "w2" {
		t.Fatalf("re-leased %+v", j)
	}
	if _, err := q.Ack(ctx(t), 1, "w1"); !errors.Is(err, ErrConflict) {
		t.Errorf("ack by the worker whose lease ran out = %v, want 409", err)
	}
}

func TestLeaseRunsOutOnLastAttemptIsDead(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreate(t, q, "a", 1)
	mustLease(t, q, "a", "w1", 100)
	clock.Advance(150 * time.Millisecond)
	j, err := q.Get(ctx(t), 1)
	if err != nil || j.State != Dead || j.Reason == nil || *j.Reason != "lease ran out" {
		t.Fatalf("after the lease ran out: %+v, %v", j, err)
	}
	if _, ok, _ := q.Lease(ctx(t), "a", "w2", 100); ok {
		t.Error("a dead job was leased")
	}
}

// A run-out lease never blocks for longer than one look: one health read
// ends every lease that ran out.
func TestOneLookEndsEveryRunOutLease(t *testing.T) {
	q, _, _, clock := newMemQueue()
	for range 5 {
		mustCreate(t, q, "a", 3)
		mustLease(t, q, "a", "w", 100)
	}
	clock.Advance(time.Second)
	h, err := q.Health(ctx(t))
	if err != nil || h.Queued != 5 || h.Leased != 0 {
		t.Errorf("health %+v, %v", h, err)
	}
}

func TestDoneJobNeverLeasedAgain(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreate(t, q, "a", 3)
	mustLease(t, q, "a", "w", 100)
	if _, err := q.Ack(ctx(t), 1, "w"); err != nil {
		t.Fatal(err)
	}
	clock.Advance(time.Second)
	if _, ok, _ := q.Lease(ctx(t), "a", "w", 100); ok {
		t.Error("a done job was leased")
	}
}

// Two workers race for one job: exactly one holds it.
func TestWorkersRaceForOneJob(t *testing.T) {
	for round := range 20 {
		q, _, _, _ := newMemQueue()
		mustCreate(t, q, "a", 3)
		var wg sync.WaitGroup
		var mu sync.Mutex
		var winners []string
		for w := range 32 {
			wg.Add(1)
			go func() {
				defer wg.Done()
				worker := "w" + string(rune('A'+w))
				_, ok, err := q.Lease(context.Background(), "a", worker, 1000)
				if err != nil {
					t.Error(err)
				}
				if ok {
					mu.Lock()
					winners = append(winners, worker)
					mu.Unlock()
				}
			}()
		}
		wg.Wait()
		j, _ := q.Get(ctx(t), 1)
		if len(winners) != 1 || j.Worker != winners[0] || j.Attempts != 1 {
			t.Fatalf("round %d: winners %v, job %+v", round, winners, j)
		}
	}
}

func TestAckFailDeleteStatuses(t *testing.T) {
	q, _, _, _ := newMemQueue()
	mustCreate(t, q, "a", 3)
	if _, err := q.Ack(ctx(t), 1, "w"); !errors.Is(err, ErrConflict) {
		t.Errorf("ack of a queued job = %v", err)
	}
	mustLease(t, q, "a", "w", 1000)
	if _, err := q.Ack(ctx(t), 1, "other"); !errors.Is(err, ErrConflict) {
		t.Errorf("ack by another worker = %v", err)
	}
	if _, err := q.Fail(ctx(t), 1, "other", ""); !errors.Is(err, ErrConflict) {
		t.Errorf("fail by another worker = %v", err)
	}
	if err := q.Delete(ctx(t), 1); !errors.Is(err, ErrConflict) {
		t.Errorf("delete of a leased job = %v", err)
	}
	if _, err := q.Ack(ctx(t), 9, "w"); !errors.Is(err, ErrNotFound) {
		t.Errorf("ack of a missing job = %v", err)
	}
	if _, err := q.Ack(ctx(t), 1, "w"); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(ctx(t), 1); err != nil {
		t.Errorf("delete of a done job = %v", err)
	}
	if err := q.Delete(ctx(t), 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("second delete = %v", err)
	}
}

// A rejects test for every requires; nothing is created or leased.
func TestRequiresReject(t *testing.T) {
	q, _, _, _ := newMemQueue()
	long := strings.Repeat("x", 65)
	for _, c := range []struct {
		queue, payload string
		max            int
	}{
		{"", "p", 1}, {long, "p", 1}, {"a b", "p", 1}, {"é", "p", 1},
		{"a", strings.Repeat("x", maxPayloadBytes+1), 1}, {"a", "\x01", 1}, {"a", "tab\t", 1},
		{"a", "\xff", 1}, {"a", "\u0085", 1},
		{"a", "p", 0}, {"a", "p", 101},
	} {
		_, err := q.Create(ctx(t), c.queue, c.payload, c.max)
		wantKind(t, err, "requires")
	}
	for _, c := range []struct {
		queue, payload string
		max            int
	}{
		{strings.Repeat("q", 64), strings.Repeat("x", maxPayloadBytes), 1}, {"a-B_9", "line\nline é 日", 100}, {"a", "", 1},
	} {
		if _, err := q.Create(ctx(t), c.queue, c.payload, c.max); err != nil {
			t.Errorf("Create(%q, %d bytes, %d) = %v", c.queue, len(c.payload), c.max, err)
		}
	}
	created := len(q.jobs)
	for _, ms := range []int64{99, 3_600_001, -1} {
		_, _, err := q.Lease(ctx(t), "a", "w", ms)
		wantKind(t, err, "requires")
	}
	for _, worker := range []string{"", "a b", strings.Repeat("w", 257)} {
		_, _, err := q.Lease(ctx(t), "a", worker, 1000)
		wantKind(t, err, "requires")
	}
	_, _, err := q.Lease(ctx(t), "bad queue", "w", 1000)
	wantKind(t, err, "requires")
	if h, _ := q.Health(ctx(t)); h.Leased != 0 || len(q.jobs) != created {
		t.Errorf("a rejected call changed the queue: %+v", h)
	}
	mustCreate(t, q, "a", 3)
	mustCreate(t, q, "a", 3)
	for _, ms := range []int64{100, 3_600_000} {
		if _, _, err := q.Lease(ctx(t), "a", "w", ms); err != nil {
			t.Errorf("Lease with %d ms = %v", ms, err)
		}
	}
	held := mustLease(t, q, "a", "w", 1000)
	_, err = q.Fail(ctx(t), held.ID, "w", strings.Repeat("r", maxReasonBytes+1))
	wantKind(t, err, "requires")
	_, err = q.List(ctx(t), "", "bogus")
	wantKind(t, err, "requires")
	_, err = q.List(ctx(t), "bad!", "")
	wantKind(t, err, "requires")
}

func TestEnsures(t *testing.T) {
	before := Job{State: Queued, Attempts: 1}
	good := Job{State: Leased, Worker: "w", Attempts: 2}
	if err := ensureLeased(before, good, "w"); err != nil {
		t.Errorf("ensureLeased(good) = %v", err)
	}
	for _, after := range []Job{
		{State: Queued, Worker: "w", Attempts: 2},
		{State: Leased, Worker: "x", Attempts: 2},
		{State: Leased, Worker: "w", Attempts: 1},
	} {
		wantKind(t, ensureLeased(before, after, "w"), "ensures")
	}
	if err := ensureDone(Job{State: Done}); err != nil {
		t.Errorf("ensureDone(done) = %v", err)
	}
	wantKind(t, ensureDone(Job{State: Leased}), "ensures")
}

// Tries to break each never directly; the check must refuse every one.
func TestNeversRefuseBrokenChanges(t *testing.T) {
	now := time.Date(2026, 9, 14, 0, 0, 10, 0, time.UTC)
	live := &Job{State: Leased, Worker: "w1", Attempts: 1, MaxAttempts: 3, LeaseUntil: now.Add(time.Second)}
	runOut := &Job{State: Leased, Worker: "w1", Attempts: 1, MaxAttempts: 3, LeaseUntil: now}
	done := &Job{State: Done, Attempts: 1, MaxAttempts: 3}
	dead := &Job{State: Dead, Attempts: 3, MaxAttempts: 3}
	leasedBy := func(w string, attempts int) *Job {
		return &Job{State: Leased, Worker: w, Attempts: attempts, MaxAttempts: 3, LeaseUntil: now.Add(time.Minute)}
	}
	for name, c := range map[string]change{
		"held by two workers": {old: live, new: leasedBy("w2", 2)},
		"done leased again":   {old: done, new: leasedBy("w2", 2)},
		"dead leased":         {old: dead, new: leasedBy("w2", 3)},
		"dead back to queued": {old: dead, new: &Job{State: Queued, Attempts: 2, MaxAttempts: 3}},
		"attempts over max":   {old: runOut, new: leasedBy("w2", 4)},
		"created over max":    {new: &Job{State: Queued, Attempts: 4, MaxAttempts: 3}},
	} {
		if err := checkNevers(c, now); err == nil {
			t.Errorf("%s: allowed", name)
		} else {
			wantKind(t, err, "never")
		}
	}
	if err := checkNevers(change{old: runOut, new: leasedBy("w2", 2)}, now); err != nil {
		t.Errorf("leasing a run-out lease: %v", err)
	}
}

// A response is never sent before its record is durable: when the store
// cannot sync, the call fails and the queue is as it was.
func TestNothingChangesWhenTheStoreFails(t *testing.T) {
	q, _, f, clock := newMemQueue()
	mustCreate(t, q, "a", 3)
	mustLease(t, q, "a", "w", 100)
	mustCreate(t, q, "a", 3)
	before := snapshot(q)
	clock.Advance(time.Second)
	f.fail = func(op string) bool { return op == "sync" }
	if _, err := q.Create(ctx(t), "a", "p", 1); !errors.Is(err, ErrStore) {
		t.Errorf("Create = %v", err)
	}
	if _, _, err := q.Lease(ctx(t), "a", "w2", 100); !errors.Is(err, ErrStore) {
		t.Errorf("Lease = %v", err)
	}
	if _, err := q.Get(ctx(t), 1); !errors.Is(err, ErrStore) {
		t.Errorf("Get, which must write the run-out lease = %v", err)
	}
	if got := snapshot(q); len(got) != len(before) || got["j_1"].State != Leased {
		t.Errorf("queue changed: %v", got)
	}
	f.fail = nil
	if j := mustLease(t, q, "a", "w2", 100); j.ID != 1 || j.Attempts != 2 {
		t.Errorf("after the store recovered: %+v", j)
	}
}

func TestBusyQueueTimesOut(t *testing.T) {
	q, _, _, _ := newMemQueue()
	if err := q.acquire(context.Background()); err != nil {
		t.Fatal(err)
	}
	c, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := q.Get(c, 1); !errors.Is(err, ErrBusy) {
		t.Errorf("Get on a held queue = %v, want ErrBusy", err)
	}
}

// Each invariant is tripped by a store record the queue accepts on replay.
func TestInvariantsTripThroughStoreRecords(t *testing.T) {
	const at = "2026-09-14T00:00:00.000Z"
	for want, job := range map[string]string{
		"exactly when it is leased": `{"id":"j_1","queue":"a","state":"leased","payload":"","attempts":1,"max_attempts":3,"created_at":"` + at + `","updated_at":"` + at + `","lease_until":"` + at + `"}`,
		"below max_attempts":        `{"id":"j_1","queue":"a","state":"queued","payload":"","attempts":3,"max_attempts":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"are valid":                 `{"id":"j_1","queue":"a b","state":"queued","payload":"","attempts":0,"max_attempts":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"created_at <= updated_at":  `{"id":"j_1","queue":"a","state":"done","payload":"","attempts":1,"max_attempts":3,"created_at":"2026-09-15T00:00:00.000Z","updated_at":"` + at + `"}`,
	} {
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, logName), []byte(lineFor(`{"op":"put","job":`+job+`}`)), 0o644); err != nil {
			t.Fatal(err)
		}
		_, _, err := openQueue(dir, realClock{})
		if err == nil || !strings.Contains(err.Error(), "invariant failed") || !strings.Contains(err.Error(), want) {
			t.Errorf("replay err = %v, want invariant %q", err, want)
		}
	}
}

// Create, lease, stop, start again: the lease has run out at the next look.
func TestReplayFindsLeaseRunOut(t *testing.T) {
	dir := t.TempDir()
	clock := newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC))
	q, s, err := openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	mustCreate(t, q, "a", 3)
	mustLease(t, q, "a", "w1", 1000)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	clock.Advance(2 * time.Second)
	q, s, err = openQueue(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if j, _ := q.Get(ctx(t), 1); j.State != Queued || j.Attempts != 1 {
		t.Errorf("after restart %+v, want queued with attempts 1", j)
	}
	if j := mustLease(t, q, "a", "w2", 1000); j.Attempts != 2 {
		t.Errorf("re-leased with attempts %d, want 2", j.Attempts)
	}
}
