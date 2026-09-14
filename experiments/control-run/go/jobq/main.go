// Command jobq is a durable job queue with an HTTP API.
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const usage = "usage: jobq serve <dir> [--port N] | jobq compact <dir> | " +
	"jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"

const defaultPort = 7900

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run dispatches: exit 2 on a usage error, 1 when <dir> cannot be opened or
// the port cannot be bound.
func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		return failf(stderr, 2, "missing command; %s", usage)
	}
	rest := args[1:]
	switch args[0] {
	case "serve":
		dir, port, err := parseServe(rest)
		if err != nil {
			return failf(stderr, 2, "%v; %s", err, usage)
		}
		return cmdServe(dir, port, stdout, stderr)
	case "compact":
		if len(rest) != 1 {
			return failf(stderr, 2, "compact takes <dir>; %s", usage)
		}
		return cmdCompact(rest[0], stdout, stderr)
	case "client":
		if len(rest) != 5 && len(rest) != 6 {
			return failf(stderr, 2, "client takes <host> <port> <token> <method> <path> [<json>]; %s", usage)
		}
		port, err := parsePort(rest[1])
		if err != nil {
			return failf(stderr, 2, "%v; %s", err, usage)
		}
		if !strings.HasPrefix(rest[4], "/") {
			return failf(stderr, 2, "path must start with /, got %q; %s", rest[4], usage)
		}
		body := ""
		if len(rest) == 6 {
			body = rest[5]
		}
		return cmdClient(rest[0], port, rest[2], rest[3], rest[4], body, stdout, stderr)
	case "check":
		if len(rest) != 2 {
			return failf(stderr, 2, "check takes <dir> <script>; %s", usage)
		}
		return cmdCheck(rest[0], rest[1], stdout, stderr)
	}
	return failf(stderr, 2, "unknown command %q; %s", args[0], usage)
}

func parseServe(args []string) (string, int, error) {
	dir, port, portSeen := "", defaultPort, false
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--port":
			if portSeen || i+1 >= len(args) {
				return "", 0, fmt.Errorf("--port wants one value")
			}
			i++
			p, err := parsePort(args[i])
			if err != nil {
				return "", 0, err
			}
			port, portSeen = p, true
		case strings.HasPrefix(args[i], "-"):
			return "", 0, fmt.Errorf("unknown flag %q", args[i])
		case dir != "":
			return "", 0, fmt.Errorf("more than one <dir>")
		default:
			dir = args[i]
		}
	}
	if dir == "" {
		return "", 0, fmt.Errorf("serve takes <dir>")
	}
	return dir, port, nil
}

// parsePort reads 0 to 65535; 0 asks the system for a free port.
func parsePort(s string) (int, error) {
	p, err := strconv.Atoi(s)
	if err != nil || p < 0 || p > 65535 {
		return 0, fmt.Errorf("port must be 0 to 65535, got %q", s)
	}
	return p, nil
}

// failf prints one line to stderr and returns the exit code.
func failf(stderr io.Writer, code int, format string, args ...any) int {
	msg := strings.ReplaceAll(fmt.Sprintf(format, args...), "\n", " ")
	_, _ = fmt.Fprintf(stderr, "jobq: %s\n", msg)
	return code
}
