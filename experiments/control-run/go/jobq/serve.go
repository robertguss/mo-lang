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
	"syscall"
	"time"
)

const defaultPort = 7900

// service is a replayed queue serving HTTP on a listener.
type service struct {
	queue *Queue
	store *Store
	srv   *http.Server
	addr  string
}

// openQueue replays <dir>/jobq.log into a new queue on clock.
func openQueue(dir string, clock Clock) (*Queue, *Store, error) {
	q := newQueue(clock)
	s, err := OpenStore(dir, q.applyRecord)
	if err != nil {
		return nil, nil, err
	}
	q.finishReplay(s)
	return q, s, nil
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
	q, s, err := openQueue(dir, clock)
	if err != nil {
		return nil, err
	}
	svc := &service{queue: q, store: s, srv: newHTTPServer(&API{q: q}, idle), addr: ln.Addr().String()}
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
	if err := s.queue.acquire(ctx); err != nil {
		return errors.Join(err, s.store.Close())
	}
	defer s.queue.release()
	return s.store.Close()
}

func parsePort(s string) (int, bool) {
	n, err := strconv.Atoi(s)
	return n, err == nil && n >= 1 && n <= 65535 && s == strconv.Itoa(n)
}

func cmdServe(args []string, stderr io.Writer) int {
	port := defaultPort
	var dir string
	switch {
	case len(args) == 1:
		dir = args[0]
	case len(args) == 3 && args[1] == "--port":
		dir = args[0]
		p, ok := parsePort(args[2])
		if !ok {
			return usageError(stderr, "--port is 1 to 65535")
		}
		port = p
	default:
		return usageError(stderr, "serve takes <dir> [--port N]")
	}
	q, s, err := openQueue(dir, realClock{})
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		_ = s.Close()
		return 1
	}
	svc := &service{queue: q, store: s, srv: newHTTPServer(&API{q: q}, idleTimeout), addr: ln.Addr().String()}
	served := make(chan error, 1)
	go func() { served <- svc.srv.Serve(ln) }()
	fmt.Fprintf(stderr, "jobq: serving %s on http://%s\n", dir, svc.addr)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	code := 0
	select {
	case <-sig:
	case err := <-served:
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		code = 1
	}
	if err := svc.stop(); err != nil {
		fmt.Fprintf(stderr, "jobq: stopping: %v\n", err)
		code = 1
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
