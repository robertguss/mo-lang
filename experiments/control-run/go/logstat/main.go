// Command logstat summarizes the *.log files in one directory.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"logstat/contract"
)

const usage = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

type options struct {
	dir      string
	top      int
	since    time.Time
	hasSince bool
	json     bool
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the whole program: exit 0 on success, 2 on a usage error, 1 when no
// .log file was found or the directory or a file could not be read.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := parseArgs(args)
	if err != nil {
		return fail(stderr, 2, err.Error()+"; "+usage)
	}
	agg, err := NewAggregator(opts.top, opts.since, opts.hasSince)
	if err != nil {
		return fail(stderr, 2, "--top: "+err.Error()+"; "+usage)
	}
	if err := AnalyzeDir(opts.dir, agg); err != nil {
		return fail(stderr, 1, err.Error())
	}
	s, err := agg.Summary()
	if err != nil {
		return fail(stderr, 1, err.Error())
	}
	out := FormatText(s)
	if opts.json {
		if out, err = FormatJSON(s); err != nil {
			return fail(stderr, 1, err.Error())
		}
	}
	if err := contract.Ensure(!HasCardNumber(out), "!HasCardNumber(out)"); err != nil {
		return fail(stderr, 1, err.Error())
	}
	if _, err := io.WriteString(stdout, out); err != nil {
		return fail(stderr, 1, err.Error())
	}
	return 0
}

// fail prints one line to stderr and returns the exit code.
func fail(stderr io.Writer, code int, msg string) int {
	msg = strings.ReplaceAll(msg, "\n", " ")
	// If stderr is gone there is nowhere left to say so; the code still does.
	_, _ = fmt.Fprintf(stderr, "logstat: %s\n", msg)
	return code
}

// parseArgs reads `<dir> [--top N] [--since T] [--json]`, flags in any
// order, each at most once. Anything starting with "-" is a flag.
func parseArgs(args []string) (options, error) {
	opts := options{top: 5}
	seen := map[string]bool{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			if opts.dir != "" {
				return opts, fmt.Errorf("more than one directory: %q", arg)
			}
			opts.dir = arg
			continue
		}
		if seen[arg] {
			return opts, fmt.Errorf("%s given twice", arg)
		}
		seen[arg] = true
		switch arg {
		case "--json":
			opts.json = true
		case "--top", "--since":
			if i+1 >= len(args) {
				return opts, fmt.Errorf("%s needs a value", arg)
			}
			i++
			if err := setValue(&opts, arg, args[i]); err != nil {
				return opts, err
			}
		default:
			return opts, fmt.Errorf("unknown flag %q", arg)
		}
	}
	if opts.dir == "" {
		return opts, errors.New("missing <dir>")
	}
	return opts, nil
}

func setValue(opts *options, flag, value string) error {
	if flag == "--top" {
		n, err := strconv.Atoi(value)
		if err != nil {
			return fmt.Errorf("--top wants a whole number, got %q", value)
		}
		opts.top = n
		return nil
	}
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return fmt.Errorf("--since wants an ISO-8601 timestamp, got %q", value)
	}
	opts.since, opts.hasSince = t, true
	return nil
}
