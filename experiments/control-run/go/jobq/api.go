package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"sort"
	"strings"
	"unicode/utf8"

	"controlrun/contract"
)

const maxBodyBytes = 256 * 1024

// API serves the HTTP routes of the spec over the board's queue.
type API struct {
	b *Board
}

type badRequest struct{ msg string }

func (e *badRequest) Error() string { return e.msg }

// handler returns a status and a body to encode, nil for no body.
type handler func(q *Queue, r *http.Request, arg, token string) (int, any, error)

type route struct {
	methods map[string]handler
	public  bool
	arg     string
}

func (a *API) match(path string) (route, bool) {
	seg := strings.Split(strings.TrimPrefix(path, "/"), "/")
	switch {
	case len(seg) == 1 && seg[0] == "health":
		return route{methods: map[string]handler{"GET": a.health}, public: true}, true
	case len(seg) == 1 && seg[0] == "jobs":
		return route{methods: map[string]handler{"POST": a.create, "GET": a.list}}, true
	case len(seg) == 2 && seg[0] == "jobs":
		return route{methods: map[string]handler{"GET": a.get, "DELETE": a.remove}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "jobs" && seg[2] == "ack":
		return route{methods: map[string]handler{"POST": a.ack}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "jobs" && seg[2] == "fail":
		return route{methods: map[string]handler{"POST": a.fail}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "jobs" && seg[2] == "handoff":
		return route{methods: map[string]handler{"POST": a.handoff}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "queues" && seg[2] == "rename":
		return route{methods: map[string]handler{"POST": a.rename}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "jobs" && seg[2] == "retry":
		return route{methods: map[string]handler{"POST": a.retry}, arg: seg[1]}, true
	case len(seg) == 1 && seg[0] == "queues":
		return route{methods: map[string]handler{"GET": a.queues}}, true
	case len(seg) == 3 && seg[0] == "queues" && seg[2] == "lease":
		return route{methods: map[string]handler{"POST": a.lease}, arg: seg[1]}, true
	}
	return route{}, false
}

func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	status, body := a.respond(w, r)
	writeJSON(w, status, body)
}

// respond handles one request and returns what to write. A panic is caught
// here and answered 503, after the queue's own defers have released the
// lock. A panic outside the queue costs this request and nothing else; one
// under the queue's lock, or a rule the queue broke, has marked the queue
// broken, and the board takes it down and rebuilds it from the log.
func (a *API) respond(w http.ResponseWriter, r *http.Request) (status int, body any) {
	st := a.b.state()
	if st == nil {
		return http.StatusServiceUnavailable, errorBody(ErrRestarting.Error())
	}
	defer func() {
		if v := recover(); v != nil {
			status, body = http.StatusServiceUnavailable, errorBody("the request could not be completed")
		}
		a.b.failed(st)
	}()
	ctx, cancel := context.WithTimeout(r.Context(), requestTimeout)
	defer cancel()
	r = r.WithContext(ctx)
	rt, ok := a.match(r.URL.Path)
	if !ok {
		return http.StatusNotFound, errorBody("no such route")
	}
	h, ok := rt.methods[r.Method]
	if !ok {
		allowed := make([]string, 0, len(rt.methods))
		for m := range rt.methods {
			allowed = append(allowed, m)
		}
		sort.Strings(allowed)
		w.Header().Set("Allow", strings.Join(allowed, ", "))
		return http.StatusMethodNotAllowed, errorBody("method not allowed")
	}
	token := ""
	if !rt.public {
		if token, ok = bearer(r); !ok {
			return http.StatusUnauthorized, errorBody("missing or empty bearer token")
		}
	}
	// The handler returns only after the queue's change is durable, so the
	// response below is never written before its record.
	status, body, err := h(st.q, r, rt.arg, token)
	if err != nil {
		return errorStatus(err), errorBody(err.Error())
	}
	return status, body
}

func errorBody(msg string) map[string]string { return map[string]string{"error": msg} }

func errorStatus(err error) int {
	var v *contract.Violation
	var bad *badRequest
	switch {
	case errors.As(err, &v) && v.Kind == "requires", errors.As(err, &bad):
		return http.StatusBadRequest
	case errors.Is(err, ErrNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrConflict):
		return http.StatusConflict
	}
	// The store, a queue that did not answer in time, and anything the
	// implementation did not expect are all the service's failure: 503.
	return http.StatusServiceUnavailable
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	if body == nil {
		w.WriteHeader(status)
		return
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(body); err != nil {
		status, buf = http.StatusInternalServerError, *bytes.NewBufferString(`{"error": "encoding the response failed"}` + "\n")
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(buf.Bytes())
}

// bearer reads `Authorization: Bearer <token>`; the scheme is case-insensitive.
func bearer(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	if len(h) < 7 || !strings.EqualFold(h[:7], "Bearer ") {
		return "", false
	}
	token := h[7:]
	return token, validToken(token)
}

// decodeBody reads one JSON object into dst. Unknown fields, trailing data,
// and bodies that are not UTF-8 are 400s. An empty body is allowed only when
// allowEmpty is set, and leaves dst untouched.
func decodeBody(r *http.Request, dst any, allowEmpty bool) error {
	data, err := io.ReadAll(io.LimitReader(r.Body, maxBodyBytes+1))
	if err != nil {
		return &badRequest{"body could not be read"}
	}
	if len(data) > maxBodyBytes {
		return &badRequest{"body is larger than 256 KiB"}
	}
	if allowEmpty && len(bytes.TrimSpace(data)) == 0 {
		return nil
	}
	if !utf8.Valid(data) {
		return &badRequest{"body is not UTF-8"}
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return &badRequest{"body is not the expected JSON object: " + err.Error()}
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return &badRequest{"body has data after the JSON object"}
	}
	return nil
}

func (a *API) create(q *Queue, r *http.Request, _, _ string) (int, any, error) {
	var b struct {
		Queue     *string `json:"queue"`
		Key       *string `json:"key"`
		Payload   *string `json:"payload"`
		MaxTries  *int    `json:"max_tries"`
		DelayMS   *int64  `json:"delay_ms"`
		BackoffMS *int64  `json:"backoff_ms"`
	}
	if err := decodeBody(r, &b, false); err != nil {
		return 0, nil, err
	}
	if b.Queue == nil || b.Payload == nil || b.MaxTries == nil {
		return 0, nil, &badRequest{"queue, payload, and max_tries are required"}
	}
	var key string
	if b.Key != nil {
		if err := requireKey(*b.Key); err != nil {
			return 0, nil, err
		}
		key = *b.Key
	}
	var delayMS, backoffMS int64
	if b.DelayMS != nil {
		delayMS = *b.DelayMS
	}
	if b.BackoffMS != nil {
		backoffMS = *b.BackoffMS
	}
	j, created, err := q.Create(r.Context(), *b.Queue, key, *b.Payload, *b.MaxTries, delayMS, backoffMS)
	if err != nil {
		return 0, nil, err
	}
	if !created {
		return http.StatusOK, jobView(j), nil
	}
	return http.StatusCreated, jobView(j), nil
}

func (a *API) get(q *Queue, r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := q.Get(r.Context(), id)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) list(q *Queue, r *http.Request, _, _ string) (int, any, error) {
	query := r.URL.Query()
	for k, vs := range query {
		if (k != "queue" && k != "state" && k != "key") || len(vs) != 1 {
			return 0, nil, &badRequest{"the query takes queue, state, and key, each at most once"}
		}
	}
	if query.Has("key") && !query.Has("queue") {
		return 0, nil, &badRequest{"key is given with queue"}
	}
	if query.Has("key") {
		if err := requireKey(query.Get("key")); err != nil {
			return 0, nil, err
		}
	}
	jobs, err := q.List(r.Context(), query.Get("queue"), query.Get("state"), query.Get("key"))
	if err != nil {
		return 0, nil, err
	}
	views := make([]jobJSON, len(jobs))
	for i, j := range jobs {
		views[i] = jobView(j)
	}
	return http.StatusOK, map[string][]jobJSON{"jobs": views}, nil
}

func (a *API) remove(q *Queue, r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	if err := q.Delete(r.Context(), id); err != nil {
		return 0, nil, err
	}
	return http.StatusNoContent, nil, nil
}

func (a *API) lease(q *Queue, r *http.Request, queue, token string) (int, any, error) {
	var b struct {
		LeaseMS *int64 `json:"lease_ms"`
	}
	if err := decodeBody(r, &b, true); err != nil {
		return 0, nil, err
	}
	ms := int64(defaultLeaseMS)
	if b.LeaseMS != nil {
		ms = *b.LeaseMS
	}
	j, ok, err := q.Lease(r.Context(), queue, token, ms)
	if err != nil {
		return 0, nil, err
	}
	if !ok {
		return http.StatusNoContent, nil, nil
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) ack(q *Queue, r *http.Request, arg, token string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := q.Ack(r.Context(), id, token)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) fail(q *Queue, r *http.Request, arg, token string) (int, any, error) {
	var b struct {
		Reason *string `json:"reason"`
	}
	if err := decodeBody(r, &b, false); err != nil {
		return 0, nil, err
	}
	if b.Reason == nil {
		return 0, nil, &badRequest{"reason is required"}
	}
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := q.Fail(r.Context(), id, token, *b.Reason)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

// toBody reads {"to": "<name>"}, to required.
func toBody(r *http.Request) (string, error) {
	var b struct {
		To *string `json:"to"`
	}
	if err := decodeBody(r, &b, false); err != nil {
		return "", err
	}
	if b.To == nil {
		return "", &badRequest{"to is required"}
	}
	return *b.To, nil
}

func (a *API) handoff(q *Queue, r *http.Request, arg, token string) (int, any, error) {
	to, err := toBody(r)
	if err != nil {
		return 0, nil, err
	}
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := q.Handoff(r.Context(), id, token, to)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

// renamed is the body of a rename's 200.
type renamed struct {
	Queue string `json:"queue"`
	Moved int    `json:"moved"`
}

func (a *API) rename(q *Queue, r *http.Request, queue, _ string) (int, any, error) {
	to, err := toBody(r)
	if err != nil {
		return 0, nil, err
	}
	moved, err := q.Rename(r.Context(), queue, to)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, renamed{Queue: to, Moved: moved}, nil
}

// retry takes no body; like ack, it does not read one.
func (a *API) retry(q *Queue, r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := q.Retry(r.Context(), id)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) queues(q *Queue, r *http.Request, _, _ string) (int, any, error) {
	qs, err := q.Queues(r.Context())
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, map[string][]QueueCounts{"queues": qs}, nil
}

func (a *API) health(q *Queue, r *http.Request, _, _ string) (int, any, error) {
	h, err := q.Health(r.Context())
	if err != nil {
		return 0, nil, err
	}
	h.Restarts = a.b.Restarts()
	return http.StatusOK, h, nil
}
