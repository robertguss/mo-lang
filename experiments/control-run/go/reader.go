package main

import (
	"bufio"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// MaxLineBytes is the longest line kept; longer lines are malformed and are
// skipped without being held in memory.
const MaxLineBytes = 64 * 1024

// ErrOutside is returned for a name that would leave the directory.
var ErrOutside = errors.New("name is not directly inside the directory")

// ListLogs returns the regular files named *.log directly inside root, in
// byte-wise name order. Directories, symlinks and other entries are skipped.
func ListLogs(root *os.Root) ([]string, error) {
	entries, err := fs.ReadDir(root.FS(), ".")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.Type().IsRegular() && len(e.Name()) > len(".log") && strings.HasSuffix(e.Name(), ".log") {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

// CheckInside requires name to be a single local path element.
func CheckInside(name string) error {
	if !filepath.IsLocal(name) || filepath.Base(name) != name || strings.ContainsAny(name, `/\`) {
		return ErrOutside
	}
	return nil
}

// ReadLog streams one file from root into acc, one line at a time. The
// os.Root refuses any path, symlink included, that resolves outside it.
func ReadLog(root *os.Root, name string, acc *Accumulator) (err error) {
	if err := CheckInside(name); err != nil {
		return err
	}
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := f.Close(); err == nil {
			err = cerr
		}
	}()
	return ScanLines(f, func(line string, ok bool) {
		if ok {
			acc.AddLine(line)
		} else {
			acc.AddMalformed()
		}
	})
}

// ScanLines calls emit for every line of r without its "\n" or "\r\n".
// ok is false for a line longer than MaxLineBytes. A final line without a
// newline still counts.
func ScanLines(r io.Reader, emit func(line string, ok bool)) error {
	br := bufio.NewReaderSize(r, MaxLineBytes)
	buf := make([]byte, 0, 256)
	tooLong := false
	for {
		chunk, more, err := br.ReadLine()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if !tooLong && len(buf)+len(chunk) > MaxLineBytes {
			tooLong, buf = true, buf[:0]
		}
		if !tooLong {
			buf = append(buf, chunk...)
		}
		if more {
			continue
		}
		emit(string(buf), !tooLong)
		buf, tooLong = buf[:0], false
	}
}
