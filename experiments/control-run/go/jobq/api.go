package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"jobq/contract"
)

// maxBody bounds a request body: a 60 KiB payload escaped as \uXXXX fits.
const maxBody = 1 << 20

// listLimit is the most jobs GET /jobs returns.
const listLimit = 100

// API is jobq's HTTP surface over one queue.
type API struct {
	q              *Queue
	requestTimeout time.Duration
}

type handler func(ctx context.Context, w http.ResponseWriter, r *http.Request, token string)

// ServeHTTP answers 404 for an unknown route, then 401 without a token
// (except /health), then 405 for a method the route lacks.
func (a *API) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), a.requestTimeout)
	defer cancel()
	methods, public, found := a.route(r.URL.Path)
	if !found {
		writeError(w, http.StatusNotFound, "no such route")
		return
	}
	token, ok := bearer(r.Header.Get("Authorization"))
	if !public && !ok {
		writeError(w, http.StatusUnauthorized, "missing bearer token")
		return
	}
	h, ok := methods[r.Method]
	if !ok {
		allow := make([]string, 0, len(methods))
		for m := range methods {
			allow = append(allow, m)
		}
		slices.Sort(allow)
		w.Header().Set("Allow", strings.Join(allow, ", "))
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	h(ctx, w, r, token)
}

func (a *API) route(path string) (map[string]handler, bool, bool) {
	segs := strings.Split(strings.TrimPrefix(path, "/"), "/")
	switch {
	case len(segs) == 1 && segs[0] == "health":
		return map[string]handler{http.MethodGet: a.health}, true, true
	case len(segs) == 1 && segs[0] == "jobs":
		return map[string]handler{http.MethodPost: a.create, http.MethodGet: a.list}, false, true
	case len(segs) == 2 && segs[0] == "jobs":
		id := segs[1]
		return map[string]handler{
			http.MethodGet:    func(ctx context.Context, w http.ResponseWriter, r *http.Request, _ string) { a.get(ctx, w, id) },
			http.MethodDelete: func(ctx context.Context, w http.ResponseWriter, r *http.Request, _ string) { a.delete(ctx, w, id) },
		}, false, true
	case len(segs) == 3 && segs[0] == "jobs" && segs[2] == "ack":
		id := segs[1]
		return map[string]handler{http.MethodPost: func(ctx context.Context, w http.ResponseWriter, r *http.Request, token string) {
			a.ack(ctx, w, id, token)
		}}, false, true
	case len(segs) == 3 && segs[0] == "jobs" && segs[2] == "fail":
		id := segs[1]
		return map[string]handler{http.MethodPost: func(ctx context.Context, w http.ResponseWriter, r *http.Request, token string) {
			a.fail(ctx, w, r, id, token)
		}}, false, true
	case len(segs) == 3 && segs[0] == "queues" && segs[2] == "lease":
		queue := segs[1]
		return map[string]handler{http.MethodPost: func(ctx context.Context, w http.ResponseWriter, r *http.Request, token string) {
			a.lease(ctx, w, r, queue, token)
		}}, false, true
	}
	return nil, false, false
}

func (a *API) create(ctx context.Context, w http.ResponseWriter, r *http.Request, _ string) {
	var body struct {
		Queue       *string `json:"queue"`
		Payload     *string `json:"payload"`
		MaxAttempts *int    `json:"max_attempts"`
	}
	if !readBody(w, r, &body, false) {
		return
	}
	if body.Queue == nil || body.Payload == nil || body.MaxAttempts == nil {
		writeError(w, http.StatusBadRequest, `"queue", "payload", and "max_attempts" are required`)
		return
	}
	j, err := a.q.Create(ctx, *body.Queue, *body.Payload, *body.MaxAttempts)
	respond(w, http.StatusCreated, j, err)
}

func (a *API) get(ctx context.Context, w http.ResponseWriter, id string) {
	j, err := a.q.Get(ctx, id)
	respond(w, http.StatusOK, j, err)
}

func (a *API) list(ctx context.Context, w http.ResponseWriter, r *http.Request, _ string) {
	query := r.URL.Query()
	jobs, err := a.q.List(ctx, query.Get("queue"), State(query.Get("state")), listLimit)
	respond(w, http.StatusOK, map[string][]Job{"jobs": jobs}, err)
}

func (a *API) delete(ctx context.Context, w http.ResponseWriter, id string) {
	if err := a.q.Delete(ctx, id); err != nil {
		writeFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *API) lease(ctx context.Context, w http.ResponseWriter, r *http.Request, queue, token string) {
	var body struct {
		LeaseMs *int `json:"lease_ms"`
	}
	if !readBody(w, r, &body, true) {
		return
	}
	leaseMs := defaultLeaseMs
	if body.LeaseMs != nil {
		leaseMs = *body.LeaseMs
	}
	j, leased, err := a.q.Lease(ctx, queue, token, leaseMs)
	if err == nil && !leased {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	respond(w, http.StatusOK, j, err)
}

func (a *API) ack(ctx context.Context, w http.ResponseWriter, id, token string) {
	j, err := a.q.Ack(ctx, id, token)
	respond(w, http.StatusOK, j, err)
}

func (a *API) fail(ctx context.Context, w http.ResponseWriter, r *http.Request, id, token string) {
	var body struct {
		Reason *string `json:"reason"`
	}
	if !readBody(w, r, &body, false) {
		return
	}
	if body.Reason == nil {
		writeError(w, http.StatusBadRequest, `"reason" is required`)
		return
	}
	j, err := a.q.Fail(ctx, id, token, *body.Reason)
	respond(w, http.StatusOK, j, err)
}

func (a *API) health(ctx context.Context, w http.ResponseWriter, _ *http.Request, _ string) {
	h, err := a.q.Health(ctx)
	respond(w, http.StatusOK, h, err)
}

// bearer reads `Bearer <token>`; the scheme's case does not matter.
func bearer(header string) (string, bool) {
	scheme, token, ok := strings.Cut(header, " ")
	token = strings.TrimSpace(token)
	return token, ok && strings.EqualFold(scheme, "Bearer") && token != ""
}

// readBody decodes one JSON object into dst, answering 400 itself when it
// cannot. An empty body is allowed only where every field has a default.
func readBody(w http.ResponseWriter, r *http.Request, dst any, emptyOK bool) bool {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
	if err != nil {
		writeError(w, http.StatusBadRequest, "reading the body: "+err.Error())
		return false
	}
	if err := decodeObject(raw, dst, emptyOK); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return false
	}
	return true
}

func decodeObject(raw []byte, dst any, emptyOK bool) error {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		if emptyOK {
			return nil
		}
		return errors.New("the body must be a JSON object")
	}
	if !utf8.Valid(trimmed) {
		return errors.New("the body is not UTF-8")
	}
	if trimmed[0] != '{' {
		return errors.New("the body must be a JSON object")
	}
	dec := json.NewDecoder(bytes.NewReader(trimmed))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return fmt.Errorf("the body is not the expected JSON: %v", err)
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return errors.New("the body has data after its JSON object")
	}
	return nil
}

func respond(w http.ResponseWriter, status int, v any, err error) {
	if err != nil {
		writeFailure(w, err)
		return
	}
	writeJSON(w, status, v)
}

// writeFailure maps an operation's error to its status.
func writeFailure(w http.ResponseWriter, err error) {
	var v *contract.Violation
	var internal internalError
	switch {
	case errors.As(err, &internal):
		writeError(w, http.StatusInternalServerError, err.Error())
	case errors.As(err, &v) && v.Kind == "requires":
		writeError(w, http.StatusBadRequest, v.Error())
	case errors.Is(err, ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, ErrConflict):
		writeError(w, http.StatusConflict, err.Error())
	case errors.Is(err, ErrStore), errors.Is(err, ErrBusy):
		writeError(w, http.StatusServiceUnavailable, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, err.Error())
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		status = http.StatusInternalServerError
		buf.Reset()
		buf.WriteString(`{"error":"encoding the response"}`)
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// A client that went away cannot be told; the change is already durable.
	_, _ = w.Write(bytes.TrimSuffix(buf.Bytes(), []byte("\n")))
}
