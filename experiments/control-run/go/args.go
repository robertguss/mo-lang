package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	defaultTop = 5
	minTop     = 1
	maxTop     = 100
)

// Options is a parsed command line.
type Options struct {
	Dir      string
	Top      int
	Since    time.Time
	HasSince bool
	JSON     bool
}

// UsageError is a bad command line; logstat exits 2 on it.
type UsageError struct{ Msg string }

func (e *UsageError) Error() string { return e.Msg }

func usagef(format string, args ...any) error {
	return &UsageError{Msg: fmt.Sprintf(format, args...)}
}

// ParseArgs reads the arguments after the program name. Options may come
// before or after <dir>, as "--top N" or "--top=N"; each may appear once.
//
// Contract: --top outside 1..100 is a UsageError, never clamped.
func ParseArgs(args []string) (Options, error) {
	opts := Options{Top: defaultTop}
	seen := map[string]bool{}
	var dirs []string
	for i := 0; i < len(args); i++ {
		name, value, hasValue := strings.Cut(args[i], "=")
		if !strings.HasPrefix(args[i], "-") {
			dirs = append(dirs, args[i])
			continue
		}
		if seen[name] {
			return Options{}, usagef("%s given more than once", name)
		}
		seen[name] = true
		switch name {
		case "--json":
			if hasValue {
				return Options{}, usagef("--json takes no value")
			}
			opts.JSON = true
		case "--top", "--since":
			if !hasValue {
				if i+1 >= len(args) {
					return Options{}, usagef("%s needs a value", name)
				}
				i++
				value = args[i]
			}
			if err := setOption(&opts, name, value); err != nil {
				return Options{}, err
			}
		default:
			return Options{}, usagef("unknown option %q", args[i])
		}
	}
	return withDir(opts, dirs)
}

func withDir(opts Options, dirs []string) (Options, error) {
	switch {
	case len(dirs) == 0:
		return Options{}, usagef("missing <dir>")
	case len(dirs) > 1:
		return Options{}, usagef("expected one <dir>, got %d", len(dirs))
	case dirs[0] == "":
		return Options{}, usagef("<dir> is empty")
	}
	opts.Dir = dirs[0]
	return opts, nil
}

func setOption(opts *Options, name, value string) error {
	if name == "--top" {
		top, err := parseTop(value)
		opts.Top = top
		return err
	}
	since, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return usagef("--since %q is not an ISO-8601 timestamp like 2026-09-12T10:00:00Z", value)
	}
	opts.Since, opts.HasSince = since, true
	return nil
}

// parseTop accepts plain digits in 1..100.
func parseTop(value string) (int, error) {
	bad := usagef("--top %q must be a whole number from %d to %d", value, minTop, maxTop)
	if value == "" || !allDigits(value) {
		return 0, bad
	}
	n, err := strconv.Atoi(value)
	if err != nil || n < minTop || n > maxTop {
		return 0, bad
	}
	return n, nil
}
