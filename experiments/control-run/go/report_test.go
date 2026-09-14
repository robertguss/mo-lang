package main

import (
	"strings"
	"testing"
)

// small is the summary every section test renders.
func small(t *testing.T) Summary {
	t.Helper()
	return accumulate(t, 5,
		"2026-09-12T10:00:00Z GET /api/users 200 12",
		"2026-09-12T10:00:30Z POST /api/orders 500 1204",
		"2026-09-12T10:01:00Z GET /api/users 200 340",
		"2026-09-12T10:02:00Z GET /api/cards/4111111111111111/charge 200 88",
		"broken",
	)
}

func section(t *testing.T, text, name string) string {
	t.Helper()
	parts := strings.Split(text, "\n\n")
	if len(parts) != 3 {
		t.Fatalf("want 3 blank-line separated sections, got %d:\n%s", len(parts), text)
	}
	return map[string]string{"totals": parts[0], "slowest": parts[1], "busiest": parts[2]}[name]
}

func TestTextTotals(t *testing.T) {
	want := "requests   4\n" +
		"errors     1  (25.0%)\n" +
		"malformed  1\n" +
		"per minute 2.0"
	if got := section(t, RenderText(small(t)), "totals"); got != want {
		t.Errorf("totals:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextTotalsSpecExample(t *testing.T) {
	s := Summary{Requests: 1204, Errors: 37, Successes: 1167, Malformed: 2, PerMinute: 40.1}
	want := "requests   1_204\n" +
		"errors        37  (3.1%)\n" +
		"malformed      2\n" +
		"per minute   40.1"
	if got := section(t, RenderText(s), "totals"); got != want {
		t.Errorf("totals:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextSlowest(t *testing.T) {
	want := "slowest\n" +
		"  1_204 ms  POST /api/orders                         2026-09-12T10:00:30Z\n" +
		"    340 ms  GET /api/users                           2026-09-12T10:01:00Z\n" +
		"     88 ms  GET /api/cards/****************/charge   2026-09-12T10:02:00Z\n" +
		"     12 ms  GET /api/users                           2026-09-12T10:00:00Z"
	if got := section(t, RenderText(small(t)), "slowest"); got != want {
		t.Errorf("slowest:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextBusiest(t *testing.T) {
	want := "busiest\n" +
		"  2  GET /api/users\n" +
		"  1  GET /api/cards/****************/charge\n" +
		"  1  POST /api/orders\n"
	if got := section(t, RenderText(small(t)), "busiest"); got != want {
		t.Errorf("busiest:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextEmptySummary(t *testing.T) {
	want := "requests   0\nerrors     0  (0.0%)\nmalformed  0\nper minute 0.0\n\nslowest\n\nbusiest\n"
	if got := RenderText(Summary{}); got != want {
		t.Errorf("empty:\n%q\nwant:\n%q", got, want)
	}
}

func TestJSONTotals(t *testing.T) {
	want := `{"requests": 4, "errors": 1, "error_rate": 0.250, "malformed": 1, "per_minute": 2.0, "slowest": [`
	if got := RenderJSON(small(t)); !strings.HasPrefix(got, want) {
		t.Errorf("json:\n%s\nwant prefix:\n%s", got, want)
	}
}

func TestJSONSlowest(t *testing.T) {
	want := `"slowest": [{"ms": 1204, "method": "POST", "path": "/api/orders", "at": "2026-09-12T10:00:30Z"}, ` +
		`{"ms": 340, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:01:00Z"}, ` +
		`{"ms": 88, "method": "GET", "path": "/api/cards/****************/charge", "at": "2026-09-12T10:02:00Z"}, ` +
		`{"ms": 12, "method": "GET", "path": "/api/users", "at": "2026-09-12T10:00:00Z"}], `
	if got := RenderJSON(small(t)); !strings.Contains(got, want) {
		t.Errorf("json:\n%s\nwant to contain:\n%s", got, want)
	}
}

func TestJSONBusiest(t *testing.T) {
	want := `"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}, ` +
		`{"count": 1, "method": "GET", "path": "/api/cards/****************/charge"}, ` +
		`{"count": 1, "method": "POST", "path": "/api/orders"}]}` + "\n"
	if got := RenderJSON(small(t)); !strings.HasSuffix(got, want) {
		t.Errorf("json:\n%s\nwant suffix:\n%s", got, want)
	}
}

func TestJSONString(t *testing.T) {
	cases := map[string]string{
		`/a`:     `"/a"`,
		`/"q"`:   `"/\"q\""`,
		`/back\`: `"/back\\"`,
		"/\x01":  `"/\u0001"`,
		"/ü":     `"/ü"`,
	}
	for in, want := range cases {
		if got := jsonString(in); got != want {
			t.Errorf("jsonString(%q) = %s, want %s", in, got, want)
		}
	}
}

func TestGroup(t *testing.T) {
	cases := map[uint64]string{0: "0", 12: "12", 999: "999", 1000: "1_000", 1204: "1_204", 4294967295: "4_294_967_295"}
	for n, want := range cases {
		if got := group(n); got != want {
			t.Errorf("group(%d) = %s, want %s", n, got, want)
		}
	}
	if whole, frac := splitDecimal("12045.5"); whole != "12_045" || frac != ".5" {
		t.Errorf("splitDecimal = %s %s", whole, frac)
	}
}
