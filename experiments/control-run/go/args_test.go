package main

import (
	"errors"
	"testing"
	"time"
)

func TestParseArgsDefaults(t *testing.T) {
	opts, err := ParseArgs([]string{"logs"})
	if err != nil {
		t.Fatal(err)
	}
	if opts != (Options{Dir: "logs", Top: 5}) {
		t.Errorf("got %+v", opts)
	}
}

func TestParseArgsAllFlagsAnyOrder(t *testing.T) {
	since := time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)
	want := Options{Dir: "logs", Top: 100, Since: since, HasSince: true, JSON: true}
	for _, args := range [][]string{
		{"logs", "--top", "100", "--since", "2026-09-12T10:00:00Z", "--json"},
		{"--json", "--since", "2026-09-12T10:00:00Z", "--top", "100", "logs"},
	} {
		opts, err := ParseArgs(args)
		if err != nil {
			t.Fatalf("%v: %v", args, err)
		}
		if !opts.Since.Equal(want.Since) || opts.Dir != want.Dir || opts.Top != want.Top || !opts.HasSince || !opts.JSON {
			t.Errorf("%v: got %+v", args, opts)
		}
	}
}

func TestParseArgsTopOne(t *testing.T) {
	opts, err := ParseArgs([]string{"logs", "--top", "1"})
	if err != nil || opts.Top != 1 {
		t.Errorf("got %+v, %v", opts, err)
	}
}

// One case per requires of ParseArgs.
func TestParseArgsRejects(t *testing.T) {
	cases := map[string][]string{
		"no arguments":     {},
		"missing dir":      {"--json"},
		"two dirs":         {"a", "b"},
		"unknown flag":     {"logs", "--verbose"},
		"single dash flag": {"logs", "-top", "5"},
		"flag twice":       {"logs", "--json", "--json"},
		"top no value":     {"logs", "--top"},
		"since no value":   {"logs", "--since"},
		"top zero":         {"logs", "--top", "0"},
		"top 101":          {"logs", "--top", "101"},
		"top negative":     {"logs", "--top", "-3"},
		"top not a number": {"logs", "--top", "five"},
		"top huge":         {"logs", "--top", "99999999999999999999"},
		"since bad":        {"logs", "--since", "yesterday"},
		"since no zone":    {"logs", "--since", "2026-09-12T10:00:00"},
	}
	for name, args := range cases {
		_, err := ParseArgs(args)
		var ue UsageError
		if !errors.As(err, &ue) {
			t.Errorf("%s: ParseArgs(%q) err = %v, want UsageError", name, args, err)
		}
	}
}
