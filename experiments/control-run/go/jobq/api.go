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

// API serves the HTTP routes of the spec over a Queue.
type API struct {
	q *Queue
}

type badRequest struct{ msg string }

func (e *badRequest) Error() string { return e.msg }

// handler returns a status and a body to encode, nil for no body.
type handler func(r *http.Request, arg, token string) (int, any, error)

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
	case len(seg) == 3 && seg[0] == "jobs" && seg[2] == "retry":
		return route{methods: map[string]handler{"POST": a.retry}, arg: seg[1]}, true
	case len(seg) == 3 && seg[0] == "queues" && seg[2] == "lease":
		return route{methods: map[string]handler{"POST": a.lease}, arg: seg[1]}, true
	}
	return route{}, false
}

func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), requestTimeout)
	defer cancel()
	r = r.WithContext(ctx)
	rt, ok := a.match(r.URL.Path)
	if !ok {
		writeJSON(w, http.StatusNotFound, errorBody("no such route"))
		return
	}
	h, ok := rt.methods[r.Method]
	if !ok {
		allowed := make([]string, 0, len(rt.methods))
		for m := range rt.methods {
			allowed = append(allowed, m)
		}
		sort.Strings(allowed)
		w.Header().Set("Allow", strings.Join(allowed, ", "))
		writeJSON(w, http.StatusMethodNotAllowed, errorBody("method not allowed"))
		return
	}
	token := ""
	if !rt.public {
		if token, ok = bearer(r); !ok {
			writeJSON(w, http.StatusUnauthorized, errorBody("missing or empty bearer token"))
			return
		}
	}
	// The handler returns only after the queue's change is durable, so the
	// response below is never written before its record.
	status, body, err := h(r, rt.arg, token)
	if err != nil {
		status, body = errorStatus(err), errorBody(err.Error())
	}
	writeJSON(w, status, body)
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
	case errors.Is(err, ErrStore), errors.Is(err, ErrBusy):
		return http.StatusServiceUnavailable
	}
	return http.StatusInternalServerError
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

func (a *API) create(r *http.Request, _, _ string) (int, any, error) {
	var b struct {
		Queue     *string `json:"queue"`
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
	var delayMS, backoffMS int64
	if b.DelayMS != nil {
		delayMS = *b.DelayMS
	}
	if b.BackoffMS != nil {
		backoffMS = *b.BackoffMS
	}
	j, err := a.q.Create(r.Context(), *b.Queue, *b.Payload, *b.MaxTries, delayMS, backoffMS)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusCreated, jobView(j), nil
}

func (a *API) get(r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := a.q.Get(r.Context(), id)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) list(r *http.Request, _, _ string) (int, any, error) {
	query := r.URL.Query()
	for k, vs := range query {
		if (k != "queue" && k != "state") || len(vs) != 1 {
			return 0, nil, &badRequest{"the query takes queue and state, each at most once"}
		}
	}
	jobs, err := a.q.List(r.Context(), query.Get("queue"), query.Get("state"))
	if err != nil {
		return 0, nil, err
	}
	views := make([]jobJSON, len(jobs))
	for i, j := range jobs {
		views[i] = jobView(j)
	}
	return http.StatusOK, map[string][]jobJSON{"jobs": views}, nil
}

func (a *API) remove(r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	if err := a.q.Delete(r.Context(), id); err != nil {
		return 0, nil, err
	}
	return http.StatusNoContent, nil, nil
}

func (a *API) lease(r *http.Request, queue, token string) (int, any, error) {
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
	j, ok, err := a.q.Lease(r.Context(), queue, token, ms)
	if err != nil {
		return 0, nil, err
	}
	if !ok {
		return http.StatusNoContent, nil, nil
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) ack(r *http.Request, arg, token string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := a.q.Ack(r.Context(), id, token)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) fail(r *http.Request, arg, token string) (int, any, error) {
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
	j, err := a.q.Fail(r.Context(), id, token, *b.Reason)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

// retry takes no body; like ack, it does not read one.
func (a *API) retry(r *http.Request, arg, _ string) (int, any, error) {
	id, ok := parseID(arg)
	if !ok {
		return 0, nil, ErrNotFound
	}
	j, err := a.q.Retry(r.Context(), id)
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, jobView(j), nil
}

func (a *API) health(r *http.Request, _, _ string) (int, any, error) {
	h, err := a.q.Health(r.Context())
	if err != nil {
		return 0, nil, err
	}
	return http.StatusOK, h, nil
}
