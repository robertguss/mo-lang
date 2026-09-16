package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// newMemBoard is a board over an in-memory log and archive: a restart
// replays the archive, then the log.
func newMemBoard(t *testing.T, f, a *memFile, clock *manualClock, cfg BoardConfig) *Board {
	t.Helper()
	open := func() (*Queue, *Store, error) {
		q := newQueue(clock)
		q.retain = cfg.retain()
		as, err := memStore(a, q.applyArchived)
		if err != nil {
			return nil, nil, err
		}
		q.archive = as
		s, err := memStore(f, q.applyRecord)
		if err != nil {
			return nil, nil, err
		}
		if err := q.checkApart(); err != nil {
			return nil, nil, err
		}
		q.finishReplay(s)
		return q, s, nil
	}
	b, err := newBoard(open, clock, cfg)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// memStore replays f through apply and cuts its torn tail.
func memStore(f *memFile, apply func(record) error) (*Store, error) {
	size, err := replay(bytes.NewReader(f.data), apply)
	if err != nil {
		return nil, err
	}
	s := &Store{f: f, size: size, dirty: int64(len(f.data)) != size}
	return s, s.repair()
}

// fixedBoard serves q and never restarts it successfully.
func fixedBoard(t *testing.T, q *Queue, s *Store) *Board {
	t.Helper()
	opened := false
	b, err := newBoard(func() (*Queue, *Store, error) {
		if opened {
			return nil, nil, fmt.Errorf("fixed board")
		}
		opened = true
		return q, s, nil
	}, q.clock, defaultBoardConfig())
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// boardMatchesLog fails unless the board's queue is what the file replays to.
func boardMatchesLog(t *testing.T, h *apiHarness) {
	t.Helper()
	q := h.q()
	if got, want := snapshot(q), snapshot(replayBoth(t, h.archive.data, h.file.data)); !reflect.DeepEqual(got, want) {
		t.Fatalf("board differs from the log:\n%v\n%v", got, want)
	}
}

func (h *apiHarness) restarts() int {
	h.t.Helper()
	h.q()
	var got Health
	if err := json.Unmarshal([]byte(h.want("-", "GET", "/health", "", 200)), &got); err != nil {
		h.t.Fatal(err)
	}
	return got.Restarts
}

func TestChaosSwitchRestartsTheBoard(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, CrashEvery: 3})
	if n := h.restarts(); n != 0 {
		t.Fatalf("restarts before any failure = %d", n)
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p1","max_tries":2}`, 201)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p2","max_tries":2}`, 201)
	// The third write fails after its record is on disk.
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p3","max_tries":2}`, 503)
	if n := h.restarts(); n != 1 {
		t.Fatalf("restarts after one failure = %d", n)
	}
	boardMatchesLog(t, h)
	if v := decodeJob(t, h.want(w1, "GET", "/jobs/j_3", "", 200)); v.Payload != "p3" {
		t.Errorf("the write the failure answered is not on the board: %+v", v)
	}
	// Ids continue (write 4), and the moves a look makes count too: the lease
	// is write 5, its run-out move write 6.
	if v := decodeJob(t, h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p4","max_tries":2}`, 201)); v.ID != "j_4" {
		t.Errorf("id after the restart = %s", v.ID)
	}
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":100}`, 200) // write 5
	h.clock.Advance(time.Second)
	h.want(w1, "GET", "/jobs/j_1", "", 503) // the run-out move is write 6
	if n := h.restarts(); n != 2 {
		t.Fatalf("restarts after a failing move = %d", n)
	}
	boardMatchesLog(t, h)
	if v := decodeJob(t, h.want(w1, "GET", "/jobs/j_1", "", 200)); v.State != Queued || v.Tries != 1 {
		t.Errorf("the move is not on the board: %+v", v)
	}
}

func TestLeasesSurviveARestart(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 5, Window: time.Minute, CrashEvery: 3})
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	held := decodeJob(t, h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":5000}`, 200))
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"q","max_tries":2}`, 503)
	h.q() // wait out the restart
	after := decodeJob(t, h.want(w1, "GET", "/jobs/j_1", "", 200))
	if after.State != Leased || !reflect.DeepEqual(after.Worker, held.Worker) || !reflect.DeepEqual(after.LeaseUntil, held.LeaseUntil) || after.LeaseUntil == nil {
		t.Fatalf("the lease after the restart: %+v, was %+v", after, held)
	}
	h.want("Bearer w2", "POST", "/queues/a/lease", "", 200) // j_2, not j_1
	h.want(w1, "POST", "/jobs/j_1/ack", "", 200)
	boardMatchesLog(t, h)
}

// A broken rule is the board's failure: memory is rebuilt from the log.
func TestABrokenRuleRestartsTheBoard(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	h.q().jobs[1].Tries = 7 // memory no longer what the log says
	if body := h.want(w1, "POST", "/queues/a/lease", "", 503); !strings.Contains(body, "never failed") {
		t.Errorf("the broken rule answered %s", body)
	}
	if n := h.restarts(); n != 1 {
		t.Fatalf("restarts = %d", n)
	}
	if v := decodeJob(t, h.want(w1, "POST", "/queues/a/lease", "", 200)); v.Tries != 1 {
		t.Errorf("the lease after the restart: %+v", v)
	}
	boardMatchesLog(t, h)
}

// A panic under the queue's lock (here, inside the store's write) takes the
// board down; the request after the restart is answered normally, and a
// torn tail the panic left is cut.
func TestAPanicUnderTheLockRestartsTheBoard(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":1000}`, 200)
	before := snapshot(h.q())
	h.file.fail = func(op string) bool {
		if op == "write" {
			h.file.fail = nil
			h.file.data = append(h.file.data, "0000 torn"...)
			panic("the store blew up")
		}
		return false
	}
	if body := h.want(w1, "POST", "/jobs/j_1/ack", "", 503); !strings.Contains(body, `"error"`) {
		t.Errorf("a panic answered %q", body)
	}
	if got := snapshot(h.q()); !reflect.DeepEqual(got, before) {
		t.Errorf("the panic changed a job: %v", got)
	}
	if h.board.Restarts() != 1 {
		t.Errorf("restarts = %d", h.board.Restarts())
	}
	if v := decodeJob(t, h.want(w1, "POST", "/jobs/j_1/ack", "", 200)); v.State != Done {
		t.Errorf("the request after a panic: %+v", v)
	}
	boardMatchesLog(t, h)
}

// A panic outside the queue's lock costs its request only.
func TestAPanicOutsideTheQueueCostsOnlyItsRequest(t *testing.T) {
	h := newAPIHarness(t)
	st := h.board.state()
	api := &API{b: h.board}
	func() {
		defer func() { _ = recover() }()
		status, _ := api.respond(nil, nil) // a nil request panics before the queue
		if status != http.StatusServiceUnavailable {
			t.Errorf("status = %d", status)
		}
	}()
	if h.board.state() != st || h.board.Restarts() != 0 {
		t.Error("a panic outside the queue restarted the board")
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
}

func TestTheBudgetStopsTheRestarts(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 2, Window: 60 * time.Second, CrashEvery: 1})
	for i := range 2 {
		h.want(w1, "POST", "/jobs", fmt.Sprintf(`{"queue":"a","payload":"p%d","max_tries":1}`, i), 503)
		if n := h.restarts(); n != i+1 {
			t.Fatalf("restarts = %d, want %d", n, i+1)
		}
		h.clock.Advance(20 * time.Second)
	}
	// The next failure is inside the window: the board gives up.
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p2","max_tries":1}`, 503)
	select {
	case <-h.board.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the board did not give up")
	}
	h.want("-", "GET", "/health", "", 503)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p3","max_tries":1}`, 503)
	if got := replayBytes(t, h.file.data); len(got.jobs) != 3 {
		t.Errorf("the log after giving up holds %d jobs, want 3", len(got.jobs))
	}
	if err := h.board.stop(ctx(t)); err != nil {
		t.Error(err)
	}
}

func TestAFailureAfterTheWindowStartsAFreshCount(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 2, Window: 60 * time.Second, CrashEvery: 1})
	for i := range 10 {
		h.want(w1, "POST", "/jobs", fmt.Sprintf(`{"queue":"a","payload":"p%d","max_tries":1}`, i), 503)
		if n := h.restarts(); n != i+1 {
			t.Fatalf("restarts = %d, want %d", n, i+1)
		}
		h.clock.Advance(31 * time.Second)
	}
	select {
	case <-h.board.Done():
		t.Fatal("the board gave up though no window held more than two restarts")
	default:
	}
}

func TestZeroRestartsGivesUpAtOnce(t *testing.T) {
	h := newAPIHarnessWith(t, BoardConfig{MaxRestarts: 0, Window: time.Second, CrashEvery: 1})
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 503)
	<-h.board.Done()
	if h.board.Restarts() != 0 {
		t.Error("restarted with a budget of 0")
	}
}

// The Go reading of `--sim --faults` for the board: failures injected at
// random writes. After every request the board, once back, equals a replay
// of the log; every created job a 2xx reported is present unless a delete
// was tried on it; an acked one stays done, archived or not.
func TestSimulationWithRandomBoardFailures(t *testing.T) {
	totalRestarts := 0
	for seed := uint64(1); seed <= 40; seed++ {
		rng := rand.New(rand.NewPCG(seed, 0xc4a05))
		cfg := BoardConfig{MaxRestarts: 1 << 20, Window: time.Second, Retain: time.Second,
			crash: func(int) bool { return rng.IntN(20) == 0 }}
		h := newAPIHarnessWith(t, cfg)
		created, deleteTried, acked := map[string]bool{}, map[string]bool{}, map[string]bool{}
		id := func() string { return "j_" + strconv.Itoa(1+rng.IntN(len(created)+2)) }
		for step := range 300 {
			worker := "Bearer w" + strconv.Itoa(rng.IntN(3))
			var status int
			var body string
			switch r := rng.IntN(10); {
			case r < 3:
				status, body, _ = h.do(w1, "POST", "/jobs", fmt.Sprintf(`{"queue":"a","payload":"p%d","max_tries":%d}`, step, 1+rng.IntN(3)))
				if status == 201 {
					created[decodeJob(t, body).ID] = true
				}
			case r < 6:
				status, _, _ = h.do(worker, "POST", "/queues/a/lease", fmt.Sprintf(`{"lease_ms":%d}`, 50+rng.IntN(200)))
			case r < 8:
				j := id()
				status, _, _ = h.do(worker, "POST", "/jobs/"+j+"/ack", "")
				if status == 200 {
					acked[j] = true
				}
			case r < 9:
				j := id()
				deleteTried[j] = true
				status, _, _ = h.do(w1, "DELETE", "/jobs/"+j, "")
			default:
				status, _, _ = h.do(w1, "GET", "/jobs/"+id(), "")
			}
			if status >= 500 && status != 503 {
				t.Fatalf("seed %d step %d: status %d", seed, step, status)
			}
			h.clock.Advance(time.Duration(rng.IntN(100)) * time.Millisecond)
			boardMatchesLog(t, h)
			q := h.q()
			for j := range created {
				got := q.lookup(mustID(j))
				ok := got != nil
				if !ok && !deleteTried[j] {
					t.Fatalf("seed %d step %d: %s is missing", seed, step, j)
				}
				if ok && acked[j] && got.State != Done {
					t.Fatalf("seed %d step %d: acked %s is %s", seed, step, j, got.State)
				}
			}
		}
		totalRestarts += h.board.Restarts()
	}
	if totalRestarts == 0 {
		t.Error("no failure was ever injected")
	}
}

// The chaos switch under load over a real socket: every answer is 2xx, 4xx,
// or 503 (or a closed connection), every 2xx job is present after, again
// after a stop and a start, and /health answers 200 soon after a failure.
func TestChaosUnderLoad(t *testing.T) {
	dir := t.TempDir()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	cfg := BoardConfig{MaxRestarts: 1 << 20, Window: time.Minute, CrashEvery: 97}
	svc, err := startServiceWith(dir, realClock{}, ln, idleTimeout, cfg)
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	created := map[string]bool{}
	var failures atomic.Int64
	deadline := time.Now().Add(3 * time.Second)
	var wg sync.WaitGroup
	for w := range 16 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			client := &http.Client{Timeout: clientTimeout}
			token := "w" + strconv.Itoa(w)
			for i := 0; time.Now().Before(deadline); i++ {
				var status int
				var body []byte
				var err error
				if i%2 == 0 {
					status, body, err = doRequest(client, svc.addr, token, "POST", "/jobs",
						fmt.Sprintf(`{"queue":"q%d","payload":"p","max_tries":3}`, w%4))
				} else {
					status, body, err = doRequest(client, svc.addr, token, "POST", fmt.Sprintf("/queues/q%d/lease", w%4), `{"lease_ms":60000}`)
				}
				switch {
				case err != nil, status == 503:
					failures.Add(1)
				case status == 201:
					mu.Lock()
					created[decodeID(body)] = true
					mu.Unlock()
				case status < 200 || status >= 500:
					t.Errorf("status %d %s", status, body)
					return
				}
			}
		}()
	}
	wg.Wait()
	restarts := svc.board.Restarts()
	if restarts == 0 || failures.Load() == 0 {
		t.Fatalf("restarts %d, failures %d: the switch did nothing", restarts, failures.Load())
	}
	client := &http.Client{Timeout: clientTimeout}
	present := func(addr string) {
		t.Helper()
		if !svc.board.waitReady(ctx(t)) {
			t.Fatal("the board gave up")
		}
		for id := range created {
			if status, body, err := doRequest(client, addr, "p", "GET", "/jobs/"+id, ""); err != nil || status != 200 {
				t.Fatalf("GET %s = %d %s %v", id, status, body, err)
			}
		}
	}
	present(svc.addr)
	// /health within a second of a failure, on the log the load made.
	for range 5 {
		before := svc.board.Restarts()
		for {
			status, _, err := doRequest(client, svc.addr, "p", "POST", "/jobs", `{"queue":"x","payload":"p","max_tries":1}`)
			if err != nil {
				t.Fatal(err)
			}
			if status == 503 {
				break
			}
		}
		failedAt := time.Now()
		for {
			status, body, err := doRequest(client, svc.addr, "-", "GET", "/health", "")
			if err == nil && status == 200 {
				var h Health
				if json.Unmarshal(body, &h) != nil || h.Restarts != before+1 {
					t.Fatalf("health after a restart: %s", body)
				}
				break
			}
			if time.Since(failedAt) > time.Second {
				t.Fatalf("/health was not 200 within a second of a failure: %d %v", status, err)
			}
			time.Sleep(5 * time.Millisecond)
		}
	}
	if err := svc.stop(); err != nil {
		t.Fatal(err)
	}
	ln, err = net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	svc, err = startService(dir, realClock{}, ln, idleTimeout)
	if err != nil {
		t.Fatal(err)
	}
	defer svc.stop()
	present(svc.addr)
	if status, body, _ := doRequest(client, svc.addr, "-", "GET", "/health", ""); status != 200 || !strings.Contains(string(body), `"restarts":0`) {
		t.Errorf("health after a stop and a start: %d %s", status, body)
	}
}

// `jobq serve` with the switch on every write and a budget of 2 exits 70,
// and the folder verifies and opens.
func TestServeExits70WhenTheBudgetIsSpent(t *testing.T) {
	dir := t.TempDir()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := ln.Addr().String()
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	ln.Close()
	type result struct {
		code   int
		stderr string
	}
	done := make(chan result, 1)
	go func() {
		code, _, errOut := runCmd("serve", dir, "--crash-every", "1", "--max-restarts", "2", "--port", port, "--restart-window", "60")
		done <- result{code, errOut}
	}()
	client := &http.Client{Timeout: clientTimeout}
	var res result
	acked := 0
loop:
	for {
		select {
		case res = <-done:
			break loop
		case <-time.After(10 * time.Second):
			t.Fatal("serve did not exit")
		default:
		}
		if status, _, err := doRequest(client, addr, "p", "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`); err == nil && status == 201 {
			acked++
		}
		time.Sleep(2 * time.Millisecond)
	}
	if res.code != 70 || !strings.Contains(res.stderr, "giving up") {
		t.Fatalf("serve = %d, %s", res.code, res.stderr)
	}
	if acked != 0 {
		t.Errorf("%d writes answered 201 with every write failing", acked)
	}
	if code, out, errOut := runCmd("verify", dir); code != 0 || !strings.HasPrefix(out, "3 jobs:") {
		t.Errorf("verify = %d, %q, %q", code, out, errOut)
	}
	data, err := os.ReadFile(filepath.Join(dir, logName))
	if err != nil || !bytes.HasSuffix(data, []byte("\n")) {
		t.Errorf("the log is not whole: %v", err)
	}
}

func TestServeOptions(t *testing.T) {
	dir := t.TempDir()
	for _, args := range [][]string{
		{"serve", dir, "--crash-every"}, {"serve", dir, "--crash-every", "-1"},
		{"serve", dir, "--crash-every", "x"}, {"serve", dir, "--max-restarts", "05"},
		{"serve", dir, "--restart-window", "0"}, {"serve", dir, "--port", "1", "--port", "2"},
		{"serve", dir, "--bogus", "1"}, {"serve", "--port", "1"},
		{"compact", dir, "--crash-every", "1"}, {"verify", dir, "--crash-every", "1"},
		{"check", dir, "s", "--crash-every", "1"},
	} {
		if code, _, errOut := runCmd(args...); code != 2 {
			t.Errorf("jobq %q = %d, %s; want 2", args, code, errOut)
		}
	}
	d, port, cfg, msg := parseServe([]string{dir, "--restart-window", "5", "--crash-every", "10", "--max-restarts", "0", "--port", "8000"})
	if msg != "" || d != dir || port != 8000 || cfg.Window != 5*time.Second || cfg.CrashEvery != 10 || cfg.MaxRestarts != 0 {
		t.Errorf("parseServe = %q %d %+v %q", d, port, cfg, msg)
	}
	if _, port, cfg, _ := parseServe([]string{dir}); port != defaultPort || cfg.MaxRestarts != 5 || cfg.Window != time.Minute || cfg.CrashEvery != 0 {
		t.Errorf("defaults = %d %+v", port, cfg)
	}
}

// A store that fails while the board closes it: the board gives up rather
// than crash or serve a store in an unknown state.
func TestARestartThatFailsGivesUp(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	h.file.fail = func(string) bool { panic("the store blew up") }
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"q","max_tries":2}`, 503)
	select {
	case <-h.board.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the board did not give up")
	}
	h.file.fail = nil
	if got := replayBytes(t, h.file.data); len(got.jobs) != 1 {
		t.Errorf("the log holds %d jobs, want 1", len(got.jobs))
	}
}
