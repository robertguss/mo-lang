package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"
)

func keys(m map[string]any) string {
	var ks []string
	for k := range m {
		ks = append(ks, k)
	}
	slices.Sort(ks)
	return strings.Join(ks, ",")
}

func TestCreateShape(t *testing.T) {
	h := newHarness(t)
	j := h.want(201, "p", "POST", "/jobs", `{"queue": "emails", "payload": "hi", "max_attempts": 3}`)
	if keys(j) != "attempts,created_at,id,max_attempts,payload,queue,state,updated_at" {
		t.Errorf("keys %s", keys(j))
	}
	if j["id"] != "j_1" || j["state"] != "queued" || j["attempts"] != 0.0 || j["max_attempts"] != 3.0 || j["created_at"] != "2026-09-14T10:00:00.000Z" {
		t.Errorf("job %v", j)
	}
	if got := h.want(200, "p", "GET", "/jobs/j_1", ""); keys(got) != keys(j) || got["payload"] != "hi" {
		t.Errorf("get %v", got)
	}
}

func TestBadBodiesAre400(t *testing.T) {
	h := newHarness(t)
	for _, body := range []string{
		``, `not json`, `[]`, `null`, `{}`, `{"queue":"q","payload":"p"}`,
		`{"queue":"q","payload":"p","max_attempts":"3"}`, `{"queue":"q","payload":"p","max_attempts":3.5}`,
		`{"queue":"q","payload":7,"max_attempts":3}`, `{"queue":"q","payload":"p","max_attempts":3,"extra":1}`,
		`{"queue":"q","payload":"p","max_attempts":3} {}`, `{"queue":"a b","payload":"p","max_attempts":3}`,
		`{"queue":"q","payload":"\u0000","max_attempts":3}`, `{"queue":"q","payload":"p","max_attempts":0}`,
		`{"queue":"q","payload":"p","max_attempts":101}`, "{\"queue\":\"q\",\"payload\":\"\xff\",\"max_attempts\":3}",
		`{"queue":"q","payload":"` + strings.Repeat("x", maxPayload+1) + `","max_attempts":3}`,
		`{"queue":"q","payload":"` + strings.Repeat("x", maxBody) + `","max_attempts":3}`,
	} {
		code, out, _ := h.do("p", "POST", "/jobs", body)
		if code != 400 || out["error"] == nil {
			t.Errorf("%.60q: %d %v", body, code, out)
		}
	}
	if len(h.q.jobs) != 0 {
		t.Errorf("a bad body made a job")
	}
}

func TestAuth(t *testing.T) {
	h := newHarness(t)
	for _, header := range []string{"", "Bearer", "Bearer ", "Bearer    ", "Basic dXNlcg==", "token"} {
		req := httptest.NewRequest("GET", "/jobs", nil)
		if header != "" {
			req.Header.Set("Authorization", header)
		}
		rec := httptest.NewRecorder()
		h.api.ServeHTTP(rec, req)
		if rec.Code != 401 {
			t.Errorf("%q: %d", header, rec.Code)
		}
	}
	req := httptest.NewRequest("GET", "/jobs", nil)
	req.Header.Set("Authorization", "bearer lower")
	rec := httptest.NewRecorder()
	h.api.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Errorf("lowercase scheme: %d", rec.Code)
	}
	health := h.want(200, "-", "GET", "/health", "")
	if keys(health) != "dead,done,leased,queued,uptime_ms" {
		t.Errorf("health keys %s", keys(health))
	}
}

func TestRoutesAndMethods(t *testing.T) {
	h := newHarness(t)
	h.create("q", 1)
	for _, c := range []struct {
		method, path string
		status       int
		allow        string
	}{
		{"GET", "/nope", 404, ""},
		{"GET", "/", 404, ""},
		{"GET", "/jobs/j_1/extra/more", 404, ""},
		{"GET", "/queues/q", 404, ""},
		{"GET", "/jobs/j_999", 404, ""},
		{"GET", "/jobs/nope", 404, ""},
		{"GET", "/jobs/", 404, ""},
		{"PUT", "/jobs", 405, "GET, POST"},
		{"POST", "/jobs/j_1", 405, "DELETE, GET"},
		{"GET", "/jobs/j_1/ack", 405, "POST"},
		{"DELETE", "/queues/q/lease", 405, "POST"},
		{"POST", "/health", 405, "GET"},
		{"POST", "/jobs/j_999/ack", 404, ""},
		{"POST", "/jobs/j_999/fail", 400, ""},
	} {
		code, _, rec := h.do("w", c.method, c.path, "")
		if code != c.status || rec.Header().Get("Allow") != c.allow {
			t.Errorf("%s %s: %d allow %q", c.method, c.path, code, rec.Header().Get("Allow"))
		}
	}
	if code, _, _ := h.do("w", "POST", "/jobs/j_999/fail", `{"reason":"x"}`); code != 404 {
		t.Errorf("fail of a missing job: %d", code)
	}
	if code, _, _ := h.do("-", "GET", "/nope", ""); code != 404 {
		t.Errorf("unknown route without a token: %d", code)
	}
}

func TestLeaseStatuses(t *testing.T) {
	h := newHarness(t)
	if code, _, rec := h.do("w", "POST", "/queues/q/lease", ""); code != 204 || rec.Body.Len() != 0 {
		t.Errorf("empty queue: %d %q", code, rec.Body.String())
	}
	h.create("q", 2)
	j := h.want(200, "w", "POST", "/queues/q/lease", "")
	if keys(j) != "attempts,created_at,id,lease_until,max_attempts,payload,queue,state,updated_at,worker" ||
		j["worker"] != "w" || j["lease_until"] != "2026-09-14T10:00:30.000Z" || j["attempts"] != 1.0 {
		t.Errorf("lease %v", j)
	}
	h.create("q", 2)
	if j := h.want(200, "w", "POST", "/queues/q/lease", `{"lease_ms": 100}`); j["lease_until"] != "2026-09-14T10:00:00.100Z" {
		t.Errorf("lease_ms: %v", j)
	}
	for _, body := range []string{`{"lease_ms": 99}`, `{"lease_ms": 3600001}`, `{"lease_ms": "100"}`, `{"ms": 100}`} {
		h.create("q", 1)
		if code, _, _ := h.do("w", "POST", "/queues/q/lease", body); code != 400 {
			t.Errorf("%s: %d", body, code)
		}
	}
	if code, _, _ := h.do("w", "POST", "/queues/bad.name/lease", ""); code != 400 {
		t.Errorf("bad queue name: %d", code)
	}
}

func TestAckFailDeleteStatuses(t *testing.T) {
	h := newHarness(t)
	h.create("q", 2)
	h.want(409, "w", "POST", "/jobs/j_1/ack", "")
	h.want(200, "w", "POST", "/queues/q/lease", "")
	h.want(409, "other", "POST", "/jobs/j_1/ack", "")
	h.want(409, "other", "POST", "/jobs/j_1/fail", `{"reason":"x"}`)
	h.want(409, "w", "DELETE", "/jobs/j_1", "")
	h.want(400, "w", "POST", "/jobs/j_1/fail", `{}`)
	failed := h.want(200, "w", "POST", "/jobs/j_1/fail", `{"reason":"flaky"}`)
	if failed["state"] != "queued" || failed["reason"] != "flaky" || failed["worker"] != nil || failed["lease_until"] != nil {
		t.Errorf("fail %v", failed)
	}
	h.want(200, "w", "POST", "/queues/q/lease", "")
	if again := h.want(200, "w", "GET", "/jobs/j_1", ""); again["reason"] != "flaky" {
		t.Errorf("reason lost on re-lease: %v", again)
	}
	if done := h.want(200, "w", "POST", "/jobs/j_1/ack", ""); done["state"] != "done" || done["worker"] != nil {
		t.Errorf("ack %v", done)
	}
	h.want(409, "w", "POST", "/jobs/j_1/ack", "")
	if code, _, rec := h.do("w", "DELETE", "/jobs/j_1", ""); code != 204 || rec.Body.Len() != 0 {
		t.Errorf("delete done: %d", code)
	}
	h.want(404, "w", "DELETE", "/jobs/j_1", "")
	h.want(404, "w", "POST", "/jobs/j_1/ack", "")

	h.create("q", 1)
	h.want(200, "w", "POST", "/queues/q/lease", "")
	if dead := h.want(200, "w", "POST", "/jobs/j_2/fail", `{"reason":""}`); dead["state"] != "dead" || dead["reason"] != "" {
		t.Errorf("last attempt: %v", dead)
	}
	h.want(204, "w", "DELETE", "/jobs/j_2", "")
}

func TestListRoute(t *testing.T) {
	h := newHarness(t)
	for i := 0; i < 103; i++ {
		h.create([]string{"a", "b", "c"}[i%3], 1)
	}
	h.want(200, "w", "POST", "/queues/b/lease", "")
	list := func(query string) []any {
		return h.want(200, "w", "GET", "/jobs"+query, "")["jobs"].([]any)
	}
	if all := list(""); len(all) != 100 || all[0].(map[string]any)["id"] != "j_1" {
		t.Errorf("all: %d", len(all))
	}
	if got := list("?queue=b&state=leased"); len(got) != 1 || got[0].(map[string]any)["id"] != "j_2" {
		t.Errorf("filtered: %v", got)
	}
	if got := list("?state=done"); len(got) != 0 {
		t.Errorf("done: %v", got)
	}
	if got := list("?queue=c"); len(got) != 34 {
		t.Errorf("queue c: %d", len(got))
	}
	h.want(400, "w", "GET", "/jobs?state=asleep", "")
	h.want(400, "w", "GET", "/jobs?queue=no%20way", "")
}

func TestStoreFailureIs503AndChangesNothing(t *testing.T) {
	clock := newClock()
	ff := &faultFile{writes: 1}
	q := faultyQueue(t, t.TempDir(), clock, ff)
	h := &harness{t: t, q: q, api: &API{q: q, requestTimeout: time.Second}, clock: clock}
	h.want(503, "p", "POST", "/jobs", `{"queue":"q","payload":"p","max_attempts":1}`)
	if got := h.want(200, "p", "GET", "/jobs", "")["jobs"].([]any); len(got) != 0 {
		t.Errorf("jobs after 503: %v", got)
	}
	if id := h.create("q", 1); id != "j_1" {
		t.Errorf("id after 503: %s", id)
	}
	ff.syncs = 1
	h.want(503, "w", "POST", "/queues/q/lease", "")
	if j := h.want(200, "w", "GET", "/jobs/j_1", ""); j["state"] != "queued" || j["attempts"] != 0.0 {
		t.Errorf("job after a failed lease: %v", j)
	}
}

func TestBusyIs503(t *testing.T) {
	h := newHarness(t)
	h.api.requestTimeout = 20 * time.Millisecond
	if err := h.q.acquire(bg()); err != nil {
		t.Fatal(err)
	}
	h.want(503, "p", "GET", "/health", "")
	h.q.release()
	h.want(200, "p", "GET", "/health", "")
}

// property: create then get round-trips any valid payload, over HTTP.
func TestPropertyCreateGetRoundTripsAnyPayload(t *testing.T) {
	h := newHarness(t)
	srv := httptest.NewServer(h.api)
	defer srv.Close()
	rng := rand.New(rand.NewSource(14))
	alphabet := []rune("aZ09 \n\"\\/<>&{}[]%+éß漢字🙂\u2028\u00a0\ufeff")
	for i := 0; i < 200; i++ {
		var b strings.Builder
		n := rng.Intn(64)
		if i%20 == 0 {
			n = maxPayload
		}
		for b.Len() < n {
			r := alphabet[rng.Intn(len(alphabet))]
			if b.Len()+utf8.RuneLen(r) > maxPayload {
				break
			}
			b.WriteRune(r)
		}
		payload := b.String()
		if i == 1 {
			payload = strings.Repeat("a", maxPayload)
		}
		body, err := json.Marshal(map[string]any{"queue": "q", "payload": payload, "max_attempts": 1})
		if err != nil {
			t.Fatal(err)
		}
		status, resp, err := request(bg(), srv.Client(), srv.URL, "p", "POST", "/jobs", string(body))
		if err != nil || status != 201 {
			t.Fatalf("create %d: %d %v %.80s", i, status, err, resp)
		}
		var created Job
		if err := json.Unmarshal([]byte(resp), &created); err != nil {
			t.Fatal(err)
		}
		status, resp, err = request(bg(), srv.Client(), srv.URL, "p", "GET", "/jobs/"+created.ID, "")
		var got Job
		if err != nil || status != 200 || json.Unmarshal([]byte(resp), &got) != nil || got.Payload != payload {
			t.Fatalf("payload %d did not round-trip: %d %v", i, status, err)
		}
	}
}

// Two workers race for one job over real sockets: exactly one holds it.
func TestTwoWorkersRaceForOneJob(t *testing.T) {
	h := newHarness(t)
	srv := httptest.NewServer(h.api)
	defer srv.Close()
	for round := 1; round <= 50; round++ {
		h.create("race", 1)
		var wg sync.WaitGroup
		statuses := make([]int, 2)
		bodies := make([]string, 2)
		for w := 0; w < 2; w++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				status, body, err := request(bg(), srv.Client(), srv.URL, fmt.Sprintf("w%d", w), "POST", "/queues/race/lease", "")
				if err != nil {
					t.Error(err)
				}
				statuses[w], bodies[w] = status, body
			}()
		}
		wg.Wait()
		slices.Sort(statuses)
		if statuses[0] != 200 || statuses[1] != 204 {
			t.Fatalf("round %d: statuses %v", round, statuses)
		}
		j, err := h.q.Get(bg(), formatID(uint64(round)))
		if err != nil || j.State != Leased || (j.Worker != "w0" && j.Worker != "w1") {
			t.Fatalf("round %d: %+v %v", round, j, err)
		}
		if _, err := h.q.Ack(bg(), j.ID, j.Worker); err != nil {
			t.Fatal(err)
		}
	}
	_ = http.StatusOK
}
