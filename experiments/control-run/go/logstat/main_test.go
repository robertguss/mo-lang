package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func runArgs(args ...string) (int, string, string) {
	var out, errOut strings.Builder
	code := run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func jsonReport(t *testing.T, args ...string) Report {
	t.Helper()
	code, out, errOut := runArgs(append(args, "--json")...)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errOut)
	}
	var r Report
	if err := json.Unmarshal([]byte(out), &r); err != nil {
		t.Fatal(err)
	}
	return r
}

func TestUsageErrors(t *testing.T) {
	for _, args := range [][]string{
		{},
		{"fixture", "other"},
		{"fixture", "--top", "0"},
		{"fixture", "--top", "101"},
		{"fixture", "--top=-3"},
		{"fixture", "--top", "five"},
		{"fixture", "--top"},
		{"fixture", "--since", "yesterday"},
		{"fixture", "--bogus"},
		{"fixture", "--json=yes"},
		{"fixture", "--top", "5", "--top", "6"},
		{"no-such-dir"},
	} {
		code, out, errOut := runArgs(args...)
		if code != 2 || out != "" || strings.Count(errOut, "\n") != 1 || !strings.HasSuffix(errOut, "\n") {
			t.Errorf("run(%q) = %d, stdout %q, stderr %q; want 2 and one stderr line", args, code, out, errOut)
		}
	}
}

func TestTopBoundsAccepted(t *testing.T) {
	if r := jsonReport(t, "fixture", "--top", "1"); len(r.Slowest) != 1 || len(r.Busiest) != 1 {
		t.Errorf("--top 1: %+v", r)
	}
	if r := jsonReport(t, "--top=100", "fixture"); len(r.Slowest) != 12 || len(r.Busiest) != 7 {
		t.Errorf("--top=100: %d slowest, %d busiest", len(r.Slowest), len(r.Busiest))
	}
}

func TestFixtureMatchesExpected(t *testing.T) {
	for _, c := range []struct {
		args     []string
		expected string
	}{
		{[]string{"fixture"}, "expected.txt"},
		{[]string{"fixture", "--json"}, "expected.json"},
	} {
		want, err := os.ReadFile(c.expected)
		if err != nil {
			t.Fatal(err)
		}
		code, out, errOut := runArgs(c.args...)
		if code != 0 || out != string(want) || errOut != "" {
			t.Errorf("run(%q) = %d\n%s\nwant\n%s\nstderr %q", c.args, code, out, want, errOut)
		}
	}
}

func TestCardNeverReachesStdout(t *testing.T) {
	card := regexp.MustCompile(`[0-9]{16}|4111`)
	for _, args := range [][]string{{"fixture"}, {"fixture", "--json"}, {"fixture", "--top", "100"}} {
		_, out, _ := runArgs(args...)
		if card.MatchString(out) || !strings.Contains(out, "/pay/****") {
			t.Errorf("run(%q) stdout:\n%s", args, out)
		}
	}
}

func TestSinceIgnoresEarlierLines(t *testing.T) {
	r := jsonReport(t, "fixture", "--since", "2026-09-12T10:05:00Z")
	if r.Requests != 3 || r.Errors != 1 || r.Malformed != 4 || r.PerMinute != 0.7 {
		t.Errorf("report = %+v", r)
	}
}

func TestNoLogFile(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "notes.txt"), "2026-09-12T10:00:00Z GET /a 200 1\n")
	if err := os.Mkdir(filepath.Join(dir, "sub.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runArgs(dir)
	if code != 1 || out != "" || !strings.Contains(errOut, "no .log file") {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out, errOut)
	}
}

func TestNeverReadsOutsideDir(t *testing.T) {
	tmp := t.TempDir()
	outside, dir := filepath.Join(tmp, "outside"), filepath.Join(tmp, "dir")
	for _, d := range []string{outside, dir} {
		if err := os.Mkdir(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeFile(t, filepath.Join(outside, "secret.log"), "2026-09-12T10:00:00Z GET /secret 200 1\n")
	if err := os.Symlink("../outside/secret.log", filepath.Join(dir, "link.log")); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := runArgs(dir); code != 1 {
		t.Errorf("a directory holding only a symlink out: exit %d, want 1", code)
	}
	writeFile(t, filepath.Join(dir, "real.log"), "2026-09-12T10:00:00Z GET /real 200 1\n")
	if r := jsonReport(t, dir); r.Requests != 1 || r.Busiest[0].Path != "/real" {
		t.Errorf("report = %+v", r)
	}

	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	sum, err := NewSummary(5)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"../outside/secret.log", "sub/x.log", "real.txt"} {
		wantViolation(t, readLog(root, name, time.Time{}, sum), "requires")
	}
	if err := readLog(root, "link.log", time.Time{}, sum); err == nil {
		t.Error("os.Root opened a symlink that leaves the directory")
	}
}

func TestLongLinesCRLFAndNoFinalNewline(t *testing.T) {
	dir := t.TempDir()
	long := "2026-09-12T10:00:00Z GET /" + strings.Repeat("x", 70_000) + " 200 1"
	writeFile(t, filepath.Join(dir, "a.log"),
		long+"\n2026-09-12T10:00:00Z GET /a 200 1\r\n\n2026-09-12T10:01:00Z GET /b 500 2")
	r := jsonReport(t, dir)
	if r.Requests != 2 || r.Malformed != 2 || r.Errors != 1 {
		t.Errorf("report = %+v", r)
	}
}
