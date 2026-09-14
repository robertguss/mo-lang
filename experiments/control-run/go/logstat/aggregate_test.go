package main

import (
	"math/rand"
	"strings"
	"testing"
	"time"
)

func mustRecord(t *testing.T, line string) Record {
	t.Helper()
	rec, err := ParseLine(line)
	if err != nil {
		t.Fatalf("%q: %v", line, err)
	}
	return rec
}

func summarize(t *testing.T, top int, lines ...string) Summary {
	t.Helper()
	agg, err := NewAggregator(top, time.Time{}, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range lines {
		if err := agg.AddLine(l); err != nil {
			t.Fatal(err)
		}
	}
	s, err := agg.Summary()
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// rejects: NewAggregator's requires on top.
func TestNewAggregatorRejectsTopOutOfRange(t *testing.T) {
	for _, top := range []int{-1, 0, 101, 1000} {
		if _, err := NewAggregator(top, time.Time{}, false); err == nil || !strings.Contains(err.Error(), "requires failed: top >= 1 && top <= 100") {
			t.Errorf("top %d: got %v", top, err)
		}
	}
	for _, top := range []int{1, 100} {
		if _, err := NewAggregator(top, time.Time{}, false); err != nil {
			t.Errorf("top %d: %v", top, err)
		}
	}
}

// rejects: Add's requires on status.
func TestAddRejectsStatusOutOfRange(t *testing.T) {
	agg, err := NewAggregator(5, time.Time{}, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, status := range []int{0, 99, 600} {
		if err := agg.Add(Record{Status: status}); err == nil || !strings.Contains(err.Error(), "requires failed: rec.Status") {
			t.Errorf("status %d: got %v", status, err)
		}
	}
}

func TestCounts(t *testing.T) {
	s := summarize(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 404 1",
		"2026-09-12T10:01:00Z GET /a 500 1",
		"2026-09-12T10:02:00Z GET /a 599 1",
		"garbage",
		"",
	)
	if s.Requests != 4 || s.Errors != 2 || s.Successes != 2 || s.Malformed != 2 {
		t.Errorf("got %+v", s)
	}
	if s.ErrorRate != 0.5 || s.PerMinute != 2.0 {
		t.Errorf("rate %v per minute %v", s.ErrorRate, s.PerMinute)
	}
}

func TestPerMinuteSingleRequestAndNone(t *testing.T) {
	if s := summarize(t, 5, "2026-09-12T10:00:00Z GET /a 200 1"); s.PerMinute != 0 {
		t.Errorf("single request: %v", s.PerMinute)
	}
	if s := summarize(t, 5, "2026-09-12T10:00:00Z GET /a 200 1", "2026-09-12T10:00:00Z GET /a 200 1"); s.PerMinute != 0 {
		t.Errorf("zero span: %v", s.PerMinute)
	}
	if s := summarize(t, 5); s.PerMinute != 0 || s.ErrorRate != 0 || s.Requests != 0 {
		t.Errorf("empty: %+v", s)
	}
}

func TestPerMinuteUsesEarliestAndLatestOutOfOrder(t *testing.T) {
	s := summarize(t, 5,
		"2026-09-12T10:01:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:02:00Z GET /a 200 1",
	)
	if s.PerMinute != 1.5 {
		t.Errorf("got %v", s.PerMinute)
	}
}

func TestSince(t *testing.T) {
	since := mustRecord(t, "2026-09-12T10:01:00Z GET /a 200 1").At
	agg, err := NewAggregator(5, since, true)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range []string{
		"2026-09-12T10:00:59Z GET /a 500 1",
		"2026-09-12T10:01:00Z GET /b 200 2",
		"2026-09-12T10:02:00Z GET /c 200 3",
		"not a line",
	} {
		if err := agg.AddLine(l); err != nil {
			t.Fatal(err)
		}
	}
	s, err := agg.Summary()
	if err != nil {
		t.Fatal(err)
	}
	if s.Requests != 2 || s.Errors != 0 || s.Malformed != 1 || len(s.Busiest) != 2 {
		t.Errorf("got %+v", s)
	}
}

func TestSlowestOrder(t *testing.T) {
	s := summarize(t, 4,
		"2026-09-12T10:00:03Z GET /c 200 340",
		"2026-09-12T10:00:01Z GET /a 200 12",
		"2026-09-12T10:00:02Z GET /b 200 340",
		"2026-09-12T10:00:05Z GET /d 200 1204",
		"2026-09-12T10:00:02Z GET /e 200 340",
		"2026-09-12T10:00:00Z GET /f 200 1",
	)
	var got []string
	for _, r := range s.Slowest {
		got = append(got, r.Path)
	}
	if strings.Join(got, " ") != "/d /b /e /c" {
		t.Errorf("slowest %v", got)
	}
}

func TestBusiestOrder(t *testing.T) {
	s := summarize(t, 3,
		"2026-09-12T10:00:00Z GET /z 200 1",
		"2026-09-12T10:00:00Z GET /z 200 1",
		"2026-09-12T10:00:00Z POST /b 200 1",
		"2026-09-12T10:00:00Z GET /b 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
	)
	var got []string
	for _, p := range s.Busiest {
		got = append(got, p.Method+p.Path)
	}
	if strings.Join(got, " ") != "GET/z GET/a GET/b" {
		t.Errorf("busiest %v", got)
	}
}

// property: for any list of records, errors <= requests and
// requests == errors + successes.
func TestPropertyErrorsAtMostRequests(t *testing.T) {
	rng := rand.New(rand.NewSource(20260912))
	methods := []string{"GET", "POST", "PUT", "DELETE"}
	for trial := 0; trial < 500; trial++ {
		agg, err := NewAggregator(1+rng.Intn(100), time.Time{}, false)
		if err != nil {
			t.Fatal(err)
		}
		n := rng.Intn(200)
		base := time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)
		for i := 0; i < n; i++ {
			rec := Record{
				At:       base.Add(time.Duration(rng.Intn(3600)) * time.Second),
				Method:   methods[rng.Intn(len(methods))],
				Path:     "/p" + string(rune('a'+rng.Intn(5))),
				Status:   100 + rng.Intn(500),
				Duration: rng.Uint32(),
			}
			rec.AtText = rec.At.Format(time.RFC3339)
			if err := agg.Add(rec); err != nil {
				t.Fatalf("trial %d: %v", trial, err)
			}
		}
		s, err := agg.Summary()
		if err != nil {
			t.Fatalf("trial %d: %v", trial, err)
		}
		if s.Errors > s.Requests || s.Requests != s.Errors+s.Successes || s.Requests != n {
			t.Fatalf("trial %d: %+v", trial, s)
		}
	}
}
