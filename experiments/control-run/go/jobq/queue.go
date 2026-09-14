package main

import (
	"container/heap"
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"controlrun/contract"
)

var (
	ErrNotFound = errors.New("no such job")
	ErrConflict = errors.New("conflict")
	ErrBusy     = errors.New("the queue did not answer in time")
)

// Appender is the store as the queue sees it.
type Appender interface {
	Append(recs ...record) error
}

// Queue holds every job in memory. One caller at a time holds lock, the Go
// reading of a process; a change is answered only after it is in the store.
type Queue struct {
	lock    chan struct{}
	clock   Clock
	store   Appender
	started time.Time
	jobs    map[uint64]*Job
	order   []uint64 // ids ascending; deleted ids are skipped when read
	queued  map[string]*idHeap
	leases  leaseHeap
	counts  map[State]int
	nextID  uint64
}

// Health is the body of GET /health.
type Health struct {
	Queued   int   `json:"queued"`
	Leased   int   `json:"leased"`
	Done     int   `json:"done"`
	Dead     int   `json:"dead"`
	UptimeMS int64 `json:"uptime_ms"`
}

// change is one job's step: old is nil on create, new is nil on delete.
type change struct {
	old, new *Job
}

func newQueue(clock Clock) *Queue {
	return &Queue{
		lock: make(chan struct{}, 1), clock: clock, jobs: map[uint64]*Job{},
		queued: map[string]*idHeap{}, counts: map[State]int{}, nextID: 1,
	}
}

// finishReplay attaches the store after replay and starts the uptime clock.
func (q *Queue) finishReplay(store Appender) {
	sort.Slice(q.order, func(i, j int) bool { return q.order[i] < q.order[j] })
	q.store = store
	q.started = q.clock.Now()
}

func (q *Queue) acquire(ctx context.Context) error {
	select {
	case q.lock <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ErrBusy
	}
}

func (q *Queue) release() { <-q.lock }

// applyRecord replays one store record, checking the nevers and invariants
// as a live change would. A record's updated_at stands in for the clock.
func (q *Queue) applyRecord(rec record) error {
	switch rec.Op {
	case "meta":
		q.nextID = max(q.nextID, rec.NextID)
		return nil
	case "put":
		if rec.Job == nil {
			return errors.New("put without a job")
		}
		j, err := jobFromView(*rec.Job)
		if err != nil {
			return err
		}
		c := change{old: q.jobs[j.ID], new: &j}
		if err := checkNevers(c, j.UpdatedAt); err != nil {
			return err
		}
		q.install(c)
		q.nextID = max(q.nextID, j.ID+1)
		return checkInvariants(j)
	case "del":
		id, ok := parseID(rec.ID)
		if !ok || q.jobs[id] == nil {
			return fmt.Errorf("del of unknown job %q", rec.ID)
		}
		q.install(change{old: q.jobs[id]})
		return nil
	}
	return fmt.Errorf("unknown op %q", rec.Op)
}

// install puts a change into memory and the indexes.
func (q *Queue) install(c change) {
	if c.old != nil {
		q.counts[c.old.State]--
	}
	if c.new == nil {
		delete(q.jobs, c.old.ID)
		if len(q.order) > 2*len(q.jobs)+64 {
			q.pruneOrder()
		}
		return
	}
	j := *c.new
	q.jobs[j.ID] = &j
	if c.old == nil {
		q.order = append(q.order, j.ID)
	}
	q.counts[j.State]++
	if j.State == Queued && (c.old == nil || c.old.State != Queued) {
		h := q.queued[j.Queue]
		if h == nil {
			h = &idHeap{}
			q.queued[j.Queue] = h
		}
		heap.Push(h, j.ID)
	}
	if j.State == Leased {
		heap.Push(&q.leases, leaseEntry{until: j.LeaseUntil, id: j.ID})
	}
}

func (q *Queue) pruneOrder() {
	kept := q.order[:0]
	for _, id := range q.order {
		if q.jobs[id] != nil {
			kept = append(kept, id)
		}
	}
	q.order = kept
}

func records(changes []change) []record {
	recs := make([]record, 0, len(changes))
	for _, c := range changes {
		if c.new == nil {
			recs = append(recs, record{Op: "del", ID: formatID(c.old.ID)})
			continue
		}
		v := jobView(*c.new)
		recs = append(recs, record{Op: "put", Job: &v})
	}
	return recs
}

// checkNevers is asserted on every state change, live or replayed.
func checkNevers(c change, now time.Time) error {
	if c.new == nil {
		return nil
	}
	n := c.new
	attempts := contract.Never(n.Attempts > n.MaxAttempts, "a job's attempts exceed its max_attempts")
	if c.old == nil {
		return attempts
	}
	old := c.old
	liveLease := old.State == Leased && old.LeaseUntil.After(now)
	terminal := old.State == Done || old.State == Dead
	return errors.Join(
		contract.Never(n.State == Leased && liveLease, "a job is held by two workers at once"),
		contract.Never(n.State == Leased && terminal, "a done or dead job is leased"),
		contract.Never(terminal && n.State != old.State, "a done or dead job changes state"),
		attempts,
	)
}

// checkInvariants holds for every job after every operation. Only the ones a
// store record can break are here; the report names those left out.
func checkInvariants(j Job) error {
	leased := j.State == Leased
	return errors.Join(
		contract.Invariant(leased == (j.Worker != "") && leased == !j.LeaseUntil.IsZero(),
			"a job has a worker and lease_until exactly when it is leased"),
		contract.Invariant(j.State != Queued || j.Attempts < j.MaxAttempts,
			"a queued job has attempts below max_attempts"),
		contract.Invariant(validQueueName(j.Queue) && validText(j.Payload, maxPayloadBytes) &&
			j.MaxAttempts >= 1 && j.MaxAttempts <= 100 && (j.Worker == "" || validToken(j.Worker)),
			"a job's queue, payload, max_attempts, and worker are valid"),
		contract.Invariant(j.Attempts >= 0 && !j.UpdatedAt.Before(j.CreatedAt),
			"attempts >= 0 and created_at <= updated_at"),
	)
}

// tx is one operation under the lock. Its look ends every lease that has run
// out, in memory at once; commit writes those expiries and the operation's
// changes as one store write, and undoes the expiries if the write fails.
// So a run-out lease never blocks its job past one look, and a 503 leaves
// both memory and the store as they were.
type tx struct {
	q       *Queue
	now     time.Time
	expired []change
}

func (q *Queue) begin(ctx context.Context) (*tx, error) {
	if err := q.acquire(ctx); err != nil {
		return nil, err
	}
	t := &tx{q: q, now: q.clock.Now()}
	for q.leases.Len() > 0 && !q.leases[0].until.After(t.now) {
		e := heap.Pop(&q.leases).(leaseEntry)
		j := q.jobs[e.id]
		if j == nil || j.State != Leased || !j.LeaseUntil.Equal(e.until) {
			continue
		}
		n := *j
		reason := "lease ran out"
		n.State, n.Worker, n.LeaseUntil, n.Reason, n.UpdatedAt = Queued, "", time.Time{}, &reason, t.now
		if n.Attempts >= n.MaxAttempts {
			n.State = Dead
		}
		c := change{old: j, new: &n}
		if err := checkNevers(c, t.now); err != nil {
			heap.Push(&q.leases, e)
			t.undo()
			q.release()
			return nil, err
		}
		q.install(c)
		t.expired = append(t.expired, c)
	}
	return t, nil
}

// undo puts back the jobs whose expiry was not written.
func (t *tx) undo() {
	for i := len(t.expired) - 1; i >= 0; i-- {
		c := t.expired[i]
		t.q.install(change{old: t.q.jobs[c.old.ID], new: c.old})
	}
	t.expired = nil
}

// commit makes the expiries and changes durable, then applies the changes.
func (t *tx) commit(changes ...change) error {
	all := append(t.expired, changes...)
	if len(all) == 0 {
		return nil
	}
	for _, c := range changes {
		if err := checkNevers(c, t.now); err != nil {
			t.undo()
			return err
		}
	}
	if err := t.q.store.Append(records(all)...); err != nil {
		t.undo()
		return err
	}
	t.expired = nil
	var errs []error
	for _, c := range changes {
		t.q.install(c)
	}
	for _, c := range all {
		if c.new != nil {
			errs = append(errs, checkInvariants(*c.new))
		}
	}
	return errors.Join(errs...)
}

// end releases the lock; expiries never committed are undone first.
func (t *tx) end() {
	t.undo()
	t.q.release()
}

// Create adds a queued job.
func (q *Queue) Create(ctx context.Context, queue, payload string, maxAttempts int) (Job, error) {
	if err := errors.Join(requireQueue(queue), requirePayload(payload), requireMaxAttempts(maxAttempts)); err != nil {
		return Job{}, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	id := q.nextID
	q.nextID++ // spent even if the write fails, so an id never repeats
	j := Job{ID: id, Queue: queue, State: Queued, Payload: payload, MaxAttempts: maxAttempts, CreatedAt: t.now, UpdatedAt: t.now}
	if err := t.commit(change{new: &j}); err != nil {
		return Job{}, err
	}
	return *q.jobs[id], nil
}

// Get returns one job.
func (q *Queue) Get(ctx context.Context, id uint64) (Job, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	if err := t.commit(); err != nil {
		return Job{}, err
	}
	j := q.jobs[id]
	if j == nil {
		return Job{}, ErrNotFound
	}
	return *j, nil
}

// List returns up to 100 jobs by id, filtered by queue and state when given.
func (q *Queue) List(ctx context.Context, queue, state string) ([]Job, error) {
	if queue != "" {
		if err := requireQueue(queue); err != nil {
			return nil, err
		}
	}
	if state != "" {
		if err := requireState(state); err != nil {
			return nil, err
		}
	}
	t, err := q.begin(ctx)
	if err != nil {
		return nil, err
	}
	defer t.end()
	if err := t.commit(); err != nil {
		return nil, err
	}
	out := []Job{}
	for _, id := range q.order {
		j := q.jobs[id]
		if j == nil || (queue != "" && j.Queue != queue) || (state != "" && string(j.State) != state) {
			continue
		}
		out = append(out, *j)
		if len(out) == 100 {
			break
		}
	}
	return out, nil
}

// Delete removes a job that is not leased.
func (q *Queue) Delete(ctx context.Context, id uint64) error {
	t, err := q.begin(ctx)
	if err != nil {
		return err
	}
	defer t.end()
	j := q.jobs[id]
	switch {
	case j == nil:
		return errors.Join(t.commit(), ErrNotFound)
	case j.State == Leased:
		return errors.Join(t.commit(), fmt.Errorf("%w: job is leased", ErrConflict))
	}
	return t.commit(change{old: j})
}

// Lease hands the oldest queued job of queue to worker. ok is false when
// nothing is queued.
func (q *Queue) Lease(ctx context.Context, queue, worker string, leaseMS int64) (job Job, ok bool, err error) {
	if err := errors.Join(requireQueue(queue), requireWorker(worker), requireLeaseMS(leaseMS)); err != nil {
		return Job{}, false, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, false, err
	}
	defer t.end()
	h := q.queued[queue]
	for h != nil && h.Len() > 0 {
		j := q.jobs[(*h)[0]]
		if j != nil && j.State == Queued && j.Queue == queue {
			break
		}
		heap.Pop(h)
	}
	if h == nil || h.Len() == 0 {
		return Job{}, false, t.commit()
	}
	old := q.jobs[(*h)[0]]
	n := *old
	n.State, n.Attempts, n.Worker, n.UpdatedAt = Leased, n.Attempts+1, worker, t.now
	n.LeaseUntil = t.now.Add(time.Duration(leaseMS) * time.Millisecond)
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, false, err
	}
	heap.Pop(h)
	got := *q.jobs[n.ID]
	return got, true, ensureLeased(*old, got, worker)
}

func ensureLeased(before, after Job, worker string) error {
	return contract.Ensure(after.State == Leased && after.Worker == worker && after.Attempts == before.Attempts+1,
		"the job is leased to the caller with attempts one higher")
}

func ensureDone(after Job) error {
	return contract.Ensure(after.State == Done, "the job is done")
}

// held returns the job if worker holds a live lease on it.
func (q *Queue) held(id uint64, worker string, now time.Time) (*Job, error) {
	j := q.jobs[id]
	if j == nil {
		return nil, ErrNotFound
	}
	if j.State != Leased || j.Worker != worker || !j.LeaseUntil.After(now) {
		return nil, fmt.Errorf("%w: the caller does not hold a live lease on %s", ErrConflict, formatID(id))
	}
	return j, nil
}

// Ack marks a job the caller holds as done.
func (q *Queue) Ack(ctx context.Context, id uint64, worker string) (Job, error) {
	if err := requireWorker(worker); err != nil {
		return Job{}, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	old, err := q.held(id, worker, t.now)
	if err != nil {
		return Job{}, errors.Join(t.commit(), err)
	}
	n := *old
	n.State, n.Worker, n.LeaseUntil, n.UpdatedAt = Done, "", time.Time{}, t.now
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	got := *q.jobs[id]
	return got, ensureDone(got)
}

// Fail gives a held job back: queued while attempts remain, dead after.
func (q *Queue) Fail(ctx context.Context, id uint64, worker, reason string) (Job, error) {
	if err := errors.Join(requireWorker(worker), requireReason(reason)); err != nil {
		return Job{}, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	old, err := q.held(id, worker, t.now)
	if err != nil {
		return Job{}, errors.Join(t.commit(), err)
	}
	n := *old
	n.State, n.Worker, n.LeaseUntil, n.Reason, n.UpdatedAt = Queued, "", time.Time{}, &reason, t.now
	if n.Attempts >= n.MaxAttempts {
		n.State = Dead
	}
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	return *q.jobs[id], nil
}

// Health counts jobs by state.
func (q *Queue) Health(ctx context.Context) (Health, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return Health{}, err
	}
	defer t.end()
	if err := t.commit(); err != nil {
		return Health{}, err
	}
	return Health{
		Queued: q.counts[Queued], Leased: q.counts[Leased], Done: q.counts[Done], Dead: q.counts[Dead],
		UptimeMS: t.now.Sub(q.started).Milliseconds(),
	}, nil
}

type idHeap []uint64

func (h idHeap) Len() int           { return len(h) }
func (h idHeap) Less(i, j int) bool { return h[i] < h[j] }
func (h idHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *idHeap) Push(x any)        { *h = append(*h, x.(uint64)) }
func (h *idHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}

type leaseEntry struct {
	until time.Time
	id    uint64
}

type leaseHeap []leaseEntry

func (h leaseHeap) Len() int { return len(h) }
func (h leaseHeap) Less(i, j int) bool {
	if !h[i].until.Equal(h[j].until) {
		return h[i].until.Before(h[j].until)
	}
	return h[i].id < h[j].id
}
func (h leaseHeap) Swap(i, j int) { h[i], h[j] = h[j], h[i] }
func (h *leaseHeap) Push(x any)   { *h = append(*h, x.(leaseEntry)) }
func (h *leaseHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}
