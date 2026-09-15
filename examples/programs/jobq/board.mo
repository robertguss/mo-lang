module Jobq.Board

expose Command, Call, Outcome, Counts, Order, Board, Decision, Kept, board, decide, rebuilt, records, health_of, snapshot

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

# One queue's queued jobs, oldest first: the jobs queued when they were made hold positions
# `head` up to `tail` in the board's `fresh`, in the order they were made, and the jobs queued
# again after a lease are in `back`, by number, from `back_head` on. An entry whose job is no
# longer queued is passed over when it is reached.
struct Order
  head: UInt64
  tail: UInt64
  back: List(UInt64)
  back_head: UInt64
end

# The jobs by number, in number order, in pages of 256; each queue's order, and the jobs at its
# fresh positions, in pages of 256 positions; each leased job's lease end, in pages of 256, and
# the earliest of them, or earlier; the next number and the numbers below `reserved` the log has
# reserved; the counts; and when the queue started. Changing a map's existing entry copies the
# whole map (TOOLCHAIN-BUGS.md, bug 1), so every change copies one page and sets one entry in a
# map of pages, never a map of every job.
struct Board
  jobs: Map(UInt64, Map(UInt64, Job))
  orders: Map(String, Order)
  fresh: Map((String, UInt64), List(UInt64))
  leases: Map(UInt64, Map(UInt64, Time))
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

  Board(jobs: Map.new(), orders: Map.new(), fresh: Map.new(), leases: Map.new(), due: None,
    next: next, reserved: next, counts: Counts(queued: 0, leased: 0, done: 0, dead: 0,
    uptime_ms: 0), started: started)
end

# The board with the leases that ran out by now put back, and their records.
struct Swept
  board: Board
  writes: List((String, Option(String)))
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = swept_board(board, now)
  decided = decided_on(swept.board, call, now)
  Decision(board: decided.board, outcome: decided.outcome,
    writes: swept.writes.concat(decided.writes))
end

fn decided_on(board: Board, call: Call, now: Time) : Decision
  case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(board, queue, payload, max_attempts, now)
    Fetch(id): unchanged(board, fetched(board, id))
    Listing(queue: queue, state: state): unchanged(board, Listed(jobs: listed(board, queue, state)))
    Remove(id): removed(board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(board, call.worker, queue, lease_ms, now)
    Ack(id): settled(board, call.worker, id, None, now)
    Fail(id: id, reason: reason): settled(board, call.worker, id, Some(reason), now)
    Health: unchanged(board, Healthy(counts: health_of(board, now)))
  end
end

fn unchanged(board: Board, outcome: Outcome) : Decision
  Decision(board: board, outcome: outcome, writes: [])
end

fn record_of(held: Job) : (String, Option(String))
  (id_of(held.number), Some(shown(held)))
end

# Every lease that has run out by now put back, queued or dead by the fail rule, in number order;
# the board as it was while its earliest lease has not run out.
fn swept_board(board: Board, now: Time) : Swept
  if (board.due or now + 1.ms) > now
    return Swept(board: board, writes: [])
  end
  ran_out = board.leases.keys.sort.flat_map(fn(at) ran_out_in(board, at, now) end)
  var next = ran_out.reduce(board, fn(b, pair) changed(b, pair.0, pair.1) end)
  next.due = earliest(next)
  Swept(board: next, writes: ran_out.map(fn(pair) record_of(pair.1) end))
end

# The jobs in one page of leases whose lease has run out, by number, each beside its look.
fn ran_out_in(board: Board, at: UInt64, now: Time) : List((Job, Job))
  page = board.leases.get(at) or Map.new()
  numbers = page.entries.filter(fn(e) e.1 <= now end).map(fn(e) e.0 end).sort
  numbers.flat_map(fn(n) some_of(job_at(board, n)) end).map(fn(held)
    (held, looked(held, now))
  end)
end

# The earliest lease end on the board.
fn earliest(board: Board) : Option(Time)
  board.leases.values.flat_map(fn(page) page.values end).min
end

fn some_of(value: Option(T)) : List(T)
  case value
    Some(held): [held]
    None: []
  end
end

fn job_at(board: Board, number: UInt64) : Option(Job)
  page = try board.jobs.get(number / 256)
  page.get(number)
end

# The job an id names, when the board holds it.
fn job_of(board: Board, id: String) : Option(Job)
  job_at(board, try number_of(id))
end

fn picked(board: Board, number: Option(UInt64)) : Option(Job)
  job_at(board, try number)
end

fn with_job(board: Board, held: Job) : Board
  at = held.number / 256
  var next = board
  next.jobs = board.jobs.set(at, (board.jobs.get(at) or Map.new()).set(held.number, held))
  next
end

fn without_job(board: Board, number: UInt64) : Board
  at = number / 256
  var next = board
  next.jobs = board.jobs.set(at, (board.jobs.get(at) or Map.new()).remove(number))
  next
end

fn added(counts: Counts, phase: Phase) : Counts
  var next = counts
  case phase
    Queued:
      next.queued = counts.queued + 1
    Leased:
      next.leased = counts.leased + 1
    Done:
      next.done = counts.done + 1
    Dead:
      next.dead = counts.dead + 1
  end
  next
end

fn taken(counts: Counts, phase: Phase) : Counts
  var next = counts
  case phase
    Queued:
      next.queued = counts.queued - 1
    Leased:
      next.leased = counts.leased - 1
    Done:
      next.done = counts.done - 1
    Dead:
      next.dead = counts.dead - 1
  end
  next
end

# The board with a job moved from `before` to `after`: its page, the counts, its lease, and, when
# a lease ended with the job queued again, its place among its queue's jobs queued again.
fn changed(board: Board, before: Job, after: Job) : Board
  var next = with_job(board, after)
  next.counts = added(taken(board.counts, before.state), after.state)
  if before.state == Leased
    next.leases = without_lease(board.leases, before.number)
  end
  if after.state == Leased
    next = with_lease(next, after)
  end
  if after.state == Queued and before.state == Leased
    next = put_back(next, after)
  end
  next
end

fn without_lease(leases: Map(UInt64, Map(UInt64, Time)), number: UInt64) : Map(UInt64, Map(UInt64,
  Time))
  at = number / 256
  case leases.get(at)
    Some(page): leases.set(at, page.remove(number))
    None: leases
  end
end

fn with_lease(board: Board, held: Job) : Board
  until = held.lease_until or board.started
  at = held.number / 256
  var next = board
  next.leases = board.leases.set(at, (board.leases.get(at) or Map.new()).set(held.number, until))
  next.due = Some(min_of(board.due or until, until))
  next
end

fn no_order() : Order
  Order(head: 0, tail: 0, back: [], back_head: 0)
end

# The job at the end of its queue's fresh positions.
fn appended(board: Board, held: Job) : Board
  var order = board.orders.get(held.queue) or no_order()
  key = (held.queue, order.tail / 256)
  var next = board
  next.fresh = board.fresh.set(key, (board.fresh.get(key) or []).push(held.number))
  order.tail = order.tail + 1
  next.orders = board.orders.set(held.queue, order)
  next
end

# The job among its queue's jobs queued again, by number.
fn put_back(board: Board, held: Job) : Board
  var order = board.orders.get(held.queue) or no_order()
  waiting = order.back.drop(order.back_head)
  order.back = if (waiting.last or 0) < held.number
    waiting.push(held.number)
  else
    waiting.filter(fn(n) n < held.number end).push(held.number).concat(waiting.filter(fn(n)
      n > held.number
    end))
  end
  order.back_head = 0
  var next = board
  next.orders = board.orders.set(held.queue, order)
  next
end

fn created(board: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  made = job(board.next, queue, payload, max_attempts, now)
  reserving = board.next >= board.reserved
  var next = appended(with_job(board, made), made)
  next.counts = added(board.counts, Queued)
  next.next = board.next + 1
  next.reserved = if reserving: board.next + 1_000 else: board.reserved
  ids = [("ids", Some("#{next.reserved}"))].take(if reserving: 1 else: 0)
  Decision(board: next, outcome: Made(job: made), writes: ids.push(record_of(made)))
end

fn fetched(board: Board, id: String) : Outcome
  case job_of(board, id)
    Some(held): Found(job: held)
    None: Missing
  end
end

fn listed(board: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  all_jobs(board).filter(fn(j) (queue or j.queue) == j.queue and (state or j.state) == j.state end).take(100)
end

fn removed(board: Board, id: String) : Decision
  case job_of(board, id)
    Some(held): removed_job(board, held)
    None: unchanged(board, Missing)
  end
end

fn removed_job(board: Board, held: Job) : Decision
  if held.state == Leased
    return unchanged(board, Conflict(reason: "#{id_of(held.number)} is leased"))
  end
  var next = without_job(board, held.number)
  next.counts = taken(board.counts, held.state)
  Decision(board: next, outcome: Removed, writes: [(id_of(held.number), None)])
end

# The oldest queued job of the queue leased to the worker: the lower number of the first job still
# queued at its fresh positions and the first among its jobs queued again. Entries passed over
# stay passed.
fn lent(board: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  return unchanged(board, Empty) if !board.orders.has?(queue)
  order = board.orders.get(queue) or no_order()
  fresh_at = first_fresh(board, queue, order)
  back_at = first_back(board, order)
  from_fresh = fresh_number(board, queue, fresh_at)
  from_back = order.back.get(back_at)
  number = [from_fresh, from_back].flat_map(fn(n) some_of(n) end).min
  var passed = order
  passed.head = if number is Some(_) and from_fresh == number: fresh_at + 1 else: fresh_at
  passed.back_head = if number is Some(_) and from_back == number: back_at + 1 else: back_at
  moved = moved_on(board, queue, order, passed)
  case picked(board, number)
    Some(held):
      after = leased(held, worker, lease_ms, now)
      Decision(board: changed(moved, held, after), outcome: Found(job: after),
        writes: [record_of(after)])
    None: unchanged(moved, Empty)
  end
end

fn fresh_number(board: Board, queue: String, at: UInt64) : Option(UInt64)
  (board.fresh.get((queue, at / 256)) or []).get(at % 256)
end

fn leasable?(board: Board, number: Option(UInt64)) : Bool
  case picked(board, number)
    Some(held): held.state == Queued and held.attempts < held.max_attempts
    None: false
  end
end

# The first fresh position from `head` whose job can be leased, or `tail`.
fn first_fresh(board: Board, queue: String, order: Order) : UInt64
  for at in order.head..order.tail
    if leasable?(board, fresh_number(board, queue, at))
      return at
    end
  end
  order.tail
end

# The first place from `back_head` whose job can be leased, or the end.
fn first_back(board: Board, order: Order) : UInt64
  for at in order.back_head..order.back.size
    if leasable?(board, order.back.get(at))
      return at
    end
  end
  order.back.size
end

# The queue's order moved on: the pages of fresh positions wholly passed dropped, and the jobs
# queued again emptied once all are passed.
fn moved_on(board: Board, queue: String, before: Order, after: Order) : Board
  var order = after
  if order.back_head >= order.back.size
    order.back = []
    order.back_head = 0
  end
  var next = board
  next.orders = board.orders.set(queue, order)
  next.fresh = (before.head / 256..after.head / 256).reduce(board.fresh, fn(f, page)
    f.remove((queue, page))
  end)
  next
end

# An ack, or a fail with its reason, of the job an id names.
fn settled(board: Board, worker: String, id: String, reason: Option(String), now: Time) : Decision
  case job_of(board, id)
    Some(held): settled_job(board, worker, held, reason, now)
    None: unchanged(board, Missing)
  end
end

fn settled_job(board: Board, worker: String, held: Job, reason: Option(String), now: Time) : Decision
  if !holds?(held, worker, now)
    return unchanged(board, Conflict(reason: "#{id_of(held.number)} is not leased to this worker"))
  end
  after = case reason
    Some(why): failed(held, worker, why, now)
    None: acked(held, worker, now)
  end
  Decision(board: changed(board, held, after), outcome: Found(job: after),
    writes: [record_of(after)])
end

fn health_of(board: Board, now: Time) : Counts
  var counts = board.counts
  counts.uptime_ms = (now - board.started).ms
  counts
end

# The board a store's records hold: every job, the reserved numbers, and the next number above
# every job and every reservation; None when a record is not the job its key names.
fn rebuilt(entries: List((String, String)), started: Time) : Option(Board)
  reserved = try reserved_in(entries.filter(fn(e) e.0 == "ids" end))
  kept = entries.filter(fn(e) e.0 != "ids" end).map(fn(e) kept_job(e) end)
  return None if kept.any?(fn(k) k is None end)
  held = kept.flat_map(fn(k) some_of(k) end).sort_by(fn(j) j.number end)
  top = held.map(fn(j) j.number end).max or 0
  Some(held.reduce(board(started, max_of(max_of(reserved, 1), top + 1)), fn(b, one)
    with_restored(b, one)
  end))
end

fn reserved_in(ids: List((String, String))) : Option(UInt64)
  case ids.last
    Some(e): e.1.to_u64
    None: Some(0)
  end
end

fn kept_job(entry: (String, String)) : Option(Job)
  held = try decoded(entry.1)
  return None if id_of(held.number) != entry.0
  Some(held)
end

fn with_restored(board: Board, held: Job) : Board
  var next = with_job(board, held)
  next.counts = added(board.counts, held.state)
  if held.state == Leased
    next = with_lease(next, held)
  end
  if held.state == Queued
    next = appended(next, held)
  end
  next
end

# The board as the changes that write it whole: the reserved numbers, then every job's record by
# number.
fn snapshot(board: Board) : List((String, Option(String)))
  ensures result.size == all_jobs(board).size + 1

  ids = ("ids", Some("#{max_of(board.reserved, board.next)}"))
  [ids].concat(all_jobs(board).map(fn(j) record_of(j) end))
end

# Every job, by number.
fn all_jobs(board: Board) : List(Job)
  board.jobs.keys.sort.flat_map(fn(at) page_jobs(board, at) end)
end

fn page_jobs(board: Board, at: UInt64) : List(Job)
  page = board.jobs.get(at) or Map.new()
  page.entries.sort_by(fn(e) e.0 end).map(fn(e) e.1 end)
end

# Every job's record, by number, as the store holds them.
fn records(board: Board) : List(String)
  all_jobs(board).map(fn(j) shown(j) end)
end

fn start() : Time
  Time.parse("2026-09-14T10:00:00Z") or Time.from_parts(2026, 9, 14, 10, 0, 0)
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# A board with one job made in each queue named, in order, each with two attempts.
fn with_jobs(queues: List(String)) : Board
  queues.reduce(board(start(), 1), fn(b, queue)
    decide(b, call("p", Create(queue: queue, payload: "", max_attempts: 2)), start()).board
  end)
end

fn number_in(decision: Decision) : UInt64
  case job_in(decision)
    Some(held): held.number
    None: 0
  end
end

fn job_in(decision: Decision) : Option(Job)
  case decision.outcome
    Made(job): Some(job)
    Found(job): Some(job)
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Unavailable(_): None
  end
end

fn lease_by(b: Board, worker: String, queue: String, ms: UInt64, now: Time) : Decision
  decide(b, call(worker, Lease(queue: queue, lease_ms: ms)), now)
end

fn store_of(b: Board) : List((String, String))
  snapshot(b).map(fn(w) (w.0, w.1 or "") end)
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

test "a board's snapshot rebuilds the same board"
  b = with_jobs(["a", "b", "a"])
  lent_one = lease_by(b, "w1", "a", 1_000, start()).board
  lines = snapshot(lent_one)
  assert lines.first == Some(("ids", Some("1001")))
  assert rebuilt(lines.map(fn(l) (l.0, l.1 or "") end), start()) is Some(again)
  assert records(again) == records(lent_one) and again.reserved == lent_one.reserved
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

verified: types, contracts, tests (10), property (200 seeds), sim (not run)
          proven: not run
