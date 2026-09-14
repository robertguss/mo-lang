module Jobq.Books
expose Books, Stored, Survivor, stored, deleted, reserving, books_of, survivors

use Jobq.Job{State, Job, Move, created, open?, json_of, job_of, id_number}
use Jobq.Store{Table, StoreError, get, put, delete, keys, compact, open}

intent "The board's books: the store and every job in it, the open jobs of each queue indexed oldest first, and each job's record put in the store before the books take it; a store that may end in part of a record is rewritten whole first, ids are reserved a hundred ahead so none is handed out twice, and a replayed store gives back every job it held."

never "a job created and not deleted is missing or changed after a replay"
  for s in Survivor.all
    s.before != s.after
  end
end

# The store and every job in it by id; per queue, the ids of its queued and leased jobs, oldest
# first; the next id, the id below which ids are reserved in the store, whether the store may end
# in part of a record, and the latest time a call brought.
struct Books
  table: Table
  jobs: Map(String, Job)
  open: Map(String, Set(UInt64))
  next_id: UInt64
  reserved: UInt64
  torn: Bool
  clock: Time
end

# A job before its service stopped, and after the log was replayed.
struct Survivor
  id: String
  before: Option(Job)
  after: Option(Job)
end

enum Stored
  Took(books: Books)
  Lost(books: Books, reason: String)
end

# The job's record in the store, then the job on the board.
fn stored(fs: Fs, books: Books, job: Job) : Stored
  case whole(fs, books)
    Ok(ready):
      case put(fs, ready.table, job.id, json_of(job))
        Ok(table): Took(books: taken(ready, table, job))
        Error(problem): lost(ready, problem)
      end
    Error(problem): lost(books, problem)
  end
end

fn deleted(fs: Fs, books: Books, job: Job) : Stored
  case whole(fs, books)
    Ok(ready):
      case delete(fs, ready.table, job.id)
        Ok(table):
          var after = ready
          after.table = table
          after.jobs = ready.jobs.remove(job.id)
          after.open = ready.open.set(job.queue, unindexed(ready, job))
          Took(books: after)
        Error(problem): lost(ready, problem)
      end
    Error(problem): lost(books, problem)
  end
end

# Before a create hands out an id at or past the reserved ones, the store takes a reservation of
# the next hundred, so an id is never handed out twice across a restart.
fn reserving(fs: Fs, books: Books) : Stored
  case whole(fs, books)
    Ok(ready):
      return Took(books: ready) if ready.next_id < ready.reserved
      ceiling = ready.next_id + 100
      case put(fs, ready.table, "ids", "#{ceiling}")
        Ok(table):
          var after = ready
          after.table = table
          after.reserved = ceiling
          Took(books: after)
        Error(problem): lost(ready, problem)
      end
    Error(problem): lost(books, problem)
  end
end

# A store that may end in part of a record is rewritten whole before it takes another.
fn whole(fs: Fs, books: Books) : Result(Books, StoreError)
  return Ok(books) if !books.torn
  var after = books
  after.table = try compact(fs, books.table)
  after.torn = false
  Ok(after)
end

fn lost(books: Books, problem: StoreError) : Stored
  var after = books
  after.torn = books.torn or problem == Torn
  reason = if after.torn
    "the store may end in part of a record; it is rewritten whole before the next change"
  else
    "the store did not take the change"
  end
  Lost(books: after, reason: reason)
end

fn taken(books: Books, table: Table, job: Job) : Books
  from = (books.jobs.get(job.id) or job).state
  move = Move(id: job.id, from: from, to: job.state)
  n = id_number(move.id) or 0
  ids = books.open.get(job.queue) or Set.new()
  open_ids = if move.to == Queued or move.to == Leased: ids.add(n) else: ids.remove(n)
  var after = books
  after.table = table
  after.jobs = books.jobs.set(job.id, job)
  after.open = books.open.set(job.queue, open_ids)
  after
end

fn unindexed(books: Books, job: Job) : Set(UInt64)
  (books.open.get(job.queue) or Set.new()).remove(id_number(job.id) or 0)
end

# The board a replayed store holds: each job under its id, the open ones indexed oldest first, and
# the next id above every id the store holds and every id it reserved.
fn books_of(table: Table, at: Time) : Books
  ensures result.next_id >= 1

  held = keys(table, "j_").flat_map(fn(key) job_at(table, key) end)
  sorted = held.sort_by(fn(j) id_number(j.id) or 0 end)
  jobs = sorted.reduce(Map.new(), fn(so_far, j) so_far.set(j.id, j) end)
  open = sorted.filter(fn(j) open?(j) end).reduce(Map.new(), fn(so_far, j) indexed(so_far, j) end)
  highest = sorted.map(fn(j) id_number(j.id) or 0 end).max or 0
  reserved = (get(table, "ids") or "0").to_u64 or 0
  next_id = max_of(max_of(highest + 1, reserved), 1)
  Books(table: table, jobs: jobs, open: open, next_id: next_id, reserved: next_id, torn: false,
    clock: at)
end

fn job_at(table: Table, key: String) : List(Job)
  case job_of(get(table, key) or "")
    Some(job): [job]
    None: []
  end
end

fn indexed(open: Map(String, Set(UInt64)), job: Job) : Map(String, Set(UInt64))
  open.set(job.queue, (open.get(job.queue) or Set.new()).add(id_number(job.id) or 0))
end

# Each job either board holds, before and after.
fn survivors(before: Books, after: Books) : List(Survivor)
  ids = before.jobs.keys.concat(after.jobs.keys).unique
  ids.map(fn(id) Survivor(id: id, before: before.jobs.get(id), after: after.jobs.get(id)) end)
end

fn at(seconds: UInt64) : Time
  Time.from_parts(2026, 9, 14, 9, 0, 0) + (seconds * 1_000).to_i64.ms
end

fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "jobq.log", bytes: 0, lines: 0, cut: false)
end

fn took(outcome: Stored) : Books
  case outcome
    Took(books): books
    Lost(books: lost, reason: _): lost
  end
end

test "a replayed store gives back every job it held, the open ones indexed oldest first"
  fs = Fs.fixture()
  var books = books_of(fresh(), at(0))
  for n in 1..5
    books = took(stored(fs, books, created(n, if n == 2: "b" else: "a", "p", 3, at(0))))
  end
  assert open(fs, "d") is Ok(table)
  again = books_of(table, at(1))
  assert survivors(books, again).all?(fn(s) s.before == s.after end)
  assert again.open.get("a") == Some(Set.new().add(1).add(3).add(4))
  assert again.next_id == 5
end

test "an id reservation is in the store before ids past it are handed out"
  fs = Fs.fixture()
  reserved = took(reserving(fs, books_of(fresh(), at(0))))
  assert reserved.reserved == 101
  assert took(reserving(fs, reserved)) == reserved
  assert open(fs, "d") is Ok(table)
  assert books_of(table, at(0)).next_id == 101
end

test "a store that may end in part of a record is rewritten whole before it takes the next"
  fs = Fs.fixture()
  books = books_of(fresh(), at(0))
  job = created(1, "a", "p", 3, at(0))
  torn = took(stored(Fs.fixture(delay: 1.minute), books, job))
  assert torn.torn and torn.jobs.size == 0
  whole_again = took(stored(fs, torn, job))
  assert !whole_again.torn and whole_again.jobs.size == 1
  gone = took(deleted(fs, whole_again, job))
  assert gone.jobs.size == 0 and gone.open.get("a") == Some(Set.new())
end

test rejects "a replay that loses a job trips the never"
  job = created(1, "emails", "", 3, at(0))
  gone = Survivor(id: "j_1", before: Some(job), after: None)
  assert gone.id == "j_1"
end
