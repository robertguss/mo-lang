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

// maxLine is the longest line kept, newline included; longer lines are malformed.
const maxLine = 64 * 1024

// ErrNoLogs reports that <dir> holds no *.log file.
var ErrNoLogs = errors.New("no .log file found")

// LogFiles lists the regular files named *.log directly inside root, in
// byte order of name. Symlinks and directories are skipped, so nothing
// outside root is ever listed; root.Open would refuse an escape regardless.
func LogFiles(root *os.Root) ([]string, error) {
	dir, err := root.Open(".")
	if err != nil {
		return nil, fmt.Errorf("cannot open directory: %w", err)
	}
	entries, readErr := dir.ReadDir(-1)
	if err := errors.Join(readErr, dir.Close()); err != nil {
		return nil, fmt.Errorf("cannot list directory: %w", err)
	}
	var names []string
	for _, e := range entries {
		if e.Type().IsRegular() && strings.HasSuffix(e.Name(), ".log") {
			names = append(names, e.Name())
		}
	}
	slices.Sort(names)
	return names, nil
}

// ScanFile feeds every line of the named file inside root to acc, holding
// at most one line in memory.
func ScanFile(root *os.Root, name string, acc *Accumulator) (err error) {
	f, err := root.Open(name)
	if err != nil {
		return fmt.Errorf("cannot open %q: %w", name, err)
	}
	defer func() {
		if closeErr := f.Close(); closeErr != nil && err == nil {
			err = fmt.Errorf("cannot close %q: %w", name, closeErr)
		}
	}()
	if err := scanLines(f, acc); err != nil {
		return fmt.Errorf("cannot read %q: %w", name, err)
	}
	return nil
}

// scanLines splits r on '\n'. A final line without a newline still counts;
// a line longer than maxLine counts once as malformed and is skipped.
func scanLines(r io.Reader, acc *Accumulator) error {
	br := bufio.NewReaderSize(r, maxLine)
	for {
		chunk, err := br.ReadSlice('\n')
		switch {
		case err == nil:
			acc.AddLine(string(chunk[:len(chunk)-1]))
		case errors.Is(err, bufio.ErrBufferFull):
			acc.AddMalformed()
			done, skipErr := skipLine(br)
			if skipErr != nil || done {
				return skipErr
			}
		case errors.Is(err, io.EOF):
			if len(chunk) > 0 {
				acc.AddLine(string(chunk))
			}
			return nil
		default:
			return err
		}
	}
}

// skipLine discards the rest of an over-long line; done reports end of input.
func skipLine(br *bufio.Reader) (done bool, err error) {
	for {
		_, err := br.ReadSlice('\n')
		switch {
		case err == nil:
			return false, nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		case errors.Is(err, io.EOF):
			return true, nil
		default:
			return true, err
		}
	}
}
