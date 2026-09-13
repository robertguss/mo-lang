package main

import (
	"errors"
	"testing"
	"time"
)

func TestParseLineAcceptsAWellFormedLine(t *testing.T) {
	rec, err := parseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatalf("parseLine: %v", err)
	}
	at := time.Date(2026, 9, 12, 10, 0, 2, 0, time.UTC)
	if !rec.At.Equal(at) || rec.Method != "POST" || rec.Path != "/api/orders" || rec.Status != 500 || rec.Duration != 340 {
		t.Errorf("parseLine = %+v", rec)
	}
}

func TestParseLineAcceptsTheBounds(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:02Z GET / 100 0",
		"2026-09-12T10:00:02Z GET / 599 4294967295",
		"2026-09-12T10:00:02.25+02:00 PATCH /a 204 007",
	} {
		if _, err := parseLine(line); err != nil {
			t.Errorf("parseLine(%q): %v", line, err)
		}
	}
}

func TestParseLineMasksCardNumbers(t *testing.T) {
	rec, err := parseLine("2026-09-12T10:00:02Z GET /cards/4111111111111111/charge 200 5")
	if err != nil {
		t.Fatalf("parseLine: %v", err)
	}
	if want := "/cards/****************/charge"; rec.Path != want {
		t.Errorf("path = %q, want %q", rec.Path, want)
	}
}

// One group of rejects per requires on parseLine.
func TestParseLineRejects(t *testing.T) {
	const ts = "2026-09-12T10:00:02Z"
	groups := map[string][]string{
		"valid UTF-8": {ts + " GET /a\xff 200 1"},
		"five fields": {
			"", ts + " GET /a 200", ts + " GET /a 200 1 extra",
			ts + "  GET /a 200 1", ts + " GET /a 200 1 ", ts + "\tGET /a 200 1",
		},
		"RFC 3339 timestamp": {
			"2026-09-12 GET /a 200 1", "yesterday GET /a 200 1",
			"2026-09-12T25:00:00Z GET /a 200 1", "2026-09-12T10:00:02 GET /a 200 1",
		},
		"method":   {ts + " get /a 200 1", ts + " G3T /a 200 1", ts + " GÉT /a 200 1"},
		"path":     {ts + " GET api/users 200 1", ts + " GET /a\x01b 200 1", ts + " GET /a\u0085 200 1"},
		"status":   {ts + " GET /a abc 1", ts + " GET /a +200 1", ts + " GET /a 99 1", ts + " GET /a 600 1", ts + " GET /a -500 1", ts + " GET /a 99999999999 1"},
		"duration": {ts + " GET /a 200 abc", ts + " GET /a 200 -1", ts + " GET /a 200 4294967296", ts + " GET /a 200 1.5", ts + " GET /a 200 +1", ts + " GET /a 200 1_000"},
	}
	for requires, lines := range groups {
		for _, line := range lines {
			_, err := parseLine(line)
			var m *MalformedError
			if !errors.As(err, &m) {
				t.Errorf("%s: parseLine(%q) error = %v, want *MalformedError", requires, line, err)
			}
		}
	}
}
