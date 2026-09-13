package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func sampleSummary(t *testing.T) Summary {
	t.Helper()
	lines := []string{
		"2026-09-12T10:00:00Z GET /api/users 200 12",
		"2026-09-12T10:00:30Z POST /orders 500 1340",
		"bad line",
		"2026-09-12T10:01:00Z GET /cards/4111111111111111 200 12",
	}
	for i := 0; i < 1201; i++ {
		lines = append(lines, "2026-09-12T10:00:10Z GET /api/users 200 1")
	}
	return mustAcc(t, 2, lines...)
}

// section returns the lines of the text report between heading and the next blank line.
func section(report, heading string) string {
	_, rest, _ := strings.Cut(report, heading+"\n")
	body, _, _ := strings.Cut(rest, "\n\n")
	return body
}

func TestGroup(t *testing.T) {
	cases := map[uint64]string{0: "0", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567"}
	for n, want := range cases {
		if got := GroupUint(n); got != want {
			t.Errorf("GroupUint(%d) = %q, want %q", n, got, want)
		}
	}
	if got := OneDecimal(12345.67); got != "12_345.7" {
		t.Errorf("OneDecimal = %q", got)
	}
}

func TestTextTotalsSection(t *testing.T) {
	report := RenderText(sampleSummary(t))
	totals, _, _ := strings.Cut(report, "\n\n")
	want := "requests     1_204\n" +
		"errors           1  (0.1%)\n" +
		"malformed        1\n" +
		"per minute 1_204.0"
	if totals != want {
		t.Errorf("totals:\n%s\nwant:\n%s", totals, want)
	}
}

func TestTextSlowestSection(t *testing.T) {
	got := section(RenderText(sampleSummary(t)), "slowest")
	want := "  1_340 ms  POST /orders     2026-09-12T10:00:30Z\n" +
		"     12 ms  GET /api/users   2026-09-12T10:00:00Z"
	if got != want {
		t.Errorf("slowest:\n%s\nwant:\n%s", got, want)
	}
}

func TestTextBusiestSection(t *testing.T) {
	got := section(RenderText(sampleSummary(t)), "busiest")
	want := "  1_202  GET /api/users\n" +
		"      1  GET /cards/****************\n"
	if got != want {
		t.Errorf("busiest:\n%q\nwant:\n%q", got, want)
	}
}

func TestTextNoRequests(t *testing.T) {
	want := "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
	if got := RenderText(mustAcc(t, 5)); got != want {
		t.Errorf("got %q", got)
	}
}

func TestJSONSections(t *testing.T) {
	out, err := RenderJSON(sampleSummary(t))
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Requests  uint64  `json:"requests"`
		Errors    uint64  `json:"errors"`
		ErrorRate float64 `json:"error_rate"`
		Malformed uint64  `json:"malformed"`
		PerMinute float64 `json:"per_minute"`
		Slowest   []struct {
			Ms               uint32
			Method, Path, At string
		} `json:"slowest"`
		Busiest []struct {
			Count        uint64
			Method, Path string
		} `json:"busiest"`
	}
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatalf("%v in %s", err, out)
	}
	if got.Requests != 1204 || got.Errors != 1 || got.ErrorRate != 0.001 || got.Malformed != 1 || got.PerMinute != 1204 {
		t.Errorf("totals: %+v", got)
	}
	if len(got.Slowest) != 2 || got.Slowest[0].Ms != 1340 || got.Slowest[0].At != "2026-09-12T10:00:30Z" {
		t.Errorf("slowest: %+v", got.Slowest)
	}
	if len(got.Busiest) != 2 || got.Busiest[1].Path != "/cards/****************" || got.Busiest[0].Count != 1202 {
		t.Errorf("busiest: %+v", got.Busiest)
	}
	if !strings.HasPrefix(out, `{"requests": 1204, "errors": 1, "error_rate": 0.001, "malformed": 1, "per_minute": 1204.0, "slowest": [`) {
		t.Errorf("layout: %s", out)
	}
}

func TestJSONEscapesStrings(t *testing.T) {
	s := mustAcc(t, 5, `2026-09-12T10:00:00Z GET /a"b\<c> 200 1`)
	out, err := RenderJSON(s)
	if err != nil {
		t.Fatal(err)
	}
	if !json.Valid([]byte(out)) || !strings.Contains(out, `"/a\"b\\<c>"`) {
		t.Errorf("got %s", out)
	}
}
