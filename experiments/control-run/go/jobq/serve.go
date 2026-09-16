package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const defaultPort = 7900

// service is a board serving HTTP on a listener.
type service struct {
	board *Board
	srv   *http.Server
	addr  string
}

// openQueue replays <dir>/jobq.archive, then <dir>/jobq.log, into a new
// queue on clock, which archives after the default retain_ms.
func openQueue(dir string, clock Clock) (*Queue, *Store, error) {
	q := newQueue(clock)
	var archive *Store
	s, err := openLog(dir, func() (err error) {
		archive, err = openArchive(dir, q.applyArchived)
		return err
	}, q.applyRecord)
	if err == nil {
		q.archive = archive
		err = q.checkApart()
		if err != nil {
			err = errors.Join(err, s.Close(), q.closeArchive())
		}
	} else if archive != nil {
		_ = archive.Close()
	}
	if err != nil {
		return nil, nil, asIllFormed(dir, err)
	}
	q.finishReplay(s)
	return q, s, nil
}

// openBoard opens the queue in dir under a board that reopens it the same way.
func openBoard(dir string, clock Clock, cfg BoardConfig) (*Board, error) {
	return newBoard(func() (*Queue, *Store, error) {
		q, s, err := openQueue(dir, clock)
		if err == nil {
			q.retain = cfg.retain()
		}
		return q, s, err
	}, clock, cfg)
}

func newHTTPServer(h http.Handler, idle time.Duration) *http.Server {
	return &http.Server{
		Handler:           h,
		ReadHeaderTimeout: idle,
		IdleTimeout:       idle,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
		MaxHeaderBytes:    64 << 10,
	}
}

// startService serves the queue in dir on ln until stop.
func startService(dir string, clock Clock, ln net.Listener, idle time.Duration) (*service, error) {
	return startServiceWith(dir, clock, ln, idle, defaultBoardConfig())
}

func startServiceWith(dir string, clock Clock, ln net.Listener, idle time.Duration, cfg BoardConfig) (*service, error) {
	b, err := openBoard(dir, clock, cfg)
	if err != nil {
		return nil, err
	}
	svc := &service{board: b, srv: newHTTPServer(&API{b: b}, idle), addr: ln.Addr().String()}
	go func() { _ = svc.srv.Serve(ln) }()
	return svc, nil
}

// stop lets requests in flight finish, then closes the store under the
// queue's lock so no change is half made.
func (s *service) stop() error {
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := s.srv.Shutdown(ctx); err != nil {
		_ = s.srv.Close()
	}
	return s.board.stop(ctx)
}

func parsePort(s string) (int, bool) {
	n, err := strconv.Atoi(s)
	return n, err == nil && n >= 1 && n <= 65535 && s == strconv.Itoa(n)
}

// parseServe reads serve's arguments: <dir>, then each option at most once.
func parseServe(args []string) (dir string, port int, cfg BoardConfig, msg string) {
	port, cfg = defaultPort, defaultBoardConfig()
	if len(args) == 0 || len(args)%2 != 1 || strings.HasPrefix(args[0], "--") {
		return "", 0, cfg, "serve takes <dir> [--port N] [--max-restarts K] [--restart-window S] [--crash-every N] [--retain-ms N]"
	}
	dir = args[0]
	seen := map[string]bool{}
	for i := 1; i < len(args); i += 2 {
		opt, val := args[i], args[i+1]
		if seen[opt] {
			return "", 0, cfg, opt + " is given twice"
		}
		seen[opt] = true
		n, err := strconv.ParseUint(val, 10, 63)
		canonical := err == nil && val == strconv.FormatUint(n, 10)
		switch opt {
		case "--port":
			p, ok := parsePort(val)
			if !ok {
				return "", 0, cfg, "--port is 1 to 65535"
			}
			port = p
		case "--max-restarts":
			if !canonical || n > 1_000_000 {
				return "", 0, cfg, "--max-restarts is 0 to 1000000"
			}
			cfg.MaxRestarts = int(n)
		case "--restart-window":
			if !canonical || n < 1 || n > 86_400 {
				return "", 0, cfg, "--restart-window is 1 to 86400 seconds"
			}
			cfg.Window = time.Duration(n) * time.Second
		case "--crash-every":
			if !canonical {
				return "", 0, cfg, "--crash-every is a whole number, 0 for never"
			}
			cfg.CrashEvery = n
		case "--retain-ms":
			if !canonical || requireRetainMS(int64(n)) != nil {
				return "", 0, cfg, "--retain-ms is 1000 to 2678400000"
			}
			cfg.Retain = time.Duration(n) * time.Millisecond
		default:
			return "", 0, cfg, "serve has no option " + opt
		}
	}
	return dir, port, cfg, ""
}

func cmdServe(args []string, stderr io.Writer) int {
	dir, port, cfg, msg := parseServe(args)
	if msg != "" {
		return usageError(stderr, msg)
	}
	b, err := openBoard(dir, realClock{}, cfg)
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	var logMu sync.Mutex
	b.logf = func(format string, args ...any) {
		logMu.Lock()
		defer logMu.Unlock()
		fmt.Fprintf(stderr, format+"\n", args...)
	}
	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		_ = b.stop(context.Background())
		return 1
	}
	svc := &service{board: b, srv: newHTTPServer(&API{b: b}, idleTimeout), addr: ln.Addr().String()}
	served := make(chan error, 1)
	go func() { served <- svc.srv.Serve(ln) }()
	b.logf("jobq: serving %s on http://%s", dir, svc.addr)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sig)
	code := 0
	select {
	case <-sig:
	case <-b.Done():
		code = exitGaveUp
	case err := <-served:
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		code = 1
	}
	if err := svc.stop(); err != nil {
		fmt.Fprintf(stderr, "jobq: stopping: %v\n", err)
		if code == 0 {
			code = 1
		}
	}
	return code
}

func cmdCompact(args []string, stderr io.Writer) int {
	if len(args) != 1 {
		return usageError(stderr, "compact takes <dir>")
	}
	if err := Compact(args[0]); err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	return 0
}
