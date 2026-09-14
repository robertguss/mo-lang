// Command jobq is a durable job queue with an HTTP API.
package main

import (
	"fmt"
	"io"
	"os"
)

const usage = "usage: jobq serve <dir> [--port N] | jobq compact <dir> | " +
	"jobq client <host> <port> <token> <method> <path> [<json>] | jobq check <dir> <script>"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		return usageError(stderr, "no command")
	}
	switch args[0] {
	case "serve":
		return cmdServe(args[1:], stderr)
	case "compact":
		return cmdCompact(args[1:], stderr)
	case "client":
		return cmdClient(args[1:], stdout, stderr)
	case "check":
		return cmdCheck(args[1:], stdout, stderr)
	}
	return usageError(stderr, "unknown command "+args[0])
}

// usageError prints one line to stderr and returns exit code 2.
func usageError(stderr io.Writer, msg string) int {
	fmt.Fprintf(stderr, "jobq: %s; %s\n", msg, usage)
	return 2
}
