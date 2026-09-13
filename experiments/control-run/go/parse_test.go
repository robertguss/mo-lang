package main

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestParseLineAcceptsSpecExample(t *testing.T) {
	rec, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatalf("ParseLine: %v", err)
	}
	want := Record{
		At:       time.Date(2026, 9, 12, 10, 0, 2, 0, time.UTC),
		Stamp:    "2026-09-12T10:00:02Z",
		Method:   "POST",
		Path:     "/api/orders",
		Status:   500,
		Duration: 340,
	}
	if rec != want {
		t.Errorf("got %+v, want %+v", rec, want)
	}
}

func TestParseLineAcceptsBoundaries(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:02Z GET / 100 0",
		"2026-09-12T10:00:02Z GET / 599 4294967295",
		"2026-09-12T10:00:02.250+02:00 GET /a 200 1",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("ParseLine(%q): %v", line, err)
		}
	}
}

// One case per requires of ParseLine.
func TestParseLineRejects(t *testing.T) {
	cases := map[string]string{
		"not UTF-8":                "2026-09-12T10:00:02Z GET /\xff 200 1",
		"too few fields":           "2026-09-12T10:00:02Z GET /a 200",
		"too many fields":          "2026-09-12T10:00:02Z GET /a 200 1 x",
		"double space":             "2026-09-12T10:00:02Z  GET /a 200 1",
		"empty line":               "",
		"bad timestamp":            "2026-13-12T10:00:02Z GET /a 200 1",
		"timestamp without zone":   "2026-09-12T10:00:02 GET /a 200 1",
		"empty method":             "2026-09-12T10:00:02Z  /a 200 1",
		"lowercase method":         "2026-09-12T10:00:02Z get /a 200 1",
		"path without slash":       "2026-09-12T10:00:02Z GET api 200 1",
		"path with control":        "2026-09-12T10:00:02Z GET /a\x1b[2J 200 1",
		"status not digits":        "2026-09-12T10:00:02Z GET /a 2x0 1",
		"status with sign":         "2026-09-12T10:00:02Z GET /a +200 1",
		"status below 100":         "2026-09-12T10:00:02Z GET /a 99 1",
		"status above 599":         "2026-09-12T10:00:02Z GET /a 700 1",
		"duration not digits":      "2026-09-12T10:00:02Z GET /a 200 abc",
		"duration negative":        "2026-09-12T10:00:02Z GET /a 200 -1",
		"duration overflows u32":   "2026-09-12T10:00:02Z GET /a 200 4294967296",
		"duration with carriage r": "2026-09-12T10:00:02Z GET /a 200 1\r",
	}
	for name, line := range cases {
		_, err := ParseLine(line)
		if !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: ParseLine(%q) err = %v, want ErrMalformed", name, line, err)
		}
	}
}

func TestParseLineRedactsCardInPath(t *testing.T) {
	rec, err := ParseLine("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	if err != nil {
		t.Fatal(err)
	}
	if rec.Path != "/api/cards/****************/charge" {
		t.Errorf("path %q", rec.Path)
	}
}

func TestRedact(t *testing.T) {
	cases := map[string]string{
		"/a/4111111111111111":               "/a/****************",
		"/a/411111111111111":                "/a/411111111111111", // 15 digits is not a card
		"/a/41111111111111112":              "/a/*****************",
		"4111111111111111x5500000000000004": "****************x****************",
		"/orders/17":                        "/orders/17",
		"":                                  "",
	}
	for in, want := range cases {
		if got := Redact(in); got != want {
			t.Errorf("Redact(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestIsError(t *testing.T) {
	for status, want := range map[int]bool{100: false, 404: false, 499: false, 500: true, 503: true, 599: true} {
		if IsError(status) != want {
			t.Errorf("IsError(%d) != %v", status, want)
		}
	}
}

// FuzzParseLine: no input panics, and every accepted record keeps the
// contract. `go test` runs the seeds; `go test -fuzz` explores further.
func FuzzParseLine(f *testing.F) {
	f.Add("2026-09-12T10:00:02Z POST /api/orders 500 340")
	f.Add("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	f.Add("this line is not a log line")
	f.Fuzz(func(t *testing.T, line string) {
		rec, err := ParseLine(line)
		if err != nil {
			return
		}
		if rec.Status < 100 || rec.Status > 599 {
			t.Errorf("status %d accepted", rec.Status)
		}
		if strings.Contains(rec.Path, "0000000000000000") || Redact(rec.Path) != rec.Path {
			t.Errorf("unredacted path %q", rec.Path)
		}
	})
}
