package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestParseID(t *testing.T) {
	for s, want := range map[string]uint64{"j_1": 1, "j_42": 42, "j_18446744073709551615": 1<<64 - 1} {
		if got, ok := parseID(s); !ok || got != want {
			t.Errorf("parseID(%q) = %d, %v", s, got, ok)
		}
	}
	for _, s := range []string{"", "j_", "j_0", "j_01", "1", "j_1x", "J_1", "j_-1", "j_18446744073709551616"} {
		if _, ok := parseID(s); ok {
			t.Errorf("parseID(%q) accepted", s)
		}
	}
}

func TestJobShapes(t *testing.T) {
	at := time.Date(2026, 9, 14, 1, 2, 3, 4_000_000, time.UTC)
	reason := "smtp down"
	for _, c := range []struct {
		job  Job
		want string
	}{
		{
			Job{ID: 1, Queue: "emails", State: Queued, Payload: "hi <b>\n", MaxTries: 3, CreatedAt: at, UpdatedAt: at},
			`{"id":"j_1","queue":"emails","state":"queued","payload":"hi <b>\n","tries":0,"max_tries":3,"created_at":"2026-09-14T01:02:03.004Z","updated_at":"2026-09-14T01:02:03.004Z"}`,
		},
		{
			Job{ID: 2, Queue: "q", State: Leased, Tries: 1, MaxTries: 3, CreatedAt: at, UpdatedAt: at, Worker: "w1", LeaseUntil: at.Add(time.Second)},
			`{"id":"j_2","queue":"q","state":"leased","payload":"","tries":1,"max_tries":3,"created_at":"2026-09-14T01:02:03.004Z","updated_at":"2026-09-14T01:02:03.004Z","worker":"w1","lease_until":"2026-09-14T01:02:04.004Z"}`,
		},
		{
			Job{ID: 3, Queue: "q", State: Dead, Tries: 3, MaxTries: 3, CreatedAt: at, UpdatedAt: at, Reason: &reason},
			`{"id":"j_3","queue":"q","state":"dead","payload":"","tries":3,"max_tries":3,"created_at":"2026-09-14T01:02:03.004Z","updated_at":"2026-09-14T01:02:03.004Z","reason":"smtp down"}`,
		},
	} {
		line, err := encodeRecord(record{Op: "put", Job: ptr(jobView(c.job))})
		if err != nil {
			t.Fatal(err)
		}
		rec, err := decodeLine(line[:len(line)-1])
		if err != nil {
			t.Fatal(err)
		}
		got, err := json.Marshal(rec.Job)
		if err != nil {
			t.Fatal(err)
		}
		if want := jsonCompact(t, c.want); string(got) != want {
			t.Errorf("shape\n%s\nwant\n%s", got, want)
		}
		back, err := jobFromView(*rec.Job)
		if err != nil || jobView(back) != jobView(c.job) && !sameView(jobView(back), jobView(c.job)) {
			t.Errorf("jobFromView = %+v, %v", back, err)
		}
	}
}

func ptr[T any](v T) *T { return &v }

func jsonCompact(t *testing.T, s string) string {
	t.Helper()
	var v jobJSON
	if err := json.Unmarshal([]byte(s), &v); err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func sameView(a, b jobJSON) bool {
	x, _ := json.Marshal(a)
	y, _ := json.Marshal(b)
	return string(x) == string(y)
}
