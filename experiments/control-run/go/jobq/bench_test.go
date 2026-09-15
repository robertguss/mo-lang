package main

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

// The spec's measurements, skipped unless JOBQ_BENCH=1:
//
//	JOBQ_BENCH=1 go test -run TestBench -v -timeout 30m ./jobq

func benchOnly(t *testing.T) {
	if os.Getenv("JOBQ_BENCH") == "" {
		t.Skip("set JOBQ_BENCH=1 to run the measurements")
	}
}

// writeLog writes a store of jobs queued jobs (each also leased once, with the
// lease already run out, when leased is set) plus updates re-putting jobs as
// queued. It returns the number of records.
func writeLog(t *testing.T, dir string, jobs, updates int, leased bool, payload string) int {
	t.Helper()
	f, err := os.Create(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	w := bufio.NewWriterSize(f, 1<<20)
	at := time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)
	n := 0
	put := func(j Job) {
		v := jobView(j)
		line, err := encodeRecord(record{Op: "put", Job: &v})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(line); err != nil {
			t.Fatal(err)
		}
		n++
	}
	for i := 1; i <= jobs; i++ {
		j := Job{ID: uint64(i), Queue: "bench", State: Queued, Payload: payload, MaxTries: 3, CreatedAt: at, UpdatedAt: at}
		put(j)
		if leased {
			j.State, j.Tries, j.Worker, j.LeaseUntil = Leased, 1, "w", at.Add(time.Second)
			put(j)
		}
	}
	for i := range updates {
		put(Job{ID: uint64(i%jobs) + 1, Queue: "bench", State: Queued, Payload: payload, MaxTries: 3,
			CreatedAt: at, UpdatedAt: at.Add(time.Duration(i) * time.Millisecond)})
	}
	if err := w.Flush(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestBenchLeaseAckThroughput(t *testing.T) {
	benchOnly(t)
	for _, workers := range []int{1, 32} {
		dir := t.TempDir()
		writeLog(t, dir, 200_000, 0, false, "payload")
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		svc, err := startService(dir, realClock{}, ln, idleTimeout)
		if err != nil {
			t.Fatal(err)
		}
		var pairs atomic.Int64
		start := time.Now()
		deadline := start.Add(5 * time.Second)
		var wg sync.WaitGroup
		for w := range workers {
			wg.Add(1)
			go func() {
				defer wg.Done()
				client := &http.Client{Timeout: clientTimeout}
				token := "w" + strconv.Itoa(w)
				for time.Now().Before(deadline) {
					status, body, err := doRequest(client, svc.addr, token, "POST", "/queues/bench/lease", `{"lease_ms":600000}`)
					if err != nil || status != 200 {
						t.Errorf("lease: %d %s %v", status, body, err)
						return
					}
					status, body, err = doRequest(client, svc.addr, token, "POST", "/jobs/"+decodeID(body)+"/ack", "")
					if err != nil || status != 200 {
						t.Errorf("ack: %d %s %v", status, body, err)
						return
					}
					pairs.Add(1)
				}
			}()
		}
		wg.Wait()
		secs := time.Since(start).Seconds()
		t.Logf("%2d workers: %.0f lease+ack pairs/s, %.0f requests/s", workers, float64(pairs.Load())/secs, 2*float64(pairs.Load())/secs)
		if err := svc.stop(); err != nil {
			t.Fatal(err)
		}
	}
}

// The lag between a lease running out and the job being handed out again,
// under a steady stream of lease requests, read from the server's own
// timestamps: updated_at of the new lease minus lease_until of the old one.
func TestBenchLeaseLag(t *testing.T) {
	benchOnly(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	svc, err := startService(t.TempDir(), realClock{}, ln, idleTimeout)
	if err != nil {
		t.Fatal(err)
	}
	defer svc.stop()
	client := &http.Client{Timeout: clientTimeout}
	if status, _, err := doRequest(client, svc.addr, "p", "POST", "/jobs", `{"queue":"lag","payload":"x","max_tries":100}`); err != nil || status != 201 {
		t.Fatal(status, err)
	}
	var mu sync.Mutex
	var lastUntil time.Time
	var lags []time.Duration
	var requests atomic.Int64
	done := make(chan struct{})
	var wg sync.WaitGroup
	for w := range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c := &http.Client{Timeout: clientTimeout}
			for {
				select {
				case <-done:
					return
				default:
				}
				status, body, err := doRequest(c, svc.addr, "s"+strconv.Itoa(w), "POST", "/queues/lag/lease", `{"lease_ms":100}`)
				requests.Add(1)
				if err != nil || status != 200 {
					continue
				}
				j := decodeJob(t, string(body))
				leasedAt, _ := time.Parse(timeLayout, j.UpdatedAt)
				until, _ := time.Parse(timeLayout, *j.LeaseUntil)
				mu.Lock()
				if !lastUntil.IsZero() {
					lags = append(lags, leasedAt.Sub(lastUntil))
				}
				lastUntil = until
				if len(lags) == 90 {
					close(done)
				}
				mu.Unlock()
			}
		}()
	}
	start := time.Now()
	wg.Wait()
	sort.Slice(lags, func(i, j int) bool { return lags[i] < lags[j] })
	t.Logf("lease lag over %d hand-outs: median %v, max %v, stream %.0f lease requests/s",
		len(lags), lags[len(lags)/2], lags[len(lags)-1], float64(requests.Load())/time.Since(start).Seconds())
}

// serveBinary starts `jobq serve` on dir and reports the time to the first
// answered /health, that answer, and resident memory at that point.
func serveBinary(t *testing.T, bin, dir string) (time.Duration, string, string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	ln.Close()
	c, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(c, bin, "serve", dir, "--port", port)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	start := time.Now()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Timeout: clientTimeout}
	var body []byte
	for {
		status, b, err := doRequest(client, "127.0.0.1:"+port, "-", "GET", "/health", "")
		if err == nil && status == 200 {
			body = b
			break
		}
		if time.Since(start) > 4*time.Minute {
			t.Fatalf("serve never answered: %s", stderr.String())
		}
		time.Sleep(2 * time.Millisecond)
	}
	ready := time.Since(start)
	status, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", cmd.Process.Pid))
	if err != nil {
		t.Fatal(err)
	}
	rss := ""
	for _, line := range strings.Split(string(status), "\n") {
		if strings.HasPrefix(line, "VmRSS:") {
			rss = strings.Join(strings.Fields(line)[1:], " ")
		}
	}
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	if err := cmd.Wait(); err != nil {
		t.Fatalf("serve exited with %v: %s", err, stderr.String())
	}
	return ready, strings.TrimSpace(string(body)), rss
}

func TestBenchMemoryReplayRestart(t *testing.T) {
	benchOnly(t)
	bin := filepath.Join(t.TempDir(), "jobq")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, out)
	}

	dir := t.TempDir()
	writeLog(t, dir, 100_000, 0, false, strings.Repeat("x", 100))
	ready, body, rss := serveBinary(t, bin, dir)
	t.Logf("100k jobs (100-byte payloads): ready in %v, VmRSS %s, %s", ready, rss, body)

	dir = t.TempDir()
	n := writeLog(t, dir, 250_000, 750_000, false, "payload")
	info, _ := os.Stat(filepath.Join(dir, logName))
	start := time.Now()
	_, s, err := openQueue(dir, realClock{})
	if err != nil {
		t.Fatal(err)
	}
	replayed := time.Since(start)
	s.Close()
	ready, _, rss = serveBinary(t, bin, dir)
	t.Logf("%d-record log (%d MB, 250k jobs): replay in-process %v; binary ready in %v, VmRSS %s", n, info.Size()>>20, replayed, ready, rss)

	dir = t.TempDir()
	writeLog(t, dir, 10_000, 0, true, "payload")
	ready, body, rss = serveBinary(t, bin, dir)
	t.Logf("restart with 10,000 leased jobs, all run out at the first look: ready in %v, VmRSS %s, %s", ready, rss, body)
}
