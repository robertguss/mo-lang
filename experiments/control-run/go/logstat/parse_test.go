package main

import (
	"errors"
	"math/rand/v2"
	"regexp"
	"strings"
	"testing"
	"time"
)

func TestParseLineGood(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:02Z POST /api/orders 500 340")
	if err != nil {
		t.Fatal(err)
	}
	want := Record{
		At: time.Date(2026, 9, 12, 10, 0, 2, 0, time.UTC), AtText: "2026-09-12T10:00:02Z",
		Method: "POST", Path: "/api/orders", Status: 500, MS: 340,
	}
	if !r.At.Equal(want.At) || r.AtText != want.AtText || r.Method != want.Method ||
		r.Path != want.Path || r.Status != want.Status || r.MS != want.MS {
		t.Errorf("ParseLine = %+v, want %+v", r, want)
	}
}

func TestParseLineAcceptsBounds(t *testing.T) {
	for _, line := range []string{
		"2026-09-12T10:00:02Z GET / 100 0",
		"2026-09-12T10:00:02Z GET / 599 4294967295",
		"2026-09-12T10:00:02.250+02:00 GET /a 200 012",
	} {
		if _, err := ParseLine(line); err != nil {
			t.Errorf("ParseLine(%q) = %v, want a record", line, err)
		}
	}
}

// Every requires of a line: each way to break the format is a MalformedError.
func TestParseLineRejects(t *testing.T) {
	for _, line := range []string{
		"",
		"2026-09-12T10:00:02Z GET /a 200",
		"2026-09-12T10:00:02Z GET /a 200 1 extra",
		"2026-09-12T10:00:02Z  GET /a 200 1",
		"2026-09-12 GET /a 200 1",
		"2026-09-12T10:00:02 GET /a 200 1",
		"yesterday GET /a 200 1",
		"2026-09-12T10:00:02Z get /a 200 1",
		"2026-09-12T10:00:02Z G3T /a 200 1",
		"2026-09-12T10:00:02Z ABCDEFGHIJKLMNOPQ /a 200 1",
		"2026-09-12T10:00:02Z GET a 200 1",
		"2026-09-12T10:00:02Z GET /a\x01 200 1",
		"2026-09-12T10:00:02Z GET /a 99 1",
		"2026-09-12T10:00:02Z GET /a 600 1",
		"2026-09-12T10:00:02Z GET /a 20 1",
		"2026-09-12T10:00:02Z GET /a 2000 1",
		"2026-09-12T10:00:02Z GET /a +20 1",
		"2026-09-12T10:00:02Z GET /a 200 -1",
		"2026-09-12T10:00:02Z GET /a 200 4294967296",
		"2026-09-12T10:00:02Z GET /a 200 1.5",
		"2026-09-12T10:00:02Z GET /a\xff 200 1",
		"2026-09-12T10:00:02Z\tGET /a 200 1",
	} {
		_, err := ParseLine(line)
		var bad *MalformedError
		if !errors.As(err, &bad) {
			t.Errorf("ParseLine(%q) = %v, want a MalformedError", line, err)
		}
	}
}

func TestMaskCards(t *testing.T) {
	cases := map[string]string{
		"/pay/4111111111111111":                  "/pay/****************",
		"/pay/4111-1111-1111-1111/x":             "/pay/****-****-****-****/x",
		"/pay/41111111111111111":                 "/pay/*****************",
		"/pay/411111111111111":                   "/pay/411111111111111",
		"/orders/2026-09-12":                     "/orders/2026-09-12",
		"/a/12345678--12345678":                  "/a/12345678--12345678",
		"/a/4111111111111111/b/5500000000000004": "/a/****************/b/****************",
		"/users/42":                              "/users/42",
	}
	for in, want := range cases {
		if got := MaskCards(in); got != want {
			t.Errorf("MaskCards(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestParseLineMasksCardInPath(t *testing.T) {
	r, err := ParseLine("2026-09-12T10:00:02Z POST /pay/4111111111111111/confirm 201 9")
	if err != nil {
		t.Fatal(err)
	}
	if r.Path != "/pay/****************/confirm" {
		t.Errorf("Path = %q", r.Path)
	}
}

// Property: after masking, no 16 digits remain in a row, hyphens or not.
func TestPropertyMaskedPathHasNoCard(t *testing.T) {
	rng := rand.New(rand.NewPCG(1, 2))
	sixteen := regexp.MustCompile(`[0-9]{16}`)
	const alphabet = "0123456789012345678901234567890123456789-/a"
	for range 5000 {
		var b strings.Builder
		for range rng.IntN(80) {
			b.WriteByte(alphabet[rng.IntN(len(alphabet))])
		}
		in := b.String()
		out := MaskCards(in)
		if len(out) != len(in) || sixteen.MatchString(out) || len(cardRuns(out)) != 0 {
			t.Fatalf("MaskCards(%q) = %q still holds a card number", in, out)
		}
	}
}
