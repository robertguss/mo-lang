package main

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func writeFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func openRoot(t *testing.T, dir string) *os.Root {
	t.Helper()
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = root.Close() })
	return root
}

func TestListLogsFiltersAndSorts(t *testing.T) {
	dir := t.TempDir()
	writeFiles(t, dir, map[string]string{"b.log": "", "a.log": "", "notes.txt": "", ".log": "", "c.log.bak": ""})
	if err := os.Mkdir(filepath.Join(dir, "d.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	names, err := ListLogs(openRoot(t, dir))
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(names, []string{"a.log", "b.log"}) {
		t.Errorf("got %v", names)
	}
}

// Never: a file outside <dir> is not read, whether through a symlink or a name.
func TestNeverReadsOutsideDir(t *testing.T) {
	outside := t.TempDir()
	writeFiles(t, outside, map[string]string{"secret.log": "2026-09-12T10:00:00Z GET /secret 200 1\n"})
	dir := t.TempDir()
	if err := os.Symlink(filepath.Join(outside, "secret.log"), filepath.Join(dir, "link.log")); err != nil {
		t.Fatal(err)
	}
	root := openRoot(t, dir)
	names, err := ListLogs(root)
	if err != nil || len(names) != 0 {
		t.Fatalf("symlink listed: %v %v", names, err)
	}
	acc, err := NewAccumulator(5, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := ReadLog(root, "link.log", acc); err == nil {
		t.Error("reading a symlink out of the root succeeded")
	}
	rel, err := filepath.Rel(dir, filepath.Join(outside, "secret.log"))
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{rel, "../secret.log", "/etc/hosts", "sub/x.log"} {
		if err := ReadLog(root, name, acc); !errors.Is(err, ErrOutside) {
			t.Errorf("%q: want ErrOutside, got %v", name, err)
		}
	}
	if s, _ := acc.Summary(); s.Requests != 0 {
		t.Errorf("read %d requests from outside", s.Requests)
	}
}

func scan(t *testing.T, body string) (lines []string, bad int) {
	t.Helper()
	err := ScanLines(strings.NewReader(body), func(line string, ok bool) {
		if ok {
			lines = append(lines, line)
		} else {
			bad++
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	return lines, bad
}

func TestScanLinesEndings(t *testing.T) {
	lines, bad := scan(t, "a\r\nb\n\nc")
	if !slices.Equal(lines, []string{"a", "b", "", "c"}) || bad != 0 {
		t.Errorf("got %q, %d", lines, bad)
	}
}

func TestScanLinesTooLongIsMalformedAndScanningContinues(t *testing.T) {
	long := strings.Repeat("x", 3*MaxLineBytes)
	lines, bad := scan(t, "a\n"+long+"\nb\n")
	if !slices.Equal(lines, []string{"a", "b"}) || bad != 1 {
		t.Errorf("got %d lines, %d bad", len(lines), bad)
	}
}
