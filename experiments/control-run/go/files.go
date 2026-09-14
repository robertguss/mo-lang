package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// maxLine bounds one line; a longer line is malformed and skipped.
const maxLine = 64 * 1024

// ErrNoLogs is returned when <dir> holds no .log file.
var ErrNoLogs = errors.New("no .log file found")

// Analyze reads every .log file in opts.Dir, one file at a time, through
// an os.Root so no path can resolve outside the directory.
func Analyze(opts Options) (Result, error) {
	root, err := os.OpenRoot(opts.Dir)
	if err != nil {
		return Result{}, fmt.Errorf("cannot open directory: %w", err)
	}
	defer root.Close()
	names, err := LogNames(root)
	if err != nil {
		return Result{}, err
	}
	if len(names) == 0 {
		return Result{}, ErrNoLogs
	}
	return summarize(root, names, opts)
}

func summarize(root *os.Root, names []string, opts Options) (Result, error) {
	s, err := NewSummary(opts.Top)
	if err != nil {
		return Result{}, err
	}
	visit := lineVisitor(s, opts)
	for _, name := range names {
		if err := scanLog(root, name, visit); err != nil {
			return Result{}, fmt.Errorf("reading %q: %w", name, err)
		}
	}
	return s.Result()
}

// LogNames lists the regular files named *.log directly inside root, in
// byte order of their names. Directories and symlinks are skipped.
func LogNames(root *os.Root) ([]string, error) {
	dir, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer dir.Close()
	entries, err := dir.ReadDir(-1)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if isLogName(e.Name()) && e.Type().IsRegular() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}

func isLogName(name string) bool {
	ok, err := filepath.Match("*.log", name)
	return err == nil && ok
}

// CheckName requires a plain file name: no separator, not . or ..
func CheckName(name string) error {
	if name == "" || name == "." || name == ".." || strings.ContainsAny(name, `/\`) {
		return broken("%q is not a plain file name", name)
	}
	return nil
}

func scanLog(root *os.Root, name string, visit func([]byte, bool) error) error {
	if err := CheckName(name); err != nil {
		return err
	}
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() {
		return broken("%q is not a regular file", name)
	}
	return eachLine(f, visit)
}

func lineVisitor(s *Summary, opts Options) func([]byte, bool) error {
	return func(line []byte, tooLong bool) error {
		if tooLong {
			s.AddMalformed()
			return nil
		}
		r, err := ParseLine(string(line))
		if err != nil {
			s.AddMalformed()
			return nil
		}
		if opts.HasSince && r.At.Before(opts.Since) {
			return nil
		}
		return s.Add(r)
	}
}

// eachLine calls visit once per line without its "\n" or "\r\n". A line
// longer than maxLine is discarded and visited as tooLong.
func eachLine(r io.Reader, visit func(line []byte, tooLong bool) error) error {
	br := bufio.NewReaderSize(r, maxLine)
	for {
		line, err := br.ReadSlice('\n')
		switch {
		case errors.Is(err, bufio.ErrBufferFull):
			if err := skipRest(br); err != nil {
				return err
			}
			err = visit(nil, true)
		case errors.Is(err, io.EOF):
			if len(line) == 0 {
				return nil
			}
			return visit(trimEOL(line), false)
		case err != nil:
			return err
		default:
			err = visit(trimEOL(line), false)
		}
		if err != nil {
			return err
		}
	}
}

func skipRest(br *bufio.Reader) error {
	for {
		_, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			continue
		}
		if errors.Is(err, io.EOF) {
			return nil
		}
		return err
	}
}

func trimEOL(line []byte) []byte {
	if n := len(line); n > 0 && line[n-1] == '\n' {
		line = line[:n-1]
	}
	if n := len(line); n > 0 && line[n-1] == '\r' {
		line = line[:n-1]
	}
	return line
}
