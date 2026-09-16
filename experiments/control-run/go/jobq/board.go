package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// The board is the queue and its store as the API reaches them. When the
// queue fails in a way that is not one request's failure (a broken rule, a
// panic under its lock, the chaos switch), the board closes the store and
// replays the log into a new queue; requests are answered 503 while it does.
// More than maxRestarts restarts inside window and it gives up instead: done
// is closed, the store already closed and whole, and serve exits 70.

// ErrRestarting is a request that reached the board while it was down.
var ErrRestarting = errors.New("the service is restarting")

// errChaos is the failure --crash-every injects.
var errChaos = errors.New("chaos: injected failure after a write reached the store")

const (
	defaultMaxRestarts   = 5
	defaultRestartWindow = 60 * time.Second
	exitGaveUp           = 70
)

// BoardConfig is the restart budget, the chaos switch, and how long a done
// or dead job stays on the board before it is archived.
type BoardConfig struct {
	MaxRestarts int
	Window      time.Duration
	CrashEvery  uint64        // 0 never fails
	Retain      time.Duration // 0 is the default, a day

	crash func(n int) bool // the tests' chaos, in place of CrashEvery
}

// retain is the configured retain, the default when none is.
func (c BoardConfig) retain() time.Duration {
	if c.Retain <= 0 {
		return defaultRetainMS * time.Millisecond
	}
	return c.Retain
}

func defaultBoardConfig() BoardConfig {
	return BoardConfig{MaxRestarts: defaultMaxRestarts, Window: defaultRestartWindow,
		Retain: defaultRetainMS * time.Millisecond}
}

type boardState struct {
	q *Queue
	s *Store
}

// Board supervises one queue at a time.
type Board struct {
	open    func() (*Queue, *Store, error)
	clock   Clock
	cfg     BoardConfig
	logf    func(format string, args ...any)
	started time.Time

	cur      atomic.Pointer[boardState] // nil while restarting or stopped
	writes   atomic.Uint64
	failNext atomic.Bool // the check script's `crash`
	restarts atomic.Int64

	pending  sync.WaitGroup // restarts started and not yet finished
	mu       sync.Mutex     // held by a restart and by stop
	times    []time.Time
	stopped  bool
	done     chan struct{}
	doneOnce sync.Once
}

// newBoard opens the first queue through open; its errors are the caller's.
func newBoard(open func() (*Queue, *Store, error), clock Clock, cfg BoardConfig) (*Board, error) {
	b := &Board{open: open, clock: clock, cfg: cfg, logf: func(string, ...any) {}, done: make(chan struct{})}
	q, s, err := open()
	if err != nil {
		return nil, err
	}
	b.started = q.started
	b.install(q, s)
	return b, nil
}

func (b *Board) install(q *Queue, s *Store) {
	q.started = b.started
	switch {
	case b.cfg.crash != nil:
		q.chaos = b.cfg.crash
	default:
		q.chaos = b.chaos
	}
	b.cur.Store(&boardState{q: q, s: s})
}

// chaos counts n writes applied and says whether one of them was an N-th,
// or whether a failure was asked for. Only the queue's lock holder calls it.
func (b *Board) chaos(n int) bool {
	before := b.writes.Load()
	after := b.writes.Add(uint64(n))
	if b.failNext.CompareAndSwap(true, false) {
		return true
	}
	return b.cfg.CrashEvery > 0 && after/b.cfg.CrashEvery > before/b.cfg.CrashEvery
}

// crashNext makes the next write the board applies fail as the chaos switch
// would.
func (b *Board) crashNext() { b.failNext.Store(true) }

// Restarts is the count since the board was made.
func (b *Board) Restarts() int { return int(b.restarts.Load()) }

// Done is closed when the board has given up.
func (b *Board) Done() <-chan struct{} { return b.done }

// state returns the live queue, or nil while the board is down.
func (b *Board) state() *boardState { return b.cur.Load() }

// failed is called after every request that used st: when the queue marked
// itself broken, the board goes down at once and restarts in the background.
func (b *Board) failed(st *boardState) {
	if !st.q.broken.Load() || !b.cur.CompareAndSwap(st, nil) {
		return
	}
	b.pending.Add(1)
	go b.restart(st)
}

func (b *Board) restart(st *boardState) {
	defer b.pending.Done()
	b.mu.Lock()
	defer b.mu.Unlock()
	// A restart that itself fails is the budget spent: the service stops.
	defer func() {
		if v := recover(); v != nil {
			b.giveUp("the restart failed: %v", v)
		}
	}()
	// Every lock holder after the failure sees broken and leaves at once, so
	// this waits only for the request that was in flight.
	_ = st.q.acquire(context.Background())
	closeErr := errors.Join(st.s.Close(), st.q.closeArchive())
	st.q.release()
	if b.stopped {
		return
	}
	if closeErr != nil {
		b.giveUp("closing the store: %v", closeErr)
		return
	}
	now := b.clock.Now()
	kept := b.times[:0]
	for _, t := range b.times {
		if now.Sub(t) < b.cfg.Window {
			kept = append(kept, t)
		}
	}
	b.times = kept
	if len(kept) >= b.cfg.MaxRestarts {
		b.giveUp("%d restarts inside %v", len(kept), b.cfg.Window)
		return
	}
	q, s, err := b.open()
	if err != nil {
		b.giveUp("reopening the store: %v", err)
		return
	}
	b.times = append(b.times, now)
	b.restarts.Add(1)
	b.logf("jobq: the board failed and was rebuilt from the log (restart %d)", b.restarts.Load())
	b.install(q, s)
}

func (b *Board) giveUp(format string, args ...any) {
	b.stopped = true
	b.logf("jobq: giving up: %s", fmt.Sprintf(format, args...))
	b.doneOnce.Do(func() { close(b.done) })
}

// waitReady waits until the board serves or has given up; true if it serves.
func (b *Board) waitReady(ctx context.Context) bool {
	for {
		if b.state() != nil {
			return true
		}
		select {
		case <-b.done:
			return false
		case <-ctx.Done():
			return false
		case <-time.After(time.Millisecond):
		}
	}
}

// stop waits for a restart in progress, then closes the live store under
// the queue's lock so no change is half made.
func (b *Board) stop(ctx context.Context) error {
	b.pending.Wait()
	b.mu.Lock()
	defer b.mu.Unlock()
	b.stopped = true
	st := b.cur.Swap(nil)
	if st == nil {
		return nil
	}
	if err := st.q.acquire(ctx); err != nil {
		return errors.Join(err, st.s.Close(), st.q.closeArchive())
	}
	defer st.q.release()
	return errors.Join(st.s.Close(), st.q.closeArchive())
}
