package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func wantRequires(t *testing.T, err error, cond string) {
	t.Helper()
	if err == nil || !strings.Contains(err.Error(), "requires failed: "+cond) {
		t.Errorf("got %v, want requires failed: %s", err, cond)
	}
}

func TestRequireQueueName(t *testing.T) {
	for _, ok := range []string{"a", "emails", "A-z_09", strings.Repeat("q", 64)} {
		if err := RequireQueueName(ok); err != nil {
			t.Errorf("%q: %v", ok, err)
		}
	}
	for _, bad := range []string{"", strings.Repeat("q", 65), "a b", "a/b", "é", "a.b", "a\n"} {
		wantRequires(t, RequireQueueName(bad), "queue is 1 to 64 bytes")
	}
}

func TestRequirePayload(t *testing.T) {
	for _, ok := range []string{"", "hello\nworld", "漢字 🙂 <&>", "\u2028", strings.Repeat("a", maxPayload)} {
		if err := RequirePayload(ok); err != nil {
			t.Errorf("%.20q: %v", ok, err)
		}
	}
	for _, bad := range []string{strings.Repeat("a", maxPayload+1), "a\x00b", "tab\there", "cr\r", "\x7f", "\u0085", "bad \xff utf-8"} {
		wantRequires(t, RequirePayload(bad), "payload is 0 to 60 KiB")
	}
}

func TestRequireReason(t *testing.T) {
	if err := RequireReason("timeout\nretry"); err != nil {
		t.Error(err)
	}
	wantRequires(t, RequireReason(strings.Repeat("r", maxReason+1)), "reason is 0 to 4 KiB")
	wantRequires(t, RequireReason("\x1b[31m"), "reason is 0 to 4 KiB")
}

func TestRequireMaxAttempts(t *testing.T) {
	for _, ok := range []int{1, 3, 100} {
		if err := RequireMaxAttempts(ok); err != nil {
			t.Errorf("%d: %v", ok, err)
		}
	}
	for _, bad := range []int{-1, 0, 101} {
		wantRequires(t, RequireMaxAttempts(bad), "max_attempts >= 1 && max_attempts <= 100")
	}
}

func TestRequireLeaseMs(t *testing.T) {
	for _, ok := range []int{100, 30_000, 3_600_000} {
		if err := RequireLeaseMs(ok); err != nil {
			t.Errorf("%d: %v", ok, err)
		}
	}
	for _, bad := range []int{0, 99, 3_600_001} {
		wantRequires(t, RequireLeaseMs(bad), "lease_ms >= 100 && lease_ms <= 3_600_000")
	}
}

func TestRequireWorker(t *testing.T) {
	wantRequires(t, RequireWorker(""), `worker != ""`)
}

func TestParseID(t *testing.T) {
	for id, want := range map[string]uint64{"j_1": 1, "j_42": 42, "j_18446744073709551615": 1<<64 - 1} {
		if got, ok := parseID(id); !ok || got != want {
			t.Errorf("%q: %d %v", id, got, ok)
		}
		if formatID(want) != id {
			t.Errorf("formatID(%d) = %q", want, formatID(want))
		}
	}
	for _, bad := range []string{"", "j_", "j_0", "j_01", "1", "J_1", "j_1a", "j_-1", "j_18446744073709551616"} {
		if _, ok := parseID(bad); ok {
			t.Errorf("%q parsed", bad)
		}
	}
}

func TestJobJSONShape(t *testing.T) {
	at := stampOf(time.Date(2026, 9, 14, 10, 0, 1, 234_567_890, time.UTC))
	j := Job{ID: "j_1", Queue: "q", State: Queued, Payload: "x", MaxAttempts: 3, CreatedAt: at, UpdatedAt: at}
	b, err := json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"id":"j_1","queue":"q","state":"queued","payload":"x","attempts":0,"max_attempts":3,"created_at":"2026-09-14T10:00:01.234Z","updated_at":"2026-09-14T10:00:01.234Z"}`
	if string(b) != want {
		t.Errorf("got  %s\nwant %s", b, want)
	}
	reason := ""
	j.State, j.Attempts, j.Worker, j.LeaseUntil, j.Reason = Leased, 1, "w", at, &reason
	b, err = json.Marshal(j)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(string(b), `"worker":"w","lease_until":"2026-09-14T10:00:01.234Z","reason":""}`) {
		t.Errorf("got %s", b)
	}
	var back Job
	if err := json.Unmarshal(b, &back); err != nil || !back.LeaseUntil.Equal(at.Time) || *back.Reason != "" {
		t.Errorf("round trip: %+v %v", back, err)
	}
}
