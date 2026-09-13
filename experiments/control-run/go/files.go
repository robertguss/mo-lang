package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"
)

// ErrNoLogs means <dir> holds no .log file; the program exits 1 on it.
var ErrNoLogs = errors.New("no .log file found")

// MaxLine is the longest line read, in bytes; a longer line is malformed.
const MaxLine = 64 * 1024

// Analyze reads every *.log file directly inside dir, in name order, one
// file at a time, and returns the summary.
//
// All reads go through an os.Root, so no path can resolve outside dir, and
// only regular files are read: a symlink, even to a file inside dir, is
// skipped.
func Analyze(opts Options) (Summary, error) {
	c, err := NewCollector(opts.Top, opts.Since, opts.HasSince)
	if err != nil {
		return Summary{}, err
	}
	root, err := os.OpenRoot(opts.Dir)
	if err != nil {
		return Summary{}, err
	}
	defer root.Close()
	names, err := LogFiles(root)
	if err != nil {
		return Summary{}, err
	}
	for _, name := range names {
		if err := readLog(root, name, c); err != nil {
			return Summary{}, err
		}
	}
	return c.Summary()
}

// LogFiles lists the regular files named *.log directly inside root, sorted
// by name (byte order). It returns ErrNoLogs when there are none.
func LogFiles(root *os.Root) ([]string, error) {
	d, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer d.Close()
	entries, err := d.ReadDir(-1)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.Type().IsRegular() && strings.HasSuffix(e.Name(), ".log") {
			names = append(names, e.Name())
		}
	}
	if len(names) == 0 {
		return nil, ErrNoLogs
	}
	slices.Sort(names)
	return names, nil
}

func readLog(root *os.Root, name string, c *Collector) error {
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%s changed into a non-regular file while reading", name)
	}
	err = EachLine(f, c.AddLine, c.AddMalformed)
	if err != nil {
		return fmt.Errorf("reading %s: %w", name, err)
	}
	return nil
}

// EachLine calls line for every line of r, without its "\n" or "\r\n", and
// tooLong for every line longer than MaxLine bytes. A final line with no
// newline is still a line; the empty text after a final newline is not.
func EachLine(r io.Reader, line func(string), tooLong func()) error {
	br := bufio.NewReaderSize(r, MaxLine)
	for {
		chunk, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			if err := skipLine(br); err != nil {
				return err
			}
			tooLong()
			continue
		}
		if len(chunk) > 0 {
			line(trimLineEnd(chunk))
		}
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

// skipLine discards the rest of a line whose start filled the buffer.
func skipLine(br *bufio.Reader) error {
	for {
		_, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			continue
		}
		if err == nil || errors.Is(err, io.EOF) {
			return nil
		}
		return err
	}
}

func trimLineEnd(chunk []byte) string {
	s := strings.TrimSuffix(string(chunk), "\n")
	return strings.TrimSuffix(s, "\r")
}
