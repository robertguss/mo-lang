package main

import (
	"cmp"
	"errors"
	"fmt"
	"slices"
	"time"
)

// Slow is one entry of the slowest list.
type Slow struct {
	Duration uint32
	Method   string
	Path     string
	At       string
	at       time.Time
	seq      uint64
}

// Busy is one entry of the busiest list.
type Busy struct {
	Count  uint64
	Method string
	Path   string
}

// Summary is everything logstat reports.
type Summary struct {
	Requests  uint64
	Errors    uint64
	Successes uint64
	Malformed uint64
	ErrorRate float64
	PerMinute float64
	Slowest   []Slow
	Busiest   []Busy
}

// ErrContract is wrapped by every broken summary invariant.
var ErrContract = errors.New("contract broken")

type route struct{ method, path string }

// Accumulator folds lines into a Summary one at a time, so memory is bounded
// by --top and the number of distinct routes, never by file size.
type Accumulator struct {
	top      int
	since    time.Time
	hasSince bool
	sum      Summary
	first    time.Time
	last     time.Time
	seq      uint64
	routes   map[route]uint64
}

// NewAccumulator starts an empty summary keeping the top entries of each list.
func NewAccumulator(top int, since time.Time, hasSince bool) *Accumulator {
	return &Accumulator{top: top, since: since, hasSince: hasSince, routes: map[route]uint64{}}
}

// AddLine parses one line and counts it as a request or as malformed.
func (a *Accumulator) AddLine(line string) {
	rec, err := ParseLine(line)
	if err != nil {
		a.AddMalformed()
		return
	}
	a.AddRecord(rec)
}

// AddMalformed counts one line that could not be parsed.
func (a *Accumulator) AddMalformed() { a.sum.Malformed++ }

// AddRecord counts one request, unless it is before --since.
func (a *Accumulator) AddRecord(r Record) {
	if a.hasSince && r.At.Before(a.since) {
		return
	}
	a.sum.Requests++
	if IsError(r.Status) {
		a.sum.Errors++
	} else {
		a.sum.Successes++
	}
	if a.sum.Requests == 1 || r.At.Before(a.first) {
		a.first = r.At
	}
	if a.sum.Requests == 1 || r.At.After(a.last) {
		a.last = r.At
	}
	a.routes[route{r.Method, r.Path}]++
	a.seq++
	a.keepSlow(Slow{Duration: r.Duration, Method: r.Method, Path: r.Path, At: r.AtText, at: r.At, seq: a.seq})
}

// IsError reports whether a status counts as an error: 500 to 599.
func IsError(status int) bool { return status >= 500 && status <= 599 }

// keepSlow inserts s in order and drops whatever falls past top.
func (a *Accumulator) keepSlow(s Slow) {
	i, _ := slices.BinarySearchFunc(a.sum.Slowest, s, compareSlow)
	if i >= a.top {
		return
	}
	a.sum.Slowest = slices.Insert(a.sum.Slowest, i, s)
	if len(a.sum.Slowest) > a.top {
		a.sum.Slowest = a.sum.Slowest[:a.top]
	}
}

// compareSlow orders by duration descending, then timestamp ascending, then
// input order, so ties are stable and deterministic.
func compareSlow(x, y Slow) int {
	return cmp.Or(
		cmp.Compare(y.Duration, x.Duration),
		x.at.Compare(y.at),
		cmp.Compare(x.seq, y.seq),
	)
}

// compareBusy orders by count descending, then path ascending, then method.
func compareBusy(x, y Busy) int {
	return cmp.Or(
		cmp.Compare(y.Count, x.Count),
		cmp.Compare(x.Path, y.Path),
		cmp.Compare(x.Method, y.Method),
	)
}

// Summary finishes the report and checks its invariants.
func (a *Accumulator) Summary() (Summary, error) {
	s := a.sum
	s.Slowest = slices.Clone(a.sum.Slowest)
	s.Busiest = busiest(a.routes, a.top)
	s.ErrorRate = ratio(s.Errors, s.Requests)
	s.PerMinute = perMinute(s.Requests, a.first, a.last)
	if err := s.Check(); err != nil {
		return Summary{}, err
	}
	return s, nil
}

func busiest(routes map[route]uint64, top int) []Busy {
	list := make([]Busy, 0, len(routes))
	for r, n := range routes {
		list = append(list, Busy{Count: n, Method: r.method, Path: r.path})
	}
	slices.SortFunc(list, compareBusy)
	if len(list) > top {
		list = list[:top]
	}
	return list
}

func ratio(part, whole uint64) float64 {
	if whole == 0 {
		return 0
	}
	return float64(part) / float64(whole)
}

// perMinute is requests over the span from first to last timestamp; a single
// request, or requests all at one instant, is 0.
func perMinute(requests uint64, first, last time.Time) float64 {
	span := last.Sub(first)
	if requests < 2 || span <= 0 {
		return 0
	}
	return float64(requests) / span.Minutes()
}

// Check is the summary's contract: requests = errors + successes,
// errors <= requests, both lists in their promised order, no card number.
func (s Summary) Check() error {
	switch {
	case s.Errors > s.Requests:
		return fmt.Errorf("%w: errors %d > requests %d", ErrContract, s.Errors, s.Requests)
	case s.Requests != s.Errors+s.Successes:
		return fmt.Errorf("%w: requests %d != errors %d + successes %d", ErrContract, s.Requests, s.Errors, s.Successes)
	case !slices.IsSortedFunc(s.Slowest, compareSlow):
		return fmt.Errorf("%w: slowest list out of order", ErrContract)
	case !slices.IsSortedFunc(s.Busiest, compareBusy):
		return fmt.Errorf("%w: busiest list out of order", ErrContract)
	}
	for _, e := range s.Slowest {
		if HasCard(e.Method) || HasCard(e.Path) || HasCard(e.At) {
			return fmt.Errorf("%w: card number in slowest list", ErrContract)
		}
	}
	for _, e := range s.Busiest {
		if HasCard(e.Method) || HasCard(e.Path) {
			return fmt.Errorf("%w: card number in busiest list", ErrContract)
		}
	}
	return nil
}
