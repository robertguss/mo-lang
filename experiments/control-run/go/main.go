// Command logstat summarizes the *.log files in a directory: requests,
// errors, malformed lines, requests per minute, the slowest requests and
// the busiest routes.
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

const usage = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

const (
	exitOK      = 0
	exitFailure = 1
	exitUsage   = 2
)

type options struct {
	dir   string
	top   int
	since *time.Time
	json  bool
}

// usageError is a bad command line: exit 2, one line on stderr.
type usageError struct {
	msg string
}

func (e *usageError) Error() string {
	return e.msg
}

func usagef(format string, args ...any) error {
	return &usageError{msg: fmt.Sprintf(format, args...)}
}

// parseArgs reads the command line without the program name. Flags may
// come before or after <dir>, each at most once.
//
//	requires: exactly one <dir>
//	requires: --top is a whole number in 1..100
//	requires: --since is an RFC 3339 timestamp
func parseArgs(args []string) (options, error) {
	opts := options{top: defaultTop}
	seen := map[string]bool{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			if opts.dir != "" {
				return options{}, usagef("more than one <dir>")
			}
			opts.dir = arg
			continue
		}
		if seen[arg] {
			return options{}, usagef("%s given twice", arg)
		}
		seen[arg] = true
		next, err := parseFlag(args, i, &opts)
		if err != nil {
			return options{}, err
		}
		i = next
	}
	if opts.dir == "" {
		return options{}, usagef("missing <dir>")
	}
	return opts, nil
}

// parseFlag applies the flag at args[i] and returns the index of the last
// argument it consumed.
func parseFlag(args []string, i int, opts *options) (int, error) {
	switch args[i] {
	case "--json":
		opts.json = true
		return i, nil
	case "--top", "--since":
		if i+1 >= len(args) {
			return i, usagef("%s needs a value", args[i])
		}
		return i + 1, setValue(args[i], args[i+1], opts)
	default:
		return i, usagef("unknown flag %q", args[i])
	}
}

func setValue(flag, value string, opts *options) error {
	if flag == "--top" {
		n, err := strconv.Atoi(value)
		if err != nil {
			return usagef("--top %q is not a whole number", value)
		}
		if n < minTop || n > maxTop {
			return usagef("--top %d outside %d..%d", n, minTop, maxTop)
		}
		opts.top = n
		return nil
	}
	t, err := parseTimestamp(value)
	if err != nil {
		return usagef("--since %q is not an RFC 3339 timestamp", value)
	}
	opts.since = &t
	return nil
}

// run is main without the process around it: it returns the exit code.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := parseArgs(args)
	if err != nil {
		complain(stderr, err.Error()+"; "+usage)
		return exitUsage
	}
	sum, err := analyze(opts.dir, opts.top, opts.since)
	if err != nil {
		complain(stderr, err.Error())
		return exitFailure
	}
	out, err := render(sum, opts.json)
	if err != nil {
		complain(stderr, err.Error())
		return exitFailure
	}
	if _, err := io.WriteString(stdout, out); err != nil {
		complain(stderr, "writing stdout: "+err.Error())
		return exitFailure
	}
	return exitOK
}

func render(s Summary, asJSON bool) (string, error) {
	if asJSON {
		return renderJSON(s)
	}
	return renderText(s), nil
}

// complain prints one line to stderr. If stderr itself fails there is
// nowhere left to report that, so its error is deliberately dropped.
func complain(stderr io.Writer, msg string) {
	_, _ = fmt.Fprintf(stderr, "logstat: %s\n", msg)
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
