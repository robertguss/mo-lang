// Command logstat summarizes the *.log files directly inside a directory.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"controlrun/contract"
)

const usage = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

// maxLine is the longest line read; a longer one is counted as malformed.
const maxLine = 64 * 1024

type options struct {
	dir   string
	top   int
	since time.Time
	json  bool
}

type usageError struct{ msg string }

func (e *usageError) Error() string { return e.msg }

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	opts, err := parseArgs(args)
	if err != nil {
		fmt.Fprintf(stderr, "logstat: %v; %s\n", err, usage)
		return 2
	}
	report, code, err := analyze(opts)
	if err != nil {
		fmt.Fprintf(stderr, "logstat: %v\n", err)
		return code
	}
	if opts.json {
		err = WriteJSON(stdout, report)
	} else {
		err = WriteText(stdout, report)
	}
	if err != nil {
		fmt.Fprintf(stderr, "logstat: writing output: %v\n", err)
		return 1
	}
	return 0
}

func parseArgs(args []string) (options, error) {
	opts := options{top: 5}
	seen := map[string]bool{}
	var positional []string
	for i := 0; i < len(args); i++ {
		name, value, hasValue := strings.Cut(args[i], "=")
		if !strings.HasPrefix(name, "--") {
			positional = append(positional, args[i])
			continue
		}
		if seen[name] {
			return opts, &usageError{name + " given twice"}
		}
		seen[name] = true
		if name == "--json" {
			if hasValue {
				return opts, &usageError{"--json takes no value"}
			}
			opts.json = true
			continue
		}
		if name != "--top" && name != "--since" {
			return opts, &usageError{"unknown option " + name}
		}
		if !hasValue {
			if i+1 >= len(args) {
				return opts, &usageError{name + " needs a value"}
			}
			i++
			value = args[i]
		}
		if err := setOption(&opts, name, value); err != nil {
			return opts, err
		}
	}
	if len(positional) != 1 {
		return opts, &usageError{"want exactly one <dir>"}
	}
	opts.dir = positional[0]
	return opts, nil
}

func setOption(opts *options, name, value string) error {
	if name == "--since" {
		t, err := time.Parse(time.RFC3339Nano, value)
		if err != nil {
			return &usageError{"--since is not an ISO-8601 timestamp with a zone: " + strconv.Quote(value)}
		}
		opts.since = t
		return nil
	}
	n, err := strconv.Atoi(value)
	if err != nil || !allDigits(value) {
		return &usageError{"--top is not a whole number: " + strconv.Quote(value)}
	}
	if err := contract.Require(n >= 1 && n <= 100, "top >= 1 && top <= 100"); err != nil {
		return &usageError{"--top " + value + ": " + err.Error()}
	}
	opts.top = n
	return nil
}

// analyze reads every *.log file in opts.dir, one at a time, through an
// os.Root so no path can resolve outside the directory. It returns the exit
// code to use when it fails.
func analyze(opts options) (Report, int, error) {
	info, err := os.Stat(opts.dir)
	if err != nil || !info.IsDir() {
		return Report{}, 2, &usageError{"<dir> is not a directory: " + opts.dir}
	}
	root, err := os.OpenRoot(opts.dir)
	if err != nil {
		return Report{}, 1, err
	}
	defer root.Close()
	names, err := logFiles(root)
	if err != nil {
		return Report{}, 1, err
	}
	if len(names) == 0 {
		return Report{}, 1, errors.New("no .log file found in " + opts.dir)
	}
	sum, err := NewSummary(opts.top)
	if err != nil {
		return Report{}, 1, err
	}
	for _, name := range names {
		if err := readLog(root, name, opts.since, sum); err != nil {
			return Report{}, 1, err
		}
	}
	report, err := sum.Report()
	if err != nil {
		return Report{}, 1, err
	}
	return report, 0, nil
}

// logFiles lists the regular *.log files directly inside root, in name
// order. Symlinks and directories are skipped.
func logFiles(root *os.Root) ([]string, error) {
	entries, err := fs.ReadDir(root.FS(), ".")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if e.Type().IsRegular() && strings.HasSuffix(e.Name(), ".log") {
			names = append(names, e.Name())
		}
	}
	return names, nil
}

func readLog(root *os.Root, name string, since time.Time, sum *Summary) error {
	if err := contract.Require(filepath.Base(name) == name && name != ".." && strings.HasSuffix(name, ".log"),
		"name is a bare *.log file name"); err != nil {
		return err
	}
	f, err := root.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	err = eachLine(f, func(line string, tooLong bool) error {
		if tooLong {
			sum.AddMalformed()
			return nil
		}
		rec, err := ParseLine(line)
		var bad *MalformedError
		if errors.As(err, &bad) {
			sum.AddMalformed()
			return nil
		}
		if err != nil {
			return err
		}
		if !since.IsZero() && rec.At.Before(since) {
			return nil
		}
		return sum.Add(rec)
	})
	if err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	return nil
}

// eachLine calls fn for every line of r without its "\n" or "\r\n". A line
// longer than maxLine is passed as tooLong with no text and skipped to its end.
func eachLine(r io.Reader, fn func(line string, tooLong bool) error) error {
	br := bufio.NewReaderSize(r, maxLine)
	for {
		chunk, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			if err := skipRest(br); err != nil {
				return err
			}
			if err := fn("", true); err != nil {
				return err
			}
			continue
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if len(chunk) > 0 {
			line := bytes.TrimSuffix(bytes.TrimSuffix(chunk, []byte("\n")), []byte("\r"))
			if ferr := fn(string(line), false); ferr != nil {
				return ferr
			}
		}
		if err != nil {
			return nil
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
