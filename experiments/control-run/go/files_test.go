package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func openRoot(t *testing.T, dir string) *os.Root {
	t.Helper()
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := root.Close(); err != nil {
			t.Error(err)
		}
	})
	return root
}

func TestLogFilesNameOrderAndFilter(t *testing.T) {
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "secret.log")
	writeFile(t, outside, "2026-09-12T10:00:00Z GET /secret 200 1\n")
	writeFile(t, filepath.Join(dir, "b.log"), "")
	writeFile(t, filepath.Join(dir, "a.log"), "")
	// Z sorts before a in byte order. Not B.log: macOS file systems ignore
	// case, so B.log would overwrite b.log.
	writeFile(t, filepath.Join(dir, "Z.log"), "")
	writeFile(t, filepath.Join(dir, "notes.txt"), "")
	writeFile(t, filepath.Join(dir, "a.log.bak"), "")
	if err := os.Mkdir(filepath.Join(dir, "dir.log"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dir, "evil.log")); err != nil {
		t.Fatal(err)
	}
	names, err := LogFiles(openRoot(t, dir))
	if err != nil {
		t.Fatalf("LogFiles: %v", err)
	}
	if want := []string{"Z.log", "a.log", "b.log"}; !slices.Equal(names, want) {
		t.Errorf("names = %q, want %q", names, want)
	}
}

// Never: the program never reads a file outside <dir>.
func TestScanFileRefusesEscape(t *testing.T) {
	parent := t.TempDir()
	dir := filepath.Join(parent, "logs")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(parent, "outside.log"), "2026-09-12T10:00:00Z GET /secret 200 1\n")
	if err := os.Symlink(filepath.Join(parent, "outside.log"), filepath.Join(dir, "link.log")); err != nil {
		t.Fatal(err)
	}
	root := openRoot(t, dir)
	for _, name := range []string{"../outside.log", "link.log", filepath.Join(parent, "outside.log")} {
		acc := NewAccumulator(5, time.Time{}, false)
		if err := ScanFile(root, name, acc); err == nil {
			t.Errorf("ScanFile(%q) read outside the directory", name)
		}
	}
}

func TestScanLinesEdges(t *testing.T) {
	long := strings.Repeat("x", maxLine+10)
	input := "2026-09-12T10:00:00Z GET /crlf 200 1\r\n" +
		"\n" +
		long + "\n" +
		"2026-09-12T10:00:01Z GET /after-long 200 1\n" +
		"2026-09-12T10:00:02Z GET /no-newline 200 1"
	acc := NewAccumulator(5, time.Time{}, false)
	if err := scanLines(strings.NewReader(input), acc); err != nil {
		t.Fatalf("scanLines: %v", err)
	}
	s, err := acc.Summary()
	if err != nil {
		t.Fatalf("Summary: %v", err)
	}
	if s.Requests != 3 || s.Malformed != 2 {
		t.Errorf("requests %d malformed %d, want 3 and 2", s.Requests, s.Malformed)
	}
}

func TestScanLinesLongLastLine(t *testing.T) {
	acc := NewAccumulator(5, time.Time{}, false)
	if err := scanLines(strings.NewReader(strings.Repeat("y", 3*maxLine)), acc); err != nil {
		t.Fatalf("scanLines: %v", err)
	}
	if acc.sum.Malformed != 1 || acc.sum.Requests != 0 {
		t.Errorf("summary = %+v", acc.sum)
	}
}
