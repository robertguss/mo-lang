// Command logstat summarizes the *.log files in one directory.
//
//	logstat <dir> [--top N] [--since <ISO-8601>] [--json]
package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

const (
	exitOK      = 0
	exitFailure = 1
	exitUsage   = 2
	usage       = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the whole program with its streams passed in, so tests can drive it.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := ParseArgs(args)
	if err != nil {
		report(stderr, err.Error()+"; "+usage)
		return exitUsage
	}
	sum, err := analyze(opts)
	if err != nil {
		report(stderr, err.Error())
		return exitFailure
	}
	out := RenderText(sum)
	if opts.JSON {
		out = RenderJSON(sum)
	}
	if _, err := io.WriteString(stdout, out); err != nil {
		report(stderr, "cannot write output: "+err.Error())
		return exitFailure
	}
	return exitOK
}

// analyze reads every *.log file in opts.Dir, one at a time, through an
// os.Root so no path can resolve outside the directory.
func analyze(opts Options) (sum Summary, err error) {
	root, err := os.OpenRoot(opts.Dir)
	if err != nil {
		return Summary{}, fmt.Errorf("cannot open directory: %w", err)
	}
	defer func() {
		if closeErr := root.Close(); closeErr != nil && err == nil {
			sum, err = Summary{}, fmt.Errorf("cannot close directory: %w", closeErr)
		}
	}()
	names, err := LogFiles(root)
	if err != nil {
		return Summary{}, err
	}
	if len(names) == 0 {
		return Summary{}, fmt.Errorf("%w in %q", ErrNoLogs, opts.Dir)
	}
	acc := NewAccumulator(opts.Top, opts.Since, opts.HasSince)
	for _, name := range names {
		if err := ScanFile(root, name, acc); err != nil {
			return Summary{}, err
		}
	}
	return acc.Summary()
}

// report writes one line to stderr. If stderr itself fails there is nowhere
// left to say so, and the exit code still carries the failure.
func report(w io.Writer, msg string) {
	msg = strings.NewReplacer("\n", " ", "\r", " ").Replace(msg)
	_, _ = fmt.Fprintf(w, "logstat: %s\n", msg)
}
