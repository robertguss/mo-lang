// Command logstat summarizes a directory of request logs.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

const usageLine = "usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]"

// Options are the parsed command line.
type Options struct {
	Dir      string
	Top      int
	Since    time.Time
	HasSince bool
	JSON     bool
}

// UsageError is a bad command line: exit 2, one line on stderr.
type UsageError string

func (e UsageError) Error() string { return string(e) }

func usage(format string, args ...any) error {
	return UsageError(fmt.Sprintf(format, args...))
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is the whole program: 0 on success, 2 on a usage error, 1 when no
// .log file was found or the directory could not be read.
func run(args []string, stdout, stderr io.Writer) int {
	opts, err := ParseArgs(args)
	if err != nil {
		fmt.Fprintf(stderr, "logstat: %s; %s\n", oneLine(err), usageLine)
		return 2
	}
	out, err := report(opts)
	if err == nil {
		_, err = io.WriteString(stdout, out)
	}
	if err != nil {
		fmt.Fprintf(stderr, "logstat: %s\n", oneLine(err))
		return 1
	}
	return 0
}

func report(opts Options) (string, error) {
	res, err := Analyze(opts)
	if err != nil {
		return "", err
	}
	out := RenderText(res)
	if opts.JSON {
		if out, err = RenderJSON(res); err != nil {
			return "", err
		}
	}
	if err := CheckOutput(out); err != nil {
		return "", err
	}
	return out, nil
}

func oneLine(err error) string {
	return strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return ' '
		}
		return r
	}, err.Error())
}

// ParseArgs reads `<dir> [--top N] [--since T] [--json]` in any order.
// Flags take `--flag value` or `--flag=value`; each may appear once.
func ParseArgs(args []string) (Options, error) {
	p := argParser{args: args, opts: Options{Top: defaultTop}, seen: map[string]bool{}}
	for p.i < len(p.args) {
		if err := p.step(); err != nil {
			return Options{}, err
		}
	}
	if p.opts.Dir == "" {
		return Options{}, usage("missing <dir>")
	}
	return p.opts, nil
}

type argParser struct {
	args []string
	i    int
	opts Options
	seen map[string]bool
}

func (p *argParser) step() error {
	arg := p.args[p.i]
	p.i++
	if !strings.HasPrefix(arg, "-") {
		return p.setDir(arg)
	}
	name, value, inline := strings.Cut(arg, "=")
	if p.seen[name] {
		return usage("%s given twice", name)
	}
	p.seen[name] = true
	switch name {
	case "--json":
		return p.setJSON(inline)
	case "--top", "--since":
		return p.setValued(name, value, inline)
	}
	return usage("unknown flag %q", arg)
}

func (p *argParser) setDir(arg string) error {
	if arg == "" {
		return usage("<dir> is empty")
	}
	if p.opts.Dir != "" {
		return usage("more than one <dir>: %q and %q", p.opts.Dir, arg)
	}
	p.opts.Dir = arg
	return nil
}

func (p *argParser) setJSON(inline bool) error {
	if inline {
		return usage("--json takes no value")
	}
	p.opts.JSON = true
	return nil
}

func (p *argParser) setValued(name, value string, inline bool) error {
	if !inline {
		if p.i >= len(p.args) {
			return usage("%s needs a value", name)
		}
		value = p.args[p.i]
		p.i++
	}
	if name == "--top" {
		return p.setTop(value)
	}
	return p.setSince(value)
}

func (p *argParser) setTop(value string) error {
	n, err := strconv.Atoi(value)
	if err != nil {
		return usage("--top %q is not a whole number", value)
	}
	if err := CheckTop(n); err != nil {
		return usage("--top %d is outside 1 to 100", n)
	}
	p.opts.Top = n
	return nil
}

func (p *argParser) setSince(value string) error {
	t, err := ParseTimestamp(value)
	if err != nil {
		return usage("--since %q is not an RFC 3339 timestamp", value)
	}
	p.opts.Since, p.opts.HasSince = t, true
	return nil
}

// isUsage reports whether err is a command-line error.
func isUsage(err error) bool {
	var u UsageError
	return errors.As(err, &u)
}
