package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"
)

// The Go reading of `--sim 100 --faults`: 100 seeds, each running producers
// and workers against the API while the store's file fails writes, syncs,
// and truncates and the transport loses requests and responses. After every
// request: memory equals a replay of the durable records, a 503 left the
// queue unchanged, and any other status is what a model of the spec gives
// for the state before the request. When the faults stop the workers keep
// working until every job is done or dead, and a full replay equals memory.
//
// Change 4: the archive is a second in-memory file that fails the same way,
// so the archive move's two writes fail on either side of each other, and
// retain is short enough that jobs are archived, read, retried, and deleted
// under the faults. A third of the creates carry one of a few keys.

const (
	simSeeds      = 100
	simFaultSteps = 400
	simFaultRate  = 0.1
	simLossRate   = 0.05
	simRetain     = 1500 * time.Millisecond
)

type simulation struct {
	t      *testing.T
	seed   uint64
	rng    *rand.Rand
	clock  *manualClock
	file   *memFile
	store  *Store
	arch   *memFile
	astore *Store
	q      *Queue
	api    *API
	faults bool
	steps  int

	mirror     *Queue // replay of the durable records so far
	mirrorSize int64
	durable    []byte
	archSize   int64
	archBytes  []byte

	created  map[string]bool
	deleted  map[string]bool
	held     map[string][]string // worker -> ids it was told it holds
	saw503   int
	sawSched int // requests that found a job scheduled
	sawRetry int // retries that took a dead job back
	sawArch  int // requests that read, retried, or deleted an archived job
	sawKey   int // keyed creates answered from the key map
	sawSplit int // archive moves on disk whose arch record the log lacks
}

func TestSimulationWithFaults(t *testing.T) {
	total503, totalSched, totalRetry, totalArch, totalKey, totalSplit := 0, 0, 0, 0, 0, 0
	for seed := uint64(1); seed <= simSeeds; seed++ {
		s := newSimulation(t, seed)
		s.run()
		total503 += s.saw503
		totalSched += s.sawSched
		totalRetry += s.sawRetry
		totalArch += s.sawArch
		totalKey += s.sawKey
		totalSplit += s.sawSplit
	}
	if totalArch == 0 || totalKey == 0 || totalSplit == 0 {
		t.Errorf("the simulation never touched an archived job (%d), hit a key (%d), or split the move (%d)",
			totalArch, totalKey, totalSplit)
	}
	if total503 == 0 {
		t.Error("no fault ever reached a response; the simulation tests nothing")
	}
	if totalSched == 0 || totalRetry == 0 {
		t.Errorf("the simulation never scheduled a job (%d) or retried a dead one (%d)", totalSched, totalRetry)
	}
}

func newSimulation(t *testing.T, seed uint64) *simulation {
	s := &simulation{
		t: t, seed: seed, rng: rand.New(rand.NewPCG(seed, 0x5eed)),
		clock:   newManualClock(time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)),
		created: map[string]bool{}, deleted: map[string]bool{}, held: map[string][]string{},
	}
	s.file = &memFile{
		fail: func(string) bool { return s.faults && s.rng.Float64() < simFaultRate },
		cut:  func(n int) int { return s.rng.IntN(n + 1) },
	}
	s.store = &Store{f: s.file}
	s.arch = &memFile{
		fail: func(string) bool { return s.faults && s.rng.Float64() < simFaultRate },
		cut:  func(n int) int { return s.rng.IntN(n + 1) },
	}
	s.astore = &Store{f: s.arch}
	s.q = newQueue(s.clock)
	s.q.archive, s.q.retain = s.astore, simRetain
	s.q.finishReplay(s.store)
	s.api = &API{b: fixedBoard(t, s.q, s.store)}
	s.mirror = newQueue(s.clock)
	return s
}

func (s *simulation) fatalf(format string, args ...any) {
	s.t.Helper()
	s.t.Fatalf("seed %d step %d: %s", s.seed, s.steps, fmt.Sprintf(format, args...))
}

func (s *simulation) run() {
	s.faults = true
	for range simFaultSteps {
		s.randomStep()
		s.clock.Advance(time.Duration(s.rng.IntN(150)) * time.Millisecond)
	}
	s.faults = false
	s.drain()
	for _, st := range []*Store{s.store, s.astore} {
		if err := st.repair(); err != nil {
			s.fatalf("store not clean after the faults: %v", err)
		}
	}
	if int64(len(s.file.data)) != s.store.size || int64(len(s.arch.data)) != s.astore.size {
		s.fatalf("a store has a tail after the faults")
	}
	full := replayBoth(s.t, s.arch.data, s.file.data)
	if !reflect.DeepEqual(snapshot(full), snapshot(s.q)) {
		s.fatalf("a job was lost: replay differs from memory")
	}
	for id := range s.created {
		if ok := s.q.lookup(mustID(id)) != nil; ok == s.deleted[id] {
			s.fatalf("job %s: present %v, deleted %v", id, ok, s.deleted[id])
		}
	}
	if n := len(s.q.jobs) + len(s.q.archived); n != len(s.created)-len(s.deleted) {
		s.fatalf("%d jobs, want %d", n, len(s.created)-len(s.deleted))
	}
}

func mustID(s string) uint64 {
	id, _ := parseID(s)
	return id
}

var simWorkers = []string{"w0", "w1", "w2", "w3"}

func (s *simulation) randomStep() {
	queue := []string{"a", "b"}[s.rng.IntN(2)]
	worker := simWorkers[s.rng.IntN(len(simWorkers))]
	switch r := s.rng.IntN(100); {
	case r < 25:
		max := 1 + s.rng.IntN(4)
		if s.rng.IntN(20) == 0 {
			max = 0
		}
		delay, backoff := 0, 0
		if s.rng.IntN(3) == 0 {
			delay = s.rng.IntN(300)
		}
		if s.rng.IntN(3) == 0 {
			backoff = s.rng.IntN(400)
		}
		key := ""
		if s.rng.IntN(3) == 0 {
			key = fmt.Sprintf(`"key":"k%d",`, s.rng.IntN(4))
		}
		s.send("prod", "POST", "/jobs", fmt.Sprintf(`{"queue":%q,%s"payload":"p%d","max_tries":%d,"delay_ms":%d,"backoff_ms":%d}`,
			queue, key, s.steps, max, delay, backoff))
	case r < 55:
		s.send(worker, "POST", "/queues/"+queue+"/lease", fmt.Sprintf(`{"lease_ms":%d}`, 100+s.rng.IntN(300)))
	case r < 70:
		s.send(worker, "POST", "/jobs/"+s.pickHeld(worker)+"/ack", "")
	case r < 80:
		s.send(worker, "POST", "/jobs/"+s.pickHeld(worker)+"/fail", `{"reason":"sim"}`)
	case r < 85:
		s.send("prod", "GET", "/jobs/"+s.randomID(), "")
	case r < 90:
		s.send("prod", "DELETE", "/jobs/"+s.randomID(), "")
	case r < 93:
		if s.rng.IntN(2) == 0 {
			s.send("prod", "GET", "/jobs?queue="+queue, "")
		} else {
			s.send("prod", "GET", fmt.Sprintf("/jobs?queue=%s&key=k%d", queue, s.rng.IntN(4)), "")
		}
	case r < 94:
		s.send("", "GET", "/health", "")
	case r < 96:
		s.send("prod", "GET", "/queues", "")
	case r < 99:
		s.send("prod", "POST", "/jobs/"+s.randomID()+"/retry", "")
	default:
		s.send("", "POST", "/jobs", `{"queue":"a","payload":"x","max_tries":1}`)
	}
}

func (s *simulation) randomID() string { return formatID(1 + uint64(s.rng.IntN(int(s.q.nextID)+1))) }

func (s *simulation) pickHeld(worker string) string {
	if ids := s.held[worker]; len(ids) > 0 && s.rng.IntN(5) != 0 {
		return ids[s.rng.IntN(len(ids))]
	}
	return s.randomID()
}

// send plays one request through the lossy transport and checks it.
func (s *simulation) send(token, method, path, body string) (int, []byte, bool) {
	s.steps++
	pre := snapshot(s.q)
	now := s.clock.Now()
	if s.faults && s.rng.Float64() < simLossRate {
		return 0, nil, false
	}
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	s.api.ServeHTTP(rec, req)
	s.checkDurable()
	if len(s.q.unlogged) > 0 {
		s.sawSplit++
	}
	if !s.faults {
		for id, j := range model(pre, now) {
			if j.ArchivedAt == nil && s.q.archived[mustID(id)] == nil && due(j, now) {
				s.fatalf("%s is due for the archive and still on the board", id)
			}
		}
	}
	for _, j := range s.q.jobs {
		if j.State == Scheduled {
			s.sawSched++
			break
		}
	}
	if rec.Code == http.StatusOK && strings.HasSuffix(path, "/retry") {
		s.sawRetry++
	}
	if rec.Code == http.StatusCreated {
		s.created[decodeID(rec.Body.Bytes())] = true
	}
	if method == "DELETE" && rec.Code == http.StatusNoContent {
		s.deleted[strings.TrimPrefix(path, "/jobs/")] = true
	}
	if rec.Code == http.StatusServiceUnavailable {
		s.saw503++
		if !s.faults {
			s.fatalf("503 with no faults: %s", rec.Body)
		}
		if !reflect.DeepEqual(unarchived(snapshot(s.q)), unarchived(pre)) {
			s.fatalf("%s %s answered 503 but changed the queue", method, path)
		}
	} else {
		s.checkAnswer(pre, now, token, method, path, body, rec.Code, rec.Body.Bytes())
	}
	if s.faults && s.rng.Float64() < simLossRate {
		return rec.Code, nil, false
	}
	s.learn(token, path, rec.Code, rec.Body.Bytes())
	return rec.Code, rec.Body.Bytes(), true
}

// unarchived is a snapshot with archived_at dropped: a look's archive move
// is on disk before any answer, a 503 included, and changes nothing else.
func unarchived(m map[string]jobJSON) map[string]jobJSON {
	out := make(map[string]jobJSON, len(m))
	for id, j := range m {
		j.ArchivedAt = nil
		out[id] = j
	}
	return out
}

// due is the archive rule on a stored job.
func due(j jobJSON, now time.Time) bool {
	job, _ := jobFromView(j)
	_, ok := archiveStep(job, now, simRetain)
	return ok
}

// checkDurable: the records before the last known size never change, and
// memory equals their replay, the archive's new records first, as the
// archive's write comes first.
func (s *simulation) checkDurable() {
	arch := s.arch.data
	if int64(len(arch)) < s.astore.size || !bytes.Equal(arch[:s.archSize], s.archBytes) {
		s.fatalf("durable archive records changed")
	}
	if _, err := replay(bytes.NewReader(arch[s.archSize:s.astore.size]), s.mirror.applyArchived); err != nil {
		s.fatalf("replaying new archive records: %v", err)
	}
	s.archBytes = append(s.archBytes, arch[s.archSize:s.astore.size]...)
	s.archSize = s.astore.size
	data := s.file.data
	if int64(len(data)) < s.store.size || !bytes.Equal(data[:s.mirrorSize], s.durable) {
		s.fatalf("durable records changed")
	}
	n, err := replay(bytes.NewReader(data[s.mirrorSize:s.store.size]), s.mirror.applyRecord)
	if err != nil || n != s.store.size-s.mirrorSize {
		s.fatalf("replaying new records: %d bytes, %v", n, err)
	}
	s.durable = append(s.durable, data[s.mirrorSize:s.store.size]...)
	s.mirrorSize = s.store.size
	if !s.store.dirty && int64(len(data)) != s.store.size {
		s.fatalf("a clean store has a tail")
	}
	if !reflect.DeepEqual(snapshot(s.mirror), snapshot(s.q)) {
		s.fatalf("memory differs from the durable records")
	}
}

// model is the spec's state after the look a request makes at now: every
// lease that ran out ends by the try rule, then every run_at that has passed
// queues its job.
func model(pre map[string]jobJSON, now time.Time) map[string]jobJSON {
	m := make(map[string]jobJSON, len(pre))
	for id, j := range pre {
		if j.State == Leased {
			until, _ := time.Parse(timeLayout, *j.LeaseUntil)
			if !until.After(now) {
				j.State, j.Worker, j.LeaseUntil = Queued, nil, nil
				switch {
				case j.Tries >= j.MaxTries:
					j.State = Dead
				case j.BackoffMS > 0:
					runAt := formatTime(now.Add(time.Duration(j.BackoffMS) * time.Millisecond))
					j.State, j.RunAt = Scheduled, &runAt
				}
			}
		}
		if j.State == Scheduled {
			runAt, _ := time.Parse(timeLayout, *j.RunAt)
			if !runAt.After(now) {
				j.State, j.RunAt = Queued, nil
			}
		}
		m[id] = j
	}
	return m
}

func (s *simulation) checkAnswer(pre map[string]jobJSON, now time.Time, token, method, path, body string, status int, resp []byte) {
	m := model(pre, now)
	seg := strings.Split(strings.TrimPrefix(path, "/"), "/")
	want := 0
	var job jobJSON
	if status == 200 || status == 201 {
		if err := json.Unmarshal(resp, &job); err != nil {
			s.fatalf("body %s: %v", resp, err)
		}
	}
	switch {
	case token == "" && path != "/health":
		want = 401
	case method == "POST" && path == "/jobs":
		var b struct {
			MaxTries  int   `json:"max_tries"`
			DelayMS   int64 `json:"delay_ms"`
			BackoffMS int64 `json:"backoff_ms"`
		}
		_ = json.Unmarshal([]byte(body), &b)
		var k struct {
			Queue string `json:"queue"`
			Key   string `json:"key"`
		}
		_ = json.Unmarshal([]byte(body), &k)
		if hit := keyed(pre, k.Queue, k.Key); k.Key != "" && hit != "" {
			want = 200
			s.sawKey++
			if status == 200 && job.ID != hit {
				s.fatalf("key %s answered %s, the key names %s", k.Key, job.ID, hit)
			}
			break
		}
		want = 201
		if b.MaxTries == 0 {
			want = 400
			break
		}
		created := Queued
		if b.DelayMS > 0 {
			created = Scheduled
		}
		if status == 201 && (job.State != created || job.Tries != 0 || job.BackoffMS != b.BackoffMS || pre[job.ID].ID != "" ||
			(k.Key != "" && (job.Key == nil || *job.Key != k.Key))) {
			s.fatalf("created %+v", job)
		}
	case method == "GET" && seg[0] == "health", method == "GET" && strings.HasPrefix(path, "/jobs?"):
		want = 200
		if status == 200 && strings.HasPrefix(path, "/jobs?") {
			s.checkList(pre, path, resp)
		}
	case method == "GET" && path == "/queues":
		want = 200
		if status == 200 {
			s.checkQueues(resp)
		}
	case method == "GET":
		want = 404
		if j, ok := m[seg[1]]; ok {
			want = 200
			s.sawArchived(seg[1])
			// A read is answered even while the store refuses writes, and
			// then the look's moves were undone: the job is as it was.
			if status == 200 && !sameJob(job, j) && !(s.faults && sameJob(job, pre[seg[1]])) {
				s.fatalf("get %s = %+v, model %+v", seg[1], job, j)
			}
		}
	case method == "DELETE":
		want = 204
		if j, ok := m[seg[1]]; !ok {
			want = 404
		} else if j.State == Leased {
			want = 409
		} else if status == 204 {
			s.sawArchived(seg[1])
		}
	case seg[0] == "queues":
		want = s.expectLease(m, seg[1], token, now, body, status, job)
	case len(seg) == 3 && seg[2] == "retry":
		want = 409
		if _, ok := m[seg[1]]; ok && s.q.archived[mustID(seg[1])] != nil {
			// Archived before or by this look: whether this look's move
			// reached the disk is the faults' to say, and memory tells.
			s.sawArchived(seg[1])
		} else if j, ok := m[seg[1]]; !ok {
			want = 404
		} else if j.State == Dead {
			want = 200
			if status == 200 && (job.State != Queued || job.Tries != 0 || job.Reason != nil) {
				s.fatalf("retry gave %+v", job)
			}
		}
	default:
		j, ok := m[seg[1]]
		want = 409
		if !ok {
			want = 404
		} else if j.State == Leased && *j.Worker == token {
			want = 200
			if status == 200 && seg[2] == "ack" && job.State != Done {
				s.fatalf("ack gave %+v", job)
			}
			if status == 200 && seg[2] == "fail" {
				failed := Queued
				switch {
				case j.Tries >= j.MaxTries:
					failed = Dead
				case j.BackoffMS > 0:
					failed = Scheduled
				}
				if job.State != failed {
					s.fatalf("fail gave %+v from %+v", job, j)
				}
			}
		}
	}
	if status != want {
		s.fatalf("%s %s %s by %q = %d %s, model says %d", method, path, body, token, status, resp, want)
	}
}

func sameJob(a, b jobJSON) bool { return a.State == b.State && a.Tries == b.Tries }

// sawArchived counts a request that met an archived job.
func (s *simulation) sawArchived(id string) {
	if s.q.archived[mustID(id)] != nil {
		s.sawArch++
	}
}

// keyed is the id the key names in queue before the request, or "".
func keyed(pre map[string]jobJSON, queue, key string) string {
	for id, j := range pre {
		if j.Queue == queue && j.Key != nil && *j.Key == key {
			return id
		}
	}
	return ""
}

// checkList: a listing never shows an archived job but by its key, and a
// key lookup shows the job the key named.
func (s *simulation) checkList(pre map[string]jobJSON, path string, resp []byte) {
	var body struct {
		Jobs []jobJSON `json:"jobs"`
	}
	if err := json.Unmarshal(resp, &body); err != nil {
		s.fatalf("body %s: %v", resp, err)
	}
	query := strings.TrimPrefix(path, "/jobs?")
	queue, rest, _ := strings.Cut(strings.TrimPrefix(query, "queue="), "&")
	key, keyGiven := strings.CutPrefix(rest, "key=")
	if !keyGiven {
		for _, j := range body.Jobs {
			if j.ArchivedAt != nil {
				s.fatalf("a listing shows archived %s", j.ID)
			}
		}
		return
	}
	hit := keyed(pre, queue, key)
	if len(body.Jobs) > 1 || (len(body.Jobs) == 1) != (hit != "") || (hit != "" && body.Jobs[0].ID != hit) {
		s.fatalf("%s gave %s, the key names %q", path, resp, hit)
	}
}

// checkQueues: every queue in the answer is named once, the names are
// sorted, and the counts add up to the jobs in memory.
func (s *simulation) checkQueues(resp []byte) {
	var body struct {
		Queues []QueueCounts `json:"queues"`
	}
	if err := json.Unmarshal(resp, &body); err != nil {
		s.fatalf("body %s: %v", resp, err)
	}
	total := 0
	for i, c := range body.Queues {
		if i > 0 && body.Queues[i-1].Name >= c.Name {
			s.fatalf("/queues is not sorted by name: %s", resp)
		}
		n := c.Queued + c.Scheduled + c.Leased + c.Done + c.Dead
		if n == 0 {
			s.fatalf("queue %s is in the list with no job", c.Name)
		}
		total += n
	}
	if total != len(s.q.jobs) {
		// archived jobs are never counted
		s.fatalf("/queues counts %d jobs, memory holds %d", total, len(s.q.jobs))
	}
}

// expectLease: the oldest queued job of the queue, leased to the caller with
// tries one higher, and never a job someone still holds.
func (s *simulation) expectLease(m map[string]jobJSON, queue, token string, now time.Time, body string, status int, job jobJSON) int {
	var oldest jobJSON
	for _, j := range m {
		if j.Queue == queue && j.State == Queued && (oldest.ID == "" || mustID(j.ID) < mustID(oldest.ID)) {
			oldest = j
		}
	}
	if oldest.ID == "" {
		return 204
	}
	if status == 200 {
		var b struct {
			LeaseMS int64 `json:"lease_ms"`
		}
		_ = json.Unmarshal([]byte(body), &b)
		until := formatTime(now.Add(time.Duration(b.LeaseMS) * time.Millisecond))
		if job.ID != oldest.ID || job.State != Leased || *job.Worker != token || job.Tries != oldest.Tries+1 || *job.LeaseUntil != until {
			s.fatalf("lease gave %+v, model says %+v leased to %s until %s", job, oldest, token, until)
		}
	}
	return 200
}

// learn records the jobs a worker was told it holds.
func (s *simulation) learn(token, path string, status int, resp []byte) {
	if status == 200 && strings.HasPrefix(path, "/queues/") {
		s.held[token] = append(s.held[token], decodeID(resp))
	}
}

// drain runs the workers with no faults until every job is done or dead.
func (s *simulation) drain() {
	for round := 0; ; round++ {
		if round > 5000 {
			s.fatalf("jobs never finished: %v", snapshot(s.q))
		}
		open := 0
		for _, j := range s.q.jobs {
			if j.State == Queued || j.State == Leased || j.State == Scheduled {
				open++
			}
		}
		if open == 0 {
			return
		}
		leasedAny := false
		for _, w := range simWorkers {
			for _, queue := range []string{"a", "b"} {
				status, resp, _ := s.send(w, "POST", "/queues/"+queue+"/lease", `{"lease_ms":100}`)
				if status != 200 {
					continue
				}
				leasedAny = true
				id := decodeID(resp)
				if s.rng.IntN(10) < 7 {
					s.send(w, "POST", "/jobs/"+id+"/ack", "")
				} else {
					s.send(w, "POST", "/jobs/"+id+"/fail", `{"reason":"drain"}`)
				}
			}
		}
		if !leasedAny {
			s.clock.Advance(500 * time.Millisecond)
		}
	}
}

func decodeID(resp []byte) string {
	var j jobJSON
	_ = json.Unmarshal(resp, &j)
	return j.ID
}
