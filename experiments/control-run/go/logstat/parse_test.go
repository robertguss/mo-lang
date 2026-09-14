package main

import (
	"errors"
	"strings"
	"testing"
)

func TestParseLineWellFormed(t *testing.T) {
	rec, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatal(err)
	}
	if rec.AtText != "2026-09-12T10:00:02Z" || rec.Method != "POST" || rec.Path != "/api/orders" || rec.Status != 500 || rec.Duration != 340 {
		t.Errorf("got %+v", rec)
	}
	if rec.At.Minute() != 0 || rec.At.Second() != 2 {
		t.Errorf("timestamp parsed as %v", rec.At)
	}
}

func TestParseLineAcceptsCRLFAndEdges(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:01:00Z GET /api/users 200 13\r",
		"2026-09-12T10:01:00Z GET / 100 0",
		"2026-09-12T10:01:00+02:00 GET /x 599 4294967295",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("%q: %v", line, err)
		}
	}
}

func TestParseLineMalformed(t *testing.T) {
	for _, line := range []string{
		"",
		"this line is not a log line",
		"2026-13-12T10:01:45Z GET /api/users 200 7",
		"2026-09-12T10:03:01Z PUT /api/users/7 200 abc",
		"2026-09-12T10:00:01Z GET /api/users 200",
		"2026-09-12T10:00:01Z GET /api/users 200 12 extra",
		"2026-09-12T10:00:01Z  GET /api/users 200 12",
		"2026-09-12T10:00:01Z\tGET /api/users 200 12",
		"2026-09-12T10:00:01Z get /api/users 200 12",
		"2026-09-12T10:00:01Z GET api/users 200 12",
		"2026-09-12T10:00:01Z GET /api/users 20 12",
		"2026-09-12T10:00:01Z GET /api/users +200 12",
		"2026-09-12T10:00:01Z GET /api/users 200 -1",
		"2026-09-12T10:00:01.1234567890123456Z GET /api/users 200 12",
		"2026-09-12T10:00:01Z GET /api/\x01users 200 12",
		"2026-09-12T10:00:01Z GET /api/\xffusers 200 12",
	} {
		if _, err := ParseLine(line); !errors.Is(err, ErrMalformed) {
			t.Errorf("%q: got %v, want malformed", line, err)
		}
	}
}

// rejects: the status requires.
func TestParseLineRejectsStatusOutOfRange(t *testing.T) {
	for _, status := range []string{"000", "099", "600", "700", "999"} {
		_, err := ParseLine("2026-09-12T10:00:01Z GET /x " + status + " 1")
		if !errors.Is(err, ErrMalformed) || !strings.Contains(err.Error(), "requires failed: status >= 100 && status <= 599") {
			t.Errorf("status %s: got %v", status, err)
		}
	}
}

// rejects: the duration_ms requires.
func TestParseLineRejectsDurationOverUInt32(t *testing.T) {
	for _, d := range []string{"4294967296", "99999999999"} {
		_, err := ParseLine("2026-09-12T10:00:01Z GET /x 200 " + d)
		if !errors.Is(err, ErrMalformed) || !strings.Contains(err.Error(), "requires failed: duration_ms <= math.MaxUint32") {
			t.Errorf("duration %s: got %v", d, err)
		}
	}
}

// ensures: no card number survives parsing.
func TestParseLineMasksCardNumber(t *testing.T) {
	rec, err := ParseLine("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	if err != nil {
		t.Fatal(err)
	}
	if rec.Path != "/api/cards/****************/charge" {
		t.Errorf("path %q", rec.Path)
	}
}

func TestMaskCards(t *testing.T) {
	cases := map[string]string{
		"/a/4111111111111111":                   "/a/****************",
		"/a/411111111111111":                    "/a/411111111111111",
		"/4111111111111111/b/12345678901234567": "/****************/b/*****************",
		"4111111111111111x":                     "****************x",
		"/orders/17":                            "/orders/17",
		"":                                      "",
	}
	for in, want := range cases {
		if got := MaskCards(in); got != want {
			t.Errorf("MaskCards(%q) = %q, want %q", in, got, want)
		}
		if HasCardNumber(MaskCards(in)) {
			t.Errorf("MaskCards(%q) still has a card number", in)
		}
	}
}
