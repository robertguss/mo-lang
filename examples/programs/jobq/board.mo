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
    next: next, reserved: next, counts: Counts(queued: 0, leased: 0, done: 0, dead: 0, uptime_ms: 0),
    started: started)
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = expired(board, now)
  b = swept.board
  decided = case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(b, queue, payload, max_attempts, now)
    Fetch(id): fetched(b, id)
    Listing(queue: queue, state: state): nothing(b, Listed(jobs: listed(b, queue, state)))
    Remove(id): removed(b, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(b, call.worker, queue, lease_ms, now)
    Ack(id): settled(b, call.worker, id, None, now)
    Fail(id: id, reason: reason): settled(b, call.worker, id, Some(reason), now)
    Health: nothing(b, Healthy(counts: health_of(b, now)))
  end
  Decision(board: decided.board, outcome: decided.outcome,
    writes: swept.writes.concat(decided.writes))
end

fn health_of(board: Board, now: Time) : Counts
  var counts = board.counts
  counts.uptime_ms = now.since(board.started).ms
  counts
end

# The board a store's records hold: every job, the reserved numbers, and the next number above
# every job and every reservation; None when a record is not the job its key names.
fn rebuilt(entries: List((String, String)), started: Time) : Option(Board)
  var reserved = 0
  var held = no_jobs()
  for e in entries
    if e.0 == "ids"
      reserved = try e.1.to_u64
    else
      one = try decoded(e.1)
      return None if number_of(e.0) != Some(one.number)
      held = held.push(one)
    end
  end
  sorted = held.sort_by(fn(j) j.number end)
  highest = case sorted.last
    Some(last): last.number
    None: 0
  end
  var empty = board(started, max_of(max_of(highest + 1, reserved), 1))
  empty.reserved = reserved
  Some(sorted.reduce(empty, fn(b, j) placed(b, j) end))
end

# The board as the changes that write it whole: the reserved numbers, then every job's record by
# number.
fn snapshot(board: Board) : List((String, Option(String)))
  ensures result.size == all_jobs(board).size + 1

  [("ids", Some("#{board.reserved}"))].concat(all_jobs(board).map(fn(j)
    (id_of(j.number), Some(shown(j)))
  end))
end

# Every job's record, by number, as the store holds them.
fn records(board: Board) : List(String)
  all_jobs(board).map(fn(j) shown(j) end)
end

# Every job, by number.
fn all_jobs(b: Board) : List(Job)
  b.jobs.keys.sort.flat_map(fn(at) page_jobs(b, at) end)
end

# The jobs in one page of 256, by number.
fn page_jobs(b: Board, at: UInt64) : List(Job)
  (b.jobs.get(at) or Map.new()).values.sort_by(fn(j) j.number end)
end

fn no_jobs() : List(Job)
  []
end

fn no_writes() : List((String, Option(String)))
  []
end

fn no_numbers() : List(UInt64)
  []
end

fn empty_order() : Order
  Order(head: 0, tail: 0, back: [], back_head: 0)
end

fn nothing(b: Board, outcome: Outcome) : Decision
  Decision(board: b, outcome: outcome, writes: [])
end

fn job_at(b: Board, number: UInt64) : Option(Job)
  page = try b.jobs.get(number / 256)
  page.get(number)
end

# The board with the job set in its page.
fn with_job(b: Board, j: Job) : Board
  at = j.number / 256
  var after = b
  after.jobs = b.jobs.set(at, (b.jobs.get(at) or Map.new()).set(j.number, j))
  after
end

fn plus(counts: Counts, phase: Phase) : Counts
  var after = counts
  case phase
    Queued:
      after.queued = counts.queued + 1
    Leased:
      after.leased = counts.leased + 1
    Done:
      after.done = counts.done + 1
    Dead:
      after.dead = counts.dead + 1
  end
  after
end

fn minus(counts: Counts, phase: Phase) : Counts
  var after = counts
  case phase
    Queued:
      after.queued = counts.queued - 1
    Leased:
      after.leased = counts.leased - 1
    Done:
      after.done = counts.done - 1
    Dead:
      after.dead = counts.dead - 1
  end
  after
end

fn lease_set(leases: Map(UInt64, Map(UInt64, Time)), number: UInt64,
  until: Time) : Map(UInt64, Map(UInt64, Time))
  at = number / 256
  leases.set(at, (leases.get(at) or Map.new()).set(number, until))
end

fn lease_dropped(leases: Map(UInt64, Map(UInt64, Time)),
  number: UInt64) : Map(UInt64, Map(UInt64, Time))
  at = number / 256
  case leases.get(at)
    Some(page): if page.size <= 1: leases.remove(at) else: leases.set(at, page.remove(number))
    None: leases
  end
end

# A job the store held, placed on the board as it was: a queued job at the end of its queue's
# fresh positions, a leased one with its lease.
fn placed(b: Board, j: Job) : Board
  return queued_fresh(b, j) if j.state == Queued
  var after = with_job(b, j)
  after.counts = plus(b.counts, j.state)
  if j.state == Leased
    if j.lease_until is Some(until)
      after.leases = lease_set(b.leases, j.number, until)
      after.due = Some(min_of(b.due or until, until))
    end
  end
  after
end

# A queued job at its queue's next fresh position.
fn queued_fresh(b: Board, j: Job) : Board
  order = b.orders.get(j.queue) or empty_order()
  key = (j.queue, order.tail / 256)
  var grown = order
  grown.tail = order.tail + 1
  var after = with_job(b, j)
  after.fresh = b.fresh.set(key, (b.fresh.get(key) or no_numbers()).push(j.number))
  after.orders = b.orders.set(j.queue, grown)
  after.counts = plus(b.counts, Queued)
  after
end

# A job moved from one state to another: its page, the counts, its lease, and, queued again,
# its place among its queue's jobs queued again.
fn moved(b: Board, before: Job, after: Job) : Board
  var changed = with_job(b, after)
  changed.counts = plus(minus(b.counts, before.state), after.state)
  if before.state == Leased
    changed.leases = lease_dropped(b.leases, before.number)
  end
  if after.state == Leased
    if after.lease_until is Some(until)
      changed.leases = lease_set(changed.leases, after.number, until)
      changed.due = Some(min_of(b.due or until, until))
    end
  end
  if after.state == Queued and before.state != Queued
    order = b.orders.get(after.queue) or empty_order()
    changed.orders = b.orders.set(after.queue, back_with(order, after.number))
  end
  changed
end

# A number joins the jobs queued again, kept by number.
fn back_with(order: Order, number: UInt64) : Order
  var after = order
  if order.back.size > order.back_head and number < (order.back.last or 0)
    after.back = order.back.drop(order.back_head).push(number).sort
    after.back_head = 0
    return after
  end
  after.back = order.back.push(number)
  after
end

# Every decision's first step: when a lease may have run out, each lease that has is put back,
# queued or dead, by number, with its record.
fn expired(b: Board, now: Time) : Decision
  case b.due
    Some(at): if at <= now: released(b, now) else: nothing(b, Empty)
    None: nothing(b, Empty)
  end
end

fn released(b: Board, now: Time) : Decision
  ends = b.leases.values.flat_map(fn(page) page.entries end).sort_by(fn(e) e.0 end)
  start_of = Decision(board: b, outcome: Empty, writes: no_writes())
  var swept = ends.filter(fn(e) e.1 <= now end).reduce(start_of, fn(d, e) put_back(d, e.0, now) end)
  swept.board.due = ends.filter(fn(e) e.1 > now end).map(fn(e) e.1 end).min
  swept
end

# A lease that ran out put back by a look, with the job's record.
fn put_back(d: Decision, number: UInt64, now: Time) : Decision
  case job_at(d.board, number)
    Some(held):
      returned = looked(held, now)
      Decision(board: moved(d.board, held, returned), outcome: d.outcome,
        writes: d.writes.push((id_of(number), Some(shown(returned)))))
    None: d
  end
end

fn created(b: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  made = job(b.next, queue, payload, max_attempts, now)
  record = (id_of(made.number), Some(shown(made)))
  var after = queued_fresh(b, made)
  after.next = b.next + 1
  if b.next < b.reserved
    return Decision(board: after, outcome: Made(job: made), writes: [record])
  end
  after.reserved = b.next + 1_000
  Decision(board: after, outcome: Made(job: made),
    writes: [("ids", Some("#{after.reserved}")), record])
end

fn fetched(b: Board, id: String) : Decision
  case job_at(b, number_of(id) or 0)
    Some(one): nothing(b, Found(job: one))
    None: nothing(b, Missing)
  end
end

# A listing by number, of at most 100 jobs.
fn listed(b: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  var found = no_jobs()
  for at in b.jobs.keys.sort
    found = found.concat(page_jobs(b, at).filter(fn(j)
      (queue is None or queue == Some(j.queue)) and (state is None or state == Some(j.state))
    end))
    if found.size >= 100
      break
    end
  end
  found.take(100)
end

fn removed(b: Board, id: String) : Decision
  number = number_of(id) or 0
  case job_at(b, number)
    Some(one):
      return nothing(b, Conflict(reason: "#{id_of(number)} is leased")) if one.state == Leased
      at = number / 256
      page = b.jobs.get(at) or Map.new()
      var after = b
      after.jobs = if page.size <= 1: b.jobs.remove(at) else: b.jobs.set(at, page.remove(number))
      after.counts = minus(b.counts, one.state)
      Decision(board: after, outcome: Removed, writes: [(id_of(number), None)])
    None: nothing(b, Missing)
  end
end

# An ack, or a fail with its reason, by the worker that holds a live lease on the job.
fn settled(b: Board, worker: String, id: String, reason: Option(String), now: Time) : Decision
  number = number_of(id) or 0
  case job_at(b, number)
    Some(one):
      if !holds?(one, worker, now)
        return nothing(b, Conflict(reason: "#{id_of(number)} is not leased to this worker"))
      end
      after = case reason
        Some(why): failed(one, worker, why, now)
        None: acked(one, worker, now)
      end
      Decision(board: moved(b, one, after), outcome: Found(job: after),
        writes: [(id_of(number), Some(shown(after)))])
    None: nothing(b, Missing)
  end
end

# The first entry from `back_head` on whose job is still queued, or the end.
fn back_next(b: Board, order: Order) : UInt64
  var at = order.back.size
  for i in order.back_head..order.back.size
    if leasable?(job_at(b, order.back.get(i) or 0))
      at = i
      break
    end
  end
  at
end

# The first fresh position from `head` on whose job is still queued, or `tail`.
fn fresh_next(b: Board, queue: String, order: Order) : UInt64
  var at = order.tail
  for p in order.head..order.tail
    if leasable?(job_at(b, fresh_number(b, queue, p)))
      at = p
      break
    end
  end
  at
end

fn fresh_number(b: Board, queue: String, position: UInt64) : UInt64
  page = b.fresh.get((queue, position / 256)) or no_numbers()
  page.get(position % 256) or 0
end

fn leasable?(held: Option(Job)) : Bool
  case held
    Some(one): one.state == Queued and one.attempts < one.max_attempts
    None: false
  end
end

# The oldest queued job of the queue, by number, from its fresh positions or the jobs queued
# again, leased to the worker; the entries passed over are dropped from the queue's order.
fn lent(b: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  return nothing(b, Empty) if !b.orders.has?(queue)
  order = b.orders.get(queue) or empty_order()
  back_at = back_next(b, order)
  fresh_at = fresh_next(b, queue, order)
  from_back = order.back.get(back_at) or 0
  from_fresh = if fresh_at < order.tail: fresh_number(b, queue, fresh_at) else: 0
  take_back = from_back > 0 and (from_fresh == 0 or from_back < from_fresh)
  var passed = order
  passed.back_head = if take_back: back_at + 1 else: back_at
  passed.head = if !take_back and from_fresh > 0: fresh_at + 1 else: fresh_at
  kept = ordered(b, queue, order, passed)
  number = if take_back: from_back else: from_fresh
  case job_at(kept, number)
    Some(one):
      after = leased(one, worker, lease_ms, now)
      Decision(board: moved(kept, one, after), outcome: Found(job: after),
        writes: [(id_of(number), Some(shown(after)))])
    None: nothing(kept, Empty)
  end
end

# The board with the queue's order moved on: fresh pages passed are dropped, and the jobs queued
# again are cut to the ones from `back_head` on once most are behind it.
fn ordered(b: Board, queue: String, before: Order, after: Order) : Board
  return b if after == before
  var order = after
  if after.back_head >= 256 and after.back_head * 2 >= after.back.size
    order.back = after.back.drop(after.back_head)
    order.back_head = 0
  end
  first_page = before.head / 256
  last_page = after.head / 256
  var kept = b
  kept.fresh = (first_page..last_page).reduce(b.fresh, fn(fresh, p) fresh.remove((queue, p)) end)
  kept.orders = b.orders.set(queue, order)
  kept
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
    Some(one): one.number
    None: 0
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
