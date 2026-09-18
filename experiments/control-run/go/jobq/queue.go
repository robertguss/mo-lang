package main

import (
	"container/heap"
	"context"
	"errors"
	"fmt"
	"sort"
	"sync/atomic"
	"time"

	"controlrun/contract"
)

var (
	ErrNotFound = errors.New("no such job")
	ErrConflict = errors.New("conflict")
	ErrBusy     = errors.New("the queue did not answer in time")
)

// errBroken is a request that found the queue broken by an earlier one.
var errBroken = fmt.Errorf("%w: the board failed", ErrRestarting)

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

	// The archive: jobs moved off the board after retain, their file, and
	// the tombstoned ids since its last compaction. keys names the job of
	// every used key, on the board or archived. ends holds the updated_at
	// of done and dead jobs, for the archive move; unlogged is archived ids
	// whose arch record the log does not have yet. A queue with no archive
	// store never archives.
	archive  *Store
	retain   time.Duration
	archived map[uint64]*Job
	gone     map[uint64]bool
	keys     map[keyRef]uint64
	ends     deadlineHeap
	unlogged []uint64
	// unarched is, during a replay, the archived ids the log has a put for
	// and no arch after it yet: the job was on the board then, so a rename
	// replayed now is already in the archive's record of it.
	unarched map[uint64]bool
	// archOff is each archived job's offset in the archive file, so a
	// replayed prune removes only jobs whose record was written before it.
	archOff map[uint64]int64
	// logNext is, during a replay, one past the highest id the live log has
	// named so far: where a rename record without next_id (the change-5
	// reading) draws its line.
	logNext uint64

	// broken is set under lock by a failure that is not one request's: a
	// broken rule or a panic. Every later holder of lock leaves at once, and
	// the board rebuilds the queue from the log.
	broken atomic.Bool
	// chaos, when set, is told how many writes each commit applied, after
	// they are on disk, and fails the commit when it says so.
	chaos func(n int) bool
}

// Health is the body of GET /health.
type Health struct {
	Queued    int   `json:"queued"`
	Scheduled int   `json:"scheduled"`
	Leased    int   `json:"leased"`
	Done      int   `json:"done"`
	Dead      int   `json:"dead"`
	Archived  int   `json:"archived"`
	UptimeMS  int64 `json:"uptime_ms"`
	Restarts  int   `json:"restarts"`
}

// keyRef is a key in its queue; the same key in another queue is another.
type keyRef struct{ queue, key string }

func (j *Job) keyRef() (keyRef, bool) { return keyRef{j.Queue, j.Key}, j.Key != "" }

// change is one job's step: old is nil on create, new is nil on delete.
type change struct {
	old, new *Job
}

func newQueue(clock Clock) *Queue {
	return &Queue{
		lock: make(chan struct{}, 1), clock: clock, jobs: map[uint64]*Job{},
		queued: map[string]*idHeap{}, counts: map[State]int{}, nextID: 1,
		retain: defaultRetainMS * time.Millisecond, archived: map[uint64]*Job{}, gone: map[uint64]bool{},
		keys: map[keyRef]uint64{}, unarched: map[uint64]bool{}, archOff: map[uint64]int64{}, logNext: 1,
	}
}

func (q *Queue) closeArchive() error {
	if q.archive == nil {
		return nil
	}
	return q.archive.Close()
}

// checkApart holds after an open: no job is on the board and archived, and
// no key names two jobs in one queue. An open reads the archive before the
// log, out of the order the records were written, so the key map is built
// again here from what the replay left, and checked as it is. An archived job
// whose arch record the log lacks (a kill fell between the two writes) gets
// one with the next commit, so a rename written after this open applies to
// it at the next.
func (q *Queue) checkApart() error {
	q.unlogged = append(q.unlogged, sortedSet(q.unarched)...)
	q.unarched = map[uint64]bool{}
	var errs []error
	for id := range q.archived {
		errs = append(errs, contract.Never(q.jobs[id] != nil, "a job is on the live board and in the archive at once"))
	}
	q.keys = map[keyRef]uint64{}
	for _, jobs := range []map[uint64]*Job{q.jobs, q.archived} {
		for _, j := range jobs {
			ref, ok := j.keyRef()
			if !ok {
				continue
			}
			_, used := q.keys[ref]
			errs = append(errs, contract.Never(used, "a key names two jobs in one queue at once"))
			q.keys[ref] = j.ID
		}
	}
	return errors.Join(errs...)
}

// lookup finds a job on the board or in the archive.
func (q *Queue) lookup(id uint64) *Job {
	if j := q.jobs[id]; j != nil {
		return j
	}
	return q.archived[id]
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

// guard marks the queue broken when err is a rule the queue itself broke; a
// failed requires is the caller's and leaves it serving.
func (q *Queue) guard(err error) error {
	var v *contract.Violation
	if errors.As(err, &v) && v.Kind != "requires" {
		q.broken.Store(true)
	}
	return err
}

// applyRecord replays one store record, checking the nevers and invariants
// as a live change would. A record's updated_at stands in for the clock.
func (q *Queue) applyRecord(rec record) error {
	switch rec.Op {
	case "meta":
		q.nextID = max(q.nextID, rec.NextID)
		q.logNext = max(q.logNext, rec.NextID)
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
		q.nextID = max(q.nextID, j.ID+1)
		q.logNext = max(q.logNext, j.ID+1)
		if q.archived[j.ID] != nil || q.gone[j.ID] {
			if q.archived[j.ID] != nil {
				q.unarched[j.ID] = true
			}
			return nil // stale: the archive's record wins
		}
		c := change{old: q.jobs[j.ID], new: &j}
		if err := checkNevers(c, j.UpdatedAt); err != nil {
			return err
		}
		q.install(c)
		return checkInvariants(j)
	case "arch":
		id, ok := parseID(rec.ID)
		if !ok || (q.archived[id] == nil && !q.gone[id]) {
			return fmt.Errorf("arch of a job not in the archive %q", rec.ID)
		}
		delete(q.unarched, id)
		if q.jobs[id] != nil {
			q.leave(id)
		}
		return nil
	case "rename":
		if err := wellFormedRename(rec); err != nil {
			return err
		}
		next := rec.NextID
		if next == 0 {
			next = q.logNext // a change-5 record: every job named so far
		}
		q.replayRename(rec.From, rec.To, next)
		return nil
	case "prune":
		if err := wellFormedPrune(rec, q.archiveSize()); err != nil {
			return err
		}
		return q.replayPrune(rec)
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

// applyArchived replays one archive record. A put archives the job, taking
// it off the board if the board still holds it; a del forgets an archived
// job and frees its key.
func (q *Queue) applyArchived(rec record, off int64) error {
	err := q.applyArchiveRecord(rec, off)
	var ill *illFormed
	if errors.As(err, &ill) {
		ill.archived = true
	}
	return err
}

func (q *Queue) applyArchiveRecord(rec record, off int64) error {
	switch rec.Op {
	case "put":
		if rec.Job == nil {
			return errors.New("put without a job")
		}
		if err := wellFormedArchived(rec.Job.ID, *rec.Job); err != nil {
			return err
		}
		j, err := jobFromView(*rec.Job)
		if err != nil {
			return err
		}
		if q.archived[j.ID] != nil || q.gone[j.ID] {
			return fmt.Errorf("job %s is archived twice", rec.Job.ID)
		}
		if live := q.jobs[j.ID]; live != nil {
			if err := contract.Never(live.Key != j.Key, "a job's key changes"); err != nil {
				return err
			}
			q.leave(j.ID)
		}
		q.archived[j.ID] = &j
		q.archOff[j.ID] = off
		if ref, ok := j.keyRef(); ok {
			q.keys[ref] = j.ID
		}
		q.nextID = max(q.nextID, j.ID+1)
		return checkInvariants(j)
	case "del":
		id, ok := parseID(rec.ID)
		if !ok || q.archived[id] == nil {
			return fmt.Errorf("del of unknown archived job %q", rec.ID)
		}
		q.forget(id)
		return nil
	}
	return fmt.Errorf("unknown archive op %q", rec.Op)
}

// forget drops an archived job, whose id stays gone until the archive is
// compacted, and frees its key.
func (q *Queue) forget(id uint64) {
	j := q.archived[id]
	delete(q.archived, id)
	delete(q.unarched, id)
	delete(q.archOff, id)
	q.gone[id] = true
	if ref, ok := j.keyRef(); ok && q.keys[ref] == id {
		delete(q.keys, ref)
	}
}

// leave takes a job off the board, keeping its key.
func (q *Queue) leave(id uint64) {
	q.counts[q.jobs[id].State]--
	delete(q.jobs, id)
	if len(q.order) > 2*len(q.jobs)+64 {
		q.pruneOrder()
	}
}

// install puts a change into memory and the indexes.
func (q *Queue) install(c change) {
	if c.new == nil {
		q.leave(c.old.ID)
		if ref, ok := c.old.keyRef(); ok && q.keys[ref] == c.old.ID {
			delete(q.keys, ref)
		}
		return
	}
	if c.old != nil {
		q.counts[c.old.State]--
	}
	j := *c.new
	q.jobs[j.ID] = &j
	if c.old == nil {
		q.order = append(q.order, j.ID)
		if ref, ok := j.keyRef(); ok {
			q.keys[ref] = j.ID
		}
	}
	q.counts[j.State]++
	if j.State == Done || j.State == Dead {
		heap.Push(&q.ends, deadline{at: j.UpdatedAt, id: j.ID})
	}
	if j.State == Queued && (c.old == nil || c.old.State != Queued) {
		h := q.queued[j.Queue]
		if h == nil {
			h = &idHeap{}
			q.queued[j.Queue] = h
		}
		heap.Push(h, j.ID)
	}
	if j.State == Leased && (c.old == nil || c.old.State != Leased || !c.old.LeaseUntil.Equal(j.LeaseUntil)) {
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
	// A handoff moves a live lease to another worker with its lease_until
	// and tries; any other change that leaves a live lease leased is a
	// second worker taking the job, or a handoff that changed the lease.
	handoff := isHandoff(*old, *n)
	return errors.Join(
		contract.Never(n.Key != old.Key, "a job's key changes"),
		contract.Never(n.Queue != old.Queue, "a job changes queue but by a rename"),
		contract.Never(n.State == Leased && liveLease && !handoff,
			"a job is held by two workers at once, or a handoff changes lease_until or tries"),
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

// isHandoff is the handoff step's shape: leased before and after, to the
// same lease_until, with the same tries.
func isHandoff(old, n Job) bool {
	return old.State == Leased && n.State == Leased && n.Tries == old.Tries && n.LeaseUntil.Equal(old.LeaseUntil)
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
	if q.broken.Load() {
		q.release()
		return nil, errBroken
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
			if err := q.guard(checkNevers(c, t.now)); err != nil {
				heap.Push(d.h, e)
				t.undo()
				q.release()
				return nil, err
			}
			q.install(c)
			t.moved = append(t.moved, c)
		}
	}
	t.archiveOld()
	return t, nil
}

// archiveStep is the archive move for one job at now: a done or dead job
// whose updated_at is at least retain before now comes back with
// archived_at set, and true; any other job is not due.
func archiveStep(j Job, now time.Time, retain time.Duration) (Job, bool) {
	if (j.State != Done && j.State != Dead) || j.UpdatedAt.After(now.Add(-retain)) {
		return Job{}, false
	}
	j.ArchivedAt = now
	return j, true
}

// archiveOld is the look's archive move. Every due job is appended to the
// archive in one write; once that is on disk the jobs are archived in
// memory, whatever happens to the log's arch records, which go with the
// next commit (the archive's record wins at open). If the archive write
// fails nothing moves, and the next look tries again. No job this look
// moved is due: a move sets updated_at to now.
func (t *tx) archiveOld() {
	q := t.q
	if q.archive == nil {
		return
	}
	var due []Job
	var popped []deadline
	seen := map[uint64]bool{}
	for q.ends.Len() > 0 && !q.ends[0].at.After(t.now.Add(-q.retain)) {
		e := heap.Pop(&q.ends).(deadline)
		j := q.jobs[e.id]
		if j == nil || seen[e.id] || !j.UpdatedAt.Equal(e.at) {
			continue
		}
		a, ok := archiveStep(*j, t.now, q.retain)
		if !ok {
			continue
		}
		seen[e.id] = true
		due = append(due, a)
		popped = append(popped, e)
	}
	if len(due) == 0 {
		return
	}
	recs := make([]record, len(due))
	for i := range due {
		v := jobView(due[i])
		recs[i] = record{Op: "put", Job: &v}
	}
	off := q.archive.size
	if err := q.archive.Append(recs...); err != nil {
		for _, e := range popped {
			heap.Push(&q.ends, e)
		}
		return
	}
	for i := range due {
		a := due[i]
		q.leave(a.ID)
		q.archived[a.ID] = &a
		q.archOff[a.ID] = off
		q.unlogged = append(q.unlogged, a.ID)
	}
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
func (t *tx) commit(changes ...change) error { return t.commitWith(nil, nil, changes...) }

// commitWith is commit with extra records written after the changes' and
// apply run after the changes are installed, both only once the write is
// durable.
func (t *tx) commitWith(extra []record, apply func(), changes ...change) error {
	all := append(t.moved, changes...)
	if len(all) == 0 && len(t.q.unlogged) == 0 && len(extra) == 0 {
		return nil
	}
	for _, c := range changes {
		back := c.new != nil && t.q.archived[c.new.ID] != nil
		err := errors.Join(checkNevers(c, t.now), contract.Never(back, "an archived job comes back to the board"))
		if err := t.q.guard(err); err != nil {
			t.undo()
			return err
		}
	}
	recs := make([]record, 0, len(t.q.unlogged)+len(all))
	for _, id := range t.q.unlogged {
		recs = append(recs, record{Op: "arch", ID: formatID(id)})
	}
	recs = append(recs, records(all)...)
	recs = append(recs, extra...)
	if err := t.q.store.Append(recs...); err != nil {
		t.undo()
		return err
	}
	t.q.unlogged = nil
	if t.q.chaos != nil && t.q.chaos(len(recs)) {
		panic(errChaos)
	}
	t.moved = nil
	var errs []error
	for _, c := range changes {
		t.q.install(c)
	}
	if apply != nil {
		apply()
	}
	for _, c := range all {
		if c.new != nil {
			errs = append(errs, checkInvariants(*c.new))
		}
	}
	return t.q.guard(errors.Join(errs...))
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

// end releases the lock; moves never committed are undone first. A panic
// under the lock breaks the queue before the lock is let go, and goes on up.
func (t *tx) end() {
	v := recover()
	if v != nil {
		t.q.broken.Store(true)
	}
	t.undo()
	t.q.release()
	if v != nil {
		panic(v)
	}
}

// Create adds a job: queued, or scheduled at created_at + delayMS when
// delayMS is above 0. backoffMS is fixed for the job's life. key is empty
// for none. A key that already names a job in queue, on the board or
// archived, makes nothing: that job comes back with created false, and the
// other arguments are not looked at.
func (q *Queue) Create(ctx context.Context, queue, key, payload string, maxTries int, delayMS, backoffMS int64) (job Job, created bool, err error) {
	if err := requireQueue(queue); err != nil {
		return Job{}, false, err
	}
	if key != "" {
		if err := requireKey(key); err != nil {
			return Job{}, false, err
		}
	}
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, false, err
	}
	defer t.end()
	if id, used := q.keys[keyRef{queue, key}]; key != "" && used {
		if err := t.commitReads(); err != nil {
			return Job{}, false, err
		}
		return *q.lookup(id), false, nil
	}
	if err := errors.Join(requirePayload(payload), requireMaxTries(maxTries),
		requireDelayMS(delayMS), requireBackoffMS(backoffMS)); err != nil {
		return Job{}, false, err
	}
	id := q.nextID
	q.nextID++ // spent even if the write fails, so an id never repeats
	j := Job{ID: id, Queue: queue, Key: key, State: Queued, Payload: payload, MaxTries: maxTries, BackoffMS: backoffMS,
		CreatedAt: t.now, UpdatedAt: t.now}
	if delayMS > 0 {
		j.State, j.RunAt = Scheduled, t.now.Add(time.Duration(delayMS)*time.Millisecond)
	}
	if err := t.commit(change{new: &j}); err != nil {
		return Job{}, false, err
	}
	return *q.jobs[id], true, nil
}

// Get returns one job, on the board or archived.
func (q *Queue) Get(ctx context.Context, id uint64) (Job, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return Job{}, err
	}
	defer t.end()
	if err := t.commitReads(); err != nil {
		return Job{}, err
	}
	j := q.lookup(id)
	if j == nil {
		return Job{}, ErrNotFound
	}
	return *j, nil
}

// List returns up to 100 jobs on the board by id, filtered by queue and
// state when given. With a key it returns the one job the key names in
// queue, archived or not, if it passes the state filter.
func (q *Queue) List(ctx context.Context, queue, state, key string) ([]Job, error) {
	if key != "" {
		if err := errors.Join(contract.Require(queue != "", "key is given with queue"), requireKey(key)); err != nil {
			return nil, err
		}
	}
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
	if key != "" {
		if id, used := q.keys[keyRef{queue, key}]; used {
			if j := q.lookup(id); state == "" || string(j.State) == state {
				out = append(out, *j)
			}
		}
		return out, nil
	}
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

// Delete removes a job that is not leased. An archived job is tombstoned in
// the archive; the look's own moves are then written as a read's are, so a
// 503 still means nothing changed.
func (q *Queue) Delete(ctx context.Context, id uint64) error {
	t, err := q.begin(ctx)
	if err != nil {
		return err
	}
	defer t.end()
	j := q.jobs[id]
	switch {
	case j == nil && q.archived[id] != nil:
		if err := q.archive.Append(record{Op: "del", ID: formatID(id)}); err != nil {
			return err
		}
		q.forget(id)
		return t.commitReads()
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
	return got, true, q.guard(ensureLeased(*old, got, worker))
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
	if j == nil && q.archived[id] != nil {
		return nil, fmt.Errorf("%w: %s is archived", ErrConflict, formatID(id))
	}
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
	return got, q.guard(ensureDone(got))
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
	case old == nil && q.archived[id] != nil:
		return Job{}, errors.Join(t.commitReads(), fmt.Errorf("%w: %s is archived", ErrConflict, formatID(id)))
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
	return got, q.guard(ensureRetried(got))
}

// Handoff moves the lease the caller holds on a job to the worker to.
// requires: worker and to are tokens, and worker holds a live lease on the
// job (409 otherwise, as for ack). ensures: the job is leased to to, with
// the lease_until and tries it had. A handoff to the caller itself changes
// nothing and writes nothing.
func (q *Queue) Handoff(ctx context.Context, id uint64, worker, to string) (Job, error) {
	if err := errors.Join(requireWorker(worker), requireWorker(to)); err != nil {
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
	if to == worker {
		if err := t.commitReads(); err != nil {
			return Job{}, err
		}
		return *q.jobs[id], nil
	}
	n := handoffStep(*old, to, t.now)
	if err := t.commit(change{old: old, new: &n}); err != nil {
		return Job{}, err
	}
	got := *q.jobs[id]
	return got, q.guard(ensureHandedOff(*old, got, to))
}

// handoffStep is the handoff on a leased job: the worker changes, and
// updated_at, and nothing else.
func handoffStep(j Job, to string, now time.Time) Job {
	j.Worker, j.UpdatedAt = to, now
	return j
}

func ensureHandedOff(before, after Job, to string) error {
	return contract.Ensure(after.State == Leased && after.Worker == to && isHandoff(before, after),
		"the job is leased to the new worker with the lease_until and tries it had")
}

// errExists is a rename onto a queue that holds a job.
var errExists = fmt.Errorf("%w: exists", ErrConflict)

// noQueue is a rename of a queue that holds no job.
type noQueue struct{ name string }

func (e *noQueue) Error() string        { return fmt.Sprintf("no such queue %q", e.name) }
func (e *noQueue) Is(target error) bool { return target == ErrNotFound }

// Rename moves every job of from, on the board or archived, in any state,
// to the queue to, with its key. It is one record, written before any job
// moves. requires: from and to are queue names. from holds a job (404
// otherwise); to holds none and is not from (409). ensures: from holds no
// job and to holds the moved ones. A lease in flight moves with its job and
// is otherwise untouched: renameStep changes only Queue.
func (q *Queue) Rename(ctx context.Context, from, to string) (moved int, err error) {
	if err := errors.Join(requireQueue(from), requireQueue(to)); err != nil {
		return 0, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return 0, err
	}
	defer t.end()
	switch {
	case q.queueSize(from) == 0:
		return 0, errors.Join(t.commitReads(), &noQueue{from})
	case from == to:
		return 0, errors.Join(t.commitReads(), fmt.Errorf("%w: queue %q is the queue renamed", errExists, to))
	case q.queueSize(to) > 0:
		return 0, errors.Join(t.commitReads(), fmt.Errorf("%w: queue %q holds jobs", errExists, to))
	}
	before := q.queueSize(from)
	rec := record{Op: "rename", From: from, To: to, NextID: q.nextID}
	var clash error
	if err := t.commitWith([]record{rec}, func() { moved, clash = q.rename(from, to, q.nextID) }); err != nil {
		return 0, err
	}
	return moved, q.guard(errors.Join(clash, contract.Ensure(moved == before && q.queueSize(from) == 0 && q.queueSize(to) == moved,
		"every job of the old queue is in the new one, and none is left behind")))
}

// queueSize counts the jobs of a queue, on the board and archived.
func (q *Queue) queueSize(name string) int {
	n := 0
	for _, jobs := range []map[uint64]*Job{q.jobs, q.archived} {
		for _, j := range jobs {
			if j.Queue == name {
				n++
			}
		}
	}
	return n
}

// renameStep is the rename on one job: a job of from is in to, any other job
// is as it was.
func renameStep(j Job, from, to string) (Job, bool) {
	if j.Queue != from {
		return j, false
	}
	j.Queue = to
	return j, true
}

// renameKeys is the rename on the key map: every key used in from is used
// in to, for the same job, and free in from. A key already used in to would
// name two jobs there; Rename never gets one, as to holds no job and every
// used key names a job that is still held.
func renameKeys(keys map[keyRef]uint64, from, to string) (map[keyRef]uint64, error) {
	out := make(map[keyRef]uint64, len(keys))
	var clash bool
	for ref, id := range keys {
		if ref.queue == from {
			continue
		}
		out[ref] = id
	}
	for ref, id := range keys {
		if ref.queue != from {
			continue
		}
		_, used := out[keyRef{to, ref.key}]
		clash = clash || used
		out[keyRef{to, ref.key}] = id
	}
	return out, contract.Never(clash, "a rename lets a key name two jobs in one queue")
}

// rename applies a durable rename in memory: the jobs, the key map, and the
// queued index. An archived job moves only if it existed when the rename
// was written (its id is below nextID) and the replay has not seen it on the
// board since its last archive point (unarched): otherwise its archive record
// was written after the rename, under the name it has now.
func (q *Queue) rename(from, to string, nextID uint64) (moved int, err error) {
	move := func(j *Job) {
		if n, ok := renameStep(*j, from, to); ok {
			*j = n
			moved++
		}
	}
	for _, j := range q.jobs {
		move(j)
	}
	for id, j := range q.archived {
		if id < nextID && !q.unarched[id] {
			move(j)
		}
	}
	q.keys, err = renameKeys(q.keys, from, to)
	if h := q.queued[from]; h != nil {
		delete(q.queued, from)
		if dst := q.queued[to]; dst != nil {
			for _, id := range *h {
				heap.Push(dst, id)
			}
		} else {
			q.queued[to] = h
		}
	}
	return moved, err
}

// replayRename is a rename record replayed. The key map is rebuilt at the
// end of the open (checkApart), so a clash in the half-built one here says
// nothing.
func (q *Queue) replayRename(from, to string, nextID uint64) {
	_, _ = q.rename(from, to, nextID)
}

// archiveSize is the archive file's length as far as it is whole and synced.
func (q *Queue) archiveSize() int64 {
	if q.archive == nil {
		return 0
	}
	return q.archive.size
}

// pruneStep is the prune as a pure step over the archive: the ids, ascending,
// of every archived job archived at or before cutoff whose archive record
// starts before the archive's first before bytes. requires: cutoff is at
// least minPruneMS before the look that asks (Prune checks it). ensures: no
// live job is named, since only archived ones are looked at; every id named
// is archived at or before cutoff.
func pruneStep(archived map[uint64]*Job, offs map[uint64]int64, cutoff time.Time, before int64) []uint64 {
	var ids []uint64
	for id, j := range archived {
		if !j.ArchivedAt.After(cutoff) && offs[id] < before {
			ids = append(ids, id)
		}
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}

// ensurePruned is the prune's ensures, checked on the queue after it: no id
// pruned is on the board or archived, every one was archived at or before
// cutoff, and no key names it.
func (q *Queue) ensurePruned(pruned []*Job, cutoff time.Time) error {
	ok := true
	for _, j := range pruned {
		ok = ok && q.jobs[j.ID] == nil && q.archived[j.ID] == nil && !j.ArchivedAt.After(cutoff)
		if ref, keyed := j.keyRef(); keyed {
			ok = ok && q.keys[ref] != j.ID
		}
	}
	return contract.Ensure(ok, "every pruned job was archived at or before the cutoff, is gone, and frees its key")
}

// Prune removes every archived job archived at least olderThanMS before now,
// as one record in the live log naming the cutoff and the count, written
// before any job goes. A prune that finds nothing writes nothing but the
// look's moves. requires: olderThanMS is minPruneMS to maxPruneMS. A live job
// is never looked at.
func (q *Queue) Prune(ctx context.Context, olderThanMS int64) (pruned, remaining int, err error) {
	if err := requireOlderThanMS(olderThanMS); err != nil {
		return 0, 0, err
	}
	t, err := q.begin(ctx)
	if err != nil {
		return 0, 0, err
	}
	defer t.end()
	cutoff := t.now.Add(-time.Duration(olderThanMS) * time.Millisecond)
	ids := pruneStep(q.archived, q.archOff, cutoff, q.archiveSize())
	if len(ids) == 0 {
		return 0, len(q.archived), t.commitReads()
	}
	gone := make([]*Job, len(ids))
	for i, id := range ids {
		gone[i] = q.archived[id]
	}
	rec := record{Op: "prune", Cutoff: formatTime(cutoff), Count: len(ids), ArchiveSize: q.archiveSize()}
	if err := t.commitWith([]record{rec}, func() {
		for _, id := range ids {
			q.forget(id)
		}
	}); err != nil {
		return 0, 0, err
	}
	return len(ids), len(q.archived), q.guard(q.ensurePruned(gone, cutoff))
}

// replayPrune is a prune record replayed: the archive was read before the
// log, so the jobs whose archive record lies past the record's archive_size
// were archived after the prune and stay.
func (q *Queue) replayPrune(rec record) error {
	cutoff, _ := time.Parse(timeLayout, rec.Cutoff)
	ids := pruneStep(q.archived, q.archOff, cutoff, rec.ArchiveSize)
	if err := contract.Never(len(ids) != rec.Count, "a replayed prune removes other than the count its record names"); err != nil {
		return fmt.Errorf("prune at %s: %w (count %d, found %d)", rec.Cutoff, err, rec.Count, len(ids))
	}
	for _, id := range ids {
		q.forget(id)
	}
	return nil
}

// ArchiveInfo is the body of GET /archive.
type ArchiveInfo struct {
	Archived int     `json:"archived"`
	Oldest   *string `json:"oldest_archived_at"`
	Bytes    int64   `json:"bytes"`
}

// Archive counts the archive: its jobs, the oldest archived_at, and the
// file's bytes, pruned and deleted records included until a compaction.
func (q *Queue) Archive(ctx context.Context) (ArchiveInfo, error) {
	t, err := q.begin(ctx)
	if err != nil {
		return ArchiveInfo{}, err
	}
	defer t.end()
	if err := t.commitReads(); err != nil {
		return ArchiveInfo{}, err
	}
	info := ArchiveInfo{Archived: len(q.archived), Bytes: q.archiveSize()}
	var oldest time.Time
	for _, j := range q.archived {
		if oldest.IsZero() || j.ArchivedAt.Before(oldest) {
			oldest = j.ArchivedAt
		}
	}
	if !oldest.IsZero() {
		s := formatTime(oldest)
		info.Oldest = &s
	}
	return info, nil
}

func sortedSet(set map[uint64]bool) []uint64 {
	ids := make([]uint64, 0, len(set))
	for id := range set {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
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
		Done: q.counts[Done], Dead: q.counts[Dead], Archived: len(q.archived),
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
