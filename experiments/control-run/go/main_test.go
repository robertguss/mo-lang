package main

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

func runArgs(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestParseArgsDefaultsAndForms(t *testing.T) {
	o, err := ParseArgs([]string{"logs"})
	if err != nil || o.Dir != "logs" || o.Top != 5 || o.JSON || o.HasSince {
		t.Fatalf("defaults: %+v %v", o, err)
	}
	o, err = ParseArgs([]string{"--json", "--top=7", "logs", "--since", "2026-09-12T10:00:00Z"})
	if err != nil || o.Dir != "logs" || o.Top != 7 || !o.JSON || !o.HasSince {
		t.Fatalf("flags: %+v %v", o, err)
	}
}

// One rejects test per requirement of the command line.
func TestParseArgsRejects(t *testing.T) {
	cases := map[string][]string{
		"no args":         {},
		"no dir":          {"--json"},
		"empty dir":       {""},
		"two dirs":        {"a", "b"},
		"unknown flag":    {"a", "--verbose"},
		"top no value":    {"a", "--top"},
		"top zero":        {"a", "--top", "0"},
		"top 101":         {"a", "--top", "101"},
		"top negative":    {"a", "--top=-3"},
		"top not number":  {"a", "--top", "five"},
		"since no value":  {"a", "--since"},
		"since bad":       {"a", "--since", "yesterday"},
		"json with value": {"a", "--json=true"},
		"flag twice":      {"a", "--top", "3", "--top", "4"},
	}
	for name, args := range cases {
		if _, err := ParseArgs(args); !isUsage(err) {
			t.Errorf("%s: want a usage error, got %v", name, err)
		}
	}
}

func TestRunUsageErrorExitsTwoWithOneLine(t *testing.T) {
	code, stdout, stderr := runArgs("fixture", "--top", "101")
	if code != 2 || stdout != "" {
		t.Fatalf("code %d stdout %q", code, stdout)
	}
	if strings.Count(stderr, "\n") != 1 || !strings.HasSuffix(stderr, "\n") {
		t.Fatalf("stderr must be one line: %q", stderr)
	}
	code, _, stderr = runArgs("a\nb", "c")
	if code != 2 || strings.Count(stderr, "\n") != 1 {
		t.Fatalf("newline in an argument broke the line: %q", stderr)
	}
}

func TestRunNoLogsExitsOne(t *testing.T) {
	code, stdout, stderr := runArgs(t.TempDir())
	if code != 1 || stdout != "" || !strings.Contains(stderr, "no .log file") {
		t.Fatalf("code %d stdout %q stderr %q", code, stdout, stderr)
	}
	if code, _, _ := runArgs(filepath.Join(t.TempDir(), "missing")); code != 1 {
		t.Fatalf("missing dir: code %d", code)
	}
}

func TestRunFixtureNeverPrintsCardNumber(t *testing.T) {
	for _, args := range [][]string{{"fixture"}, {"fixture", "--json"}, {"fixture", "--top", "100"}} {
		code, stdout, _ := runArgs(args...)
		if code != 0 || ContainsCard(stdout) || !strings.Contains(stdout, "****************") {
			t.Fatalf("%v: code %d\n%s", args, code, stdout)
		}
	}
}

type jsonBack struct {
	Requests  int           `json:"requests"`
	Errors    int           `json:"errors"`
	Malformed int           `json:"malformed"`
	PerMinute float64       `json:"per_minute"`
	Slowest   []jsonSlow    `json:"slowest"`
	Busiest   []jsonBusiest `json:"busiest"`
}

func runJSON(t *testing.T, args ...string) jsonBack {
	t.Helper()
	code, stdout, stderr := runArgs(append(args, "--json")...)
	if code != 0 {
		t.Fatalf("code %d: %s", code, stderr)
	}
	var back jsonBack
	if err := json.Unmarshal([]byte(stdout), &back); err != nil {
		t.Fatal(err)
	}
	return back
}

func TestRunSinceIgnoresEarlierLines(t *testing.T) {
	got := runJSON(t, "fixture", "--since", "2026-09-12T10:01:00Z")
	if got.Requests != 5 || got.Errors != 1 || got.Malformed != 5 {
		t.Fatalf("got %+v", got)
	}
	if got.PerMinute != 2.0 { // 5 requests over 151 seconds, 1.987 rounded
		t.Fatalf("per minute %v", got.PerMinute)
	}
}

func TestRunTopLimitsBothLists(t *testing.T) {
	got := runJSON(t, "fixture", "--top", "1")
	if len(got.Slowest) != 1 || got.Slowest[0].Ms != 1204 {
		t.Fatalf("slowest %+v", got.Slowest)
	}
	if len(got.Busiest) != 1 || got.Busiest[0].Count != 7 {
		t.Fatalf("busiest %+v", got.Busiest)
	}
}
