package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/iotest"
)

const validLine = "2026-09-12T10:00:00Z GET /a 200 1\n"

func TestNoLogFileExitsOne(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{"notes.txt": validLine, "sub/a.log": validLine})
	missing := filepath.Join(t.TempDir(), "missing")
	for _, d := range []string{dir, missing} {
		code, out, errOut := runLogstat(d)
		if code != exitFailure || out != "" || strings.Count(errOut, "\n") != 1 {
			t.Errorf("logstat %s: exit %d, stdout %q, stderr %q", d, code, out, errOut)
		}
	}
	if _, _, errOut := runLogstat(dir); !strings.Contains(errOut, "no .log file found") {
		t.Errorf("stderr = %q", errOut)
	}
}

func TestOnlyLogFilesDirectlyInsideAreRead(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{
		"a.log": validLine, "notes.txt": validLine, "sub/b.log": validLine, "c.log.bak": validLine,
	})
	if err := os.Mkdir(filepath.Join(dir, "d.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runLogstat(dir, "--json")
	if code != exitOK || !strings.HasPrefix(out, `{"requests": 1,`) {
		t.Errorf("exit %d, stderr %q, stdout %s", code, errOut, out)
	}
}

func TestFilesAreReadInNameOrder(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{
		"b.log": "2026-09-12T10:00:00Z GET /from-b 200 7\n",
		"a.log": "2026-09-12T10:00:00Z GET /from-a 200 7\n",
	})
	code, out, _ := runLogstat(dir, "--json", "--top", "1")
	if code != exitOK || !strings.Contains(out, `"slowest": [{"ms": 7, "method": "GET", "path": "/from-a"`) {
		t.Errorf("exit %d, stdout %s", code, out)
	}
}

func TestSymlinkOutsideDirIsNeverRead(t *testing.T) {
	outside := t.TempDir()
	writeFiles(t, outside, map[string]string{"secret.log": "2026-09-12T10:00:00Z GET /secret 200 1\n"})
	secret := filepath.Join(outside, "secret.log")
	relative, err := filepath.Rel(t.TempDir(), secret)
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range []string{secret, relative} {
		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{"a.log": validLine})
		if err := os.Symlink(target, filepath.Join(dir, "evil.log")); err != nil {
			t.Fatal(err)
		}
		code, out, errOut := runLogstat(dir)
		if code != exitFailure || out != "" || strings.Contains(errOut, "/secret ") {
			t.Errorf("link to %s: exit %d, stdout %q, stderr %q", target, code, out, errOut)
		}
	}
}

func TestSymlinkInsideDirIsRead(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{"logs/real.txt": validLine})
	if err := os.Symlink("logs/real.txt", filepath.Join(dir, "link.log")); err != nil {
		t.Fatal(err)
	}
	if code, out, errOut := runLogstat(dir, "--json"); code != exitOK || !strings.HasPrefix(out, `{"requests": 1,`) {
		t.Errorf("exit %d, stderr %q, stdout %s", code, errOut, out)
	}
}

func TestTallyReaderLineEndings(t *testing.T) {
	long := strings.Repeat("x", maxLine+10)
	cases := []struct {
		name                string
		input               string
		requests, malformed uint64
	}{
		{"long lines are malformed", long + "\n" + validLine + long, 1, 2},
		{"CRLF and no final newline", "2026-09-12T10:00:00Z GET /a 200 1\r\n2026-09-12T10:00:01Z GET /b 200 1", 2, 0},
		{"blank line is malformed", validLine + "\n" + validLine, 2, 1},
		{"line just under the limit", strings.Repeat("y", maxLine-1) + "\n" + validLine, 1, 1},
		{"empty file", "", 0, 0},
	}
	for _, c := range cases {
		tally := mustTally(t, 5, nil)
		if err := tallyReader(strings.NewReader(c.input), tally); err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		s := mustSummary(t, tally)
		if s.Requests != c.requests || s.Malformed != c.malformed {
			t.Errorf("%s: requests %d malformed %d, want %d %d", c.name, s.Requests, s.Malformed, c.requests, c.malformed)
		}
	}
}

func TestTallyReaderReturnsReadErrors(t *testing.T) {
	boom := errors.New("boom")
	if err := tallyReader(iotest.ErrReader(boom), mustTally(t, 5, nil)); !errors.Is(err, boom) {
		t.Errorf("tallyReader error = %v, want boom", err)
	}
}
