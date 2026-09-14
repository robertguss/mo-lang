module Jobq.Job
expose Phase, Job, Settled, Look, job, leased, acked, failed, looked, holds?, run_out?, queue?, payload?, reason?, token?, attempts?, lease_ms?, id_of, number_of, phase_named, phase_name, shown, decoded, to_ms

intent "A job and its rules: a queue's name, a payload, attempts, and a lease; each move between the four states as a function whose contracts say what it leaves; and the one line of JSON a job is kept as, which is also what the API shows."

never "a job's attempts exceed its max_attempts"
  for j in Job.all
    j.attempts > j.max_attempts
  end
end

never "a job is held by two workers at once"
  for a in Settled.all, b in Settled.all if a.number == b.number and a.attempt == b.attempt
    a.worker != b.worker
  end
end

never "a lease that ran out still holds its job after a look"
  for l in Look.all
    l.leased and l.until <= l.at
  end
end

enum Phase
  Queued
  Leased
  Done
  Dead
end

# `worker` and `lease_until` are Some only while the job is leased; `reason` is the last fail's.
struct Job
  number: UInt64
  queue: String
  state: Phase
  payload: String
  attempts: UInt64
  max_attempts: UInt64
  created_at: Time
  updated_at: Time
  worker: Option(String)
  lease_until: Option(Time)
  reason: Option(String)
end

# A worker's ack or fail of one lease, the attempt it ended.
struct Settled
  number: UInt64
  attempt: UInt64
  worker: String
end

# A look at a job: when, whether it is still leased after the look, and until when.
struct Look
  number: UInt64
  at: Time
  leased: Bool
  until: Time
end

# A queue's name is 1 to 64 bytes of ASCII letters, digits, - and _.
fn queue?(name: String) : Bool
  size = name.byte_size
  size >= 1 and size <= 64 and name.bytes.all?(fn(b) word_byte?(b) end)
end

fn word_byte?(b: UInt8) : Bool
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45 or b == 95
end

# A payload is at most 60 KiB of UTF-8 with no control character but a newline.
fn payload?(text: String) : Bool
  text.byte_size <= 61_440 and plain?(text)
end

# A fail's reason is at most 4 KiB with no control character but a newline, so its record stays
# far under the store's limit however it is escaped.
fn reason?(text: String) : Bool
  text.byte_size <= 4_096 and plain?(text)
end

# No C0 control character but a newline, no DEL, and no C1 control character (U+0080 to U+009F,
# two bytes in UTF-8: C2, then 80 to 9F).
fn plain?(text: String) : Bool
  ascii = text.bytes.all?(fn(b) (b >= 32 and b != 127) or b == 10 end)
  return ascii if !ascii or text.size == text.byte_size
  !text.bytes.enumerate.any?(fn(e) e.1 == 194 and c1_after?(text, e.0) end)
end

fn c1_after?(text: String, at: UInt64) : Bool
  next = text.bytes.get(at + 1) or 0
  next >= 128 and next <= 159
end

# A token is RFC 6750's b64token, 1 to 256 bytes: letters, digits, - . _ ~ + /, then any = signs.
fn token?(text: String) : Bool
  size = text.byte_size
  return false if size < 1 or size > 256
  body = text.bytes.filter(fn(b) b != 61 end)
  tail = text.bytes.drop(body.size)
  body.size >= 1 and body.all?(fn(b) token_byte?(b) end) and tail.all?(fn(b) b == 61 end)
end

fn token_byte?(b: UInt8) : Bool
  word_byte?(b) or b == 46 or b == 126 or b == 43 or b == 47
end

fn attempts?(n: UInt64) : Bool
  n >= 1 and n <= 100
end

fn lease_ms?(n: UInt64) : Bool
  n >= 100 and n <= 3_600_000
end

# A time cut to whole milliseconds, as the store writes it, so a job reads back equal.
fn to_ms(at: Time) : Time
  Time.parse(at.to_iso8601) or at
end

# A new job, queued, with no attempts yet.
fn job(number: UInt64, queue: String, payload: String, max_attempts: UInt64, now: Time) : Job
  requires queue?(queue)
  requires payload?(payload)
  requires attempts?(max_attempts)
  ensures result.state == Queued and result.attempts == 0

  Job(number: number, queue: queue, state: Queued, payload: payload, attempts: 0,
    max_attempts: max_attempts, created_at: now, updated_at: now, worker: None, lease_until: None,
    reason: None)
end

# The job leased to the worker for `lease_ms` from now, one attempt more.
fn leased(job: Job, worker: String, lease_ms: UInt64, now: Time) : Job
  requires job.state == Queued and job.attempts < job.max_attempts
  requires token?(worker)
  requires lease_ms?(lease_ms)
  ensures result.state == Leased and result.worker == Some(worker)
  ensures result.attempts == job.attempts + 1

  var next = job
  next.state = Leased
  next.attempts = job.attempts + 1
  next.updated_at = now
  next.worker = Some(worker)
  next.lease_until = Some(now + lease_ms.to_i64.ms)
  next
end

# Whether the worker holds a lease on the job that has not run out.
fn holds?(job: Job, worker: String, now: Time) : Bool
  job.state == Leased and job.worker == Some(worker) and !run_out?(job, now)
end

# A lease has run out at its `lease_until`.
fn run_out?(job: Job, now: Time) : Bool
  case job.lease_until
    Some(until): until <= now
    None: false
  end
end

# The job done by the worker that holds it.
fn acked(job: Job, worker: String, now: Time) : Job
  requires holds?(job, worker, now)
  ensures result.state == Done and result.worker is None

  settled = Settled(number: job.number, attempt: job.attempts, worker: worker)
  var next = job
  next.state = Done
  next.attempts = settled.attempt
  next.updated_at = now
  next.worker = None
  next.lease_until = None
  next
end

# The job failed by the worker that holds it: queued again while it has attempts left, dead on
# its last.
fn failed(job: Job, worker: String, reason: String, now: Time) : Job
  requires holds?(job, worker, now)
  requires reason?(reason)
  ensures result.state == (if job.attempts < job.max_attempts: Queued else: Dead)
  ensures result.reason == Some(reason)

  settled = Settled(number: job.number, attempt: job.attempts, worker: worker)
  released(job, now, Some(reason), settled.attempt)
end

fn released(job: Job, now: Time, reason: Option(String), attempt: UInt64) : Job
  var next = job
  next.state = if attempt < job.max_attempts: Queued else: Dead
  next.attempts = attempt
  next.updated_at = now
  next.worker = None
  next.lease_until = None
  next.reason = if reason is Some(_): reason else: job.reason
  next
end

# A look at the job: a lease that has run out puts it back, queued or dead by the fail rule, and
# anything else is left as it is.
fn looked(job: Job, now: Time) : Job
  ensures !(result.state == Leased and run_out?(result, now))
  ensures result.attempts == job.attempts

  after = if job.state == Leased and run_out?(job, now)
    released(job, now, None, job.attempts)
  else
    job
  end
  look = Look(number: job.number, at: now, leased: after.state == Leased,
    until: after.lease_until or now + 1.ms)
  if look.leased: after else: after
end

fn id_of(number: UInt64) : String
  "j_#{number}"
end

# The number in an id: j_ and digits, no sign and no leading zero.
fn number_of(id: String) : Option(UInt64)
  return None if !id.starts_with?("j_") or id.byte_size < 3
  digits = id.slice(2, id.size)
  return None if digits.starts_with?("0")
  digits.to_u64
end

fn phase_name(phase: Phase) : String
  case phase
    Queued: "queued"
    Leased: "leased"
    Done: "done"
    Dead: "dead"
  end
end

fn phase_named(name: String) : Option(Phase)
  case name
    "queued": Some(Queued)
    "leased": Some(Leased)
    "done": Some(Done)
    "dead": Some(Dead)
    _: None
  end
end

# The job as JSON: the API's shape, and the line the store keeps.
fn shown(job: Job) : String
  head = "{\"id\": \"#{id_of(job.number)}\", \"queue\": #{Json.encode(job.queue)}, \"state\": \"#{phase_name(job.state)}\""
  counts = "\"payload\": #{Json.encode(job.payload)}, \"attempts\": #{job.attempts}, \"max_attempts\": #{job.max_attempts}"
  times = "\"created_at\": #{Json.encode(job.created_at)}, \"updated_at\": #{Json.encode(job.updated_at)}"
  lease = case (job.worker, job.lease_until)
    (Some(worker), Some(until)):
      ", \"worker\": #{Json.encode(worker)}, \"lease_until\": #{Json.encode(until)}"
    _: ""
  end
  why = case job.reason
    Some(reason): ", \"reason\": #{Json.encode(reason)}"
    None: ""
  end
  "#{head}, #{counts}, #{times}#{lease}#{why}}"
end

# A job read back from its JSON, or None for anything that is not one.
fn decoded(text: String) : Option(Job)
  case Json.decode(text)
    Ok(Object(fields)): from_fields(fields)
    Ok(_): None
    Error(_): None
  end
end

fn from_fields(fields: Map(String, Json)) : Option(Job)
  number = try number_of(try text_in(fields, "id"))
  queue = try text_in(fields, "queue")
  state = try phase_named(try text_in(fields, "state"))
  payload = try text_in(fields, "payload")
  attempts = try count_in(fields, "attempts")
  max_attempts = try count_in(fields, "max_attempts")
  created = try Time.parse(try text_in(fields, "created_at"))
  updated = try Time.parse(try text_in(fields, "updated_at"))
  worker = text_in(fields, "worker")
  until = case text_in(fields, "lease_until")
    Some(text): Some(try Time.parse(text))
    None: None
  end
  return None if !queue?(queue) or !payload?(payload) or !attempts?(max_attempts)
  return None if attempts > max_attempts or (state == Leased) != (worker is Some(_) and until is Some(_))
  Some(Job(number: number, queue: queue, state: state, payload: payload, attempts: attempts,
    max_attempts: max_attempts, created_at: created, updated_at: updated, worker: worker,
    lease_until: until, reason: text_in(fields, "reason")))
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
  whole = try value.to_i64
  whole.checked_to_u64
end

fn at(text: String) : Time
  Time.parse(text) or Time.from_parts(2026, 1, 1, 0, 0, 0)
end

fn sample() : Job
  job(7, "emails", "hello \"there\"\nsecond line é", 3, at("2026-09-14T10:00:00Z"))
end

test "a new job is queued with no attempts, and its JSON is the API's shape"
  made = sample()
  assert made.state == Queued and made.attempts == 0
  assert shown(made) == "{\"id\": \"j_7\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"hello \\\"there\\\"\\nsecond line é\", \"attempts\": 0, \"max_attempts\": 3, \"created_at\": \"2026-09-14T10:00:00Z\", \"updated_at\": \"2026-09-14T10:00:00Z\"}"
  assert decoded(shown(made)) == Some(made)
end

test "a lease names its worker and its end, and a fail keeps its reason"
  now = at("2026-09-14T10:00:00Z")
  held = leased(sample(), "w-1", 30_000, now)
  assert held.state == Leased and held.attempts == 1
  assert held.lease_until == Some(at("2026-09-14T10:00:30Z"))
  assert shown(held).ends_with?(", \"worker\": \"w-1\", \"lease_until\": \"2026-09-14T10:00:30Z\"}")
  assert decoded(shown(held)) == Some(held)
  back = failed(held, "w-1", "smtp down", now + 1_000.ms)
  assert back.state == Queued and back.worker is None and back.reason == Some("smtp down")
  assert shown(back).ends_with?(", \"reason\": \"smtp down\"}")
  assert decoded(shown(back)) == Some(back)
end

test "only the worker whose lease has not run out holds the job"
  now = at("2026-09-14T10:00:00Z")
  held = leased(sample(), "w-1", 1_000, now)
  assert holds?(held, "w-1", now + 999.ms)
  assert !holds?(held, "w-1", now + 1_000.ms)
  assert !holds?(held, "w-2", now)
  assert acked(held, "w-1", now).state == Done
end

test "a lease that runs out is queued again at the next look, and dead on its last attempt"
  now = at("2026-09-14T10:00:00Z")
  first = leased(sample(), "w-1", 100, now)
  assert looked(first, now + 99.ms) == first
  again = looked(first, now + 100.ms)
  assert again.state == Queued and again.attempts == 1 and again.worker is None
  second = leased(again, "w-2", 100, now + 200.ms)
  assert second.attempts == 2
  last = leased(looked(second, now + 300.ms), "w-3", 100, now + 400.ms)
  assert last.attempts == 3
  assert looked(last, now + 500.ms).state == Dead
  assert failed(leased(looked(second, now + 300.ms), "w-3", 100, now + 400.ms), "w-3", "",
    now + 450.ms).state == Dead
end

test "a queue name, a payload, a token, attempts, and a lease keep their rules"
  assert queue?("emails_2-a") and queue?("q".repeat(64))
  assert !queue?("") and !queue?("q".repeat(65)) and !queue?("a b") and !queue?("é")
  assert payload?("") and payload?("x".repeat(61_440)) and payload?("line\nline")
  assert !payload?("x".repeat(61_441)) and !payload?("tab\there") and !payload?("a\rb")
  assert !payload?(String.from_bytes([97, 194, 133]) or "\t")
  assert payload?("é and \u{1F600}")
  assert token?("worker-1") and token?("abc.DEF_~+/==") and !token?("") and !token?("a b")
  assert !token?("=abc") and !token?("ab=c") and !token?("k".repeat(257))
  assert attempts?(1) and attempts?(100) and !attempts?(0) and !attempts?(101)
  assert lease_ms?(100) and lease_ms?(3_600_000) and !lease_ms?(99) and !lease_ms?(3_600_001)
  assert number_of("j_12") == Some(12)
  assert number_of("j_") is None and number_of("j_012") is None and number_of("12") is None
end

test "a record that is not a job reads as none"
  assert decoded("not json") is None
  assert decoded("[1]") is None
  assert decoded("{\"id\": \"j_1\"}") is None
  held = leased(sample(), "w-1", 30_000, at("2026-09-14T10:00:00Z"))
  assert decoded(shown(held).replace(", \"worker\": \"w-1\"", "")) is None
end

test rejects "a job in a queue whose name has a space"
  job(1, "two words", "", 1, at("2026-09-14T10:00:00Z"))
end

test rejects "a job whose payload holds a tab"
  job(1, "q", "a\tb", 1, at("2026-09-14T10:00:00Z"))
end

test rejects "a job with no attempts allowed"
  job(1, "q", "", 0, at("2026-09-14T10:00:00Z"))
end

test rejects "a lease of a job that is not queued"
  now = at("2026-09-14T10:00:00Z")
  leased(leased(sample(), "w-1", 1_000, now), "w-2", 1_000, now)
end

test rejects "a lease with a token that has a space"
  leased(sample(), "w 1", 1_000, at("2026-09-14T10:00:00Z"))
end

test rejects "a lease shorter than 100 ms"
  leased(sample(), "w-1", 99, at("2026-09-14T10:00:00Z"))
end

test rejects "an ack by a worker that does not hold the lease"
  now = at("2026-09-14T10:00:00Z")
  acked(leased(sample(), "w-1", 1_000, now), "w-2", now)
end

test rejects "a fail after the lease ran out"
  now = at("2026-09-14T10:00:00Z")
  failed(leased(sample(), "w-1", 1_000, now), "w-1", "late", now + 1_000.ms)
end

test rejects "a fail whose reason is over 4 KiB"
  now = at("2026-09-14T10:00:00Z")
  failed(leased(sample(), "w-1", 1_000, now), "w-1", "x".repeat(4_097), now)
end

property "any valid job reads back from its JSON as it was, leased or not"
  for payload in any(String), queue in any(String), n in any(UInt8), ms in any(UInt32) if payload?(payload) and queue?(queue) and lease_ms?(ms.to_u64)
    tries = n.to_u64 % 100 + 1
    made = job(n.to_u64 + 1, queue, payload, tries, at("2026-09-14T10:00:00.123Z"))
    assert decoded(shown(made)) == Some(made)
    held = leased(made, "w", ms.to_u64, made.created_at)
    assert decoded(shown(held)) == Some(held)
  end
end

verified: types, contracts, tests (16), property (200 seeds), sim (not run)
          proven: not run
