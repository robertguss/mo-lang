// Command logstat summarizes the *.log files in one directory.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"
)

// Exit codes.
const (
	ExitOK     = 0
	ExitNoLogs = 1
	ExitUsage  = 2
)

const usageLine = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

// Options are the parsed command-line arguments.
type Options struct {
	Dir   string
	Top   int
	Since *time.Time
	JSON  bool
}

// UsageError is any problem with the command line.
type UsageError struct{ Reason string }

func (e *UsageError) Error() string { return usageLine + ": " + e.Reason }

func usage(format string, args ...any) error {
	return &UsageError{Reason: fmt.Sprintf(format, args...)}
}

// ParseArgs requires exactly one <dir>, --top N with N in 1 to 100, an
// RFC 3339 --since, and no flag given twice. Flags may come in any order.
func ParseArgs(args []string) (Options, error) {
	opts := Options{Top: 5}
	seen := map[string]bool{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if seen[a] {
			return Options{}, usage("%s given twice", a)
		}
		switch a {
		case "--json":
			opts.JSON, seen[a] = true, true
		case "--top", "--since":
			if i+1 >= len(args) {
				return Options{}, usage("%s needs a value", a)
			}
			i++
			if err := setValue(&opts, a, args[i]); err != nil {
				return Options{}, err
			}
			seen[a] = true
		default:
			if err := setDir(&opts, a); err != nil {
				return Options{}, err
			}
		}
	}
	if opts.Dir == "" {
		return Options{}, usage("missing <dir>")
	}
	return opts, nil
}

func setValue(opts *Options, flag, value string) error {
	if flag == "--since" {
		t, err := ParseTimestamp(value)
		if err != nil {
			return usage("--since must be an RFC 3339 timestamp, got %q", value)
		}
		opts.Since = &t
		return nil
	}
	n, err := strconv.Atoi(value)
	if err != nil || n < MinTop || n > MaxTop {
		return usage("--top must be %d to %d, got %q", MinTop, MaxTop, value)
	}
	opts.Top = n
	return nil
}

func setDir(opts *Options, a string) error {
	if len(a) > 1 && a[0] == '-' {
		return usage("unknown flag %q", a)
	}
	if opts.Dir != "" || a == "" {
		return usage("want exactly one non-empty <dir>")
	}
	opts.Dir = a
	return nil
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the whole program with its streams injected; it returns the exit code.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := ParseArgs(args)
	if err != nil {
		return fail(stderr, ExitUsage, err)
	}
	s, err := summarize(opts)
	if err != nil {
		return fail(stderr, ExitNoLogs, err)
	}
	out := RenderText(s)
	if opts.JSON {
		if out, err = RenderJSON(s); err != nil {
			return fail(stderr, ExitNoLogs, err)
		}
	}
	if _, err := io.WriteString(stdout, out); err != nil {
		return fail(stderr, ExitNoLogs, err)
	}
	return ExitOK
}

// ErrNoLogs is returned when the directory holds no *.log file.
var ErrNoLogs = errors.New("no .log file found")

func summarize(opts Options) (s Summary, err error) {
	root, err := os.OpenRoot(opts.Dir)
	if err != nil {
		return Summary{}, err
	}
	defer func() {
		if cerr := root.Close(); err == nil && cerr != nil {
			s, err = Summary{}, cerr
		}
	}()
	names, err := ListLogs(root)
	if err != nil {
		return Summary{}, err
	}
	if len(names) == 0 {
		return Summary{}, fmt.Errorf("%w in %s", ErrNoLogs, opts.Dir)
	}
	acc, err := NewAccumulator(opts.Top, opts.Since)
	if err != nil {
		return Summary{}, err
	}
	for _, name := range names {
		if err := ReadLog(root, name, acc); err != nil {
			return Summary{}, fmt.Errorf("%s: %w", name, err)
		}
	}
	return acc.Summary()
}

func fail(stderr io.Writer, code int, err error) int {
	// A failed write to stderr leaves nothing better to do; the code still reports it.
	_, _ = fmt.Fprintf(stderr, "logstat: %v\n", err)
	return code
}
