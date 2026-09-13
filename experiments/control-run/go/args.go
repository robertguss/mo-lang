package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Usage is the one-line synopsis printed with every usage error.
const Usage = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

// Options is a parsed command line.
type Options struct {
	Dir      string
	Top      int
	Since    time.Time
	HasSince bool
	JSON     bool
}

// UsageError is a bad command line; the program exits 2 on it.
type UsageError struct{ Reason string }

func (e UsageError) Error() string { return e.Reason }

func usageError(format string, a ...any) error {
	return UsageError{Reason: fmt.Sprintf(format, a...)}
}

// ParseArgs parses the arguments after the program name. Flags may come
// before or after <dir>.
//
// Requires, each one a UsageError when broken:
//   - exactly one <dir>
//   - no unknown flag and no flag given twice
//   - --top and --since have a value
//   - --top is an integer from 1 to 100 (outside is an error, not a clamp)
//   - --since is an RFC 3339 timestamp
func ParseArgs(args []string) (Options, error) {
	opts := Options{Top: 5}
	seen := map[string]bool{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") {
			if opts.Dir != "" {
				return Options{}, usageError("unexpected second <dir> %q", a)
			}
			opts.Dir = a
			continue
		}
		if seen[a] {
			return Options{}, usageError("%s given twice", a)
		}
		seen[a] = true
		switch a {
		case "--json":
			opts.JSON = true
		case "--top", "--since":
			if i+1 >= len(args) {
				return Options{}, usageError("%s needs a value", a)
			}
			i++
			if err := setValue(&opts, a, args[i]); err != nil {
				return Options{}, err
			}
		default:
			return Options{}, usageError("unknown flag %q", a)
		}
	}
	if opts.Dir == "" {
		return Options{}, usageError("missing <dir>")
	}
	return opts, nil
}

func setValue(opts *Options, flag, value string) error {
	if flag == "--since" {
		t, err := time.Parse(time.RFC3339, value)
		if err != nil {
			return usageError("--since %q is not an ISO-8601 timestamp like 2026-09-12T10:00:00Z", value)
		}
		opts.Since, opts.HasSince = t, true
		return nil
	}
	n, err := strconv.Atoi(value)
	if err != nil || n < 1 || n > 100 {
		return usageError("--top %q is not a whole number from 1 to 100", value)
	}
	opts.Top = n
	return nil
}
