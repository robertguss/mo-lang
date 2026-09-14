package main

import (
	"errors"
	"testing"
)

func TestParseLineAccepts(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatalf("ParseLine: %v", err)
	}
	if r.AtText != "2026-09-12T10:00:02Z" || r.Method != "POST" || r.Path != "/api/orders" || r.Status != 500 || r.Duration != 340 {
		t.Errorf("got %+v", r)
	}
}

func TestParseLineAcceptsBounds(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:02Z GET / 100 0",
		"2026-09-12T10:00:02Z GET / 599 4294967295",
		"2026-09-12T10:00:02Z GET /crlf 200 12\r",
		"2026-09-12T10:00:02+02:00 GET /offset 200 12",
		"2026-09-12T10:00:02.250Z GET /fraction 200 12",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("ParseLine(%q): %v", line, err)
		}
	}
}

// One rejects case per requirement of ParseLine's contract, and per field.
func TestParseLineRejects(t *testing.T) {
	const ts = "2026-09-12T10:00:02Z "
	cases := map[string]string{
		"status below 100":         ts + "GET /x 099 1",
		"status two digits":        ts + "GET /x 99 1",
		"status above 599":         ts + "GET /x 600 1",
		"status 700":               ts + "GET /x 700 1",
		"status not a number":      ts + "GET /x 2x0 1",
		"duration above UInt32":    ts + "GET /x 200 4294967296",
		"duration negative":        ts + "GET /x 200 -1",
		"duration signed":          ts + "GET /x 200 +5",
		"duration not a number":    ts + "GET /x 200 abc",
		"duration fractional":      ts + "GET /x 200 1.5",
		"empty line":               "",
		"prose":                    "this line is not a log line",
		"too few fields":           ts + "GET /x 200",
		"too many fields":          ts + "GET /x 200 1 extra",
		"double space":             ts + "GET  /x 200 1",
		"tab separated":            "2026-09-12T10:00:02Z\tGET /x 200 1",
		"month 13":                 "2026-13-12T10:00:02Z GET /x 200 1",
		"day 31 of September":      "2026-09-31T10:00:02Z GET /x 200 1",
		"date only":                "2026-09-12 GET /x 200 1",
		"lowercase method":         ts + "get /x 200 1",
		"method too long":          ts + "ABCDEFGHIJKLMNOPQ /x 200 1",
		"path without slash":       ts + "GET x 200 1",
		"path with control":        ts + "GET /x\x01 200 1",
		"invalid UTF-8":            ts + "GET /\xff 200 1",
		"trailing space":           ts + "GET /x 200 1 ",
		"card number in duration":  ts + "GET /x 200 4111111111111111",
		"status wider than digits": ts + "GET /x 2000 1",
	}
	for name, line := range cases {
		if _, err := ParseLine(line); !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: ParseLine(%q) error = %v, want ErrMalformed", name, line, err)
		}
	}
}

func TestParseLineMasksCardInPath(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	if err != nil {
		t.Fatalf("ParseLine: %v", err)
	}
	if want := "/api/cards/****************/charge"; r.Path != want {
		t.Errorf("Path = %q, want %q", r.Path, want)
	}
}

func TestParseLineMasksCardInFractionalSeconds(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:09.4111111111111111Z GET /x 200 88")
	if err != nil {
		t.Skipf("time.Parse rejects 16 fraction digits here: %v", err)
	}
	if HasCard(r.AtText) {
		t.Errorf("AtText = %q still holds a card number", r.AtText)
	}
}
