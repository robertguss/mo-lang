package main

import (
	"errors"
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"
	"time"
)

// Slow is one entry of the slowest list.
type Slow struct {
	Duration uint32
	Method   string
	Path     string
	AtText   string
	At       time.Time
	Seq      uint64
}

// Busy is one entry of the busiest list.
type Busy struct {
	Count  uint64
	Method string
	Path   string
}

// Summary is the result of reading every log file.
type Summary struct {
	Top       int
	Requests  uint64
	Errors    uint64
	Successes uint64
	Malformed uint64
	First     time.Time
	Last      time.Time
	Slowest   []Slow
	Busiest   []Busy
}

type busyKey struct{ method, path string }

// Accumulator folds lines into a Summary one at a time, so no file is held
// in memory.
type Accumulator struct {
	sum      Summary
	since    time.Time
	hasSince bool
	seq      uint64
	counts   map[busyKey]uint64
}

// Top bounds.
const (
	MinTop = 1
	MaxTop = 100
)

// ErrTop is returned when top is outside MinTop to MaxTop.
var ErrTop = fmt.Errorf("--top must be %d to %d", MinTop, MaxTop)

// NewAccumulator requires top in 1 to 100. A nil since keeps every line.
func NewAccumulator(top int, since *time.Time) (*Accumulator, error) {
	if top < MinTop || top > MaxTop {
		return nil, ErrTop
	}
	a := &Accumulator{sum: Summary{Top: top}, counts: map[busyKey]uint64{}}
	if since != nil {
		a.since, a.hasSince = *since, true
	}
	return a, nil
}

// AddLine parses one raw line and folds it in.
func (a *Accumulator) AddLine(line string) {
	r, err := ParseLine(line)
	if err != nil {
		a.AddMalformed()
		return
	}
	a.Add(r)
}

// AddMalformed counts a line that could not be parsed.
func (a *Accumulator) AddMalformed() {
	a.sum.Malformed++
}

// Add folds in one record, skipping it if it is before --since.
func (a *Accumulator) Add(r Record) {
	if a.hasSince && r.At.Before(a.since) {
		return
	}
	s := &a.sum
	if s.Requests == 0 || r.At.Before(s.First) {
		s.First = r.At
	}
	if s.Requests == 0 || r.At.After(s.Last) {
		s.Last = r.At
	}
	s.Requests++
	if r.Status >= 500 && r.Status <= 599 {
		s.Errors++
	} else {
		s.Successes++
	}
	path := MaskCards(r.Path)
	a.counts[busyKey{r.Method, path}]++
	a.seq++
	a.insertSlow(Slow{Duration: r.Duration, Method: r.Method, Path: path, AtText: r.AtText, At: r.At, Seq: a.seq})
}

// slowerThan orders by duration descending, timestamp ascending, then input
// order, so the order is total.
func slowerThan(x, y Slow) bool {
	if x.Duration != y.Duration {
		return x.Duration > y.Duration
	}
	if !x.At.Equal(y.At) {
		return x.At.Before(y.At)
	}
	return x.Seq < y.Seq
}

// busierThan orders by count descending, path ascending, then method.
func busierThan(x, y Busy) bool {
	if x.Count != y.Count {
		return x.Count > y.Count
	}
	if x.Path != y.Path {
		return x.Path < y.Path
	}
	return x.Method < y.Method
}

func (a *Accumulator) insertSlow(e Slow) {
	list := a.sum.Slowest
	if len(list) == a.sum.Top && !slowerThan(e, list[len(list)-1]) {
		return
	}
	i := sort.Search(len(list), func(i int) bool { return slowerThan(e, list[i]) })
	list = slices.Insert(list, i, e)
	if len(list) > a.sum.Top {
		list = list[:a.sum.Top]
	}
	a.sum.Slowest = list
}

// Summary returns the finished summary after checking its invariants.
func (a *Accumulator) Summary() (Summary, error) {
	s := a.sum
	s.Slowest = slices.Clone(a.sum.Slowest)
	s.Busiest = make([]Busy, 0, len(a.counts))
	for k, n := range a.counts {
		s.Busiest = append(s.Busiest, Busy{Count: n, Method: k.method, Path: k.path})
	}
	sort.Slice(s.Busiest, func(i, j int) bool { return busierThan(s.Busiest[i], s.Busiest[j]) })
	if len(s.Busiest) > s.Top {
		s.Busiest = s.Busiest[:s.Top]
	}
	if err := s.Check(); err != nil {
		return Summary{}, err
	}
	return s, nil
}

// Invariant violations reported by Check.
var (
	ErrErrorsExceed = errors.New("summary: errors > requests")
	ErrUnbalanced   = errors.New("summary: requests != errors + successes")
	ErrCardLeak     = errors.New("summary: a card number would reach stdout")
	ErrOrder        = errors.New("summary: list out of order or longer than top")
)

// Check enforces the nevers and ordering contracts on a summary.
func (s Summary) Check() error {
	if s.Errors > s.Requests {
		return ErrErrorsExceed
	}
	if s.Requests != s.Errors+s.Successes {
		return ErrUnbalanced
	}
	if len(s.Slowest) > s.Top || len(s.Busiest) > s.Top {
		return ErrOrder
	}
	for i, e := range s.Slowest {
		if HasCard(strings.Join([]string{e.Method, e.Path, e.AtText}, " ")) {
			return ErrCardLeak
		}
		if i > 0 && !slowerThan(s.Slowest[i-1], e) {
			return ErrOrder
		}
	}
	for i, e := range s.Busiest {
		if HasCard(e.Method + " " + e.Path) {
			return ErrCardLeak
		}
		if i > 0 && !busierThan(s.Busiest[i-1], e) {
			return ErrOrder
		}
	}
	return nil
}

// ErrorRate is errors / requests, 0 when there are no requests.
func (s Summary) ErrorRate() float64 {
	if s.Requests == 0 {
		return 0
	}
	return float64(s.Errors) / float64(s.Requests)
}

// PerMinute is requests divided by the first-to-last span in minutes; 0 when
// the span is zero, which covers a single request.
func (s Summary) PerMinute() float64 {
	span := s.Last.Sub(s.First).Minutes()
	if s.Requests < 2 || span <= 0 {
		return 0
	}
	return float64(s.Requests) / span
}

// roundTo rounds x half away from zero to the given number of decimals.
func roundTo(x float64, decimals int) float64 {
	p := math.Pow(10, float64(decimals))
	return math.Round(x*p) / p
}
