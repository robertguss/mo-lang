package main

import (
	"strings"
	"testing"
)

func smallSummary(t *testing.T) Summary {
	t.Helper()
	return collect(t, 2,
		rec(0, "GET", "/api/users", 200, 12),
		rec(1, "POST", "/api/orders", 500, 340),
		rec(60, "GET", "/api/users", 200, 1204),
	)
}

func text(t *testing.T, s Summary) string {
	t.Helper()
	var b strings.Builder
	if err := WriteText(&b, s); err != nil {
		t.Fatal(err)
	}
	return b.String()
}

func section(t *testing.T, report, header string) string {
	t.Helper()
	_, rest, ok := strings.Cut(report, "\n"+header+"\n")
	if !ok {
		t.Fatalf("no %q section in\n%s", header, report)
	}
	body, _, _ := strings.Cut(rest, "\n\n")
	return body
}

func TestTextCountsSection(t *testing.T) {
	s := smallSummary(t)
	s.Requests, s.Errors, s.Malformed = 1204, 37, 2
	counts, _, _ := strings.Cut(text(t, s), "\n\n")
	want := "requests   1_204\n" +
		"errors        37  (3.1%)\n" +
		"malformed      2\n" +
		"per minute   3.0"
	if counts != want {
		t.Errorf("got\n%s\nwant\n%s", counts, want)
	}
}

func TestTextSlowestSection(t *testing.T) {
	got := section(t, text(t, smallSummary(t)), "slowest")
	want := "  1_204 ms  GET /api/users     2026-09-12T10:01:00Z\n" +
		"    340 ms  POST /api/orders   2026-09-12T10:00:01Z"
	if got != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
}

func TestTextBusiestSection(t *testing.T) {
	got := section(t, text(t, smallSummary(t)), "busiest")
	want := "  2  GET /api/users\n  1  POST /api/orders\n"
	if got != want {
		t.Errorf("got\n%q\nwant\n%q", got, want)
	}
}

func TestTextEmptySummary(t *testing.T) {
	got := text(t, collect(t, 5))
	want := "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
	if got != want {
		t.Errorf("got\n%q\nwant\n%q", got, want)
	}
}

func TestJSON(t *testing.T) {
	var b strings.Builder
	if err := WriteJSON(&b, smallSummary(t)); err != nil {
		t.Fatal(err)
	}
	want := `{"requests": 3, "errors": 1, "error_rate": 0.333, "malformed": 0, "per_minute": 3.0, ` +
		`"slowest": [{"ms": 1204, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:01:00Z"}, ` +
		`{"ms": 340, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:01Z"}], ` +
		`"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}, {"count": 1, "method": "POST", "path": "/api/orders"}]}` + "\n"
	if b.String() != want {
		t.Errorf("got\n%s\nwant\n%s", b.String(), want)
	}
}

func TestJSONEscapesStrings(t *testing.T) {
	if got := jsonString(`/a"b\c<d>`); got != `"/a\"b\\c<d>"` {
		t.Errorf("got %s", got)
	}
}

func TestGrouped(t *testing.T) {
	cases := map[int]string{0: "0", 7: "7", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567", -1204: "-1_204"}
	for n, want := range cases {
		if got := Grouped(n); got != want {
			t.Errorf("Grouped(%d) = %q, want %q", n, got, want)
		}
	}
}

func TestDecimal(t *testing.T) {
	cases := []struct {
		x      float64
		places int
		want   string
	}{
		{0, 1, "0.0"}, {40.1, 1, "40.1"}, {1234.56, 1, "1_234.6"}, {0.0307, 3, "0.031"}, {-1234.5, 0, "-1_234"},
	}
	for _, c := range cases {
		if got := Decimal(c.x, c.places); got != c.want {
			t.Errorf("Decimal(%v, %d) = %q, want %q", c.x, c.places, got, c.want)
		}
	}
}
