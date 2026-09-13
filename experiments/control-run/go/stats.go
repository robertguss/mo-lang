package main

import (
	"cmp"
	"errors"
	"fmt"
	"slices"
	"time"
)

// Summary is everything the report prints.
type Summary struct {
	Requests  int
	Errors    int
	Malformed int
	PerMinute float64
	Slowest   []Record
	Busiest   []PathCount
}

// PathCount is one row of the busiest list.
type PathCount struct {
	Count  int
	Method string
	Path   string
}

type pathKey struct{ method, path string }

type ranked struct {
	rec Record
	seq int // input order, the last tie-break
}

// Collector folds records into a Summary one at a time, so no file is ever
// held in memory. It keeps only the top slowest records, never all of them.
type Collector struct {
	top       int
	since     time.Time
	hasSince  bool
	requests  int
	errors    int
	malformed int
	first     time.Time
	last      time.Time
	seq       int
	slowest   []ranked
	busiest   map[pathKey]int
}

// NewCollector requires top from 1 to 100.
func NewCollector(top int, since time.Time, hasSince bool) (*Collector, error) {
	if top < 1 || top > 100 {
		return nil, fmt.Errorf("top %d is outside 1 to 100", top)
	}
	return &Collector{top: top, since: since, hasSince: hasSince, busiest: map[pathKey]int{}}, nil
}

// AddLine parses one line and counts it: malformed, ignored by --since, or a
// request. Malformed lines count whatever their timestamp.
func (c *Collector) AddLine(line string) {
	rec, err := ParseLine(line)
	if err != nil {
		c.malformed++
		return
	}
	c.Add(rec)
}

// AddMalformed counts a line that never reached ParseLine (too long to read).
func (c *Collector) AddMalformed() { c.malformed++ }

// Add counts one well-formed record unless it is before --since.
func (c *Collector) Add(rec Record) {
	if c.hasSince && rec.At.Before(c.since) {
		return
	}
	if c.requests == 0 || rec.At.Before(c.first) {
		c.first = rec.At
	}
	if c.requests == 0 || rec.At.After(c.last) {
		c.last = rec.At
	}
	c.requests++
	if IsError(rec.Status) {
		c.errors++
	}
	c.busiest[pathKey{rec.Method, rec.Path}]++
	c.insertSlowest(ranked{rec, c.seq})
	c.seq++
}

func (c *Collector) insertSlowest(r ranked) {
	i, _ := slices.BinarySearchFunc(c.slowest, r, compareSlowest)
	if i >= c.top {
		return
	}
	c.slowest = slices.Insert(c.slowest, i, r)
	if len(c.slowest) > c.top {
		c.slowest = c.slowest[:c.top]
	}
}

// compareSlowest orders by duration descending, then timestamp ascending,
// then input order, so the order is total and deterministic.
func compareSlowest(a, b ranked) int {
	if a.rec.Duration != b.rec.Duration {
		return cmp.Compare(b.rec.Duration, a.rec.Duration)
	}
	if c := a.rec.At.Compare(b.rec.At); c != 0 {
		return c
	}
	return cmp.Compare(a.seq, b.seq)
}

// compareBusiest orders by count descending, then path ascending, then
// method ascending, so the order is total and deterministic.
func compareBusiest(a, b PathCount) int {
	if a.Count != b.Count {
		return cmp.Compare(b.Count, a.Count)
	}
	if a.Path != b.Path {
		return cmp.Compare(a.Path, b.Path)
	}
	return cmp.Compare(a.Method, b.Method)
}

// Summary builds the summary and checks its invariants.
func (c *Collector) Summary() (Summary, error) {
	s := Summary{
		Requests:  c.requests,
		Errors:    c.errors,
		Malformed: c.malformed,
		PerMinute: PerMinute(c.requests, c.first, c.last),
		Slowest:   make([]Record, 0, len(c.slowest)),
		Busiest:   make([]PathCount, 0, len(c.busiest)),
	}
	for _, r := range c.slowest {
		s.Slowest = append(s.Slowest, r.rec)
	}
	for k, n := range c.busiest {
		s.Busiest = append(s.Busiest, PathCount{Count: n, Method: k.method, Path: k.path})
	}
	slices.SortFunc(s.Busiest, compareBusiest)
	s.Busiest = s.Busiest[:min(len(s.Busiest), c.top)]
	return s, CheckSummary(s)
}

// ErrInvariant is wrapped by every error CheckSummary returns.
var ErrInvariant = errors.New("summary invariant broken")

// CheckSummary enforces the spec's nevers on counts: no count is negative,
// errors <= requests, and so requests == errors + successes with
// successes >= 0.
func CheckSummary(s Summary) error {
	if s.Requests < 0 || s.Errors < 0 || s.Malformed < 0 {
		return fmt.Errorf("%w: negative count", ErrInvariant)
	}
	if s.Errors > s.Requests {
		return fmt.Errorf("%w: errors %d > requests %d", ErrInvariant, s.Errors, s.Requests)
	}
	return nil
}

// PerMinute is requests over the span from the earliest to the latest
// timestamp, in minutes. With no span (zero or one request, or all at the
// same instant) it is 0.
func PerMinute(requests int, first, last time.Time) float64 {
	span := last.Sub(first).Minutes()
	if requests < 2 || span <= 0 {
		return 0
	}
	return float64(requests) / span
}
