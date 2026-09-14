package main

import (
	"math"
	"sort"
	"time"

	"controlrun/contract"
)

// SlowRow is one of the slowest requests. Seq is the input order, the last tie-break.
type SlowRow struct {
	MS     uint32 `json:"ms"`
	Method string `json:"method"`
	Path   string `json:"path"`
	At     string `json:"at"`
	at     time.Time
	seq    uint64
}

// BusyRow is one of the busiest method and path pairs.
type BusyRow struct {
	Count  uint64 `json:"count"`
	Method string `json:"method"`
	Path   string `json:"path"`
}

// Report is the finished summary, in the JSON key order of the spec.
type Report struct {
	Requests  uint64    `json:"requests"`
	Errors    uint64    `json:"errors"`
	ErrorRate float64   `json:"error_rate"`
	Malformed uint64    `json:"malformed"`
	PerMinute float64   `json:"per_minute"`
	Slowest   []SlowRow `json:"slowest"`
	Busiest   []BusyRow `json:"busiest"`
}

type busyKey struct{ method, path string }

// Summary accumulates records one at a time, holding at most top slow rows
// and one counter per method and path.
type Summary struct {
	top                         int
	requests, errors, successes uint64
	malformed                   uint64
	first, last                 time.Time
	slowest                     []SlowRow
	counts                      map[busyKey]uint64
	seq                         uint64
}

// NewSummary starts an empty summary that keeps top rows per list.
func NewSummary(top int) (*Summary, error) {
	if err := contract.Require(top >= 1 && top <= 100, "top >= 1 && top <= 100"); err != nil {
		return nil, err
	}
	return &Summary{top: top, counts: map[busyKey]uint64{}}, nil
}

// AddMalformed counts one line that did not parse.
func (s *Summary) AddMalformed() { s.malformed++ }

// Add counts one record and checks the summary's invariants after it.
func (s *Summary) Add(r Record) error {
	s.requests++
	if r.Status >= 500 && r.Status <= 599 {
		s.errors++
	} else {
		s.successes++
	}
	if s.requests == 1 || r.At.Before(s.first) {
		s.first = r.At
	}
	if s.requests == 1 || r.At.After(s.last) {
		s.last = r.At
	}
	s.counts[busyKey{r.Method, r.Path}]++
	s.insertSlow(SlowRow{MS: r.MS, Method: r.Method, Path: r.Path, At: r.AtText, at: r.At, seq: s.seq})
	s.seq++
	return s.checkInvariants()
}

func (s *Summary) checkInvariants() error {
	if err := contract.Invariant(s.requests == s.errors+s.successes, "requests == errors + successes"); err != nil {
		return err
	}
	if err := contract.Invariant(s.errors <= s.requests, "errors <= requests"); err != nil {
		return err
	}
	return contract.Invariant(len(s.slowest) <= s.top, "len(slowest) <= top")
}

// slower orders the slowest list: duration descending, then timestamp
// ascending, then input order.
func slower(a, b SlowRow) bool {
	if a.MS != b.MS {
		return a.MS > b.MS
	}
	if !a.at.Equal(b.at) {
		return a.at.Before(b.at)
	}
	return a.seq < b.seq
}

// busier orders the busiest list: count descending, then path ascending,
// then method ascending.
func busier(a, b BusyRow) bool {
	if a.Count != b.Count {
		return a.Count > b.Count
	}
	if a.Path != b.Path {
		return a.Path < b.Path
	}
	return a.Method < b.Method
}

func (s *Summary) insertSlow(row SlowRow) {
	i := sort.Search(len(s.slowest), func(i int) bool { return slower(row, s.slowest[i]) })
	if i >= s.top {
		return
	}
	s.slowest = append(s.slowest, SlowRow{})
	copy(s.slowest[i+1:], s.slowest[i:])
	s.slowest[i] = row
	if len(s.slowest) > s.top {
		s.slowest = s.slowest[:s.top]
	}
}

// sortedBy reports whether no element should come before the one ahead of it.
func sortedBy[T any](xs []T, before func(a, b T) bool) bool {
	for i := 1; i < len(xs); i++ {
		if before(xs[i], xs[i-1]) {
			return false
		}
	}
	return true
}

// PerMinute is requests over the span from first to last timestamp in
// minutes; zero when the span is zero.
func (s *Summary) PerMinute() float64 {
	span := s.last.Sub(s.first).Minutes()
	if s.requests < 2 || span <= 0 {
		return 0
	}
	return float64(s.requests) / span
}

func round(x float64, places int) float64 {
	p := math.Pow(10, float64(places))
	return math.Round(x*p) / p
}

// Report finishes the summary: rates rounded, both lists sorted and checked.
func (s *Summary) Report() (Report, error) {
	busiest := make([]BusyRow, 0, len(s.counts))
	for k, n := range s.counts {
		busiest = append(busiest, BusyRow{Count: n, Method: k.method, Path: k.path})
	}
	sort.Slice(busiest, func(i, j int) bool { return busier(busiest[i], busiest[j]) })
	if len(busiest) > s.top {
		busiest = busiest[:s.top]
	}
	rate := 0.0
	if s.requests > 0 {
		rate = float64(s.errors) / float64(s.requests)
	}
	r := Report{
		Requests: s.requests, Errors: s.errors, ErrorRate: round(rate, 3),
		Malformed: s.malformed, PerMinute: round(s.PerMinute(), 1),
		Slowest: append([]SlowRow{}, s.slowest...), Busiest: busiest,
	}
	return r, ensureReport(r, s.top)
}

func ensureReport(r Report, top int) error {
	checks := []error{
		contract.Ensure(r.Errors <= r.Requests, "errors <= requests"),
		contract.Ensure(len(r.Slowest) <= top && len(r.Busiest) <= top, "len(slowest) <= top && len(busiest) <= top"),
		contract.Ensure(sortedBy(r.Slowest, slower), "slowest sorted by ms desc, at asc"),
		contract.Ensure(sortedBy(r.Busiest, busier), "busiest sorted by count desc, path asc"),
	}
	for _, err := range checks {
		if err != nil {
			return err
		}
	}
	return nil
}
