package main

import (
	"sync"
	"time"
)

// Clock is main's clock. The queue reads no other time, and every reading is
// UTC to the millisecond so a job survives the store's JSON unchanged.
type Clock interface {
	Now() time.Time
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now().UTC().Truncate(time.Millisecond) }

// manualClock moves only when told; `jobq check` and the tests use it.
type manualClock struct {
	mu  sync.Mutex
	now time.Time
}

func newManualClock(start time.Time) *manualClock {
	return &manualClock{now: start.UTC().Truncate(time.Millisecond)}
}

func (c *manualClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *manualClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d).Truncate(time.Millisecond)
}
