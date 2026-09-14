package main

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

var cardRun = regexp.MustCompile(`[0-9]{16}`)

func runArgs(args ...string) (code int, stdout, stderr string) {
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestRunFixture(t *testing.T) {
	for _, extra := range [][]string{nil, {"--json"}} {
		code, out, errOut := runArgs(append([]string{"fixture"}, extra...)...)
		if code != exitOK || errOut != "" {
			t.Fatalf("%v: exit %d, stderr %q", extra, code, errOut)
		}
		// Never: a card number reaches stdout.
		if cardRun.MatchString(out) {
			t.Errorf("%v: card number on stdout:\n%s", extra, out)
		}
	}
}

func TestRunTopAndSince(t *testing.T) {
	code, out, _ := runArgs("fixture", "--top", "1", "--since", "2026-09-12T10:01:00Z")
	if code != exitOK {
		t.Fatalf("exit %d", code)
	}
	want := "requests    5\n"
	if !strings.HasPrefix(out, want) || strings.Count(out, " ms ") != 1 {
		t.Errorf("output:\n%s", out)
	}
}

func TestRunUsageErrorIsOneLineExit2(t *testing.T) {
	for _, args := range [][]string{{}, {"fixture", "--top", "0"}, {"fixture", "--top", "101"}, {"fixture", "--nope\nline"}} {
		code, out, errOut := runArgs(args...)
		if code != exitUsage || out != "" || strings.Count(errOut, "\n") != 1 || !strings.HasSuffix(errOut, "\n") {
			t.Errorf("%q: exit %d stdout %q stderr %q", args, code, out, errOut)
		}
	}
}

func TestRunNoLogsExit1(t *testing.T) {
	empty := t.TempDir()
	writeFile(t, filepath.Join(empty, "notes.txt"), "x")
	for _, dir := range []string{empty, filepath.Join(empty, "missing"), filepath.Join(empty, "notes.txt")} {
		code, out, errOut := runArgs(dir)
		if code != exitFailure || out != "" || strings.Count(errOut, "\n") != 1 {
			t.Errorf("%s: exit %d stdout %q stderr %q", dir, code, out, errOut)
		}
	}
}

func TestRunUnreadableLogExit1(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root reads any file")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "locked.log")
	writeFile(t, path, "2026-09-12T10:00:00Z GET /a 200 1\n")
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	if code, out, _ := runArgs(dir); code != exitFailure || out != "" {
		t.Errorf("exit %d stdout %q", code, out)
	}
}
