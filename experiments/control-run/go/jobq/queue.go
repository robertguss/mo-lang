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
	leases  deadlineHeap // lease_until of leased jobs
	due     deadlineHeap // run_at of scheduled jobs
	counts  map[State]int
	nextID  uint64
}

// Health is the body of GET /health.
type Health struct {
	Queued    int   `json:"queued"`
	Scheduled int   `json:"scheduled"`
	Leased    int   `json:"leased"`
	Done      int   `json:"done"`
	Dead      int   `json:"dead"`
	UptimeMS  int64 `json:"uptime_ms"`
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
		if err := wellFormed(rec.Job.ID, *rec.Job); err != nil {
			return err
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
		heap.Push(&q.leases, deadline{at: j.LeaseUntil, id: j.ID})
	}
	if j.State == Scheduled {
		heap.Push(&q.due, deadline{at: j.RunAt, id: j.ID})
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
	tries := contract.Never(n.Tries > n.MaxTries, "a job's tries exceed its max_tries")
	if c.old == nil {
		return tries
	}
	old := c.old
	liveLease := old.State == Leased && old.LeaseUntil.After(now)
	terminal := old.State == Done || old.State == Dead
	retry := old.State == Dead && n.State == Queued && n.Tries == 0
	return errors.Join(
		contract.Never(n.State == Leased && liveLease, "a job is held by two workers at once"),
		contract.Never(n.State == Leased && terminal, "a done job is leased again, or a dead job before it is retried"),
		contract.Never(old.State == Done && n.State != Done, "a done job changes state"),
		contract.Never(old.State == Dead && n.State != Dead && !retry, "a dead job changes state but by a retry"),
		contract.Never(n.Tries < old.Tries && old.State != Dead, "a retry touches a job that is not dead"),
		contract.Never(n.State == Leased && old.State == Scheduled && old.RunAt.After(now),
			"a scheduled job is leased before its run_at"),
		tries,
	)
}

// checkInvariants holds for every job after every operation. Only the ones a
// store record can break are here; the report names those left out.
func checkInvariants(j Job) error {
	leased, scheduled := j.State == Leased, j.State == Scheduled
	return errors.Join(
		contract.Invariant(leased == (j.Worker != "") && leased == !j.LeaseUntil.IsZero(),
			"a job has a worker and lease_until exactly when it is leased"),
		contract.Invariant(scheduled == !j.RunAt.IsZero() && (!scheduled || j.RunAt.After(j.UpdatedAt)),
			"a job has run_at exactly when it is scheduled, and run_at is after updated_at"),
		contract.Invariant((j.State != Queued && !scheduled) || j.Tries < j.MaxTries,
			"a queued or scheduled job has tries below max_tries"),
		contract.Invariant(validQueueName(j.Queue) && validText(j.Payload, maxPayloadBytes) &&
			j.MaxTries >= 1 && j.MaxTries <= 100 && j.BackoffMS >= 0 && j.BackoffMS <= maxBackoffMS &&
			(j.Worker == "" || validToken(j.Worker)),
			"a job's queue, payload, max_tries, backoff_ms, and worker are valid"),
		contract.Invariant(j.Tries >= 0 && !j.UpdatedAt.Before(j.CreatedAt),
			"tries >= 0 and created_at <= updated_at"),
	)
}

// tx is one operation under the lock. Its look ends every lease that has run
// out, then queues every scheduled job whose run_at has come, in memory at
// once; commit writes those moves and the operation's changes as one store
// write, and undoes the moves if the write fails. So a run-out lease or a
// passed run_at never holds its job back past one look, and a 503 leaves
// both memory and the store as they were.
type tx struct {
	q     *Queue
	now   time.Time
	moved []change
}

func (q *Queue) begin(ctx context.Context) (*tx, error) {
	if err := q.acquire(ctx); err != nil {
		return nil, err
	}
	t := &tx{q: q, now: q.clock.Now()}
	// A run-out lease with backoff is scheduled after now, so it is never
	// due in the same look; the order of the two loops does not matter.
	for _, d := range []struct {
		h     *deadlineHeap
		state State
		at    func(*Job) time.Time
		move  func(*Job)
	}{
		{&q.leases, Leased, func(j *Job) time.Time { return j.LeaseUntil }, func(n *Job) {
			reason := "lease ran out"
			n.Reason = &reason
			n.afterTry(t.now)
		}},
		{&q.due, Scheduled, func(j *Job) time.Time { return j.RunAt }, func(n *Job) {
			n.State, n.RunAt, n.UpdatedAt = Queued, time.Time{}, t.now
		}},
	} {
		for d.h.Len() > 0 && !(*d.h)[0].at.After(t.now) {
			e := heap.Pop(d.h).(deadline)
			j := q.jobs[e.id]
			if j == nil || j.State != d.state || !d.at(j).Equal(e.at) {
				continue
			}
			n := *j
			d.move(&n)
			c := change{old: j, new: &n}
			if err := checkNevers(c, t.now); err != nil {
				heap.Push(d.h, e)
				t.undo()
				q.release()
				return nil, err
			}
			q.install(c)
			t.moved = append(t.moved, c)
		}
	}
	return t, nil
}

// afterTry ends a lease by a fail or by running out: dead when no try is
// left, else scheduled after the backoff, else queued.
func (n *Job) afterTry(now time.Time) {
	n.State, n.Worker, n.LeaseUntil, n.UpdatedAt = Queued, "", time.Time{}, now
	switch {
	case n.Tries >= n.MaxTries:
		n.State = Dead
	case n.BackoffMS > 0:
		n.State, n.RunAt = Scheduled, now.Add(time.Duration(n.BackoffMS)*time.Millisecond)
	}
}

// undo puts back the jobs whose move was not written.
func (t *tx) undo() {
	for i := len(t.moved) - 1; i >= 0; i-- {
		c := t.moved[i]
		t.q.install(change{old: t.q.jobs[c.old.ID], new: c.old})
	}
	t.moved = nil
}

// commit makes the moves and changes durable, then applies the changes.
func (t *tx) commit(changes ...change) error {
	all := append(t.moved, changes...)
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
	t.moved = nil
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

// commitReads writes the look's moves if it can. A read is answered even
// while the store refuses writes: the moves are undone, the read sees the
// state before them, and the next look makes them again. So an unwritable
// store costs the writes and nothing else.
func (t *tx) commitReads() error {
	if err := t.commit(); err != nil && !errors.Is(err, ErrStore) {
		return err
	}
	return nil
}

// end releases the lock; moves never committed are undone first.
func (t *tx) end() {
	t.undo()
	t.q.release()
}

// Create adds a job: queued, or scheduled at created_at + delayMS when
// delayMS is above 0. backoffMS is fixed for the job's life.
func (q *Queue) Create(ctx context.Context, queue, payload string, maxTries int, delayMS, backoffMS int64) (Job, error) {
	if err := errors.Join(requireQueue(queue), requirePayload(payload), requireMaxTries(maxTries),
		requireDelayMS(delayMS), requireBackoffMS(backoffMS)); err != nil {
		return Job{}, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	id := q.nextID
	q.nextID++ // spent even if the write fails, so an id never repeats
	j := Job{ID: id, Queue: queue, State: Queued, Payload: payload, MaxTries: maxTries, BackoffMS: backoffMS,
		CreatedAt: t.now, UpdatedAt: t.now}
	if delayMS > 0 {
		j.State, j.RunAt = Scheduled, t.now.Add(time.Duration(delayMS)*time.Millisecond)
	}
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
	if err := t.commitReads(); err != nil {
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
	if err := t.commitReads(); err != nil {
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
		return errors.Join(t.commitReads(), ErrNotFound)
	case j.State == Leased:
		return errors.Join(t.commitReads(), fmt.Errorf("%w: job is leased", ErrConflict))
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
		return Job{}, false, t.commitReads()
	}
	old := q.jobs[(*h)[0]]
	n := *old
	n.State, n.Tries, n.Worker, n.UpdatedAt = Leased, n.Tries+1, worker, t.now
	n.LeaseUntil = t.now.Add(time.Duration(leaseMS) * time.Millisecond)
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, false, err
	}
	heap.Pop(h)
	got := *q.jobs[n.ID]
	return got, true, ensureLeased(*old, got, worker)
}

func ensureLeased(before, after Job, worker string) error {
	return contract.Ensure(after.State == Leased && after.Worker == worker && after.Tries == before.Tries+1,
		"the job is leased to the caller with tries one higher")
}

func ensureDone(after Job) error {
	return contract.Ensure(after.State == Done, "the job is done")
}

func ensureRetried(after Job) error {
	return contract.Ensure(after.State == Queued && after.Tries == 0, "the job is queued with tries at 0")
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
		return Job{}, errors.Join(t.commitReads(), err)
	}
	n := *old
	n.State, n.Worker, n.LeaseUntil, n.UpdatedAt = Done, "", time.Time{}, t.now
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	got := *q.jobs[id]
	return got, ensureDone(got)
}

// Fail gives a held job back: queued, or scheduled after its backoff, while
// tries remain; dead after.
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
		return Job{}, errors.Join(t.commitReads(), err)
	}
	n := *old
	n.Reason = &reason
	n.afterTry(t.now)
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	return *q.jobs[id], nil
}

// Retry puts a dead job back in its queue with its tries at 0.
func (q *Queue) Retry(ctx context.Context, id uint64) (Job, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	old := q.jobs[id]
	switch {
	case old == nil:
		return Job{}, errors.Join(t.commitReads(), ErrNotFound)
	case old.State != Dead:
		return Job{}, errors.Join(t.commitReads(), fmt.Errorf("%w: %s is %s, not dead", ErrConflict, formatID(id), old.State))
	}
	n := *old
	n.State, n.Tries, n.Reason, n.UpdatedAt = Queued, 0, nil, t.now
	n.Worker, n.LeaseUntil, n.RunAt = "", time.Time{}, time.Time{}
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	got := *q.jobs[id]
	return got, ensureRetried(got)
}

// QueueCounts is one queue's jobs by state in GET /queues.
type QueueCounts struct {
	Name      string `json:"name"`
	Queued    int    `json:"queued"`
	Scheduled int    `json:"scheduled"`
	Leased    int    `json:"leased"`
	Done      int    `json:"done"`
	Dead      int    `json:"dead"`
}

// Queues counts the jobs of every queue that holds at least one, by name. A
// queue whose last job is deleted is not in the list, and the sums of the
// counts are what Health reports.
func (q *Queue) Queues(ctx context.Context) ([]QueueCounts, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return nil, err
	}
	defer t.end()
	if err := t.commitReads(); err != nil {
		return nil, err
	}
	by := map[string]*QueueCounts{}
	for _, j := range q.jobs {
		c := by[j.Queue]
		if c == nil {
			c = &QueueCounts{Name: j.Queue}
			by[j.Queue] = c
		}
		switch j.State {
		case Queued:
			c.Queued++
		case Scheduled:
			c.Scheduled++
		case Leased:
			c.Leased++
		case Done:
			c.Done++
		case Dead:
			c.Dead++
		}
	}
	out := make([]QueueCounts, 0, len(by))
	for _, c := range by {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// Health counts jobs by state.
func (q *Queue) Health(ctx context.Context) (Health, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return Health{}, err
	}
	defer t.end()
	if err := t.commitReads(); err != nil {
		return Health{}, err
	}
	return Health{
		Queued: q.counts[Queued], Scheduled: q.counts[Scheduled], Leased: q.counts[Leased],
		Done: q.counts[Done], Dead: q.counts[Dead],
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

// deadline is a job's lease_until or run_at; an entry whose job has since
// moved on is skipped when popped.
type deadline struct {
	at time.Time
	id uint64
}

type deadlineHeap []deadline

func (h deadlineHeap) Len() int { return len(h) }
func (h deadlineHeap) Less(i, j int) bool {
	if !h[i].at.Equal(h[j].at) {
		return h[i].at.Before(h[j].at)
	}
	return h[i].id < h[j].id
}
func (h deadlineHeap) Swap(i, j int) { h[i], h[j] = h[j], h[i] }
func (h *deadlineHeap) Push(x any)   { *h = append(*h, x.(deadline)) }
func (h *deadlineHeap) Pop() any {
	old := *h
	x := old[len(old)-1]
	*h = old[:len(old)-1]
	return x
}
