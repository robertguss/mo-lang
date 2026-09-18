package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// `jobq bench` is the speed budget's measure, the round's measure.py in Go:
// it serves <dir> from a jobq binary in a child process on a free port,
// creates --jobs jobs from 8 producers into four queues, leases and acks
// them from one worker and then from --workers, restarts the service, and
// prints one line per number. --serve names the binary to serve with, so the
// same client measures an older program built from the history; the default
// is this binary.

const benchUsage = "bench takes <dir> [--jobs N] [--workers N] [--serve <jobq binary>]"

// benchConfig is bench's arguments.
type benchConfig struct {
	dir     string
	jobs    int
	workers int
	serve   string
}

func parseBench(args []string) (benchConfig, string) {
	cfg := benchConfig{jobs: 30_000, workers: 32}
	if len(args) == 0 || len(args)%2 != 1 || strings.HasPrefix(args[0], "--") {
		return cfg, benchUsage
	}
	cfg.dir = args[0]
	seen := map[string]bool{}
	for i := 1; i < len(args); i += 2 {
		opt, val := args[i], args[i+1]
		if seen[opt] {
			return cfg, opt + " is given twice"
		}
		seen[opt] = true
		n, err := strconv.Atoi(val)
		switch opt {
		case "--jobs":
			if err != nil || n < 100 || n > 10_000_000 {
				return cfg, "--jobs is 100 to 10000000"
			}
			cfg.jobs = n
		case "--workers":
			if err != nil || n < 1 || n > 1024 {
				return cfg, "--workers is 1 to 1024"
			}
			cfg.workers = n
		case "--serve":
			cfg.serve = val
		default:
			return cfg, "bench has no option " + opt
		}
	}
	return cfg, ""
}

func cmdBench(args []string, stdout, stderr io.Writer) int {
	cfg, msg := parseBench(args)
	if msg != "" {
		return usageError(stderr, msg)
	}
	if cfg.serve == "" {
		self, err := os.Executable()
		if err != nil {
			fmt.Fprintf(stderr, "jobq: %v\n", err)
			return 1
		}
		cfg.serve = self
	}
	if err := runBench(cfg, stdout); err != nil {
		fmt.Fprintf(stderr, "jobq: bench: %v\n", err)
		return 1
	}
	return 0
}

// benchServer is the served child process.
type benchServer struct {
	cmd  *exec.Cmd
	addr string
}

func freePort() (int, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port, nil
}

// startBenchServer starts bin serving dir on port and waits for /health.
func startBenchServer(bin, dir string, port int, c *http.Client) (*benchServer, time.Duration, error) {
	start := time.Now()
	cmd := exec.Command(bin, "serve", dir, "--port", strconv.Itoa(port))
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	if err := cmd.Start(); err != nil {
		return nil, 0, err
	}
	s := &benchServer{cmd: cmd, addr: net.JoinHostPort("127.0.0.1", strconv.Itoa(port))}
	for time.Since(start) < 300*time.Second {
		if st, _, err := benchReq(c, s.addr, "x", "GET", "/health", nil); err == nil && st == 200 {
			return s, time.Since(start), nil
		}
		time.Sleep(10 * time.Millisecond)
	}
	s.kill()
	return nil, 0, errors.New("the service did not answer /health in 300 s")
}

func (s *benchServer) kill() {
	_ = s.cmd.Process.Kill()
	_ = s.cmd.Wait()
}

// stop sends SIGTERM and waits, killing it after 30 s.
func (s *benchServer) stop() error {
	if err := s.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() { done <- s.cmd.Wait() }()
	select {
	case err := <-done:
		return err
	case <-time.After(30 * time.Second):
		_ = s.cmd.Process.Kill()
		return errors.New("the service did not stop in 30 s")
	}
}

// rssMiB is the child's resident memory, as ps reports it on Linux and
// macOS alike.
func (s *benchServer) rssMiB() float64 {
	out, err := exec.Command("ps", "-o", "rss=", "-p", strconv.Itoa(s.cmd.Process.Pid)).Output()
	if err != nil {
		return 0
	}
	kb, _ := strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
	return kb / 1024
}

func benchReq(c *http.Client, addr, token, method, path string, body any) (int, map[string]any, error) {
	var rdr io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return 0, nil, err
		}
		rdr = bytes.NewReader(data)
	}
	req, err := http.NewRequest(method, "http://"+addr+path, rdr)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, nil, err
	}
	var out map[string]any
	if len(data) > 0 {
		_ = json.Unmarshal(data, &out)
	}
	return resp.StatusCode, out, nil
}

const benchQueues = 4

// runBench runs the measure and prints its lines.
func runBench(cfg benchConfig, out io.Writer) error {
	if err := os.MkdirAll(cfg.dir, 0o755); err != nil {
		return err
	}
	c := &http.Client{Timeout: clientTimeout, Transport: &http.Transport{
		MaxIdleConns: 2 * (cfg.workers + 8), MaxIdleConnsPerHost: 2 * (cfg.workers + 8), IdleConnTimeout: time.Minute}}
	port, err := freePort()
	if err != nil {
		return err
	}
	srv, _, err := startBenchServer(cfg.serve, cfg.dir, port, c)
	if err != nil {
		return err
	}
	defer func() {
		if srv != nil {
			srv.kill()
		}
	}()
	// Creates: 8 producers, 100-byte payloads, four queues.
	payload := strings.Repeat("x", 100)
	const producers = 8
	var bad atomic.Int64
	var wg sync.WaitGroup
	t0 := time.Now()
	for p := range producers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for k := p; k < cfg.jobs; k += producers {
				st, _, err := benchReq(c, srv.addr, fmt.Sprintf("p%d", p), "POST", "/jobs",
					map[string]any{"queue": fmt.Sprintf("q%d", k%benchQueues), "payload": payload, "max_tries": 3})
				if err != nil || st != 201 {
					bad.Add(1)
				}
			}
		}()
	}
	wg.Wait()
	dt := time.Since(t0).Seconds()
	fmt.Fprintf(out, "creates/s: %.0f (%d in %.2f s, %d errors)\n", float64(cfg.jobs)/dt, cfg.jobs, dt, bad.Load())

	// Pairs at one worker: a quarter of the jobs, at most 5 s.
	n, dt, errs := benchPairs(c, srv.addr, 1, cfg.jobs/4, 5*time.Second)
	fmt.Fprintf(out, "pairs/s at 1 worker: %.0f (%d in %.2f s, %d errors)\n", float64(n)/dt, n, dt, errs)
	// Pairs at --workers: the rest.
	n, dt, errs = benchPairs(c, srv.addr, cfg.workers, cfg.jobs, 60*time.Second)
	fmt.Fprintf(out, "pairs/s at %d workers: %.0f (%d in %.2f s, %d errors)\n", cfg.workers, float64(n)/dt, n, dt, errs)
	fmt.Fprintf(out, "resident memory after the pairs: %.1f MiB\n", srv.rssMiB())

	if err := srv.stop(); err != nil {
		return fmt.Errorf("stopping: %v", err)
	}
	srv = nil
	c.CloseIdleConnections()
	s2, up, err := startBenchServer(cfg.serve, cfg.dir, port, c)
	if err != nil {
		return err
	}
	srv = s2
	fmt.Fprintf(out, "restart seconds: %.3f\n", up.Seconds())
	return srv.stop()
}

// benchPairs leases and acks from workers clients until limit pairs are made,
// every queue answers 204, or within passes. Worker i starts on queue i mod
// 4 and moves to the next on a 204.
func benchPairs(c *http.Client, addr string, workers, limit int, within time.Duration) (int, float64, int64) {
	var done, errs atomic.Int64
	var wg sync.WaitGroup
	t0 := time.Now()
	stop := t0.Add(within)
	for w := range workers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			token := fmt.Sprintf("w%d", w)
			qi, empty := w%benchQueues, 0
			for empty < benchQueues && time.Now().Before(stop) && done.Load() < int64(limit) {
				st, j, err := benchReq(c, addr, token, "POST", fmt.Sprintf("/queues/q%d/lease", qi), map[string]any{"lease_ms": 60000})
				switch {
				case err != nil:
					errs.Add(1)
					continue
				case st == 204:
					empty++
					qi = (qi + 1) % benchQueues
					continue
				case st != 200:
					errs.Add(1)
					continue
				}
				empty = 0
				id, _ := j["id"].(string)
				st, _, err = benchReq(c, addr, token, "POST", "/jobs/"+id+"/ack", nil)
				if err != nil || st != 200 {
					errs.Add(1)
					continue
				}
				done.Add(1)
			}
		}()
	}
	wg.Wait()
	return int(done.Load()), time.Since(t0).Seconds(), errs.Load()
}
