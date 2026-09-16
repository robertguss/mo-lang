package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
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

func mustCreate(t *testing.T, q *Queue, queue string, maxTries int) Job {
	t.Helper()
	j, err := q.Create(ctx(t), queue, "payload", maxTries, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

func mustCreateWith(t *testing.T, q *Queue, queue string, maxTries int, delayMS, backoffMS int64) Job {
	t.Helper()
	j, err := q.Create(ctx(t), queue, "payload", maxTries, delayMS, backoffMS)
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
	if j.ID != 1 || j.State != Queued || j.Tries != 0 {
		t.Fatalf("created %+v", j)
	}
	l := mustLease(t, q, "emails", "w1", 30_000)
	if l.State != Leased || l.Worker != "w1" || l.Tries != 1 || !l.LeaseUntil.Equal(clock.Now().Add(30*time.Second)) {
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
	if err != nil || j.State != Queued || j.Tries != 1 || j.Reason == nil || *j.Reason != "boom" {
		t.Fatalf("first fail %+v, %v", j, err)
	}
	mustLease(t, q, "a", "w", 1000)
	if j, err = q.Fail(ctx(t), 1, "w", "boom again"); err != nil || j.State != Dead || j.Tries != 2 {
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
	if j.ID != 1 || j.Tries != 2 || j.Worker != "w2" {
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

// A job created with delay_ms waits until its run_at.
func TestCreateWithDelayIsScheduledUntilRunAt(t *testing.T) {
	q, _, _, clock := newMemQueue()
	j := mustCreateWith(t, q, "a", 3, 5000, 0)
	if j.State != Scheduled || !j.RunAt.Equal(clock.Now().Add(5*time.Second)) || j.Tries != 0 {
		t.Fatalf("created %+v", j)
	}
	clock.Advance(4999 * time.Millisecond)
	if _, ok, err := q.Lease(ctx(t), "a", "w", 1000); ok || err != nil {
		t.Fatalf("leased before run_at: %v, %v", ok, err)
	}
	if got, _ := q.Get(ctx(t), 1); got.State != Scheduled {
		t.Errorf("before run_at %+v", got)
	}
	clock.Advance(time.Millisecond)
	l := mustLease(t, q, "a", "w", 1000)
	if l.Tries != 1 || !l.RunAt.IsZero() {
		t.Fatalf("leased at run_at %+v", l)
	}
	if h, _ := q.Health(ctx(t)); h.Scheduled != 0 || h.Leased != 1 {
		t.Errorf("health %+v", h)
	}
}

// A fail with a backoff schedules the job; the last try is dead instead.
func TestFailWithBackoffSchedulesThenDies(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreateWith(t, q, "a", 2, 0, 2000)
	mustLease(t, q, "a", "w", 1000)
	j, err := q.Fail(ctx(t), 1, "w", "flaky")
	if err != nil || j.State != Scheduled || !j.RunAt.Equal(clock.Now().Add(2*time.Second)) || j.Tries != 1 {
		t.Fatalf("failed with backoff %+v, %v", j, err)
	}
	if h, _ := q.Health(ctx(t)); h.Scheduled != 1 || h.Queued != 0 {
		t.Errorf("health %+v", h)
	}
	if _, ok, _ := q.Lease(ctx(t), "a", "w", 1000); ok {
		t.Error("a scheduled job was leased before its run_at")
	}
	clock.Advance(2 * time.Second)
	if l := mustLease(t, q, "a", "w", 1000); l.Tries != 2 {
		t.Fatalf("leased after the backoff %+v", l)
	}
	if j, err = q.Fail(ctx(t), 1, "w", "again"); err != nil || j.State != Dead || !j.RunAt.IsZero() {
		t.Fatalf("fail on the last try %+v, %v", j, err)
	}
}

// A lease that runs out follows the same rule as a fail.
func TestRunOutLeaseWithBackoffIsScheduled(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreateWith(t, q, "a", 3, 0, 1000) // with a backoff
	mustCreateWith(t, q, "b", 3, 0, 0)    // without one
	mustLease(t, q, "a", "w", 100)
	mustLease(t, q, "b", "w", 100)
	clock.Advance(150 * time.Millisecond)
	withBackoff, err := q.Get(ctx(t), 1)
	if err != nil || withBackoff.State != Scheduled || !withBackoff.RunAt.Equal(clock.Now().Add(time.Second)) {
		t.Fatalf("with a backoff %+v, %v", withBackoff, err)
	}
	if *withBackoff.Reason != "lease ran out" || withBackoff.Tries != 1 {
		t.Errorf("with a backoff %+v", withBackoff)
	}
	if without, _ := q.Get(ctx(t), 2); without.State != Queued || !without.RunAt.IsZero() {
		t.Errorf("without a backoff %+v", without)
	}
}

// A dead job is queued again by a retry, with its tries at 0.
func TestRetryOfADeadJob(t *testing.T) {
	q, _, _, _ := newMemQueue()
	mustCreateWith(t, q, "a", 1, 0, 1000)
	mustLease(t, q, "a", "w", 1000)
	if j, err := q.Fail(ctx(t), 1, "w", "boom"); err != nil || j.State != Dead {
		t.Fatalf("fail %+v, %v", j, err)
	}
	j, err := q.Retry(ctx(t), 1)
	if err != nil || j.State != Queued || j.Tries != 0 || j.Reason != nil || j.Worker != "" || !j.RunAt.IsZero() {
		t.Fatalf("retried %+v, %v", j, err)
	}
	if j.MaxTries != 1 || j.BackoffMS != 1000 || j.Payload != "payload" || j.Queue != "a" {
		t.Errorf("a retry changed what it must keep: %+v", j)
	}
	if l := mustLease(t, q, "a", "w2", 1000); l.Tries != 1 {
		t.Fatalf("leased after the retry %+v", l)
	}
}

// A retry never touches a job that is not dead.
func TestRetryOfALiveJobIs409(t *testing.T) {
	q, _, _, clock := newMemQueue()
	mustCreateWith(t, q, "a", 3, 0, 0)    // queued
	mustCreateWith(t, q, "a", 3, 5000, 0) // scheduled
	mustCreateWith(t, q, "b", 3, 0, 0)    // leased, then done
	mustLease(t, q, "b", "w", 60_000)
	mustCreateWith(t, q, "c", 3, 0, 0) // leased
	mustLease(t, q, "c", "w", 60_000)
	if _, err := q.Ack(ctx(t), 3, "w"); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uint64{1, 2, 3, 4} {
		before, _ := q.Get(ctx(t), id)
		if _, err := q.Retry(ctx(t), id); !errors.Is(err, ErrConflict) {
			t.Errorf("retry of j_%d (%s) = %v, want 409", id, before.State, err)
		}
		if after, _ := q.Get(ctx(t), id); after.State != before.State || after.Tries != before.Tries {
			t.Errorf("a refused retry changed j_%d: %+v", id, after)
		}
	}
	if _, err := q.Retry(ctx(t), 9); !errors.Is(err, ErrNotFound) {
		t.Errorf("retry of a missing job = %v", err)
	}
	clock.Advance(time.Hour)
	if _, err := q.Retry(ctx(t), 2); !errors.Is(err, ErrConflict) {
		t.Errorf("retry of a job that is queued again = %v", err)
	}
}

// One look queues every scheduled job whose run_at has passed.
func TestOneLookQueuesEveryDueJob(t *testing.T) {
	q, _, _, clock := newMemQueue()
	for range 5 {
		mustCreateWith(t, q, "a", 3, 100, 0)
	}
	mustCreateWith(t, q, "a", 3, 60_000, 0)
	clock.Advance(time.Second)
	h, err := q.Health(ctx(t))
	if err != nil || h.Queued != 5 || h.Scheduled != 1 {
		t.Errorf("health %+v, %v", h, err)
	}
}

// The scheduled-to-queued move is durable before it is answered: when the
// store cannot sync, the job is still scheduled.
func TestScheduledMoveIsUndoneWhenTheStoreFails(t *testing.T) {
	q, _, f, clock := newMemQueue()
	mustCreateWith(t, q, "a", 3, 1000, 0)
	before := snapshot(q)
	clock.Advance(2 * time.Second)
	f.fail = func(op string) bool { return op == "sync" }
	if j, err := q.Get(ctx(t), 1); err != nil || j.State != Scheduled {
		t.Errorf("Get, whose move cannot be written = %+v, %v; want the job still scheduled", j, err)
	}
	if got := snapshot(q); !reflect.DeepEqual(got, before) {
		t.Errorf("the queue changed: %v", got)
	}
	f.fail = nil
	if j, err := q.Get(ctx(t), 1); err != nil || j.State != Queued {
		t.Errorf("after the store recovered %+v, %v", j, err)
	}
	if j := mustLease(t, q, "a", "w", 1000); j.Tries != 1 {
		t.Errorf("leased %+v", j)
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
		if len(winners) != 1 || j.Worker != winners[0] || j.Tries != 1 {
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
		_, err := q.Create(ctx(t), c.queue, c.payload, c.max, 0, 0)
		wantKind(t, err, "requires")
	}
	for _, c := range []struct {
		queue, payload string
		max            int
	}{
		{strings.Repeat("q", 64), strings.Repeat("x", maxPayloadBytes), 1}, {"a-B_9", "line\nline é 日", 100}, {"a", "", 1},
	} {
		if _, err := q.Create(ctx(t), c.queue, c.payload, c.max, 0, 0); err != nil {
			t.Errorf("Create(%q, %d bytes, %d) = %v", c.queue, len(c.payload), c.max, err)
		}
	}
	for _, c := range []struct{ delay, backoff int64 }{
		{-1, 0}, {maxDelayMS + 1, 0}, {0, -1}, {0, maxBackoffMS + 1},
	} {
		_, err := q.Create(ctx(t), "a", "p", 1, c.delay, c.backoff)
		wantKind(t, err, "requires")
	}
	for _, c := range []struct{ delay, backoff int64 }{{0, 0}, {maxDelayMS, maxBackoffMS}, {1, 1}} {
		if _, err := q.Create(ctx(t), "a", "p", 1, c.delay, c.backoff); err != nil {
			t.Errorf("Create(delay %d, backoff %d) = %v", c.delay, c.backoff, err)
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
	before := Job{State: Queued, Tries: 1}
	good := Job{State: Leased, Worker: "w", Tries: 2}
	if err := ensureLeased(before, good, "w"); err != nil {
		t.Errorf("ensureLeased(good) = %v", err)
	}
	for _, after := range []Job{
		{State: Queued, Worker: "w", Tries: 2},
		{State: Leased, Worker: "x", Tries: 2},
		{State: Leased, Worker: "w", Tries: 1},
	} {
		wantKind(t, ensureLeased(before, after, "w"), "ensures")
	}
	if err := ensureDone(Job{State: Done}); err != nil {
		t.Errorf("ensureDone(done) = %v", err)
	}
	wantKind(t, ensureDone(Job{State: Leased}), "ensures")
	if err := ensureRetried(Job{State: Queued, Tries: 0}); err != nil {
		t.Errorf("ensureRetried(queued with 0 tries) = %v", err)
	}
	for _, after := range []Job{{State: Queued, Tries: 1}, {State: Dead}, {State: Scheduled}} {
		wantKind(t, ensureRetried(after), "ensures")
	}
}

// Tries to break each never directly; the check must refuse every one.
func TestNeversRefuseBrokenChanges(t *testing.T) {
	now := time.Date(2026, 9, 14, 0, 0, 10, 0, time.UTC)
	live := &Job{State: Leased, Worker: "w1", Tries: 1, MaxTries: 3, LeaseUntil: now.Add(time.Second)}
	runOut := &Job{State: Leased, Worker: "w1", Tries: 1, MaxTries: 3, LeaseUntil: now}
	done := &Job{State: Done, Tries: 1, MaxTries: 3}
	dead := &Job{State: Dead, Tries: 3, MaxTries: 3}
	leasedBy := func(w string, tries int) *Job {
		return &Job{State: Leased, Worker: w, Tries: tries, MaxTries: 3, LeaseUntil: now.Add(time.Minute)}
	}
	for name, c := range map[string]change{
		"held by two workers":                  {old: live, new: leasedBy("w2", 2)},
		"done leased again":                    {old: done, new: leasedBy("w2", 2)},
		"dead leased":                          {old: dead, new: leasedBy("w2", 3)},
		"dead back to queued":                  {old: dead, new: &Job{State: Queued, Tries: 2, MaxTries: 3}},
		"tries over max":                       {old: runOut, new: leasedBy("w2", 4)},
		"created over max":                     {new: &Job{State: Queued, Tries: 4, MaxTries: 3}},
		"dead leased before a retry queues it": {old: dead, new: leasedBy("w2", 1)},
		"retry of a job that is not dead":      {old: &Job{State: Queued, Tries: 2, MaxTries: 3}, new: &Job{State: Queued, Tries: 0, MaxTries: 3}},
		"retry of a done job":                  {old: done, new: &Job{State: Queued, Tries: 0, MaxTries: 3}},
		"scheduled leased before run_at": {
			old: &Job{State: Scheduled, Tries: 1, MaxTries: 3, RunAt: now.Add(time.Minute)},
			new: leasedBy("w2", 2),
		},
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
	retried := change{old: dead, new: &Job{State: Queued, Tries: 0, MaxTries: 3}}
	if err := checkNevers(retried, now); err != nil {
		t.Errorf("retrying a dead job: %v", err)
	}
	due := change{
		old: &Job{State: Scheduled, Tries: 1, MaxTries: 3, RunAt: now},
		new: leasedBy("w2", 2),
	}
	if err := checkNevers(due, now); err != nil {
		t.Errorf("leasing a job whose run_at has come: %v", err)
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
	if _, err := q.Create(ctx(t), "a", "p", 1, 0, 0); !errors.Is(err, ErrStore) {
		t.Errorf("Create = %v", err)
	}
	if _, _, err := q.Lease(ctx(t), "a", "w2", 100); !errors.Is(err, ErrStore) {
		t.Errorf("Lease = %v", err)
	}
	if j, err := q.Get(ctx(t), 1); err != nil || j.State != Leased {
		t.Errorf("Get, whose run-out lease cannot be written = %+v, %v; want the job still leased", j, err)
	}
	if got := snapshot(q); len(got) != len(before) || got["j_1"].State != Leased {
		t.Errorf("queue changed: %v", got)
	}
	f.fail = nil
	if j := mustLease(t, q, "a", "w2", 100); j.ID != 1 || j.Tries != 2 {
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

// Every rule of change 2 is tripped by a hand-written record, and the
// folder is refused at open with the record's key and the rule.
func TestIllFormedRecordsRefuseTheFolder(t *testing.T) {
	const at = "2026-09-14T00:00:00.000Z"
	for want, job := range map[string]string{
		"a leased job has a worker":                `{"id":"j_1","queue":"a","state":"leased","payload":"","tries":1,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `","lease_until":"` + at + `"}`,
		"a queued job has tries from 0 below":      `{"id":"j_1","queue":"a","state":"queued","payload":"","tries":3,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"a scheduled job has a run_at":             `{"id":"j_1","queue":"a","state":"scheduled","payload":"","tries":0,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"a scheduled job's run_at is after":        `{"id":"j_1","queue":"a","state":"scheduled","payload":"","tries":0,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `","run_at":"` + at + `"}`,
		"backoff_ms is 0 to 3_600_000":             `{"id":"j_1","queue":"a","state":"queued","payload":"","tries":0,"max_tries":3,"backoff_ms":3600001,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"a scheduled job has tries from 0 below":   `{"id":"j_1","queue":"a","state":"scheduled","payload":"","tries":3,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `","run_at":"2026-09-15T00:00:00.000Z"}`,
		"queue is 1 to 64 bytes":                   `{"id":"j_1","queue":"a b","state":"queued","payload":"","tries":0,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"created_at is at or before updated_at":    `{"id":"j_1","queue":"a","state":"done","payload":"","tries":1,"max_tries":3,"created_at":"2026-09-15T00:00:00.000Z","updated_at":"` + at + `"}`,
		"a done job has tries from 1 to max_tries": `{"id":"j_1","queue":"a","state":"done","payload":"","tries":0,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `"}`,
		"a queued job has no lease_until":          `{"id":"j_1","queue":"a","state":"queued","payload":"","tries":0,"max_tries":3,"created_at":"` + at + `","updated_at":"` + at + `","lease_until":"` + at + `"}`,
		"max_tries is 1 to 100":                    `{"id":"j_1","queue":"a","state":"queued","payload":"","tries":0,"max_tries":0,"created_at":"` + at + `","updated_at":"` + at + `"}`,
	} {
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, logName), []byte(lineFor(`{"op":"put","job":`+job+`}`)), 0o644); err != nil {
			t.Fatal(err)
		}
		_, _, err := openQueue(dir, realClock{})
		if err == nil || !strings.HasPrefix(err.Error(), dir+": record j_1: ") || !strings.Contains(err.Error(), want) {
			t.Errorf("open err = %v, want %q", err, want)
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
	if j, _ := q.Get(ctx(t), 1); j.State != Queued || j.Tries != 1 {
		t.Errorf("after restart %+v, want queued with tries 1", j)
	}
	if j := mustLease(t, q, "a", "w2", 1000); j.Tries != 2 {
		t.Errorf("re-leased with tries %d, want 2", j.Tries)
	}
}
