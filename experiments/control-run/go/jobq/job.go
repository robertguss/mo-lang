package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"controlrun/contract"
)

// State is where a job is in its life.
type State string

const (
	Scheduled State = "scheduled"
	Queued    State = "queued"
	Leased    State = "leased"
	Done      State = "done"
	Dead      State = "dead"
)

const (
	maxPayloadBytes = 60 * 1024
	maxReasonBytes  = 1024
	maxTokenBytes   = 256
	minLeaseMS      = 100
	maxLeaseMS      = 3_600_000
	defaultLeaseMS  = 30_000
	maxDelayMS      = 86_400_000
	maxBackoffMS    = 3_600_000
	timeLayout      = "2006-01-02T15:04:05.000Z"
)

// Job is one unit of work. RunAt is set only while scheduled; Worker and
// LeaseUntil only while leased. Reason is set by a fail or a lease that ran
// out, kept afterwards, and dropped by a retry.
type Job struct {
	ID         uint64
	Queue      string
	State      State
	Payload    string
	Tries      int
	MaxTries   int
	BackoffMS  int64
	CreatedAt  time.Time
	UpdatedAt  time.Time
	RunAt      time.Time
	Worker     string
	LeaseUntil time.Time
	Reason     *string
}

// jobJSON is the {job} shape of the API and of a store record as written.
type jobJSON struct {
	ID         string  `json:"id"`
	Queue      string  `json:"queue"`
	State      State   `json:"state"`
	Payload    string  `json:"payload"`
	Tries      int     `json:"tries"`
	MaxTries   int     `json:"max_tries"`
	BackoffMS  int64   `json:"backoff_ms"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
	RunAt      *string `json:"run_at,omitempty"`
	Worker     *string `json:"worker,omitempty"`
	LeaseUntil *string `json:"lease_until,omitempty"`
	Reason     *string `json:"reason,omitempty"`
}

// storedJob is a store record's job as read. It also reads the names the
// service wrote before the tries rename: attempts and max_attempts stand for
// tries and max_tries, and a record without backoff_ms has 0. A record gives
// each count under exactly one of its names.
type storedJob struct {
	ID          string  `json:"id"`
	Queue       string  `json:"queue"`
	State       State   `json:"state"`
	Payload     string  `json:"payload"`
	Tries       *int    `json:"tries"`
	MaxTries    *int    `json:"max_tries"`
	Attempts    *int    `json:"attempts"`
	MaxAttempts *int    `json:"max_attempts"`
	BackoffMS   int64   `json:"backoff_ms"`
	CreatedAt   string  `json:"created_at"`
	UpdatedAt   string  `json:"updated_at"`
	RunAt       *string `json:"run_at"`
	Worker      *string `json:"worker"`
	LeaseUntil  *string `json:"lease_until"`
	Reason      *string `json:"reason"`
}

// view reads a stored job, old names or new, as the shape written today.
func (s storedJob) view() (jobJSON, error) {
	count := func(name string, v, old *int, oldName string) (int, error) {
		switch {
		case v != nil && old != nil:
			return 0, fmt.Errorf("job %s has both %s and %s", s.ID, name, oldName)
		case v != nil:
			return *v, nil
		case old != nil:
			return *old, nil
		}
		return 0, fmt.Errorf("job %s has no %s", s.ID, name)
	}
	tries, err1 := count("tries", s.Tries, s.Attempts, "attempts")
	maxTries, err2 := count("max_tries", s.MaxTries, s.MaxAttempts, "max_attempts")
	if err := errors.Join(err1, err2); err != nil {
		return jobJSON{}, err
	}
	return jobJSON{
		ID: s.ID, Queue: s.Queue, State: s.State, Payload: s.Payload, Tries: tries, MaxTries: maxTries,
		BackoffMS: s.BackoffMS, CreatedAt: s.CreatedAt, UpdatedAt: s.UpdatedAt,
		RunAt: s.RunAt, Worker: s.Worker, LeaseUntil: s.LeaseUntil, Reason: s.Reason,
	}, nil
}

func formatTime(t time.Time) string { return t.UTC().Format(timeLayout) }

func formatID(id uint64) string { return "j_" + strconv.FormatUint(id, 10) }

// parseID reads `j_<n>` with n a positive decimal without leading zeros.
func parseID(s string) (uint64, bool) {
	digits, ok := strings.CutPrefix(s, "j_")
	if !ok || digits == "" || digits[0] == '0' {
		return 0, false
	}
	for i := 0; i < len(digits); i++ {
		if digits[i] < '0' || digits[i] > '9' {
			return 0, false
		}
	}
	n, err := strconv.ParseUint(digits, 10, 64)
	return n, err == nil
}

func jobView(j Job) jobJSON {
	v := jobJSON{
		ID: formatID(j.ID), Queue: j.Queue, State: j.State, Payload: j.Payload,
		Tries: j.Tries, MaxTries: j.MaxTries, BackoffMS: j.BackoffMS,
		CreatedAt: formatTime(j.CreatedAt), UpdatedAt: formatTime(j.UpdatedAt),
		Reason: j.Reason,
	}
	if j.State == Scheduled {
		runAt := formatTime(j.RunAt)
		v.RunAt = &runAt
	}
	if j.State == Leased {
		worker, until := j.Worker, formatTime(j.LeaseUntil)
		v.Worker, v.LeaseUntil = &worker, &until
	}
	return v
}

// jobFromView parses a stored job. It checks syntax only; what a job may
// hold is the queue's invariants, checked when the job is applied.
func jobFromView(v jobJSON) (Job, error) {
	id, ok := parseID(v.ID)
	if !ok {
		return Job{}, fmt.Errorf("bad job id %q", v.ID)
	}
	switch v.State {
	case Scheduled, Queued, Leased, Done, Dead:
	default:
		return Job{}, fmt.Errorf("bad state %q", v.State)
	}
	created, err1 := time.Parse(timeLayout, v.CreatedAt)
	updated, err2 := time.Parse(timeLayout, v.UpdatedAt)
	if err := errors.Join(err1, err2); err != nil {
		return Job{}, err
	}
	j := Job{
		ID: id, Queue: v.Queue, State: v.State, Payload: v.Payload, Tries: v.Tries, MaxTries: v.MaxTries,
		BackoffMS: v.BackoffMS, CreatedAt: created, UpdatedAt: updated, Reason: v.Reason,
	}
	if v.Worker != nil {
		j.Worker = *v.Worker
	}
	for _, at := range []struct {
		s   *string
		dst *time.Time
	}{{v.RunAt, &j.RunAt}, {v.LeaseUntil, &j.LeaseUntil}} {
		if at.s == nil {
			continue
		}
		t, err := time.Parse(timeLayout, *at.s)
		if err != nil {
			return Job{}, err
		}
		*at.dst = t
	}
	return j, nil
}

func validQueueName(q string) bool {
	if len(q) < 1 || len(q) > 64 {
		return false
	}
	for i := 0; i < len(q); i++ {
		c := q[i]
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

// validText is UTF-8 of at most maxBytes with no control character but \n.
func validText(s string, maxBytes int) bool {
	if len(s) > maxBytes || !utf8.ValidString(s) {
		return false
	}
	for _, r := range s {
		if r != '\n' && unicode.IsControl(r) {
			return false
		}
	}
	return true
}

// validToken is 1 to 256 visible ASCII characters.
func validToken(t string) bool {
	if len(t) < 1 || len(t) > maxTokenBytes {
		return false
	}
	for i := 0; i < len(t); i++ {
		if t[i] < 0x21 || t[i] > 0x7e {
			return false
		}
	}
	return true
}

func requireQueue(q string) error {
	return contract.Require(validQueueName(q), "queue is 1 to 64 bytes of letters, digits, '-' and '_'")
}

func requirePayload(p string) error {
	return contract.Require(validText(p, maxPayloadBytes), "payload is 0 to 60 KiB of UTF-8 with no control character but \\n")
}

func requireMaxTries(n int) error {
	return contract.Require(n >= 1 && n <= 100, "max_tries is 1 to 100")
}

func requireDelayMS(ms int64) error {
	return contract.Require(ms >= 0 && ms <= maxDelayMS, "delay_ms is 0 to 86_400_000")
}

func requireBackoffMS(ms int64) error {
	return contract.Require(ms >= 0 && ms <= maxBackoffMS, "backoff_ms is 0 to 3_600_000")
}

func requireLeaseMS(ms int64) error {
	return contract.Require(ms >= minLeaseMS && ms <= maxLeaseMS, "lease_ms is 100 to 3_600_000")
}

func requireReason(r string) error {
	return contract.Require(validText(r, maxReasonBytes), "reason is 0 to 1 KiB of UTF-8 with no control character but \\n")
}

func requireWorker(w string) error {
	return contract.Require(validToken(w), "token is 1 to 256 visible ASCII characters")
}

func requireState(s string) error {
	st := State(s)
	return contract.Require(st == Scheduled || st == Queued || st == Leased || st == Done || st == Dead,
		"state is scheduled, queued, leased, done, or dead")
}
