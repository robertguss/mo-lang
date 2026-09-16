package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// checkEpoch is where `jobq check`'s clock starts, so its output is the same
// on every run.
var checkEpoch = time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)

// step is one script line: a request, `clock +<ms>`, `restart` (stop and
// start the service), or `crash` (the next write the board applies fails, and
// the board restarts itself).
type step struct {
	raw                          string
	kind                         string
	advance                      time.Duration
	token, method, path, payload string
}

func parseScript(text string) ([]step, error) {
	var steps []step
	for n, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		s, err := parseStep(line)
		if err != nil {
			return nil, fmt.Errorf("script line %d: %v", n+1, err)
		}
		steps = append(steps, s)
	}
	return steps, nil
}

func parseStep(line string) (step, error) {
	if line == "restart" || line == "crash" {
		return step{raw: line, kind: line}, nil
	}
	if ms, ok := strings.CutPrefix(line, "clock +"); ok {
		n, err := strconv.ParseInt(ms, 10, 64)
		if err != nil || n < 0 {
			return step{}, fmt.Errorf("clock takes +<ms>")
		}
		return step{raw: line, kind: "clock", advance: time.Duration(n) * time.Millisecond}, nil
	}
	token, rest, _ := strings.Cut(line, " ")
	method, rest, _ := strings.Cut(rest, " ")
	path, payload, _ := strings.Cut(rest, " ")
	if token == "" || !validMethod(method) || !strings.HasPrefix(path, "/") {
		return step{}, fmt.Errorf("want <token> <method> <path> [<json>]")
	}
	return step{raw: line, kind: "request", token: token, method: method, path: path, payload: strings.TrimSpace(payload)}, nil
}

func cmdCheck(args []string, stdout, stderr io.Writer) int {
	if len(args) != 2 {
		return usageError(stderr, "check takes <dir> <script>")
	}
	text, err := os.ReadFile(args[1])
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	steps, err := parseScript(string(text))
	if err != nil {
		return usageError(stderr, err.Error())
	}
	if err := runCheck(args[0], steps, stdout); err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	return 0
}

// runCheck serves dir on a free port with a manual clock and plays the steps
// through the client over a real socket.
func runCheck(dir string, steps []step, out io.Writer) error {
	clock := newManualClock(checkEpoch)
	start := func() (*service, error) {
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return nil, err
		}
		svc, err := startService(dir, clock, ln, idleTimeout)
		if err != nil {
			ln.Close()
		}
		return svc, err
	}
	svc, err := start()
	if err != nil {
		return err
	}
	client := newHTTPClient()
	for _, s := range steps {
		fmt.Fprintf(out, "> %s\n", s.raw)
		switch s.kind {
		case "clock":
			clock.Advance(s.advance)
		case "restart":
			client.CloseIdleConnections()
			if err := svc.stop(); err != nil {
				return err
			}
			if svc, err = start(); err != nil {
				return err
			}
		case "crash":
			svc.board.crashNext()
		case "request":
			status, body, err := doRequest(client, svc.addr, s.token, s.method, s.path, s.payload)
			if err != nil {
				_ = svc.stop()
				return err
			}
			printResponse(out, status, body)
			// A request the crash failed is followed by the restart; the
			// next line waits for it, so the output is the same on every run.
			ctx, cancel := context.WithTimeout(context.Background(), requestTimeout)
			ready := svc.board.waitReady(ctx)
			cancel()
			if !ready {
				_ = svc.stop()
				return fmt.Errorf("the service did not come back after a failure")
			}
		}
	}
	client.CloseIdleConnections()
	return svc.stop()
}
