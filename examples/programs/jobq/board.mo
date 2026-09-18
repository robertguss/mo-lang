module Jobq.Board
expose Command, Call, Outcome, Counts, Tally, Order, Move, Cut, Board, Decision, Kept, Placement, Relabeled, Pruned, board, retaining, decide, relabeled, pruned, oldest_shelved, folded_in, shelved, shelved_into, shelf_applied, tombstone?, rebuilt, records, shelf_records, health_of, tallies, ill_formed, snapshot, shelf_snapshot

use Jobq.Job{Phase, Job, Making, job, archived, leased, acked, failed, retried, handed_off, looked, holds?, due?, queue?, payload?, token?, worker?, lease_ms?, id_of, number_of, shown, decoded, rule_broken, archive_broken, tagged, renames_of, to_ms}

intent "The queue as a value: every job by number, each queue's queued jobs oldest first, the leases and when the first runs out, the scheduled jobs and when the first is due, and the counts; a call becomes a decision, the board after it, the answer, and the records the store must hold before the answer is sent; every decision first puts back the leases that have run out, queues the scheduled jobs whose run_at has passed, and moves to the archive the done and dead jobs older than the retention; a create with a key answers the job the key already names; the archived jobs are kept beside the board, readable by id and by key, never listed; a lease is handed from the worker that holds it to another; a queue is renamed, every job in it, live or archived, with its key, by one record that names the id the next job would take, which a replay applies to the records written before it and to no job numbered from that id on; and the archived jobs older than an age are pruned, their keys freed, by one record naming the cutoff, which a replay applies to the archive records written before it."

never "a job is lost or changed by a replay"
  for k in Kept.all
    k.after != k.before
  end
end

never "a job is on the live board and in the archive at once after an open"
  for p in Placement.all
    p.live and p.shelved
  end
end

never "a rename leaves a job in no queue but its own or the new one, or moves a job of another queue"
  for r in Relabeled.all
    (r.before == r.from and r.after != r.to) or (r.before != r.from and r.after != r.before)
  end
end

never "a prune removes a live job, or an archived job younger than its age"
  for p in Pruned.all
    p.live or p.archived_at > p.cutoff
  end
end

never "a rename touches a lease"
  for r in Relabeled.all
    r.worker_before != r.worker_after or r.until_before != r.until_after
  end
end

# What a caller asks of the queue once its request is read. `worker` is the caller's token.
enum Command
  Create(making: Making)
  Fetch(id: String)
  Listing(queue: Option(String), state: Option(Phase), key: Option(String))
  Remove(id: String)
  Lease(queue: String, lease_ms: UInt64)
  Ack(id: String)
  Fail(id: String, reason: String)
  Retry(id: String)
  Handoff(id: String, to: String)
  Rename(queue: String, to: String)
  Pruning(older_than_ms: UInt64)
  Archive
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
  archived: UInt64
  uptime_ms: Int64
  restarts: UInt64
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
  Renamed(queue: String, moved: UInt64)
  Cleared(pruned: UInt64, remaining: UInt64)
  Shelf(archived: UInt64, oldest: Option(Time), bytes: UInt64)
  Absent(reason: String)
  Unavailable(reason: String)
end

# A rename as the log keeps it: its place among the log's marks (renames and prunes, numbered in one
# run), `from`, `to`, and the id the next created job would have taken at the rename, which a record
# the previous version wrote leaves out (None).
struct Move
  number: UInt64
  from: String
  to: String
  next_id: Option(UInt64)
end

# A prune as the log keeps it: its place among the log's marks, the cutoff (an archived job whose
# archived_at is at or before it is gone), and how many jobs it removed.
struct Cut
  number: UInt64
  cutoff: Time
  pruned: UInt64
end

# One job a prune removed: whether it was live, when it was archived, and the prune's cutoff.
struct Pruned
  number: UInt64
  live: Bool
  archived_at: Time
  cutoff: Time
end

# One job a rename moved: its queue before and after, the rename's two names, and its lease before
# and after.
struct Relabeled
  number: UInt64
  before: String
  after: String
  from: String
  to: String
  worker_before: Option(String)
  worker_after: Option(String)
  until_before: Option(Time)
  until_after: Option(Time)
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

# The jobs by number, in number order, in pages of 256; the archived jobs the same way, and how
# many; each queue and key's job number, in 256 pages by the pair's hash; each done or dead job's
# updated_at, in pages of 256, the earliest of them, or earlier, and how long a job is kept after
# it; each queue's order, and the jobs at its
# fresh positions, in pages of 256 positions; each leased job's lease end, in pages of 256, and
# the earliest of them, or earlier; each scheduled job's run_at the same way, and the earliest of
# them; the next number and the numbers below `reserved` the log has reserved; the counts; when
# the queue started; and the marks so far (renames and prunes, numbered in one run), with the
# renames and the prunes the log still holds as records. Changing a map's existing entry copies the whole map (TOOLCHAIN-BUGS.md,
# bug 1), so every change copies one page and sets one entry in a map of pages, never a map of
# every job.
struct Board
  jobs: Map(UInt64, Map(UInt64, Job))
  shelf: Map(UInt64, Map(UInt64, Job))
  shelved: UInt64
  keys: Map(UInt64, Map((String, String), UInt64))
  ends: Map(UInt64, Map(UInt64, Time))
  retire: Option(Time)
  retain_ms: UInt64
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
  marks: UInt64
  moves: List(Move)
  cuts: List(Cut)
end

# The board after a call, the answer to send, and the records to write first: a job's record
# under its id, None for a job removed or archived, and the reserved numbers under `ids`; and the
# archive's changes, a job's archived record under its id, or None for an archived job deleted,
# which the archive keeps as a tombstone until its next compaction. Every archive change is on disk
# before the live log's lines, so a kill between the two leaves the archive's word standing.
struct Decision
  board: Board
  outcome: Outcome
  writes: List((String, Option(String)))
  shelved: List((String, Option(String)))
end

# A job after an open: whether it is on the live board, and whether it is in the archive.
struct Placement
  number: UInt64
  live: Bool
  shelved: Bool
end

# A store's jobs before it stopped and after it was opened again, as their records.
struct Kept
  before: List(String)
  after: List(String)
end

# An empty board whose first job is numbered `next`.
fn board(started: Time, next: UInt64) : Board
  requires next >= 1

  Board(jobs: Map.new(), shelf: Map.new(), shelved: 0, keys: Map.new(), ends: Map.new(),
    retire: None, retain_ms: 86_400_000, orders: Map.new(), fresh: Map.new(), leases: Map.new(),
    due: None, waits: Map.new(), wake: None, next: next, reserved: next,
    counts: Counts(queued: 0, scheduled: 0, leased: 0, done: 0, dead: 0, archived: 0, uptime_ms: 0,
    restarts: 0),
    started: started, marks: 0, moves: [], cuts: [])
end

# The board keeping a done or dead job `ms` after its last change before it archives it.
fn retaining(board: Board, ms: UInt64) : Board
  var after = board
  after.retain_ms = ms
  after
end

fn decide(board: Board, call: Call, now: Time) : Decision
  swept = sweep(board, now)
  decided = case call.command
    Create(making): created(swept.board, making, now)
    Fetch(id): answered(swept.board, fetched(swept.board, id))
    Listing(queue: queue, state: state, key: key):
      answered(swept.board, Listed(jobs: listed(swept.board, queue, state, key)))
    Remove(id): removed(swept.board, id)
    Lease(queue: queue, lease_ms: lease_ms): lent(swept.board, call.worker, queue, lease_ms, now)
    Ack(id): settled(swept.board, call.worker, id, "", false, now)
    Fail(id: id, reason: reason): settled(swept.board, call.worker, id, reason, true, now)
    Retry(id): revived(swept.board, id, now)
    Handoff(id: id, to: to): passed_on(swept.board, call.worker, id, to, now)
    Rename(queue: queue, to: to): renaming(swept.board, queue, to)
    Pruning(older_than_ms): pruning(swept.board, older_than_ms, now)
    Archive: answered(swept.board, shelf_of(swept.board))
    Health: answered(swept.board, Healthy(counts: health_of(swept.board, now)))
    Tallying: answered(swept.board, Tallied(queues: tallies(swept.board)))
  end
  Decision(board: decided.board, outcome: decided.outcome,
    writes: tags(swept.writes.concat(decided.writes), board.marks),
    shelved: tags(swept.shelved.concat(decided.shelved), board.marks))
end

# A decision's job records with the marks the board had before it: no decision both writes a mark
# (a rename or a prune) and a job's record, so every record a decision writes has seen exactly those.
fn tags(changes: List((String, Option(String))), marks: UInt64) : List((String, Option(String)))
  return changes if marks == 0
  changes.map(fn(c) tag(c, marks) end)
end

fn tag(change: (String, Option(String)), marks: UInt64) : (String, Option(String))
  case change.1
    Some(record):
      (change.0, Some(if change.0.starts_with?("j_")
        tagged(record, marks)
      else
        record
      end))
    None: change
  end
end

fn answered(board: Board, outcome: Outcome) : Decision
  Decision(board: board, outcome: outcome, writes: [], shelved: [])
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

fn shelf_job(board: Board, number: UInt64) : Option(Job)
  page = try board.shelf.get(page_of(number))
  page.get(number)
end

fn with_shelf_job(board: Board, held: Job) : Board
  at = page_of(held.number)
  var after = board
  after.shelf = after.shelf.set(at, (after.shelf.get(at) or Map.new()).set(held.number, held))
  after.shelved = board.shelved + 1
  after
end

fn without_shelf_job(board: Board, number: UInt64) : Board
  at = page_of(number)
  var after = board
  after.shelf = after.shelf.set(at, (after.shelf.get(at) or Map.new()).remove(number))
  after.shelved = board.shelved - 1
  after
end

# Every archived job, by number.
fn all_shelved(board: Board) : List(Job)
  board.shelf.values.flat_map(fn(page) page.values end)
end

# Which of 256 pages holds a queue and key.
fn key_page(queue: String, key: String) : UInt64
  ensures result < 256

  "#{queue} #{key}".bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 256 end)
end

# The job number a queue and key name, live or archived.
fn keyed_number(board: Board, queue: String, key: String) : Option(UInt64)
  page = try board.keys.get(key_page(queue, key))
  page.get((queue, key))
end

# The board with the job's key, if it has one, naming it.
fn with_key(board: Board, held: Job) : Board
  case held.key
    Some(key):
      at = key_page(held.queue, key)
      var after = board
      after.keys = after.keys.set(at,
        (after.keys.get(at) or Map.new()).set((held.queue, key), held.number))
      after
    None: board
  end
end

# The board with the job's key, if it has one, free again.
fn without_key(board: Board, held: Job) : Board
  case held.key
    Some(key):
      at = key_page(held.queue, key)
      var after = board
      after.keys = after.keys.set(at, (after.keys.get(at) or Map.new()).remove((held.queue, key)))
      after
    None: board
  end
end

# The job a queue and key name, live or archived.
fn keyed_job(board: Board, queue: String, key: String) : Option(Job)
  number = try keyed_number(board, queue, key)
  case job_of(board, number)
    Some(held): Some(held)
    None: shelf_job(board, number)
  end
end

# The board noting that a job is done or dead since `at`, so a look archives it once it is old.
fn with_end(board: Board, held: Job) : Board
  return board if held.state != Done and held.state != Dead
  page = page_of(held.number)
  var after = board
  after.ends = after.ends.set(page,
    (after.ends.get(page) or Map.new()).set(held.number, held.updated_at))
  after.retire = Some(min_of(board.retire or held.updated_at, held.updated_at))
  after
end

fn without_end(board: Board, number: UInt64) : Board
  page = page_of(number)
  var after = board
  after.ends = after.ends.set(page, (after.ends.get(page) or Map.new()).remove(number))
  after
end

# Every done or dead job's number and last change.
fn all_ends(board: Board) : List((UInt64, Time))
  board.ends.values.flat_map(fn(page) page.entries end)
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
  counts.archived = board.shelved
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
  ensures !looks_due?(result.board, now)

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
  shelving = shelved(cleared, now)
  Decision(board: shelving.board, outcome: Empty, writes: writes.concat(shelving.writes),
    shelved: shelving.shelved)
end

# Whether a lease has run out, a scheduled job is due, or a done or dead job is old enough to
# archive.
fn looks_due?(board: Board, now: Time) : Bool
  retired = case board.retire
    Some(at): old_enough?(board, at, now)
    None: false
  end
  passed?(board.due, now) or passed?(board.wake, now) or retired
end

# Whether a job last changed at `at` has been kept its retention by `now`.
fn old_enough?(board: Board, at: Time, now: Time) : Bool
  (now - at).ms >= board.retain_ms.to_i64
end

# The archive move, as a pure step: every done or dead job whose updated_at is at least the
# retention before now leaves the live board for the archive, with `archived_at` now; its archived
# record is the archive's change, and a delete of its id the live log's.
fn shelved(board: Board, now: Time) : Decision
  ensures all_ends(result.board).all?(fn(e) !old_enough?(board, e.1, now) end)
  ensures result.writes.size == result.shelved.size
  ensures result.board.shelved == board.shelved + result.shelved.size

  due = all_ends(board).filter(fn(e) old_enough?(board, e.1, now) end).map(fn(e) e.0 end).sort
  moved = due.flat_map(fn(n) ended_job(board, n) end).map(fn(j) archived(j, now) end)
  var after = moved.reduce(board, fn(so_far, j) shelved_into(so_far, j) end)
  after.retire = all_ends(after).map(fn(e) e.1 end).min
  Decision(board: after, outcome: Empty, writes: moved.map(fn(j) (id_of(j.number), None) end),
    shelved: moved.map(fn(j) (id_of(j.number), Some(shown(j))) end))
end

fn ended_job(board: Board, number: UInt64) : List(Job)
  case job_of(board, number)
    Some(held) if held.state == Done or held.state == Dead: [held]
    Some(_): []
    None: []
  end
end

# The board with an archived job off the live board, if it was there, and in the archive; its key
# still names it.
fn shelved_into(board: Board, held: Job) : Board
  requires held.archived_at is Some(_)

  var after = board
  if job_of(board, held.number) is Some(live)
    after = without_end(without_job(after, held.number), held.number)
    after.counts = counted(board.counts, live.state, false)
  end
  if shelf_job(after, held.number) is Some(_)
    after = without_shelf_job(after, held.number)
  end
  with_key(with_shelf_job(after, held), held)
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
      after = if held.state == Leased
        without_lease(after, number)
      else
        without_wait(after, number)
      end
      after = if back.state == Scheduled: with_wait(after, number, back.run_at or now) else: after
      after = with_end(after, back)
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
  if making.key is Some(key)
    if keyed_job(board, making.queue, key) is Some(first)
      return answered(board, Found(job: first))
    end
  end
  made = job(board.next, making, now)
  reserving = board.next >= board.reserved
  placed_now = if made.state == Queued
    with_fresh(board, made.queue, made.number)
  else
    with_wait(board, made.number, made.run_at or now)
  end
  var after = with_key(with_job(placed_now, made), made)
  after.next = board.next + 1
  after.reserved = if reserving: board.next + 1_000 else: board.reserved
  after.counts = counted(board.counts, made.state, true)
  reserve = if reserving: [("ids", Some("#{board.next + 1_000}"))] else: []
  Decision(board: after, outcome: Made(job: made),
    writes: reserve.concat([(id_of(made.number), Some(shown(made)))]), shelved: [])
end

# A job by id, live or archived.
fn fetched(board: Board, id: String) : Outcome
  case job_at(board, id)
    Some(held): Found(job: held)
    None:
      case shelf_at(board, id)
        Some(held): Found(job: held)
        None: Missing
      end
  end
end

fn shelf_at(board: Board, id: String) : Option(Job)
  number = try number_of(id)
  shelf_job(board, number)
end

# The answer for a call that would change an archived job, or Missing when there is none.
fn on_shelf(board: Board, id: String) : Outcome
  if shelf_at(board, id) is Some(_)
    return Conflict(reason: "#{id} is archived")
  end
  Missing
end

fn job_at(board: Board, id: String) : Option(Job)
  number = try number_of(id)
  job_of(board, number)
end

# The jobs in a queue, in a state, or both, by id, the first 100; with a key, the one job the
# queue and key name, archived or not, when it is in the state asked for. An archived job is
# listed by its key only.
fn listed(board: Board, queue: Option(String), state: Option(Phase),
  key: Option(String)) : List(Job)
  ensures result.size <= 100

  if key is Some(name)
    return case keyed_job(board, queue or "", name)
      Some(held) if wanted?(held, queue, state): [held]
      Some(_): []
      None: []
    end
  end
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
      var after = without_key(without_end(without_job(board, held.number), held.number), held)
      after = if held.state == Scheduled: without_wait(after, held.number) else: after
      after.counts = counted(board.counts, held.state, false)
      Decision(board: after, outcome: Removed, writes: [(id, None)], shelved: [])
    None: unshelved(board, id)
  end
end

# An archived job deleted: out of the archive, its key free, and a tombstone in the archive, which
# also keeps a stale live record of the job from coming back at the next open.
fn unshelved(board: Board, id: String) : Decision
  case shelf_at(board, id)
    Some(held):
      after = without_key(without_shelf_job(board, held.number), held)
      Decision(board: after, outcome: Removed, writes: [], shelved: [(id, None)])
    None: answered(board, Missing)
  end
end

# The value an archive keeps under a deleted job's id.
fn tombstone?(value: String) : Bool
  value == "deleted"
end

# The board with archive changes applied that are on disk though the batch they came in was not:
# each archived record moved off the live board, and each deleted id out of the archive.
fn shelf_applied(board: Board, changes: List((String, Option(String)))) : Board
  changes.reduce(board, fn(so_far, c) shelf_change(so_far, c) end)
end

fn shelf_change(board: Board, change: (String, Option(String))) : Board
  case change.1
    Some(record):
      case decoded(record)
        Some(held) if held.archived_at is Some(_): shelved_into(board, held)
        Some(_): board
        None: board
      end
    None:
      case shelf_at(board, change.0)
        Some(held): without_key(without_shelf_job(board, held.number), held)
        None: board
      end
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
        writes: [(id_of(number), Some(shown(lease)))], shelved: [])
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
      var after = with_end(without_lease(with_job(board, after_job), held.number), after_job)
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
      Decision(board: after, outcome: Found(job: after_job), writes: [(id, Some(shown(after_job)))],
        shelved: [])
    None: answered(board, on_shelf(board, id))
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
      var after = without_end(with_job(board, back), held.number)
      after.counts = recounted(board.counts, Dead, Queued)
      after.orders = after.orders.set(held.queue,
        with_back(after.orders.get(held.queue) or no_order(), [held.number]))
      Decision(board: after, outcome: Found(job: back), writes: [(id, Some(shown(back)))],
        shelved: [])
    None: answered(board, on_shelf(board, id))
  end
end

# A leased job handed by the worker that holds a live lease on it to another worker, its lease end
# and tries kept; 409 for anyone else, and the job as it is when the worker hands it to itself.
fn passed_on(board: Board, worker: String, id: String, to: String, now: Time) : Decision
  case job_at(board, id)
    Some(held):
      if !holds?(held, worker, now)
        return answered(board, Conflict(reason: "#{id} is not leased to this worker"))
      end
      return answered(board, Found(job: held)) if to == worker
      if !worker?(to)
        return answered(board, Unavailable(reason: "#{to} is not a worker a lease can go to"))
      end
      next = handed_off(held, worker, to, now)
      Decision(board: with_job(board, next), outcome: Found(job: next),
        writes: [(id, Some(shown(next)))], shelved: [])
    None: answered(board, on_shelf(board, id))
  end
end

# A queue renamed: 404 when `from` holds no job, live or archived, and 409 when `to` holds one,
# which also covers `to` equal to `from`; otherwise the rename as a pure step, and one record for
# the log naming the two queues and the id the next created job will take, so a replay moves no job
# numbered from it on. Since `to` holds no job, no key in it can meet one of `from`'s.
fn renaming(board: Board, from: String, to: String) : Decision
  if !queue?(from) or !queue?(to)
    return answered(board, Unavailable(reason: "a rename names two queues"))
  end
  if !holds_queue?(board, from)
    return answered(board, Absent(reason: "no such queue #{from}"))
  end
  return answered(board, Conflict(reason: "#{to} exists")) if holds_queue?(board, to)
  step = relabeled(board, from, to)
  number = board.marks + 1
  var after = step.0
  after.marks = number
  after.moves = board.moves.push(Move(number: number, from: from, to: to,
    next_id: Some(board.next)))
  Decision(board: after, outcome: Renamed(queue: to, moved: step.1),
    writes: [(rename_key(number), Some(rename_record(from, to, board.next)))], shelved: [])
end

# The archived jobs older than `older_than_ms` pruned: none removed writes nothing, and otherwise
# one record for the log naming the cutoff and the count, never one per job.
fn pruning(board: Board, older_than_ms: UInt64, now: Time) : Decision
  if !age?(older_than_ms)
    return answered(board, Unavailable(reason: "a prune's age is 1000 ms or more"))
  end
  step = pruned(board, older_than_ms, now)
  return answered(board, Cleared(pruned: 0, remaining: board.shelved)) if step.1.size == 0
  number = board.marks + 1
  cut = Cut(number: number, cutoff: cutoff_of(older_than_ms, now), pruned: step.1.size)
  var after = step.0
  after.marks = number
  after.cuts = board.cuts.push(cut)
  Decision(board: after, outcome: Cleared(pruned: step.1.size, remaining: after.shelved),
    writes: [(prune_key(number), Some(prune_record(cut)))], shelved: [])
end

# A prune's age: at least a second, and at most a hundred years, so its cutoff is a time.
fn age?(ms: UInt64) : Bool
  ms >= 1_000 and ms <= 3_153_600_000_000
end

# The cutoff of a prune at `now`: an archived job whose archived_at is at or before it is pruned.
fn cutoff_of(older_than_ms: UInt64, now: Time) : Time
  to_ms(now - older_than_ms.to_i64.ms)
end

# Whether an archived job is old enough for a prune whose cutoff is `cutoff`.
fn aged?(held: Job, cutoff: Time) : Bool
  case held.archived_at
    Some(at): at <= cutoff
    None: false
  end
end

# The prune as a pure step over the archive and the key map: every archived job whose archived_at is
# at least `older_than_ms` before now leaves the archive, and its key is free in its queue; nothing
# live changes. Gives the board and the jobs removed.
fn pruned(board: Board, older_than_ms: UInt64, now: Time) : (Board, List(Job))
  requires age?(older_than_ms)
  ensures result.0.jobs == board.jobs and result.0.counts == board.counts
  ensures result.1.all?(fn(j) aged?(j, cutoff_of(older_than_ms, now)) end)
  ensures keys_freed?(result.0, result.1)
  ensures result.0.shelved + result.1.size == board.shelved

  cutoff = cutoff_of(older_than_ms, now)
  gone = all_shelved(board).filter(fn(j) aged?(j, cutoff) end).sort_by(fn(j) j.number end)
  after = gone.reduce(board, fn(b, j) cut_from(b, j, cutoff) end)
  (after, gone)
end

# One archived job pruned: out of the archive, and its key free when the key still names it.
fn cut_from(board: Board, held: Job, cutoff: Time) : Board
  removed = Pruned(number: held.number, live: job_of(board, held.number) is Some(_),
    archived_at: held.archived_at or cutoff, cutoff: cutoff)
  after = without_own_key(without_shelf_job(board, held.number), held)
  if removed.live: board else: after
end

# Whether no key names any of the jobs any more.
fn keys_freed?(board: Board, gone: List(Job)) : Bool
  gone.all?(fn(j) key_free?(board, j) end)
end

# Whether no key names the job any more.
fn key_free?(board: Board, held: Job) : Bool
  case held.key
    Some(key): keyed_number(board, held.queue, key) != Some(held.number)
    None: true
  end
end

# The board with the job's key free, when it names this job and not a later one.
fn without_own_key(board: Board, held: Job) : Board
  case held.key
    Some(key):
      if keyed_number(board, held.queue, key) == Some(held.number)
        without_key(board, held)
      else
        board
      end
    None: board
  end
end

# The archive as GET /archive shows it: how many jobs, the oldest archived_at, and the file's bytes,
# which the queue fills in once the batch is on disk.
fn shelf_of(board: Board) : Outcome
  Shelf(archived: board.shelved, oldest: oldest_shelved(board), bytes: 0)
end

# The earliest archived_at in the archive, or None when it holds no job.
fn oldest_shelved(board: Board) : Option(Time)
  all_shelved(board).flat_map(fn(j) times_of(j.archived_at) end).min
end

fn times_of(at: Option(Time)) : List(Time)
  case at
    Some(t): [t]
    None: []
  end
end

# Whether a queue holds a job in any state, live or archived.
fn holds_queue?(board: Board, name: String) : Bool
  all_jobs(board).any?(fn(j)
    j.queue == name
  end) or all_shelved(board).any?(fn(j) j.queue == name end)
end

# The rename as a pure step over the board and its key map: every job in `from`, live or archived,
# is in `to`, its key names it under `to` and is free under `from`, `from`'s order and fresh
# positions are `to`'s, and nothing else changes, leases and counts included. Gives the board and
# how many jobs moved.
fn relabeled(board: Board, from: String, to: String) : (Board, UInt64)
  requires from != to
  requires !holds_queue?(board, to)
  ensures !holds_queue?(result.0, from)
  ensures result.0.counts == board.counts and result.0.shelved == board.shelved
  ensures all_jobs(result.0).size == all_jobs(board).size

  live = all_jobs(board).filter(fn(j) j.queue == from end)
  shelf = all_shelved(board).filter(fn(j) j.queue == from end)
  var after = live.reduce(board, fn(b, j) relabeled_live(b, j, from, to) end)
  after = shelf.reduce(after, fn(b, j) relabeled_shelf(b, j, from, to) end)
  after.orders = moved_order(board.orders, from, to)
  after.fresh = moved_fresh(board.fresh, from, to)
  (after, live.size + shelf.size)
end

fn relabeled_live(board: Board, held: Job, from: String, to: String) : Board
  next = relabel(held, from, to)
  with_key(with_job(without_key(board, held), next), next)
end

fn relabeled_shelf(board: Board, held: Job, from: String, to: String) : Board
  next = relabel(held, from, to)
  at = page_of(held.number)
  var after = without_key(board, held)
  after.shelf = after.shelf.set(at, (after.shelf.get(at) or Map.new()).set(held.number, next))
  with_key(after, next)
end

# The job in `to`, if it was in `from`.
fn relabel(held: Job, from: String, to: String) : Job
  var next = held
  next.queue = if held.queue == from: to else: held.queue
  moved = Relabeled(number: held.number, before: held.queue, after: next.queue, from: from, to: to,
    worker_before: held.worker, worker_after: next.worker, until_before: held.lease_until,
    until_after: next.lease_until)
  if moved.after == to: next else: held
end

# The orders with `from`'s under `to`; `to` held no job, so any order it had is spent.
fn moved_order(orders: Map(String, Order), from: String, to: String) : Map(String, Order)
  case orders.get(from)
    Some(order): orders.remove(from).set(to, order)
    None: orders.remove(to)
  end
end

# The fresh positions with `from`'s pages under `to`, and any page `to` had left dropped first, so
# a create into `to` or into `from` later starts on pages of its own.
fn moved_fresh(fresh: Map((String, UInt64), List(UInt64)), from: String,
  to: String) : Map((String, UInt64), List(UInt64))
  pages = fresh.entries
  cleared = pages.filter(fn(e) e.0.0 == to end).reduce(fresh, fn(f, e) f.remove(e.0) end)
  pages.filter(fn(e) e.0.0 == from end).reduce(cleared,
    fn(f, e) f.remove(e.0).set((to, e.0.1), e.1) end)
end

# The key a rename's record is kept under, by its number.
fn rename_key(number: UInt64) : String
  "rename_#{number}"
end

fn rename_record(from: String, to: String, next_id: UInt64) : String
  "{\"from\": #{Json.encode(from)}, \"to\": #{Json.encode(to)}, \"next_id\": #{next_id}}"
end

fn move_record(move: Move) : String
  case move.next_id
    Some(next_id): rename_record(move.from, move.to, next_id)
    None: "{\"from\": #{Json.encode(move.from)}, \"to\": #{Json.encode(move.to)}}"
  end
end

# The key a prune's record is kept under, by its number among the marks.
fn prune_key(number: UInt64) : String
  "prune_#{number}"
end

fn prune_record(cut: Cut) : String
  "{\"cutoff\": #{Json.encode(cut.cutoff)}, \"pruned\": #{cut.pruned}}"
end

# The number in a prune's key: prune_ and digits, no sign and no leading zero.
fn prune_number(key: String) : Option(UInt64)
  return None if !key.starts_with?("prune_") or key.byte_size < 7
  digits = key.slice(6, key.size)
  return None if digits.starts_with?("0")
  digits.to_u64
end

# The rule a prune's record breaks, or None when it is one a prune could have written: a cutoff
# that is a time, and a count of at least one.
fn prune_broken(entry: (String, String)) : Option(String)
  return Some("its key is not prune_ and a number") if prune_number(entry.0) is None
  case Json.decode(entry.1)
    Ok(Object(fields)):
      return Some("its cutoff is not a time") if Time.parse(name_in(fields, "cutoff")) is None
      case fields.get("pruned")
        Some(value):
          count = value.to_i64 or 0
          return Some("its pruned is not a whole number above 0") if count < 1
          None
        None: Some("its pruned is not a whole number above 0")
      end
    Ok(_): Some("is not a prune")
    Error(_): Some("is not a prune")
  end
end

# The prune a record holds, as a list of one, or none when it is not a good one.
fn cuts_in(entry: (String, String)) : List(Cut)
  return [] if !entry.0.starts_with?("prune_") or prune_broken(entry) is Some(_)
  case (prune_number(entry.0), Json.decode(entry.1))
    (Some(number), Ok(Object(fields))):
      cutoff = Time.parse(name_in(fields, "cutoff")) or Time.from_parts(1970, 1, 1, 0, 0, 0)
      count = (fields.get("pruned") or Null).to_i64 or 0
      [Cut(number: number, cutoff: cutoff, pruned: count.to_u64)]
    _: []
  end
end

# The number in a rename's key: rename_ and digits, no sign and no leading zero.
fn rename_number(key: String) : Option(UInt64)
  return None if !key.starts_with?("rename_") or key.byte_size < 8
  digits = key.slice(7, key.size)
  return None if digits.starts_with?("0")
  digits.to_u64
end

# The rule a rename's record breaks, or None when it is one a rename could have written.
fn rename_broken(entry: (String, String)) : Option(String)
  return Some("its key is not rename_ and a number") if rename_number(entry.0) is None
  case Json.decode(entry.1)
    Ok(Object(fields)):
      from = name_in(fields, "from")
      to = name_in(fields, "to")
      return Some("its from is not 1 to 64 letters, digits, - or _") if !queue?(from)
      return Some("its to is not 1 to 64 letters, digits, - or _") if !queue?(to)
      return Some("it renames #{from} to itself") if from == to
      if fields.has?("next_id") and next_id_in(fields) is None
        return Some("its next_id is not a whole number above 0")
      end
      None
    Ok(_): Some("is not a rename")
    Error(_): Some("is not a rename")
  end
end

fn name_in(fields: Map(String, Json), name: String) : String
  case fields.get(name)
    Some(String(text)): text
    Some(_): ""
    None: ""
  end
end

# A rename record's next_id: a whole number above 0.
fn next_id_in(fields: Map(String, Json)) : Option(UInt64)
  value = try fields.get("next_id")
  whole = try value.to_i64
  return None if whole < 1
  Some(whole.to_u64)
end

# The rename a record holds, as a list of one, or none when it is not a good one. A record the
# previous version wrote has no next_id: it applies to every job the records before it hold, which
# is every job numbered below the highest id in the folder when it was written.
fn moves_in(entry: (String, String)) : List(Move)
  return [] if !entry.0.starts_with?("rename_") or rename_broken(entry) is Some(_)
  case (rename_number(entry.0), Json.decode(entry.1))
    (Some(number), Ok(Object(fields))):
      [Move(number: number, from: name_in(fields, "from"), to: name_in(fields, "to"),
        next_id: next_id_in(fields))]
    _: []
  end
end

# A folder's records with the marks applied: each job record, live or archived, in the queue the
# renames written after it put it in, in order, each archived one the prunes written after it
# removed left out, and no mark left among the live ones; the ids of the archived jobs pruned; the
# mark count, the highest of the marks kept, of the ones the records say they have seen, and of the
# count the previous version kept; the renames; and the prunes.
struct Folded
  live: List((String, String))
  shelf: List((String, String))
  pruned: Map(String, Bool)
  marks: UInt64
  moves: List(Move)
  cuts: List(Cut)
end

fn folded(entries: List((String, String)), shelf: List((String, String))) : Folded
  moves = entries.flat_map(fn(e) moves_in(e) end).sort_by(fn(m) m.number end)
  cuts = entries.flat_map(fn(e) cuts_in(e) end).sort_by(fn(c) c.number end)
  kept = case entries.find(fn(e) e.0 == "renames" end)
    Some(e): e.1.to_u64 or 0
    None: 0
  end
  last = max_of((moves.last or no_move()).number, (cuts.last or no_cut()).number)
  seen = max_of(highest_seen(entries), highest_seen(shelf))
  count = max_of(max_of(kept, last), seen)
  live = entries.filter(fn(e) !mark_key?(e.0) end)
  if moves.size == 0 and cuts.size == 0
    return Folded(live: live, shelf: shelf, pruned: Map.new(), marks: count, moves: [], cuts: [])
  end
  gone = shelf.filter(fn(e) cut_by?(e, cuts) end)
  kept_shelf = shelf.filter(fn(e) !cut_by?(e, cuts) end)
  Folded(live: live.map(fn(e) refolded(e, moves) end),
    shelf: kept_shelf.map(fn(e) refolded(e, moves) end),
    pruned: gone.reduce(Map.new(), fn(ids, e) ids.set(e.0, true) end), marks: count, moves: moves,
    cuts: cuts)
end

fn no_move() : Move
  Move(number: 0, from: "", to: "", next_id: None)
end

fn no_cut() : Cut
  Cut(number: 0, cutoff: Time.from_parts(1970, 1, 1, 0, 0, 0), pruned: 0)
end

# Whether a live entry is the log's own and not a job's: the ids counter, the count the previous
# version kept, or a mark.
fn mark_key?(key: String) : Bool
  key == "renames" or key.starts_with?("rename_") or key.starts_with?("prune_")
end

# The most marks any record says it has seen; only a record that carries the count is decoded.
fn highest_seen(entries: List((String, String))) : UInt64
  entries.filter(fn(e) e.1.contains?("\"renames\": ") end).map(fn(e) renames_of(e.1) end).max or 0
end

# Whether a prune written after an archived record removes it: its archived_at at or before the
# cutoff of a prune the record has not seen.
fn cut_by?(entry: (String, String), cuts: List(Cut)) : Bool
  return false if cuts.size == 0 or !entry.0.starts_with?("j_") or tombstone?(entry.1)
  seen = renames_of(entry.1)
  later = cuts.filter(fn(c) c.number > seen end)
  return false if later.size == 0
  case decoded(entry.1)
    Some(held): later.any?(fn(c) aged?(held, c.cutoff) end)
    None: false
  end
end

# One record with the renames it has not seen applied, in order: a rename moves a job numbered
# below its next_id that is in its `from` at that point.
fn refolded(entry: (String, String), moves: List(Move)) : (String, String)
  return entry if moves.size == 0 or !entry.0.starts_with?("j_") or tombstone?(entry.1)
  seen = renames_of(entry.1)
  later = moves.filter(fn(m) m.number > seen end)
  return entry if later.size == 0
  case decoded(entry.1)
    Some(held):
      queue = later.reduce(held.queue, fn(q, m) moved_by(q, held.number, m) end)
      return entry if queue == held.queue
      var next = held
      next.queue = queue
      (entry.0, shown(next))
    None: entry
  end
end

# The queue a job numbered `number` in `queue` is in after the rename.
fn moved_by(queue: String, number: UInt64, move: Move) : String
  below = case move.next_id
    Some(next_id): number < next_id
    None: true
  end
  if queue == move.from and below: move.to else: queue
end

# The first record a folder holds that no request could have left, in key order, the live log's
# before the archive's: its key, named `archive <key>` for the archive's, and the rule it breaks,
# None when every record is one. Every command that opens a folder checks it against this, so a
# board is built only from records the API could have written. A live record of a job the archive
# holds is stale, since the archive's record wins, and a key that names two jobs in one queue is
# broken at the second.
fn ill_formed(entries: List((String, String)),
  shelf: List((String, String))) : Option((String, String))
  sorted = entries.sort_by(fn(e) e.0 end)
  held = shelf.filter(fn(e) !tombstone?(e.1) end).sort_by(fn(e) e.0 end)
  top = max_of(highest(sorted), highest(shelf))
  if sorted.find(fn(e) entry_broken(e, top) is Some(_) end) is Some(bad)
    return Some((bad.0, entry_broken(bad, top) or ""))
  end
  if held.find(fn(e) archive_broken(e.0, e.1) is Some(_) end) is Some(bad)
    return Some(("archive #{bad.0}", archive_broken(bad.0, bad.1) or ""))
  end
  if shared_mark(sorted) is Some(clash)
    return Some(clash)
  end
  fold = folded(entries, shelf)
  twice(fold.live, fold.shelf, fold.pruned)
end

# The first mark whose number another mark already has: renames and prunes are numbered in one run.
fn shared_mark(sorted: List((String, String))) : Option((String, String))
  numbers = sorted.flat_map(fn(e) mark_number(e.0) end)
  seen = numbers.reduce((Map.new(), [("", "")].take(0)), fn(acc, n) marked_once(acc, n) end)
  seen.1.first
end

fn mark_number(key: String) : List((String, UInt64))
  case (rename_number(key), prune_number(key))
    (Some(n), _): [(key, n)]
    (None, Some(n)): [(key, n)]
    (None, None): []
  end
end

fn marked_once(acc: (Map(UInt64, String), List((String, String))),
  mark: (String, UInt64)) : (Map(UInt64, String), List((String, String)))
  case acc.0.get(mark.1)
    Some(first): (acc.0, acc.1.push((mark.0, "its number is #{first}'s too")))
    None: (acc.0.set(mark.1, mark.0), acc.1)
  end
end

# The first job whose key another job in its queue already has, by number, the archive's taking
# the place of any live record of the same job.
fn twice(entries: List((String, String)), shelf: List((String, String)),
  pruned: Map(String, Bool)) : Option((String, String))
  archived = shelf.flat_map(fn(e) job_under(e) end)
  held = shelf.reduce(pruned, fn(ids, e) ids.set(e.0, true) end)
  live = entries.flat_map(fn(e) job_under(e) end).filter(fn(j) !held.has?(id_of(j.number)) end)
  jobs = live.concat(archived).filter(fn(j) j.key is Some(_) end).sort_by(fn(j) j.number end)
  seen = jobs.reduce((Map.new(), [("", "")].take(0)), fn(acc, j) keyed_once(acc, j) end)
  seen.1.first
end

fn keyed_once(acc: (Map((String, String), UInt64), List((String, String))),
  held: Job) : (Map((String, String), UInt64), List((String, String)))
  pair = (held.queue, held.key or "")
  case acc.0.get(pair)
    Some(first):
      why = "its key #{pair.1} is #{id_of(first)}'s too"
      (acc.0, acc.1.push((id_of(held.number), why)))
    None: (acc.0.set(pair, held.number), acc.1)
  end
end

fn entry_broken(entry: (String, String), top: UInt64) : Option(String)
  return ids_broken(entry.1, top) if entry.0 == "ids"
  return renames_broken(entry.1) if entry.0 == "renames"
  return rename_broken(entry) if entry.0.starts_with?("rename_")
  return prune_broken(entry) if entry.0.starts_with?("prune_")
  rule_broken(entry.0, entry.1)
end

# The rename count the previous version kept is a number. It is only ever a floor: the marks a
# folder holds and the counts its records carry are what number the next mark, so a count below the
# last rename, which that version wrote after a compaction and one more rename, is no fault.
fn renames_broken(value: String) : Option(String)
  if value.to_u64 is Some(_): None else: Some("is not a number")
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

# The board a store's records and its archive's hold: every archived job in the archive, every
# other job on the board, the reserved numbers, and the next number above every job and every
# reservation; None when a record is not the job its key names. A job in both files was archived
# by a move a kill cut short: the archive's record wins, and the live one is left out, as it is
# when the archive holds the job's tombstone.
#
# A rename record applies to the job records written before it, live and archived, and a prune
# record to the archive records written before it, as `folded` says: a pruned job is in neither
# file, and a stale live record of it stays gone. A mark record that is not one is None too.
fn rebuilt(entries: List((String, String)), shelf_entries: List((String, String)),
  started: Time) : Option(Board)
  fold = folded(entries, shelf_entries)
  renamings = entries.filter(fn(e) e.0.starts_with?("rename_") end)
  return None if renamings.any?(fn(e) rename_broken(e) is Some(_) end)
  prunings = entries.filter(fn(e) e.0.starts_with?("prune_") end)
  return None if prunings.any?(fn(e) prune_broken(e) is Some(_) end)
  shelf = fold.shelf
  floor = case fold.live.find(fn(e) e.0 == "ids" end)
    Some(e): try e.1.to_u64
    None: 1
  end
  held = fold.live.filter(fn(e) e.0 != "ids" end)
  jobs = held.flat_map(fn(e) job_under(e) end)
  kept = shelf.filter(fn(e) !tombstone?(e.1) end)
  gone = shelf.filter(fn(e) tombstone?(e.1) end).reduce(Map.new(),
    fn(ids, e) ids.set(e.0, true) end)
  archived = kept.flat_map(fn(e) job_under(e) end)
  return None if jobs.size != held.size or archived.size != kept.size
  return None if !archived.all?(fn(j) j.archived_at is Some(_) end)
  sorted = jobs.sort_by(fn(j) j.number end)
  top = max_of(max_of(numbers_top(sorted), numbers_top(archived.sort_by(fn(j) j.number end))),
    highest(fold.pruned.keys.map(fn(k) (k, "") end)))
  start = board(started, max_of(top + 1, max_of(floor, 1)))
  shelved_first = archived.reduce(start, fn(so_far, j) shelved_into(so_far, j) end)
  live = sorted.filter(fn(j)
    shelf_job(shelved_first,
      j.number) is None and !gone.has?(id_of(j.number)) and !fold.pruned.has?(id_of(j.number))
  end)
  var built = live.reduce(shelved_first, fn(so_far, j) placed(so_far, j) end)
  built.reserved = max_of(floor, built.next)
  built.marks = fold.marks
  built.moves = fold.moves
  built.cuts = fold.cuts
  whole = built
  placements = live.map(fn(j)
    Placement(number: j.number, live: true, shelved: shelf_job(whole, j.number) is Some(_))
  end)
  return None if placements.any?(fn(p) p.live and p.shelved end)
  Some(whole)
end

fn numbers_top(sorted: List(Job)) : UInt64
  case sorted.last
    Some(j): j.number
    None: 0
  end
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
  var after = with_key(with_end(with_job(waiting, held), held), held)
  after.counts = counted(board.counts, held.state, true)
  after
end

# The board as the changes that write it whole: the reserved numbers, the rename and prune records
# the board still keeps, then every job's record by number, in its current queue and carrying the
# count of every mark, so no mark applies to it again. The marks are kept because the archive's
# records may still need them; no count is kept, since the marks and the records carry it.
fn snapshot(board: Board) : List((String, Option(String)))
  ensures result.size >= all_jobs(board).size + 1
  ensures board.moves.size == 0 implies result.all?(fn(w) !w.0.starts_with?("rename_") end)
  ensures board.cuts.size == 0 implies result.all?(fn(w) !w.0.starts_with?("prune_") end)

  moves = board.moves.map(fn(m) (rename_key(m.number), Some(move_record(m))) end)
  cuts = board.cuts.map(fn(c) (prune_key(c.number), Some(prune_record(c))) end)
  [("ids", Some("#{board.reserved}"))].concat(moves).concat(cuts).concat(all_jobs(board).map(fn(j)
    (id_of(j.number), Some(tagged(shown(j), board.marks)))
  end))
end

# The board once every mark is folded into the records that write it whole: no rename or prune
# record left to keep, and no count, so the records it writes carry none and the next mark is the
# first.
fn folded_in(board: Board) : Board
  var after = board
  after.moves = []
  after.cuts = []
  after.marks = 0
  after
end

# The archive as the changes that write it whole: every archived job's record by number, in its
# current queue, the pruned ones gone, and carrying the count of every mark.
fn shelf_snapshot(board: Board) : List((String, Option(String)))
  ensures result.size == board.shelved

  all_shelved(board).map(fn(j) (id_of(j.number), Some(tagged(shown(j), board.marks))) end)
end

# Every job's record, by number, as the store holds them.
fn records(board: Board) : List(String)
  all_jobs(board).map(fn(j) shown(j) end)
end

# Every archived job's record, by number, as the archive holds them.
fn shelf_records(board: Board) : List(String)
  all_shelved(board).map(fn(j) shown(j) end)
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
  Making(queue: queue, key: None, payload: payload, max_tries: max_tries, backoff_ms: 0,
    delay_ms: 0)
end

fn making(queue: String, payload: String, max_tries: UInt64, backoff_ms: UInt64,
  delay_ms: UInt64) : Making
  Making(queue: queue, key: None, payload: payload, max_tries: max_tries, backoff_ms: backoff_ms,
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
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Renamed(queue: _,
      moved: _) | Cleared(pruned: _, remaining: _) | Shelf(archived: _, oldest: _,
      bytes: _) | Absent(_) | Unavailable(_):
      0
  end
end

fn job_in(decision: Decision) : Option(Job)
  case decision.outcome
    Made(one): Some(one)
    Found(one): Some(one)
    Listed(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Renamed(queue: _,
      moved: _) | Cleared(pruned: _, remaining: _) | Shelf(archived: _, oldest: _,
      bytes: _) | Absent(_) | Unavailable(_):
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

fn keyed(queue: String, key: String) : Making
  var made = plain(queue, key, 2)
  made.key = Some(key)
  made
end

fn create_keyed(b: Board, queue: String, key: String, now: Time) : Decision
  decide(b, call("p", Create(making: keyed(queue, key))), now)
end

# The board with j_1 made under `key` in queue a, leased, and acked at start.
fn one_done(key: String) : Board
  made = create_keyed(board(start(), 1), "a", key, start())
  held = lease_by(made.board, "w1", "a", 1_000, start())
  decide(held.board, call("w1", Ack(id: "j_1")), start()).board
end

# The store a run of decisions leaves: each write applied in order, as the log's replay applies its
# lines.
fn logged(store: Map(String, String), decision: Decision) : Map(String, String)
  decision.writes.reduce(store, fn(held, w) kept_in(held, w) end)
end

fn kept_in(store: Map(String, String), change: (String, Option(String))) : Map(String, String)
  case change.1
    Some(value): store.set(change.0, value)
    None: store.remove(change.0)
  end
end

fn hand(b: Board, worker: String, id: String, to: String, now: Time) : Decision
  decide(b, call(worker, Handoff(id: id, to: to)), now)
end

fn rename(b: Board, from: String, to: String, now: Time) : Decision
  decide(b, call("op", Rename(queue: from, to: to)), now)
end

# Whether a lookup by the queue and key finds one job.
fn keyed_under?(b: Board, queue: String, key: String, now: Time) : Bool
  found = decide(b, call("p", Listing(queue: Some(queue), state: None, key: Some(key))), now)
  case found.outcome
    Listed(jobs): jobs.size == 1
    Made(_) | Found(_) | Removed | Missing | Conflict(_) | Empty | Healthy(_) | Tallied(_) | Renamed(queue: _,
      moved: _) | Cleared(pruned: _, remaining: _) | Shelf(archived: _, oldest: _,
      bytes: _) | Absent(_) | Unavailable(_):
      false
  end
end

fn queue_in(decision: Decision) : String
  case job_in(decision)
    Some(one): one.queue
    None: ""
  end
end

# The board a rename test starts from, at `now`: in queue a, j_1 done and archived (key k1), j_2 dead
# (key k2), j_3 leased to w1 (key k3), j_4 queued, j_5 scheduled; in queue b, j_6 queued with key k1.
fn busy(now: Time) : Board
  var b = ["k1", "k2", "k3"].reduce(retaining(board(start(), 1), 1_000),
    fn(so_far, key) create_keyed(so_far, "a", key, start()).board end)
  b = decide(b, call("p", Create(making: plain("a", "four", 2))), start()).board
  b = decide(b, call("p", Create(making: making("a", "five", 2, 0, 3_600_000))), start()).board
  b = create_keyed(b, "b", "k1", start()).board
  b = decide(lease_by(b, "w1", "a", 100, start()).board, call("w1", Ack(id: "j_1")), start()).board
  later = start() + 500.ms
  b = decide(lease_by(b, "w1", "a", 100, later).board, call("w1", Fail(id: "j_2", reason: "x")),
    later).board
  b = decide(lease_by(b, "w1", "a", 100, later).board, call("w1", Fail(id: "j_2", reason: "y")),
    later).board
  b = lease_by(b, "w1", "a", 3_600_000, later).board
  shelved(b, now).board
end

# In queue a with a retention of a second: j_1 (key k1) done at start and archived at start + 2 s,
# j_2 (key k2) done at start + 5 s and archived at start + 7 s, and j_3 (key k3) queued, live.
fn aging() : Board
  var b = ["k1", "k2", "k3"].reduce(retaining(board(start(), 1), 1_000),
    fn(so_far, key) create_keyed(so_far, "a", key, start()).board end)
  b = decide(lease_by(b, "w1", "a", 100, start()).board, call("w1", Ack(id: "j_1")), start()).board
  b = shelved(b, start() + 2_000.ms).board
  later = start() + 5_000.ms
  b = decide(lease_by(b, "w1", "a", 100, later).board, call("w1", Ack(id: "j_2")), later).board
  shelved(b, start() + 7_000.ms).board
end

# A rename record as the previous version wrote it, with no next_id.
fn without_next_id(entry: (String, String)) : (String, String)
  return entry if !entry.0.starts_with?("rename_")
  (entry.0, entry.1.replace(", \"next_id\": 2}", "}"))
end

fn prune(b: Board, older_than_ms: UInt64, now: Time) : Decision
  decide(b, call("op", Pruning(older_than_ms: older_than_ms)), now)
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
  listing = decide(first.board, call("p", Listing(queue: None, state: Some(Scheduled), key: None)),
    start())
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
  all = decide(b, call("p", Listing(queue: None, state: None, key: None)), start())
  assert all.outcome is Listed(jobs)
  assert jobs.size == 100 and (jobs.first or job(9, plain("q", "", 1), start())).number == 1
  assert jobs.map(fn(j) j.number end) == jobs.map(fn(j) j.number end).sort
  in_b = decide(b, call("p", Listing(queue: Some("b"), state: None, key: None)), start())
  assert in_b.outcome is Listed(bs)
  assert bs.map(fn(j) j.number end) == [1, 107]
  lent_one = lease_by(b, "w", "b", 1_000, start())
  leased_b = decide(lent_one.board,
    call("p", Listing(queue: Some("b"), state: Some(Leased), key: None)), start())
  assert leased_b.outcome is Listed(held)
  assert held.map(fn(j) j.number end) == [1]
  none = decide(lent_one.board, call("p", Listing(queue: Some("c"), state: None, key: None)),
    start())
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
  assert ill_formed(entries, []) is None
  assert ill_formed([], []) is None
  ill = entries.map(fn(e) broken_tries(e, "j_1") end)
  assert ill_formed(ill, []) == Some(("j_1", "a leased job has at least one try"))
  two = ill.push(("j_0", "not a job"))
  assert ill_formed(two, []) == Some(("j_0", "is not a job"))
  assert ill_formed(entries.push(("j_9", "not a job")), []) == Some(("j_9", "is not a job"))
  assert ill_formed(entries.map(fn(e) counter(e, "x") end), []) == Some(("ids", "is not a number"))
  assert ill_formed(entries.map(fn(e) counter(e, "2") end),
    []) == Some(("ids", "the next id is below j_3"))
  assert ill_formed(entries.map(fn(e) counter(e, "3") end), []) is None
  assert ill_formed(records(held).map(fn(r) ("j_9", r) end), []) is Some(named)
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
  assert rebuilt(store_of(cut).reverse, [], start()) is Some(again)
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
  assert rebuilt([("j_1", "not a job")], [], start()) is None
  assert rebuilt([("j_2", records(cut).first or "")], [], start()) is None
  assert rebuilt([], [], start()) is Some(empty)
  assert empty.next == 1
end

test "a board rebuilt from the records the previous version wrote holds every job with its state"
  old_queued = "{\"id\": \"j_1\", \"queue\": \"emails\", \"state\": \"queued\", \"payload\": \"one\", \"attempts\": 0, \"max_attempts\": 3, \"created_at\": \"2026-09-14T09:00:00Z\", \"updated_at\": \"2026-09-14T09:00:00Z\"}"
  old_leased = "{\"id\": \"j_2\", \"queue\": \"emails\", \"state\": \"leased\", \"payload\": \"two\", \"attempts\": 1, \"max_attempts\": 2, \"created_at\": \"2026-09-14T09:01:00Z\", \"updated_at\": \"2026-09-14T09:07:00Z\", \"worker\": \"w-old\", \"lease_until\": \"2026-09-14T09:08:00Z\"}"
  assert rebuilt([("ids", "1000"), ("j_1", old_queued), ("j_2", old_leased)], [],
    start()) is Some(b)
  assert health_of(b, start()) == Counts(queued: 1, scheduled: 0, leased: 1, done: 0, dead: 0,
    archived: 0, uptime_ms: 0, restarts: 0)
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
  assert rebuilt(lines.map(fn(l) (l.0, l.1 or "") end), [], start()) is Some(again)
  assert records(again) == records(lent_one) and again.reserved == lent_one.reserved
end

test "a second create with a key answers the job the key names in every state, and writes nothing"
  first = create_keyed(board(start(), 1), "a", "order-1", start())
  assert first.outcome is Made(made)
  assert made.key == Some("order-1") and number_in(first) == 1
  queued = create_keyed(first.board, "a", "order-1", start())
  assert queued.outcome == Found(job: made) and queued.writes == [] and queued.shelved == []
  assert queued.board.next == first.board.next
  var other = keyed("a", "order-1")
  other.payload = "ignored"
  other.max_tries = 9
  assert decide(first.board, call("p", Create(making: other)), start()).outcome == Found(job: made)
  elsewhere = create_keyed(first.board, "b", "order-1", start())
  assert elsewhere.outcome is Made(second)
  assert second.number == 2
  lent = lease_by(first.board, "w1", "a", 1_000, start())
  assert job_in(create_keyed(lent.board, "a", "order-1", start())) is Some(held)
  assert held.state == Leased and held.worker == Some("w1")
  done = decide(lent.board, call("w1", Ack(id: "j_1")), start())
  assert job_in(create_keyed(done.board, "a", "order-1", start())) is Some(finished)
  assert finished.state == Done
  dead = decide(lent.board, call("w1", Fail(id: "j_1", reason: "x")), start())
  assert job_in(dead) is Some(again)
  assert again.state == Queued
  later = decide(first.board, call("p", Create(making: making("a", "l", 1, 0, 5_000))), start())
  var waiting_key = making("a", "l", 1, 0, 5_000)
  waiting_key.key = Some("later")
  scheduled = decide(later.board, call("p", Create(making: waiting_key)), start())
  assert job_in(create_keyed(scheduled.board, "a", "later", start())) is Some(waits)
  assert waits.state == Scheduled
  one_try = decide(board(start(), 1), call("p", Create(making: keyed("a", "k"))), start())
  spent = lease_by(lease_by(one_try.board, "w1", "a", 100, start()).board, "w2", "a", 100,
    start() + 100.ms)
  gone = decide(spent.board, call("w2", Fail(id: "j_1", reason: "y")), start() + 150.ms)
  assert job_in(create_keyed(gone.board, "a", "k", start() + 150.ms)) is Some(ended)
  assert ended.state == Dead
end

test "a deleted job frees its key, and the next create with it makes a new job"
  first = create_keyed(board(start(), 1), "a", "k", start())
  gone = decide(first.board, call("p", Remove(id: "j_1")), start())
  assert gone.outcome == Removed
  again = create_keyed(gone.board, "a", "k", start())
  assert again.outcome is Made(fresh)
  assert fresh.number == 2 and fresh.key == Some("k")
  assert job_in(create_keyed(again.board, "a", "k", start())) == Some(fresh)
end

test "a listing by key finds the one job its queue and key name, archived or not"
  first = create_keyed(board(start(), 1), "a", "k", start())
  assert first.outcome is Made(made)
  by_key = decide(first.board, call("p", Listing(queue: Some("a"), state: None, key: Some("k"))),
    start())
  assert by_key.outcome == Listed(jobs: [made])
  other = call("p", Listing(queue: Some("b"), state: None, key: Some("k")))
  assert decide(first.board, other, start()).outcome == Listed(jobs: [])
  wrong_state = call("p", Listing(queue: Some("a"), state: Some(Done), key: Some("k")))
  assert decide(first.board, wrong_state, start()).outcome == Listed(jobs: [])
  later = start() + 2_000.ms
  moved = decide(retaining(one_done("k"), 1_000),
    call("p", Listing(queue: Some("a"), state: None, key: Some("k"))), later)
  assert moved.outcome is Listed(found)
  assert found.size == 1 and (found.first or made).archived_at == Some(later)
end

test "the archive move takes each done or dead job at least retain_ms old, and nothing younger"
  b = retaining(one_done("k"), 1_000)
  assert health_of(b, start()).done == 1
  young = shelved(b, start() + 999.ms)
  assert young.writes == [] and young.shelved == [] and records(young.board) == records(b)
  assert decide(b, call("", Health), start() + 999.ms).writes == []
  now = start() + 1_000.ms
  moved = shelved(b, now)
  assert moved.writes == [("j_1", None)]
  assert moved.shelved.map(fn(w) w.0 end) == ["j_1"]
  assert records(moved.board) == [] and shelf_records(moved.board).size == 1
  assert (moved.shelved.first or ("", None)).1 == shelf_records(moved.board).first
  counts = health_of(moved.board, now)
  assert counts.done == 0 and counts.archived == 1
  assert decide(moved.board, call("p", Tallying), now).outcome == Tallied(queues: [])
  assert decide(moved.board, call("p", Listing(queue: None, state: None, key: None)),
    now).outcome == Listed(jobs: [])
  assert shelved(moved.board, now + 1.minute).shelved == []
  looked_at = decide(b, call("p", Fetch(id: "j_1")), now)
  assert looked_at.writes == moved.writes and looked_at.shelved == moved.shelved
  assert job_in(looked_at) is Some(read)
  assert read.archived_at == Some(now) and read.state == Done
  queued = with_jobs(["q"])
  assert shelved(retaining(queued, 0), start() + 1.minute).shelved == []
end

test "a lease that runs out on its last try is archived once it is old, from the same look"
  made = decide(retaining(board(start(), 1), 1_000), call("p", Create(making: plain("a", "x", 1))),
    start())
  held = lease_by(made.board, "w1", "a", 100, start())
  dead = decide(held.board, call("p", Fetch(id: "j_1")), start() + 100.ms)
  assert job_in(dead) is Some(ended)
  assert ended.state == Dead and dead.shelved == []
  moved = decide(dead.board, call("", Health), start() + 1_100.ms)
  assert moved.shelved.map(fn(w) w.0 end) == ["j_1"] and moved.writes == [("j_1", None)]
  assert moved.outcome is Healthy(counts)
  assert counts.dead == 0 and counts.archived == 1
end

test "an archived job reads by id, refuses a retry or a settle, and a delete frees its key"
  now = start() + 2_000.ms
  moved = shelved(retaining(one_done("k"), 1_000), now).board
  assert decide(moved, call("p", Retry(id: "j_1")),
    now).outcome == Conflict(reason: "j_1 is archived")
  assert decide(moved, call("w1", Ack(id: "j_1")),
    now).outcome == Conflict(reason: "j_1 is archived")
  assert decide(moved, call("p", Retry(id: "j_2")), now).outcome == Missing
  assert job_in(create_keyed(moved, "a", "k", now)) is Some(kept)
  assert kept.archived_at == Some(now)
  gone = decide(moved, call("p", Remove(id: "j_1")), now)
  assert gone.outcome == Removed
  assert gone.writes == [] and gone.shelved == [("j_1", None)]
  after = shelf_applied(moved, gone.shelved)
  assert records(after) == records(gone.board) and shelf_records(after) == []
  assert create_keyed(after, "a", "k", now).outcome is Made(_)
  assert health_of(gone.board, now).archived == 0
  assert decide(gone.board, call("p", Fetch(id: "j_1")), now).outcome == Missing
  assert decide(gone.board, call("p", Remove(id: "j_1")), now).outcome == Missing
  assert create_keyed(gone.board, "a", "k", now).outcome is Made(fresh)
  assert fresh.number == 2
end

test "the key map and the archive are rebuilt from the records, and a job in both files is archived"
  now = start() + 2_000.ms
  moved = shelved(retaining(one_done("k"), 1_000), now)
  two = create_keyed(moved.board, "b", "k2", now)
  live = store_of(two.board)
  shelf = moved.shelved.map(fn(w) (w.0, w.1 or "") end)
  assert rebuilt(live, shelf, now) is Some(again)
  assert records(again) == records(two.board) and shelf_records(again) == shelf_records(two.board)
  assert health_of(again, now) == health_of(two.board, start())
  assert create_keyed(again, "a", "k", now).outcome is Found(old_one)
  assert old_one.number == 1 and old_one.archived_at == Some(now)
  assert create_keyed(again, "b", "k2", now).outcome is Found(_)
  assert create_keyed(again, "b", "k3", now).outcome is Made(_)
  stale = store_of(one_done("k"))
  assert rebuilt(stale, shelf, now) is Some(both)
  assert records(both) == [] and shelf_records(both).size == 1
  assert health_of(both, now).archived == 1 and health_of(both, now).done == 0
  assert ill_formed(stale, shelf) is None
  assert rebuilt(stale, [], now) is Some(unmoved)
  assert shelved(retaining(unmoved, 1_000), now).shelved.size == 1
  assert rebuilt(stale, [("j_1", "not a job")], now) is None
  assert rebuilt(stale, [("j_1", records(one_done("k")).first or "")], now) is None
  assert rebuilt(stale, [("j_1", "deleted")], now) is Some(deleted)
  assert records(deleted) == [] and shelf_records(deleted) == []
  assert create_keyed(deleted, "a", "k", now).outcome is Made(_)
  assert ill_formed(stale, [("j_1", "deleted")]) is None
  assert health_of(deleted, now).archived == 0 and health_of(deleted, now).done == 0
end

test "archive changes on disk from a batch the live log refused move the durable board too"
  now = start() + 2_000.ms
  b = retaining(one_done("k"), 1_000)
  moved = shelved(b, now)
  applied = shelf_applied(b, moved.shelved)
  assert records(applied) == records(moved.board)
  assert shelf_records(applied) == shelf_records(moved.board)
  assert health_of(applied, now) == health_of(moved.board, now)
  assert shelf_applied(applied, moved.shelved) == applied
  assert shelf_applied(b, [("j_1", Some("not a job"))]) == b
  assert shelf_applied(b, [("j_9", None)]) == b
end

test "the ids counter stays above the archive's jobs, and a new board numbers past them"
  now = start() + 2_000.ms
  moved = shelved(retaining(one_done("k"), 1_000), now)
  shelf = moved.shelved.map(fn(w) (w.0, w.1 or "") end)
  assert rebuilt([], shelf, now) is Some(fresh)
  assert fresh.next == 2
  assert ill_formed([("ids", "0")], shelf) == Some(("ids", "the next id is below j_1"))
  assert ill_formed([("ids", "1")], shelf) is None
end

test "an archive with a bad record, or a key on two jobs, is ill-formed by name"
  now = start() + 2_000.ms
  moved = shelved(retaining(one_done("k"), 1_000), now)
  shelf = moved.shelved.map(fn(w) (w.0, w.1 or "") end)
  queued = shelf.map(fn(e) (e.0, e.1.replace("\"state\": \"done\"", "\"state\": \"queued\"")) end)
  assert ill_formed([], queued) == Some(("archive j_1", "is not a job"))
  bare = records(one_done("k")).map(fn(r) ("j_1", r) end)
  assert ill_formed([], bare) == Some(("archive j_1", "an archived job has an archived_at"))
  assert ill_formed([], [("j_1", "{}")]) == Some(("archive j_1", "is not a job"))
  second = create_keyed(board(start(), 2), "a", "k", start()).board
  assert ill_formed(store_of(second), shelf) == Some(("j_2", "its key k is j_1's too"))
  elsewhere = create_keyed(board(start(), 2), "b", "k", start()).board
  assert ill_formed(store_of(elsewhere), shelf) is None
end

test "a handoff from the holder moves the lease; a stranger, a run-out lease, and an archived job are 409"
  b = with_jobs(["a", "a"])
  lent = lease_by(b, "w1", "a", 1_000, start())
  assert job_in(lent) is Some(held)
  moved = hand(lent.board, "w1", "j_1", "w2", start() + 10.ms)
  assert job_in(moved) is Some(passed)
  assert passed.worker == Some("w2") and passed.lease_until == held.lease_until
  assert passed.tries == held.tries and passed.state == Leased
  assert passed.updated_at == start() + 10.ms
  assert moved.writes == [("j_1", Some(shown(passed)))]
  assert health_of(moved.board, start()) == health_of(lent.board, start())
  stranger = hand(lent.board, "w3", "j_1", "w3", start())
  assert stranger.outcome == Conflict(reason: "j_1 is not leased to this worker")
  assert stranger.writes == []
  assert hand(lent.board, "w1", "j_2", "w2", start()).outcome is Conflict(_)
  assert hand(lent.board, "w1", "j_9", "w2", start()).outcome == Missing
  late = hand(lent.board, "w1", "j_1", "w2", start() + 1_000.ms)
  assert late.outcome is Conflict(_)
  assert late.writes.map(fn(w) w.0 end) == ["j_1"]
  now = start() + 2_000.ms
  archived_one = shelved(retaining(one_done("k"), 1_000), now).board
  assert hand(archived_one, "w1", "j_1", "w2", now).outcome == Conflict(reason: "j_1 is archived")
end

test "a handoff to the holder itself is 200 and changes nothing"
  lent = lease_by(with_jobs(["a"]), "w1", "a", 1_000, start())
  same = hand(lent.board, "w1", "j_1", "w1", start() + 5.ms)
  assert job_in(same) == job_in(lent) and same.writes == [] and same.board == lent.board
end

test "A hands to B, B to C: A and B are 409 from then on, and C acks"
  lent = lease_by(with_jobs(["a"]), "a-1", "a", 1_000, start())
  to_b = hand(lent.board, "a-1", "j_1", "b-1", start())
  to_c = hand(to_b.board, "b-1", "j_1", "c-1", start())
  assert queue_in(to_c) == "a"
  assert job_in(to_c) is Some(held)
  assert held.worker == Some("c-1") and held.tries == 1
  assert decide(to_c.board, call("a-1", Ack(id: "j_1")), start()).outcome is Conflict(_)
  assert decide(to_c.board, call("a-1", Fail(id: "j_1", reason: "x")),
    start()).outcome is Conflict(_)
  assert hand(to_c.board, "a-1", "j_1", "a-1", start()).outcome is Conflict(_)
  assert decide(to_c.board, call("b-1", Ack(id: "j_1")), start()).outcome is Conflict(_)
  assert hand(to_b.board, "a-1", "j_1", "d-1", start()).outcome is Conflict(_)
  done = decide(to_c.board, call("c-1", Ack(id: "j_1")), start())
  assert job_in(done) is Some(finished)
  assert finished.state == Done
  failing = decide(to_c.board, call("c-1", Fail(id: "j_1", reason: "x")), start())
  assert job_in(failing) is Some(back)
  assert back.state == Queued and back.tries == 1
end

test "a handoff is replayed from the log: after a restart the job is leased to the new worker until the same time"
  made = decide(board(start(), 1), call("p", Create(making: plain("a", "x", 2))), start())
  lent = lease_by(made.board, "w1", "a", 60_000, start())
  moved = hand(lent.board, "w1", "j_1", "w2", start() + 1.ms)
  store = logged(logged(logged(Map.new(), made), lent), moved)
  assert rebuilt(store.entries, [], start()) is Some(again)
  assert decide(again, call("p", Fetch(id: "j_1")), start() + 2.ms).outcome is Found(held)
  assert held.worker == Some("w2") and held.lease_until == Some(start() + 60_000.ms)
  assert held.tries == 1
  assert decide(again, call("w1", Ack(id: "j_1")), start() + 2.ms).outcome is Conflict(_)
  assert job_in(decide(again, call("w2", Ack(id: "j_1")), start() + 2.ms)) is Some(done)
  assert done.state == Done
  assert rebuilt(snapshot(moved.board).map(fn(w) (w.0, w.1 or "") end), [], start()) is Some(whole)
  assert records(whole) == records(moved.board)
end

test "a rename moves every job of the queue in every state, archived too, with its key, and leaves the lease alone"
  now = start() + 1_000.ms
  b = busy(now)
  assert decide(b, call("p", Tallying), now).outcome is Tallied(before)
  assert before.map(fn(t) t.name end) == ["a", "b"]
  assert decide(b, call("p", Fetch(id: "j_3")), now).outcome is Found(lent)
  assert lent.state == Leased and lent.worker == Some("w1")
  step = relabeled(b, "a", "c")
  assert step.1 == 5
  done = rename(b, "a", "c", now)
  assert done.outcome == Renamed(queue: "c", moved: 5)
  assert done.writes == [("rename_1", Some("{\"from\": \"a\", \"to\": \"c\", \"next_id\": 7}"))]
  assert done.shelved == [] and done.board.marks == 1
  after = done.board
  assert decide(after, call("p", Tallying), now).outcome is Tallied(queues)
  assert queues.map(fn(t) t.name end) == ["b", "c"]
  assert queues.first == Some(Tally(name: "b", queued: 1, scheduled: 0, leased: 0, done: 0,
    dead: 0))
  assert queues.get(1) == Some(Tally(name: "c", queued: 1, scheduled: 1, leased: 1, done: 0,
    dead: 1))
  assert health_of(after, now) == health_of(b, now)
  assert ["j_1",
    "j_2",
    "j_3",
    "j_4",
    "j_5"].all?(fn(id) queue_in(decide(after, call("p", Fetch(id: id)), now)) == "c" end)
  assert queue_in(decide(after, call("p", Fetch(id: "j_6")), now)) == "b"
  assert decide(after, call("p", Fetch(id: "j_3")), now).outcome is Found(still)
  assert still.worker == lent.worker and still.lease_until == lent.lease_until
  assert still.tries == lent.tries
  assert ["k1", "k2", "k3"].all?(fn(key) keyed_under?(after, "c", key, now) end)
  assert !["k1", "k2", "k3"].any?(fn(key) keyed_under?(after, "a", key, now) end)
  assert job_in(create_keyed(after, "c", "k1", now)) is Some(old_one)
  assert old_one.number == 1 and old_one.archived_at is Some(_)
  assert job_in(create_keyed(after, "b", "k1", now)) is Some(other)
  assert other.number == 6
  in_c = decide(after, call("p", Listing(queue: Some("c"), state: None, key: None)), now)
  assert in_c.outcome is Listed(listed_c)
  assert listed_c.map(fn(j) j.number end) == [2, 3, 4, 5]
  acked = decide(after, call("w1", Ack(id: "j_3")), now)
  assert job_in(acked) is Some(finished)
  assert finished.state == Done and finished.queue == "c"
  assert lease_by(after, "w2", "a", 1_000, now).outcome == Empty
  assert number_in(lease_by(after, "w2", "c", 1_000, now)) == 4
  fresh = create_keyed(after, "a", "k1", now)
  assert fresh.outcome is Made(new_one)
  assert new_one.number == 7 and new_one.queue == "a"
  assert number_in(lease_by(fresh.board, "w2", "a", 1_000, now)) == 7
  assert number_in(lease_by(fresh.board, "w2", "c", 1_000, now)) == 4
end

test "a rename to a queue that holds a job is 409, to itself is 409, and from an empty one is 404"
  now = start() + 1_000.ms
  b = busy(now)
  assert rename(b, "a", "b", now).outcome == Conflict(reason: "b exists")
  assert rename(b, "a", "a", now).outcome == Conflict(reason: "a exists")
  assert rename(b, "zzz", "c", now).outcome == Absent(reason: "no such queue zzz")
  assert rename(b, "a", "b", now).writes == []
  only_archived = shelved(retaining(one_done("k"), 1_000), now).board
  assert rename(only_archived, "a", "b", now).outcome == Renamed(queue: "b", moved: 1)
  assert rename(only_archived, "c", "a", now).outcome == Absent(reason: "no such queue c")
  assert rename(only_archived, "z", "a", now).outcome is Absent(_)
  assert rename(with_jobs(["a"]), "b", "a", now).outcome is Absent(_)
  assert rename(with_jobs(["a", "b"]), "b", "a", now).outcome == Conflict(reason: "a exists")
end

# A key clash cannot happen: a key names one job per queue in the key map, a rename's target holds
# no job in any state (or the rename is 409), so it holds no key, and each of the source's keys
# already named one job there. The key map is moved entry for entry, so the target ends with
# exactly the source's keys and no second job under any of them.
test "a rename never lets a key name two jobs in one queue, since its target holds no key at all"
  now = start() + 1_000.ms
  b = create_keyed(create_keyed(busy(now), "d", "k1", now).board, "d", "k9", now).board
  assert rename(b, "a", "d", now).outcome is Conflict(_)
  gone = decide(decide(b, call("p", Remove(id: "j_7")), now).board, call("p", Remove(id: "j_8")),
    now).board
  moved = rename(gone, "a", "d", now)
  assert moved.outcome == Renamed(queue: "d", moved: 5)
  assert job_in(create_keyed(moved.board, "d", "k1", now)) is Some(one)
  assert one.number == 1
  assert create_keyed(moved.board, "d", "k9", now).outcome is Made(_)
  assert ill_formed(moved.board.jobs.values.flat_map(fn(p)
    p.values
  end).map(fn(j)
    (id_of(j.number), shown(j))
  end), shelf_snapshot(moved.board).map(fn(w) (w.0, w.1 or "") end)) is None
end

test "a rename undone by a rename restores every job and key, and a freed name is used again"
  now = start() + 1_000.ms
  b = busy(now)
  there = rename(b, "a", "c", now)
  back = rename(there.board, "c", "a", now)
  assert back.outcome == Renamed(queue: "a", moved: 5)
  assert records(back.board) == records(b) and shelf_records(back.board) == shelf_records(b)
  assert back.board.marks == 2 and back.board.moves.size == 2
  assert ["k1", "k2", "k3"].all?(fn(key) keyed_under?(back.board, "a", key, now) end)
  assert !["k1", "k2", "k3"].any?(fn(key) keyed_under?(back.board, "c", key, now) end)
  assert number_in(lease_by(back.board, "w2", "a", 1_000, now)) == 4
  assert decide(back.board, call("w1", Ack(id: "j_3")), now).outcome is Found(_)
  reused = decide(there.board, call("p", Create(making: plain("a", "new", 1))), now)
  assert reused.outcome is Made(fresh)
  assert fresh.queue == "a"
  assert rename(reused.board, "c", "a", now).outcome == Conflict(reason: "a exists")
end

test "a replay applies a rename to the records written before it and not to those after, archive included"
  now = start() + 1_000.ms
  b = busy(now)
  first = decide(retaining(board(start(), 1), 1_000), call("p", Create(making: keyed("a", "k1"))),
    start())
  lent = lease_by(first.board, "w1", "a", 100, start())
  acked = decide(lent.board, call("w1", Ack(id: "j_1")), start())
  second = decide(acked.board, call("p", Create(making: keyed("a", "k2"))), start())
  third = decide(second.board, call("p", Create(making: plain("a", "three", 1))), start())
  moved = rename(third.board, "a", "c", now)
  assert moved.shelved.size == 1 and moved.writes.map(fn(w) w.0 end) == ["j_1", "rename_1"]
  after = decide(moved.board, call("p", Create(making: keyed("a", "k1"))), now)
  held = lease_by(after.board, "w2", "c", 1_000, now)
  assert number_in(held) == 2
  assert (held.writes.first or ("",
    None)).1 == Some(tagged(shown(job_in(held) or job(1, plain("q", "", 1), now)), 1))
  decisions = [first, lent, acked, second, third, moved, after, held]
  store = decisions.reduce(Map.new(), fn(s, d) logged(s, d) end)
  shelf = moved.shelved.map(fn(w) (w.0, w.1 or "") end)
  assert shelf.all?(fn(e) e.1.contains?("\"queue\": \"a\"") end)
  assert ill_formed(store.entries, shelf) is None
  assert rebuilt(store.entries, shelf, now) is Some(again)
  assert records(again) == records(held.board)
  assert shelf_records(again) == shelf_records(held.board)
  assert again.marks == 1
  assert queue_in(decide(again, call("p", Fetch(id: "j_1")), now)) == "c"
  assert queue_in(decide(again, call("p", Fetch(id: "j_2")), now)) == "c"
  assert queue_in(decide(again, call("p", Fetch(id: "j_3")), now)) == "c"
  assert queue_in(decide(again, call("p", Fetch(id: "j_4")), now)) == "a"
  assert job_in(create_keyed(again, "c", "k1", now)) is Some(old_one)
  assert old_one.number == 1
  assert number_in(create_keyed(again, "a", "k1", now)) == 4
  twice = rename(again, "c", "a", now)
  assert twice.outcome is Conflict(_)
  out = rename(again, "a", "e", now)
  back = rename(out.board, "c", "a", now)
  assert back.writes.map(fn(w) w.0 end) == ["rename_3"]
  later = [out, back].reduce(store, fn(s, d) logged(s, d) end)
  assert rebuilt(later.entries, shelf, now) is Some(third_time)
  assert records(third_time) == records(back.board)
  assert shelf_records(third_time) == shelf_records(back.board)
  assert queue_in(decide(third_time, call("p", Fetch(id: "j_1")), now)) == "a"
  assert queue_in(decide(third_time, call("p", Fetch(id: "j_4")), now)) == "e"
  assert records(b).size > 0
end

test "a snapshot keeps the renames and no count, and a compacted one keeps neither"
  now = start() + 1_000.ms
  b = busy(now)
  moved = rename(rename(b, "a", "c", now).board, "b", "a", now).board
  lines = snapshot(moved)
  assert lines.map(fn(w) w.0 end).take(3) == ["ids", "rename_1", "rename_2"]
  assert lines.all?(fn(w) w.0 != "renames" end)
  shelf = shelf_snapshot(moved).map(fn(w) (w.0, w.1 or "") end)
  assert shelf.all?(fn(e) renames_of(e.1) == 2 and e.1.contains?("\"queue\": \"c\"") end)
  assert rebuilt(lines.map(fn(w) (w.0, w.1 or "") end), shelf, now) is Some(again)
  assert records(again) == records(moved) and shelf_records(again) == shelf_records(moved)
  assert again.marks == 2
  bare = snapshot(folded_in(moved))
  assert bare.all?(fn(w) !mark_key?(w.0) end)
  assert bare.all?(fn(w) renames_of(w.1 or "") == 0 end)
  plain_shelf = shelf_snapshot(folded_in(moved)).map(fn(w) (w.0, w.1 or "") end)
  assert plain_shelf.all?(fn(e) renames_of(e.1) == 0 end)
  assert rebuilt(bare.map(fn(w) (w.0, w.1 or "") end), plain_shelf, now) is Some(folded_board)
  assert records(folded_board) == records(moved) and folded_board.marks == 0
  assert shelf_records(folded_board) == shelf_records(moved)
  assert rename(folded_board, "c", "f", now).writes.map(fn(w) w.0 end) == ["rename_1"]
  assert rebuilt(bare.map(fn(w) (w.0, w.1 or "") end), shelf, now) is Some(half)
  assert half.marks == 2 and shelf_records(half) == shelf_records(moved)
  assert rename(half, "c", "f", now).writes.map(fn(w) w.0 end) == ["rename_3"]
  assert snapshot(b).size == records(b).size + 1
end

# The generation-five bug: the previous version compacted a folder with renames to a count and no
# rename record, then renamed once more, and refused the folder it had written itself ("the rename
# count is below rename_3"). The count is a floor now, and the marks and records number the next.
test "a folder the previous version compacted and renamed once more opens, and numbers the next mark past both"
  entries = [("ids", "1000"),
    ("renames", "2"),
    ("j_1", tagged(shown(job(1, plain("c", "", 1), start())), 2)),
    ("rename_3", "{\"from\": \"c\", \"to\": \"d\"}")]
  assert ill_formed(entries, []) is None
  assert rebuilt(entries, [], start()) is Some(b)
  assert b.marks == 3
  assert queue_in(decide(b, call("p", Fetch(id: "j_1")), start())) == "d"
  assert rename(b, "d", "e", start()).writes.map(fn(w) w.0 end) == ["rename_4"]
  made = decide(b, call("p", Create(making: plain("c", "new", 1))), start())
  assert queue_in(made) == "c"
end

test "a folder with a rename record that is not one is ill-formed by name"
  entries = [("ids", "1000"), ("j_1", shown(job(1, plain("a", "", 1), start())))]
  good = entries.push(("rename_1", "{\"from\": \"a\", \"to\": \"b\"}"))
  assert ill_formed(good, []) is None
  assert rebuilt(good, [], start()) is Some(b)
  assert queue_in(decide(b, call("p", Fetch(id: "j_1")), start())) == "b"
  bad_to = entries.push(("rename_1", "{\"from\": \"a\", \"to\": \"b c\"}"))
  assert ill_formed(bad_to,
    []) == Some(("rename_1", "its to is not 1 to 64 letters, digits, - or _"))
  assert rebuilt(bad_to, [], start()) is None
  bad_from = entries.push(("rename_1", "{\"to\": \"b\"}"))
  assert ill_formed(bad_from,
    []) == Some(("rename_1", "its from is not 1 to 64 letters, digits, - or _"))
  assert ill_formed(entries.push(("rename_1", "[1]")), []) == Some(("rename_1", "is not a rename"))
  assert ill_formed(entries.push(("rename_1", "{\"from\": \"a\", \"to\": \"a\"}")),
    []) == Some(("rename_1", "it renames a to itself"))
  assert ill_formed(entries.push(("rename_01", "{\"from\": \"a\", \"to\": \"b\"}")),
    []) == Some(("rename_01", "its key is not rename_ and a number"))
  assert ill_formed(good.push(("renames", "x")), []) == Some(("renames", "is not a number"))
  assert ill_formed(good.push(("renames", "0")), []) is None
  assert ill_formed(good.push(("renames", "1")), []) is None
  assert ill_formed(entries.push(("rename_1", "{\"from\": \"a\", \"to\": \"b\", \"next_id\": 0}")),
    []) == Some(("rename_1", "its next_id is not a whole number above 0"))
  assert ill_formed(entries.push(("rename_1",
    "{\"from\": \"a\", \"to\": \"b\", \"next_id\": \"2\"}")),
    []) == Some(("rename_1", "its next_id is not a whole number above 0"))
  clash = good.push(("j_2", shown(job(2, keyed("b", "k"), start())))).push(("j_3",
    shown(job(3, keyed("a", "k"), start()))))
  assert ill_formed(clash, []) == Some(("j_3", "its key k is j_2's too"))
end

test "a prune removes each archived job at least its age old, frees its key, and leaves the rest and every live job alone"
  b = aging()
  now = start() + 10_000.ms
  assert health_of(b, now).archived == 2 and health_of(b, now).queued == 1
  done = prune(b, 5_000, now)
  assert done.outcome == Cleared(pruned: 1, remaining: 1)
  assert done.writes == [("prune_1", Some("{\"cutoff\": \"2026-09-14T10:00:05Z\", \"pruned\": 1}"))]
  assert done.shelved == [] and done.board.marks == 1 and done.board.cuts.size == 1
  after = done.board
  assert decide(after, call("p", Fetch(id: "j_1")), now).outcome == Missing
  assert decide(after, call("p", Fetch(id: "j_2")), now).outcome is Found(kept)
  assert kept.archived_at == Some(start() + 7_000.ms)
  assert records(after) == records(b) and health_of(after, now).queued == 1
  assert health_of(after, now).archived == 1
  assert create_keyed(after, "a", "k1", now).outcome is Made(fresh)
  assert fresh.number == 4
  assert number_in(create_keyed(after, "a", "k2", now)) == 2
  assert number_in(create_keyed(after, "a", "k3", now)) == 3
  assert decide(after, call("p", Archive), now).outcome == Shelf(archived: 1,
    oldest: Some(start() + 7_000.ms), bytes: 0)
  none = prune(after, 5_000, now)
  assert none.outcome == Cleared(pruned: 0, remaining: 1) and none.writes == []
  assert none.board == after
  at_edge = prune(b, 8_000, now)
  assert at_edge.outcome == Cleared(pruned: 1, remaining: 1)
  assert prune(b, 8_001, now).outcome == Cleared(pruned: 0, remaining: 2)
  assert prune(b, 999, now).outcome is Unavailable(_)
  assert decide(board(start(), 1), call("p", Archive), now).outcome == Shelf(archived: 0,
    oldest: None, bytes: 0)
  step = pruned(b, 1_000, now)
  assert step.1.map(fn(j) j.number end) == [1, 2] and step.0.jobs == b.jobs
end

test "a replay applies a prune to the archive records written before it and not after, and a pruned job's stale live record stays gone"
  b = aging()
  now = start() + 10_000.ms
  entries = store_of(b)
  shelf = shelf_snapshot(b).map(fn(w) (w.0, w.1 or "") end)
  done = prune(b, 5_000, now)
  logged_entries = done.writes.reduce(Map.new(), fn(m, w) kept_in(m, w) end)
  live = entries.concat(logged_entries.entries)
  assert ill_formed(live, shelf) is None
  assert rebuilt(live, shelf, now) is Some(again)
  assert records(again) == records(done.board) and shelf_records(again) == shelf_records(done.board)
  assert again.marks == 1 and health_of(again, now).archived == 1
  assert create_keyed(again, "a", "k1", now).outcome is Made(_)
  stale = live.push(("j_1", records(one_done("k1")).first or ""))
  assert rebuilt(stale, shelf, now) is Some(no_stale)
  assert records(no_stale) == records(again)
  old_one = shelf.find(fn(e) e.0 == "j_1" end) or ("", "")
  after_it = shelf.push(("j_9",
    tagged(old_one.1.replace("\"j_1\"", "\"j_9\"").replace("\"k1\"", "\"k9\""), 1)))
  assert rebuilt(live.push(("ids", "1000")), after_it, now) is Some(written_after)
  assert decide(written_after, call("p", Fetch(id: "j_9")), now).outcome is Found(nine)
  assert nine.archived_at == Some(start() + 2_000.ms)
  whole = snapshot(done.board).map(fn(w) (w.0, w.1 or "") end)
  shelf_whole = shelf_snapshot(done.board).map(fn(w) (w.0, w.1 or "") end)
  assert rebuilt(whole, shelf_whole, now) is Some(compacted)
  assert records(compacted) == records(done.board)
  assert shelf_records(compacted) == shelf_records(done.board)
  plain_log = snapshot(folded_in(done.board)).map(fn(w) (w.0, w.1 or "") end)
  plain_shelf = shelf_snapshot(folded_in(done.board)).map(fn(w) (w.0, w.1 or "") end)
  assert plain_log.all?(fn(e) !mark_key?(e.0) end)
  assert rebuilt(plain_log, plain_shelf, now) is Some(folded_board)
  assert shelf_records(folded_board) == shelf_records(done.board) and folded_board.marks == 0
end

test "a rename record's next_id keeps a job numbered from it in the old name, and one without moves every job before it"
  one = shown(job(1, plain("a", "one", 1), start()))
  two = shown(job(2, plain("a", "two", 1), start()))
  done_two = archived(acked(leased(job(3, plain("a", "three", 1), start()), "w", 100, start()), "w",
    start()),
    start() + 1.ms)
  entries = [("ids", "1000"),
    ("j_1", one),
    ("j_2", two),
    ("rename_1", "{\"from\": \"a\", \"to\": \"c\", \"next_id\": 2}")]
  shelf = [("j_3", shown(done_two))]
  assert ill_formed(entries, shelf) is None
  assert rebuilt(entries, shelf, start()) is Some(b)
  assert queue_in(decide(b, call("p", Fetch(id: "j_1")), start())) == "c"
  assert queue_in(decide(b, call("p", Fetch(id: "j_2")), start())) == "a"
  assert queue_in(decide(b, call("p", Fetch(id: "j_3")), start())) == "a"
  old = entries.map(fn(e) without_next_id(e) end)
  assert rebuilt(old, shelf, start()) is Some(every)
  assert ["j_1",
    "j_2",
    "j_3"].all?(fn(id) queue_in(decide(every, call("p", Fetch(id: id)), start())) == "c" end)
  made = decide(board(start(), 1), call("p", Create(making: plain("a", "x", 1))), start())
  moved = rename(made.board, "a", "c", start())
  again = decide(moved.board, call("p", Create(making: keyed("a", "k"))), start())
  assert moved.writes == [("rename_1", Some("{\"from\": \"a\", \"to\": \"c\", \"next_id\": 2}"))]
  held = lease_by(again.board, "w", "a", 100, start())
  acked_two = decide(held.board, call("w", Ack(id: "j_2")), start())
  shelving = shelved(retaining(acked_two.board, 1_000), start() + 1_000.ms)
  untagged = shelving.shelved.map(fn(w) (w.0, (w.1 or "").replace(", \"renames\": 1", "")) end)
  store = [made, moved, again, held, acked_two, shelving].reduce(Map.new(),
    fn(s, d) logged(s, d) end)
  assert rebuilt(store.entries, untagged, start() + 1_000.ms) is Some(replayed)
  assert queue_in(decide(replayed, call("p", Fetch(id: "j_2")), start() + 1_000.ms)) == "a"
  assert number_in(create_keyed(replayed, "a", "k", start() + 1_000.ms)) == 2
  assert queue_in(decide(replayed, call("p", Fetch(id: "j_1")), start() + 1_000.ms)) == "c"
end

test "a folder with a prune record that is not one, or two marks with one number, is ill-formed by name"
  entries = [("ids", "1000"), ("j_1", shown(job(1, plain("a", "", 1), start())))]
  good = entries.push(("prune_1", "{\"cutoff\": \"2026-09-14T10:00:05Z\", \"pruned\": 2}"))
  assert ill_formed(good, []) is None
  assert rebuilt(good, [], start()) is Some(b)
  assert b.marks == 1 and b.cuts.size == 1
  bad_cutoff = entries.push(("prune_1", "{\"cutoff\": \"yesterday\", \"pruned\": 2}"))
  assert ill_formed(bad_cutoff, []) == Some(("prune_1", "its cutoff is not a time"))
  assert rebuilt(bad_cutoff, [], start()) is None
  none = entries.push(("prune_1", "{\"cutoff\": \"2026-09-14T10:00:05Z\", \"pruned\": 0}"))
  assert ill_formed(none, []) == Some(("prune_1", "its pruned is not a whole number above 0"))
  assert ill_formed(entries.push(("prune_1", "{\"cutoff\": \"2026-09-14T10:00:05Z\"}")),
    []) == Some(("prune_1", "its pruned is not a whole number above 0"))
  assert ill_formed(entries.push(("prune_1", "7")), []) == Some(("prune_1", "is not a prune"))
  assert ill_formed(entries.push(("prune_x", "{}")),
    []) == Some(("prune_x", "its key is not prune_ and a number"))
  shared = good.push(("rename_1", "{\"from\": \"a\", \"to\": \"b\", \"next_id\": 2}"))
  assert ill_formed(shared, []) == Some(("rename_1", "its number is prune_1's too"))
end

test rejects "a prune step whose age is under a second"
  pruned(aging(), 999, start() + 10_000.ms)
end

test rejects "a rename step whose target is its source"
  relabeled(with_jobs(["a"]), "a", "a")
end

test rejects "a rename step whose target holds a job"
  relabeled(with_jobs(["a", "b"]), "a", "b")
end

test rejects "an archived job put on the shelf with no archived_at"
  shelved_into(board(start(), 1), job(1, plain("a", "", 1), start()))
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

verified: types, contracts, tests (47), property (200 seeds), sim (not run)
          proven: not run
