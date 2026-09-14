package main

import (
	"container/heap"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sort"
	"time"

	"jobq/contract"
)

// The errors an operation answers with; the API maps each to a status.
var (
	ErrNotFound = errors.New("not found")
	ErrConflict = errors.New("conflict")
	ErrStore    = errors.New("store unavailable")
	ErrBusy     = errors.New("queue busy past the request's deadline")
)

// internalError is a broken ensures or invariant, a bug answered 500. It
// does not unwrap, so a requires inside it is not taken for bad input.
type internalError struct{ err error }

func (e internalError) Error() string { return "internal: " + e.err.Error() }

// QueueConfig is what a queue takes from main.
type QueueConfig struct {
	Now func() time.Time // main's clock
}

type entry struct {
	job  Job
	qgen uint64 // bumped each time the job enters queued
	lgen uint64 // bumped each time the job enters leased
}

// Queue holds every job in memory and writes every change to its log
// before applying it. One operation runs at a time; the lock is a channel so
// that waiting for it honours the request's deadline.
type Queue struct {
	lock    chan struct{}
	log     *Log
	now     func() time.Time
	started time.Time
	jobs    map[uint64]*entry
	ids     []uint64 // ascending; may hold ids since deleted
	holes   int
	next    uint64
	queued  map[string]*idHeap
	leases  leaseHeap
	counts  map[State]int
	expired int // lease expiries written
}

func newQueue(cfg QueueConfig) *Queue {
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	return &Queue{
		lock: make(chan struct{}, 1), now: now, started: now(),
		jobs: map[uint64]*entry{}, next: 1, queued: map[string]*idHeap{}, counts: map[State]int{},
	}
}

func (q *Queue) clock() time.Time { return q.now().UTC().Truncate(time.Millisecond) }

func (q *Queue) acquire(ctx context.Context) error {
	select {
	case q.lock <- struct{}{}:
		return nil
	case <-ctx.Done():
		return fmt.Errorf("%w: %v", ErrBusy, ctx.Err())
	}
}

func (q *Queue) release() { <-q.lock }

// do runs op under the lock after a look at every lease, then checks the
// never that a run-out lease is not held past that look.
func (q *Queue) do(ctx context.Context, op func(now time.Time) error) error {
	if err := q.acquire(ctx); err != nil {
		return err
	}
	defer q.release()
	now := q.clock()
	if err := q.sweep(now); err != nil {
		return err
	}
	if err := op(now); err != nil {
		return err
	}
	top, held := q.firstLease()
	if err := contract.Invariant(!held || top.until.After(now), "no lease that ran out is held after a look"); err != nil {
		return internalError{err}
	}
	return nil
}

func firstErr(errs ...error) error {
	for _, err := range errs {
		if err != nil {
			return err
		}
	}
	return nil
}

// Create adds a queued job.
func (q *Queue) Create(ctx context.Context, queue, payload string, maxAttempts int) (Job, error) {
	if err := firstErr(RequireQueueName(queue), RequirePayload(payload), RequireMaxAttempts(maxAttempts)); err != nil {
		return Job{}, err
	}
	var j Job
	err := q.do(ctx, func(now time.Time) error {
		id := q.next
		j = Job{ID: formatID(id), Queue: queue, State: Queued, Payload: payload, MaxAttempts: maxAttempts, CreatedAt: stampOf(now), UpdatedAt: stampOf(now)}
		return q.commit(record{Op: opPut, Next: id + 1, Job: &j})
	})
	return j, err
}

// Get returns one job.
func (q *Queue) Get(ctx context.Context, id string) (Job, error) {
	var j Job
	err := q.do(ctx, func(time.Time) error {
		e, err := q.find(id)
		if err == nil {
			j = e.job
		}
		return err
	})
	return j, err
}

// List returns up to limit jobs by id; an empty queue or state matches all.
func (q *Queue) List(ctx context.Context, queue string, state State, limit int) ([]Job, error) {
	if queue != "" {
		if err := RequireQueueName(queue); err != nil {
			return nil, err
		}
	}
	if err := contract.Require(state == "" || state.valid(), "state is queued, leased, done, or dead"); err != nil {
		return nil, err
	}
	jobs := []Job{}
	err := q.do(ctx, func(time.Time) error {
		q.eachJob(func(e *entry) bool {
			if (queue == "" || e.job.Queue == queue) && (state == "" || e.job.State == state) {
				jobs = append(jobs, e.job)
			}
			return len(jobs) < limit
		})
		return nil
	})
	return jobs, err
}

// Delete removes a job that is not leased.
func (q *Queue) Delete(ctx context.Context, id string) error {
	return q.do(ctx, func(time.Time) error {
		e, err := q.find(id)
		if err != nil {
			return err
		}
		if e.job.State == Leased {
			return fmt.Errorf("%w: %s is leased", ErrConflict, id)
		}
		return q.commit(record{Op: opDel, Next: q.next, ID: id})
	})
}

// Lease hands the oldest queued job of queue to worker until now + leaseMs.
// It reports false when nothing is queued.
func (q *Queue) Lease(ctx context.Context, queue, worker string, leaseMs int) (Job, bool, error) {
	if err := firstErr(RequireQueueName(queue), RequireWorker(worker), RequireLeaseMs(leaseMs)); err != nil {
		return Job{}, false, err
	}
	var j Job
	var leased bool
	err := q.do(ctx, func(now time.Time) error {
		id, ok := q.peekQueued(queue)
		if !ok {
			return nil
		}
		old := q.jobs[id].job
		j = old
		j.State, j.Attempts, j.Worker = Leased, old.Attempts+1, worker
		j.LeaseUntil, j.UpdatedAt = stampOf(now.Add(time.Duration(leaseMs)*time.Millisecond)), stampOf(now)
		if err := q.commit(record{Op: opPut, Next: q.next, Job: &j}); err != nil {
			return err
		}
		leased = true
		got := q.jobs[id].job
		return internalOr(contract.Ensure(got.State == Leased && got.Worker == worker && got.Attempts == old.Attempts+1,
			"the job is leased to the caller with attempts one higher"))
	})
	return j, leased, err
}

// Ack marks done a job the caller holds a live lease on.
func (q *Queue) Ack(ctx context.Context, id, worker string) (Job, error) {
	var j Job
	err := q.do(ctx, func(now time.Time) error {
		e, err := q.held(id, worker)
		if err != nil {
			return err
		}
		j = e.job
		j.State, j.Worker, j.LeaseUntil, j.UpdatedAt = Done, "", Stamp{}, stampOf(now)
		if err := q.commit(record{Op: opPut, Next: q.next, Job: &j}); err != nil {
			return err
		}
		return internalOr(contract.Ensure(e.job.State == Done, "the job is done"))
	})
	return j, err
}

// Fail gives back a job the caller holds a live lease on: queued again, or
// dead on its last attempt.
func (q *Queue) Fail(ctx context.Context, id, worker, reason string) (Job, error) {
	if err := RequireReason(reason); err != nil {
		return Job{}, err
	}
	var j Job
	err := q.do(ctx, func(now time.Time) error {
		e, err := q.held(id, worker)
		if err != nil {
			return err
		}
		j = release(e.job, now)
		j.Reason = &reason
		return q.commit(record{Op: opPut, Next: q.next, Job: &j})
	})
	return j, err
}

// Health counts the jobs in each state.
type Health struct {
	Queued   int   `json:"queued"`
	Leased   int   `json:"leased"`
	Done     int   `json:"done"`
	Dead     int   `json:"dead"`
	UptimeMs int64 `json:"uptime_ms"`
}

// Health is the listener's view of the queue; it is a look too.
func (q *Queue) Health(ctx context.Context) (Health, error) {
	var h Health
	err := q.do(ctx, func(now time.Time) error {
		h = Health{Queued: q.counts[Queued], Leased: q.counts[Leased], Done: q.counts[Done], Dead: q.counts[Dead], UptimeMs: now.Sub(q.started).Milliseconds()}
		return nil
	})
	return h, err
}

// Sweep is the listener's Idle: a look at every lease and nothing else.
func (q *Queue) Sweep(ctx context.Context) error {
	return q.do(ctx, func(time.Time) error { return nil })
}

func internalOr(err error) error {
	if err != nil {
		return internalError{err}
	}
	return nil
}

func (q *Queue) find(id string) (*entry, error) {
	n, ok := parseID(id)
	if !ok {
		return nil, fmt.Errorf("%w: %s", ErrNotFound, id)
	}
	e, found := q.jobs[n]
	if !found {
		return nil, fmt.Errorf("%w: %s", ErrNotFound, id)
	}
	return e, nil
}

// held finds a job worker holds a live lease on; the sweep before every
// operation has already put a run-out lease back.
func (q *Queue) held(id, worker string) (*entry, error) {
	e, err := q.find(id)
	if err != nil {
		return nil, err
	}
	if e.job.State != Leased || e.job.Worker != worker {
		return nil, fmt.Errorf("%w: the caller does not hold a live lease on %s", ErrConflict, id)
	}
	return e, nil
}

// release ends a lease: queued again below max_attempts, dead at it.
func release(j Job, now time.Time) Job {
	if j.Attempts >= j.MaxAttempts {
		j.State = Dead
	} else {
		j.State = Queued
	}
	j.Worker, j.LeaseUntil, j.UpdatedAt = "", Stamp{}, stampOf(now)
	return j
}

// sweep writes the expiry of every lease that ran out by now.
func (q *Queue) sweep(now time.Time) error {
	for {
		top, ok := q.firstLease()
		if !ok || top.until.After(now) {
			return nil
		}
		j := release(q.jobs[top.id].job, now)
		if err := q.commit(record{Op: opPut, Next: q.next, Job: &j}); err != nil {
			return err
		}
		q.expired++
	}
}

// firstLease drops stale heap items and returns the earliest live lease.
func (q *Queue) firstLease() (leaseItem, bool) {
	for len(q.leases) > 0 {
		top := q.leases[0]
		if e, found := q.jobs[top.id]; found && e.job.State == Leased && e.lgen == top.gen {
			return top, true
		}
		heap.Pop(&q.leases)
	}
	return leaseItem{}, false
}

// peekQueued returns the oldest queued job of queue without taking it.
func (q *Queue) peekQueued(queue string) (uint64, bool) {
	h := q.queued[queue]
	for h != nil && len(*h) > 0 {
		top := (*h)[0]
		if e, found := q.jobs[top.id]; found && e.job.State == Queued && e.qgen == top.gen {
			return top.id, true
		}
		heap.Pop(h)
	}
	delete(q.queued, queue)
	return 0, false
}

// eachJob visits live jobs by id until fn returns false.
func (q *Queue) eachJob(fn func(*entry) bool) {
	if q.holes > len(q.ids)/2 {
		live := q.ids[:0]
		for _, id := range q.ids {
			if _, found := q.jobs[id]; found {
				live = append(live, id)
			}
		}
		q.ids, q.holes = live, 0
	}
	for _, id := range q.ids {
		if e, found := q.jobs[id]; found && !fn(e) {
			return
		}
	}
}

func (q *Queue) insertID(id uint64) {
	n := len(q.ids)
	if n == 0 || q.ids[n-1] < id {
		q.ids = append(q.ids, id)
		return
	}
	i := sort.Search(n, func(i int) bool { return q.ids[i] >= id })
	q.ids = append(q.ids, 0)
	copy(q.ids[i+1:], q.ids[i:])
	q.ids[i] = id
}

// commit checks a change, makes it durable, and only then applies it.
func (q *Queue) commit(rec record) error {
	if err := q.check(rec); err != nil {
		return internalError{err}
	}
	line, err := json.Marshal(rec)
	if err != nil {
		return internalError{err}
	}
	before := q.log.Records()
	if err := q.log.Append(append(line, '\n')); err != nil {
		return fmt.Errorf("%w: %v", ErrStore, err)
	}
	if err := contract.Ensure(q.log.Records() == before+1, "the record is durable before it is applied"); err != nil {
		return internalError{err}
	}
	q.apply(rec)
	return nil
}

// replayRecord applies one record read back from the log, under the same
// checks as a live change.
func (q *Queue) replayRecord(rec record) error {
	if err := q.check(rec); err != nil {
		return err
	}
	q.apply(rec)
	return nil
}

// check holds the queue's invariants, run on every change before it is
// written and on every record replayed: a crafted log trips each one.
func (q *Queue) check(rec record) error {
	switch rec.Op {
	case opNext:
		return nil
	case opDel:
		e, err := q.find(rec.ID)
		if err != nil {
			return contract.Require(false, "a deletion names a job that exists")
		}
		return contract.Invariant(e.job.State != Leased, "a leased job is never deleted")
	case opPut:
		if rec.Job == nil {
			return contract.Require(false, "a put carries a job")
		}
		return q.checkPut(*rec.Job)
	}
	return contract.Require(false, `op is "put", "del", or "next"`)
}

func (q *Queue) checkPut(j Job) error {
	id, ok := parseID(j.ID)
	err := firstErr(
		contract.Require(ok, "id is j_<n>"),
		RequireQueueName(j.Queue),
		RequirePayload(j.Payload),
		RequireMaxAttempts(j.MaxAttempts),
		contract.Require(j.State.valid(), "state is queued, leased, done, or dead"),
		contract.Require(j.Reason == nil || RequireReason(*j.Reason) == nil, "reason is valid"),
		contract.Invariant(j.Attempts >= 0 && j.Attempts <= j.MaxAttempts, "0 <= attempts <= max_attempts"),
		contract.Invariant((j.State == Leased) == (j.Worker != "") && (j.State == Leased) == !j.LeaseUntil.IsZero(),
			"a job has a worker and a lease_until exactly when it is leased"),
	)
	if err != nil {
		return err
	}
	old, found := q.jobs[id]
	if !found {
		return contract.Invariant(id >= q.next, "a new job's id is above every id handed out before")
	}
	return checkTransition(old.job, j)
}

// checkTransition is the state machine. Done and dead are final, a job is
// leased only from queued (so never by two workers at once), and attempts
// grow by one exactly when a job is leased.
func checkTransition(old, j Job) error {
	legal := false
	switch {
	case old.State == Queued && j.State == Leased:
		legal = j.Attempts == old.Attempts+1
	case old.State == Leased && j.State == Done:
		legal = j.Attempts == old.Attempts
	case old.State == Leased && j.State == Queued:
		legal = j.Attempts == old.Attempts && j.Attempts < j.MaxAttempts
	case old.State == Leased && j.State == Dead:
		legal = j.Attempts == old.Attempts && j.Attempts == j.MaxAttempts
	}
	if err := contract.Invariant(legal, fmt.Sprintf("%s -> %s follows the state machine", old.State, j.State)); err != nil {
		return err
	}
	return contract.Invariant(j.Queue == old.Queue && j.Payload == old.Payload && j.MaxAttempts == old.MaxAttempts && j.CreatedAt.Equal(old.CreatedAt.Time),
		"a job's queue, payload, max_attempts, and created_at never change")
}

// apply changes memory after check passed and the record is durable.
func (q *Queue) apply(rec record) {
	q.next = max(q.next, rec.Next)
	switch rec.Op {
	case opPut:
		j := *rec.Job
		id, _ := parseID(j.ID)
		e, found := q.jobs[id]
		if found {
			q.counts[e.job.State]--
		} else {
			e = &entry{}
			q.jobs[id] = e
			q.insertID(id)
		}
		e.job = j
		q.counts[j.State]++
		q.next = max(q.next, id+1)
		switch j.State {
		case Queued:
			e.qgen++
			h := q.queued[j.Queue]
			if h == nil {
				h = &idHeap{}
				q.queued[j.Queue] = h
			}
			heap.Push(h, idItem{id: id, gen: e.qgen})
		case Leased:
			e.lgen++
			heap.Push(&q.leases, leaseItem{until: j.LeaseUntil.Time, id: id, gen: e.lgen})
		}
	case opDel:
		id, _ := parseID(rec.ID)
		if e, found := q.jobs[id]; found {
			q.counts[e.job.State]--
			delete(q.jobs, id)
			q.holes++
		}
	}
}

// writeCompact writes one put per live job by id, then the id counter.
func (q *Queue) writeCompact(w io.Writer) (int, error) {
	kept := 0
	var werr error
	write := func(rec record) bool {
		line, err := json.Marshal(rec)
		if err == nil {
			_, err = w.Write(append(line, '\n'))
		}
		werr = err
		return err == nil
	}
	q.eachJob(func(e *entry) bool {
		id, _ := parseID(e.job.ID)
		kept++
		return write(record{Op: opPut, Next: id + 1, Job: &e.job})
	})
	if werr == nil {
		write(record{Op: opNext, Next: q.next})
	}
	return kept, werr
}

type idItem struct{ id, gen uint64 }

type idHeap []idItem

func (h idHeap) Len() int           { return len(h) }
func (h idHeap) Less(i, j int) bool { return h[i].id < h[j].id }
func (h idHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *idHeap) Push(x any)        { *h = append(*h, x.(idItem)) }
func (h *idHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}

type leaseItem struct {
	until   time.Time
	id, gen uint64
}

type leaseHeap []leaseItem

func (h leaseHeap) Len() int { return len(h) }
func (h leaseHeap) Less(i, j int) bool {
	if !h[i].until.Equal(h[j].until) {
		return h[i].until.Before(h[j].until)
	}
	return h[i].id < h[j].id
}
func (h leaseHeap) Swap(i, j int) { h[i], h[j] = h[j], h[i] }
func (h *leaseHeap) Push(x any)   { *h = append(*h, x.(leaseItem)) }
func (h *leaseHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}
