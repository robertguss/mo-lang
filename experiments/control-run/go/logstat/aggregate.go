package main

import (
	"errors"
	"math"
	"sort"
	"time"

	"logstat/contract"
)

// PathCount is one row of the busiest list.
type PathCount struct {
	Method string
	Path   string
	Count  int
}

// Summary is what logstat prints, in either format.
type Summary struct {
	Requests  int
	Errors    int
	Successes int
	Malformed int
	ErrorRate float64 // errors / requests, rounded to 3 decimals
	PerMinute float64 // rounded to 1 decimal
	Slowest   []Record
	Busiest   []PathCount
}

type ranked struct {
	rec Record
	seq int
}

type pathKey struct{ method, path string }

// Aggregator folds records one at a time, so no file is held in memory.
type Aggregator struct {
	top       int
	since     time.Time
	hasSince  bool
	requests  int
	errors    int
	successes int
	malformed int
	first     time.Time
	last      time.Time
	seq       int
	slowest   []ranked
	counts    map[pathKey]int
}

// NewAggregator keeps the top slowest requests and busiest paths.
func NewAggregator(top int, since time.Time, hasSince bool) (*Aggregator, error) {
	if err := contract.Require(top >= 1 && top <= 100, "top >= 1 && top <= 100"); err != nil {
		return nil, err
	}
	return &Aggregator{top: top, since: since, hasSince: hasSince, counts: map[pathKey]int{}}, nil
}

// AddLine parses a line and adds it; a malformed line is counted and skipped.
// The only error is a broken contract, which is a bug, not bad input.
func (a *Aggregator) AddLine(line string) error {
	rec, err := ParseLine(line)
	if errors.Is(err, ErrMalformed) {
		a.AddMalformed()
		return nil
	}
	if err != nil {
		return err
	}
	return a.Add(rec)
}

// AddMalformed counts a line that did not parse.
func (a *Aggregator) AddMalformed() { a.malformed++ }

// Add folds one record in, unless it is before --since.
func (a *Aggregator) Add(rec Record) error {
	if err := contract.Require(rec.Status >= 100 && rec.Status <= 599, "rec.Status >= 100 && rec.Status <= 599"); err != nil {
		return err
	}
	if a.hasSince && rec.At.Before(a.since) {
		return nil
	}
	a.requests++
	if rec.Status >= 500 {
		a.errors++
	} else {
		a.successes++
	}
	if a.requests == 1 || rec.At.Before(a.first) {
		a.first = rec.At
	}
	if a.requests == 1 || rec.At.After(a.last) {
		a.last = rec.At
	}
	a.insertSlow(ranked{rec: rec, seq: a.seq})
	a.seq++
	a.counts[pathKey{rec.Method, rec.Path}]++
	return a.checkInvariants()
}

func (a *Aggregator) checkInvariants() error {
	if err := contract.Invariant(a.errors <= a.requests, "errors <= requests"); err != nil {
		return err
	}
	if err := contract.Invariant(a.requests == a.errors+a.successes, "requests == errors + successes"); err != nil {
		return err
	}
	return contract.Invariant(len(a.slowest) <= a.top, "len(slowest) <= top")
}

// slower orders the slowest list: duration descending, then timestamp
// ascending, then input order.
func slower(x, y ranked) bool {
	if x.rec.Duration != y.rec.Duration {
		return x.rec.Duration > y.rec.Duration
	}
	if !x.rec.At.Equal(y.rec.At) {
		return x.rec.At.Before(y.rec.At)
	}
	return x.seq < y.seq
}

func (a *Aggregator) insertSlow(r ranked) {
	i := sort.Search(len(a.slowest), func(i int) bool { return slower(r, a.slowest[i]) })
	if i >= a.top {
		return
	}
	a.slowest = append(a.slowest, ranked{})
	copy(a.slowest[i+1:], a.slowest[i:])
	a.slowest[i] = r
	if len(a.slowest) > a.top {
		a.slowest = a.slowest[:a.top]
	}
}

// Summary returns the report so far.
func (a *Aggregator) Summary() (Summary, error) {
	s := Summary{Requests: a.requests, Errors: a.errors, Successes: a.successes, Malformed: a.malformed}
	if a.requests > 0 {
		s.ErrorRate = math.Round(float64(a.errors)/float64(a.requests)*1000) / 1000
	}
	if span := a.last.Sub(a.first).Minutes(); a.requests > 1 && span > 0 {
		s.PerMinute = math.Round(float64(a.requests)/span*10) / 10
	}
	s.Slowest = make([]Record, 0, len(a.slowest))
	for _, r := range a.slowest {
		s.Slowest = append(s.Slowest, r.rec)
	}
	s.Busiest = busiest(a.counts, a.top)
	if err := contract.Ensure(s.Requests == s.Errors+s.Successes && s.Errors <= s.Requests, "requests == errors + successes && errors <= requests"); err != nil {
		return Summary{}, err
	}
	return s, nil
}

// busiest sorts by count descending, then path ascending, then method.
func busiest(counts map[pathKey]int, top int) []PathCount {
	rows := make([]PathCount, 0, len(counts))
	for k, n := range counts {
		rows = append(rows, PathCount{Method: k.method, Path: k.path, Count: n})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].Count != rows[j].Count {
			return rows[i].Count > rows[j].Count
		}
		if rows[i].Path != rows[j].Path {
			return rows[i].Path < rows[j].Path
		}
		return rows[i].Method < rows[j].Method
	})
	if len(rows) > top {
		rows = rows[:top]
	}
	return rows
}
