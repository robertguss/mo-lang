package main

import (
	"encoding/json"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type apiHarness struct {
	t     *testing.T
	api   *API
	q     *Queue
	file  *memFile
	clock *manualClock
}

func newAPIHarness(t *testing.T) *apiHarness {
	q, _, f, clock := newMemQueue()
	return &apiHarness{t: t, api: &API{q: q}, q: q, file: f, clock: clock}
}

// do sends one request; a token of "-" sends no authorization header.
func (h *apiHarness) do(token, method, path, body string) (int, string, http.Header) {
	h.t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "-" {
		req.Header.Set("Authorization", token)
	}
	rec := httptest.NewRecorder()
	h.api.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String(), rec.Header()
}

func (h *apiHarness) want(token, method, path, body string, status int) string {
	h.t.Helper()
	got, resp, _ := h.do(token, method, path, body)
	if got != status {
		h.t.Errorf("%s %s %s = %d %s, want %d", method, path, body, got, resp, status)
	}
	return resp
}

func decodeJob(t *testing.T, body string) jobJSON {
	t.Helper()
	var v jobJSON
	if err := json.Unmarshal([]byte(body), &v); err != nil {
		t.Fatalf("body %q: %v", body, err)
	}
	return v
}

const w1 = "Bearer w1"

func TestHealthNeedsNoToken(t *testing.T) {
	h := newAPIHarness(t)
	h.clock.Advance(1500 * time.Millisecond)
	body := h.want("-", "GET", "/health", "", 200)
	if body != `{"queued":0,"scheduled":0,"leased":0,"done":0,"dead":0,"uptime_ms":1500}`+"\n" {
		t.Errorf("health body %q", body)
	}
}

func TestAuthorization(t *testing.T) {
	h := newAPIHarness(t)
	create := `{"queue":"a","payload":"p","max_tries":1}`
	for _, token := range []string{"-", "", "Bearer ", "Basic w1", "Bearer a b", "Bearerw1"} {
		body := h.want(token, "POST", "/jobs", create, 401)
		if !strings.Contains(body, `"error"`) {
			t.Errorf("401 body %q", body)
		}
	}
	h.want("bearer w1", "POST", "/jobs", create, 201)
}

func TestRoutesAndMethods(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "GET", "/nope", "", 404)
	h.want(w1, "GET", "/jobs/j_1/nope", "", 404)
	h.want(w1, "GET", "/queues/a", "", 404)
	for _, c := range []struct{ method, path, allow string }{
		{"PUT", "/jobs", "GET, POST"},
		{"POST", "/jobs/j_1", "DELETE, GET"},
		{"GET", "/jobs/j_1/ack", "POST"},
		{"GET", "/jobs/j_1/fail", "POST"},
		{"GET", "/queues/a/lease", "POST"},
		{"POST", "/health", "GET"},
	} {
		status, _, header := h.do(w1, c.method, c.path, "")
		if status != 405 || header.Get("Allow") != c.allow {
			t.Errorf("%s %s = %d, Allow %q; want 405, %q", c.method, c.path, status, header.Get("Allow"), c.allow)
		}
	}
}

func TestCreateAndGetShapes(t *testing.T) {
	h := newAPIHarness(t)
	body := h.want(w1, "POST", "/jobs", `{"queue":"emails","payload":"hi","max_tries":3}`, 201)
	want := `{"id":"j_1","queue":"emails","state":"queued","payload":"hi","tries":0,"max_tries":3,"backoff_ms":0,` +
		`"created_at":"2026-09-14T12:00:00.000Z","updated_at":"2026-09-14T12:00:00.000Z"}` + "\n"
	if body != want {
		t.Errorf("created\n%s\nwant\n%s", body, want)
	}
	if got := h.want(w1, "GET", "/jobs/j_1", "", 200); got != want {
		t.Errorf("get\n%s\nwant\n%s", got, want)
	}
	h.want(w1, "GET", "/jobs/j_2", "", 404)
	h.want(w1, "GET", "/jobs/x", "", 404)
}

func TestBadBodiesAre400(t *testing.T) {
	h := newAPIHarness(t)
	for _, body := range []string{
		``, `not json`, `[]`, `null`, `{}`,
		`{"queue":"a","payload":"p"}`,
		`{"queue":"a","payload":"p","max_tries":"3"}`,
		`{"queue":"a","payload":"p","max_tries":3.5}`,
		`{"queue":"a","payload":7,"max_tries":3}`,
		`{"queue":"a","payload":"p","max_tries":3,"extra":1}`,
		`{"queue":"a","payload":"p","max_tries":3}{}`,
		`{"queue":"a b","payload":"p","max_tries":3}`,
		"{\"queue\":\"a\",\"payload\":\"\\u0000\",\"max_attempts\":3}",
		`{"queue":"a","payload":"p","max_tries":0}`,
		"{\"queue\":\"a\",\"payload\":\"\xff\",\"max_attempts\":3}",
		`{"queue":"a","payload":"` + strings.Repeat("x", maxBodyBytes) + `","max_tries":3}`,
	} {
		resp := h.want(w1, "POST", "/jobs", body, 400)
		if !strings.HasPrefix(resp, `{"error":`) {
			t.Errorf("400 body %q", resp)
		}
	}
	if len(h.q.jobs) != 0 {
		t.Errorf("a bad body created %d jobs", len(h.q.jobs))
	}
}

func TestListFiltersAndLimit(t *testing.T) {
	h := newAPIHarness(t)
	for range 105 {
		h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	}
	for range 2 {
		h.want(w1, "POST", "/jobs", `{"queue":"b","payload":"p","max_tries":1}`, 201)
	}
	h.want(w1, "POST", "/queues/b/lease", "", 200)
	count := func(path string) (int, []jobJSON) {
		var out struct{ Jobs []jobJSON }
		if err := json.Unmarshal([]byte(h.want(w1, "GET", path, "", 200)), &out); err != nil {
			t.Fatal(err)
		}
		return len(out.Jobs), out.Jobs
	}
	if n, jobs := count("/jobs"); n != 100 || jobs[0].ID != "j_1" || jobs[99].ID != "j_100" {
		t.Errorf("/jobs gave %d jobs", n)
	}
	if n, _ := count("/jobs?queue=b"); n != 2 {
		t.Errorf("queue=b gave %d", n)
	}
	if n, jobs := count("/jobs?queue=b&state=leased"); n != 1 || jobs[0].ID != "j_106" {
		t.Errorf("queue=b&state=leased gave %v", jobs)
	}
	if n, _ := count("/jobs?state=done"); n != 0 {
		t.Errorf("state=done gave %d", n)
	}
	for _, path := range []string{"/jobs?state=bogus", "/jobs?queue=bad!", "/jobs?other=1", "/jobs?queue=a&queue=b"} {
		h.want(w1, "GET", path, "", 400)
	}
}

func TestDeleteStatuses(t *testing.T) {
	h := newAPIHarness(t)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 201)
	h.want(w1, "POST", "/queues/a/lease", "", 200)
	h.want(w1, "DELETE", "/jobs/j_1", "", 409)
	if body := h.want(w1, "DELETE", "/jobs/j_2", "", 204); body != "" {
		t.Errorf("204 with body %q", body)
	}
	h.want(w1, "GET", "/jobs/j_2", "", 404)
	h.want(w1, "DELETE", "/jobs/j_2", "", 404)
}

func TestLeaseAckFailStatuses(t *testing.T) {
	h := newAPIHarness(t)
	if body := h.want(w1, "POST", "/queues/a/lease", "", 204); body != "" {
		t.Errorf("204 with body %q", body)
	}
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":2}`, 201)
	for _, body := range []string{`{"lease_ms":99}`, `{"lease_ms":"1000"}`, `{"lease_ms":3600001}`, `{"ms":1000}`, `nope`} {
		h.want(w1, "POST", "/queues/a/lease", body, 400)
	}
	h.want(w1, "POST", "/queues/bad!/lease", "", 400)
	leased := decodeJob(t, h.want(w1, "POST", "/queues/a/lease", "", 200))
	if leased.Worker == nil || *leased.Worker != "w1" || leased.LeaseUntil == nil || *leased.LeaseUntil != "2026-09-14T12:00:30.000Z" {
		t.Errorf("leased %+v", leased)
	}
	h.want("Bearer w2", "POST", "/jobs/j_1/ack", "", 409)
	h.want(w1, "POST", "/jobs/j_1/fail", "", 400)
	h.want(w1, "POST", "/jobs/j_1/fail", `{}`, 400)
	failed := decodeJob(t, h.want(w1, "POST", "/jobs/j_1/fail", `{"reason":"flaky"}`, 200))
	if failed.State != Queued || failed.Reason == nil || *failed.Reason != "flaky" || failed.Worker != nil {
		t.Errorf("failed %+v", failed)
	}
	h.want(w1, "POST", "/jobs/j_1/fail", `{"reason":"again"}`, 409)
	h.want(w1, "POST", "/queues/a/lease", `{"lease_ms":1000}`, 200)
	done := decodeJob(t, h.want(w1, "POST", "/jobs/j_1/ack", "", 200))
	if done.State != Done || done.Tries != 2 || done.LeaseUntil != nil {
		t.Errorf("done %+v", done)
	}
	h.want(w1, "POST", "/jobs/j_1/ack", "", 409)
	h.want(w1, "POST", "/jobs/j_9/ack", "", 404)
	h.want(w1, "POST", "/jobs/j_9/fail", `{"reason":"x"}`, 404)
}

func TestStoreFailureIs503(t *testing.T) {
	h := newAPIHarness(t)
	h.file.fail = func(string) bool { return true }
	h.want(w1, "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`, 503)
	h.file.fail = nil
	if body := h.want(w1, "GET", "/jobs", "", 200); body != `{"jobs":[]}`+"\n" {
		t.Errorf("after a 503 the list is %q", body)
	}
}

// Property: create then get round-trips any valid payload.
func TestPropertyCreateGetRoundTrip(t *testing.T) {
	h := newAPIHarness(t)
	rng := rand.New(rand.NewPCG(3, 5))
	runes := []rune{'a', 'Z', ' ', '\n', '"', '\\', '/', '<', '&', 'é', '日', '😀', '\u2028', '\ufffd', '~'}
	payloads := []string{"", strings.Repeat("é", maxPayloadBytes/2)}
	for range 300 {
		var b strings.Builder
		for range rng.IntN(300) {
			b.WriteRune(runes[rng.IntN(len(runes))])
		}
		payloads = append(payloads, b.String())
	}
	for _, p := range payloads {
		body, err := json.Marshal(map[string]any{"queue": "q", "payload": p, "max_tries": 1})
		if err != nil {
			t.Fatal(err)
		}
		created := decodeJob(t, h.want(w1, "POST", "/jobs", string(body), 201))
		got := decodeJob(t, h.want(w1, "GET", "/jobs/"+created.ID, "", 200))
		if got.Payload != p || created.Payload != p {
			t.Fatalf("payload %q came back as %q", p, got.Payload)
		}
	}
}
