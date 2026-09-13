package main

import (
	"cmp"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"
)

const (
	minTop     = 1
	maxTop     = 100
	defaultTop = 5
)

// Slow is one entry of the slowest list.
type Slow struct {
	Record
	seq uint64 // input order, the last tie-breaker
}

// Busy is one entry of the busiest list.
type Busy struct {
	Count  uint64
	Method string
	Path   string
}

// Summary is everything logstat prints.
type Summary struct {
	Requests  uint64
	Errors    uint64
	Successes uint64
	Malformed uint64
	First     time.Time
	Last      time.Time
	Slowest   []Slow
	Busiest   []Busy
}

type route struct {
	method, path string
}

// Tally accumulates a summary one line at a time, so no file is held in
// memory: only the counts per route and the top slowest records.
type Tally struct {
	top    int
	since  *time.Time
	sum    Summary
	counts map[route]uint64
	seq    uint64
}

// newTally starts an empty tally. A nil since keeps every line.
//
//	requires: top is in 1..100
func newTally(top int, since *time.Time) (*Tally, error) {
	if top < minTop || top > maxTop {
		return nil, fmt.Errorf("top %d outside %d..%d", top, minTop, maxTop)
	}
	return &Tally{top: top, since: since, counts: map[route]uint64{}}, nil
}

// addLine parses one line and adds it, or counts it as malformed.
func (t *Tally) addLine(line string) {
	rec, err := parseLine(line)
	if err != nil {
		t.addMalformed()
		return
	}
	t.add(rec)
}

func (t *Tally) addMalformed() {
	t.sum.Malformed++
}

// add counts one record, unless it is before --since.
func (t *Tally) add(r Record) {
	if t.since != nil && r.At.Before(*t.since) {
		return
	}
	t.seq++
	s := &t.sum
	s.Requests++
	if isError(r.Status) {
		s.Errors++
	} else {
		s.Successes++
	}
	if s.Requests == 1 || r.At.Before(s.First) {
		s.First = r.At
	}
	if s.Requests == 1 || r.At.After(s.Last) {
		s.Last = r.At
	}
	t.counts[route{r.Method, r.Path}]++
	t.insertSlow(Slow{Record: r, seq: t.seq})
}

func isError(status int) bool {
	return status >= 500 && status <= 599
}

// insertSlow keeps sum.Slowest sorted by compareSlow and at most top long.
func (t *Tally) insertSlow(e Slow) {
	list := t.sum.Slowest
	if len(list) == t.top && compareSlow(e, list[len(list)-1]) >= 0 {
		return
	}
	i, _ := slices.BinarySearchFunc(list, e, compareSlow)
	list = slices.Insert(list, i, e)
	if len(list) > t.top {
		list = list[:t.top]
	}
	t.sum.Slowest = list
}

// compareSlow orders by duration descending, then timestamp ascending, then
// input order, so the order is total and deterministic.
func compareSlow(a, b Slow) int {
	return cmp.Or(
		cmp.Compare(b.Duration, a.Duration),
		a.At.Compare(b.At),
		cmp.Compare(a.seq, b.seq),
	)
}

// compareBusy orders by count descending, then path ascending, then method
// ascending, so the order is total and deterministic.
func compareBusy(a, b Busy) int {
	return cmp.Or(
		cmp.Compare(b.Count, a.Count),
		strings.Compare(a.Path, b.Path),
		strings.Compare(a.Method, b.Method),
	)
}

// summary finishes the tally.
//
//	ensures: requests == errors + successes and errors <= requests
func (t *Tally) summary() (Summary, error) {
	s := t.sum
	s.Slowest = slices.Clone(s.Slowest)
	s.Busiest = busiest(t.counts, t.top)
	return s, checkSummary(s)
}

func busiest(counts map[route]uint64, top int) []Busy {
	list := make([]Busy, 0, len(counts))
	for r, n := range counts {
		list = append(list, Busy{Count: n, Method: r.method, Path: r.path})
	}
	slices.SortFunc(list, compareBusy)
	return list[:min(top, len(list))]
}

var errInvariant = errors.New("summary invariant broken")

// checkSummary checks the spec's never: requests equals errors plus
// successes, and errors never exceed requests.
func checkSummary(s Summary) error {
	if s.Errors > s.Requests {
		return fmt.Errorf("%w: errors %d > requests %d", errInvariant, s.Errors, s.Requests)
	}
	if s.Errors+s.Successes != s.Requests {
		return fmt.Errorf("%w: errors %d + successes %d != requests %d", errInvariant, s.Errors, s.Successes, s.Requests)
	}
	return nil
}

// errorRateThousandths is errs/requests in thousandths, rounded half up,
// computed in integers so text and JSON agree. No requests is 0.
func errorRateThousandths(errs, requests uint64) uint64 {
	if requests == 0 {
		return 0
	}
	return (errs*2000 + requests) / (2 * requests)
}

// perMinuteTenths is requests per minute over first..last in tenths,
// rounded half up. A single request, or a zero span, is 0.
func perMinuteTenths(requests uint64, first, last time.Time) uint64 {
	span := last.Sub(first)
	if requests < 2 || span <= 0 {
		return 0
	}
	return uint64(math.Round(float64(requests) * float64(time.Minute) * 10 / float64(span)))
}
