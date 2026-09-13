package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func runLogstat(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func writeFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, content := range files {
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRunMatchesExpectedFiles(t *testing.T) {
	cases := []struct {
		args []string
		file string
	}{
		{[]string{"fixture"}, "expected.txt"},
		{[]string{"fixture", "--json"}, "expected.json"},
	}
	for _, c := range cases {
		want, err := os.ReadFile(c.file)
		if err != nil {
			t.Fatal(err)
		}
		code, out, errOut := runLogstat(c.args...)
		if code != exitOK || errOut != "" || out != string(want) {
			t.Errorf("logstat %v: exit %d, stderr %q, stdout:\n%s\nwant:\n%s", c.args, code, errOut, out, want)
		}
	}
}

// One usage error per requires on parseArgs, plus --top outside 1..100,
// which is an error and never a clamp.
func TestUsageErrorsExitTwoWithOneLine(t *testing.T) {
	for _, args := range [][]string{
		{},
		{"fixture", "other"},
		{"--json"},
		{"fixture", "--top", "0"},
		{"fixture", "--top", "101"},
		{"fixture", "--top", "-3"},
		{"fixture", "--top", "five"},
		{"fixture", "--top"},
		{"fixture", "--since", "yesterday"},
		{"fixture", "--since", "2026-09-12"},
		{"fixture", "--since"},
		{"fixture", "--verbose"},
		{"fixture", "--json", "--json"},
	} {
		code, out, errOut := runLogstat(args...)
		if code != exitUsage || out != "" || strings.Count(errOut, "\n") != 1 || !strings.HasSuffix(errOut, "\n") {
			t.Errorf("logstat %q: exit %d, stdout %q, stderr %q", args, code, out, errOut)
		}
	}
}

func TestParseArgs(t *testing.T) {
	opts, err := parseArgs([]string{"logs"})
	if err != nil || opts.dir != "logs" || opts.top != defaultTop || opts.since != nil || opts.json {
		t.Errorf("defaults = %+v, %v", opts, err)
	}
	opts, err = parseArgs([]string{"--json", "--top", "3", "logs", "--since", "2026-09-12T10:00:00Z"})
	if err != nil || opts.dir != "logs" || opts.top != 3 || !opts.json || opts.since == nil || !opts.since.Equal(base) {
		t.Errorf("flags anywhere = %+v, %v", opts, err)
	}
}

func TestTopBoundsAreAccepted(t *testing.T) {
	for _, top := range []string{"1", "100"} {
		if code, _, errOut := runLogstat("fixture", "--top", top); code != exitOK {
			t.Errorf("--top %s: exit %d, stderr %q", top, code, errOut)
		}
	}
	_, out, _ := runLogstat("fixture", "--top", "1")
	if !strings.Contains(out, "slowest\n  1_200 ms  DELETE /api/users/7  2026-09-12T10:03:30Z\n\n") {
		t.Errorf("--top 1 slowest section wrong:\n%s", out)
	}
}

func TestSinceFiltersTheRun(t *testing.T) {
	code, out, _ := runLogstat("fixture", "--json", "--since", "2026-09-12T10:05:00Z")
	if code != exitOK || !strings.HasPrefix(out, `{"requests": 4, "errors": 1, "error_rate": 0.25, "malformed": 3, "per_minute": 0.8,`) {
		t.Errorf("exit %d, stdout %s", code, out)
	}
}

func TestNoCardNumberReachesStdout(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{"a.log": "" +
		"2026-09-12T10:00:00Z GET /pay/41111111111111112222 200 5\n" +
		"2026-09-12T10:00:00.1234567890123456Z GET /pay/4111111111111111 200 5\n"})
	card := regexp.MustCompile(`[0-9]{16}`)
	for _, args := range [][]string{{"fixture"}, {"fixture", "--json"}, {dir}, {dir, "--json"}} {
		code, out, _ := runLogstat(args...)
		if code != exitOK || card.MatchString(out) {
			t.Errorf("logstat %v: exit %d, stdout:\n%s", args, code, out)
		}
	}
}

func TestSinceIsInclusive(t *testing.T) {
	code, out, _ := runLogstat("fixture", "--json", "--since", base.Add(10*time.Minute).Format(time.RFC3339))
	if code != exitOK || !strings.HasPrefix(out, `{"requests": 1,`) {
		t.Errorf("exit %d, stdout %s", code, out)
	}
}
