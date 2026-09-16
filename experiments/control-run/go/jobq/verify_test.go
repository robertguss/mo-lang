package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var wellFormedAt = time.Date(2026, 9, 14, 0, 0, 0, 0, time.UTC)

// wellFormedJob is the record the service itself writes for a job in state.
func wellFormedJob(state State) jobJSON {
	j := Job{ID: 1, Queue: "a", State: state, Payload: "p", MaxTries: 2, BackoffMS: 1000,
		CreatedAt: wellFormedAt, UpdatedAt: wellFormedAt}
	switch state {
	case Scheduled:
		j.RunAt = wellFormedAt.Add(time.Minute)
	case Leased:
		j.Tries, j.Worker, j.LeaseUntil = 1, "w1", wellFormedAt.Add(time.Minute)
	case Done:
		j.Tries = 1
	case Dead:
		j.Tries = 2
	}
	return jobView(j)
}

// A record the service writes is well-formed in every state.
func TestWellFormedAcceptsWhatTheServiceWrites(t *testing.T) {
	for _, state := range []State{Queued, Scheduled, Leased, Done, Dead} {
		v := wellFormedJob(state)
		if err := wellFormed(v.ID, v); err != nil {
			t.Errorf("a %s job the service wrote: %v", state, err)
		}
	}
}

// One test per state for the fields that state may and may not carry, plus
// the field rules of the spec.
func TestWellFormedRefusesByState(t *testing.T) {
	at := formatTime(wellFormedAt)
	for _, c := range []struct {
		name   string
		state  State
		break_ func(*jobJSON)
		want   string
	}{
		{"queued with tries at max_tries", Queued, func(v *jobJSON) { v.Tries = v.MaxTries }, "a queued job has tries from 0 below max_tries"},
		{"queued with a run_at", Queued, func(v *jobJSON) { v.RunAt = ptr(at) }, "a queued job has no run_at"},
		{"queued with a worker", Queued, func(v *jobJSON) { v.Worker = ptr("w1") }, "a queued job has no worker"},
		{"queued with a lease_until", Queued, func(v *jobJSON) { v.LeaseUntil = ptr(at) }, "a queued job has no lease_until"},

		{"scheduled with tries at max_tries", Scheduled, func(v *jobJSON) { v.Tries = v.MaxTries }, "a scheduled job has tries from 0 below max_tries"},
		{"scheduled with no run_at", Scheduled, func(v *jobJSON) { v.RunAt = nil }, "a scheduled job has a run_at"},
		{"scheduled with a worker", Scheduled, func(v *jobJSON) { v.Worker = ptr("w1") }, "a scheduled job has no worker"},
		{"scheduled with a lease_until", Scheduled, func(v *jobJSON) { v.LeaseUntil = ptr(at) }, "a scheduled job has no lease_until"},
		{"scheduled before its updated_at", Scheduled, func(v *jobJSON) { v.RunAt = ptr(at) }, "a scheduled job's run_at is after its updated_at"},

		{"leased with tries at 0", Leased, func(v *jobJSON) { v.Tries = 0 }, "a leased job has tries from 1 to max_tries"},
		{"leased past max_tries", Leased, func(v *jobJSON) { v.Tries = v.MaxTries + 1 }, "a leased job has tries from 1 to max_tries"},
		{"leased with no worker", Leased, func(v *jobJSON) { v.Worker = nil }, "a leased job has a worker"},
		{"leased with no lease_until", Leased, func(v *jobJSON) { v.LeaseUntil = nil }, "a leased job has a lease_until"},
		{"leased with a run_at", Leased, func(v *jobJSON) { v.RunAt = ptr(at) }, "a leased job has no run_at"},
		{"leased by a worker with a space", Leased, func(v *jobJSON) { v.Worker = ptr("w 1") }, "worker is 1 to 256 visible ASCII characters"},

		{"done with tries at 0", Done, func(v *jobJSON) { v.Tries = 0 }, "a done job has tries from 1 to max_tries"},
		{"done past max_tries", Done, func(v *jobJSON) { v.Tries = v.MaxTries + 1 }, "a done job has tries from 1 to max_tries"},
		{"done with a run_at", Done, func(v *jobJSON) { v.RunAt = ptr(at) }, "a done job has no run_at"},
		{"done with a worker", Done, func(v *jobJSON) { v.Worker = ptr("w1") }, "a done job has no worker"},
		{"done with a lease_until", Done, func(v *jobJSON) { v.LeaseUntil = ptr(at) }, "a done job has no lease_until"},

		{"dead with tries at 0", Dead, func(v *jobJSON) { v.Tries = 0 }, "a dead job has tries from 1 to max_tries"},
		{"dead with a run_at", Dead, func(v *jobJSON) { v.RunAt = ptr(at) }, "a dead job has no run_at"},
		{"dead with a worker", Dead, func(v *jobJSON) { v.Worker = ptr("w1") }, "a dead job has no worker"},
		{"dead with a lease_until", Dead, func(v *jobJSON) { v.LeaseUntil = ptr(at) }, "a dead job has no lease_until"},

		{"a queue name with a space", Queued, func(v *jobJSON) { v.Queue = "a b" }, "queue is 1 to 64 bytes"},
		{"a payload with a control character", Queued, func(v *jobJSON) { v.Payload = "\x01" }, "payload is 0 to 60 KiB"},
		{"max_tries at 0", Queued, func(v *jobJSON) { v.MaxTries = 0 }, "max_tries is 1 to 100"},
		{"max_tries past 100", Queued, func(v *jobJSON) { v.MaxTries = 101 }, "max_tries is 1 to 100"},
		{"backoff_ms past an hour", Queued, func(v *jobJSON) { v.BackoffMS = maxBackoffMS + 1 }, "backoff_ms is 0 to 3_600_000"},
		{"a reason with a control character", Queued, func(v *jobJSON) { v.Reason = ptr("\x01") }, "reason is 0 to 1 KiB"},
		{"created_at after updated_at", Queued, func(v *jobJSON) { v.CreatedAt = formatTime(wellFormedAt.Add(time.Hour)) }, "created_at is at or before updated_at"},
		{"a state the spec does not name", Queued, func(v *jobJSON) { v.State = "paused" }, `bad state "paused"`},
		{"an id that is not j_<n>", Queued, func(v *jobJSON) { v.ID = "1" }, `bad job id "1"`},
		{"a lease_until that is not a time", Leased, func(v *jobJSON) { v.LeaseUntil = ptr("soon") }, "cannot parse"},
	} {
		v := wellFormedJob(c.state)
		c.break_(&v)
		err := wellFormed(v.ID, v)
		var ill *illFormed
		if err == nil {
			t.Errorf("%s: well-formed, want %q", c.name, c.want)
			continue
		}
		if !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: %v, want %q", c.name, err, c.want)
		}
		if !asIllFormedIs(err, &ill) || ill.key != v.ID {
			t.Errorf("%s: %v is not an *illFormed keyed by %s", c.name, err, v.ID)
		}
	}
}

// The key of a record must name the job it holds.
func TestWellFormedNeedsTheKeyToNameTheJob(t *testing.T) {
	v := wellFormedJob(Queued)
	err := wellFormed("j_7", v)
	if err == nil || !strings.Contains(err.Error(), "the key does not name the job's id j_1") {
		t.Errorf("a record keyed j_7 holding j_1 = %v", err)
	}
}

func asIllFormedIs(err error, dst **illFormed) bool {
	ill, ok := err.(*illFormed)
	if ok {
		*dst = ill
	}
	return ok
}

// verify on the program's own fixture folders, and on a hand-written
// ill-formed one.
func TestVerifyCommand(t *testing.T) {
	empty := t.TempDir()
	if code, out, errOut := runCmd("verify", empty); code != 0 ||
		out != "0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_1\n" {
		t.Errorf("verify of an empty folder = %d, %q, %q", code, out, errOut)
	}
	old := copyFixture(t, "testdata/v1/jobq.log")
	if code, out, errOut := runCmd("verify", old); code != 0 ||
		out != "6 jobs: queued 2, scheduled 0, leased 2, done 1, dead 1; next id j_9\n" {
		t.Errorf("verify of testdata/v1 = %d, %q, %q", code, out, errOut)
	}
	ill := copyFixture(t, "testdata/ill/jobq.log")
	want := "jobq: " + ill + ": record j_2: a leased job has a worker\n"
	if code, out, errOut := runCmd("verify", ill); code != 1 || out != "" || errOut != want {
		t.Errorf("verify of testdata/ill = %d, %q, %q; want 1 and %q", code, out, errOut, want)
	}
	// serve and compact refuse the same folder the same way, and serve does
	// it before it binds a port.
	for _, args := range [][]string{{"serve", ill}, {"serve", ill, "--port", "7901"}, {"compact", ill}} {
		if code, out, errOut := runCmd(args...); code != 1 || out != "" || errOut != want {
			t.Errorf("jobq %q = %d, %q, %q; want 1 and %q", args, code, out, errOut, want)
		}
	}
	// The check command serves through the same door.
	script := filepath.Join(t.TempDir(), "s.script")
	if err := os.WriteFile(script, []byte("- GET /health\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := runCmd("check", ill, script); code != 1 {
		t.Errorf("check on an ill-formed folder = %d, want 1", code)
	}
}

// A last line with no newline is still a torn write, not a refusal.
func TestVerifyCutsATornLastLine(t *testing.T) {
	dir := t.TempDir()
	good := lineFor(`{"op":"put","job":{"id":"j_1","queue":"a","state":"queued","payload":"p","tries":0,"max_tries":2,"backoff_ms":0,` +
		`"created_at":"2026-09-14T00:00:00.000Z","updated_at":"2026-09-14T00:00:00.000Z"}}`)
	torn := good[:len(good)/2]
	if err := os.WriteFile(filepath.Join(dir, logName), []byte(good+torn), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, out, errOut := runCmd("verify", dir); code != 0 ||
		out != "1 jobs: queued 1, scheduled 0, leased 0, done 0, dead 0; next id j_2\n" {
		t.Errorf("verify of a torn log = %d, %q, %q", code, out, errOut)
	}
}

func copyFixture(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, logName), data, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}
