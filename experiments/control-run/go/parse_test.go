package main

import (
	"errors"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestParseLineAcceptsTheSpecExample(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatal(err)
	}
	if r.Method != "POST" || r.Path != "/api/orders" || r.Status != 500 || r.Ms != 340 {
		t.Fatalf("got %+v", r)
	}
	if r.AtText != "2026-09-12T10:00:02Z" || r.At.Second() != 2 {
		t.Fatalf("timestamp: %+v", r)
	}
}

func TestParseLineAcceptsBounds(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:02Z GET / 100 0",
		"2026-09-12T10:00:02Z GET / 599 4294967295",
		"2026-09-12T10:00:02+02:00 GET /x 200 1",
		"2026-09-12T10:00:02.5Z GET /x 200 1",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("%q: %v", line, err)
		}
	}
}

// One rejects test per requirement of ParseLine.
func TestParseLineRejects(t *testing.T) {
	cases := map[string]string{
		"not utf-8":           "2026-09-12T10:00:02Z GET /\xff 200 1",
		"empty line":          "",
		"four fields":         "2026-09-12T10:00:02Z GET /x 200",
		"six fields":          "2026-09-12T10:00:02Z GET /x 200 1 extra",
		"double space":        "2026-09-12T10:00:02Z  GET /x 200 1",
		"tab separator":       "2026-09-12T10:00:02Z\tGET /x 200 1",
		"bad month":           "2026-13-12T10:00:02Z GET /x 200 1",
		"no zone":             "2026-09-12T10:00:02 GET /x 200 1",
		"status 99":           "2026-09-12T10:00:02Z GET /x 099 1",
		"status 600":          "2026-09-12T10:00:02Z GET /x 600 1",
		"status 700":          "2026-09-12T10:00:02Z GET /x 700 1",
		"status four digits":  "2026-09-12T10:00:02Z GET /x 2000 1",
		"status signed":       "2026-09-12T10:00:02Z GET /x +20 1",
		"duration over u32":   "2026-09-12T10:00:02Z GET /x 200 4294967296",
		"duration negative":   "2026-09-12T10:00:02Z GET /x 200 -1",
		"duration not number": "2026-09-12T10:00:02Z GET /x 200 abc",
		"duration empty":      "2026-09-12T10:00:02Z GET /x 200 ",
		"method lower":        "2026-09-12T10:00:02Z get /x 200 1",
		"method empty":        "2026-09-12T10:00:02Z  /x 200 1",
		"path relative":       "2026-09-12T10:00:02Z GET x 200 1",
		"path control":        "2026-09-12T10:00:02Z GET /a\x01 200 1",
	}
	for name, line := range cases {
		if _, err := ParseLine(line); !errors.Is(err, ErrMalformed) {
			t.Errorf("%s: want ErrMalformed, got %v", name, err)
		}
	}
}

func TestParseLineMasksCardInPath(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	if err != nil {
		t.Fatal(err)
	}
	if r.Path != "/api/cards/****************/charge" {
		t.Fatalf("path %q", r.Path)
	}
}

func TestMaskCards(t *testing.T) {
	cases := map[string]string{
		"/a/123456789012345/b":              "/a/123456789012345/b",
		"/a/1234567890123456/b":             "/a/****************/b",
		"/a/12345678901234567":              "/a/*****************",
		"1111222233334444x5555666677778888": "****************x****************",
		"":                                  "",
	}
	for in, want := range cases {
		if got := MaskCards(in); got != want {
			t.Errorf("MaskCards(%q) = %q, want %q", in, got, want)
		}
	}
}

func FuzzParseLine(f *testing.F) {
	f.Add("2026-09-12T10:00:01Z GET /api/users 200 12")
	f.Add("this line is not a log line")
	f.Add("2026-09-12T10:00:09Z GET /api/cards/4111111111111111/charge 200 88")
	f.Fuzz(func(t *testing.T, line string) {
		r, err := ParseLine(line)
		if err != nil {
			if !errors.Is(err, ErrMalformed) {
				t.Fatalf("unexpected error kind: %v", err)
			}
			return
		}
		checkParsedRecord(t, r)
	})
}

func checkParsedRecord(t *testing.T, r Record) {
	t.Helper()
	if r.Status < 100 || r.Status > 599 {
		t.Fatalf("status %d escaped parsing", r.Status)
	}
	if ContainsCard(r.Path) || ContainsCard(r.AtText) {
		t.Fatalf("card number escaped parsing: %+v", r)
	}
	if !utf8.ValidString(r.Path) || !strings.HasPrefix(r.Path, "/") {
		t.Fatalf("bad path %q", r.Path)
	}
}
