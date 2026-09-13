// Command logstat summarizes a directory of request logs.
//
//	logstat <dir> [--top N] [--since <ISO-8601>] [--json]
//
// Exit code 0 on success, 2 on a usage error, 1 if no .log file was found or
// a file could not be read.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the whole program, with its streams passed in so tests can call it.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := ParseArgs(args)
	if err != nil {
		fail(stderr, fmt.Sprintf("logstat: %v (%s)", err, Usage))
		return 2
	}
	sum, err := Analyze(opts)
	if err != nil {
		reportAnalyzeError(stderr, opts.Dir, err)
		return 1
	}
	out := bufio.NewWriter(stdout)
	if opts.JSON {
		err = WriteJSON(out, sum)
	} else {
		err = WriteText(out, sum)
	}
	if err == nil {
		err = out.Flush()
	}
	if err != nil {
		fail(stderr, fmt.Sprintf("logstat: writing output: %v", err))
		return 1
	}
	return 0
}

func reportAnalyzeError(stderr io.Writer, dir string, err error) {
	if errors.Is(err, ErrNoLogs) {
		fail(stderr, fmt.Sprintf("logstat: no .log file found in %s", dir))
		return
	}
	fail(stderr, fmt.Sprintf("logstat: %v", err))
}

// fail prints one line to stderr, redacted like stdout. A failed write to
// stderr has nowhere left to be reported.
func fail(stderr io.Writer, msg string) {
	_, _ = fmt.Fprintln(stderr, Redact(msg))
}
