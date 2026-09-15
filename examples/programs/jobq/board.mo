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
  acted = case call.command
    Create(queue: queue, payload: payload, max_attempts: max_attempts):
      created(swept.board, queue, payload, max_attempts, now)
    Fetch(id): fetched(swept.board, id)
    Listing(queue: queue, state: state):
      Decision(board: swept.board, outcome: Listed(jobs: listed(swept.board, queue, state)),
        writes: [])
    Remove(id): removed(swept.board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(swept.board, call.worker, queue, lease_ms, now)
    Ack(id): settled(swept.board, call.worker, id, None, now)
    Fail(id: id, reason: reason): settled(swept.board, call.worker, id, Some(reason), now)
    Health:
      Decision(board: swept.board, outcome: Healthy(counts: health_of(swept.board, now)),
        writes: [])
  end
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
  var held = board(started, 1)
  var reserved = 0
  for entry in entries
    if entry.0 == "ids"
      reserved = try entry.1.to_u64
    else
      one = try decoded(entry.1)
      return None if number_of(entry.0) != Some(one.number)
      held = loaded(held, one)
    end
  end
  lined = all_jobs(held).filter(fn(j) j.state == Queued end).reduce(held, fn(b, j)
    lined_up(b, j)
  end)
  var whole = lined
  whole.next = if reserved > held.next: reserved else: held.next
  whole.reserved = if reserved > 0: reserved else: whole.next
  Some(whole)
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

# The board with no lease run out at `now`: each one run out is looked at, in number order,
# and its record written.
fn swept(board: Board, now: Time) : Decision
  case board.due
    Some(due): if due <= now: expired(board, now) else: unchanged(board)
    None: unchanged(board)
  end
end

fn unchanged(board: Board) : Decision
  Decision(board: board, outcome: Empty, writes: [])
end

fn expired(board: Board, now: Time) : Decision
  held = board.leases.values.flat_map(fn(page) page.entries end)
  run_out = held.filter(fn(e) e.1 <= now end).sort_by(fn(e) e.0 end)
  var kept = board
  kept.due = held.filter(fn(e) e.1 > now end).map(fn(e) e.1 end).min
  run_out.reduce(unchanged(kept), fn(d, e) put_back(d, e.0, now) end)
end

fn put_back(decision: Decision, number: UInt64, now: Time) : Decision
  case job_at(decision.board, number)
    Some(one):
      back = looked(one, now)
      Decision(board: changed(decision.board, one, back), outcome: decision.outcome,
        writes: decision.writes.push((id_of(number), Some(shown(back)))))
    None: decision
  end
end

fn created(board: Board, queue: String, payload: String, max_attempts: UInt64, now: Time) : Decision
  made = job(board.next, queue, payload, max_attempts, now)
  reserving = board.next >= board.reserved
  var after = lined_up(board, made)
  after.jobs = with_job(board.jobs, made)
  after.counts = counted(board.counts, Queued, true)
  after.next = board.next + 1
  after.reserved = if reserving: board.next + 1_000 else: board.reserved
  ids = if reserving: [("ids", Some("#{after.reserved}"))] else: []
  Decision(board: after, outcome: Made(job: made),
    writes: ids.push((id_of(made.number), Some(shown(made)))))
end

fn fetched(board: Board, id: String) : Decision
  case found_by(board, id)
    Some(one): Decision(board: board, outcome: Found(job: one), writes: [])
    None: Decision(board: board, outcome: Missing, writes: [])
  end
end

# At most 100 jobs, by number, in the queue and the state when either is given.
fn listed(board: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  all_jobs(board).filter(fn(j)
    (queue is None or queue == Some(j.queue)) and (state is None or state == Some(j.state))
  end).take(100)
end

# An ack, or a fail with its reason, by the worker that holds a live lease on the job.
fn settled(board: Board, worker: String, id: String, reason: Option(String), now: Time) : Decision
  case found_by(board, id)
    Some(one):
      if !holds?(one, worker, now)
        return Decision(board: board,
          outcome: Conflict(reason: "#{id_of(one.number)} is not leased to this worker"), writes: [])
      end
      after = case reason
        Some(why): failed(one, worker, why, now)
        None: acked(one, worker, now)
      end
      Decision(board: changed(board, one, after), outcome: Found(job: after),
        writes: [(id_of(one.number), Some(shown(after)))])
    None: Decision(board: board, outcome: Missing, writes: [])
  end
end

fn removed(board: Board, id: String) : Decision
  case found_by(board, id)
    Some(one):
      if one.state == Leased
        return Decision(board: board, outcome: Conflict(reason: "#{id_of(one.number)} is leased"),
          writes: [])
      end
      var after = board
      after.jobs = without_job(board.jobs, one.number)
      after.counts = counted(board.counts, one.state, false)
      Decision(board: after, outcome: Removed, writes: [(id_of(one.number), None)])
    None: Decision(board: board, outcome: Missing, writes: [])
  end
end

# The oldest queued job of the queue leased to the worker: the first live entry of its fresh
# positions or of its jobs queued again, whichever has the lower number.
fn lent(board: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  order = order_of(board, queue)
  at = fresh_from(board, queue, order)
  back_at = back_from(board, order)
  pick = chosen(fresh_at(board, queue, at), order.back.get(back_at))
  from_back = case pick
    Some(p): p.1
    None: false
  end
  var passed = order
  passed.head = if pick is Some(_) and !from_back: at + 1 else: at
  passed.back_head = if from_back: back_at + 1 else: back_at
  var after = board
  if board.orders.has?(queue)
    after.orders = board.orders.set(queue, emptied_back(passed))
    after.fresh = trimmed(board.fresh, queue, order.head, passed.head)
  end
  case pick
    Some(p): handed(after, p.0, worker, lease_ms, now)
    None: Decision(board: after, outcome: Empty, writes: [])
  end
end

fn chosen(fresh: Option(UInt64), back: Option(UInt64)) : Option((UInt64, Bool))
  case (fresh, back)
    (Some(f), Some(b)): if b < f: Some((b, true)) else: Some((f, false))
    (Some(f), None): Some((f, false))
    (None, Some(b)): Some((b, true))
    (None, None): None
  end
end

fn handed(board: Board, number: UInt64, worker: String, lease_ms: UInt64, now: Time) : Decision
  case job_at(board, number)
    Some(one):
      lease = leased(one, worker, lease_ms, now)
      Decision(board: changed(board, one, lease), outcome: Found(job: lease),
        writes: [(id_of(number), Some(shown(lease)))])
    None: Decision(board: board, outcome: Empty, writes: [])
  end
end

# The first fresh position from `head` whose job is still queued, or `tail`.
fn fresh_from(board: Board, queue: String, order: Order) : UInt64
  for at in order.head..order.tail
    return at if queued?(board, fresh_at(board, queue, at))
  end
  order.tail
end

fn back_from(board: Board, order: Order) : UInt64
  for at in order.back_head..order.back.size
    return at if queued?(board, order.back.get(at))
  end
  order.back.size
end

fn fresh_at(board: Board, queue: String, at: UInt64) : Option(UInt64)
  page = try board.fresh.get((queue, at / 256))
  page.get(at % 256)
end

fn queued?(board: Board, number: Option(UInt64)) : Bool
  case number
    Some(n):
      case job_at(board, n)
        Some(one): one.state == Queued
        None: false
      end
    None: false
  end
end

fn emptied_back(order: Order) : Order
  return order if order.back_head < order.back.size
  var after = order
  after.back = []
  after.back_head = 0
  after
end

# The fresh pages every position of which is now behind the head, removed.
fn trimmed(fresh: Map((String, UInt64), List(UInt64)), queue: String, from: UInt64,
  to: UInt64) : Map((String, UInt64), List(UInt64))
  var kept = fresh
  for page in (from / 256)..(to / 256)
    kept = kept.remove((queue, page))
  end
  kept
end

# The board with a job moved from `before` to `after`: its page, the counts, its lease, and, when
# it is queued again, its place among its queue's jobs queued again.
fn changed(board: Board, before: Job, after: Job) : Board
  var next = board
  next.jobs = with_job(board.jobs, after)
  next.counts = counted(counted(board.counts, before.state, false), after.state, true)
  if before.state == Leased and after.state != Leased
    next.leases = without_lease(board.leases, after.number)
  end
  if after.state == Leased
    next.leases = with_lease(board.leases, after)
    next.due = earlier(board.due, after.lease_until)
  end
  if after.state == Queued and before.state != Queued
    next.orders = board.orders.set(after.queue,
      requeued(order_of(board, after.queue), after.number))
  end
  next
end

# A queued job placed in its queue's order: a job never leased at its next fresh position, and
# one leased before among the jobs queued again, by number.
fn lined_up(board: Board, one: Job) : Board
  order = order_of(board, one.queue)
  var after = board
  if one.attempts > 0
    after.orders = board.orders.set(one.queue, requeued(order, one.number))
    return after
  end
  key = (one.queue, order.tail / 256)
  var grown = order
  grown.tail = order.tail + 1
  after.orders = board.orders.set(one.queue, grown)
  after.fresh = board.fresh.set(key, (board.fresh.get(key) or []).push(one.number))
  after
end

fn requeued(order: Order, number: UInt64) : Order
  live = order.back.drop(order.back_head)
  var after = order
  after.back_head = 0
  after.back = if (live.last or 0) < number
    live.push(number)
  else
    live.filter(fn(n) n < number end).push(number).concat(live.filter(fn(n) n > number end))
  end
  after
end

fn order_of(board: Board, queue: String) : Order
  board.orders.get(queue) or Order(head: 0, tail: 0, back: [], back_head: 0)
end

fn counted(counts: Counts, phase: Phase, up: Bool) : Counts
  var after = counts
  case phase
    Queued:
      after.queued = if up: counts.queued + 1 else: counts.queued - 1
    Leased:
      after.leased = if up: counts.leased + 1 else: counts.leased - 1
    Done:
      after.done = if up: counts.done + 1 else: counts.done - 1
    Dead:
      after.dead = if up: counts.dead + 1 else: counts.dead - 1
  end
  after
end

fn earlier(due: Option(Time), until: Option(Time)) : Option(Time)
  case (due, until)
    (Some(a), Some(b)): if b < a: Some(b) else: Some(a)
    (Some(a), None): Some(a)
    (None, Some(b)): Some(b)
    (None, None): None
  end
end

# A job read into an empty or growing board from its record.
fn loaded(board: Board, one: Job) : Board
  var after = board
  after.jobs = with_job(board.jobs, one)
  after.counts = counted(board.counts, one.state, true)
  if one.state == Leased
    after.leases = with_lease(board.leases, one)
    after.due = earlier(board.due, one.lease_until)
  end
  after.next = if one.number >= board.next: one.number + 1 else: board.next
  after
end

fn job_at(board: Board, number: UInt64) : Option(Job)
  page = try board.jobs.get(number / 256)
  page.get(number)
end

fn found_by(board: Board, id: String) : Option(Job)
  job_at(board, try number_of(id))
end

fn with_job(jobs: Map(UInt64, Map(UInt64, Job)), one: Job) : Map(UInt64, Map(UInt64, Job))
  page = one.number / 256
  jobs.set(page, (jobs.get(page) or Map.new()).set(one.number, one))
end

fn without_job(jobs: Map(UInt64, Map(UInt64, Job)), number: UInt64) : Map(UInt64, Map(UInt64, Job))
  page = one_page(jobs, number / 256).remove(number)
  if page.size == 0: jobs.remove(number / 256) else: jobs.set(number / 256, page)
end

fn one_page(jobs: Map(UInt64, Map(UInt64, Job)), page: UInt64) : Map(UInt64, Job)
  jobs.get(page) or Map.new()
end

fn with_lease(leases: Map(UInt64, Map(UInt64, Time)), one: Job) : Map(UInt64, Map(UInt64, Time))
  page = one.number / 256
  until = one.lease_until or one.updated_at
  leases.set(page, (leases.get(page) or Map.new()).set(one.number, until))
end

fn without_lease(leases: Map(UInt64, Map(UInt64, Time)),
  number: UInt64) : Map(UInt64, Map(UInt64, Time))
  page = (leases.get(number / 256) or Map.new()).remove(number)
  if page.size == 0: leases.remove(number / 256) else: leases.set(number / 256, page)
end

# Every job, by number.
fn all_jobs(board: Board) : List(Job)
  board.jobs.keys.sort.flat_map(fn(page)
    one_page(board.jobs, page).values.sort_by(fn(j) j.number end)
  end)
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
