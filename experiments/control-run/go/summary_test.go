package main

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"testing"
	"time"
)

var base = time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)

func mustTally(t *testing.T, top int, since *time.Time) *Tally {
	t.Helper()
	tally, err := newTally(top, since)
	if err != nil {
		t.Fatalf("newTally(%d): %v", top, err)
	}
	return tally
}

func mustSummary(t *testing.T, tally *Tally) Summary {
	t.Helper()
	s, err := tally.summary()
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	return s
}

func record(offset time.Duration, method, path string, status int, ms uint32) Record {
	return Record{At: base.Add(offset), Method: method, Path: path, Status: status, Duration: ms}
}

func TestNewTallyRejectsTopOutOfRange(t *testing.T) {
	for _, top := range []int{-1, 0, 101, 1000} {
		if _, err := newTally(top, nil); err == nil {
			t.Errorf("newTally(%d) accepted", top)
		}
	}
	for _, top := range []int{1, 100} {
		if _, err := newTally(top, nil); err != nil {
			t.Errorf("newTally(%d): %v", top, err)
		}
	}
}

func TestTallyCounts(t *testing.T) {
	tally := mustTally(t, 5, nil)
	for _, line := range []string{
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:01Z GET /a 404 1",
		"2026-09-12T10:00:02Z GET /a 500 1",
		"2026-09-12T10:00:03Z GET /a 599 1",
		"2026-09-12T10:00:04Z GET /a 499 1",
		"garbage",
	} {
		tally.addLine(line)
	}
	s := mustSummary(t, tally)
	if s.Requests != 5 || s.Errors != 2 || s.Successes != 3 || s.Malformed != 1 {
		t.Errorf("summary = %+v", s)
	}
}

func TestTallySinceIgnoresEarlierLines(t *testing.T) {
	since := base.Add(time.Minute)
	tally := mustTally(t, 5, &since)
	tally.add(record(59*time.Second, "GET", "/early", 500, 1))
	tally.add(record(time.Minute, "GET", "/at", 200, 1))
	tally.add(record(2*time.Minute, "GET", "/late", 500, 1))
	tally.addLine("garbage")
	s := mustSummary(t, tally)
	if s.Requests != 2 || s.Errors != 1 || s.Malformed != 1 || !s.First.Equal(since) {
		t.Errorf("summary = %+v", s)
	}
}

func slowPaths(list []Slow) []string {
	paths := make([]string, len(list))
	for i, e := range list {
		paths[i] = e.Path
	}
	return paths
}

func TestSlowestOrder(t *testing.T) {
	tally := mustTally(t, 3, nil)
	tally.add(record(3*time.Second, "GET", "/late-tie", 200, 50))
	tally.add(record(0, "GET", "/small", 200, 5))
	tally.add(record(time.Second, "GET", "/early-tie", 200, 50))
	tally.add(record(time.Second, "GET", "/same-instant", 200, 50))
	tally.add(record(2*time.Second, "GET", "/big", 200, 900))
	got := slowPaths(mustSummary(t, tally).Slowest)
	want := []string{"/big", "/early-tie", "/same-instant"}
	if !slices.Equal(got, want) {
		t.Errorf("slowest = %v, want %v", got, want)
	}
}

func TestBusiestOrder(t *testing.T) {
	tally := mustTally(t, 4, nil)
	add := func(n int, method, path string) {
		for range n {
			tally.add(record(0, method, path, 200, 1))
		}
	}
	add(1, "GET", "/z")
	add(3, "POST", "/b")
	add(3, "GET", "/b")
	add(3, "GET", "/a")
	add(5, "GET", "/c")
	add(2, "GET", "/d")
	got := mustSummary(t, tally).Busiest
	want := []Busy{{5, "GET", "/c"}, {3, "GET", "/a"}, {3, "GET", "/b"}, {3, "POST", "/b"}}
	if !slices.Equal(got, want) {
		t.Errorf("busiest = %v, want %v", got, want)
	}
}

func randomRecord(r *rand.Rand) Record {
	return Record{
		At:       base.Add(time.Duration(r.Int64N(int64(time.Hour)))),
		Method:   []string{"GET", "POST", "PUT", "DELETE"}[r.IntN(4)],
		Path:     fmt.Sprintf("/p/%d", r.IntN(20)),
		Status:   minStatus + r.IntN(maxStatus-minStatus+1),
		Duration: uint32(r.IntN(50)),
	}
}

// The bounded insertion must keep exactly what a full sort would keep.
func TestPropertySlowestMatchesFullSort(t *testing.T) {
	for seed := uint64(0); seed < 200; seed++ {
		r := rand.New(rand.NewPCG(seed, 1))
		top := 1 + r.IntN(maxTop)
		tally := mustTally(t, top, nil)
		var all []Slow
		for i := range r.IntN(300) {
			rec := randomRecord(r)
			tally.add(rec)
			all = append(all, Slow{Record: rec, seq: uint64(i + 1)})
		}
		slices.SortFunc(all, compareSlow)
		want := all[:min(top, len(all))]
		got := mustSummary(t, tally).Slowest
		if !slices.EqualFunc(got, want, func(a, b Slow) bool { return a.seq == b.seq }) {
			t.Fatalf("seed %d: slowest differs from a full sort", seed)
		}
	}
}

// The spec's property: errors <= requests for any list of records.
func TestPropertyErrorsNeverExceedRequests(t *testing.T) {
	for seed := uint64(0); seed < 300; seed++ {
		r := rand.New(rand.NewPCG(seed, 2))
		tally := mustTally(t, 1+r.IntN(maxTop), nil)
		n, garbage := r.IntN(500), 0
		for i := range n {
			if r.IntN(10) == 0 {
				tally.addLine(fmt.Sprintf("junk %d", i))
				garbage++
				continue
			}
			tally.add(randomRecord(r))
		}
		s, err := tally.summary()
		if err != nil {
			t.Fatalf("seed %d: %v", seed, err)
		}
		if s.Errors > s.Requests || s.Errors+s.Successes != s.Requests {
			t.Fatalf("seed %d: invariant broken: %+v", seed, s)
		}
		if s.Requests != uint64(n-garbage) || s.Malformed != uint64(garbage) {
			t.Fatalf("seed %d: requests %d malformed %d, want %d %d", seed, s.Requests, s.Malformed, n-garbage, garbage)
		}
	}
}

func TestCheckSummary(t *testing.T) {
	if err := checkSummary(Summary{Requests: 3, Errors: 1, Successes: 2}); err != nil {
		t.Errorf("valid summary rejected: %v", err)
	}
	for _, s := range []Summary{
		{Requests: 1, Errors: 2},
		{Requests: 3, Errors: 1, Successes: 1},
	} {
		if err := checkSummary(s); !errors.Is(err, errInvariant) {
			t.Errorf("checkSummary(%+v) = %v, want errInvariant", s, err)
		}
	}
}

func TestErrorRateThousandths(t *testing.T) {
	cases := []struct{ errs, requests, want uint64 }{
		{0, 0, 0}, {3, 13, 231}, {37, 1204, 31}, {1, 2000, 1}, {1, 3, 333}, {2, 3, 667}, {5, 5, 1000},
	}
	for _, c := range cases {
		if got := errorRateThousandths(c.errs, c.requests); got != c.want {
			t.Errorf("errorRateThousandths(%d, %d) = %d, want %d", c.errs, c.requests, got, c.want)
		}
	}
}

func TestPerMinuteTenths(t *testing.T) {
	cases := []struct {
		requests uint64
		span     time.Duration
		want     uint64
	}{
		{0, 0, 0}, {1, 0, 0}, {1, time.Hour, 0}, {5, 0, 0},
		{13, 10 * time.Minute, 13}, {2, 3 * time.Minute, 7}, {1204, 30 * time.Minute, 401}, {21, 4 * time.Minute, 53},
	}
	for _, c := range cases {
		if got := perMinuteTenths(c.requests, base, base.Add(c.span)); got != c.want {
			t.Errorf("perMinuteTenths(%d, %v) = %d, want %d", c.requests, c.span, got, c.want)
		}
	}
}
