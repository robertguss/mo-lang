package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// The --sim 100 --faults run: 100 seeds, each a deterministic run of
// producers and workers against the API with injected file failures (failed
// and partial writes, failed syncs and truncates) and socket failures (a
// request lost before the handler, a response lost after it). After every
// step: each response was correct or a 503 that wrote nothing but due lease
// expiries; the log replays to exactly what memory holds; no job was held by
// two workers; attempts never exceed max_attempts. Then the faults stop and
// the workers keep working until every job is done or dead.
func TestSim100Faults(t *testing.T) {
	seeds := 100
	if testing.Short() {
		seeds = 10
	}
	for seed := 1; seed <= seeds; seed++ {
		t.Run(fmt.Sprintf("seed-%d", seed), func(t *testing.T) {
			t.Parallel()
			runSim(t, int64(seed))
		})
	}
}

type holding struct {
	worker string
	until  time.Time
}

type sim struct {
	t          *testing.T
	rng        *rand.Rand
	clock      *fakeClock
	q          *Queue
	api        *API
	ff         *faultFile
	dir        string
	socketRate float64
	holders    map[string]holding  // what workers were told, by job id
	held       map[string][]string // job ids each worker believes it holds
	log        []string
}

var simWorkers = []string{"w1", "w2", "w3"}
var simQueues = []string{"mail", "thumbs"}

func runSim(t *testing.T, seed int64) {
	rng := rand.New(rand.NewSource(seed))
	dir := t.TempDir()
	clock := newClock()
	ff := &faultFile{rng: rng, rate: 0.08}
	q := faultyQueue(t, dir, clock, ff)
	s := &sim{t: t, rng: rng, clock: clock, q: q, api: &API{q: q, requestTimeout: time.Second}, ff: ff, dir: dir,
		socketRate: 0.1, holders: map[string]holding{}, held: map[string][]string{}}
	defer func() {
		if t.Failed() {
			t.Logf("seed %d, last steps:\n%s", seed, strings.Join(s.log[max(0, len(s.log)-15):], "\n"))
		}
	}()
	for step := 0; step < 250 && !t.Failed(); step++ {
		s.step(true)
	}
	ff.rate, s.socketRate = 0, 0
	for step := 0; !t.Failed(); step++ {
		if q.counts[Queued] == 0 && q.counts[Leased] == 0 {
			break
		}
		if step > 20_000 {
			t.Fatalf("seed %d: jobs never drained: %v", seed, q.counts)
		}
		s.step(false)
	}
	for _, e := range q.jobs {
		if e.job.State != Done && e.job.State != Dead {
			t.Errorf("seed %d: %s is %s after the faults stopped", seed, e.job.ID, e.job.State)
		}
	}
}

// step advances the clock and plays one request. With create false only
// workers act: lease, then ack or fail what they hold.
func (s *sim) step(create bool) {
	s.clock.Advance(time.Duration(s.rng.Intn(120)) * time.Millisecond)
	w := simWorkers[s.rng.Intn(len(simWorkers))]
	roll := s.rng.Intn(100)
	switch {
	case create && roll < 25:
		body := fmt.Sprintf(`{"queue":%q,"payload":"job %d","max_attempts":%d}`, simQueues[s.rng.Intn(2)], s.rng.Intn(1000), 1+s.rng.Intn(4))
		s.play("producer", "POST", "/jobs", body)
	case roll < 60 || len(s.held[w]) == 0:
		s.play(w, "POST", "/queues/"+simQueues[s.rng.Intn(2)]+"/lease", fmt.Sprintf(`{"lease_ms":%d}`, 100+s.rng.Intn(900)))
	case create && roll < 65:
		s.play(w, "POST", fmt.Sprintf("/jobs/j_%d/ack", 1+s.rng.Intn(int(s.q.next))), "")
	case create && roll < 70:
		s.play(w, []string{"GET", "DELETE"}[s.rng.Intn(2)], fmt.Sprintf("/jobs/j_%d", 1+s.rng.Intn(int(s.q.next))), "")
	case create && roll < 73:
		s.play(w, "GET", "/health", "")
	default:
		ids := s.held[w]
		id := ids[s.rng.Intn(len(ids))]
		if s.rng.Intn(10) < 7 {
			s.play(w, "POST", "/jobs/"+id+"/ack", "")
		} else {
			s.play(w, "POST", "/jobs/"+id+"/fail", `{"reason":"sim"}`)
		}
	}
}

// play sends one request through the fault model and checks everything
// that must hold after it.
func (s *sim) play(token, method, path, body string) {
	t := s.t
	t.Helper()
	before := map[string]Job{}
	for _, e := range s.q.jobs {
		before[e.job.ID] = e.job
	}
	records, expired, next := s.q.log.Records(), s.q.expired, s.q.next
	now := s.clock.Now()

	if s.rng.Float64() < s.socketRate/2 {
		s.log = append(s.log, fmt.Sprintf("%s %s %s %s -> lost before the handler", token, method, path, body))
		return
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	s.api.ServeHTTP(rec, req)
	delivered := s.rng.Float64() >= s.socketRate/2
	s.log = append(s.log, fmt.Sprintf("%s %s %s %s -> %d %s (delivered %v)", token, method, path, body, rec.Code, rec.Body.String(), delivered))

	var resp Job
	if rec.Code == 200 || rec.Code == 201 {
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("response is not JSON: %v", err)
		}
	}
	after := func(id string) (Job, bool) {
		n, _ := parseID(id)
		e, ok := s.q.jobs[n]
		if !ok {
			return Job{}, false
		}
		return e.job, true
	}
	isLease := strings.HasSuffix(path, "/lease")
	isAck := strings.HasSuffix(path, "/ack")
	isFail := strings.HasSuffix(path, "/fail")

	switch rec.Code {
	case 500:
		t.Fatalf("500: %s", rec.Body.String())
	case 503:
		if s.q.log.Records()-records != s.q.expired-expired {
			t.Fatalf("a 503 wrote %d records beyond %d expiries", s.q.log.Records()-records, s.q.expired-expired)
		}
		if s.q.next != next {
			t.Fatalf("a 503 moved the id counter")
		}
	case 201:
		if j, ok := after(resp.ID); !ok || j.State != Queued || s.q.next != next+1 {
			t.Fatalf("201 but the job is %+v", j)
		}
	case 200:
		switch {
		case isLease:
			old := before[resp.ID]
			if !(old.State == Queued || old.State == Leased && !old.LeaseUntil.After(now)) {
				t.Fatalf("leased %s while it was %s until %v (now %v)", resp.ID, old.State, old.LeaseUntil, now)
			}
			j, _ := after(resp.ID)
			if j.State != Leased || j.Worker != token || j.Attempts != old.Attempts+1 || j.Attempts > j.MaxAttempts {
				t.Fatalf("lease 200 but the job is %+v (was %+v)", j, old)
			}
			if delivered {
				if h, ok := s.holders[resp.ID]; ok && h.until.After(now) {
					t.Fatalf("%s handed to %s while %s holds it until %v", resp.ID, token, h.worker, h.until)
				}
				s.holders[resp.ID] = holding{worker: token, until: resp.LeaseUntil.Time}
				s.held[token] = append(s.held[token], resp.ID)
			}
		case isAck || isFail:
			old := before[resp.ID]
			j, _ := after(resp.ID)
			if old.State != Leased || old.Worker != token || !old.LeaseUntil.After(now) {
				t.Fatalf("%s 200 without a live lease: was %+v", path, old)
			}
			if isAck && j.State != Done || isFail && j.State != map[bool]State{true: Dead, false: Queued}[j.Attempts == j.MaxAttempts] {
				t.Fatalf("%s 200 but the job is %+v", path, j)
			}
			// The holder gave the job up itself, whether or not it heard back.
			delete(s.holders, resp.ID)
		}
	case 204:
		if isLease {
			queue := strings.Split(path, "/")[2]
			for _, e := range s.q.jobs {
				if e.job.Queue == queue && e.job.State == Queued {
					t.Fatalf("204 while %s is queued", e.job.ID)
				}
			}
		}
	case 409:
		if isAck || isFail {
			id := strings.Split(path, "/")[2]
			if j, ok := after(id); ok && j.State == Leased && j.Worker == token && before[id].State == Leased && before[id].Worker == token && before[id].LeaseUntil.After(now) {
				t.Fatalf("409 but %s holds a live lease on %s", token, id)
			}
		}
	}
	if delivered && (isAck || isFail) && rec.Code != 503 {
		id := strings.Split(path, "/")[2]
		s.held[token] = remove(s.held[token], id)
	}
	s.checkState()
}

// checkState: attempts never exceed max_attempts, and the log replays to
// memory. While the log is broken (a failed write whose cut also failed)
// the file holds bytes the next append removes first, so replay waits.
func (s *sim) checkState() {
	for _, e := range s.q.jobs {
		if e.job.Attempts > e.job.MaxAttempts {
			s.t.Fatalf("%s has %d attempts of %d", e.job.ID, e.job.Attempts, e.job.MaxAttempts)
		}
	}
	if s.q.log.broken {
		return
	}
	back := replayDir(s.t, s.dir)
	if !sameJobs(snapshot(s.t, back), snapshot(s.t, s.q)) || back.next != s.q.next {
		s.t.Fatalf("the log does not replay to memory: next %d vs %d", back.next, s.q.next)
	}
}

func remove(ids []string, id string) []string {
	out := ids[:0]
	for _, x := range ids {
		if x != id {
			out = append(out, x)
		}
	}
	return out
}
