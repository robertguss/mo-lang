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
  swept = swept(board, now)
  acted = acted(swept.board, call, now)
  Decision(board: acted.board, outcome: acted.outcome, writes: swept.writes.concat(acted.writes))
end

fn health_of(board: Board, now: Time) : Counts
  var counts = board.counts
  counts.uptime_ms = (now - board.started).ms
  counts
end

# The board a store's records hold: every job, the reserved numbers, and the next number above
# every job and every reservation; None when a record is not the job its key names.
fn rebuilt(entries: List((String, String)), started: Time) : Option(Board)
  reserved = try reserved_in(entries)
  found = entries.filter(fn(e) e.0 != "ids" end).map(fn(e) record_of(e) end)
  return None if found.any?(fn(f) f is None end)
  jobs = found.flat_map(fn(f) one_of(f) end).sort_by(fn(j) j.number end)
  var held = jobs.reduce(board(started, 1), fn(b, j) placed(b, None, j) end)
  top = case jobs.last
    Some(last): last.number + 1
    None: 1
  end
  next = max_of(reserved, top)
  held.next = next
  held.reserved = next
  Some(held)
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

# Every job, by number: the pages are added in number order and a page's jobs too.
fn all_jobs(board: Board) : List(Job)
  board.jobs.values.flat_map(fn(page) page.values end)
end

fn no_jobs() : List(Job)
  []
end

# The numbers the ids record reserves, 0 when there is none; None when it is not a number.
fn reserved_in(entries: List((String, String))) : Option(UInt64)
  case entries.find(fn(e) e.0 == "ids" end)
    Some(ids): ids.1.to_u64
    None: Some(0)
  end
end

# A record as its job, when the job is the one its key names.
fn record_of(entry: (String, String)) : Option(Job)
  number = try number_of(entry.0)
  held = try decoded(entry.1)
  return None if held.number != number
  Some(held)
end

fn one_of(found: Option(Job)) : List(Job)
  case found
    Some(held): [held]
    None: no_jobs()
  end
end

fn page_of(number: UInt64) : UInt64
  number / 256
end

fn job_at(board: Board, number: UInt64) : Option(Job)
  page = try board.jobs.get(page_of(number))
  page.get(number)
end

fn job_by(board: Board, id: String) : Option(Job)
  number = try number_of(id)
  job_at(board, number)
end

# Every lease that has run out put back, by number, once the earliest lease end has come.
fn swept(board: Board, now: Time) : Decision
  due = board.due or now + 1.ms
  return Decision(board: board, outcome: Empty, writes: []) if due > now
  late = board.leases.values.flat_map(fn(page) page.entries end).filter(fn(e) e.1 <= now end)
  held = late.map(fn(e) e.0 end).sort.flat_map(fn(n) one_of(job_at(board, n)) end)
  backs = held.map(fn(j) looked(j, now) end)
  var after = held.zip(backs).reduce(board, fn(b, pair) placed(b, Some(pair.0), pair.1) end)
  after.due = after.leases.values.flat_map(fn(page) page.values end).min
  Decision(board: after, outcome: Empty,
    writes: backs.map(fn(j) (id_of(j.number), Some(shown(j))) end))
end

fn acted(board: Board, call: Call, now: Time) : Decision
  case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(board, queue, payload, max_attempts, now)
    Fetch(id):
      case job_by(board, id)
        Some(held): Decision(board: board, outcome: Found(job: held), writes: [])
        None: Decision(board: board, outcome: Missing, writes: [])
      end
    Listing(queue: queue, state: phase):
      Decision(board: board, outcome: Listed(jobs: listed(board, queue, phase)), writes: [])
    Remove(id): removed(board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(board, call.worker, queue, lease_ms, now)
    Ack(id): settled(board, call.worker, id, None, now)
    Fail(id: id, reason: reason): settled(board, call.worker, id, Some(reason), now)
    Health: Decision(board: board, outcome: Healthy(counts: health_of(board, now)), writes: [])
  end
end

# A new job under the next number; when the number reaches the reserved ones, a thousand more
# are reserved and that record is written first.
fn created(board: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  number = board.next
  made = job(number, queue, payload, max_attempts, now)
  var after = placed(board, None, made)
  after.next = number + 1
  record = (id_of(number), Some(shown(made)))
  if number >= board.reserved
    after.reserved = number + 1_000
    return Decision(board: after, outcome: Made(job: made),
      writes: [("ids", Some("#{after.reserved}")), record])
  end
  Decision(board: after, outcome: Made(job: made), writes: [record])
end

fn removed(board: Board, id: String) : Decision
  case job_by(board, id)
    Some(held):
      if held.state == Leased
        return Decision(board: board, outcome: Conflict(reason: "#{id} is leased"), writes: [])
      end
      page = board.jobs.get(page_of(held.number)) or Map.new()
      var after = board
      after.jobs = after.jobs.set(page_of(held.number), page.remove(held.number))
      after.counts = counted(board.counts, held.state, false)
      Decision(board: after, outcome: Removed, writes: [(id, None)])
    None: Decision(board: board, outcome: Missing, writes: [])
  end
end

# An ack, or a fail with its reason, by the worker that holds a live lease on the job.
fn settled(board: Board, worker: String, id: String, reason: Option(String), now: Time) : Decision
  case job_by(board, id)
    Some(held):
      if !holds?(held, worker, now)
        return Decision(board: board, outcome: Conflict(reason: "#{id} is not leased to this worker"),
          writes: [])
      end
      after = case reason
        Some(why): failed(held, worker, why, now)
        None: acked(held, worker, now)
      end
      changed(board, held, after)
    None: Decision(board: board, outcome: Missing, writes: [])
  end
end

# The oldest queued job of the queue, leased to the worker: the lower number of the next fresh
# entry and the next entry queued again, once the entries whose jobs are no longer queued are
# passed over.
fn lent(board: Board, worker: String, queue: String, ms: UInt64, now: Time) : Decision
  order = board.orders.get(queue) or Order(head: 0, tail: 0, back: [], back_head: 0)
  cleared = passed_over(board, queue, order)
  pick = chosen(fresh_at(board, queue, cleared.head), cleared.back.get(cleared.back_head))
  case pick
    Some(taken):
      var moved = cleared
      if taken.1
        moved.head = cleared.head + 1
      else
        moved.back_head = cleared.back_head + 1
      end
      ordered_board = ordered(board, queue, order, moved)
      case job_at(board, taken.0)
        Some(held): changed(ordered_board, held, leased(held, worker, ms, now))
        None: Decision(board: ordered_board, outcome: Empty, writes: [])
      end
    None: Decision(board: ordered(board, queue, order, cleared), outcome: Empty, writes: [])
  end
end

# The job changed, answered with its new state and written under its id.
fn changed(board: Board, prior: Job, after: Job) : Decision
  Decision(board: placed(board, Some(prior), after), outcome: Found(job: after),
    writes: [(id_of(after.number), Some(shown(after)))])
end

fn chosen(fresh: Option(UInt64), back: Option(UInt64)) : Option((UInt64, Bool))
  case (fresh, back)
    (Some(f), Some(b)): if f < b: Some((f, true)) else: Some((b, false))
    (Some(f), None): Some((f, true))
    (None, Some(b)): Some((b, false))
    (None, None): None
  end
end

fn fresh_at(board: Board, queue: String, position: UInt64) : Option(UInt64)
  page = try board.fresh.get((queue, position / 256))
  page.get(position % 256)
end

# The order with its heads moved past the entries whose jobs are no longer queued.
fn passed_over(board: Board, queue: String, order: Order) : Order
  var cleared = order
  for i in order.head..order.tail
    if waiting?(board, fresh_at(board, queue, i))
      break
    end
    cleared.head = i + 1
  end
  for i in order.back_head..order.back.size
    if waiting?(board, order.back.get(i))
      break
    end
    cleared.back_head = i + 1
  end
  cleared
end

fn waiting?(board: Board, number: Option(UInt64)) : Bool
  case number
    Some(n):
      case job_at(board, n)
        Some(held): held.state == Queued
        None: false
      end
    None: false
  end
end

# The board with the queue's order changed: the fresh pages its head has passed dropped, and its
# back list emptied once every entry is passed. A queue with no order and no change gets none.
fn ordered(board: Board, queue: String, before: Order, after: Order) : Board
  return board if before == after
  var kept = after
  if kept.back_head >= kept.back.size
    kept.back = []
    kept.back_head = 0
  end
  var next = board
  first = before.head / 256
  last = after.head / 256
  for p in first..last
    next.fresh = next.fresh.remove((queue, p))
  end
  next.orders = next.orders.set(queue, kept)
  next
end

# The board holding the job as it is now: its page, the counts, its lease, and, when it becomes
# queued, its place in its queue's order.
fn placed(board: Board, prior: Option(Job), job: Job) : Board
  var next = board
  page = board.jobs.get(page_of(job.number)) or Map.new()
  next.jobs = next.jobs.set(page_of(job.number), page.set(job.number, job))
  var counts = board.counts
  if prior is Some(was)
    counts = counted(counts, was.state, false)
    if was.state == Leased
      next.leases = without_lease(next.leases, was.number)
    end
  end
  next.counts = counted(counts, job.state, true)
  if job.state == Leased and job.lease_until is Some(until)
    next.leases = with_lease(next.leases, job.number, until)
    next.due = Some(min_of(next.due or until, until))
  end
  if job.state == Queued
    next = if prior is Some(_): queued_back(next, job) else: queued_fresh(next, job)
  end
  next
end

fn with_lease(leases: Map(UInt64, Map(UInt64, Time)), number: UInt64, until: Time) : Map(UInt64,
  Map(UInt64, Time))
  page = leases.get(page_of(number)) or Map.new()
  leases.set(page_of(number), page.set(number, until))
end

fn without_lease(leases: Map(UInt64, Map(UInt64, Time)), number: UInt64) : Map(UInt64,
  Map(UInt64, Time))
  case leases.get(page_of(number))
    Some(page): leases.set(page_of(number), page.remove(number))
    None: leases
  end
end

fn order_of(board: Board, queue: String) : Order
  board.orders.get(queue) or Order(head: 0, tail: 0, back: [], back_head: 0)
end

# A job made, at the tail of its queue's fresh positions.
fn queued_fresh(board: Board, job: Job) : Board
  order = order_of(board, job.queue)
  key = (job.queue, order.tail / 256)
  page = board.fresh.get(key) or []
  var next = board
  next.fresh = next.fresh.set(key, page.push(job.number))
  var grown = order
  grown.tail = order.tail + 1
  next.orders = next.orders.set(job.queue, grown)
  next
end

# A job queued again, in its place by number among the entries not yet passed.
fn queued_back(board: Board, job: Job) : Board
  order = order_of(board, job.queue)
  live = order.back.drop(order.back_head)
  var grown = order
  if live.last is Some(last) and last > job.number
    grown.back = live.filter(fn(n) n < job.number end).push(job.number).concat(live.filter(fn(n)
      n > job.number
    end))
    grown.back_head = 0
  else
    grown.back = order.back.push(job.number)
  end
  var next = board
  next.orders = next.orders.set(job.queue, grown)
  next
end

fn counted(counts: Counts, phase: Phase, up: Bool) : Counts
  var next = counts
  case phase
    Queued:
      next.queued = moved(counts.queued, up)
    Leased:
      next.leased = moved(counts.leased, up)
    Done:
      next.done = moved(counts.done, up)
    Dead:
      next.dead = moved(counts.dead, up)
  end
  next
end

fn moved(n: UInt64, up: Bool) : UInt64
  if up: n + 1 else: n - 1
end

# The jobs a listing holds, by number, at most 100.
fn listed(board: Board, queue: Option(String), phase: Option(Phase)) : List(Job)
  var kept = no_jobs()
  for page in board.jobs.values
    kept = kept.concat(page.values.filter(fn(j) shows?(j, queue, phase) end))
    if kept.size >= 100
      break
    end
  end
  kept.take(100)
end

fn shows?(job: Job, queue: Option(String), phase: Option(Phase)) : Bool
  (queue is None or queue == Some(job.queue)) and (phase is None or phase == Some(job.state))
end

fn start() : Time
  Time.parse("2026-09-14T10:00:00Z") or Time.from_parts(2026, 9, 14, 10, 0, 0)
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# A board with one job made in each queue named, in order, each with two attempts.
fn with_jobs(queues: List(String)) : Board
  queues.reduce(board(start(), 1), fn(b, q)
    decide(b, call("p", Create(queue: q, payload: "job in #{q}", max_attempts: 2)), start()).board
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
