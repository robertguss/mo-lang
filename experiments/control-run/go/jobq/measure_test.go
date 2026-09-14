package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

// The spec's measurements. They run against a built binary:
//
//	go build -o /tmp/jobq . && JOBQ_BIN=/tmp/jobq go test -run TestMeasure -v -timeout 20m
func TestMeasure(t *testing.T) {
	bin := os.Getenv("JOBQ_BIN")
	if bin == "" {
		t.Skip("set JOBQ_BIN to a built jobq to measure")
	}
	t.Run("throughput", func(t *testing.T) {
		for _, workers := range []int{1, 32} {
			measureThroughput(t, bin, workers)
		}
	})
	t.Run("lease lag", func(t *testing.T) { measureLag(t, bin) })
	t.Run("memory at 100k jobs", func(t *testing.T) { measureMemory(t, bin) })
	t.Run("replay 1M records", measureReplay)
	t.Run("restart with 10k leased", func(t *testing.T) { measureRestart(t, bin) })
}

// writeLog writes n jobs through fn, which sets each job's fields, as the
// records a service would have written.
func writeLog(t *testing.T, dir string, n int, fn func(i int, w func(Job))) {
	t.Helper()
	f, err := os.Create(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	bw := bufio.NewWriterSize(f, 1<<20)
	write := func(j Job) {
		id, _ := parseID(j.ID)
		line, err := json.Marshal(record{Op: opPut, Next: id + 1, Job: &j})
		if err != nil {
			t.Fatal(err)
		}
		if _, err := bw.Write(append(line, '\n')); err != nil {
			t.Fatal(err)
		}
	}
	for i := 1; i <= n; i++ {
		fn(i, write)
	}
	if err := bw.Flush(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
}

func queuedJob(i int, at time.Time) Job {
	return Job{ID: formatID(uint64(i)), Queue: "q", State: Queued, Payload: strings.Repeat("p", 100), MaxAttempts: 3, CreatedAt: stampOf(at), UpdatedAt: stampOf(at)}
}

type running struct {
	cmd     *exec.Cmd
	base    string
	started time.Duration // from exec to the address line
}

func startBinary(t *testing.T, bin, dir string) *running {
	t.Helper()
	cmd := exec.Command(bin, "serve", dir, "--port", "0")
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	began := time.Now()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	line := make(chan string, 1)
	go func() {
		sc := bufio.NewScanner(out)
		if sc.Scan() {
			line <- sc.Text()
		}
		close(line)
	}()
	select {
	case l := <-line:
		_, addr, _ := strings.Cut(l, " on ")
		r := &running{cmd: cmd, base: "http://" + addr, started: time.Since(began)}
		t.Cleanup(func() { r.stop(t) })
		return r
	case <-time.After(5 * time.Minute):
		_ = cmd.Process.Kill()
		t.Fatal("the service did not start")
	}
	return nil
}

func (r *running) stop(t *testing.T) {
	if r.cmd.ProcessState != nil {
		return
	}
	if err := r.cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Error(err)
	}
	done := make(chan error, 1)
	go func() { done <- r.cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		_ = r.cmd.Process.Kill()
		t.Error("the service did not stop")
	}
}

func measureClient() *http.Client {
	return &http.Client{Timeout: clientTimeout, Transport: &http.Transport{MaxIdleConnsPerHost: 64}}
}

func measureThroughput(t *testing.T, bin string, workers int) {
	dir := t.TempDir()
	now := time.Now()
	writeLog(t, dir, 200_000, func(i int, w func(Job)) { w(queuedJob(i, now)) })
	r := startBinary(t, bin, dir)
	hc := measureClient()
	const window = 5 * time.Second
	var leases, acks, others atomic.Int64
	deadline := time.Now().Add(window)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			token := fmt.Sprintf("w%d", w)
			for time.Now().Before(deadline) {
				status, body, err := request(context.Background(), hc, r.base, token, "POST", "/queues/q/lease", `{"lease_ms": 60000}`)
				if err != nil || status != 200 {
					others.Add(1)
					continue
				}
				leases.Add(1)
				var j Job
				if json.Unmarshal([]byte(body), &j) != nil {
					others.Add(1)
					continue
				}
				if status, _, err := request(context.Background(), hc, r.base, token, "POST", "/jobs/"+j.ID+"/ack", ""); err == nil && status == 200 {
					acks.Add(1)
				} else {
					others.Add(1)
				}
			}
		}()
	}
	wg.Wait()
	secs := window.Seconds()
	t.Logf("MEASURE %d worker(s): %.0f leases/s, %.0f acks/s, %.0f leases+acks/s, %d other responses",
		workers, float64(leases.Load())/secs, float64(acks.Load())/secs, float64(leases.Load()+acks.Load())/secs, others.Load())
	r.stop(t)
}

// measureLag: a job leased for 100 ms and never acked, under a steady stream
// of lease requests from another worker; the lag is from lease_until to the
// moment the stream gets the job back.
func measureLag(t *testing.T, bin string) {
	r := startBinary(t, bin, t.TempDir())
	hc := measureClient()
	var lags []time.Duration
	for round := 0; round < 20; round++ {
		if status, _, err := request(context.Background(), hc, r.base, "p", "POST", "/jobs", `{"queue":"lag","payload":"x","max_attempts":2}`); err != nil || status != 201 {
			t.Fatal(status, err)
		}
		status, body, err := request(context.Background(), hc, r.base, "sleeper", "POST", "/queues/lag/lease", `{"lease_ms":100}`)
		var held Job
		if err != nil || status != 200 || json.Unmarshal([]byte(body), &held) != nil {
			t.Fatal(status, err)
		}
		for {
			status, body, err := request(context.Background(), hc, r.base, "stream", "POST", "/queues/lag/lease", `{"lease_ms":60000}`)
			if err != nil {
				t.Fatal(err)
			}
			if status == 200 {
				got := time.Now()
				var j Job
				if json.Unmarshal([]byte(body), &j) != nil || j.ID != held.ID {
					t.Fatalf("stream got %s", body)
				}
				lags = append(lags, got.Sub(held.LeaseUntil.Time))
				if _, _, err := request(context.Background(), hc, r.base, "stream", "POST", "/jobs/"+j.ID+"/ack", ""); err != nil {
					t.Fatal(err)
				}
				break
			}
		}
	}
	slices.Sort(lags)
	t.Logf("MEASURE lease lag over 20 rounds: median %v, max %v (timestamps have ms precision)", lags[len(lags)/2], lags[len(lags)-1])
}

func rssKiB(t *testing.T, pid int) int64 {
	b, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "VmRSS:") {
			var kib int64
			if _, err := fmt.Sscanf(strings.TrimSpace(strings.TrimPrefix(line, "VmRSS:")), "%d kB", &kib); err != nil {
				t.Fatal(err)
			}
			return kib
		}
	}
	t.Fatal("no VmRSS")
	return 0
}

func measureMemory(t *testing.T, bin string) {
	dir := t.TempDir()
	now := time.Now()
	writeLog(t, dir, 100_000, func(i int, w func(Job)) { w(queuedJob(i, now)) })
	r := startBinary(t, bin, dir)
	if status, _, err := request(context.Background(), measureClient(), r.base, "-", "GET", "/health", ""); err != nil || status != 200 {
		t.Fatal(status, err)
	}
	t.Logf("MEASURE resident memory with 100k queued jobs (100-byte payloads): %d MiB, started in %v", rssKiB(t, r.cmd.Process.Pid)/1024, r.started)
}

// measureReplay: 1M records, three per job (created, leased, done).
func measureReplay(t *testing.T) {
	dir := t.TempDir()
	now := time.Now()
	writeLog(t, dir, 333_334, func(i int, w func(Job)) {
		j := queuedJob(i, now)
		w(j)
		j.State, j.Attempts, j.Worker, j.LeaseUntil = Leased, 1, "w", stampOf(now.Add(time.Minute))
		w(j)
		j.State, j.Worker, j.LeaseUntil = Done, "", Stamp{}
		w(j)
	})
	info, err := os.Stat(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	began := time.Now()
	st, err := openStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = st.close() }()
	q, err := loadQueue(st, QueueConfig{})
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("MEASURE replay of 1,000,002 records (%d MiB, %d jobs) in process: %v", info.Size()>>20, len(q.jobs), time.Since(began))
}

// measureRestart: 10,000 jobs leased when the service stopped, their leases
// run out during the downtime.
func measureRestart(t *testing.T, bin string) {
	dir := t.TempDir()
	past := time.Now().Add(-time.Hour)
	writeLog(t, dir, 10_000, func(i int, w func(Job)) {
		j := queuedJob(i, past)
		j.State, j.Attempts, j.Worker, j.LeaseUntil = Leased, 1, "w", stampOf(past.Add(time.Minute))
		w(j)
	})
	began := time.Now()
	r := startBinary(t, bin, dir)
	hc := measureClient()
	var answered time.Duration
	busy := 0
	for {
		status, body, err := request(context.Background(), hc, r.base, "-", "GET", "/health", "")
		if err != nil {
			t.Fatal(err)
		}
		if status == 503 {
			busy++
			continue
		}
		var h Health
		if status != 200 || json.Unmarshal([]byte(body), &h) != nil {
			t.Fatal(status, body)
		}
		if h.Leased == 0 {
			answered = time.Since(began)
			if h.Queued != 10_000 {
				t.Errorf("health %+v", h)
			}
			break
		}
	}
	t.Logf("MEASURE restart with 10,000 run-out leases: listening after %v, all 10,000 queued again after %v, %d health answers were 503", r.started, answered, busy)
}
