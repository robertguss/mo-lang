package main

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"testing"
	"time"
)

var t0 = time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)

func rec(sec int, method, path string, status int, ms uint32) Record {
	at := t0.Add(time.Duration(sec) * time.Second)
	return Record{At: at, Stamp: at.Format(time.RFC3339), Method: method, Path: path, Status: status, Duration: ms}
}

func collect(t *testing.T, top int, recs ...Record) Summary {
	t.Helper()
	c, err := NewCollector(top, time.Time{}, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range recs {
		c.Add(r)
	}
	s, err := c.Summary()
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestNewCollectorRejectsTop(t *testing.T) {
	for _, top := range []int{0, -1, 101} {
		if _, err := NewCollector(top, time.Time{}, false); err == nil {
			t.Errorf("NewCollector(%d) accepted", top)
		}
	}
}

func TestCollectorCounts(t *testing.T) {
	c, _ := NewCollector(5, time.Time{}, false)
	c.AddLine("2026-09-12T10:00:01Z GET /a 200 12")
	c.AddLine("2026-09-12T10:00:02Z POST /b 500 340")
	c.AddLine("2026-09-12T10:00:03Z POST /b 599 1")
	c.AddLine("2026-09-12T10:00:04Z GET /a 404 1")
	c.AddLine("garbage")
	c.AddMalformed()
	s, err := c.Summary()
	if err != nil {
		t.Fatal(err)
	}
	if s.Requests != 4 || s.Errors != 2 || s.Malformed != 2 {
		t.Errorf("got requests %d errors %d malformed %d", s.Requests, s.Errors, s.Malformed)
	}
}

func TestCollectorSince(t *testing.T) {
	c, _ := NewCollector(5, t0.Add(10*time.Second), true)
	c.Add(rec(9, "GET", "/a", 500, 1))
	c.Add(rec(10, "GET", "/a", 200, 1)) // at --since exactly: kept
	c.Add(rec(11, "GET", "/a", 200, 1))
	c.AddLine("2026-09-12T10:00:01Z GET /a 999 1") // malformed counts even before --since
	s, _ := c.Summary()
	if s.Requests != 2 || s.Errors != 0 || s.Malformed != 1 {
		t.Errorf("got %+v", s)
	}
}

func TestPerMinute(t *testing.T) {
	cases := []struct {
		n           int
		first, last time.Time
		want        float64
	}{
		{0, time.Time{}, time.Time{}, 0},
		{1, t0, t0, 0},
		{3, t0, t0, 0},
		{3, t0, t0.Add(time.Minute), 3},
		{16, t0, t0.Add(210 * time.Second), 16 / 3.5},
	}
	for _, c := range cases {
		if got := PerMinute(c.n, c.first, c.last); got != c.want {
			t.Errorf("PerMinute(%d, span %v) = %v, want %v", c.n, c.last.Sub(c.first), got, c.want)
		}
	}
}

func TestPerMinuteUsesEarliestAndLatestNotInputOrder(t *testing.T) {
	s := collect(t, 5, rec(60, "GET", "/a", 200, 1), rec(0, "GET", "/a", 200, 1), rec(30, "GET", "/a", 200, 1))
	if s.PerMinute != 3 {
		t.Errorf("per minute %v", s.PerMinute)
	}
}

func TestSlowestOrder(t *testing.T) {
	s := collect(t, 3,
		rec(5, "GET", "/late-tie", 200, 340),
		rec(1, "GET", "/fast", 200, 1),
		rec(2, "GET", "/early-tie", 200, 340),
		rec(3, "GET", "/slowest", 200, 1204),
		rec(2, "PUT", "/same-instant-later-input", 200, 340),
	)
	var got []string
	for _, r := range s.Slowest {
		got = append(got, fmt.Sprintf("%d %s", r.Duration, r.Path))
	}
	want := []string{"1204 /slowest", "340 /early-tie", "340 /same-instant-later-input"}
	if !slices.Equal(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestBusiestOrder(t *testing.T) {
	s := collect(t, 4,
		rec(0, "GET", "/b", 200, 1),
		rec(0, "POST", "/c", 200, 1),
		rec(0, "GET", "/c", 200, 1),
		rec(0, "GET", "/a", 200, 1),
		rec(0, "GET", "/z", 200, 1), rec(0, "GET", "/z", 200, 1), rec(0, "GET", "/z", 200, 1),
	)
	want := []PathCount{{3, "GET", "/z"}, {1, "GET", "/a"}, {1, "GET", "/b"}, {1, "GET", "/c"}}
	if !slices.Equal(s.Busiest, want) {
		t.Errorf("got %v, want %v", s.Busiest, want)
	}
}

func TestCheckSummaryRejects(t *testing.T) {
	for _, s := range []Summary{
		{Requests: 1, Errors: 2},
		{Requests: -1},
		{Errors: -1},
		{Malformed: -1},
	} {
		if err := CheckSummary(s); !errors.Is(err, ErrInvariant) {
			t.Errorf("CheckSummary(%+v) = %v, want ErrInvariant", s, err)
		}
	}
}

func randomRecords(r *rand.Rand) []Record {
	recs := make([]Record, r.IntN(200))
	methods := []string{"GET", "POST", "PUT"}
	for i := range recs {
		recs[i] = rec(r.IntN(3600), methods[r.IntN(3)], fmt.Sprintf("/p%d", r.IntN(10)), 100+r.IntN(500), uint32(r.IntN(50)))
	}
	return recs
}

// Property: for any list of records, errors <= requests and requests ==
// errors + successes.
func TestPropertyErrorsAtMostRequests(t *testing.T) {
	r := rand.New(rand.NewPCG(1, 2))
	for range 500 {
		recs := randomRecords(r)
		s := collect(t, 1+r.IntN(100), recs...)
		successes := 0
		for _, rec := range recs {
			if !IsError(rec.Status) {
				successes++
			}
		}
		if s.Errors > s.Requests || s.Requests != s.Errors+successes {
			t.Fatalf("requests %d errors %d successes %d", s.Requests, s.Errors, successes)
		}
	}
}

// Property: the bounded slowest list equals a full stable sort cut to top.
func TestPropertySlowestMatchesFullSort(t *testing.T) {
	r := rand.New(rand.NewPCG(3, 4))
	for range 500 {
		recs := randomRecords(r)
		top := 1 + r.IntN(100)
		s := collect(t, top, recs...)
		want := slices.Clone(recs)
		slices.SortStableFunc(want, func(a, b Record) int {
			return compareSlowest(ranked{rec: a}, ranked{rec: b})
		})
		want = want[:min(top, len(want))]
		if !slices.Equal(s.Slowest, want) {
			t.Fatalf("top %d: got %v, want %v", top, s.Slowest, want)
		}
	}
}
