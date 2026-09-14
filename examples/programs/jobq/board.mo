module Jobq.Board
expose Board, Counts, board, find, placed, removed, oldest_queued, due_in, due_anywhere, listed, counts, highest, second_of

use Jobq.Job{Job, State, run_out?}

intent "The jobs a queue service holds, indexed for its looks: every job by number over small maps, each queue's queued jobs by number so a lease finds the oldest, each queue's leased jobs by the second their lease runs out so a look finds the ones run out, and the count of jobs in each state."

# The counts of jobs in each state.
struct Counts
  queued: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
end

# Jobs by number over maps of 256, so a change copies one small map; a queue's queued job
# numbers over sets of 256 numbers; a queue's leased job numbers by the second their lease
# runs out; the counts; and how many jobs.
struct Board
  jobs: Map(UInt64, Map(UInt64, Job))
  waiting: Map(String, Map(UInt64, Set(UInt64)))
  due: Map(String, Map(Int64, Set(UInt64)))
  counts: Counts
  size: UInt64
end

fn board() : Board
  Board(jobs: Map.new(), waiting: Map.new(), due: Map.new(),
    counts: Counts(queued: 0, leased: 0, done: 0, dead: 0), size: 0)
end

fn find(board: Board, number: UInt64) : Option(Job)
  bucket = try board.jobs.get(number / 256)
  bucket.get(number)
end

fn counts(board: Board) : Counts
  board.counts
end

# The board with the job in its number's place, every index moved from the job it replaces.
fn placed(board: Board, job: Job) : Board
  ensures find(result, job.number) == Some(job)

  var after = unindexed(board, job.number)
  at = job.number / 256
  bucket = after.jobs.get(at) or Map.new()
  after.jobs = after.jobs.set(at, bucket.set(job.number, job))
  after.size = after.size + 1
  after.counts = counted(after.counts, job.state, true)
  after.waiting = with_number(after.waiting, job, job.state == Queued, at)
  after.due = with_number(after.due, job, job.state == Leased, due_key(job))
  after
end

# The board without the job.
fn removed(board: Board, number: UInt64) : Board
  ensures find(result, number) is None

  var after = unindexed(board, number)
  at = number / 256
  if after.jobs.get(at) is Some(bucket)
    rest = bucket.remove(number)
    after.jobs = if rest.size == 0: after.jobs.remove(at) else: after.jobs.set(at, rest)
  end
  after
end

# The board with the job of that number, if it holds one, out of every index and count.
fn unindexed(board: Board, number: UInt64) : Board
  case find(board, number)
    Some(prior):
      var after = board
      after.size = board.size - 1
      after.counts = counted(board.counts, prior.state, false)
      after.waiting = without_number(board.waiting, prior, prior.state == Queued, number / 256)
      after.due = without_number(board.due, prior, prior.state == Leased, due_key(prior))
      after
    None: board
  end
end

# A job's key in the due index: the second its lease runs out.
fn due_key(job: Job) : Int64
  second_of(job.lease_until or job.updated_at)
end

# The whole seconds from 2000 to a time; a later time never has a smaller second.
fn second_of(at: Time) : Int64
  (at - Time.from_parts(2000, 1, 1, 0, 0, 0)).ms / 1000
end

fn with_number(index: Map(String, Map(K, Set(UInt64))), job: Job, when: Bool, key: K) : Map(String,
  Map(K, Set(UInt64)))
  return index if !when
  sets = index.get(job.queue) or Map.new()
  numbers = sets.get(key) or Set.new()
  index.set(job.queue, sets.set(key, numbers.add(job.number)))
end

fn without_number(index: Map(String, Map(K, Set(UInt64))), job: Job, when: Bool,
  key: K) : Map(String, Map(K, Set(UInt64)))
  return index if !when
  sets = index.get(job.queue) or Map.new()
  numbers = (sets.get(key) or Set.new()).remove(job.number)
  rest = if numbers.size == 0: sets.remove(key) else: sets.set(key, numbers)
  return index.remove(job.queue) if rest.size == 0
  index.set(job.queue, rest)
end

fn counted(counts: Counts, status: State, adding: Bool) : Counts
  var after = counts
  case status
    Queued:
      after.queued = moved(counts.queued, adding)
    Leased:
      after.leased = moved(counts.leased, adding)
    Done:
      after.done = moved(counts.done, adding)
    Dead:
      after.dead = moved(counts.dead, adding)
  end
  after
end

fn moved(n: UInt64, adding: Bool) : UInt64
  return n + 1 if adding
  n - 1
end

# The queued job of the queue with the lowest number, which is the oldest.
fn oldest_queued(board: Board, queue: String) : Option(Job)
  sets = try board.waiting.get(queue)
  lowest = try sets.keys.min
  numbers = try sets.get(lowest)
  find(board, try numbers.to_list.min)
end

# The queue's leased jobs whose lease has run out by now, oldest first.
fn due_in(board: Board, queue: String, now: Time) : List(Job)
  sets = board.due.get(queue) or Map.new()
  second = second_of(now)
  numbers = sets.keys.filter(fn(key) key <= second end).flat_map(fn(key) numbers_at(sets, key) end)
  jobs = numbers.flat_map(fn(n) found(board, n) end)
  jobs.filter(fn(job) run_out?(job, now) end).sort_by(fn(job) job.number end)
end

# Every queue's leased jobs whose lease has run out by now, oldest first.
fn due_anywhere(board: Board, now: Time) : List(Job)
  every = board.due.keys.flat_map(fn(queue) due_in(board, queue, now) end)
  every.sort_by(fn(job) job.number end)
end

fn numbers_at(sets: Map(Int64, Set(UInt64)), key: Int64) : List(UInt64)
  (sets.get(key) or Set.new()).to_list
end

fn found(board: Board, number: UInt64) : List(Job)
  case find(board, number)
    Some(job): [job]
    None: []
  end
end

# The jobs in the queue and the state asked for, either one or both left out, by number, the
# first `limit`.
fn listed(board: Board, queue: Option(String), status: Option(State), limit: UInt64) : List(Job)
  ensures result.size <= limit

  var picked = []
  for at in board.jobs.keys.sort
    if picked.size >= limit
      break
    end
    bucket = board.jobs.get(at) or Map.new()
    kept = bucket.values.filter(fn(job) wanted?(job, queue, status) end)
    picked = picked.concat(kept.sort_by(fn(job) job.number end))
  end
  picked.take(limit)
end

fn wanted?(job: Job, queue: Option(String), status: Option(State)) : Bool
  in_queue = (queue or job.queue) == job.queue
  in_state = (status or job.state) == job.state
  in_queue and in_state
end

# The highest job number held, or 0.
fn highest(board: Board) : UInt64
  top = board.jobs.keys.max or 0
  (board.jobs.get(top) or Map.new()).keys.max or 0
end

fn fresh(number: UInt64, queue: String, at: Time) : Job
  Job(number: number, queue: queue, state: Queued, payload: "p", attempts: 0, max_attempts: 2,
    created_at: at, updated_at: at, worker: None, lease_until: None, reason: None)
end

fn leased_until(job: Job, worker: String, until: Time) : Job
  var after = job
  after.state = Leased
  after.attempts = job.attempts + 1
  after.worker = Some(worker)
  after.lease_until = Some(until)
  after
end

fn with_status(job: Job, status: State) : Job
  var after = job
  after.state = status
  after.worker = None
  after.lease_until = None
  after
end

fn parity(n: UInt64) : String
  return "even" if n % 2 == 0
  "odd"
end

fn numbers(jobs: List(Job)) : List(UInt64)
  jobs.map(fn(job) job.number end)
end

test "the oldest queued job of a queue is the one with the lowest number, over buckets"
  var b = [700, 3, 300, 5].reduce(board(),
    fn(acc, n) placed(acc, fresh(n, "emails", Time.fixture())) end)
  b = placed(b, fresh(1, "other", Time.fixture()))
  assert oldest_queued(b, "emails") == Some(fresh(3, "emails", Time.fixture()))
  b = placed(b, leased_until(fresh(3, "emails", Time.fixture()), "ada", Time.fixture()))
  assert oldest_queued(b, "emails") == Some(fresh(5, "emails", Time.fixture()))
  b = placed(b, leased_until(fresh(5, "emails", Time.fixture()), "ada", Time.fixture()))
  assert oldest_queued(b, "emails") == Some(fresh(300, "emails", Time.fixture()))
  b = placed(b, fresh(3, "emails", Time.fixture()))
  assert oldest_queued(b, "emails") == Some(fresh(3, "emails", Time.fixture()))
  assert oldest_queued(b, "nowhere") is None
  assert oldest_queued(b, "other") == Some(fresh(1, "other", Time.fixture()))
end

test "a queue's leases run out by the second, and only the ones whose deadline has passed"
  at = Time.fixture()
  var b = board()
  b = placed(b, leased_until(fresh(1, "q", Time.fixture()), "ada", at + 1_500.ms))
  b = placed(b, leased_until(fresh(2, "q", Time.fixture()), "ada", at + 1_200.ms))
  b = placed(b, leased_until(fresh(3, "q", Time.fixture()), "ada", at + 5_000.ms))
  b = placed(b, leased_until(fresh(4, "r", Time.fixture()), "ada", at + 100.ms))
  assert due_in(b, "q", at) == []
  assert numbers(due_in(b, "q", at + 1_300.ms)) == [2]
  assert numbers(due_in(b, "q", at + 1_500.ms)) == [1, 2]
  assert numbers(due_anywhere(b, at + 1_500.ms)) == [1, 2, 4]
  b = placed(b, with_status(fresh(2, "q", Time.fixture()), Done))
  assert numbers(due_in(b, "q", at + 1.minute)) == [1, 3]
  assert b.due.get("r") is Some(_)
  b = removed(b, 4)
  assert b.due.get("r") is None
end

test "the counts follow every job's state, and a removed job leaves every index"
  at = Time.fixture()
  var b = (1..6).reduce(board(), fn(acc, n) placed(acc, fresh(n, "q", Time.fixture())) end)
  b = placed(b, leased_until(fresh(1, "q", Time.fixture()), "ada", at))
  b = placed(b, with_status(fresh(2, "q", Time.fixture()), Done))
  b = placed(b, with_status(fresh(3, "q", Time.fixture()), Dead))
  assert counts(b) == Counts(queued: 2, leased: 1, done: 1, dead: 1)
  assert b.size == 5 and highest(b) == 5
  b = removed(removed(b, 4), 5)
  assert counts(b) == Counts(queued: 0, leased: 1, done: 1, dead: 1)
  assert oldest_queued(b, "q") is None and b.waiting.size == 0
  assert highest(b) == 3 and b.size == 3
  assert removed(b, 99) == b
end

test "a listing is by number, filtered by queue and state, at most the limit"
  var b = (1..400).reduce(board(), fn(acc, n) placed(acc, fresh(n, parity(n), Time.fixture())) end)
  b = placed(b, with_status(fresh(7, "odd", Time.fixture()), Done))
  first = listed(b, None, None, 100)
  assert first.size == 100 and numbers(first.take(3)) == [1, 2, 3]
  assert numbers(listed(b, Some("even"), None, 3)) == [2, 4, 6]
  assert numbers(listed(b, None, Some(Done), 100)) == [7]
  assert numbers(listed(b, Some("even"), Some(Done), 100)) == []
  assert numbers(listed(b, Some("odd"), Some(Queued), 300)).last == Some(399)
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
