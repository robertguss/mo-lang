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
    next: next, reserved: next,
    counts: Counts(queued: 0, leased: 0, done: 0, dead: 0, uptime_ms: 0), started: started)
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = expired(board, now)
  held = swept.board
  var decision = case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(held, queue, payload, max_attempts, now)
    Fetch(id): fetched(held, id)
    Listing(queue: queue, state: state): unchanged(held, Listed(jobs: listed(held, queue, state)))
    Remove(id): removed(held, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(held, call.worker, queue, lease_ms, now)
    Ack(id): settled(held, call.worker, id, None, now)
    Fail(id: id, reason: reason): settled(held, call.worker, id, Some(reason), now)
    Health: unchanged(held, Healthy(counts: health_of(held, now)))
  end
  decision.writes = swept.writes.concat(decision.writes)
  decision
end

fn health_of(board: Board, now: Time) : Counts
  var held = board.counts
  held.uptime_ms = (now - board.started).ms
  held
end

# The board a store's records hold: every job, the reserved numbers, and the next number above
# every job and every reservation; None when a record is not the job its key names.
fn rebuilt(entries: List((String, String)), started: Time) : Option(Board)
  reserved = try reserved_in(entries)
  kept = try jobs_of(entries.filter(fn(e) e.0 != "ids" end))
  top = case kept.last
    Some(last_job): last_job.number + 1
    None: 1
  end
  var held = board(started, [reserved, top].max or top)
  held.reserved = reserved
  held.jobs = paged_jobs(kept)
  held.counts = counted(kept)
  leased_jobs = kept.filter(fn(j) j.state == Leased end)
  held.leases = paged_leases(leased_jobs, started)
  held.due = leased_jobs.map(fn(j) j.lease_until or started end).min
  queued = kept.filter(fn(j) j.state == Queued end).group_by(fn(j) j.queue end)
  held.orders = queued.entries.reduce(held.orders, fn(orders, e)
    orders.set(e.0, Order(head: 0, tail: e.1.size, back: [], back_head: 0))
  end)
  held.fresh = queued.entries.flat_map(fn(e) pages_of(e.0, e.1) end).reduce(held.fresh,
    fn(fresh, p) fresh.set(p.0, p.1) end)
  Some(held)
end

# The board as the changes that write it whole: the reserved numbers, then every job's record by
# number.
fn snapshot(board: Board) : List((String, Option(String)))
  ensures result.size == all_jobs(board).size + 1

  ids = [board.reserved, board.next].max or board.next
  [("ids", Some("#{ids}"))].concat(all_jobs(board).map(fn(j) record_of(j) end))
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

fn unchanged(board: Board, outcome: Outcome) : Decision
  Decision(board: board, outcome: outcome, writes: [])
end

fn record_of(one: Job) : (String, Option(String))
  (id_of(one.number), Some(shown(one)))
end

fn written_of(board: Board, number: UInt64) : (String, Option(String))
  case job_at(board, number)
    Some(one): record_of(one)
    None: (id_of(number), None)
  end
end

fn job_at(board: Board, number: UInt64) : Option(Job)
  page = try board.jobs.get(number / 256)
  page.get(number)
end

# Every job on the board, by number.
fn all_jobs(board: Board) : List(Job)
  board.jobs.keys.sort.flat_map(fn(page) page_of(board, page) end)
end

fn page_of(board: Board, page: UInt64) : List(Job)
  case board.jobs.get(page)
    Some(held): held.values.sort_by(fn(j) j.number end)
    None: []
  end
end

fn order_of(board: Board, queue: String) : Order
  board.orders.get(queue) or Order(head: 0, tail: 0, back: [], back_head: 0)
end

# The job set in its page, which is copied; the map of pages is not.
fn with_job(board: Board, one: Job) : Board
  page = one.number / 256
  var moved = board
  moved.jobs = board.jobs.set(page, (board.jobs.get(page) or Map.new()).set(one.number, one))
  moved
end

fn with_lease(board: Board, number: UInt64, until: Time) : Board
  page = number / 256
  var moved = board
  moved.leases = board.leases.set(page,
    (board.leases.get(page) or Map.new()).set(number, until))
  moved.due = case board.due
    Some(due): if until < due: Some(until) else: Some(due)
    None: Some(until)
  end
  moved
end

fn lease_dropped(leases: Map(UInt64, Map(UInt64, Time)), number: UInt64) : Map(UInt64,
  Map(UInt64, Time))
  page = number / 256
  case leases.get(page)
    Some(held): if held.size == 1: leases.remove(page) else: leases.set(page, held.remove(number))
    None: leases
  end
end

fn stepped(n: UInt64, up: Bool) : UInt64
  if up: n + 1 else: n - 1
end

fn bumped(counts: Counts, phase: Phase, up: Bool) : Counts
  var after = counts
  case phase
    Queued:
      after.queued = stepped(counts.queued, up)
    Leased:
      after.leased = stepped(counts.leased, up)
    Done:
      after.done = stepped(counts.done, up)
    Dead:
      after.dead = stepped(counts.dead, up)
  end
  after
end

# The board with a job moved from one state to another: its page, the counts, its lease, and,
# when it is queued again, its place at the back of its queue.
fn changed(board: Board, before: Job, after: Job) : Board
  var moved = with_job(board, after)
  moved.counts = bumped(bumped(board.counts, before.state, false), after.state, true)
  if before.state == Leased
    moved.leases = lease_dropped(board.leases, after.number)
  end
  if after.state == Leased and after.lease_until is Some(until)
    moved = with_lease(moved, after.number, until)
  end
  if after.state == Queued and before.state != Queued
    moved.orders = board.orders.set(after.queue,
      requeued(order_of(board, after.queue), after.number))
  end
  moved
end

# A number queued again joins `back` in number order; the entries before `back_head` are
# dropped when it goes anywhere but the end.
fn requeued(order: Order, number: UInt64) : Order
  var moved = order
  if order.back_head >= order.back.size
    moved.back = [number]
    moved.back_head = 0
    return moved
  end
  if (order.back.last or 0) < number
    moved.back = order.back.push(number)
    return moved
  end
  live = order.back.drop(order.back_head)
  moved.back = live.filter(fn(n) n < number end).push(number).concat(live.filter(fn(n)
    n > number
  end))
  moved.back_head = 0
  moved
end

fn due_by?(due: Option(Time), now: Time) : Bool
  case due
    Some(at): at <= now
    None: false
  end
end

# Every lease that has run out by now put back, by number, each by a look at its job.
fn expired(board: Board, now: Time) : Decision
  return unchanged(board, Empty) if !due_by?(board.due, now)
  ends = board.leases.values.flat_map(fn(page) page.entries end)
  numbers = ends.filter(fn(e) e.1 <= now end).map(fn(e) e.0 end).sort
  swept = numbers.reduce(board, fn(b, n) put_back(b, n, now) end)
  var after = swept
  after.due = ends.filter(fn(e) e.1 > now end).map(fn(e) e.1 end).min
  Decision(board: after, outcome: Empty, writes: numbers.map(fn(n) written_of(swept, n) end))
end

fn put_back(board: Board, number: UInt64, now: Time) : Board
  case job_at(board, number)
    Some(held): changed(board, held, looked(held, now))
    None: board
  end
end

fn created(board: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  made = job(board.next, queue, payload, max_attempts, now)
  var moved = fresh_added(with_job(board, made), made)
  moved.counts = bumped(board.counts, Queued, true)
  moved.next = board.next + 1
  moved.reserved = if board.next >= board.reserved: board.next + 1_000 else: board.reserved
  Decision(board: moved, outcome: Made(job: made), writes: reserving(board).push(record_of(made)))
end

# The numbers the log must hold before the next one is handed out: a thousand more whenever the
# reserved ones run out.
fn reserving(board: Board) : List((String, Option(String)))
  return [] if board.next < board.reserved
  [("ids", Some("#{board.next + 1_000}"))]
end

fn positions(board: Board, queue: String, page: UInt64) : List(UInt64)
  case board.fresh.get((queue, page))
    Some(numbers): numbers
    None: []
  end
end

fn fresh_at(board: Board, queue: String, position: UInt64) : UInt64
  positions(board, queue, position / 256).get(position % 256) or 0
end

fn fresh_added(board: Board, one: Job) : Board
  order = order_of(board, one.queue)
  page = order.tail / 256
  var kept = order
  kept.tail = order.tail + 1
  var moved = board
  moved.orders = board.orders.set(one.queue, kept)
  moved.fresh = board.fresh.set((one.queue, page),
    positions(board, one.queue, page).push(one.number))
  moved
end

fn fetched(board: Board, id: String) : Decision
  case job_at(board, number_of(id) or 0)
    Some(held): unchanged(board, Found(job: held))
    None: unchanged(board, Missing)
  end
end

fn removed(board: Board, id: String) : Decision
  number = number_of(id) or 0
  case job_at(board, number)
    Some(held):
      return unchanged(board, Conflict(reason: "#{id} is leased")) if held.state == Leased
      page = number / 256
      var moved = board
      moved.jobs = board.jobs.set(page, (board.jobs.get(page) or Map.new()).remove(number))
      moved.counts = bumped(board.counts, held.state, false)
      Decision(board: moved, outcome: Removed, writes: [(id_of(number), None)])
    None: unchanged(board, Missing)
  end
end

fn listed?(one: Job, queue: Option(String), state: Option(Phase)) : Bool
  (queue is None or queue == Some(one.queue)) and (state is None or state == Some(one.state))
end

# At most 100 jobs, by number, reading pages only until 100 are found.
fn listed(board: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  var picked = page_of(board, 0).take(0)
  for page in board.jobs.keys.sort
    picked = picked.concat(page_of(board, page).filter(fn(j) listed?(j, queue, state) end))
    if picked.size >= 100
      break
    end
  end
  picked.take(100)
end

fn settled(board: Board, worker: String, id: String, reason: Option(String), now: Time) : Decision
  case job_at(board, number_of(id) or 0)
    Some(held):
      if !holds?(held, worker, now)
        return unchanged(board, Conflict(reason: "#{id} is not leased to this worker"))
      end
      settle(board, held, worker, reason, now)
    None: unchanged(board, Missing)
  end
end

fn settle(board: Board, held: Job, worker: String, reason: Option(String), now: Time) : Decision
  case reason
    Some(why): moved_to(board, held, failed(held, worker, why, now))
    None: moved_to(board, held, acked(held, worker, now))
  end
end

fn moved_to(board: Board, before: Job, after: Job) : Decision
  Decision(board: changed(board, before, after), outcome: Found(job: after),
    writes: [record_of(after)])
end

fn leasable?(board: Board, number: UInt64) : Bool
  case job_at(board, number)
    Some(held): held.state == Queued and held.attempts < held.max_attempts
    None: false
  end
end

fn back_passed(board: Board, order: Order) : Order
  var at = order.back_head
  for i in order.back_head..order.back.size
    if leasable?(board, order.back.get(i) or 0)
      break
    end
    at = i + 1
  end
  var moved = order
  moved.back_head = at
  if at >= order.back.size
    moved.back = []
    moved.back_head = 0
  end
  moved
end

fn fresh_head(board: Board, queue: String, order: Order) : UInt64
  var at = order.head
  for p in order.head..order.tail
    if leasable?(board, fresh_at(board, queue, p))
      break
    end
    at = p + 1
  end
  at
end

# The queue's order with every entry at its heads that is no longer queued passed over, and the
# pages of fresh positions it has passed dropped.
fn passed_over(board: Board, queue: String) : Board
  order = order_of(board, queue)
  head = fresh_head(board, queue, order)
  var kept = back_passed(board, order)
  kept.head = head
  var moved = board
  moved.orders = board.orders.set(queue, kept)
  moved.fresh = (order.head / 256..head / 256).reduce(board.fresh, fn(fresh, page)
    fresh.remove((queue, page))
  end)
  moved
end

fn back_first?(from_back: Option(UInt64), from_fresh: Option(UInt64)) : Bool
  case (from_back, from_fresh)
    (Some(b), Some(f)): b < f
    (Some(_), None): true
    (None, _): false
  end
end

fn lent(board: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  return unchanged(board, Empty) if !board.orders.has?(queue)
  passed = passed_over(board, queue)
  order = order_of(passed, queue)
  from_back = order.back.get(order.back_head)
  from_fresh = if order.head < order.tail: Some(fresh_at(passed, queue, order.head)) else: None
  return unchanged(passed, Empty) if from_back is None and from_fresh is None
  use_back = back_first?(from_back, from_fresh)
  number = if use_back: (from_back or 0) else: (from_fresh or 0)
  granted(advanced(passed, queue, use_back), number, worker, lease_ms, now)
end

fn advanced(board: Board, queue: String, from_back: Bool) : Board
  order = order_of(board, queue)
  var kept = order
  if from_back
    kept.back_head = order.back_head + 1
  else
    kept.head = order.head + 1
  end
  var moved = board
  moved.orders = board.orders.set(queue, kept)
  moved
end

fn granted(board: Board, number: UInt64, worker: String, lease_ms: UInt64, now: Time) : Decision
  case job_at(board, number)
    Some(held): moved_to(board, held, leased(held, worker, lease_ms, now))
    None: unchanged(board, Empty)
  end
end

fn reserved_in(entries: List((String, String))) : Option(UInt64)
  case entries.find(fn(e) e.0 == "ids" end)
    Some(e): e.1.to_u64
    None: Some(1)
  end
end

# The jobs the records hold, by number; None when a record is not the job its key names.
fn jobs_of(entries: List((String, String))) : Option(List(Job))
  read = entries.map(fn(e) job_under(e.0, e.1) end)
  return None if read.any?(fn(j) j is None end)
  Some(read.flat_map(fn(j) present(j) end).sort_by(fn(j) j.number end))
end

fn job_under(key: String, text: String) : Option(Job)
  one = try decoded(text)
  if id_of(one.number) == key: Some(one) else: None
end

fn present(one: Option(Job)) : List(Job)
  case one
    Some(held): [held]
    None: []
  end
end

fn counted(jobs: List(Job)) : Counts
  Counts(queued: jobs.count(fn(j) j.state == Queued end),
    leased: jobs.count(fn(j) j.state == Leased end), done: jobs.count(fn(j) j.state == Done end),
    dead: jobs.count(fn(j) j.state == Dead end), uptime_ms: 0)
end

# Jobs in number order as pages, each page and each entry set once.
fn paged_jobs(jobs: List(Job)) : Map(UInt64, Map(UInt64, Job))
  jobs.group_by(fn(j) j.number / 256 end).entries.reduce(Map.new(), fn(pages, e)
    pages.set(e.0, e.1.reduce(Map.new(), fn(page, j) page.set(j.number, j) end))
  end)
end

fn paged_leases(jobs: List(Job), started: Time) : Map(UInt64, Map(UInt64, Time))
  jobs.group_by(fn(j) j.number / 256 end).entries.reduce(Map.new(), fn(pages, e)
    pages.set(e.0, e.1.reduce(Map.new(), fn(page, j)
      page.set(j.number, j.lease_until or started)
    end))
  end)
end

# A queue's queued jobs, in number order, at fresh positions from 0, in pages of 256.
fn pages_of(queue: String, jobs: List(Job)) : List(((String, UInt64), List(UInt64)))
  jobs.enumerate.group_by(fn(e) e.0 / 256 end).entries.map(fn(p)
    ((queue, p.0), p.1.map(fn(e) e.1.number end))
  end)
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
