module Jobq.Board
expose Command, Call, Outcome, Counts, Order, Board, Decision, Kept, board, decide, rebuilt, records, health_of

use Jobq.Job{Phase, Job, job, leased, acked, failed, looked, holds?, payload?, id_of, number_of, shown, decoded}

intent "The queue as a value: every job by number, each queue's queued jobs oldest first, the leases and when the first runs out, and the counts; a call becomes a decision, the board after it, the answer, and the records the store must hold before the answer is sent; every decision first puts back the leases that have run out."

never "a job is lost or changed by a replay"
  for k in Kept.all
    k.after != k.before
  end
end

# What a caller asks of the queue once its request is read. `worker` is the caller's token.
enum Command
  Create(queue: String, payload: String, max_attempts: UInt64)
  Fetch(id: String)
  Listing(queue: Option(String), state: Option(Phase))
  Remove(id: String)
  Lease(queue: String, lease_ms: UInt64)
  Ack(id: String)
  Fail(id: String, reason: String)
  Health
end

struct Call
  worker: String
  command: Command
end

struct Counts
  queued: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
  uptime_ms: Int64
end

enum Outcome
  Made(job: Job)
  Found(job: Job)
  Listed(jobs: List(Job))
  Removed
  Missing
  Conflict(reason: String)
  Empty
  Healthy(counts: Counts)
  Unavailable(reason: String)
end

# One queue's queued jobs, oldest first: the jobs queued when they were made, in the order they
# were made, from `head` on, and the jobs queued again after a lease, by number, from
# `back_head` on. An entry whose job is no longer queued is passed over when it is reached.
struct Order
  fresh: List(UInt64)
  head: UInt64
  back: List(UInt64)
  back_head: UInt64
end

# The jobs by number, in number order; each queue's order; each leased job's lease end and the
# earliest of them, or earlier; the next number and the numbers below `reserved` the log has
# reserved; the counts; and when the queue started.
struct Board
  jobs: Map(UInt64, Job)
  orders: Map(String, Order)
  leases: Map(UInt64, Time)
  due: Option(Time)
  next: UInt64
  reserved: UInt64
  counts: Counts
  started: Time
end

# The board after a call, the answer to send, and the records to write first: a job's record
# under its id, None for a job removed, and the reserved numbers under `ids`.
struct Decision
  board: Board
  outcome: Outcome
  writes: List((String, Option(String)))
end

# A store's jobs before it stopped and after it was opened again, as their records.
struct Kept
  before: List(String)
  after: List(String)
end

# An empty board whose first job is numbered `next`.
fn board(started: Time, next: UInt64) : Board
  requires next >= 1

  Board(jobs: Map.new(), orders: Map.new(), leases: Map.new(), due: None, next: next,
    reserved: next, counts: Counts(queued: 0, leased: 0, done: 0, dead: 0, uptime_ms: 0),
    started: started)
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = sweep(board, now)
  decided = case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(swept.board, queue, payload, max_attempts, now)
    Fetch(id): answered(swept.board, fetched(swept.board, id))
    Listing(queue: queue, state: state):
      answered(swept.board, Listed(jobs: listed(swept.board, queue, state)))
    Remove(id): removed(swept.board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(swept.board, call.worker, queue, lease_ms, now)
    Ack(id): settled(swept.board, call.worker, id, "", false, now)
    Fail(id: id, reason: reason): settled(swept.board, call.worker, id, reason, true, now)
    Health: answered(swept.board, Healthy(counts: health_of(swept.board, now)))
  end
  Decision(board: decided.board, outcome: decided.outcome,
    writes: swept.writes.concat(decided.writes))
end

fn answered(board: Board, outcome: Outcome) : Decision
  Decision(board: board, outcome: outcome, writes: [])
end

fn health_of(board: Board, now: Time) : Counts
  var counts = board.counts
  counts.uptime_ms = (now - board.started).ms
  counts
end

# Every lease that has run out put back, queued or dead, with its record to write; nothing is
# looked at until the earliest lease end has come.
fn sweep(board: Board, now: Time) : Decision
  ensures result.board.leases.values.all?(fn(until) until > now end)

  return answered(board, Empty) if !due?(board, now)
  ran_out = board.leases.entries.filter(fn(e) e.1 <= now end).map(fn(e) e.0 end)
  after = ran_out.reduce(board, fn(so_far, n) put_back(so_far, n, now) end)
  var cleared = after
  cleared.due = after.leases.values.min
  cleared.orders = requeued(after, ran_out)
  writes = ran_out.flat_map(fn(n) record_of(after, n) end)
  Decision(board: cleared, outcome: Empty, writes: writes)
end

fn due?(board: Board, now: Time) : Bool
  case board.due
    Some(at): at <= now
    None: false
  end
end

fn put_back(board: Board, number: UInt64, now: Time) : Board
  var after = board
  after.leases = after.leases.remove(number)
  case board.jobs.get(number)
    Some(held):
      back = looked(held, now)
      after.jobs = after.jobs.set(number, back)
      after.counts = recounted(board.counts, held.state, back.state)
    None:
      after.counts = board.counts
  end
  after
end

# Each queue's order with the jobs just put back and queued added to its back, by number.
fn requeued(board: Board, numbers: List(UInt64)) : Map(String, Order)
  queued = numbers.filter(fn(n) queued_job?(board, n) end)
  groups = queued.group_by(fn(n) queue_of(board, n) end)
  groups.entries.reduce(board.orders,
    fn(orders, g) orders.set(g.0, with_back(orders.get(g.0) or no_order(), g.1)) end)
end

fn queue_of(board: Board, number: UInt64) : String
  case board.jobs.get(number)
    Some(held): held.queue
    None: ""
  end
end

fn queued_job?(board: Board, number: UInt64) : Bool
  case board.jobs.get(number)
    Some(held): held.state == Queued
    None: false
  end
end

fn no_order() : Order
  Order(fresh: [], head: 0, back: [], back_head: 0)
end

fn with_back(order: Order, numbers: List(UInt64)) : Order
  var after = order
  after.back = order.back.drop(order.back_head).concat(numbers).sort
  after.back_head = 0
  after
end

fn with_fresh(order: Order, number: UInt64) : Order
  var after = order
  after.fresh = after.fresh.push(number)
  after
end

fn record_of(board: Board, number: UInt64) : List((String, Option(String)))
  case board.jobs.get(number)
    Some(held): [(id_of(number), Some(shown(held)))]
    None: []
  end
end

fn recounted(counts: Counts, before: Phase, after: Phase) : Counts
  counted(counted(counts, after, true), before, false)
end

fn counted(counts: Counts, phase: Phase, up: Bool) : Counts
  var after = counts
  case phase
    Queued:
      after.queued = moved(counts.queued, up)
    Leased:
      after.leased = moved(counts.leased, up)
    Done:
      after.done = moved(counts.done, up)
    Dead:
      after.dead = moved(counts.dead, up)
  end
  after
end

fn moved(n: UInt64, up: Bool) : UInt64
  if up: n + 1 else: n - 1
end

# A new job, numbered next; when that number reaches the reserved ones, another thousand are
# reserved in the log first, so no number is handed out twice, restart or not.
fn created(board: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  made = job(board.next, queue, payload, max_attempts, now)
  reserving = board.next >= board.reserved
  var after = board
  after.jobs = after.jobs.set(made.number, made)
  after.orders = after.orders.set(queue,
    with_fresh(board.orders.get(queue) or no_order(), made.number))
  after.next = board.next + 1
  after.reserved = if reserving: board.next + 1_000 else: board.reserved
  after.counts = counted(board.counts, Queued, true)
  reserve = if reserving: [("ids", Some("#{board.next + 1_000}"))] else: []
  Decision(board: after, outcome: Made(job: made),
    writes: reserve.concat([(id_of(made.number), Some(shown(made)))]))
end

fn fetched(board: Board, id: String) : Outcome
  case job_at(board, id)
    Some(held): Found(job: held)
    None: Missing
  end
end

fn job_at(board: Board, id: String) : Option(Job)
  number = try number_of(id)
  board.jobs.get(number)
end

# The jobs in a queue, in a state, or both, by id, the first 100.
fn listed(board: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  ensures result.size <= 100

  board.jobs.values.filter(fn(j) wanted?(j, queue, state) end).take(100)
end

fn wanted?(held: Job, queue: Option(String), state: Option(Phase)) : Bool
  (queue is None or queue == Some(held.queue)) and (state is None or state == Some(held.state))
end

fn removed(board: Board, id: String) : Decision
  case job_at(board, id)
    Some(held):
      if held.state == Leased
        return answered(board, Conflict(reason: "#{id} is leased"))
      end
      var after = board
      after.jobs = after.jobs.remove(held.number)
      after.counts = counted(board.counts, held.state, false)
      Decision(board: after, outcome: Removed, writes: [(id, None)])
    None: answered(board, Missing)
  end
end

# The oldest queued job of the queue, leased to the worker; Empty when none is queued.
fn lent(board: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  order = board.orders.get(queue) or no_order()
  fresh_at = first_queued(board, order.fresh, order.head)
  back_at = first_queued(board, order.back, order.back_head)
  var passed = order
  passed.head = fresh_at
  passed.back_head = back_at
  case (order.fresh.get(fresh_at), order.back.get(back_at))
    (Some(f), Some(b)):
      if b < f
        passed.back_head = back_at + 1
        return handed(board, trimmed(passed), b, worker, lease_ms, now)
      end
      passed.head = fresh_at + 1
      handed(board, trimmed(passed), f, worker, lease_ms, now)
    (Some(f), None):
      passed.head = fresh_at + 1
      handed(board, trimmed(passed), f, worker, lease_ms, now)
    (None, Some(b)):
      passed.back_head = back_at + 1
      handed(board, trimmed(passed), b, worker, lease_ms, now)
    (None, None):
      var after = board
      after.orders = after.orders.set(queue, trimmed(passed))
      answered(after, Empty)
  end
end

fn handed(board: Board, order: Order, number: UInt64, worker: String, lease_ms: UInt64,
  now: Time) : Decision
  case board.jobs.get(number)
    Some(held):
      lease = leased(held, worker, lease_ms, now)
      until = lease.lease_until or now
      var after = board
      after.jobs = after.jobs.set(number, lease)
      after.orders = after.orders.set(lease.queue, order)
      after.leases = after.leases.set(number, until)
      after.due = Some(min_of(board.due or until, until))
      after.counts = recounted(board.counts, Queued, Leased)
      Decision(board: after, outcome: Found(job: lease),
        writes: [(id_of(number), Some(shown(lease)))])
    None: answered(board, Empty)
  end
end

# The position of the first entry from `from` on whose job is still queued, or the list's size;
# looked for 256 entries at a time.
fn first_queued(board: Board, numbers: List(UInt64), from: UInt64) : UInt64
  ensures result >= from or result == numbers.size

  return numbers.size if from >= numbers.size
  window = numbers.slice(from, from + 256)
  case window.enumerate.find(fn(e) queued_job?(board, e.1) end)
    Some(found): from + found.0
    None: first_queued(board, numbers, from + 256)
  end
end

# An order whose passed-over entries are dropped once they are most of it.
fn trimmed(order: Order) : Order
  var after = order
  if order.head >= 1_024 and order.head * 2 >= order.fresh.size
    after.fresh = order.fresh.drop(order.head)
    after.head = 0
  end
  if order.back_head >= 1_024 and order.back_head * 2 >= order.back.size
    after.back = order.back.drop(order.back_head)
    after.back_head = 0
  end
  after
end

# An ack or a fail by the worker that holds a live lease on the job; 409 for anyone else.
fn settled(board: Board, worker: String, id: String, reason: String, failing: Bool,
  now: Time) : Decision
  case job_at(board, id)
    Some(held):
      if !holds?(held, worker, now)
        return answered(board, Conflict(reason: "#{id} is not leased to this worker"))
      end
      after_job = if failing: failed(held, worker, reason, now) else: acked(held, worker, now)
      var after = board
      after.jobs = after.jobs.set(held.number, after_job)
      after.leases = after.leases.remove(held.number)
      after.counts = recounted(board.counts, Leased, after_job.state)
      after.orders = if after_job.state == Queued
        board.orders.set(held.queue,
          with_back(board.orders.get(held.queue) or no_order(), [held.number]))
      else
        board.orders
      end
      Decision(board: after, outcome: Found(job: after_job), writes: [(id, Some(shown(after_job)))])
    None: answered(board, Missing)
  end
end

# The board a store's records hold: every job, the reserved numbers, and the next number above
# every job and every reservation; None when a record is not the job its key names.
fn rebuilt(entries: List((String, String)), started: Time) : Option(Board)
  floor = case entries.find(fn(e) e.0 == "ids" end)
    Some(e): try e.1.to_u64
    None: 1
  end
  held = entries.filter(fn(e) e.0 != "ids" end)
  jobs = held.flat_map(fn(e) job_under(e) end)
  return None if jobs.size != held.size
  sorted = jobs.sort_by(fn(j) j.number end)
  top = case sorted.last
    Some(j): j.number
    None: 0
  end
  start = board(started, max_of(top + 1, max_of(floor, 1)))
  var built = sorted.reduce(start, fn(so_far, j) placed(so_far, j) end)
  built.reserved = max_of(floor, built.next)
  Some(built)
end

fn job_under(entry: (String, String)) : List(Job)
  case decoded(entry.1)
    Some(one) if id_of(one.number) == entry.0: [one]
    Some(_): []
    None: []
  end
end

fn placed(board: Board, held: Job) : Board
  var after = board
  after.jobs = after.jobs.set(held.number, held)
  after.counts = counted(board.counts, held.state, true)
  after.orders = if held.state == Queued
    board.orders.set(held.queue,
      with_fresh(board.orders.get(held.queue) or no_order(), held.number))
  else
    board.orders
  end
  until = held.lease_until or board.started
  after.leases = if held.state == Leased: board.leases.set(held.number, until) else: board.leases
  after.due = if held.state == Leased: Some(min_of(board.due or until, until)) else: board.due
  after
end

# Every job's record, by number, as the store holds them.
fn records(board: Board) : List(String)
  board.jobs.values.map(fn(j) shown(j) end)
end

fn at(text: String) : Time
  Time.parse(text) or Time.from_parts(2026, 1, 1, 0, 0, 0)
end

fn start() : Time
  at("2026-09-14T10:00:00Z")
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# A board with one job made in each queue named, in order, each with two attempts.
fn with_jobs(queues: List(String)) : Board
  queues.reduce(board(start(), 1),
    fn(b, q) decide(b, call("p", Create(queue: q, payload: q, max_attempts: 2)), start()).board end)
end

fn number_in(decision: Decision) : UInt64
  case decision.outcome
    Made(one): one.number
    Found(one): one.number
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Unavailable(_): 0
  end
end

fn job_in(decision: Decision) : Option(Job)
  case decision.outcome
    Made(one): Some(one)
    Found(one): Some(one)
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Unavailable(_): None
  end
end

fn lease_by(b: Board, worker: String, queue: String, ms: UInt64, now: Time) : Decision
  decide(b, call(worker, Lease(queue: queue, lease_ms: ms)), now)
end

fn store_of(b: Board) : List((String, String))
  b.jobs.values.map(fn(j) (id_of(j.number), shown(j)) end).push(("ids", "#{b.reserved}"))
end

test "a job made is found by its id, and its record is written under that id"
  first = decide(board(start(), 1),
    call("p", Create(queue: "emails", payload: "hi", max_attempts: 3)), start())
  assert number_in(first) == 1
  assert first.writes.map(fn(w) w.0 end) == ["ids", "j_1"]
  assert first.writes.get(0) == Some(("ids", Some("1001")))
  found = decide(first.board, call("p", Fetch(id: "j_1")), start())
  assert job_in(found) == job_in(first) and found.writes == []
  assert decide(first.board, call("p", Fetch(id: "j_2")), start()).outcome == Missing
  assert decide(first.board, call("p", Fetch(id: "nope")), start()).outcome == Missing
  second = decide(first.board, call("p", Create(queue: "emails", payload: "", max_attempts: 1)),
    start())
  assert second.writes.map(fn(w) w.0 end) == ["j_2"]
end

test "a lease hands out the oldest queued job of its queue, and Empty when none is queued"
  b = with_jobs(["a", "b", "a"])
  first = lease_by(b, "w1", "a", 1_000, start())
  assert number_in(first) == 1
  assert job_in(first) is Some(one)
  assert one.worker == Some("w1") and one.attempts == 1
  second = lease_by(first.board, "w2", "a", 1_000, start())
  assert number_in(second) == 3
  assert lease_by(second.board, "w3", "a", 1_000, start()).outcome == Empty
  assert lease_by(second.board, "w3", "nowhere", 1_000, start()).outcome == Empty
  failed_one = decide(second.board, call("w1", Fail(id: "j_1", reason: "smtp")), start())
  assert job_in(failed_one) is Some(back)
  assert back.state == Queued and back.reason == Some("smtp")
  newer = decide(failed_one.board, call("p", Create(queue: "a", payload: "4", max_attempts: 2)),
    start())
  again = lease_by(newer.board, "w4", "a", 1_000, start())
  assert number_in(again) == 1
  assert job_in(again) is Some(retried)
  assert retried.attempts == 2
  assert number_in(lease_by(again.board, "w5", "a", 1_000, start())) == 4
end

test "two workers race for one job: exactly one holds it, and only the holder acks it"
  b = with_jobs(["a"])
  one = lease_by(b, "w1", "a", 1_000, start())
  two = lease_by(one.board, "w2", "a", 1_000, start())
  assert number_in(one) == 1 and two.outcome == Empty
  assert decide(two.board, call("w2", Ack(id: "j_1")), start()).outcome is Conflict(_)
  done = decide(two.board, call("w1", Ack(id: "j_1")), start())
  assert job_in(done) is Some(finished)
  assert finished.state == Done
  assert decide(done.board, call("w1", Ack(id: "j_1")), start()).outcome is Conflict(_)
  assert decide(done.board, call("w1", Fail(id: "j_1", reason: "")), start()).outcome is Conflict(_)
  assert decide(done.board, call("w1", Ack(id: "j_9")), start()).outcome == Missing
  assert lease_by(done.board, "w3", "a", 1_000, start()).outcome == Empty
end

test "a lease that runs out is leased again with attempts at 2, and one that runs out on its last attempt is dead"
  b = with_jobs(["a"])
  first = lease_by(b, "w1", "a", 100, start())
  assert lease_by(first.board, "w2", "a", 100, start() + 99.ms).outcome == Empty
  second = lease_by(first.board, "w2", "a", 100, start() + 100.ms)
  assert second.writes.map(fn(w) w.0 end) == ["j_1", "j_1"]
  assert job_in(second) is Some(retried)
  assert retried.attempts == 2 and retried.worker == Some("w2")
  late = decide(second.board, call("w1", Ack(id: "j_1")), start() + 150.ms)
  assert late.outcome is Conflict(_)
  gone = decide(second.board, call("p", Fetch(id: "j_1")), start() + 200.ms)
  assert job_in(gone) is Some(dead)
  assert dead.state == Dead and dead.attempts == 2 and gone.writes.size == 1
  assert decide(gone.board, call("", Health), start() + 200.ms).outcome is Healthy(counts)
  assert counts.dead == 1 and counts.leased == 0 and counts.queued == 0
  assert lease_by(gone.board, "w3", "a", 100, start() + 300.ms).outcome == Empty
end

test "a delete takes a queued, done, or dead job, and refuses a leased one"
  b = with_jobs(["a", "a"])
  lent_one = lease_by(b, "w1", "a", 1_000, start())
  assert decide(lent_one.board, call("p", Remove(id: "j_1")), start()).outcome is Conflict(_)
  queued = decide(lent_one.board, call("p", Remove(id: "j_2")), start())
  assert queued.outcome == Removed and queued.writes == [("j_2", None)]
  assert decide(queued.board, call("p", Fetch(id: "j_2")), start()).outcome == Missing
  assert lease_by(queued.board, "w2", "a", 1_000, start()).outcome == Empty
  done = decide(queued.board, call("w1", Ack(id: "j_1")), start())
  assert decide(done.board, call("p", Remove(id: "j_1")), start()).outcome == Removed
  assert decide(done.board, call("p", Remove(id: "j_7")), start()).outcome == Missing
end

test "a listing filters by queue and by state, by id, and holds at most 100"
  b = with_jobs(["b"].concat("a".repeat(105).chars).push("b"))
  all = decide(b, call("p", Listing(queue: None, state: None)), start())
  assert all.outcome is Listed(jobs)
  assert jobs.size == 100 and (jobs.first or job(9, "q", "", 1, start())).number == 1
  assert jobs.map(fn(j) j.number end) == jobs.map(fn(j) j.number end).sort
  in_b = decide(b, call("p", Listing(queue: Some("b"), state: None)), start())
  assert in_b.outcome is Listed(bs)
  assert bs.map(fn(j) j.number end) == [1, 107]
  lent_one = lease_by(b, "w", "b", 1_000, start())
  leased_b = decide(lent_one.board, call("p", Listing(queue: Some("b"), state: Some(Leased))),
    start())
  assert leased_b.outcome is Listed(held)
  assert held.map(fn(j) j.number end) == [1]
  none = decide(lent_one.board, call("p", Listing(queue: Some("c"), state: None)), start())
  assert none.outcome == Listed(jobs: [])
end

test "a board rebuilt from its records holds the same jobs, leases, counts, and next number"
  b = with_jobs(["a", "b", "a", "a", "a", "a", "a", "a", "a", "a", "a"])
  lent_one = lease_by(b, "w1", "a", 1_000, start())
  done = decide(lease_by(lent_one.board, "w2", "a", 1_000, start()).board,
    call("w2", Ack(id: "j_3")), start())
  cut = decide(done.board, call("p", Remove(id: "j_4")), start()).board
  assert rebuilt(store_of(cut).reverse, start()) is Some(again)
  kept = Kept(before: records(cut), after: records(again))
  assert kept.after == kept.before
  assert again.next == 1_001 and again.reserved == 1_001
  assert health_of(again, start()) == health_of(cut, start())
  assert lease_by(again, "w3", "a", 1_000, start()).outcome is Found(fifth)
  assert fifth.number == 5
  expired = lease_by(again, "w3", "a", 1_000, start() + 1_000.ms)
  assert number_in(expired) == 1
  assert rebuilt([("j_1", "not a job")], start()) is None
  assert rebuilt([("j_2", records(cut).first or "")], start()) is None
  assert rebuilt([], start()) is Some(empty)
  assert empty.next == 1
end

test rejects "an empty board whose first number is 0"
  board(start(), 0)
end

property "a job made then fetched gives back any valid payload"
  for payload in any(String) if payload?(payload)
    made = decide(board(start(), 1),
      call("p", Create(queue: "q", payload: payload, max_attempts: 1)), start())
    fetched = decide(made.board, call("p", Fetch(id: "j_1")), start())
    assert job_in(fetched) is Some(back)
    assert back.payload == payload and job_in(made) == Some(back)
  end
end

verified: types, contracts, tests (9), property (200 seeds), sim (not run)
          proven: not run
