module Jobq.Job
expose State, Job, job, leased, acked, failed, ran_out, run_out?, holds?, queue?, payload?, max_attempts?, lease_ms?, token?, id_of, number_of, state_name, state_named, shown, job_of, quoted

intent "What jobq is about: a job, its four states and the moves between them, the rules a queue name, a payload, max_attempts, a lease, and a token keep, and the one JSON object a job is both shown and stored as."

never "a job's attempts exceed its max_attempts"
  for j in Job.all
    j.attempts > j.max_attempts
  end
end

enum State
  Queued
  Leased
  Done
  Dead
end

# A job; its `state` is a field of its own (step 25). `worker` and `lease_until` are Some
# only while it is leased; `reason` is the last fail's, kept from the first fail on.
struct Job
  number: UInt64
  queue: String
  state: State
  payload: String
  attempts: UInt64
  max_attempts: UInt64
  created_at: Time
  updated_at: Time
  worker: Option(String)
  lease_until: Option(Time)
  reason: Option(String)
end

# A new job, queued, stamped now.
fn job(number: UInt64, queue: String, payload: String, max_attempts: UInt64, now: Time) : Job
  requires queue?(queue)
  requires payload?(payload)
  requires max_attempts?(max_attempts)
  ensures result.state == Queued and result.attempts == 0
  # body gone; regenerate
end

# The job leased to the worker for lease_ms from now: one attempt more.
fn leased(job: Job, worker: String, lease_ms: UInt64, now: Time) : Job
  requires lease_ms?(lease_ms)
  requires job.state == Queued and job.attempts < job.max_attempts
  ensures result.state == Leased and result.worker == Some(worker)
  ensures result.attempts == job.attempts + 1
  # body gone; regenerate
end

fn acked(job: Job, now: Time) : Job
  requires job.state == Leased
  ensures result.state == Done
  # body gone; regenerate
end

# A fail: queued again while attempts are left, dead on the last one.
fn failed(job: Job, reason: String, now: Time) : Job
  requires job.state == Leased
  ensures result.state == Queued or result.state == Dead
  # body gone; regenerate
end

# A lease that ran out: queued or dead by the same rule as a fail, the reason kept.
fn ran_out(job: Job, now: Time) : Job
  requires job.state == Leased
  ensures result.state == Queued or result.state == Dead
  # body gone; regenerate
end

fn released(job: Job, now: Time) : Job
  # body gone; regenerate
end

# A lease is a deadline: it has run out once the clock reaches lease_until.
fn run_out?(job: Job, now: Time) : Bool
  # body gone; regenerate
end

# Whether the worker holds a live lease on the job.
fn holds?(job: Job, worker: String, now: Time) : Bool
  # body gone; regenerate
end

# A queue name is 1 to 64 bytes of letters, digits, - and _.
fn queue?(text: String) : Bool
  # body gone; regenerate
end

fn named?(b: UInt8) : Bool
  # body gone; regenerate
end

# A payload is at most 60 KiB of UTF-8 with no control character but a newline.
fn payload?(text: String) : Bool
  # body gone; regenerate
end

# No C0 control character but a newline, no DEL, and no C1 control character.
fn plain?(text: String) : Bool
  # body gone; regenerate
end

# A C1 control character is two bytes in UTF-8: C2, then 80 to 9F.
fn c1?(c: String) : Bool
  # body gone; regenerate
end

fn max_attempts?(n: UInt64) : Bool
  # body gone; regenerate
end

fn lease_ms?(n: UInt64) : Bool
  # body gone; regenerate
end

# A token names a worker: 1 to 256 bytes with no space or control character.
fn token?(text: String) : Bool
  # body gone; regenerate
end

fn id_of(number: UInt64) : String
  # body gone; regenerate
end

# The number in an id, which is j_ and the number as id_of writes it.
fn number_of(id: String) : Option(UInt64)
  # body gone; regenerate
end

fn state_name(status: State) : String
  # body gone; regenerate
end

fn state_named(name: String) : Option(State)
  # body gone; regenerate
end

# A string as a JSON string, quotes and escapes included.
fn quoted(text: String) : String
  # body gone; regenerate
end

# A job as JSON: what the API shows and the record the store keeps under its id, the spec's
# fields in its order, with worker and lease_until while leased and reason after a fail. Written
# by hand, since Json.encode of a Job would write its number where the API names an id, a state by
# its variant's name where the API writes it in lowercase, and worker, lease_until, and reason as
# null where the API leaves them out.
fn shown(job: Job) : String
  # body gone; regenerate
end

fn held_part(job: Job) : String
  # body gone; regenerate
end

fn reason_part(job: Job) : String
  # body gone; regenerate
end

# A job read back from its JSON, or None for text that is not a job that keeps the rules.
fn job_of(text: String) : Option(Job)
  # body gone; regenerate
end

fn object_of(text: String) : Option(Map(String, Json))
  # body gone; regenerate
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  # body gone; regenerate
end

fn time_in(fields: Map(String, Json), name: String) : Option(Time)
  # body gone; regenerate
end

# A whole number from 0 up; a number with a fraction, or anything but a number, is None.
fn count_in(fields: Map(String, Json), name: String) : Option(UInt64)
  # body gone; regenerate
end

test "a queue name, a payload, max_attempts, a lease, and a token each keep their rule"
  assert queue?("emails") and queue?("a-b_C9") and queue?("q".repeat(64))
  assert !queue?("") and !queue?("q".repeat(65)) and !queue?("a b") and !queue?("é")
  assert payload?("") and payload?("line one\nline two") and payload?("x".repeat(61_440))
  assert !payload?("x".repeat(61_441)) and !payload?("a\tb") and !payload?("a\rb")
  assert !payload?(String.from_bytes([97, 194, 133]) or "\t")
  assert max_attempts?(1) and max_attempts?(100) and !max_attempts?(0) and !max_attempts?(101)
  assert lease_ms?(100) and lease_ms?(3_600_000) and !lease_ms?(99) and !lease_ms?(3_600_001)
  assert token?("ada") and !token?("") and !token?("a b") and !token?("k".repeat(257))
end

test "an id is j_ and the number, written one way"
  assert id_of(7) == "j_7"
  assert number_of("j_7") == Some(7)
  assert number_of("j_07") is None
  assert number_of("j_") is None
  assert number_of("7") is None
  assert number_of("j_7x") is None
end

test "a job leases, acks, fails, and runs out as the state diagram says"
  at = Time.fixture()
  made = job(1, "emails", "hi", 2, at)
  first = leased(made, "ada", 30_000, at)
  assert first.attempts == 1 and first.lease_until == Some(at + 30_000.ms)
  assert holds?(first, "ada", at) and !holds?(first, "grace", at)
  assert !run_out?(first, at + 29_999.ms) and run_out?(first, at + 30_000.ms)
  assert !holds?(first, "ada", at + 30_000.ms)
  assert acked(first, at).state == Done and acked(first, at).worker is None
  again = failed(first, "smtp down", at + 1.minute)
  assert again.state == Queued and again.reason == Some("smtp down") and again.worker is None
  second = leased(again, "grace", 100, at + 1.minute)
  assert second.attempts == 2
  assert ran_out(second, at + 2.minute).state == Dead
  assert failed(second, "still down", at).state == Dead
  assert ran_out(first, at).state == Queued
end

test "a job is shown with worker and lease_until only while leased, and reason after a fail"
  at = Time.fixture()
  made = job(3, "emails", "hi\n\"there\"", 3, at)
  assert shown(made) == "{\"id\": \"j_3\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"hi\\n\\\"there\\\"\", \"attempts\": 0, \"max_attempts\": 3, \"created_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:00:00Z\"}"
  held_job = leased(made, "ada", 1_500, at)
  assert shown(held_job).ends_with?("\"worker\": \"ada\", \"lease_until\": \"2026-01-01T00:00:01.500Z\"}")
  failed_job = failed(held_job, "no", at)
  assert shown(failed_job).ends_with?("\"attempts\": 1, \"max_attempts\": 3, \"created_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:00:00Z\", \"reason\": \"no\"}")
  both = leased(failed_job, "grace", 100, at)
  assert shown(both).ends_with?("\"worker\": \"grace\", \"lease_until\": \"2026-01-01T00:00:00.100Z\", \"reason\": \"no\"}")
  assert shown(both).contains?("\"state\": \"leased\"")
end

test "a job reads back from its JSON, and text that is not a job that keeps the rules does not"
  at = Time.fixture()
  made = job(9, "q", "p", 5, at)
  both = leased(failed(leased(made, "ada", 100, at), "x", at), "grace", 200, at)
  assert job_of(shown(made)) == Some(made)
  assert job_of(shown(both)) == Some(both)
  assert job_of(shown(acked(both, at))) == Some(acked(both, at))
  assert job_of("not json") is None
  assert job_of("[1]") is None
  assert job_of(shown(made).replace("\"attempts\": 0", "\"attempts\": 6")) is None
  assert job_of(shown(made).replace("\"attempts\": 0", "\"attempts\": 0.5")) is None
  assert job_of(shown(made).replace("\"attempts\": 0", "\"attempts\": -1")) is None
  assert job_of(shown(made).replace("\"attempts\": 0", "\"attempts\": \"0\"")) is None
  assert job_of(shown(made).replace("\"queue\": \"q\"", "\"queue\": \"a b\"")) is None
  assert job_of(shown(made).replace("\"state\": \"queued\"", "\"state\": \"lost\"")) is None
  assert job_of(shown(made).replace("\"state\": \"queued\"", "\"state\": \"leased\"")) is None
end

test rejects "a job in a queue whose name holds a space"
  job(1, "a b", "", 1, Time.fixture())
end

test rejects "a job whose payload is over 60 KiB"
  job(1, "q", "x".repeat(61_441), 1, Time.fixture())
end

test rejects "a job with no attempts allowed"
  job(1, "q", "", 0, Time.fixture())
end

test rejects "a lease shorter than 100 ms"
  leased(job(1, "q", "", 1, Time.fixture()), "ada", 99, Time.fixture())
end

test rejects "a lease of a job that is not queued"
  at = Time.fixture()
  leased(acked(leased(job(1, "q", "", 3, at), "ada", 100, at), at), "ada", 100, at)
end

test rejects "an ack of a job that is not leased"
  acked(job(1, "q", "", 1, Time.fixture()), Time.fixture())
end

test rejects "a fail of a job that is not leased"
  failed(job(1, "q", "", 1, Time.fixture()), "no", Time.fixture())
end

test rejects "a lease run out on a job that is not leased"
  ran_out(job(1, "q", "", 1, Time.fixture()), Time.fixture())
end

property "any valid payload survives a job's JSON"
  for payload in any(String), max in any(UInt64) if payload?(payload) and max_attempts?(max)
    made = job(1, "q", payload, max, Time.fixture())
    assert job_of(shown(made)) == Some(made)
  end
end
