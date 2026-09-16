package main

import (
	"errors"
	"fmt"
	"io"
	"time"
)

// A record in the store must be well-formed before the folder is served:
// change 2's answer to a log line the API can never produce. `jobq verify`
// runs the same check without serving; `serve` and `compact` run it at open.

// illFormed is a store record that breaks a rule. The key names the record,
// the rule is the line an operator reads.
// archived says the record is in the archive, not the live log.
type illFormed struct {
	key, rule string
	archived  bool
}

func (e *illFormed) Error() string {
	if e.archived {
		return fmt.Sprintf("archive record %s: %s", e.key, e.rule)
	}
	return fmt.Sprintf("record %s: %s", e.key, e.rule)
}

// wellFormed checks one store record's job against the rules of its state
// and the field rules of the spec. key is the record's key, which must name
// the job's id. It takes no precondition: any key and any decoded record
// may be handed to it, and a broken one comes back as an *illFormed. A live
// record never carries archived_at.
func wellFormed(key string, v jobJSON) error {
	if v.ArchivedAt != nil {
		return &illFormed{key: key, rule: "a live job has no archived_at"}
	}
	return wellFormedFields(key, v)
}

// wellFormedArchived checks one archive record's job: a done or dead job,
// well-formed as a live one, with archived_at at or after its updated_at.
func wellFormedArchived(key string, v jobJSON) error {
	bad := func(rule string) error { return &illFormed{key: key, rule: rule} }
	if v.State != Done && v.State != Dead {
		return bad("an archived job is done or dead")
	}
	if v.ArchivedAt == nil {
		return bad("an archived job has archived_at")
	}
	live := v
	live.ArchivedAt = nil
	if err := wellFormedFields(key, live); err != nil {
		return err
	}
	j, _ := jobFromView(live)
	at, err := time.Parse(timeLayout, *v.ArchivedAt)
	if err != nil {
		return bad(err.Error())
	}
	if at.Before(j.UpdatedAt) {
		return bad("an archived job's archived_at is at or after its updated_at")
	}
	return nil
}

func wellFormedFields(key string, v jobJSON) error {
	bad := func(rule string) error { return &illFormed{key: key, rule: rule} }
	if key != v.ID {
		return bad("the key does not name the job's id " + v.ID)
	}
	j, err := jobFromView(v)
	if err != nil {
		return bad(err.Error())
	}
	switch {
	case !validQueueName(j.Queue):
		return bad("queue is 1 to 64 bytes of letters, digits, '-' and '_'")
	case v.Key != nil && !validKey(*v.Key):
		return bad("key is 1 to 64 bytes of letters, digits, '-' and '_'")
	case !validText(j.Payload, maxPayloadBytes):
		return bad("payload is 0 to 60 KiB of UTF-8 with no control character but \\n")
	case j.MaxTries < 1 || j.MaxTries > 100:
		return bad("max_tries is 1 to 100")
	case j.BackoffMS < 0 || j.BackoffMS > maxBackoffMS:
		return bad("backoff_ms is 0 to 3_600_000")
	case v.Reason != nil && !validText(*v.Reason, maxReasonBytes):
		return bad("reason is 0 to 1 KiB of UTF-8 with no control character but \\n")
	case j.UpdatedAt.Before(j.CreatedAt):
		return bad("created_at is at or before updated_at")
	}
	// Each state says what its tries may be and which of run_at, worker,
	// and lease_until it carries; every other one of the three is absent.
	state := string(v.State)
	switch v.State {
	case Queued, Scheduled:
		if v.Tries < 0 || v.Tries >= v.MaxTries {
			return bad("a " + state + " job has tries from 0 below max_tries")
		}
	default:
		if v.Tries < 1 || v.Tries > v.MaxTries {
			return bad("a " + state + " job has tries from 1 to max_tries")
		}
	}
	for _, f := range []struct {
		name string
		set  bool
		want bool
	}{
		{"run_at", v.RunAt != nil, v.State == Scheduled},
		{"worker", v.Worker != nil, v.State == Leased},
		{"lease_until", v.LeaseUntil != nil, v.State == Leased},
	} {
		if f.set != f.want {
			return bad(fmt.Sprintf("a %s job has %s %s", state, none(f.want), f.name))
		}
	}
	if v.State == Leased && !validToken(j.Worker) {
		return bad("worker is 1 to 256 visible ASCII characters")
	}
	if v.State == Scheduled && !j.RunAt.After(j.UpdatedAt) {
		return bad("a scheduled job's run_at is after its updated_at")
	}
	return nil
}

func none(want bool) string {
	if want {
		return "a"
	}
	return "no"
}

// asIllFormed names dir in front of a refused record, so serve, compact, and
// verify all print `jobq: <dir>: record <key>: <rule>`.
func asIllFormed(dir string, err error) error {
	var ill *illFormed
	if errors.As(err, &ill) {
		return fmt.Errorf("%s: %w", dir, ill)
	}
	return err
}

func cmdVerify(args []string, stdout, stderr io.Writer) int {
	if len(args) != 1 {
		return usageError(stderr, "verify takes <dir>")
	}
	q, s, err := openQueue(args[0], realClock{})
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	line := fmt.Sprintf("%d jobs: queued %d, scheduled %d, leased %d, done %d, dead %d; next id %s; archived %d\n",
		len(q.jobs), q.counts[Queued], q.counts[Scheduled], q.counts[Leased], q.counts[Done], q.counts[Dead],
		formatID(q.nextID), len(q.archived))
	if err := errors.Join(s.Close(), q.closeArchive()); err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	fmt.Fprint(stdout, line)
	return 0
}
