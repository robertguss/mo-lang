package main

import (
	"encoding/json"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"jobq/contract"
)

// The limits the spec sets on a job and a lease.
const (
	maxQueueName   = 64
	maxPayload     = 60 << 10
	maxReason      = 4 << 10
	minAttempts    = 1
	maxAttempts    = 100
	minLeaseMs     = 100
	maxLeaseMs     = 3_600_000
	defaultLeaseMs = 30_000
)

// State is where a job is in its life.
type State string

// The four states of the spec's state machine.
const (
	Queued State = "queued"
	Leased State = "leased"
	Done   State = "done"
	Dead   State = "dead"
)

func (s State) valid() bool { return s == Queued || s == Leased || s == Done || s == Dead }

// Stamp is a UTC time with millisecond precision, written as ISO-8601.
type Stamp struct{ time.Time }

const stampLayout = "2006-01-02T15:04:05.000Z"

// MarshalJSON writes "2026-09-14T10:00:00.000Z".
func (s Stamp) MarshalJSON() ([]byte, error) {
	return []byte(`"` + s.UTC().Format(stampLayout) + `"`), nil
}

// UnmarshalJSON reads what MarshalJSON writes and nothing else.
func (s *Stamp) UnmarshalJSON(b []byte) error {
	var text string
	if err := json.Unmarshal(b, &text); err != nil {
		return err
	}
	t, err := time.Parse(stampLayout, text)
	if err != nil {
		return err
	}
	s.Time = t
	return nil
}

func stampOf(t time.Time) Stamp { return Stamp{t.UTC().Truncate(time.Millisecond)} }

// Job is the `{job}` of the API and the record the store keeps under its id.
type Job struct {
	ID          string  `json:"id"`
	Queue       string  `json:"queue"`
	State       State   `json:"state"`
	Payload     string  `json:"payload"`
	Attempts    int     `json:"attempts"`
	MaxAttempts int     `json:"max_attempts"`
	CreatedAt   Stamp   `json:"created_at"`
	UpdatedAt   Stamp   `json:"updated_at"`
	Worker      string  `json:"worker,omitempty"`
	LeaseUntil  Stamp   `json:"lease_until,omitzero"`
	Reason      *string `json:"reason,omitempty"`
}

func formatID(n uint64) string { return "j_" + strconv.FormatUint(n, 10) }

// parseID reads `j_<n>` with n >= 1 and no leading zero.
func parseID(id string) (uint64, bool) {
	digits, ok := strings.CutPrefix(id, "j_")
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

// RequireQueueName: 1 to 64 bytes of letters, digits, '-', '_'.
func RequireQueueName(name string) error {
	ok := len(name) >= 1 && len(name) <= maxQueueName
	for i := 0; ok && i < len(name); i++ {
		c := name[i]
		ok = c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_'
	}
	return contract.Require(ok, "queue is 1 to 64 bytes of [A-Za-z0-9_-]")
}

// RequirePayload: 0 to 60 KiB of UTF-8 with no control character but \n.
func RequirePayload(payload string) error {
	return contract.Require(len(payload) <= maxPayload && cleanText(payload), `payload is 0 to 60 KiB of UTF-8, no control characters but \n`)
}

// RequireReason: a fail's reason follows the payload's rule, up to 4 KiB.
func RequireReason(reason string) error {
	return contract.Require(len(reason) <= maxReason && cleanText(reason), `reason is 0 to 4 KiB of UTF-8, no control characters but \n`)
}

// RequireMaxAttempts: 1 to 100.
func RequireMaxAttempts(n int) error {
	return contract.Require(n >= minAttempts && n <= maxAttempts, "max_attempts >= 1 && max_attempts <= 100")
}

// RequireLeaseMs: 100 to 3,600,000.
func RequireLeaseMs(ms int) error {
	return contract.Require(ms >= minLeaseMs && ms <= maxLeaseMs, "lease_ms >= 100 && lease_ms <= 3_600_000")
}

// RequireWorker: the token that names a worker is not empty.
func RequireWorker(worker string) error {
	return contract.Require(worker != "", `worker != ""`)
}

func cleanText(s string) bool {
	if !utf8.ValidString(s) {
		return false
	}
	for _, r := range s {
		if r != '\n' && unicode.IsControl(r) {
			return false
		}
	}
	return true
}
