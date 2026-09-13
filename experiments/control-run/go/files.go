package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"strings"
	"time"
)

// maxLine is the longest line logstat reads, newline included. A longer
// line is malformed and skipped without buffering the rest of it.
const maxLine = 64 * 1024

var errNoLogFiles = errors.New("no .log file found")

// analyze tallies every *.log file directly inside dir, one file at a time.
// Every open goes through an os.Root, so no path or symlink can reach a
// file outside dir.
func analyze(dir string, top int, since *time.Time) (sum Summary, err error) {
	root, err := os.OpenRoot(dir)
	if err != nil {
		return Summary{}, err
	}
	defer func() {
		if cerr := root.Close(); cerr != nil && err == nil {
			err = cerr
		}
	}()
	names, err := logFileNames(root)
	if err != nil {
		return Summary{}, err
	}
	if len(names) == 0 {
		return Summary{}, fmt.Errorf("%w in %s", errNoLogFiles, dir)
	}
	tally, err := newTally(top, since)
	if err != nil {
		return Summary{}, err
	}
	for _, name := range names {
		if err := tallyFile(root, name, tally); err != nil {
			return Summary{}, err
		}
	}
	return tally.summary()
}

// logFileNames lists the *.log entries directly inside root, in name order
// (fs.ReadDir sorts by name). Directories are skipped.
func logFileNames(root *os.Root) ([]string, error) {
	entries, err := fs.ReadDir(root.FS(), ".")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".log") {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

// tallyFile streams the file name inside root into t.
func tallyFile(root *os.Root, name string, t *Tally) (err error) {
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := f.Close(); cerr != nil && err == nil {
			err = cerr
		}
	}()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%s: not a regular file", name)
	}
	return tallyReader(f, t)
}

// tallyReader feeds each line of r to t, holding at most maxLine bytes.
func tallyReader(r io.Reader, t *Tally) error {
	br := bufio.NewReaderSize(r, maxLine)
	for {
		chunk, err := br.ReadSlice('\n')
		switch {
		case err == nil:
			t.addLine(trimEOL(chunk))
		case errors.Is(err, bufio.ErrBufferFull):
			t.addMalformed()
			if err := skipLine(br); errors.Is(err, io.EOF) {
				return nil
			} else if err != nil {
				return err
			}
		case errors.Is(err, io.EOF):
			if len(chunk) > 0 {
				t.addLine(trimEOL(chunk))
			}
			return nil
		default:
			return err
		}
	}
}

// skipLine discards the rest of an over-long line: nil once past its
// newline, io.EOF if the file ends first.
func skipLine(br *bufio.Reader) error {
	for {
		_, err := br.ReadSlice('\n')
		if !errors.Is(err, bufio.ErrBufferFull) {
			return err
		}
	}
}

// trimEOL drops a trailing "\n" or "\r\n".
func trimEOL(b []byte) string {
	s := strings.TrimSuffix(string(b), "\n")
	return strings.TrimSuffix(s, "\r")
}
