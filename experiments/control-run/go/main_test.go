package main

import (
	"bytes"
	"errors"
	"os"
	"strings"
	"testing"
)

func TestParseArgsDefaultsAndOrder(t *testing.T) {
	opts, err := ParseArgs([]string{"--json", "--top", "7", "logs", "--since", "2026-09-12T10:00:00Z"})
	if err != nil {
		t.Fatal(err)
	}
	if opts.Dir != "logs" || opts.Top != 7 || !opts.JSON || opts.Since == nil {
		t.Errorf("got %+v", opts)
	}
	if opts, err := ParseArgs([]string{"logs"}); err != nil || opts.Top != 5 || opts.JSON || opts.Since != nil {
		t.Errorf("defaults: %+v %v", opts, err)
	}
}

// --top outside 1 to 100 is a usage error, not a clamp; so is every other bad command line.
func TestParseArgsRejects(t *testing.T) {
	cases := map[string][]string{
		"top 0":          {"logs", "--top", "0"},
		"top 101":        {"logs", "--top", "101"},
		"top not number": {"logs", "--top", "five"},
		"top no value":   {"logs", "--top"},
		"bad since":      {"logs", "--since", "yesterday"},
		"missing dir":    {"--json"},
		"two dirs":       {"a", "b"},
		"empty dir":      {""},
		"unknown flag":   {"logs", "--verbose"},
		"flag twice":     {"logs", "--json", "--json"},
		"equals form":    {"logs", "--top=5"},
	}
	for name, args := range cases {
		var ue *UsageError
		if _, err := ParseArgs(args); !errors.As(err, &ue) {
			t.Errorf("%s: want UsageError, got %v", name, err)
		}
	}
}

func runCapture(args ...string) (code int, stdout, stderr string) {
	var out, errb bytes.Buffer
	code = run(args, &out, &errb)
	return code, out.String(), errb.String()
}

func TestRunUsageErrorExit2OneLine(t *testing.T) {
	code, out, errs := runCapture("fixture", "--top", "0")
	if code != ExitUsage || out != "" || strings.Count(errs, "\n") != 1 {
		t.Errorf("code %d, stdout %q, stderr %q", code, out, errs)
	}
}

func TestRunNoLogsExit1(t *testing.T) {
	for _, dir := range []string{t.TempDir(), "does-not-exist"} {
		code, out, errs := runCapture(dir)
		if code != 1 || out != "" || strings.Count(errs, "\n") != 1 {
			t.Errorf("%s: code %d, stdout %q, stderr %q", dir, code, out, errs)
		}
	}
}

func TestRunFixtureMatchesExpected(t *testing.T) {
	for args, file := range map[string]string{"fixture": "expected.txt", "fixture --json": "expected.json"} {
		want, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		code, out, errs := runCapture(strings.Fields(args)...)
		if code != ExitOK || out != string(want) || errs != "" {
			t.Errorf("%s: code %d\n%s\nstderr %q", args, code, out, errs)
		}
	}
}

func TestRunSinceAndTop(t *testing.T) {
	code, out, _ := runCapture("fixture", "--since", "2026-09-12T10:01:00Z", "--top", "1", "--json")
	want := `{"requests": 5, "errors": 1, "error_rate": 0.2, "malformed": 5, "per_minute": 2.0, ` +
		`"slowest": [{"ms": 610, "method": "GET", "path": "/api/cards/****************/charge", "at": "2026-09-12T10:01:30Z"}], ` +
		`"busiest": [{"count": 2, "method": "GET", "path": "/api/users"}]}` + "\n"
	if code != ExitOK || out != want {
		t.Errorf("code %d\n got %s\nwant %s", code, out, want)
	}
}
