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
	"syscall"
	"time"
)

// Deadlines. Each literal is either chosen for its call or derived from an
// enclosing deadline; the report counts them.
const (
	// chosen: how long one request may wait for the queue.
	requestTimeout = 10 * time.Second
	// chosen: the spec's `idle:`; a connection that has sent no request
	// header by then is closed, so idle connections cannot pile up.
	readHeaderTimeout = 5 * time.Second
	// derived: reading a whole request fits in the request's deadline.
	readTimeout = requestTimeout
	// derived: the request's deadline plus a chosen margin to write its 503.
	writeTimeout = requestTimeout + 5*time.Second
	// chosen: how long a keep-alive connection may sit between requests.
	idleTimeout = 60 * time.Second
	// chosen: how long a stop waits for requests in flight.
	shutdownTimeout = 5 * time.Second
	// derived: a client waits as long as the server may take to answer,
	// plus a chosen margin.
	clientTimeout = writeTimeout + 5*time.Second
	// derived: the idle sweep runs as often as the shortest lease.
	sweepEvery = minLeaseMs * time.Millisecond
)

// service is a running jobq: a locked store, its queue, and a listener.
type service struct {
	st        *store
	q         *Queue
	srv       *http.Server
	ln        net.Listener
	served    chan struct{}
	serveErr  error
	stopSweep chan struct{}
	swept     chan struct{}
}

// startService opens dir, replays it, and listens on addr.
func startService(dir, addr string, now func() time.Time) (*service, error) {
	st, err := openStore(dir)
	if err != nil {
		return nil, err
	}
	q, err := loadQueue(st, QueueConfig{Now: now})
	if err != nil {
		return nil, errors.Join(err, st.close())
	}
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, errors.Join(err, st.close())
	}
	s := &service{
		st: st, q: q, ln: ln, served: make(chan struct{}), stopSweep: make(chan struct{}), swept: make(chan struct{}),
		srv: &http.Server{
			Handler:           &API{q: q, requestTimeout: requestTimeout},
			ReadHeaderTimeout: readHeaderTimeout,
			ReadTimeout:       readTimeout,
			WriteTimeout:      writeTimeout,
			IdleTimeout:       idleTimeout,
			MaxHeaderBytes:    64 << 10,
		},
	}
	go func() {
		s.serveErr = s.srv.Serve(ln)
		close(s.served)
	}()
	go s.sweepLoop()
	return s, nil
}

func (s *service) addr() string { return s.ln.Addr().String() }

// sweepLoop is the listener's Idle: a look at the leases every sweepEvery.
// A failed sweep is not reported here; the next look retries it, and a
// request's look answers 503.
func (s *service) sweepLoop() {
	defer close(s.swept)
	t := time.NewTicker(sweepEvery)
	defer t.Stop()
	for {
		select {
		case <-s.stopSweep:
			return
		case <-t.C:
			ctx, cancel := context.WithTimeout(context.Background(), sweepEvery)
			_ = s.q.Sweep(ctx)
			cancel()
		}
	}
}

// stop closes the listener, waits for requests in flight, then takes the
// queue's lock so that nothing writes while the store closes.
func (s *service) stop() error {
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	err := s.srv.Shutdown(ctx)
	close(s.stopSweep)
	<-s.swept
	<-s.served
	if !errors.Is(s.serveErr, http.ErrServerClosed) {
		err = errors.Join(err, s.serveErr)
	}
	if lerr := s.q.acquire(ctx); lerr != nil {
		return errors.Join(err, lerr, s.st.close())
	}
	return errors.Join(err, s.st.close())
}

func cmdServe(dir string, port int, stdout, stderr io.Writer) int {
	s, err := startService(dir, net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), time.Now)
	if err != nil {
		return failf(stderr, 1, "%v", err)
	}
	_, _ = fmt.Fprintf(stdout, "jobq: serving %s on %s\n", dir, s.addr())
	ctx, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()
	select {
	case <-ctx.Done():
	case <-s.served:
	}
	if err := s.stop(); err != nil {
		return failf(stderr, 1, "%v", err)
	}
	return 0
}

func cmdCompact(dir string, stdout, stderr io.Writer) int {
	kept, err := compact(dir, QueueConfig{Now: time.Now})
	if err != nil {
		return failf(stderr, 1, "%v", err)
	}
	_, _ = fmt.Fprintf(stdout, "jobq: compacted %s to %d jobs\n", dir, kept)
	return 0
}

// request sends one request; a token of "-" sends no authorization.
func request(ctx context.Context, hc *http.Client, base, token, method, path, body string) (int, string, error) {
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, base+path, rd)
	if err != nil {
		return 0, "", err
	}
	if token != "-" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := hc.Do(req)
	if err != nil {
		return 0, "", err
	}
	raw, rerr := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
	if err := errors.Join(rerr, resp.Body.Close()); err != nil {
		return 0, "", err
	}
	return resp.StatusCode, string(raw), nil
}

func printResponse(w io.Writer, status int, body string) error {
	if body == "" {
		_, err := fmt.Fprintf(w, "%d\n", status)
		return err
	}
	_, err := fmt.Fprintf(w, "%d\n%s\n", status, body)
	return err
}

func cmdClient(host string, port int, token, method, path, body string, stdout, stderr io.Writer) int {
	ctx, cancel := context.WithTimeout(context.Background(), clientTimeout)
	defer cancel()
	hc := &http.Client{Timeout: clientTimeout}
	status, resp, err := request(ctx, hc, "http://"+net.JoinHostPort(host, strconv.Itoa(port)), token, method, path, body)
	if err != nil {
		return failf(stderr, 1, "%v", err)
	}
	if err := printResponse(stdout, status, resp); err != nil {
		return failf(stderr, 1, "%v", err)
	}
	return 0
}

// cmdCheck serves dir on a free port and plays a script through the client.
// A line is `<token> <method> <path> [<json>]`, `sleep <ms>`, or `restart`;
// blank lines and lines starting with # are skipped.
func cmdCheck(dir, scriptPath string, stdout, stderr io.Writer) int {
	script, err := os.ReadFile(scriptPath)
	if err != nil {
		return failf(stderr, 1, "%v", err)
	}
	s, err := startService(dir, "127.0.0.1:0", time.Now)
	if err != nil {
		return failf(stderr, 1, "%v", err)
	}
	hc := &http.Client{Timeout: clientTimeout}
	for n, line := range strings.Split(string(script), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if s, err = playLine(s, dir, hc, line, stdout); err != nil {
			stopErr := error(nil)
			if s != nil {
				stopErr = s.stop()
			}
			return failf(stderr, 1, "%s line %d: %v", scriptPath, n+1, errors.Join(err, stopErr))
		}
	}
	if err := s.stop(); err != nil {
		return failf(stderr, 1, "%v", err)
	}
	return 0
}

func playLine(s *service, dir string, hc *http.Client, line string, stdout io.Writer) (*service, error) {
	if _, err := fmt.Fprintf(stdout, "> %s\n", line); err != nil {
		return s, err
	}
	fields := strings.SplitN(line, " ", 4)
	switch {
	case fields[0] == "restart" && len(fields) == 1:
		if err := s.stop(); err != nil {
			return nil, err
		}
		return startService(dir, "127.0.0.1:0", time.Now)
	case fields[0] == "sleep" && len(fields) == 2:
		ms, err := strconv.Atoi(fields[1])
		if err != nil || ms < 0 {
			return s, fmt.Errorf("sleep wants milliseconds, got %q", fields[1])
		}
		time.Sleep(time.Duration(ms) * time.Millisecond)
		return s, nil
	case len(fields) >= 3:
		body := ""
		if len(fields) == 4 {
			body = fields[3]
		}
		ctx, cancel := context.WithTimeout(context.Background(), clientTimeout)
		defer cancel()
		status, resp, err := request(ctx, hc, "http://"+s.addr(), fields[0], fields[1], fields[2], body)
		if err != nil {
			return s, err
		}
		return s, printResponse(stdout, status, resp)
	}
	return s, errors.New("want `<token> <method> <path> [<json>]`, `sleep <ms>`, or `restart`")
}
