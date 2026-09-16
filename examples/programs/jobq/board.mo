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
  # body gone; regenerate
end

fn find(board: Board, number: UInt64) : Option(Job)
  # body gone; regenerate
end

fn counts(board: Board) : Counts
  # body gone; regenerate
end

# The board with the job in its number's place, every index moved from the job it replaces.
fn placed(board: Board, job: Job) : Board
  ensures find(result, job.number) == Some(job)
  # body gone; regenerate
end

# The board without the job.
fn removed(board: Board, number: UInt64) : Board
  ensures find(result, number) is None
  # body gone; regenerate
end

# The board with the job of that number, if it holds one, out of every index and count.
fn unindexed(board: Board, number: UInt64) : Board
  # body gone; regenerate
end

# A job's key in the due index: the second its lease runs out.
fn due_key(job: Job) : Int64
  # body gone; regenerate
end

# The whole seconds from 2000 to a time; a later time never has a smaller second.
fn second_of(at: Time) : Int64
  # body gone; regenerate
end

fn with_number(index: Map(String, Map(K, Set(UInt64))), job: Job, when: Bool, key: K) : Map(String,
  # body gone; regenerate
end

fn without_number(index: Map(String, Map(K, Set(UInt64))), job: Job, when: Bool,
  key: K) : Map(String, Map(K, Set(UInt64)))
  # body gone; regenerate
end

fn counted(counts: Counts, status: State, adding: Bool) : Counts
  # body gone; regenerate
end

fn moved(n: UInt64, adding: Bool) : UInt64
  # body gone; regenerate
end

# The queued job of the queue with the lowest number, which is the oldest.
fn oldest_queued(board: Board, queue: String) : Option(Job)
  # body gone; regenerate
end

# The queue's leased jobs whose lease has run out by now, oldest first.
fn due_in(board: Board, queue: String, now: Time) : List(Job)
  # body gone; regenerate
end

# Every queue's leased jobs whose lease has run out by now, oldest first.
fn due_anywhere(board: Board, now: Time) : List(Job)
  # body gone; regenerate
end

fn numbers_at(sets: Map(Int64, Set(UInt64)), key: Int64) : List(UInt64)
  # body gone; regenerate
end

fn found(board: Board, number: UInt64) : List(Job)
  # body gone; regenerate
end

# The jobs in the queue and the state asked for, either one or both left out, by number, the
# first `limit`.
fn listed(board: Board, queue: Option(String), status: Option(State), limit: UInt64) : List(Job)
  ensures result.size <= limit
  # body gone; regenerate
end

fn wanted?(job: Job, queue: Option(String), status: Option(State)) : Bool
  # body gone; regenerate
end

# The highest job number held, or 0.
fn highest(board: Board) : UInt64
  # body gone; regenerate
end

fn fresh(number: UInt64, queue: String, at: Time) : Job
  # body gone; regenerate
end

fn leased_until(job: Job, worker: String, until: Time) : Job
  # body gone; regenerate
end

fn with_status(job: Job, status: State) : Job
  # body gone; regenerate
end

fn parity(n: UInt64) : String
  # body gone; regenerate
end

fn numbers(jobs: List(Job)) : List(UInt64)
  # body gone; regenerate
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
