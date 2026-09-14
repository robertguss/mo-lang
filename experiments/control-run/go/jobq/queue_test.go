package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLeaseRunsOutAndIsLeasedAgainAtAttemptTwo(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	clock := newClock()
	q.now = clock.Now
	if _, err := q.Create(bg(), "q", "p", 3); err != nil {
		t.Fatal(err)
	}
	j, ok, err := q.Lease(bg(), "q", "w1", 100)
	if err != nil || !ok || j.Attempts != 1 || j.Worker != "w1" {
		t.Fatalf("%+v %v %v", j, ok, err)
	}
	clock.Advance(99 * time.Millisecond)
	if _, ok, _ := q.Lease(bg(), "q", "w2", 100); ok {
		t.Fatal("leased while w1 still holds it")
	}
	clock.Advance(time.Millisecond)
	j, ok, err = q.Lease(bg(), "q", "w2", 100)
	if err != nil || !ok || j.Attempts != 2 || j.Worker != "w2" {
		t.Fatalf("%+v %v %v", j, ok, err)
	}
	if _, err := q.Ack(bg(), j.ID, "w1"); !errors.Is(err, ErrConflict) {
		t.Errorf("w1's late ack: %v, want conflict", err)
	}
	if done, err := q.Ack(bg(), j.ID, "w2"); err != nil || done.State != Done {
		t.Errorf("w2's ack: %+v %v", done, err)
	}
	if q.expired != 1 {
		t.Errorf("expired %d", q.expired)
	}
}

func TestLeaseThatRunsOutOnItsLastAttemptIsDead(t *testing.T) {
	clock := newClock()
	q, _ := openTestQueue(t, t.TempDir(), clock)
	if _, err := q.Create(bg(), "q", "p", 1); err != nil {
		t.Fatal(err)
	}
	if _, ok, err := q.Lease(bg(), "q", "w", 100); !ok || err != nil {
		t.Fatal(ok, err)
	}
	clock.Advance(time.Second)
	j, err := q.Get(bg(), "j_1")
	if err != nil || j.State != Dead || j.Attempts != 1 || j.Worker != "" {
		t.Errorf("%+v %v", j, err)
	}
	if _, ok, err := q.Lease(bg(), "q", "w", 100); ok || err != nil {
		t.Errorf("a dead job was leased: %v %v", ok, err)
	}
}

func TestFailRequeuesThenKills(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	if _, err := q.Create(bg(), "q", "p", 2); err != nil {
		t.Fatal(err)
	}
	for attempt, want := range []State{Queued, Dead} {
		if _, ok, err := q.Lease(bg(), "q", "w", 1000); !ok || err != nil {
			t.Fatal(attempt, ok, err)
		}
		j, err := q.Fail(bg(), "j_1", "w", "boom")
		if err != nil || j.State != want || *j.Reason != "boom" || j.Attempts != attempt+1 {
			t.Errorf("attempt %d: %+v %v", attempt+1, j, err)
		}
	}
	if _, err := q.Fail(bg(), "j_1", "w", "again"); !errors.Is(err, ErrConflict) {
		t.Errorf("fail of a dead job: %v", err)
	}
}

func TestDoneJobIsNeverLeasedAgain(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	if _, err := q.Create(bg(), "q", "p", 5); err != nil {
		t.Fatal(err)
	}
	if _, _, err := q.Lease(bg(), "q", "w", 1000); err != nil {
		t.Fatal(err)
	}
	if _, err := q.Ack(bg(), "j_1", "w"); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if _, ok, err := q.Lease(bg(), "q", "w", 1000); ok || err != nil {
			t.Fatalf("leased a done job: %v %v", ok, err)
		}
		if _, err := q.Ack(bg(), "j_1", "w"); !errors.Is(err, ErrConflict) {
			t.Fatalf("acked a done job twice: %v", err)
		}
	}
}

func TestLeaseHandsOutOldestFirstPerQueue(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	for _, name := range []string{"a", "b", "a", "a"} {
		if _, err := q.Create(bg(), name, "p", 1); err != nil {
			t.Fatal(err)
		}
	}
	if err := q.Delete(bg(), "j_1"); err != nil {
		t.Fatal(err)
	}
	var got []string
	for {
		j, ok, err := q.Lease(bg(), "a", "w", 1000)
		if err != nil {
			t.Fatal(err)
		}
		if !ok {
			break
		}
		got = append(got, j.ID)
	}
	if strings.Join(got, ",") != "j_3,j_4" {
		t.Errorf("got %v", got)
	}
}

func TestReplayFindsTheLeaseRunOut(t *testing.T) {
	dir := t.TempDir()
	clock := newClock()
	st, err := openStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	q, err := loadQueue(st, QueueConfig{Now: clock.Now})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err := q.Create(bg(), "q", "p", 2); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := q.Lease(bg(), "q", "w", 1000); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(bg(), "j_2"); err != nil {
		t.Fatal(err)
	}
	if err := st.close(); err != nil {
		t.Fatal(err)
	}

	clock.Advance(2 * time.Second)
	q2, _ := openTestQueue(t, dir, clock)
	if h := q2.counts; h[Leased] != 1 || len(q2.jobs) != 1 {
		t.Fatalf("before a look: %v, %d jobs", h, len(q2.jobs))
	}
	j, err := q2.Get(bg(), "j_1")
	if err != nil || j.State != Queued || j.Attempts != 1 {
		t.Errorf("%+v %v", j, err)
	}
	if _, err := q2.Get(bg(), "j_2"); !errors.Is(err, ErrNotFound) {
		t.Errorf("deleted job came back: %v", err)
	}
	if j, err := q2.Create(bg(), "q", "p", 1); err != nil || j.ID != "j_3" {
		t.Errorf("ids repeat after replay: %s %v", j.ID, err)
	}
}

func TestListFiltersAndLimits(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	for i := 0; i < 105; i++ {
		if _, err := q.Create(bg(), []string{"a", "b"}[i%2], "p", 1); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := q.Lease(bg(), "b", "w", 1000); err != nil {
		t.Fatal(err)
	}
	all, err := q.List(bg(), "", "", 100)
	if err != nil || len(all) != 100 || all[0].ID != "j_1" || all[99].ID != "j_100" {
		t.Errorf("all: %d %v", len(all), err)
	}
	leased, err := q.List(bg(), "b", Leased, 100)
	if err != nil || len(leased) != 1 || leased[0].ID != "j_2" {
		t.Errorf("leased: %+v %v", leased, err)
	}
	if none, err := q.List(bg(), "a", Leased, 100); err != nil || len(none) != 0 {
		t.Errorf("none: %+v %v", none, err)
	}
	wantRequires(t, func() error { _, err := q.List(bg(), "", "sleeping", 100); return err }(), "state is queued")
	wantRequires(t, func() error { _, err := q.List(bg(), "no way", "", 100); return err }(), "queue is 1 to 64")
}

func TestDeleteRules(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	for i := 0; i < 2; i++ {
		if _, err := q.Create(bg(), "q", "p", 1); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := q.Lease(bg(), "q", "w", 1000); err != nil {
		t.Fatal(err)
	}
	if err := q.Delete(bg(), "j_1"); !errors.Is(err, ErrConflict) {
		t.Errorf("deleted a leased job: %v", err)
	}
	if err := q.Delete(bg(), "j_2"); err != nil {
		t.Error(err)
	}
	if err := q.Delete(bg(), "j_2"); !errors.Is(err, ErrNotFound) {
		t.Errorf("second delete: %v", err)
	}
}

// ensures on lease and ack hold on every call; the contract package's tests
// show the failure a broken one gives.
func TestLeaseAndAckEnsures(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	for i := 0; i < 20; i++ {
		if _, err := q.Create(bg(), "q", "p", 3); err != nil {
			t.Fatal(err)
		}
		before, _ := q.jobs[uint64(i+1)]
		attempts := before.job.Attempts
		j, ok, err := q.Lease(bg(), "q", "w", 1000)
		if err != nil || !ok || j.State != Leased || j.Worker != "w" || j.Attempts != attempts+1 {
			t.Fatalf("lease ensures: %+v %v", j, err)
		}
		if j, err := q.Ack(bg(), j.ID, "w"); err != nil || j.State != Done {
			t.Fatalf("ack ensures: %+v %v", j, err)
		}
	}
}

func TestRequiresRejectedByOperations(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	wantRequires(t, func() error { _, err := q.Create(bg(), "", "p", 1); return err }(), "queue is")
	wantRequires(t, func() error { _, err := q.Create(bg(), "q", "\x00", 1); return err }(), "payload is")
	wantRequires(t, func() error { _, err := q.Create(bg(), "q", "p", 0); return err }(), "max_attempts")
	wantRequires(t, func() error { _, _, err := q.Lease(bg(), "q", "w", 99); return err }(), "lease_ms")
	wantRequires(t, func() error { _, _, err := q.Lease(bg(), "q", "", 100); return err }(), "worker")
	wantRequires(t, func() error { _, err := q.Fail(bg(), "j_1", "w", "\x07"); return err }(), "reason")
	if len(q.jobs) != 0 || q.log.Records() != 0 {
		t.Errorf("a rejected call changed the queue")
	}
}

func TestBusyQueueAnswersWithinTheDeadline(t *testing.T) {
	q, _ := openTestQueue(t, t.TempDir(), newClock())
	if err := q.acquire(bg()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(bg(), 20*time.Millisecond)
	defer cancel()
	if _, err := q.Create(ctx, "q", "p", 1); !errors.Is(err, ErrBusy) {
		t.Errorf("got %v", err)
	}
	q.release()
}

// Each invariant is tripped by a record the queue accepts: a log line.
func TestInvariantsTripOnACraftedLog(t *testing.T) {
	put := func(state, extra string, attempts, maxAttempts int) string {
		return `{"op":"put","next":0,"job":{"id":"j_1","queue":"q","state":"` + state + `","payload":"p","attempts":` +
			itoa(attempts) + `,"max_attempts":` + itoa(maxAttempts) + `,"created_at":"2026-09-14T10:00:00.000Z","updated_at":"2026-09-14T10:00:00.000Z"` + extra + `}}`
	}
	lease := `,"worker":"w1","lease_until":"2026-09-14T10:00:30.000Z"`
	cases := map[string]struct {
		lines []string
		want  string
	}{
		"attempts over max":        {[]string{put("queued", "", 4, 3)}, "invariant failed: 0 <= attempts <= max_attempts"},
		"leased without a worker":  {[]string{put("leased", "", 1, 3)}, "invariant failed: a job has a worker and a lease_until exactly when it is leased"},
		"worker while queued":      {[]string{put("queued", lease, 1, 3)}, "invariant failed: a job has a worker"},
		"done leased again":        {[]string{put("done", "", 1, 3), put("leased", lease, 2, 3)}, "invariant failed: done -> leased follows the state machine"},
		"dead leased again":        {[]string{put("dead", "", 3, 3), put("leased", lease, 3, 3)}, "invariant failed: dead -> leased"},
		"held by two workers":      {[]string{put("leased", lease, 1, 3), put("leased", `,"worker":"w2","lease_until":"2026-09-14T10:00:30.000Z"`, 2, 3)}, "invariant failed: leased -> leased"},
		"lease without an attempt": {[]string{put("queued", "", 1, 3), put("leased", lease, 1, 3)}, "invariant failed: queued -> leased"},
		"dead below max_attempts":  {[]string{put("leased", lease, 1, 3), put("dead", "", 1, 3)}, "invariant failed: leased -> dead"},
		"payload changed": {[]string{put("queued", "", 0, 3), strings.Replace(put("leased", lease, 1, 3), `"payload":"p"`, `"payload":"other"`, 1)},
			"invariant failed: a job's queue, payload, max_attempts, and created_at never change"},
		"id handed out twice": {[]string{put("queued", "", 0, 3), `{"op":"del","next":2,"id":"j_1"}`, put("queued", "", 0, 3)},
			"invariant failed: a new job's id is above every id handed out before"},
		"leased job deleted": {[]string{put("leased", lease, 1, 3), `{"op":"del","next":2,"id":"j_1"}`}, "invariant failed: a leased job is never deleted"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, logName), []byte(strings.Join(c.lines, "\n")+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			st, err := openStore(dir)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = st.close() }()
			if _, err := loadQueue(st, QueueConfig{Now: newClock().Now}); err == nil || !strings.Contains(err.Error(), c.want) {
				t.Errorf("got %v\nwant %s", err, c.want)
			}
		})
	}
}

func itoa(n int) string { return formatID(uint64(n))[2:] }
