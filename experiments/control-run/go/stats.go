package main

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"
)

const (
	defaultTop = 5
	minTop     = 1
	maxTop     = 100
)

// ErrContract is wrapped by every broken requirement or invariant.
var ErrContract = errors.New("contract broken")

func broken(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrContract, fmt.Sprintf(format, args...))
}

// Summary accumulates records one at a time so no file is held in memory.
// It keeps only the top-N slowest and one counter per method and path.
type Summary struct {
	top       int
	requests  int
	errors    int
	successes int
	malformed int
	first     time.Time
	last      time.Time
	seq       int
	slowest   []ranked
	counts    map[endpoint]int
}

type ranked struct {
	Record
	seq int
}

type endpoint struct {
	Method string
	Path   string
}

// PathCount is one row of the busiest list.
type PathCount struct {
	endpoint
	Count int
}

// Result is the finished summary, ready to render.
type Result struct {
	Requests  int
	Errors    int
	Malformed int
	ErrorRate float64
	PerMinute float64
	Slowest   []Record
	Busiest   []PathCount
}

// NewSummary requires top in 1..100: out of range is an error, not a clamp.
func NewSummary(top int) (*Summary, error) {
	if err := CheckTop(top); err != nil {
		return nil, err
	}
	return &Summary{top: top, counts: map[endpoint]int{}}, nil
}

// CheckTop requires n in 1..100.
func CheckTop(n int) error {
	if n < minTop || n > maxTop {
		return broken("top %d outside %d..%d", n, minTop, maxTop)
	}
	return nil
}

// AddMalformed counts one line that did not parse.
func (s *Summary) AddMalformed() { s.malformed++ }

// Add requires a record ParseLine could have produced; it refuses any
// other without changing the summary.
func (s *Summary) Add(r Record) error {
	if err := checkRecord(r); err != nil {
		return err
	}
	s.count(r)
	s.span(r.At)
	s.rankSlow(ranked{Record: r, seq: s.seq})
	s.seq++
	return nil
}

func checkRecord(r Record) error {
	switch {
	case r.Status < 100 || r.Status > 599:
		return broken("status %d outside 100..599", r.Status)
	case ContainsCard(r.Path) || ContainsCard(r.AtText):
		return broken("record holds an unmasked card number")
	case checkMethod(r.Method) != nil || checkPath(r.Path) != nil:
		return broken("record method or path not well formed")
	}
	return nil
}

func (s *Summary) count(r Record) {
	s.requests++
	if r.Status >= 500 {
		s.errors++
	} else {
		s.successes++
	}
	s.counts[endpoint{r.Method, r.Path}]++
}

func (s *Summary) span(at time.Time) {
	if s.requests == 1 || at.Before(s.first) {
		s.first = at
	}
	if s.requests == 1 || at.After(s.last) {
		s.last = at
	}
}

// slower orders the slowest list: duration descending, then timestamp
// ascending, then arrival order, so ties are stable and deterministic.
func slower(a, b ranked) bool {
	if a.Ms != b.Ms {
		return a.Ms > b.Ms
	}
	if !a.At.Equal(b.At) {
		return a.At.Before(b.At)
	}
	return a.seq < b.seq
}

func (s *Summary) rankSlow(r ranked) {
	i := sort.Search(len(s.slowest), func(i int) bool { return slower(r, s.slowest[i]) })
	if i >= s.top {
		return
	}
	s.slowest = append(s.slowest, ranked{})
	copy(s.slowest[i+1:], s.slowest[i:])
	s.slowest[i] = r
	if len(s.slowest) > s.top {
		s.slowest = s.slowest[:s.top]
	}
}

// Check holds the summary's nevers: requests = errors + successes and
// errors <= requests.
func (s *Summary) Check() error {
	if s.requests != s.errors+s.successes {
		return broken("requests %d != errors %d + successes %d", s.requests, s.errors, s.successes)
	}
	if s.errors > s.requests || s.errors < 0 {
		return broken("errors %d not within requests %d", s.errors, s.requests)
	}
	return nil
}

// Result finishes the summary, checking its invariants first.
func (s *Summary) Result() (Result, error) {
	if err := s.Check(); err != nil {
		return Result{}, err
	}
	return Result{
		Requests:  s.requests,
		Errors:    s.errors,
		Malformed: s.malformed,
		ErrorRate: ratio(s.errors, s.requests),
		PerMinute: s.perMinute(),
		Slowest:   s.slowRecords(),
		Busiest:   s.busiest(),
	}, nil
}

func ratio(part, whole int) float64 {
	if whole == 0 {
		return 0
	}
	return float64(part) / float64(whole)
}

// perMinute is requests over the span between the earliest and latest
// timestamp; a zero span (one request, or all at one instant) is 0.
func (s *Summary) perMinute() float64 {
	minutes := s.last.Sub(s.first).Minutes()
	if s.requests == 0 || minutes <= 0 {
		return 0
	}
	return float64(s.requests) / minutes
}

func (s *Summary) slowRecords() []Record {
	out := make([]Record, 0, len(s.slowest))
	for _, r := range s.slowest {
		out = append(out, r.Record)
	}
	return out
}

// busiest sorts by count descending, then path ascending, then method
// ascending, and keeps the top N.
func (s *Summary) busiest() []PathCount {
	rows := make([]PathCount, 0, len(s.counts))
	for e, n := range s.counts {
		rows = append(rows, PathCount{endpoint: e, Count: n})
	}
	sort.Slice(rows, func(i, j int) bool { return busier(rows[i], rows[j]) })
	if len(rows) > s.top {
		rows = rows[:s.top]
	}
	return rows
}

func busier(a, b PathCount) bool {
	if a.Count != b.Count {
		return a.Count > b.Count
	}
	if c := strings.Compare(a.Path, b.Path); c != 0 {
		return c < 0
	}
	return a.Method < b.Method
}
