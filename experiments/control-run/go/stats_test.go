package main

import (
	"errors"
	"math/rand/v2"
	"testing"
	"time"
)

func rec(t *testing.T, line string) Record {
	t.Helper()
	r, err := ParseLine(line)
	if err != nil {
		t.Fatalf("%q: %v", line, err)
	}
	return r
}

func summaryOf(t *testing.T, top int, lines ...string) Result {
	t.Helper()
	s, err := NewSummary(top)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range lines {
		if err := s.Add(rec(t, l)); err != nil {
			t.Fatal(err)
		}
	}
	res, err := s.Result()
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func TestNewSummaryRejectsTopOutOfRange(t *testing.T) {
	for _, n := range []int{-1, 0, 101, 1000} {
		if _, err := NewSummary(n); !errors.Is(err, ErrContract) {
			t.Errorf("top %d: want ErrContract, got %v", n, err)
		}
	}
	for _, n := range []int{1, 100} {
		if _, err := NewSummary(n); err != nil {
			t.Errorf("top %d: %v", n, err)
		}
	}
}

func TestAddRejectsRecordsParseCouldNotProduce(t *testing.T) {
	good := Record{Method: "GET", Path: "/x", Status: 200}
	bad := map[string]Record{
		"status 99":  {Method: "GET", Path: "/x", Status: 99},
		"status 600": {Method: "GET", Path: "/x", Status: 600},
		"card":       {Method: "GET", Path: "/1234567890123456", Status: 200},
		"card at":    {Method: "GET", Path: "/x", Status: 200, AtText: "1234567890123456"},
		"method":     {Method: "get", Path: "/x", Status: 200},
		"path":       {Method: "GET", Path: "x", Status: 200},
	}
	s, _ := NewSummary(5)
	for name, r := range bad {
		if err := s.Add(r); !errors.Is(err, ErrContract) {
			t.Errorf("%s: want ErrContract, got %v", name, err)
		}
	}
	if s.requests != 0 {
		t.Fatalf("a refused record changed the summary: %d requests", s.requests)
	}
	if err := s.Add(good); err != nil {
		t.Fatal(err)
	}
}

func TestCheckRejectsBrokenInvariants(t *testing.T) {
	cases := map[string]Summary{
		"sum":            {requests: 3, errors: 1, successes: 1},
		"errors > total": {requests: 1, errors: 2, successes: -1},
	}
	for name, s := range cases {
		if err := s.Check(); !errors.Is(err, ErrContract) {
			t.Errorf("%s: want ErrContract, got %v", name, err)
		}
		if _, err := s.Result(); !errors.Is(err, ErrContract) {
			t.Errorf("%s: Result must refuse, got %v", name, err)
		}
	}
}

func TestCountsAndRates(t *testing.T) {
	res := summaryOf(t, 5,
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 500 1",
		"2026-09-12T10:01:00Z GET /a 599 1",
		"2026-09-12T10:02:00Z GET /a 499 1",
	)
	if res.Requests != 4 || res.Errors != 2 || res.ErrorRate != 0.5 {
		t.Fatalf("got %+v", res)
	}
	if res.PerMinute != 2 {
		t.Fatalf("per minute %v, want 2", res.PerMinute)
	}
}

func TestPerMinuteUsesEarliestAndLatestNotFileOrder(t *testing.T) {
	res := summaryOf(t, 5,
		"2026-09-12T10:01:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:30Z GET /a 200 1",
	)
	if res.PerMinute != 3 {
		t.Fatalf("per minute %v, want 3", res.PerMinute)
	}
}

func TestPerMinuteSingleRequestAndEmpty(t *testing.T) {
	if res := summaryOf(t, 5, "2026-09-12T10:00:00Z GET /a 200 1"); res.PerMinute != 0 {
		t.Fatalf("single request: %v", res.PerMinute)
	}
	if res := summaryOf(t, 5); res.PerMinute != 0 || res.ErrorRate != 0 {
		t.Fatalf("empty: %+v", res)
	}
}

func TestSlowestOrder(t *testing.T) {
	res := summaryOf(t, 3,
		"2026-09-12T10:00:05Z GET /late 300 340",
		"2026-09-12T10:00:01Z GET /small 200 5",
		"2026-09-12T10:00:02Z GET /early 200 340",
		"2026-09-12T10:00:03Z GET /big 200 900",
		"2026-09-12T10:00:02Z GET /early-twin 200 340",
	)
	want := []string{"/big", "/early", "/early-twin"}
	if len(res.Slowest) != len(want) {
		t.Fatalf("got %d rows", len(res.Slowest))
	}
	for i, p := range want {
		if res.Slowest[i].Path != p {
			t.Errorf("row %d: %s, want %s", i, res.Slowest[i].Path, p)
		}
	}
}

func TestBusiestOrder(t *testing.T) {
	res := summaryOf(t, 3,
		"2026-09-12T10:00:00Z GET /b 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z POST /a 200 1",
		"2026-09-12T10:00:00Z GET /a 200 1",
		"2026-09-12T10:00:00Z GET /c 200 1",
		"2026-09-12T10:00:00Z GET /z 200 1",
	)
	want := []PathCount{
		{endpoint{"GET", "/c"}, 2},
		{endpoint{"GET", "/a"}, 1},
		{endpoint{"POST", "/a"}, 1},
	}
	if len(res.Busiest) != len(want) {
		t.Fatalf("got %+v", res.Busiest)
	}
	for i := range want {
		if res.Busiest[i] != want[i] {
			t.Errorf("row %d: %+v, want %+v", i, res.Busiest[i], want[i])
		}
	}
}

// Property: for any list of records, errors <= requests and
// requests = errors + successes, and both lists are ordered and bounded.
func TestPropertyErrorsWithinRequests(t *testing.T) {
	rng := rand.New(rand.NewPCG(4, 2026))
	for trial := 0; trial < 2000; trial++ {
		top := 1 + rng.IntN(maxTop)
		s, _ := NewSummary(top)
		n := rng.IntN(300)
		for i := 0; i < n; i++ {
			_ = s.Add(randomRecord(rng))
		}
		checkProperty(t, s, top)
	}
}

func randomRecord(rng *rand.Rand) Record {
	at := time.Date(2026, 9, 12, 0, 0, 0, 0, time.UTC).Add(time.Duration(rng.IntN(86400)) * time.Second)
	return Record{
		At:     at,
		AtText: at.Format(time.RFC3339),
		Method: []string{"GET", "POST", "PUT"}[rng.IntN(3)],
		Path:   []string{"/a", "/b", "/c", "/d"}[rng.IntN(4)],
		Status: uint16(rng.IntN(700)), // some out of range, which Add refuses
		Ms:     rng.Uint32(),
	}
}

func checkProperty(t *testing.T, s *Summary, top int) {
	t.Helper()
	res, err := s.Result()
	if err != nil {
		t.Fatal(err)
	}
	if res.Errors > res.Requests || res.Requests != s.errors+s.successes {
		t.Fatalf("invariant: %+v", res)
	}
	if len(res.Slowest) > top || len(res.Busiest) > top {
		t.Fatalf("lists exceed top %d", top)
	}
	for i := 1; i < len(res.Slowest); i++ {
		if res.Slowest[i].Ms > res.Slowest[i-1].Ms {
			t.Fatalf("slowest out of order at %d", i)
		}
	}
	for i := 1; i < len(res.Busiest); i++ {
		if busier(res.Busiest[i], res.Busiest[i-1]) {
			t.Fatalf("busiest out of order at %d", i)
		}
	}
}
