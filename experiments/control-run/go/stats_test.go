package main

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"testing"
	"time"
)

func accumulate(t *testing.T, top int, lines ...string) Summary {
	t.Helper()
	acc := NewAccumulator(top, time.Time{}, false)
	for _, l := range lines {
		acc.AddLine(l)
	}
	s, err := acc.Summary()
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	return s
}

func TestSummaryCounts(t *testing.T) {
	s := accumulate(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 500 1",
		"2026-09-12T10:01:00Z GET /a 599 1",
		"2026-09-12T10:01:30Z GET /a 499 1",
		"garbage",
	)
	if s.Requests != 4 || s.Errors != 2 || s.Successes != 2 || s.Malformed != 1 {
		t.Errorf("counts = %+v", s)
	}
	if s.ErrorRate != 0.5 {
		t.Errorf("ErrorRate = %v, want 0.5", s.ErrorRate)
	}
	if s.PerMinute != 4.0/1.5 {
		t.Errorf("PerMinute = %v, want %v", s.PerMinute, 4.0/1.5)
	}
}

func TestPerMinuteUsesEarliestAndLatestNotFileOrder(t *testing.T) {
	s := accumulate(t, 5,
		"2026-09-12T10:02:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:01:00Z GET /a 200 1",
	)
	if s.PerMinute != 1.5 {
		t.Errorf("PerMinute = %v, want 1.5", s.PerMinute)
	}
}

func TestPerMinuteZeroCases(t *testing.T) {
	if s := accumulate(t, 5); s.PerMinute != 0 || s.ErrorRate != 0 {
		t.Errorf("empty: %+v", s)
	}
	if s := accumulate(t, 5, "2026-09-12T10:00:00Z GET /a 200 1"); s.PerMinute != 0 {
		t.Errorf("single request PerMinute = %v", s.PerMinute)
	}
	same := "2026-09-12T10:00:00Z GET /a 200 1"
	if s := accumulate(t, 5, same, same); s.PerMinute != 0 {
		t.Errorf("one instant PerMinute = %v", s.PerMinute)
	}
}

func TestSinceIgnoresEarlierLines(t *testing.T) {
	since := time.Date(2026, 9, 12, 10, 1, 0, 0, time.UTC)
	acc := NewAccumulator(5, since, true)
	acc.AddLine("2026-09-12T10:00:59Z GET /early 500 1")
	acc.AddLine("2026-09-12T10:01:00Z GET /edge 200 1")
	acc.AddLine("2026-09-12T10:02:00Z GET /late 200 1")
	acc.AddLine("not a line")
	s, err := acc.Summary()
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	if s.Requests != 2 || s.Errors != 0 || s.Malformed != 1 {
		t.Errorf("counts = %+v", s)
	}
	for _, b := range s.Busiest {
		if b.Path == "/early" {
			t.Error("line before --since reached busiest")
		}
	}
}

func TestSlowestOrder(t *testing.T) {
	s := accumulate(t, 4,
		"2026-09-12T10:00:05Z GET /tie-late 200 340",
		"2026-09-12T10:00:01Z GET /fast 200 1",
		"2026-09-12T10:00:02Z GET /slowest 200 1204",
		"2026-09-12T10:00:03Z GET /tie-early 200 340",
		"2026-09-12T10:00:03Z GET /tie-early-second 200 340",
		"2026-09-12T10:00:04Z GET /mid 200 610",
	)
	want := []string{"/slowest", "/mid", "/tie-early", "/tie-early-second"}
	if len(s.Slowest) != len(want) {
		t.Fatalf("len = %d, want %d", len(s.Slowest), len(want))
	}
	for i, w := range want {
		if s.Slowest[i].Path != w {
			t.Errorf("slowest[%d] = %s, want %s", i, s.Slowest[i].Path, w)
		}
	}
}

func TestBusiestOrder(t *testing.T) {
	s := accumulate(t, 3,
		"2026-09-12T10:00:00Z GET /b 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z POST /a 200 1",
		"2026-09-12T10:00:00Z GET /z 200 1",
	)
	want := []Busy{{2, "GET", "/c"}, {1, "GET", "/a"}, {1, "POST", "/a"}}
	if fmt.Sprint(s.Busiest) != fmt.Sprint(want) {
		t.Errorf("busiest = %v, want %v", s.Busiest, want)
	}
}

// One rejects case per clause of Summary.Check.
func TestCheckRejects(t *testing.T) {
	good := accumulate(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 9",
		"2026-09-12T10:00:01Z GET /b 500 1",
		"2026-09-12T10:00:01Z GET /b 200 1",
	)
	if err := good.Check(); err != nil {
		t.Fatalf("good summary: %v", err)
	}
	cases := map[string]func(s *Summary){
		"errors above requests":           func(s *Summary) { s.Errors = s.Requests + 1 },
		"requests not errors + successes": func(s *Summary) { s.Successes++ },
		"slowest out of order":            func(s *Summary) { s.Slowest[0], s.Slowest[1] = s.Slowest[1], s.Slowest[0] },
		"busiest out of order":            func(s *Summary) { s.Busiest[0], s.Busiest[1] = s.Busiest[1], s.Busiest[0] },
		"card in slowest path":            func(s *Summary) { s.Slowest[0].Path = "/4111111111111111" },
		"card in slowest timestamp":       func(s *Summary) { s.Slowest[0].At = "4111111111111111" },
		"card in busiest path":            func(s *Summary) { s.Busiest[0].Path = "/4111111111111111" },
	}
	for name, corrupt := range cases {
		s := good
		s.Slowest = append([]Slow(nil), good.Slowest...)
		s.Busiest = append([]Busy(nil), good.Busiest...)
		corrupt(&s)
		if err := s.Check(); !errors.Is(err, ErrContract) {
			t.Errorf("%s: Check() = %v, want ErrContract", name, err)
		}
	}
}

// Property: for any list of lines, errors <= requests, requests = errors +
// successes, every line is either a request or malformed, and lists respect top.
func TestPropertyErrorsNeverExceedRequests(t *testing.T) {
	rng := rand.New(rand.NewPCG(2026, 9))
	methods := []string{"GET", "POST", "PUT", "DELETE", "get"}
	paths := []string{"/", "/a", "/b", "/a/4111111111111111", "x"}
	base := time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)
	for trial := range 500 {
		top := minTop + rng.IntN(maxTop)
		acc := NewAccumulator(top, time.Time{}, false)
		n := rng.IntN(300)
		for range n {
			at := base.Add(time.Duration(rng.IntN(7200)) * time.Second).Format(time.RFC3339)
			acc.AddLine(fmt.Sprintf("%s %s %s %d %d", at, methods[rng.IntN(len(methods))],
				paths[rng.IntN(len(paths))], rng.IntN(1000), rng.Uint64N(1<<33)))
		}
		s, err := acc.Summary()
		if err != nil {
			t.Fatalf("trial %d: %v", trial, err)
		}
		switch {
		case s.Errors > s.Requests:
			t.Fatalf("trial %d: errors %d > requests %d", trial, s.Errors, s.Requests)
		case s.Requests != s.Errors+s.Successes:
			t.Fatalf("trial %d: requests %d != %d + %d", trial, s.Requests, s.Errors, s.Successes)
		case s.Requests+s.Malformed != uint64(n):
			t.Fatalf("trial %d: %d requests + %d malformed != %d lines", trial, s.Requests, s.Malformed, n)
		case len(s.Slowest) > top || len(s.Busiest) > top:
			t.Fatalf("trial %d: lists longer than top %d", trial, top)
		}
	}
}
