package main

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"testing"
	"time"
)

func mustAcc(t *testing.T, top int, lines ...string) Summary {
	t.Helper()
	acc, err := NewAccumulator(top, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range lines {
		acc.AddLine(l)
	}
	s, err := acc.Summary()
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestNewAccumulatorRejectsTopOutOfRange(t *testing.T) {
	for _, top := range []int{-1, 0, 101} {
		if _, err := NewAccumulator(top, nil); !errors.Is(err, ErrTop) {
			t.Errorf("top %d: want ErrTop, got %v", top, err)
		}
	}
	for _, top := range []int{1, 100} {
		if _, err := NewAccumulator(top, nil); err != nil {
			t.Errorf("top %d: %v", top, err)
		}
	}
}

func TestTotals(t *testing.T) {
	s := mustAcc(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 500 1",
		"garbage",
		"2026-09-12T10:01:00Z GET /a 404 1",
	)
	if s.Requests != 3 || s.Errors != 1 || s.Successes != 2 || s.Malformed != 1 {
		t.Fatalf("got %+v", s)
	}
	if s.PerMinute() != 3 {
		t.Errorf("per minute %v, want 3", s.PerMinute())
	}
}

func TestPerMinuteZeroForSingleRequestAndZeroSpan(t *testing.T) {
	one := mustAcc(t, 5, "2026-09-12T10:00:00Z GET /a 200 1")
	same := mustAcc(t, 5, "2026-09-12T10:00:00Z GET /a 200 1", "2026-09-12T10:00:00Z GET /b 200 1")
	none := mustAcc(t, 5)
	for _, s := range []Summary{one, same, none} {
		if s.PerMinute() != 0 {
			t.Errorf("got per minute %v for %+v", s.PerMinute(), s)
		}
	}
	if none.ErrorRate() != 0 {
		t.Errorf("error rate with no requests: %v", none.ErrorRate())
	}
}

func TestPerMinuteUsesEarliestAndLatestNotFileOrder(t *testing.T) {
	s := mustAcc(t, 5, "2026-09-12T10:02:00Z GET /a 200 1", "2026-09-12T10:00:00Z GET /a 200 1")
	if s.PerMinute() != 1 {
		t.Errorf("per minute %v, want 1", s.PerMinute())
	}
}

func TestSince(t *testing.T) {
	since := time.Date(2026, 9, 12, 10, 0, 30, 0, time.UTC)
	acc, err := NewAccumulator(5, &since)
	if err != nil {
		t.Fatal(err)
	}
	acc.AddLine("2026-09-12T10:00:29Z GET /a 500 1")
	acc.AddLine("2026-09-12T10:00:30Z GET /a 200 1")
	acc.AddLine("junk")
	s, err := acc.Summary()
	if err != nil {
		t.Fatal(err)
	}
	if s.Requests != 1 || s.Errors != 0 || s.Malformed != 1 {
		t.Errorf("got %+v", s)
	}
}

func TestSlowestOrderDurationDescThenTimestampAsc(t *testing.T) {
	s := mustAcc(t, 3,
		"2026-09-12T10:00:05Z GET /late 300 50",
		"2026-09-12T10:00:01Z GET /early 200 50",
		"2026-09-12T10:00:09Z GET /fast 200 1",
		"2026-09-12T10:00:09Z GET /slow 200 90",
		"2026-09-12T10:00:03Z GET /mid 200 50",
	)
	want := []string{"/slow", "/early", "/mid"}
	if len(s.Slowest) != 3 {
		t.Fatalf("got %d entries", len(s.Slowest))
	}
	for i, p := range want {
		if s.Slowest[i].Path != p {
			t.Errorf("slowest[%d] = %s, want %s", i, s.Slowest[i].Path, p)
		}
	}
}

func TestBusiestOrderCountDescThenPathAsc(t *testing.T) {
	s := mustAcc(t, 3,
		"2026-09-12T10:00:00Z GET /z 200 1",
		"2026-09-12T10:00:00Z GET /z 200 1",
		"2026-09-12T10:00:00Z GET /b 200 1",
		"2026-09-12T10:00:00Z POST /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
	)
	want := []Busy{{2, "GET", "/z"}, {1, "GET", "/a"}, {1, "POST", "/a"}}
	if fmt.Sprint(s.Busiest) != fmt.Sprint(want) {
		t.Errorf("got %v, want %v", s.Busiest, want)
	}
}

func TestBusiestGroupsMaskedPaths(t *testing.T) {
	s := mustAcc(t, 5,
		"2026-09-12T10:00:00Z GET /c/4111111111111111 200 1",
		"2026-09-12T10:00:00Z GET /c/5500000000000004 200 1",
	)
	if len(s.Busiest) != 1 || s.Busiest[0].Count != 2 || s.Busiest[0].Path != "/c/****************" {
		t.Errorf("got %v", s.Busiest)
	}
}

func TestCheckRejectsBrokenSummaries(t *testing.T) {
	slow := func(ms uint32, path string) Slow {
		return Slow{Duration: ms, Method: "GET", Path: path, Seq: uint64(ms)}
	}
	cases := []struct {
		name string
		s    Summary
		want error
	}{
		{"errors > requests", Summary{Top: 5, Requests: 1, Errors: 2}, ErrErrorsExceed},
		{"unbalanced", Summary{Top: 5, Requests: 3, Errors: 1, Successes: 1}, ErrUnbalanced},
		{"card in busiest", Summary{Top: 5, Busiest: []Busy{{1, "GET", "/c/4111111111111111"}}}, ErrCardLeak},
		{"card in slowest", Summary{Top: 5, Slowest: []Slow{slow(1, "/4111111111111111")}}, ErrCardLeak},
		{"slowest unordered", Summary{Top: 5, Slowest: []Slow{slow(1, "/a"), slow(9, "/b")}}, ErrOrder},
		{"busiest unordered", Summary{Top: 5, Busiest: []Busy{{1, "GET", "/b"}, {1, "GET", "/a"}}}, ErrOrder},
		{"longer than top", Summary{Top: 1, Busiest: []Busy{{2, "GET", "/a"}, {1, "GET", "/b"}}}, ErrOrder},
	}
	for _, c := range cases {
		if err := c.s.Check(); !errors.Is(err, c.want) {
			t.Errorf("%s: want %v, got %v", c.name, c.want, err)
		}
	}
}

// Property: for any generated list of records, errors <= requests and
// requests == errors + successes, and Summary's own check passes.
func TestPropertyErrorsNeverExceedRequests(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	base := time.Date(2026, 9, 12, 0, 0, 0, 0, time.UTC)
	for trial := 0; trial < 500; trial++ {
		acc, err := NewAccumulator(1+rng.IntN(100), nil)
		if err != nil {
			t.Fatal(err)
		}
		n := rng.IntN(200)
		for i := 0; i < n; i++ {
			acc.Add(Record{
				At:       base.Add(time.Duration(rng.IntN(86400)) * time.Second),
				Method:   []string{"GET", "POST", "PUT"}[rng.IntN(3)],
				Path:     fmt.Sprintf("/p/%d", rng.IntN(20)),
				Status:   uint16(100 + rng.IntN(500)),
				Duration: rng.Uint32(),
			})
		}
		s, err := acc.Summary()
		if err != nil {
			t.Fatalf("trial %d: %v", trial, err)
		}
		if s.Errors > s.Requests || s.Requests != s.Errors+s.Successes || s.Requests != uint64(n) {
			t.Fatalf("trial %d: %+v", trial, s)
		}
	}
}
