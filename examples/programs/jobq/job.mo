module Jobq.Job
expose Phase, Job, Making, Settled, Look, Woken, Retried, Handed, job, archived, leased, acked, failed, retried, handed_off, looked, holds?, worker?, tagged, renames_of, run_out?, due?, queue?, key?, payload?, reason?, token?, tries?, lease_ms?, delay_ms?, backoff_ms?, id_of, number_of, phase_named, phase_name, shown, decoded, rule_broken, archive_broken, to_ms

intent "A job and its rules: a queue's name, a payload, tries, a backoff, a lease, and a time to run at; each move between the five states as a function whose contracts say what it leaves; and the one line of JSON a job is kept as, which is also what the API shows, read back from the names the previous version wrote as well."

never "a job's tries exceed its max_tries"
  for j in Job.all
    j.tries > j.max_tries
  end
end

never "a job is held by two workers at once"
  for a in Settled.all, b in Settled.all if a.number == b.number and a.tries == b.tries and a.at == b.at
    a.worker != b.worker
  end
end

never "a lease that ran out, or a run_at that passed, still holds its job after a look"
  for l in Look.all
    (l.leased and l.until <= l.at) or (l.scheduled and l.run_at <= l.at)
  end
end

# Only a queued job is leased, so a scheduled job is leased before its run_at only if it is queued
# before it.
never "a scheduled job is leased before its run_at"
  for w in Woken.all
    w.run_at > w.at
  end
end

never "a handoff changes a lease's lease_until or a job's tries, or leaves the job with no worker"
  for h in Handed.all
    h.until_before != h.until_after or h.tries_before != h.tries_after or h.worker_after is None
  end
end

never "a retry touches a job that is not dead"
  for r in Retried.all
    r.state != Dead
  end
end

enum Phase
  Queued
  Scheduled
  Leased
  Done
  Dead
end

# `worker` and `lease_until` are Some only while the job is leased, `run_at` only while it is
# scheduled; `reason` is the last fail's; `key` is the producer's idempotency key, if it gave one;
# `archived_at` is Some only for a job moved to the archive.
struct Job
  number: UInt64
  queue: String
  key: Option(String)
  state: Phase
  payload: String
  tries: UInt64
  max_tries: UInt64
  backoff_ms: UInt64
  created_at: Time
  updated_at: Time
  run_at: Option(Time)
  worker: Option(String)
  lease_until: Option(Time)
  reason: Option(String)
  archived_at: Option(Time)
end

# What a producer asks for when it makes a job: its queue, its payload, how many tries it gets,
# how long it waits after a fail, how long before it is queued at all, and the key that makes a
# second create with it answer the first job.
struct Making
  queue: String
  key: Option(String)
  payload: String
  max_tries: UInt64
  backoff_ms: UInt64
  delay_ms: UInt64
end

# A worker's ack or fail of one lease: the try it ended, and when. A retry starts a job's tries
# over, so a job and a try no longer name one lease on their own, and two tries of one job can be
# settled at one instant, so the instant does not either; one lease is the three together.
struct Settled
  number: UInt64
  tries: UInt64
  worker: String
  at: Time
end

# A look at a job: when, whether it is still leased after the look and until when, and whether
# it is still scheduled and until when.
struct Look
  number: UInt64
  at: Time
  leased: Bool
  until: Time
  scheduled: Bool
  run_at: Time
end

# A scheduled job queued at a look: when, and the run_at it had.
struct Woken
  number: UInt64
  at: Time
  run_at: Time
end

# A retry of a job, and the state the job was in.
struct Retried
  number: UInt64
  state: Phase
end

# A lease handed from one worker to another: the job's lease end and tries before and after, and
# the worker it is leased to after.
struct Handed
  number: UInt64
  until_before: Option(Time)
  until_after: Option(Time)
  tries_before: UInt64
  tries_after: UInt64
  worker_after: Option(String)
end

# A queue's name is 1 to 64 bytes of ASCII letters, digits, - and _.
fn queue?(name: String) : Bool
  size = name.byte_size
  size >= 1 and size <= 64 and name.bytes.all?(fn(b) word_byte?(b) end)
end

fn word_byte?(b: UInt8) : Bool
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45 or b == 95
end

# A key follows a queue name's rule.
fn key?(text: String) : Bool
  queue?(text)
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

# A worker named in a handoff: a token as a lease's is, and at most 128 bytes.
fn worker?(text: String) : Bool
  token?(text) and text.byte_size <= 128
end

fn tries?(n: UInt64) : Bool
  n >= 1 and n <= 100
end

fn lease_ms?(n: UInt64) : Bool
  n >= 100 and n <= 3_600_000
end

# A create's delay is up to a day.
fn delay_ms?(n: UInt64) : Bool
  n <= 86_400_000
end

# A job's backoff after a fail is up to an hour.
fn backoff_ms?(n: UInt64) : Bool
  n <= 3_600_000
end

# A time cut to whole milliseconds, as the store writes it, so a job reads back equal.
fn to_ms(at: Time) : Time
  Time.parse(at.to_iso8601) or at
end

# A new job with no tries yet: queued, or scheduled `delay_ms` from now when there is a delay.
fn job(number: UInt64, making: Making, now: Time) : Job
  requires queue?(making.queue)
  requires key?(making.key or "k")
  requires payload?(making.payload)
  requires tries?(making.max_tries)
  requires backoff_ms?(making.backoff_ms)
  requires delay_ms?(making.delay_ms)
  ensures result.tries == 0 and result.backoff_ms == making.backoff_ms and result.key == making.key
  ensures result.state == (if making.delay_ms == 0: Queued else: Scheduled)
  ensures (making.delay_ms > 0) implies (result.run_at == Some(now + making.delay_ms.to_i64.ms))

  run_at = if making.delay_ms == 0: None else: Some(now + making.delay_ms.to_i64.ms)
  Job(number: number, queue: making.queue, key: making.key,
    state: if making.delay_ms == 0: Queued else: Scheduled, payload: making.payload, tries: 0,
    max_tries: making.max_tries, backoff_ms: making.backoff_ms, created_at: now, updated_at: now,
    run_at: run_at, worker: None, lease_until: None, reason: None, archived_at: None)
end

# A done or dead job as the archive keeps it: the same record, with when it was moved.
fn archived(job: Job, now: Time) : Job
  requires job.state == Done or job.state == Dead
  ensures result.archived_at == Some(now)

  var next = job
  next.archived_at = Some(now)
  next
end

# The job leased to the worker for `lease_ms` from now, one try more.
fn leased(job: Job, worker: String, lease_ms: UInt64, now: Time) : Job
  requires job.state == Queued and job.tries < job.max_tries
  requires token?(worker)
  requires lease_ms?(lease_ms)
  ensures result.state == Leased and result.worker == Some(worker)
  ensures result.tries == job.tries + 1

  var next = job
  next.state = Leased
  next.tries = job.tries + 1
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

# A scheduled job is due at its `run_at`.
fn due?(job: Job, now: Time) : Bool
  case job.run_at
    Some(at): job.state == Scheduled and at <= now
    None: false
  end
end

# The job done by the worker that holds it.
fn acked(job: Job, worker: String, now: Time) : Job
  requires holds?(job, worker, now)
  ensures result.state == Done and result.worker is None

  settled = Settled(number: job.number, tries: job.tries, worker: worker, at: now)
  var next = job
  next.state = Done
  next.tries = settled.tries
  next.updated_at = now
  next.worker = None
  next.lease_until = None
  next
end

# The job failed by the worker that holds it: dead on its last try, and otherwise queued again,
# or scheduled `backoff_ms` from now when it has a backoff.
fn failed(job: Job, worker: String, reason: String, now: Time) : Job
  requires holds?(job, worker, now)
  requires reason?(reason)
  ensures (job.tries == job.max_tries) implies (result.state == Dead)
  ensures (job.tries < job.max_tries and job.backoff_ms == 0) implies (result.state == Queued)
  ensures (job.tries < job.max_tries and job.backoff_ms > 0) implies (result.state == Scheduled and result.run_at == Some(now + job.backoff_ms.to_i64.ms))
  ensures result.reason == Some(reason)

  settled = Settled(number: job.number, tries: job.tries, worker: worker, at: now)
  released(job, now, Some(reason), settled.tries)
end

fn released(job: Job, now: Time, reason: Option(String), tries: UInt64) : Job
  var next = job
  next.state = released_to(job, tries)
  next.tries = tries
  next.updated_at = now
  next.run_at = if next.state == Scheduled: Some(now + job.backoff_ms.to_i64.ms) else: None
  next.worker = None
  next.lease_until = None
  next.reason = if reason is Some(_): reason else: job.reason
  next
end

# Where a lease ends that did not end in an ack: dead on the last try, queued with no backoff,
# scheduled with one.
fn released_to(job: Job, tries: UInt64) : Phase
  return Dead if tries >= job.max_tries
  return Queued if job.backoff_ms == 0
  Scheduled
end

# A dead job put back in its queue: no tries, no reason, no worker; its queue, payload, max_tries,
# and backoff kept.
fn retried(job: Job, now: Time) : Job
  requires job.state == Dead
  ensures result.state == Queued and result.tries == 0
  ensures result.reason is None and result.worker is None and result.run_at is None
  ensures result.max_tries == job.max_tries and result.backoff_ms == job.backoff_ms

  kept = Retried(number: job.number, state: job.state)
  var next = job
  next.state = if kept.state == Dead: Queued else: job.state
  next.tries = 0
  next.updated_at = now
  next.run_at = None
  next.worker = None
  next.lease_until = None
  next.reason = None
  next
end

# The job's lease handed by the worker that holds it to another worker: still leased, with the same
# lease end and tries, and from now on the other worker's alone; the lease moves, it is not copied.
fn handed_off(job: Job, worker: String, to: String, now: Time) : Job
  requires holds?(job, worker, now)
  requires worker?(to)
  ensures result.state == Leased and result.worker == Some(to)
  ensures result.lease_until == job.lease_until and result.tries == job.tries
  ensures result.updated_at == now

  var next = job
  next.worker = Some(to)
  next.updated_at = now
  handed = Handed(number: job.number, until_before: job.lease_until, until_after: next.lease_until,
    tries_before: job.tries, tries_after: next.tries, worker_after: next.worker)
  if handed.worker_after is Some(_): next else: job
end

# A look at the job: a lease that has run out ends by the fail rule, a scheduled job whose run_at
# has passed is queued, and anything else is left as it is.
fn looked(job: Job, now: Time) : Job
  ensures !(result.state == Leased and run_out?(result, now))
  ensures !(result.state == Scheduled and due?(result, now))
  ensures result.tries == job.tries

  after = looked_at(job, now)
  look = Look(number: job.number, at: now, leased: after.state == Leased,
    until: after.lease_until or now + 1.ms, scheduled: after.state == Scheduled,
    run_at: after.run_at or now + 1.ms)
  if look.leased: after else: after
end

fn looked_at(job: Job, now: Time) : Job
  return released(job, now, None, job.tries) if job.state == Leased and run_out?(job, now)
  return job if !due?(job, now)
  woken = Woken(number: job.number, at: now, run_at: job.run_at or now)
  var next = job
  next.state = if woken.run_at <= woken.at: Queued else: Scheduled
  next.updated_at = now
  next.run_at = None
  next
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
    Scheduled: "scheduled"
    Leased: "leased"
    Done: "done"
    Dead: "dead"
  end
end

fn phase_named(name: String) : Option(Phase)
  case name
    "queued": Some(Queued)
    "scheduled": Some(Scheduled)
    "leased": Some(Leased)
    "done": Some(Done)
    "dead": Some(Dead)
    _: None
  end
end

# The job as JSON: the API's shape, and the line the store keeps.
fn shown(job: Job) : String
  keyed = case job.key
    Some(key): ", \"key\": #{Json.encode(key)}"
    None: ""
  end
  head = "{\"id\": \"#{id_of(job.number)}\", \"queue\": #{Json.encode(job.queue)}#{keyed}, \"state\": \"#{phase_name(job.state)}\""
  counts = "\"payload\": #{Json.encode(job.payload)}, \"tries\": #{job.tries}, \"max_tries\": #{job.max_tries}, \"backoff_ms\": #{job.backoff_ms}"
  times = "\"created_at\": #{Json.encode(job.created_at)}, \"updated_at\": #{Json.encode(job.updated_at)}"
  wait = case job.run_at
    Some(at): ", \"run_at\": #{Json.encode(at)}"
    None: ""
  end
  lease = case (job.worker, job.lease_until)
    (Some(worker), Some(until)):
      ", \"worker\": #{Json.encode(worker)}, \"lease_until\": #{Json.encode(until)}"
    _: ""
  end
  why = case job.reason
    Some(reason): ", \"reason\": #{Json.encode(reason)}"
    None: ""
  end
  moved = case job.archived_at
    Some(at): ", \"archived_at\": #{Json.encode(at)}"
    None: ""
  end
  "#{head}, #{counts}, #{times}#{wait}#{lease}#{why}#{moved}}"
end

# A record as the logs keep it: the job's JSON, and, once a queue has been renamed, how many
# renames the record already carries, so a replay applies only the renames written after it. A
# record written before any rename is the job's JSON alone.
fn tagged(record: String, renames: UInt64) : String
  return record if renames == 0 or !record.ends_with?("}")
  "#{record.slice(0, record.size - 1)}, \"renames\": #{renames}}"
end

# How many renames a record already carries: its `renames`, or 0 when it has none.
fn renames_of(record: String) : UInt64
  case Json.decode(record)
    Ok(Object(fields)): count_in(fields, "renames") or 0
    Ok(_): 0
    Error(_): 0
  end
end

# A job read back from its JSON, or None for anything that is not one. A record the previous
# version wrote reads too: `attempts` and `max_attempts` as `tries` and `max_tries`, and no
# `backoff_ms` as 0.
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
  tries = try count_named(fields, "tries", "attempts")
  max_tries = try count_named(fields, "max_tries", "max_attempts")
  backoff = if fields.has?("backoff_ms"): try count_in(fields, "backoff_ms") else: 0
  created = try Time.parse(try text_in(fields, "created_at"))
  updated = try Time.parse(try text_in(fields, "updated_at"))
  run_at = case text_in(fields, "run_at")
    Some(text): Some(try Time.parse(text))
    None: None
  end
  worker = text_in(fields, "worker")
  key = text_in(fields, "key")
  archived_at = case text_in(fields, "archived_at")
    Some(text): Some(try Time.parse(text))
    None: None
  end
  until = case text_in(fields, "lease_until")
    Some(text): Some(try Time.parse(text))
    None: None
  end
  return None if !queue?(queue) or !payload?(payload) or !tries?(max_tries) or !backoff_ms?(backoff)
  return None if tries > max_tries or (state == Leased) != (worker is Some(_) and until is Some(_))
  return None if (state == Scheduled) != (run_at is Some(_))
  return None if fields.has?("key") and !key?(key or "")
  return None if fields.has?("archived_at") and archived_at is None
  return None if archived_at is Some(_) and state != Done and state != Dead
  Some(Job(number: number, queue: queue, key: key, state: state, payload: payload, tries: tries,
    max_tries: max_tries, backoff_ms: backoff, created_at: created, updated_at: updated,
    run_at: run_at, worker: worker, lease_until: until, reason: text_in(fields, "reason"),
    archived_at: archived_at))
end

# A count under its name, or under the name the previous version wrote when the record has not
# the new one.
fn count_named(fields: Map(String, Json), name: String, old: String) : Option(UInt64)
  if fields.has?(name): count_in(fields, name) else: count_in(fields, old)
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

# The rule a record breaks, or None when it is a job the API could have produced: it decodes
# under the names this version writes or the ones the previous one wrote, its key names its id,
# and its tries fit its state. A folder is checked against this before it is served, so a record
# in a state no request could have left reaches no board.
fn rule_broken(key: String, record: String) : Option(String)
  return Some("its key is not 1 to 64 letters, digits, - or _") if key_broken?(record)
  case decoded(record)
    Some(held):
      return Some("its id is #{id_of(held.number)}, not its key") if key != id_of(held.number)
      return Some("a live job has no archived_at") if held.archived_at is Some(_)
      tries_broken(held)
    None: Some("is not a job")
  end
end

# The rule an archive record breaks: a live record's rules, except that it is done or dead and
# carries the time it was archived.
fn archive_broken(key: String, record: String) : Option(String)
  return Some("its key is not 1 to 64 letters, digits, - or _") if key_broken?(record)
  case decoded(record)
    Some(held):
      return Some("its id is #{id_of(held.number)}, not its key") if key != id_of(held.number)
      if held.state != Done and held.state != Dead
        return Some("an archived job is done or dead, not #{phase_name(held.state)}")
      end
      return Some("an archived job has an archived_at") if held.archived_at is None
      tries_broken(held)
    None: Some("is not a job")
  end
end

# Whether the record is a JSON object whose key field is there but not a key.
fn key_broken?(record: String) : Bool
  case Json.decode(record)
    Ok(Object(fields)):
      case fields.get("key")
        Some(String(text)): !key?(text)
        Some(_): true
        None: false
      end
    Ok(_): false
    Error(_): false
  end
end

# What a state says about a job's tries: a job waiting to run has a try left, and a job that has
# been handed out has taken at least one. The rest of a record's rules are `decoded`'s, which
# refuses a state without the worker, the lease, or the run_at that state keeps.
fn tries_broken(held: Job) : Option(String)
  name = phase_name(held.state)
  case held.state
    Queued | Scheduled:
      if held.tries < held.max_tries
        None
      else
        Some("a #{name} job has tries below its max_tries")
      end
    Leased | Done | Dead:
      if held.tries >= 1: None else: Some("a #{name} job has at least one try")
  end
end

fn at(text: String) : Time
  Time.parse(text) or Time.from_parts(2026, 1, 1, 0, 0, 0)
end

fn making(queue: String, payload: String, max_tries: UInt64, backoff_ms: UInt64,
  delay_ms: UInt64) : Making
  Making(queue: queue, key: None, payload: payload, max_tries: max_tries, backoff_ms: backoff_ms,
    delay_ms: delay_ms)
end

fn sample() : Job
  job(7, making("emails", "hello \"there\"\nsecond line é", 3, 0, 0), at("2026-09-14T10:00:00Z"))
end

# The sample with a backoff of a second.
fn backing() : Job
  job(8, making("emails", "retry me", 2, 1_000, 0), at("2026-09-14T10:00:00Z"))
end

test "a new job is queued with no tries, and its JSON is the API's shape"
  made = sample()
  assert made.state == Queued and made.tries == 0 and made.run_at is None
  assert shown(made) == "{\"id\": \"j_7\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"hello \\\"there\\\"\\nsecond line é\", \"tries\": 0, \"max_tries\": 3, \"backoff_ms\": 0, \"created_at\": \"2026-09-14T10:00:00Z\", \"updated_at\": \"2026-09-14T10:00:00Z\"}"
  assert decoded(shown(made)) == Some(made)
end

test "a lease names its worker and its end, and a fail keeps its reason"
  now = at("2026-09-14T10:00:00Z")
  held = leased(sample(), "w-1", 30_000, now)
  assert held.state == Leased and held.tries == 1
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

test "a lease that runs out is queued again at the next look, and dead on its last try"
  now = at("2026-09-14T10:00:00Z")
  first = leased(sample(), "w-1", 100, now)
  assert looked(first, now + 99.ms) == first
  again = looked(first, now + 100.ms)
  assert again.state == Queued and again.tries == 1 and again.worker is None
  second = leased(again, "w-2", 100, now + 200.ms)
  assert second.tries == 2
  last = leased(looked(second, now + 300.ms), "w-3", 100, now + 400.ms)
  assert last.tries == 3
  assert looked(last, now + 500.ms).state == Dead
  assert failed(leased(looked(second, now + 300.ms), "w-3", 100, now + 400.ms), "w-3", "",
    now + 450.ms).state == Dead
end

test "a job made with a delay is scheduled until its run_at, and queued at the first look after it"
  now = at("2026-09-14T10:00:00Z")
  later = job(9, making("emails", "later", 2, 0, 60_000), now)
  assert later.state == Scheduled and later.run_at == Some(at("2026-09-14T10:01:00Z"))
  assert shown(later).ends_with?("\"updated_at\": \"2026-09-14T10:00:00Z\", \"run_at\": \"2026-09-14T10:01:00Z\"}")
  assert decoded(shown(later)) == Some(later)
  assert looked(later, now + 59_999.ms) == later
  assert !due?(later, now + 59_999.ms) and due?(later, now + 60_000.ms)
  woke = looked(later, now + 60_000.ms)
  assert woke.state == Queued and woke.run_at is None and woke.tries == 0
  assert woke.updated_at == now + 60_000.ms
  assert leased(woke, "w-1", 100, now + 60_000.ms).tries == 1
end

test "a fail with backoff schedules the job at now plus the backoff, and a fail on the last try is dead"
  now = at("2026-09-14T10:00:00Z")
  first = failed(leased(backing(), "w-1", 1_000, now), "w-1", "flaky", now + 10.ms)
  assert first.state == Scheduled and first.run_at == Some(now + 1_010.ms)
  assert first.worker is None and first.lease_until is None and first.tries == 1
  assert decoded(shown(first)) == Some(first)
  assert looked(first, now + 1_009.ms).state == Scheduled
  second = leased(looked(first, now + 1_010.ms), "w-2", 1_000, now + 1_010.ms)
  assert second.tries == 2
  last = failed(second, "w-2", "flaky again", now + 1_020.ms)
  assert last.state == Dead and last.run_at is None and last.reason == Some("flaky again")
end

test "a lease that runs out with a backoff is scheduled, and without one queued"
  now = at("2026-09-14T10:00:00Z")
  with_backoff = looked(leased(backing(), "w-1", 100, now), now + 150.ms)
  assert with_backoff.state == Scheduled and with_backoff.run_at == Some(now + 1_150.ms)
  without = looked(leased(sample(), "w-1", 100, now), now + 150.ms)
  assert without.state == Queued and without.run_at is None
end

test "a retry puts a dead job back queued with no tries, no reason, and its backoff kept"
  now = at("2026-09-14T10:00:00Z")
  one_try = job(3, making("q", "p", 1, 500, 0), now)
  dead = failed(leased(one_try, "w-1", 1_000, now), "w-1", "broken", now + 1.ms)
  assert dead.state == Dead
  back = retried(dead, now + 2.ms)
  assert back.state == Queued and back.tries == 0 and back.reason is None
  assert back.backoff_ms == 500 and back.max_tries == 1 and back.updated_at == now + 2.ms
  assert shown(back) == "{\"id\": \"j_3\", \"queue\": \"q\", \"state\": \"queued\", \"payload\": \"p\", \"tries\": 0, \"max_tries\": 1, \"backoff_ms\": 500, \"created_at\": \"2026-09-14T10:00:00Z\", \"updated_at\": \"2026-09-14T10:00:00.002Z\"}"
  assert leased(back, "w-2", 1_000, now + 3.ms).tries == 1
end

test "a record the previous version wrote reads its old names as tries and max_tries, and shows only the new"
  old = "{\"id\": \"j_7\", \"queue\": \"reports\", \"state\": \"dead\", \"payload\": \"failed twice\", \"attempts\": 2, \"max_attempts\": 2, \"created_at\": \"2026-09-14T09:02:00Z\", \"updated_at\": \"2026-09-14T09:08:00Z\", \"reason\": \"disk full\"}"
  assert decoded(old) is Some(read)
  assert read.tries == 2 and read.max_tries == 2 and read.backoff_ms == 0 and read.state == Dead
  assert read.reason == Some("disk full") and read.run_at is None
  assert !shown(read).contains?("attempts") and shown(read).contains?("\"tries\": 2, \"max_tries\": 2, \"backoff_ms\": 0")
  held = "{\"id\": \"j_2\", \"queue\": \"emails\", \"state\": \"leased\", \"payload\": \"x\", \"attempts\": 1, \"max_attempts\": 2, \"created_at\": \"2026-09-14T09:01:00Z\", \"updated_at\": \"2026-09-14T09:07:00Z\", \"worker\": \"w-old\", \"lease_until\": \"2026-09-14T09:08:00Z\"}"
  assert decoded(held) is Some(lent)
  assert lent.state == Leased and lent.tries == 1 and lent.worker == Some("w-old")
  assert looked(lent, at("2026-09-15T00:00:00Z")).state == Queued
  assert decoded(old.replace("\"attempts\": 2", "\"attempts\": 3")) is None
end

test "a queue name, a payload, a token, tries, a lease, a delay, and a backoff keep their rules"
  assert queue?("emails_2-a") and queue?("q".repeat(64))
  assert !queue?("") and !queue?("q".repeat(65)) and !queue?("a b") and !queue?("é")
  assert payload?("") and payload?("x".repeat(61_440)) and payload?("line\nline")
  assert !payload?("x".repeat(61_441)) and !payload?("tab\there") and !payload?("a\rb")
  assert !payload?(String.from_bytes([97, 194, 133]) or "\t")
  assert payload?("é and \u{1F600}")
  assert token?("worker-1") and token?("abc.DEF_~+/==") and !token?("") and !token?("a b")
  assert !token?("=abc") and !token?("ab=c") and !token?("k".repeat(257))
  assert tries?(1) and tries?(100) and !tries?(0) and !tries?(101)
  assert lease_ms?(100) and lease_ms?(3_600_000) and !lease_ms?(99) and !lease_ms?(3_600_001)
  assert delay_ms?(0) and delay_ms?(86_400_000) and !delay_ms?(86_400_001)
  assert backoff_ms?(0) and backoff_ms?(3_600_000) and !backoff_ms?(3_600_001)
  assert number_of("j_12") == Some(12)
  assert number_of("j_") is None and number_of("j_012") is None and number_of("12") is None
end

test "a record that is not a job reads as none"
  assert decoded("not json") is None
  assert decoded("[1]") is None
  assert decoded("{\"id\": \"j_1\"}") is None
  held = leased(sample(), "w-1", 30_000, at("2026-09-14T10:00:00Z"))
  assert decoded(shown(held).replace(", \"worker\": \"w-1\"", "")) is None
  later = job(9, making("q", "", 1, 0, 1_000), at("2026-09-14T10:00:00Z"))
  assert decoded(shown(later).replace("\"state\": \"scheduled\"", "\"state\": \"queued\"")) is None
  assert decoded(shown(sample()).replace("\"state\": \"queued\"",
    "\"state\": \"scheduled\"")) is None
  assert decoded(shown(sample()).replace("\"backoff_ms\": 0", "\"backoff_ms\": 3600001")) is None
end

# One record per state, well-formed and then with the tries its state refuses; the states a
# record's own shape rules out (a leased job with no worker, a scheduled one with no run_at) are
# the test above's, since `decoded` refuses them.
test "a record is well-formed in each state only with the tries that state allows"
  now = at("2026-09-14T10:00:00Z")
  queued = shown(sample())
  assert rule_broken("j_7", queued) is None
  assert rule_broken("j_7",
    queued.replace("\"tries\": 0",
    "\"tries\": 3")) == Some("a queued job has tries below its max_tries")
  later = shown(job(9, making("q", "", 2, 0, 1_000), now))
  assert rule_broken("j_9", later) is None
  assert rule_broken("j_9",
    later.replace("\"tries\": 0",
    "\"tries\": 2")) == Some("a scheduled job has tries below its max_tries")
  held = shown(leased(sample(), "w-1", 1_000, now))
  assert rule_broken("j_7", held) is None
  assert rule_broken("j_7",
    held.replace("\"tries\": 1", "\"tries\": 0")) == Some("a leased job has at least one try")
  done = shown(acked(leased(sample(), "w-1", 1_000, now), "w-1", now))
  assert rule_broken("j_7", done) is None
  assert rule_broken("j_7",
    done.replace("\"tries\": 1", "\"tries\": 0")) == Some("a done job has at least one try")
  one_try = job(3, making("q", "p", 1, 0, 0), now)
  dead = shown(failed(leased(one_try, "w-1", 1_000, now), "w-1", "broken", now))
  assert rule_broken("j_3", dead) is None
  assert rule_broken("j_3",
    dead.replace("\"tries\": 1", "\"tries\": 0")) == Some("a dead job has at least one try")
end

test "a record that is not a job, or whose key is not its id, breaks the rule by name"
  assert rule_broken("j_7", "not json") == Some("is not a job")
  assert rule_broken("j_7", "{\"id\": \"j_7\"}") == Some("is not a job")
  assert rule_broken("ids", "1000") == Some("is not a job")
  assert rule_broken("j_9", shown(sample())) == Some("its id is j_7, not its key")
  old = "{\"id\": \"j_7\", \"queue\": \"reports\", \"state\": \"dead\", \"payload\": \"\", \"attempts\": 2, \"max_attempts\": 2, \"created_at\": \"2026-09-14T09:02:00Z\", \"updated_at\": \"2026-09-14T09:08:00Z\"}"
  assert rule_broken("j_7", old) is None
  assert rule_broken("j_7",
    old.replace("\"attempts\": 2", "\"attempts\": 0")) == Some("a dead job has at least one try")
end

test "a key follows the queue name's rule, is kept in the record, and reads back"
  assert key?("order-17_a") and key?("k".repeat(64))
  assert !key?("") and !key?("k".repeat(65)) and !key?("a b") and !key?("a.b")
  var keyed = making("emails", "p", 2, 0, 0)
  keyed.key = Some("order-17")
  made = job(4, keyed, at("2026-09-14T10:00:00Z"))
  assert made.key == Some("order-17")
  assert shown(made).starts_with?("{\"id\": \"j_4\", \"queue\": \"emails\", \"key\": \"order-17\", \"state\": \"queued\"")
  assert decoded(shown(made)) == Some(made)
  assert !shown(sample()).contains?("\"key\"")
  assert decoded(shown(made).replace("\"order-17\"", "\"a b\"")) is None
  assert rule_broken("j_4", shown(made)) is None
  assert rule_broken("j_4",
    shown(made).replace("\"order-17\"",
    "\"a b\"")) == Some("its key is not 1 to 64 letters, digits, - or _")
  assert rule_broken("j_4",
    shown(made).replace("\"order-17\"",
    "7")) == Some("its key is not 1 to 64 letters, digits, - or _")
end

test "an archived job carries archived_at, and only a done or dead one is a good archive record"
  now = at("2026-09-14T10:00:00Z")
  done = acked(leased(sample(), "w-1", 1_000, now), "w-1", now)
  moved = archived(done, now + 1.minute)
  assert moved.archived_at == Some(at("2026-09-14T10:01:00Z"))
  assert shown(moved).ends_with?(", \"archived_at\": \"2026-09-14T10:01:00Z\"}")
  assert decoded(shown(moved)) == Some(moved)
  assert archive_broken("j_7", shown(moved)) is None
  assert rule_broken("j_7", shown(moved)) == Some("a live job has no archived_at")
  assert archive_broken("j_7", shown(done)) == Some("an archived job has an archived_at")
  assert archive_broken("j_8", shown(moved)) == Some("its id is j_7, not its key")
  assert archive_broken("j_7", "nope") == Some("is not a job")
  queued = shown(sample()).replace("}", ", \"archived_at\": \"2026-09-14T10:01:00Z\"}")
  assert decoded(queued) is None
  assert archive_broken("j_7", queued) == Some("is not a job")
  bad = shown(moved).replace("\"tries\": 1", "\"tries\": 0")
  assert archive_broken("j_7", bad) == Some("a done job has at least one try")
end

test "a handoff moves the lease to the other worker, and keeps its lease end and tries"
  now = at("2026-09-14T10:00:00Z")
  held = leased(sample(), "w-1", 30_000, now)
  moved = handed_off(held, "w-1", "w-2", now + 5.ms)
  assert moved.state == Leased and moved.worker == Some("w-2")
  assert moved.lease_until == held.lease_until and moved.tries == held.tries
  assert moved.updated_at == now + 5.ms and moved.created_at == held.created_at
  assert !holds?(moved, "w-1", now + 5.ms) and holds?(moved, "w-2", now + 5.ms)
  assert decoded(shown(moved)) == Some(moved)
  assert acked(moved, "w-2", now + 6.ms).state == Done
  again = handed_off(moved, "w-2", "w-3", now + 7.ms)
  assert again.worker == Some("w-3") and again.lease_until == held.lease_until
  assert worker?("w".repeat(128)) and !worker?("w".repeat(129)) and !worker?("a b")
  assert !worker?("")
end

test "a record carries the renames it has seen only once there is one, and reads back the same"
  made = sample()
  assert tagged(shown(made), 0) == shown(made)
  assert tagged(shown(made),
    3).ends_with?("\"updated_at\": \"2026-09-14T10:00:00Z\", \"renames\": 3}")
  assert decoded(tagged(shown(made), 3)) == Some(made)
  assert renames_of(tagged(shown(made), 3)) == 3
  assert renames_of(shown(made)) == 0 and renames_of("nope") == 0
  assert rule_broken("j_7", tagged(shown(made), 2)) is None
end

test rejects "a handoff by a worker that does not hold the lease"
  now = at("2026-09-14T10:00:00Z")
  handed_off(leased(sample(), "w-1", 1_000, now), "w-2", "w-3", now)
end

test rejects "a handoff after the lease ran out"
  now = at("2026-09-14T10:00:00Z")
  handed_off(leased(sample(), "w-1", 1_000, now), "w-1", "w-2", now + 1_000.ms)
end

test rejects "a handoff to a worker whose name has a space"
  now = at("2026-09-14T10:00:00Z")
  handed_off(leased(sample(), "w-1", 1_000, now), "w-1", "w 2", now)
end

test rejects "an archive of a job that is still queued"
  archived(sample(), at("2026-09-14T10:00:00Z"))
end

test rejects "a job whose key has a space"
  var keyed = making("q", "", 1, 0, 0)
  keyed.key = Some("a b")
  job(1, keyed, at("2026-09-14T10:00:00Z"))
end

test rejects "a job in a queue whose name has a space"
  job(1, making("two words", "", 1, 0, 0), at("2026-09-14T10:00:00Z"))
end

test rejects "a job whose payload holds a tab"
  job(1, making("q", "a\tb", 1, 0, 0), at("2026-09-14T10:00:00Z"))
end

test rejects "a job with no tries allowed"
  job(1, making("q", "", 0, 0, 0), at("2026-09-14T10:00:00Z"))
end

test rejects "a job whose backoff is over an hour"
  job(1, making("q", "", 1, 3_600_001, 0), at("2026-09-14T10:00:00Z"))
end

test rejects "a job whose delay is over a day"
  job(1, making("q", "", 1, 0, 86_400_001), at("2026-09-14T10:00:00Z"))
end

test rejects "a lease of a job that is not queued"
  now = at("2026-09-14T10:00:00Z")
  leased(leased(sample(), "w-1", 1_000, now), "w-2", 1_000, now)
end

test rejects "a lease of a scheduled job before its run_at"
  now = at("2026-09-14T10:00:00Z")
  leased(job(1, making("q", "", 1, 0, 1_000), now), "w-1", 1_000, now)
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

test rejects "a retry of a job that is not dead"
  retried(sample(), at("2026-09-14T10:00:00Z"))
end

property "any valid job reads back from its JSON as it was, scheduled, leased, or not"
  for payload in any(String), queue in any(String), n in any(UInt8), ms in any(UInt32) if payload?(payload) and queue?(queue) and lease_ms?(ms.to_u64)
    tries = n.to_u64 % 100 + 1
    backoff = ms.to_u64 % 3_600_001
    made = job(n.to_u64 + 1, making(queue, payload, tries, backoff, 0),
      at("2026-09-14T10:00:00.123Z"))
    assert decoded(shown(made)) == Some(made)
    held = leased(made, "w", ms.to_u64, made.created_at)
    assert decoded(shown(held)) == Some(held)
    later = job(n.to_u64 + 1, making(queue, payload, tries, backoff, ms.to_u64), made.created_at)
    assert decoded(shown(later)) == Some(later)
  end
end

verified: types, contracts, tests (36), property (200 seeds), sim (not run)
          proven: not run
