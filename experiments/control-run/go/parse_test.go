package main

import (
	"errors"
	"testing"
)

func TestParseLineAcceptsSpecExample(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatal(err)
	}
	if r.AtText != "2026-09-12T10:00:02Z" || r.Method != "POST" || r.Path != "/api/orders" || r.Status != 500 || r.Duration != 340 {
		t.Fatalf("got %+v", r)
	}
}

func TestParseLineAcceptsBounds(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:01Z GET / 100 0",
		"2026-09-12T10:00:01Z GET / 599 4294967295",
		"2026-09-12T10:00:01.250+02:00 GET /x 200 1",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("%q: %v", line, err)
		}
	}
}

// One rejects case per requirement of ParseLine.
func TestParseLineRejects(t *testing.T) {
	cases := map[string]string{
		"not UTF-8":            "2026-09-12T10:00:01Z GET /\xff 200 1",
		"too few fields":       "2026-09-12T10:00:01Z GET /x 200",
		"too many fields":      "2026-09-12T10:00:01Z GET /x 200 1 extra",
		"double space":         "2026-09-12T10:00:01Z  GET /x 200 1",
		"empty line":           "",
		"bad month":            "2026-13-12T10:00:01Z GET /x 200 1",
		"no zone":              "2026-09-12T10:00:01 GET /x 200 1",
		"lower-case method":    "2026-09-12T10:00:01Z get /x 200 1",
		"path without slash":   "2026-09-12T10:00:01Z GET x 200 1",
		"status not digits":    "2026-09-12T10:00:01Z GET /x 2x0 1",
		"status four digits":   "2026-09-12T10:00:01Z GET /x 0200 1",
		"status below 100":     "2026-09-12T10:00:01Z GET /x 099 1",
		"status above 599":     "2026-09-12T10:00:01Z GET /x 600 1",
		"duration not digits":  "2026-09-12T10:00:01Z GET /x 200 abc",
		"duration negative":    "2026-09-12T10:00:01Z GET /x 200 -1",
		"duration over uint32": "2026-09-12T10:00:01Z GET /x 200 4294967296",
	}
	for name, line := range cases {
		if _, err := ParseLine(line); !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: want ErrMalformed, got %v", name, err)
		}
	}
}
