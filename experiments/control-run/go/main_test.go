package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func runCapture(args ...string) (code int, stdout, stderr string) {
	var out, errOut strings.Builder
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// countOf returns the value on the counts line that starts with label.
func countOf(out, label string) string {
	for _, line := range strings.Split(out, "\n") {
		if rest, ok := strings.CutPrefix(line, label+" "); ok {
			if f := strings.Fields(rest); len(f) > 0 {
				return f[0]
			}
		}
	}
	return ""
}

func golden(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestFixtureText(t *testing.T) {
	code, out, errOut := runCapture("fixture")
	if code != 0 || errOut != "" {
		t.Fatalf("exit %d, stderr %q", code, errOut)
	}
	if want := golden(t, "expected.txt"); out != want {
		t.Errorf("got\n%s\nwant\n%s", out, want)
	}
}

func TestFixtureJSON(t *testing.T) {
	code, out, _ := runCapture("fixture", "--json")
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if want := golden(t, "expected.json"); out != want {
		t.Errorf("got\n%s\nwant\n%s", out, want)
	}
}

var cardRun = regexp.MustCompile(`[0-9]{16}`)

func TestFixtureNeverPrintsCardNumber(t *testing.T) {
	for _, args := range [][]string{{"fixture"}, {"fixture", "--json"}, {"fixture", "--top", "100"}} {
		_, out, _ := runCapture(args...)
		if cardRun.MatchString(out) {
			t.Errorf("%v: card number in output\n%s", args, out)
		}
	}
}

func TestSinceAndTop(t *testing.T) {
	code, out, _ := runCapture("fixture", "--since", "2026-09-12T10:01:00Z", "--top", "1")
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if countOf(out, "requests") != "5" || !strings.Contains(out, "slowest\n  610 ms") ||
		strings.Count(out, " ms ") != 1 {
		t.Errorf("got\n%s", out)
	}
}

func TestUsageErrorExits2WithOneLine(t *testing.T) {
	for _, args := range [][]string{{}, {"fixture", "--top", "0"}, {"fixture", "--top", "101"}, {"fixture", "--nope"}} {
		code, out, errOut := runCapture(args...)
		if code != 2 || out != "" || strings.Count(errOut, "\n") != 1 {
			t.Errorf("%v: exit %d, stdout %q, stderr %q", args, code, out, errOut)
		}
	}
}

func TestNoLogFileExits1(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "notes.txt"), "2026-09-12T10:00:01Z GET /a 200 1\n")
	if err := os.Mkdir(filepath.Join(dir, "sub.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runCapture(dir)
	if code != 1 || out != "" || !strings.Contains(errOut, "no .log file") {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out, errOut)
	}
}

func TestMissingDirExits1(t *testing.T) {
	code, out, errOut := runCapture(filepath.Join(t.TempDir(), "absent"))
	if code != 1 || out != "" || errOut == "" {
		t.Errorf("exit %d, stdout %q, stderr %q", code, out, errOut)
	}
}

// The program never reads outside <dir>: a symlink to a log elsewhere is
// skipped, so its lines are not counted.
func TestSymlinkOutsideDirIsNotRead(t *testing.T) {
	outside := t.TempDir()
	writeFile(t, filepath.Join(outside, "secret.log"), "2026-09-12T10:00:01Z GET /secret 200 1\n")
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "a.log"), "2026-09-12T10:00:01Z GET /a 200 1\n")
	if err := os.Symlink(filepath.Join(outside, "secret.log"), filepath.Join(dir, "b.log")); err != nil {
		t.Skip("symlinks unavailable:", err)
	}
	code, out, _ := runCapture(dir)
	if code != 0 || strings.Contains(out, "secret") || countOf(out, "requests") != "1" {
		t.Errorf("exit %d\n%s", code, out)
	}
}

func TestLineEndingsAndLongLines(t *testing.T) {
	dir := t.TempDir()
	long := "2026-09-12T10:00:01Z GET /" + strings.Repeat("x", MaxLine) + " 200 1"
	content := "2026-09-12T10:00:01Z GET /a 200 1\r\n" + long + "\n\n" + "2026-09-12T10:00:02Z GET /b 200 1"
	writeFile(t, filepath.Join(dir, "a.log"), content)
	code, out, _ := runCapture(dir)
	if code != 0 || countOf(out, "requests") != "2" || countOf(out, "errors") != "0" || countOf(out, "malformed") != "2" {
		t.Errorf("exit %d\n%s", code, out)
	}
}

func TestFilesReadInNameOrder(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "b.log"), "2026-09-12T10:00:01Z GET /b 200 5\n")
	writeFile(t, filepath.Join(dir, "a.log"), "2026-09-12T10:00:01Z GET /a 200 5\n")
	_, out, _ := runCapture(dir)
	if !strings.Contains(out, "slowest\n  5 ms  GET /a   2026-09-12T10:00:01Z\n  5 ms  GET /b") {
		t.Errorf("same duration and instant should keep a.log first\n%s", out)
	}
}
