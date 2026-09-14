package main

import (
	"errors"
	"testing"
	"time"
)

func TestParseArgsDefaults(t *testing.T) {
	opts, err := ParseArgs([]string{"logs"})
	if err != nil {
		t.Fatalf("ParseArgs: %v", err)
	}
	if opts.Dir != "logs" || opts.Top != defaultTop || opts.HasSince || opts.JSON {
		t.Errorf("opts = %+v", opts)
	}
}

func TestParseArgsAllOptions(t *testing.T) {
	for _, args := range [][]string{
		{"logs", "--top", "7", "--since", "2026-09-12T10:00:00Z", "--json"},
		{"--json", "--top=7", "--since=2026-09-12T10:00:00Z", "logs"},
	} {
		opts, err := ParseArgs(args)
		if err != nil {
			t.Fatalf("ParseArgs(%q): %v", args, err)
		}
		since := time.Date(2026, 9, 12, 10, 0, 0, 0, time.UTC)
		if opts.Dir != "logs" || opts.Top != 7 || !opts.HasSince || !opts.Since.Equal(since) || !opts.JSON {
			t.Errorf("ParseArgs(%q) = %+v", args, opts)
		}
	}
}

// Contract: --top outside 1..100 is a usage error, not a clamp.
func TestParseArgsTopRange(t *testing.T) {
	for _, top := range []string{"1", "100"} {
		if _, err := ParseArgs([]string{"logs", "--top", top}); err != nil {
			t.Errorf("--top %s: %v", top, err)
		}
	}
	for _, top := range []string{"0", "101", "-1", "+5", "abc", "", "5.0", "99999999999999999999"} {
		_, err := ParseArgs([]string{"logs", "--top=" + top})
		var usage *UsageError
		if !errors.As(err, &usage) {
			t.Errorf("--top=%q error = %v, want UsageError", top, err)
		}
	}
}

func TestParseArgsRejects(t *testing.T) {
	for _, args := range [][]string{
		{},
		{"a", "b"},
		{""},
		{"logs", "--top"},
		{"logs", "--since"},
		{"logs", "--since", "yesterday"},
		{"logs", "--since", "2026-13-01T00:00:00Z"},
		{"logs", "--json=yes"},
		{"logs", "--json", "--json"},
		{"logs", "--top", "3", "--top", "4"},
		{"logs", "--verbose"},
		{"logs", "-t", "3"},
	} {
		_, err := ParseArgs(args)
		var usage *UsageError
		if !errors.As(err, &usage) {
			t.Errorf("ParseArgs(%q) error = %v, want UsageError", args, err)
		}
	}
}
