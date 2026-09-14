package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestLogNamesInNameOrderSkippingOthers(t *testing.T) {
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "secret.log")
	writeFile(t, outside, "2026-09-12T10:00:00Z GET /secret 200 1\n")
	for _, n := range []string{"b.log", "a.log", "notes.txt", "A.LOG", "c.log.bak"} {
		writeFile(t, filepath.Join(dir, n), "")
	}
	if err := os.Mkdir(filepath.Join(dir, "sub.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dir, "evil.log")); err != nil {
		t.Fatal(err)
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	names, err := LogNames(root)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"a.log", "b.log"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("got %v, want %v", names, want)
	}
}

func TestAnalyzeNeverReadsOutsideDir(t *testing.T) {
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "secret.log")
	writeFile(t, outside, "2026-09-12T10:00:00Z GET /secret 200 1\n")
	if err := os.Symlink(outside, filepath.Join(dir, "evil.log")); err != nil {
		t.Fatal(err)
	}
	if _, err := Analyze(Options{Dir: dir, Top: 5}); !errors.Is(err, ErrNoLogs) {
		t.Fatalf("want ErrNoLogs, got %v", err)
	}
	root, _ := os.OpenRoot(dir)
	defer root.Close()
	err := scanLog(root, "evil.log", func([]byte, bool) error { return nil })
	if err == nil {
		t.Fatal("opening a symlink that leaves the root must fail")
	}
}

func TestCheckNameRejectsPaths(t *testing.T) {
	for _, n := range []string{"", ".", "..", "../a.log", "sub/a.log", `sub\a.log`} {
		if err := CheckName(n); !errors.Is(err, ErrContract) {
			t.Errorf("%q: want ErrContract, got %v", n, err)
		}
	}
	if err := CheckName("a.log"); err != nil {
		t.Fatal(err)
	}
}

func TestAnalyzeNoLogsAndMissingDir(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "notes.txt"), "x")
	if _, err := Analyze(Options{Dir: dir, Top: 5}); !errors.Is(err, ErrNoLogs) {
		t.Fatalf("want ErrNoLogs, got %v", err)
	}
	_, err := Analyze(Options{Dir: filepath.Join(dir, "missing"), Top: 5})
	if err == nil || errors.Is(err, ErrNoLogs) {
		t.Fatalf("missing dir: got %v", err)
	}
}

type seen struct {
	lines   []string
	tooLong int
}

func collect(t *testing.T, content string) seen {
	t.Helper()
	var s seen
	err := eachLine(strings.NewReader(content), func(line []byte, tooLong bool) error {
		if tooLong {
			s.tooLong++
		} else {
			s.lines = append(s.lines, string(line))
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestEachLineEndings(t *testing.T) {
	got := collect(t, "a\r\nb\n\nc")
	if want := []string{"a", "b", "", "c"}; !reflect.DeepEqual(got.lines, want) {
		t.Fatalf("got %q, want %q", got.lines, want)
	}
	if got := collect(t, ""); len(got.lines) != 0 {
		t.Fatalf("empty input visited %q", got.lines)
	}
}

func TestEachLineSkipsTooLongLine(t *testing.T) {
	long := strings.Repeat("x", 3*maxLine)
	got := collect(t, "a\n"+long+"\nb\n"+long)
	if want := []string{"a", "b"}; !reflect.DeepEqual(got.lines, want) || got.tooLong != 2 {
		t.Fatalf("got %q and %d too long", got.lines, got.tooLong)
	}
}

func TestAnalyzeFixture(t *testing.T) {
	res, err := Analyze(Options{Dir: "fixture", Top: 5})
	if err != nil {
		t.Fatal(err)
	}
	if res.Requests != 16 || res.Errors != 3 || res.Malformed != 5 {
		t.Fatalf("got %+v", res)
	}
}
