module Jobq.Job
expose State, Job, Move, queue?, payload?, attempts?, lease_ms?, reason?, token?, id_of, id_number, created, leased, acked, failed, expired, run_out?, held_by?, open?, json_of, job_of, state_name, state_of

intent "What jobq is about: a job, its four states and the moves between them, the rules a queue name, a payload, max_attempts, lease_ms, a reason, and a worker's token keep, and the JSON a job is stored and answered as."

never "a job's attempts exceed its max_attempts"
  for j in Job.all
    j.attempts > j.max_attempts
  end
end

never "a done job is leased again, or a dead job is leased"
  for m in Move.all
    m.to == Leased and (m.from == Done or m.from == Dead)
  end
end

enum State
  Queued
  Leased
  Done
  Dead
end

# worker and lease_until are Some while the job is leased; reason is the last fail's.
struct Job
  id: String
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

# One job moved from one state to another, as the queue took it.
struct Move
  id: String
  from: State
  to: State
end

# A queue name is 1 to 64 bytes of letters, digits, - and _.
fn queue?(text: String) : Bool
  size = text.byte_size
  size >= 1 and size <= 64 and text.bytes.all?(fn(b) name_byte?(b) end)
end

fn name_byte?(b: UInt8) : Bool
  digit = b >= 48 and b <= 57
  letter = (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
  digit or letter or b == 45 or b == 95
end

# A payload is 0 to 60 KiB of UTF-8 with no control character but a newline.
fn payload?(text: String) : Bool
  text.byte_size <= 61_440 and plain?(text)
end

fn attempts?(n: UInt64) : Bool
  n >= 1 and n <= 100
end

fn lease_ms?(n: UInt64) : Bool
  n >= 100 and n <= 3_600_000
end

# A fail's reason is at most 1 KiB, as plain as a payload.
fn reason?(text: String) : Bool
  text.byte_size <= 1_024 and plain?(text)
end

# A worker's token is 1 to 64 bytes with no space and no control character.
fn token?(text: String) : Bool
  size = text.byte_size
  size >= 1 and size <= 64 and text.bytes.all?(fn(b) b > 32 and b != 127 end)
end

# No C0 control character but a newline, no DEL, and no C1 control character (U+0080 to U+009F,
# C2 then 80 to 9F in UTF-8).
fn plain?(text: String) : Bool
  ascii = text.bytes.all?(fn(b) b >= 32 and b != 127 or b == 10 end)
  return ascii if !ascii or text.size == text.byte_size
  !text.chars.any?(fn(c) c1?(c) end)
end

fn c1?(c: String) : Bool
  second = c.bytes.get(1) or 0
  c.bytes.first == Some(194) and second >= 128 and second <= 159
end

fn id_of(n: UInt64) : String
  "j_#{n}"
end

# The number in an id, j_ and digits.
fn id_number(id: String) : Option(UInt64)
  return None if !id.starts_with?("j_")
  id.slice(2, id.size).to_u64
end

fn created(n: UInt64, queue: String, payload: String, max_attempts: UInt64, now: Time) : Job
  requires queue?(queue)
  requires payload?(payload)
  requires attempts?(max_attempts)
  ensures result.state == Queued and result.attempts == 0

  Job(id: id_of(n), queue: queue, state: Queued, payload: payload, attempts: 0,
    max_attempts: max_attempts, created_at: now, updated_at: now, worker: None, lease_until: None,
    reason: None)
end

fn leased(job: Job, worker: String, lease_ms: UInt64, now: Time) : Job
  requires job.state == Queued
  requires token?(worker)
  requires lease_ms?(lease_ms)
  ensures result.state == Leased and result.worker == Some(worker)
  ensures result.attempts == job.attempts + 1

  var after = job
  after.state = Leased
  after.attempts = job.attempts + 1
  after.updated_at = now
  after.worker = Some(worker)
  after.lease_until = Some(now + lease_ms.to_i64.ms)
  after
end

fn acked(job: Job, now: Time) : Job
  requires job.state == Leased
  ensures result.state == Done

  released(job, Done, now)
end

# A fail puts the job back while it has attempts left, and makes it dead on its last.
fn failed(job: Job, reason: String, now: Time) : Job
  requires job.state == Leased
  requires reason?(reason)
  ensures result.state == Queued or result.state == Dead

  var after = released(job, again(job), now)
  after.reason = Some(reason)
  after
end

# A lease that ran out puts the job back, or makes it dead, by the rule a fail keeps.
fn expired(job: Job, now: Time) : Job
  requires run_out?(job, now)
  ensures !run_out?(result, now) and result.attempts == job.attempts

  released(job, again(job), now)
end

fn again(job: Job) : State
  if job.attempts < job.max_attempts: Queued else: Dead
end

fn released(job: Job, to: State, now: Time) : Job
  var after = job
  after.state = to
  after.updated_at = now
  after.worker = None
  after.lease_until = None
  after
end

# Whether the job is leased on a lease that has run out: at its lease_until it has.
fn run_out?(job: Job, now: Time) : Bool
  job.state == Leased and (job.lease_until or now) <= now
end

fn held_by?(job: Job, worker: String, now: Time) : Bool
  job.state == Leased and job.worker == Some(worker) and !run_out?(job, now)
end

fn open?(job: Job) : Bool
  job.state == Queued or job.state == Leased
end

fn state_name(given: State) : String
  case given
    Queued: "queued"
    Leased: "leased"
    Done: "done"
    Dead: "dead"
  end
end

fn state_of(name: String) : Option(State)
  case name
    "queued": Some(Queued)
    "leased": Some(Leased)
    "done": Some(Done)
    "dead": Some(Dead)
    _: None
  end
end

# The job as the API answers it and the store keeps it: worker and lease_until while leased,
# reason once a fail gave one.
fn json_of(job: Job) : String
  ensures !result.contains?("\n")

  base = ["\"id\": #{Json.encode(job.id)}",
    "\"queue\": #{Json.encode(job.queue)}",
    "\"state\": #{Json.encode(state_name(job.state))}",
    "\"payload\": #{Json.encode(job.payload)}",
    "\"attempts\": #{job.attempts}",
    "\"max_attempts\": #{job.max_attempts}",
    "\"created_at\": #{Json.encode(job.created_at)}",
    "\"updated_at\": #{Json.encode(job.updated_at)}"]
  "{#{String.join(base.concat(lease_fields(job)).concat(reason_field(job)), ", ")}}"
end

fn lease_fields(job: Job) : List(String)
  case (job.worker, job.lease_until)
    (Some(worker), Some(until)):
      ["\"worker\": #{Json.encode(worker)}", "\"lease_until\": #{Json.encode(until)}"]
    (_, _): []
  end
end

fn reason_field(job: Job) : List(String)
  case job.reason
    Some(reason): ["\"reason\": #{Json.encode(reason)}"]
    None: []
  end
end

# A job read back from its JSON; None for anything that is not one.
fn job_of(text: String) : Option(Job)
  case Json.decode(text)
    Ok(Object(fields)):
      status = try state_of(try text_in(fields, "state"))
      Some(Job(id: try text_in(fields, "id"), queue: try text_in(fields, "queue"), state: status,
        payload: try text_in(fields, "payload"), attempts: try count_in(fields, "attempts"),
        max_attempts: try count_in(fields, "max_attempts"),
        created_at: try time_in(fields, "created_at"),
        updated_at: try time_in(fields, "updated_at"), worker: text_in(fields, "worker"),
        lease_until: time_in(fields, "lease_until"), reason: text_in(fields, "reason")))
    Ok(_): None
    Error(_): None
  end
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  case fields.get(name)
    Some(String(text)): Some(text)
    Some(_): None
    None: None
  end
end

fn count_in(fields: Map(String, Json), name: String) : Option(UInt64)
  value = try fields.get(name)
  n = try value.to_i64
  n.checked_to_u64
end

fn time_in(fields: Map(String, Json), name: String) : Option(Time)
  Time.parse(try text_in(fields, name))
end

fn at(seconds: UInt64) : Time
  Time.from_parts(2026, 9, 14, 9, 0, seconds)
end

test "a queue name is 1 to 64 bytes of letters, digits, - and _"
  assert queue?("emails") and queue?("a") and queue?("Q-1_x") and queue?("q".repeat(64))
  assert !queue?("") and !queue?("q".repeat(65)) and !queue?("two words") and !queue?("a/b")
  assert !queue?("café")
end

test "a payload is up to 60 KiB with no control character but a newline, and a token has no space"
  assert payload?("") and payload?("line\nline") and payload?("é".repeat(10))
  assert payload?("p".repeat(61_440)) and !payload?("p".repeat(61_441))
  assert !payload?("tab\there") and !payload?("a\rb")
  next_line = String.from_bytes([194, 133]) or ""
  no_break = String.from_bytes([194, 160]) or ""
  assert !payload?(next_line) and payload?(no_break)
  assert reason?("r".repeat(1_024)) and !reason?("r".repeat(1_025))
  assert token?("ada") and !token?("") and !token?("a b") and !token?("t".repeat(65))
  assert attempts?(1) and attempts?(100) and !attempts?(0) and !attempts?(101)
  assert lease_ms?(100) and lease_ms?(3_600_000) and !lease_ms?(99) and !lease_ms?(3_600_001)
end

test "an id is j_ and a number"
  assert id_of(12) == "j_12"
  assert id_number("j_12") == Some(12)
  assert id_number("n_12") is None and id_number("j_") is None and id_number("j_x") is None
end

test "a lease holds the job for the worker with one more attempt, and an ack makes it done"
  job = created(1, "emails", "hi", 3, at(0))
  held = leased(job, "ada", 30_000, at(1))
  assert held.state == Leased and held.attempts == 1
  assert held.lease_until == Some(at(31))
  assert held_by?(held, "ada", at(30)) and !held_by?(held, "bob", at(30))
  assert !held_by?(held, "ada", at(31)) and run_out?(held, at(31)) and !run_out?(held, at(30))
  done = acked(held, at(2))
  assert done.state == Done and done.worker is None and done.lease_until is None
  assert !open?(done) and open?(job) and open?(held)
end

test "a fail or a lease run out puts the job back with attempts left, and makes it dead on its last"
  job = created(1, "emails", "hi", 2, at(0))
  first = failed(leased(job, "ada", 100, at(1)), "smtp down", at(2))
  assert first.state == Queued and first.attempts == 1 and first.reason == Some("smtp down")
  second = leased(first, "bob", 1_000, at(3))
  assert second.reason == Some("smtp down")
  gone = expired(second, at(4))
  assert gone.state == Dead and gone.attempts == 2 and gone.worker is None
  back = expired(leased(job, "ada", 1_000, at(1)), at(2))
  assert back.state == Queued and back.attempts == 1
end

test "a job's JSON has the spec's fields, worker and lease_until while leased, and reason after a fail"
  job = created(7, "emails", "say \"hi\"\n", 3, at(0))
  queued = "{\"id\": \"j_7\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"say \\\"hi\\\"\\n\", \"attempts\": 0, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:00:00Z\"}"
  assert json_of(job) == queued
  held = leased(job, "ada", 1_500, at(1))
  assert json_of(held).ends_with?("\"worker\": \"ada\", \"lease_until\": \"2026-09-14T09:00:02.500Z\"}")
  back = failed(held, "no", at(2))
  assert json_of(back).ends_with?("\"updated_at\": \"2026-09-14T09:00:02Z\", \"reason\": \"no\"}")
  assert job_of(json_of(job)) == Some(job)
  assert job_of(json_of(held)) == Some(held)
  assert job_of(json_of(back)) == Some(back)
  assert job_of("{\"id\": \"j_1\"}") is None and job_of("not json") is None
  assert state_of("leased") == Some(Leased) and state_of("Leased") is None
end

test rejects "a job in a queue whose name has a space"
  created(1, "two words", "", 3, at(0))
end

test rejects "a job whose payload holds a tab"
  created(1, "emails", "a\tb", 3, at(0))
end

test rejects "a job with no attempts"
  created(1, "emails", "", 0, at(0))
end

test rejects "a lease on a job that is done"
  job = created(1, "emails", "", 3, at(0))
  leased(acked(leased(job, "ada", 1_000, at(1)), at(2)), "bob", 1_000, at(3))
end

test rejects "a lease for an empty token"
  leased(created(1, "emails", "", 3, at(0)), "", 1_000, at(1))
end

test rejects "a lease of 99 ms"
  leased(created(1, "emails", "", 3, at(0)), "ada", 99, at(1))
end

test rejects "an ack of a job that is not leased"
  acked(created(1, "emails", "", 3, at(0)), at(1))
end

test rejects "a fail of a job that is not leased"
  failed(created(1, "emails", "", 3, at(0)), "no", at(1))
end

test rejects "a fail whose reason holds a control character"
  failed(leased(created(1, "emails", "", 3, at(0)), "ada", 1_000, at(1)),
    String.from_bytes([97, 0, 98]) or "", at(2))
end

test rejects "an expiry of a lease that is still live"
  expired(leased(created(1, "emails", "", 3, at(0)), "ada", 1_000, at(1)), at(1))
end

test rejects "a job with more attempts than its max trips the never"
  var job = created(1, "emails", "", 1, at(0))
  job.attempts = 2
  assert job.attempts == 2
end

test rejects "a move from done to leased trips the never"
  move = Move(id: "j_1", from: Done, to: Leased)
  assert move.id == "j_1"
end

property "any valid payload reads back from a job's JSON as it was written"
  for payload in any(String), n in any(UInt32) if payload?(payload)
    job = created(n.to_u64, "q", payload, 3, at(0))
    assert job_of(json_of(job)) == Some(job)
  end
end
