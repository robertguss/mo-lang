module Jobq.Board
expose Command, Call, Outcome, Counts, Tally, Order, Board, Decision, Kept, board, decide, rebuilt, records, health_of, tallies, ill_formed, snapshot

use Jobq.Job{Phase, Job, Making, job, leased, acked, failed, retried, looked, holds?, due?, payload?, token?, lease_ms?, id_of, number_of, shown, decoded, rule_broken}

intent "The queue as a value: every job by number, each queue's queued jobs oldest first, the leases and when the first runs out, the scheduled jobs and when the first is due, and the counts; a call becomes a decision, the board after it, the answer, and the records the store must hold before the answer is sent; every decision first puts back the leases that have run out and queues the scheduled jobs whose run_at has passed."

never "a job is lost or changed by a replay"
  for k in Kept.all
    k.after != k.before
  end
end

# What a caller asks of the queue once its request is read. `worker` is the caller's token.
enum Command
  Create(making: Making)
  Fetch(id: String)
  Listing(queue: Option(String), state: Option(Phase))
  Remove(id: String)
  Lease(queue: String, lease_ms: UInt64)
  Ack(id: String)
  Fail(id: String, reason: String)
  Retry(id: String)
  Health
  Tallying
end

struct Call
  worker: String
  command: Command
end

struct Counts
  queued: UInt64
  scheduled: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
  uptime_ms: Int64
end

# One queue's jobs by state, as /queues lists them; a queue with no job in any state has no Tally.
struct Tally
  name: String
  queued: UInt64
  scheduled: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
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
  Tallied(queues: List(Tally))
  Unavailable(reason: String)
end

# One queue's queued jobs, oldest first: the jobs queued when they were made hold positions
# `head` up to `tail` in the board's `fresh`, in the order they were made, and the jobs queued
# again after a lease, a backoff, or a retry are in `back`, by number, from `back_head` on. An
# entry whose job is no longer queued is passed over when it is reached.
struct Order
  head: UInt64
  tail: UInt64
  back: List(UInt64)
  back_head: UInt64
end

# The jobs by number, in number order, in pages of 256; each queue's order, and the jobs at its
# fresh positions, in pages of 256 positions; each leased job's lease end, in pages of 256, and
# the earliest of them, or earlier; each scheduled job's run_at the same way, and the earliest of
# them; the next number and the numbers below `reserved` the log has reserved; the counts; and
# when the queue started. Changing a map's existing entry copies the whole map (TOOLCHAIN-BUGS.md,
# bug 1), so every change copies one page and sets one entry in a map of pages, never a map of
# every job.
struct Board
  jobs: Map(UInt64, Map(UInt64, Job))
  orders: Map(String, Order)
  fresh: Map((String, UInt64), List(UInt64))
  leases: Map(UInt64, Map(UInt64, Time))
  due: Option(Time)
  waits: Map(UInt64, Map(UInt64, Time))
  wake: Option(Time)
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
    waits: Map.new(), wake: None, next: next, reserved: next,
    counts: Counts(queued: 0, scheduled: 0, leased: 0, done: 0, dead: 0, uptime_ms: 0),
    started: started)
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = sweep(board, now)
  decided = case call.command
    Create(making): created(swept.board, making, now)
    Fetch(id): answered(swept.board, fetched(swept.board, id))
    Listing(queue: queue, state: state):
      answered(swept.board, Listed(jobs: listed(swept.board, queue, state)))
    Remove(id): removed(swept.board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(swept.board, call.worker, queue, lease_ms, now)
    Ack(id): settled(swept.board, call.worker, id, "", false, now)
    Fail(id: id, reason: reason): settled(swept.board, call.worker, id, reason, true, now)
    Retry(id): revived(swept.board, id, now)
    Health: answered(swept.board, Healthy(counts: health_of(swept.board, now)))
    Tallying: answered(swept.board, Tallied(queues: tallies(swept.board)))
  end
  Decision(board: decided.board, outcome: decided.outcome,
    writes: swept.writes.concat(decided.writes))
end

fn answered(board: Board, outcome: Outcome) : Decision
  Decision(board: board, outcome: outcome, writes: [])
end

# The page of 256 a job number, or a fresh position, is kept in.
fn page_of(n: UInt64) : UInt64
  n / 256
end

fn job_of(board: Board, number: UInt64) : Option(Job)
  page = try board.jobs.get(page_of(number))
  page.get(number)
end

fn with_job(board: Board, held: Job) : Board
  at = page_of(held.number)
  var after = board
  after.jobs = after.jobs.set(at, (after.jobs.get(at) or Map.new()).set(held.number, held))
  after
end

fn without_job(board: Board, number: UInt64) : Board
  at = page_of(number)
  var after = board
  after.jobs = after.jobs.set(at, (after.jobs.get(at) or Map.new()).remove(number))
  after
end

# Every job, by number.
fn all_jobs(board: Board) : List(Job)
  board.jobs.values.flat_map(fn(page) page.values end)
end

fn with_lease(board: Board, number: UInt64, until: Time) : Board
  at = page_of(number)
  var after = board
  after.leases = after.leases.set(at, (after.leases.get(at) or Map.new()).set(number, until))
  after.due = Some(min_of(board.due or until, until))
  after
end

fn without_lease(board: Board, number: UInt64) : Board
  at = page_of(number)
  var after = board
  after.leases = after.leases.set(at, (after.leases.get(at) or Map.new()).remove(number))
  after
end

# Every leased job's number and lease end.
fn all_leases(board: Board) : List((UInt64, Time))
  board.leases.values.flat_map(fn(page) page.entries end)
end

fn with_wait(board: Board, number: UInt64, at: Time) : Board
  page = page_of(number)
  var after = board
  after.waits = after.waits.set(page, (after.waits.get(page) or Map.new()).set(number, at))
  after.wake = Some(min_of(board.wake or at, at))
  after
end

fn without_wait(board: Board, number: UInt64) : Board
  page = page_of(number)
  var after = board
  after.waits = after.waits.set(page, (after.waits.get(page) or Map.new()).remove(number))
  after
end

# Every scheduled job's number and the time it is due.
fn all_waits(board: Board) : List((UInt64, Time))
  board.waits.values.flat_map(fn(page) page.entries end)
end

# The job at a queue's fresh position, when the position's page is still kept.
fn fresh_number(board: Board, queue: String, position: UInt64) : Option(UInt64)
  page = try board.fresh.get((queue, page_of(position)))
  page.get(position % 256)
end

fn health_of(board: Board, now: Time) : Counts
  var counts = board.counts
  counts.uptime_ms = (now - board.started).ms
  counts
end

# Every queue that holds a job, by name, with its jobs by state; the counts are summed from the
# jobs themselves, so health's totals are these sums and a queue whose last job is gone is gone.
fn tallies(board: Board) : List(Tally)
  ensures result.all?(fn(t) t.queued + t.scheduled + t.leased + t.done + t.dead >= 1 end)

  groups = all_jobs(board).group_by(fn(j) j.queue end)
  groups.entries.map(fn(g) tallied(g.0, g.1) end).sort_by(fn(t) t.name end)
end

fn tallied(name: String, jobs: List(Job)) : Tally
  Tally(name: name, queued: in_state(jobs, Queued), scheduled: in_state(jobs, Scheduled),
    leased: in_state(jobs, Leased), done: in_state(jobs, Done), dead: in_state(jobs, Dead))
end

fn in_state(jobs: List(Job), phase: Phase) : UInt64
  jobs.count(fn(j) j.state == phase end)
end

# Every lease that has run out put back, queued, scheduled, or dead, and every scheduled job whose
# run_at has passed queued, with its record to write; nothing is looked at until the earliest of
# them has come.
fn sweep(board: Board, now: Time) : Decision
  ensures all_leases(result.board).all?(fn(e) e.1 > now end)
  ensures all_waits(result.board).all?(fn(e) e.1 > now end)

  return answered(board, Empty) if !looks_due?(board, now)
  ran_out = all_leases(board).filter(fn(e) e.1 <= now end).map(fn(e) e.0 end)
  woken = all_waits(board).filter(fn(e) e.1 <= now end).map(fn(e) e.0 end)
  moved = ran_out.concat(woken)
  after = moved.reduce(board, fn(so_far, n) put_back(so_far, n, now) end)
  var cleared = after
  cleared.due = all_leases(after).map(fn(e) e.1 end).min
  cleared.wake = all_waits(after).map(fn(e) e.1 end).min
  cleared.orders = requeued(after, moved)
  writes = moved.flat_map(fn(n) record_of(after, n) end)
  Decision(board: cleared, outcome: Empty, writes: writes)
end

# Whether a lease has run out or a scheduled job is due.
fn looks_due?(board: Board, now: Time) : Bool
  passed?(board.due, now) or passed?(board.wake, now)
end

fn passed?(at: Option(Time), now: Time) : Bool
  case at
    Some(when): when <= now
    None: false
  end
end

# One job looked at: a lease that ran out ends by the fail rule, and a scheduled job that is due
# is queued; it leaves the leases or the waits it was in, and joins the waits when a backoff
# schedules it.
fn put_back(board: Board, number: UInt64, now: Time) : Board
  case job_of(board, number)
    Some(held):
      back = looked(held, now)
      var after = with_job(board, back)
      after = if held.state == Leased: without_lease(after, number) else: without_wait(after,
        number)
      after = if back.state == Scheduled: with_wait(after, number, back.run_at or now) else: after
      after.counts = recounted(board.counts, held.state, back.state)
      after
    None: without_wait(without_lease(board, number), number)
  end
end

# Each queue's order with the jobs just put back and queued added to its back, by number.
fn requeued(board: Board, numbers: List(UInt64)) : Map(String, Order)
  queued = numbers.filter(fn(n) queued_job?(board, n) end)
  groups = queued.group_by(fn(n) queue_of(board, n) end)
  groups.entries.reduce(board.orders,
    fn(orders, g) orders.set(g.0, with_back(orders.get(g.0) or no_order(), g.1)) end)
end

fn queue_of(board: Board, number: UInt64) : String
  case job_of(board, number)
    Some(held): held.queue
    None: ""
  end
end

fn queued_job?(board: Board, number: UInt64) : Bool
  case job_of(board, number)
    Some(held): held.state == Queued
    None: false
  end
end

fn no_order() : Order
  Order(head: 0, tail: 0, back: [], back_head: 0)
end

fn with_back(order: Order, numbers: List(UInt64)) : Order
  var after = order
  after.back = order.back.drop(order.back_head).concat(numbers).sort
  after.back_head = 0
  after
end

# The board with a queued job taking its queue's next fresh position.
fn with_fresh(board: Board, queue: String, number: UInt64) : Board
  order = board.orders.get(queue) or no_order()
  at = (queue, page_of(order.tail))
  var after = board
  after.fresh = after.fresh.set(at, (after.fresh.get(at) or []).push(number))
  after.orders = after.orders.set(queue,
    Order(head: order.head, tail: order.tail + 1, back: order.back, back_head: order.back_head))
  after
end

fn record_of(board: Board, number: UInt64) : List((String, Option(String)))
  case job_of(board, number)
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
    Scheduled:
      after.scheduled = moved(counts.scheduled, up)
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

# A new job, numbered next: queued now, or scheduled until its run_at when it was made with a
# delay. When the number reaches the reserved ones, another thousand are reserved in the log
# first, so no number is handed out twice, restart or not.
fn created(board: Board, making: Making, now: Time) : Decision
  made = job(board.next, making, now)
  reserving = board.next >= board.reserved
  placed_now = if made.state == Queued
    with_fresh(board, made.queue, made.number)
  else
    with_wait(board, made.number, made.run_at or now)
  end
  var after = with_job(placed_now, made)
  after.next = board.next + 1
  after.reserved = if reserving: board.next + 1_000 else: board.reserved
  after.counts = counted(board.counts, made.state, true)
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
  job_of(board, number)
end

# The jobs in a queue, in a state, or both, by id, the first 100.
fn listed(board: Board, queue: Option(String), state: Option(Phase)) : List(Job)
  ensures result.size <= 100

  all_jobs(board).filter(fn(j) wanted?(j, queue, state) end).take(100)
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
      var after = without_job(board, held.number)
      after = if held.state == Scheduled: without_wait(after, held.number) else: after
      after.counts = counted(board.counts, held.state, false)
      Decision(board: after, outcome: Removed, writes: [(id, None)])
    None: answered(board, Missing)
  end
end

# The oldest queued job of the queue, leased to the worker; Empty when none is queued.
fn lent(board: Board, worker: String, queue: String, lease_ms: UInt64, now: Time) : Decision
  order = board.orders.get(queue) or no_order()
  fresh_at = first_fresh(board, queue, order.head, order.tail)
  back_at = first_queued(board, order.back, order.back_head)
  fresh = fresh_number(board, queue, fresh_at)
  back = order.back.get(back_at)
  take_back = case (fresh, back)
    (Some(f), Some(b)): b < f
    (None, Some(_)): true
    (Some(_), None) | (None, None): false
  end
  head = if fresh is Some(_) and !take_back: fresh_at + 1 else: fresh_at
  back_head = if take_back: back_at + 1 else: back_at
  var passed = passed_over(board, queue, order, head)
  passed.orders = passed.orders.set(queue,
    trimmed(Order(head: head, tail: order.tail, back: order.back, back_head: back_head)))
  chosen = if take_back: back else: fresh
  case chosen
    Some(number): handed(passed, number, worker, lease_ms, now)
    None: answered(passed, Empty)
  end
end

# The board without the pages of fresh positions its queue's head has passed.
fn passed_over(board: Board, queue: String, order: Order, head: UInt64) : Board
  var after = board
  after.fresh = (page_of(order.head)..page_of(head)).reduce(after.fresh,
    fn(fresh, p) fresh.remove((queue, p)) end)
  after
end

# What `leased` asks of the job, the worker, and the lease. A record in a state the API can never
# produce would break the first, so a call that would trip the contract is answered 503 instead of
# crashing the queue; the folder check at open is what keeps such a record out in the first place.
fn leasable?(held: Job, worker: String, lease_ms: UInt64) : Bool
  held.state == Queued and held.tries < held.max_tries and token?(worker) and lease_ms?(lease_ms)
end

fn handed(board: Board, number: UInt64, worker: String, lease_ms: UInt64, now: Time) : Decision
  case job_of(board, number)
    Some(held):
      if !leasable?(held, worker, lease_ms)
        return answered(board,
          Unavailable(reason: "#{id_of(number)} is not in a state a lease can take"))
      end
      lease = leased(held, worker, lease_ms, now)
      var after = with_lease(with_job(board, lease), number, lease.lease_until or now)
      after.counts = recounted(board.counts, Queued, Leased)
      Decision(board: after, outcome: Found(job: lease),
        writes: [(id_of(number), Some(shown(lease)))])
    None: answered(board, Empty)
  end
end

# The first fresh position of the queue from `from` on whose job is still queued, or `tail`;
# looked for 256 positions at a time.
fn first_fresh(board: Board, queue: String, from: UInt64, tail: UInt64) : UInt64
  ensures result >= from or result == tail

  return tail if from >= tail
  upto = min_of(from + 256, tail)
  case (from..upto).find(fn(p) fresh_queued?(board, queue, p) end)
    Some(p): p
    None: first_fresh(board, queue, upto, tail)
  end
end

fn fresh_queued?(board: Board, queue: String, position: UInt64) : Bool
  case fresh_number(board, queue, position)
    Some(number): queued_job?(board, number)
    None: false
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

# An order whose passed-over back entries are dropped once they are most of it.
fn trimmed(order: Order) : Order
  var after = order
  if order.back_head >= 1_024 and order.back_head * 2 >= order.back.size
    after.back = order.back.drop(order.back_head)
    after.back_head = 0
  end
  after
end

# An ack or a fail by the worker that holds a live lease on the job; 409 for anyone else. A fail
# with a backoff leaves the job scheduled, and one without it queued again.
fn settled(board: Board, worker: String, id: String, reason: String, failing: Bool,
  now: Time) : Decision
  case job_at(board, id)
    Some(held):
      if !holds?(held, worker, now)
        return answered(board, Conflict(reason: "#{id} is not leased to this worker"))
      end
      after_job = if failing: failed(held, worker, reason, now) else: acked(held, worker, now)
      var after = without_lease(with_job(board, after_job), held.number)
      after = if after_job.state == Scheduled
        with_wait(after, held.number, after_job.run_at or now)
      else
        after
      end
      after.counts = recounted(board.counts, Leased, after_job.state)
      after.orders = if after_job.state == Queued
        after.orders.set(held.queue,
          with_back(after.orders.get(held.queue) or no_order(), [held.number]))
      else
        after.orders
      end
      Decision(board: after, outcome: Found(job: after_job), writes: [(id, Some(shown(after_job)))])
    None: answered(board, Missing)
  end
end

# A dead job put back in its queue with no tries, taking its place by number; 409 for a job in
# any other state.
fn revived(board: Board, id: String, now: Time) : Decision
  case job_at(board, id)
    Some(held):
      if held.state != Dead
        return answered(board, Conflict(reason: "#{id} is not dead"))
      end
      back = retried(held, now)
      var after = with_job(board, back)
      after.counts = recounted(board.counts, Dead, Queued)
      after.orders = after.orders.set(held.queue,
        with_back(after.orders.get(held.queue) or no_order(), [held.number]))
      Decision(board: after, outcome: Found(job: back), writes: [(id, Some(shown(back)))])
    None: answered(board, Missing)
  end
end

# The first record a folder holds that no request could have left, in key order: its key and the
# rule it breaks, None when every record is one. Every command that opens a folder checks it
# against this, so a board is built only from records the API could have written.
fn ill_formed(entries: List((String, String))) : Option((String, String))
  sorted = entries.sort_by(fn(e) e.0 end)
  top = highest(sorted)
  bad = try sorted.find(fn(e) entry_broken(e, top) is Some(_) end)
  case entry_broken(bad, top)
    Some(why): Some((bad.0, why))
    None: None
  end
end

fn entry_broken(entry: (String, String), top: UInt64) : Option(String)
  if entry.0 == "ids": ids_broken(entry.1, top) else: rule_broken(entry.0, entry.1)
end

# The ids counter is a number, and no lower than the highest job's, so no number is handed twice.
fn ids_broken(value: String, top: UInt64) : Option(String)
  case value.to_u64
    Some(next):
      if next >= top: None else: Some("the next id is below j_#{top}")
    None: Some("is not a number")
  end
end

fn highest(entries: List((String, String))) : UInt64
  entries.flat_map(fn(e) numbered(e.0) end).max or 0
end

fn numbered(key: String) : List(UInt64)
  case number_of(key)
    Some(n): [n]
    None: []
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
  queued = if held.state == Queued: with_fresh(board, held.queue, held.number) else: board
  leased_too = if held.state == Leased
    with_lease(queued, held.number, held.lease_until or board.started)
  else
    queued
  end
  waiting = if held.state == Scheduled
    with_wait(leased_too, held.number, held.run_at or board.started)
  else
    leased_too
  end
  var after = with_job(waiting, held)
  after.counts = counted(board.counts, held.state, true)
  after
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

fn at(text: String) : Time
  Time.parse(text) or Time.from_parts(2026, 1, 1, 0, 0, 0)
end

fn start() : Time
  at("2026-09-14T10:00:00Z")
end

fn call(worker: String, command: Command) : Call
  Call(worker: worker, command: command)
end

# A job to make with no backoff and no delay.
fn plain(queue: String, payload: String, max_tries: UInt64) : Making
  Making(queue: queue, payload: payload, max_tries: max_tries, backoff_ms: 0, delay_ms: 0)
end

fn making(queue: String, payload: String, max_tries: UInt64, backoff_ms: UInt64,
  delay_ms: UInt64) : Making
  Making(queue: queue, payload: payload, max_tries: max_tries, backoff_ms: backoff_ms,
    delay_ms: delay_ms)
end

# A board with one job made in each queue named, in order, each with two tries.
fn with_jobs(queues: List(String)) : Board
  queues.reduce(board(start(), 1),
    fn(b, q) decide(b, call("p", Create(making: plain(q, q, 2))), start()).board end)
end

fn number_in(decision: Decision) : UInt64
  case decision.outcome
    Made(one): one.number
    Found(one): one.number
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Unavailable(_):
      0
  end
end

fn job_in(decision: Decision) : Option(Job)
  case decision.outcome
    Made(one): Some(one)
    Found(one): Some(one)
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Unavailable(_):
      None
  end
end

fn lease_by(b: Board, worker: String, queue: String, ms: UInt64, now: Time) : Decision
  decide(b, call(worker, Lease(queue: queue, lease_ms: ms)), now)
end

fn store_of(b: Board) : List((String, String))
  all_jobs(b).map(fn(j) (id_of(j.number), shown(j)) end).push(("ids", "#{b.reserved}"))
end

fn counts_of(b: Board, now: Time) : Counts
  health_of(b, now)
end

# The entry with the tries of the record under `key` taken to 0, which no state of that job allows.
fn broken_tries(entry: (String, String), key: String) : (String, String)
  return entry if entry.0 != key
  (entry.0, entry.1.replace("\"tries\": 1", "\"tries\": 0"))
end

# The entry with the ids counter set to `value`.
fn counter(entry: (String, String), value: String) : (String, String)
  if entry.0 == "ids": (entry.0, value) else: entry
end

test "a job made is found by its id, and its record is written under that id"
  first = decide(board(start(), 1), call("p", Create(making: plain("emails", "hi", 3))), start())
  assert number_in(first) == 1
  assert first.writes.map(fn(w) w.0 end) == ["ids", "j_1"]
  assert first.writes.get(0) == Some(("ids", Some("1001")))
  found = decide(first.board, call("p", Fetch(id: "j_1")), start())
  assert job_in(found) == job_in(first) and found.writes == []
  assert decide(first.board, call("p", Fetch(id: "j_2")), start()).outcome == Missing
  assert decide(first.board, call("p", Fetch(id: "nope")), start()).outcome == Missing
  second = decide(first.board, call("p", Create(making: plain("emails", "", 1))), start())
  assert second.writes.map(fn(w) w.0 end) == ["j_2"]
end

test "a lease hands out the oldest queued job of its queue, and Empty when none is queued"
  b = with_jobs(["a", "b", "a"])
  first = lease_by(b, "w1", "a", 1_000, start())
  assert number_in(first) == 1
  assert job_in(first) is Some(one)
  assert one.worker == Some("w1") and one.tries == 1
  second = lease_by(first.board, "w2", "a", 1_000, start())
  assert number_in(second) == 3
  assert lease_by(second.board, "w3", "a", 1_000, start()).outcome == Empty
  assert lease_by(second.board, "w3", "nowhere", 1_000, start()).outcome == Empty
  failed_one = decide(second.board, call("w1", Fail(id: "j_1", reason: "smtp")), start())
  assert job_in(failed_one) is Some(back)
  assert back.state == Queued and back.reason == Some("smtp")
  newer = decide(failed_one.board, call("p", Create(making: plain("a", "4", 2))), start())
  again = lease_by(newer.board, "w4", "a", 1_000, start())
  assert number_in(again) == 1
  assert job_in(again) is Some(retried_one)
  assert retried_one.tries == 2
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

test "a lease that runs out is leased again with tries at 2, and one that runs out on its last try is dead"
  b = with_jobs(["a"])
  first = lease_by(b, "w1", "a", 100, start())
  assert lease_by(first.board, "w2", "a", 100, start() + 99.ms).outcome == Empty
  second = lease_by(first.board, "w2", "a", 100, start() + 100.ms)
  assert second.writes.map(fn(w) w.0 end) == ["j_1", "j_1"]
  assert job_in(second) is Some(again)
  assert again.tries == 2 and again.worker == Some("w2")
  late = decide(second.board, call("w1", Ack(id: "j_1")), start() + 150.ms)
  assert late.outcome is Conflict(_)
  gone = decide(second.board, call("p", Fetch(id: "j_1")), start() + 200.ms)
  assert job_in(gone) is Some(dead)
  assert dead.state == Dead and dead.tries == 2 and gone.writes.size == 1
  assert decide(gone.board, call("", Health), start() + 200.ms).outcome is Healthy(counts)
  assert counts.dead == 1 and counts.leased == 0 and counts.queued == 0
  assert lease_by(gone.board, "w3", "a", 100, start() + 300.ms).outcome == Empty
end

test "a job made with a delay is scheduled, is not leased before its run_at, and is leased after it"
  first = decide(board(start(), 1), call("p", Create(making: making("a", "later", 2, 0, 1_000))),
    start())
  assert job_in(first) is Some(made)
  assert made.state == Scheduled and made.run_at == Some(start() + 1_000.ms)
  assert lease_by(first.board, "w1", "a", 1_000, start() + 999.ms).outcome == Empty
  assert decide(first.board, call("", Health), start()).outcome is Healthy(before)
  assert before.scheduled == 1 and before.queued == 0
  due_now = lease_by(first.board, "w1", "a", 1_000, start() + 1_000.ms)
  assert job_in(due_now) is Some(held)
  assert held.state == Leased and held.tries == 1 and held.run_at is None
  assert due_now.writes.map(fn(w) w.0 end) == ["j_1", "j_1"]
  listing = decide(first.board, call("p", Listing(queue: None, state: Some(Scheduled))), start())
  assert listing.outcome is Listed(waiting)
  assert waiting.map(fn(j) j.number end) == [1]
end

test "a fail with a backoff schedules the job, and a lease before its run_at is Empty"
  made = decide(board(start(), 1), call("p", Create(making: making("a", "flaky", 2, 500, 0))),
    start())
  held = lease_by(made.board, "w1", "a", 1_000, start())
  assert number_in(held) == 1
  back = decide(held.board, call("w1", Fail(id: "j_1", reason: "flaky")), start() + 10.ms)
  assert job_in(back) is Some(waiting)
  assert waiting.state == Scheduled and waiting.run_at == Some(start() + 510.ms)
  assert decide(back.board, call("", Health), start()).outcome is Healthy(counts)
  assert counts.scheduled == 1 and counts.queued == 0 and counts.leased == 0
  assert lease_by(back.board, "w2", "a", 1_000, start() + 509.ms).outcome == Empty
  again = lease_by(back.board, "w2", "a", 1_000, start() + 510.ms)
  assert job_in(again) is Some(second)
  assert second.tries == 2 and second.worker == Some("w2")
  dead = decide(again.board, call("w2", Fail(id: "j_1", reason: "again")), start() + 520.ms)
  assert job_in(dead) is Some(last)
  assert last.state == Dead and last.run_at is None
end

test "a lease that runs out with a backoff leaves the job scheduled until its run_at"
  made = decide(board(start(), 1), call("p", Create(making: making("a", "flaky", 3, 500, 0))),
    start())
  held = lease_by(made.board, "w1", "a", 100, start())
  assert number_in(held) == 1
  looked_at = decide(held.board, call("p", Fetch(id: "j_1")), start() + 100.ms)
  assert job_in(looked_at) is Some(waiting)
  assert waiting.state == Scheduled and waiting.run_at == Some(start() + 600.ms)
  assert looked_at.writes.map(fn(w) w.0 end) == ["j_1"]
  assert lease_by(looked_at.board, "w2", "a", 100, start() + 599.ms).outcome == Empty
  assert number_in(lease_by(looked_at.board, "w2", "a", 100, start() + 600.ms)) == 1
end

test "a retry queues a dead job with no tries and its place by id, and refuses any other state"
  b = with_jobs(["a", "a"])
  one = lease_by(b, "w1", "a", 1_000, start())
  assert decide(one.board, call("p", Retry(id: "j_1")), start()).outcome is Conflict(_)
  assert decide(one.board, call("p", Retry(id: "j_2")), start()).outcome is Conflict(_)
  assert decide(one.board, call("p", Retry(id: "j_9")), start()).outcome == Missing
  failed_once = decide(one.board, call("w1", Fail(id: "j_1", reason: "one")), start())
  twice = decide(lease_by(failed_once.board, "w1", "a", 1_000, start()).board,
    call("w1", Fail(id: "j_1", reason: "two")), start())
  assert job_in(twice) is Some(dead)
  assert dead.state == Dead and dead.tries == 2
  back = decide(twice.board, call("p", Retry(id: "j_1")), start() + 1.ms)
  assert job_in(back) is Some(revived_one)
  assert revived_one.state == Queued and revived_one.tries == 0 and revived_one.reason is None
  assert back.writes == [("j_1", Some(shown(revived_one)))]
  assert decide(back.board, call("", Health), start()).outcome is Healthy(counts)
  assert counts.dead == 0 and counts.queued == 2
  assert number_in(lease_by(back.board, "w2", "a", 1_000, start() + 2.ms)) == 1
  done = decide(lease_by(back.board, "w2", "a", 1_000, start() + 2.ms).board,
    call("w2", Ack(id: "j_1")), start() + 3.ms)
  assert decide(done.board, call("p", Retry(id: "j_1")), start()).outcome is Conflict(_)
end

test "a delete takes a queued, scheduled, done, or dead job, and refuses a leased one"
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
  later = decide(done.board, call("p", Create(making: making("a", "later", 1, 0, 5_000))), start())
  gone = decide(later.board, call("p", Remove(id: "j_3")), start())
  assert gone.outcome == Removed
  assert decide(gone.board, call("", Health), start()).outcome is Healthy(counts)
  assert counts.scheduled == 0
  assert lease_by(gone.board, "w2", "a", 1_000, start() + 10_000.ms).outcome == Empty
end

test "a listing filters by queue and by state, by id, and holds at most 100"
  b = with_jobs(["b"].concat("a".repeat(105).chars).push("b"))
  all = decide(b, call("p", Listing(queue: None, state: None)), start())
  assert all.outcome is Listed(jobs)
  assert jobs.size == 100 and (jobs.first or job(9, plain("q", "", 1), start())).number == 1
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

test "the queues list every queue that holds a job, by name, and health's totals are their sums"
  b = with_jobs(["b", "a", "a", "c"])
  lent = lease_by(b, "w1", "a", 1_000, start())
  listed_queues = decide(lent.board, call("p", Tallying), start())
  assert listed_queues.outcome is Tallied(queues)
  assert queues.map(fn(t) t.name end) == ["a", "b", "c"]
  assert queues.first == Some(Tally(name: "a", queued: 1, scheduled: 0, leased: 1, done: 0,
    dead: 0))
  assert queues.get(1) == Some(Tally(name: "b", queued: 1, scheduled: 0, leased: 0, done: 0,
    dead: 0))
  counts = health_of(lent.board, start())
  assert queues.map(fn(t) t.queued end).sum == counts.queued
  assert queues.map(fn(t) t.leased end).sum == counts.leased
  assert listed_queues.writes == []
  gone = decide(lent.board, call("p", Remove(id: "j_1")), start())
  assert decide(gone.board, call("p", Tallying), start()).outcome is Tallied(fewer)
  assert fewer.map(fn(t) t.name end) == ["a", "c"]
  assert decide(board(start(), 1), call("p", Tallying), start()).outcome == Tallied(queues: [])
end

test "a folder's records are ill-formed at the first key whose record breaks a rule"
  b = with_jobs(["a", "a", "a"])
  held = lease_by(b, "w1", "a", 1_000, start()).board
  entries = store_of(held)
  assert ill_formed(entries) is None
  assert ill_formed([]) is None
  ill = entries.map(fn(e) broken_tries(e, "j_1") end)
  assert ill_formed(ill) == Some(("j_1", "a leased job has at least one try"))
  two = ill.push(("j_0", "not a job"))
  assert ill_formed(two) == Some(("j_0", "is not a job"))
  assert ill_formed(entries.push(("j_9", "not a job"))) == Some(("j_9", "is not a job"))
  assert ill_formed(entries.map(fn(e) counter(e, "x") end)) == Some(("ids", "is not a number"))
  assert ill_formed(entries.map(fn(e) counter(e, "2") end)) == Some(("ids",
    "the next id is below j_3"))
  assert ill_formed(entries.map(fn(e) counter(e, "3") end)) is None
  assert ill_formed(records(held).map(fn(r) ("j_9", r) end)) is Some(named)
  assert named.0 == "j_9" and named.1.starts_with?("its id is j_")
end

test "a board rebuilt from its records holds the same jobs, leases, counts, and next number"
  b = with_jobs(["a", "b", "a", "a", "a", "a", "a", "a", "a", "a", "a"])
  lent_one = lease_by(b, "w1", "a", 1_000, start())
  done = decide(lease_by(lent_one.board, "w2", "a", 1_000, start()).board,
    call("w2", Ack(id: "j_3")), start())
  waiting = decide(done.board, call("p", Create(making: making("a", "later", 2, 0, 5_000))),
    start())
  cut = decide(waiting.board, call("p", Remove(id: "j_4")), start()).board
  assert rebuilt(store_of(cut).reverse, start()) is Some(again)
  kept = Kept(before: records(cut), after: records(again))
  assert kept.after == kept.before
  assert again.next == 1_001 and again.reserved == 1_001
  assert health_of(again, start()) == health_of(cut, start())
  assert counts_of(again, start()).scheduled == 1
  assert lease_by(again, "w3", "a", 1_000, start()).outcome is Found(fifth)
  assert fifth.number == 5
  expired = lease_by(again, "w3", "a", 1_000, start() + 1_000.ms)
  assert number_in(expired) == 1
  woken = decide(again, call("p", Fetch(id: "j_12")), start() + 5_000.ms)
  assert job_in(woken) is Some(later_job)
  assert later_job.state == Queued and later_job.run_at is None
  assert woken.writes.map(fn(w) w.0 end) == ["j_1", "j_12"]
  assert rebuilt([("j_1", "not a job")], start()) is None
  assert rebuilt([("j_2", records(cut).first or "")], start()) is None
  assert rebuilt([], start()) is Some(empty)
  assert empty.next == 1
end

test "a board rebuilt from the records the previous version wrote holds every job with its state"
  old_queued = "{\"id\": \"j_1\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"one\", \"attempts\": 0, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:00:00Z\"}"
  old_leased = "{\"id\": \"j_2\", \"queue\": \"emails\", \"state\": \"leased\", \"payload\": \"two\", \"attempts\": 1, \"max_attempts\": 2, \"created_at\": \"2026-09-14T09:01:00Z\", \"updated_at\": \"2026-09-14T09:07:00Z\", \"worker\": \"w-old\", \"lease_until\": \"2026-09-14T09:08:00Z\"}"
  assert rebuilt([("ids", "1000"), ("j_1", old_queued), ("j_2", old_leased)], start()) is Some(b)
  assert health_of(b, start()) == Counts(queued: 1, scheduled: 0, leased: 1, done: 0, dead: 0,
    uptime_ms: 0)
  assert b.next == 1_000 and b.reserved == 1_000
  assert records(b).all?(fn(r) !r.contains?("attempts") end)
  assert records(b).all?(fn(r) r.contains?("\"backoff_ms\": 0") end)
  assert snapshot(b).size == 3
  first = lease_by(b, "w1", "emails", 1_000, start())
  assert number_in(first) == 1
  assert job_in(first) is Some(one)
  assert one.tries == 1 and one.backoff_ms == 0
  ran_out = lease_by(first.board, "w2", "emails", 1_000, start())
  assert number_in(ran_out) == 2
  assert job_in(ran_out) is Some(two)
  assert two.tries == 2 and two.worker == Some("w2")
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
    made = decide(board(start(), 1), call("p", Create(making: plain("q", payload, 1))), start())
    fetched = decide(made.board, call("p", Fetch(id: "j_1")), start())
    assert job_in(fetched) is Some(back)
    assert back.payload == payload and job_in(made) == Some(back)
  end
end

verified: types, contracts, tests (17), property (200 seeds), sim (not run)
          proven: not run
