package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

// errNoLogFiles is exit code 1.
var errNoLogFiles = errors.New("no .log file found")

// maxLine is the longest line read; a longer one is malformed.
const maxLine = 64 << 10

// AnalyzeDir feeds every *.log file directly inside dir, in name order, to
// agg, one file at a time. All opens go through an os.Root, so a symlink or
// a name cannot reach a file outside dir.
func AnalyzeDir(dir string, agg *Aggregator) error {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer func() { _ = root.Close() }() // read-only: nothing to lose on close
	names, err := logFiles(root)
	if err != nil {
		return err
	}
	if len(names) == 0 {
		return errNoLogFiles
	}
	for _, name := range names {
		if err := analyzeFile(root, name, agg); err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
	}
	return nil
}

// logFiles lists the regular files named *.log, not hidden, sorted by name.
// Symlinks are skipped even when they stay inside the directory.
func logFiles(root *os.Root) ([]string, error) {
	d, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer func() { _ = d.Close() }()
	entries, err := d.ReadDir(-1)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		name := e.Name()
		if e.Type().IsRegular() && strings.HasSuffix(name, ".log") && !strings.HasPrefix(name, ".") {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names, nil
}

func analyzeFile(root *os.Root, name string, agg *Aggregator) error {
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	return eachLine(f, agg.AddLine, agg.AddMalformed)
}

// eachLine calls onLine for every line without its "\n", and onTooLong for
// a line longer than maxLine, which it skips without holding it.
func eachLine(r io.Reader, onLine func(string) error, onTooLong func()) error {
	br := bufio.NewReaderSize(r, maxLine)
	tooLong := false
	for {
		chunk, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			tooLong = true
			continue
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		atEOF := err != nil
		if len(chunk) > 0 || !atEOF || tooLong {
			if tooLong {
				onTooLong()
			} else if lerr := onLine(strings.TrimSuffix(string(chunk), "\n")); lerr != nil {
				return lerr
			}
		}
		tooLong = false
		if atEOF {
			return nil
		}
	}
}
