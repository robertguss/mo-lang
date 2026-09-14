package main

import (
	"context"
	"encoding/json"
	"errors"
	"math/rand"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func newClock() *fakeClock {
	return &fakeClock{t: time.Date(2026, 9, 14, 10, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func bg() context.Context { return context.Background() }

// openTestQueue opens a real store on dir; it closes when the test ends.
func openTestQueue(t *testing.T, dir string, clock *fakeClock) (*Queue, *store) {
	t.Helper()
	st, err := openStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	q, err := loadQueue(st, QueueConfig{Now: clock.Now})
	if err != nil {
		_ = st.close()
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.close() })
	return q, st
}

var errInjected = errors.New("injected fault")

// faultFile fails the next scripted calls, or each call with chance rate.
type faultFile struct {
	f                        *os.File
	rng                      *rand.Rand
	rate                     float64
	writes, syncs, truncates int
}

func (ff *faultFile) roll(n *int) bool {
	if *n > 0 {
		*n--
		return true
	}
	return ff.rng != nil && ff.rng.Float64() < ff.rate
}

func (ff *faultFile) Write(p []byte) (int, error) {
	if ff.roll(&ff.writes) {
		cut := len(p) / 2
		if ff.rng != nil {
			cut = ff.rng.Intn(len(p) + 1)
		}
		n, err := ff.f.Write(p[:cut])
		if err != nil {
			return n, err
		}
		return n, errInjected
	}
	return ff.f.Write(p)
}

// Sync does not reach the disk: the tests check the log's contents, not
// power loss, and a real fsync per record would make 100 seeds slow.
func (ff *faultFile) Sync() error {
	if ff.roll(&ff.syncs) {
		return errInjected
	}
	return nil
}

func (ff *faultFile) Truncate(size int64) error {
	if ff.roll(&ff.truncates) {
		return errInjected
	}
	return ff.f.Truncate(size)
}

// faultyQueue is a queue whose log appends through ff into <dir>/jobq.log.
func faultyQueue(t *testing.T, dir string, clock *fakeClock, ff *faultFile) *Queue {
	t.Helper()
	f, err := os.OpenFile(filepath.Join(dir, logName), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.Close() })
	ff.f = f
	q := newQueue(QueueConfig{Now: clock.Now})
	q.log = NewLog(ff, 0)
	return q
}

// replayDir reads <dir>/jobq.log back into a fresh queue.
func replayDir(t *testing.T, dir string) *Queue {
	t.Helper()
	f, err := os.Open(filepath.Join(dir, logName))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	q := newQueue(QueueConfig{Now: newClock().Now})
	if _, err := replay(f, q.replayRecord); err != nil {
		t.Fatal(err)
	}
	return q
}

// snapshot is every job as its JSON, by id.
func snapshot(t *testing.T, q *Queue) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, e := range q.jobs {
		b, err := json.Marshal(e.job)
		if err != nil {
			t.Fatal(err)
		}
		out[e.job.ID] = string(b)
	}
	return out
}

func sameJobs(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

// harness drives the API in process.
type harness struct {
	t     *testing.T
	q     *Queue
	api   *API
	clock *fakeClock
	dir   string
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	dir := t.TempDir()
	clock := newClock()
	q, _ := openTestQueue(t, dir, clock)
	return &harness{t: t, q: q, api: &API{q: q, requestTimeout: time.Second}, clock: clock, dir: dir}
}

// do sends one request; a token of "-" sends no authorization header.
func (h *harness) do(token, method, path, body string) (int, map[string]any, *httptest.ResponseRecorder) {
	h.t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "-" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.api.ServeHTTP(rec, req)
	var out map[string]any
	if rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			h.t.Fatalf("%s %s: body %q is not a JSON object: %v", method, path, rec.Body.String(), err)
		}
	}
	return rec.Code, out, rec
}

// want sends a request and fails the test unless the status matches.
func (h *harness) want(status int, token, method, path, body string) map[string]any {
	h.t.Helper()
	got, out, rec := h.do(token, method, path, body)
	if got != status {
		h.t.Fatalf("%s %s %s: status %d, want %d, body %s", token, method, path, got, status, rec.Body.String())
	}
	return out
}

func (h *harness) create(queue string, maxAttempts int) string {
	h.t.Helper()
	body, err := json.Marshal(map[string]any{"queue": queue, "payload": "p", "max_attempts": maxAttempts})
	if err != nil {
		h.t.Fatal(err)
	}
	return h.want(201, "producer", "POST", "/jobs", string(body))["id"].(string)
}
