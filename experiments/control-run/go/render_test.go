package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// smallFixture is a summary over a few lines that fill every section.
func smallFixture(t *testing.T) Summary {
	t.Helper()
	tally := mustTally(t, 2, nil)
	for _, line := range []string{
		"2026-09-12T10:00:00Z GET /api/users 200 12",
		"2026-09-12T10:00:30Z POST /api/orders 500 1340",
		"not a line",
		"2026-09-12T10:01:00Z GET /api/users 200 8",
		"2026-09-12T10:02:00Z GET /api/cards/4111111111111111 503 90",
	} {
		tally.addLine(line)
	}
	return mustSummary(t, tally)
}

func textSections(t *testing.T, s Summary) []string {
	t.Helper()
	sections := strings.Split(renderText(s), "\n\n")
	if len(sections) != 3 {
		t.Fatalf("text report has %d sections, want 3:\n%s", len(sections), renderText(s))
	}
	return sections
}

func TestTextCountsSection(t *testing.T) {
	want := "requests     4\n" +
		"errors       2  (50.0%)\n" +
		"malformed    1\n" +
		"per minute 2.0"
	if got := textSections(t, smallFixture(t))[0]; got != want {
		t.Errorf("counts section:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextSlowestSection(t *testing.T) {
	want := "slowest\n" +
		"  1_340 ms  POST /api/orders                 2026-09-12T10:00:30Z\n" +
		"     90 ms  GET /api/cards/****************  2026-09-12T10:02:00Z"
	if got := textSections(t, smallFixture(t))[1]; got != want {
		t.Errorf("slowest section:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextBusiestSection(t *testing.T) {
	want := "busiest\n" +
		"  2  GET /api/users\n" +
		"  1  GET /api/cards/****************\n"
	if got := textSections(t, smallFixture(t))[2]; got != want {
		t.Errorf("busiest section:\n%s\nwant:\n%s", got, want)
	}
}

func TestJSONSummary(t *testing.T) {
	got, err := renderJSON(smallFixture(t))
	if err != nil {
		t.Fatalf("renderJSON: %v", err)
	}
	want := `{"requests": 4, "errors": 2, "error_rate": 0.5, "malformed": 1, "per_minute": 2, ` +
		`"slowest": [{"ms": 1340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:30Z"}, ` +
		`{"ms": 90, "method": "GET", "path": "/api/cards/****************", "at": "2026-09-12T10:02:00Z"}], ` +
		`"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}, ` +
		`{"count": 1, "method": "GET", "path": "/api/cards/****************"}]}` + "\n"
	if got != want {
		t.Errorf("renderJSON:\n%s\nwant:\n%s", got, want)
	}
	if !json.Valid([]byte(got)) {
		t.Errorf("renderJSON is not valid JSON")
	}
}

func TestEmptySummaryRenders(t *testing.T) {
	text := renderText(Summary{})
	want := "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
	if text != want {
		t.Errorf("renderText(empty):\n%q\nwant:\n%q", text, want)
	}
	got, err := renderJSON(Summary{})
	if err != nil {
		t.Fatalf("renderJSON: %v", err)
	}
	if !strings.Contains(got, `"slowest": [], "busiest": []`) || !json.Valid([]byte(got)) {
		t.Errorf("renderJSON(empty) = %s", got)
	}
}

func TestJSONQuotesPaths(t *testing.T) {
	path := `/a"b\c<&>`
	got, err := renderJSON(Summary{Busiest: []Busy{{1, "GET", path}}})
	if err != nil {
		t.Fatalf("renderJSON: %v", err)
	}
	var decoded struct {
		Busiest []struct{ Path string } `json:"busiest"`
	}
	if err := json.Unmarshal([]byte(got), &decoded); err != nil {
		t.Fatalf("unmarshal %s: %v", got, err)
	}
	if len(decoded.Busiest) != 1 || decoded.Busiest[0].Path != path {
		t.Errorf("round trip = %+v", decoded)
	}
}

func TestThousands(t *testing.T) {
	cases := map[uint64]string{
		0: "0", 7: "7", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567",
		18446744073709551615: "18_446_744_073_709_551_615",
	}
	for n, want := range cases {
		if got := thousands(n); got != want {
			t.Errorf("thousands(%d) = %q, want %q", n, got, want)
		}
	}
}

func TestTenths(t *testing.T) {
	cases := map[uint64]string{0: "0.0", 5: "0.5", 401: "40.1", 123456: "12_345.6"}
	for n, want := range cases {
		if got := tenths(n); got != want {
			t.Errorf("tenths(%d) = %q, want %q", n, got, want)
		}
	}
}

func TestFormatAt(t *testing.T) {
	cases := map[string]string{
		"2026-09-12T11:03:30+01:00":      "2026-09-12T10:03:30Z",
		"2026-09-12T10:00:00.250Z":       "2026-09-12T10:00:00.25Z",
		"2026-09-12T10:00:00Z":           "2026-09-12T10:00:00Z",
		"2026-09-12T10:00:00.123456789Z": "2026-09-12T10:00:00.123456789Z",
	}
	for in, want := range cases {
		at, err := time.Parse(time.RFC3339, in)
		if err != nil {
			t.Fatalf("parse %q: %v", in, err)
		}
		if got := formatAt(at); got != want {
			t.Errorf("formatAt(%s) = %q, want %q", in, got, want)
		}
	}
}
