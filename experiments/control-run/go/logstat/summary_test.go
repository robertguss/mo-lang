package main

import (
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"testing"
	"time"

	"controlrun/contract"
)

func mustRecord(t *testing.T, line string) Record {
	t.Helper()
	r, err := ParseLine(line)
	if err != nil {
		t.Fatalf("ParseLine(%q): %v", line, err)
	}
	return r
}

func mustSummary(t *testing.T, top int, lines ...string) *Summary {
	t.Helper()
	s, err := NewSummary(top)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range lines {
		if err := s.Add(mustRecord(t, l)); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func wantViolation(t *testing.T, err error, kind string) {
	t.Helper()
	var v *contract.Violation
	if !errors.As(err, &v) || v.Kind != kind {
		t.Errorf("err = %v, want a %s violation", err, kind)
	}
}

func TestNewSummaryRejectsTopOutOfRange(t *testing.T) {
	for _, top := range []int{-1, 0, 101} {
		_, err := NewSummary(top)
		wantViolation(t, err, "requires")
	}
	for _, top := range []int{1, 100} {
		if _, err := NewSummary(top); err != nil {
			t.Errorf("NewSummary(%d) = %v", top, err)
		}
	}
}

func TestSummaryCounts(t *testing.T) {
	s := mustSummary(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 404 1",
		"2026-09-12T10:01:00Z GET /a 500 1",
	)
	s.AddMalformed()
	r, err := s.Report()
	if err != nil {
		t.Fatal(err)
	}
	if r.Requests != 3 || r.Errors != 1 || r.Malformed != 1 || r.ErrorRate != 0.333 || r.PerMinute != 3 {
		t.Errorf("report = %+v", r)
	}
}

func TestPerMinute(t *testing.T) {
	cases := []struct {
		lines []string
		want  float64
	}{
		{nil, 0},
		{[]string{"2026-09-12T10:00:00Z GET /a 200 1"}, 0},
		{[]string{"2026-09-12T10:00:00Z GET /a 200 1", "2026-09-12T10:00:00Z GET /a 200 1"}, 0},
		{[]string{"2026-09-12T10:02:00Z GET /a 200 1", "2026-09-12T10:00:00Z GET /a 200 1", "2026-09-12T10:01:00Z GET /a 200 1"}, 1.5},
	}
	for _, c := range cases {
		if got := mustSummary(t, 5, c.lines...).PerMinute(); got != c.want {
			t.Errorf("PerMinute(%v) = %v, want %v", c.lines, got, c.want)
		}
	}
}

func TestSlowestOrderAndTop(t *testing.T) {
	s := mustSummary(t, 3,
		"2026-09-12T10:00:05Z GET /late 200 50",
		"2026-09-12T10:00:01Z GET /fast 200 1",
		"2026-09-12T10:00:03Z GET /early 200 50",
		"2026-09-12T10:00:03Z GET /same-time-second 200 50",
		"2026-09-12T10:00:09Z GET /slowest 200 900",
	)
	r, err := s.Report()
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, row := range r.Slowest {
		got = append(got, row.Path)
	}
	if want := "[/slowest /early /same-time-second]"; fmt.Sprint(got) != want {
		t.Errorf("slowest = %v, want %v", got, want)
	}
}

func TestBusiestOrderAndTop(t *testing.T) {
	s := mustSummary(t, 3,
		"2026-09-12T10:00:00Z GET /b 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z POST /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z GET /d 200 1",
	)
	r, err := s.Report()
	if err != nil {
		t.Fatal(err)
	}
	want := []BusyRow{{2, "GET", "/c"}, {1, "GET", "/a"}, {1, "POST", "/a"}}
	if fmt.Sprint(r.Busiest) != fmt.Sprint(want) {
		t.Errorf("busiest = %v, want %v", r.Busiest, want)
	}
}

// Property: for any list of records, errors <= requests and
// requests == errors + successes, checked after every Add and in the report.
func TestPropertyErrorsNeverExceedRequests(t *testing.T) {
	rng := rand.New(rand.NewPCG(7, 11))
	base := time.Date(2026, 9, 12, 0, 0, 0, 0, time.UTC)
	for range 300 {
		s, err := NewSummary(1 + rng.IntN(100))
		if err != nil {
			t.Fatal(err)
		}
		var fives, others uint64
		for range rng.IntN(500) {
			status := 100 + rng.IntN(500)
			if status >= 500 {
				fives++
			} else {
				others++
			}
			r := Record{
				At: base.Add(time.Duration(rng.IntN(86400)) * time.Second), Method: "GET",
				Path: fmt.Sprintf("/p%d", rng.IntN(20)), Status: status, MS: rng.Uint32(),
			}
			if err := s.Add(r); err != nil {
				t.Fatal(err)
			}
		}
		rep, err := s.Report()
		if err != nil {
			t.Fatal(err)
		}
		if rep.Errors > rep.Requests || rep.Requests != fives+others || rep.Errors != fives {
			t.Fatalf("report %+v, want errors %d of %d", rep, fives, fives+others)
		}
	}
}

func TestInvariantsReportViolations(t *testing.T) {
	s := mustSummary(t, 2)
	s.requests, s.errors, s.successes = 5, 6, 0
	wantViolation(t, s.checkInvariants(), "invariant")

	s.requests, s.errors, s.successes = 1, math.MaxUint64, 2 // sums to 1 by wrapping
	err := s.checkInvariants()
	wantViolation(t, err, "invariant")
	if err != nil && err.Error() != "invariant failed: errors <= requests" {
		t.Errorf("err = %v", err)
	}

	s.requests, s.errors, s.successes = 0, 0, 0
	s.slowest = make([]SlowRow, 3)
	wantViolation(t, s.checkInvariants(), "invariant")
}

func TestEnsureReportRejects(t *testing.T) {
	ok := Report{Requests: 2, Errors: 1}
	if err := ensureReport(ok, 5); err != nil {
		t.Fatal(err)
	}
	bad := []Report{
		{Requests: 1, Errors: 2},
		{Busiest: []BusyRow{{1, "GET", "/a"}, {1, "GET", "/b"}}},
		{Slowest: []SlowRow{{MS: 1}, {MS: 2}}},
		{Busiest: []BusyRow{{1, "GET", "/b"}, {2, "GET", "/a"}}},
		{Busiest: []BusyRow{{1, "GET", "/b"}, {1, "GET", "/a"}}},
	}
	tops := []int{5, 1, 5, 5, 5}
	for i, r := range bad {
		wantViolation(t, ensureReport(r, tops[i]), "ensures")
	}
}
