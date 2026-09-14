module Jobq.Books
expose Step, Books, Place, Moment, Committed, Health, committed, opened, unopened, health_of

use Jobq.Board{Board, board, placed, highest}
use Jobq.Job{Job, State, job, run_out?, holds?, id_of, shown, job_of}
use Jobq.Journal{opened_by, continued, put_all, compacted}
use Jobq.Store{Table, StoreError, get, keys, cut_short?}

intent "The books a queue service keeps: the store and the jobs on the board, opened from the log and changed only by a write the log took first, one append for every change a call makes; and the nevers every such write is held to."

never "a job is held by two workers at once"
  for s in Step.all
    held_twice?(s)
  end
end

never "a done job is leased again, or a dead job is leased"
  for s in Step.all
    revived?(s)
  end
end

never "a response is sent before its record is durable"
  for s in Step.all
    s.kept and !s.logged
  end
end

never "a lease that ran out blocks its job past a look"
  for s in Step.all
    blocked?(s)
  end
end

# One job a call looked at or changed: as it was (None for a new job), as the call decided it
# should be (None for a delete), the time, whether its record reached the log, and whether the
# books took the change.
struct Step
  before: Option(Job)
  after: Option(Job)
  now: Time
  logged: Bool
  kept: Bool
end

# The store, the jobs on the board, the next id, the id below which ids are reserved in the log,
# and whether the log may end in part of a change.
struct Books
  table: Table
  board: Board
  next_id: UInt64
  reserved: UInt64
  torn: Bool
end

# Where a service keeps its jobs: a folder whose jobq.log it replays, and the log in that
# folder its changes go to, jobq.log itself or jobq.check.log replayed after it.
struct Place
  dir: String
  log: String
end

# When a call is served: the service's clock, and the deadline of the ask it answers, which
# every file call the call makes waits on.
struct Moment
  now: Time
  by: Deadline
end

# The books after a write, whether the log took it, and the steps it made.
struct Committed
  books: Books
  ok: Bool
  steps: List(Step)
end

struct Health
  queued: UInt64
  leased: UInt64
  done: UInt64
  dead: UInt64
  uptime_ms: Int64
end

# The changes appended to the log in one write, the ids reserved up to `ceiling` first when it is
# above 0, and only then on the board. A log that may end in part of a change is rewritten whole
# from the store first. A log that did not take them leaves the books as they were, torn when
# it may end in part of them.
fn committed(fs: Fs, books: Books, changes: List((Option(Job), Job)), ceiling: UInt64,
  at: Moment) : Committed
  if changes.size == 0 and ceiling == 0
    return Committed(books: books, ok: true, steps: [])
  end
  case mended(fs, books, at.by)
    Ok(whole):
      pairs = reserved(ceiling).concat(changes.map(fn(c) (id_of(c.1.number), shown(c.1)) end))
      case put_all(fs, whole.table, pairs, at.by)
        Ok(table):
          var after = whole
          after.table = table
          after.board = changes.reduce(whole.board, fn(b, change) placed(b, change.1) end)
          after.reserved = max_of(whole.reserved, ceiling)
          Committed(books: after, ok: true, steps: stepped(changes, at.now, true))
        Error(problem):
          var torn = whole
          torn.torn = problem == Torn
          Committed(books: torn, ok: false, steps: stepped(changes, at.now, false))
      end
    Error(_): Committed(books: books, ok: false, steps: stepped(changes, at.now, false))
  end
end

fn reserved(ceiling: UInt64) : List((String, String))
  return [] if ceiling == 0
  [("ids", "#{ceiling}")]
end

fn stepped(changes: List((Option(Job), Job)), now: Time, logged: Bool) : List(Step)
  changes.map(fn(c) Step(before: c.0, after: Some(c.1), now: now, logged: logged, kept: logged) end)
end

fn mended(fs: Fs, books: Books, by: Deadline) : Result(Books, StoreError)
  return Ok(books) if !books.torn
  table = try compacted(fs, books.table, by)
  var after = books
  after.table = table
  after.torn = false
  Ok(after)
end

fn held_twice?(s: Step) : Bool
  case s.after
    Some(after):
      before = s.before or after
      live = holds?(before, before.worker or "", s.now)
      live and after.status == Leased and after.worker != before.worker
    None: false
  end
end

fn revived?(s: Step) : Bool
  case s.before
    Some(before):
      finished = before.status == Done or before.status == Dead
      finished and (s.after or before).status == Leased
    None: false
  end
end

fn blocked?(s: Step) : Bool
  case s.before
    Some(before):
      after = s.after or before
      same = after.status == Leased and after.lease_until == before.lease_until
      run_out?(before, s.now) and same
    None: false
  end
end

# The books a service starts with before its first message opens the store.
fn unopened(place: Place) : Books
  table = Table(buckets: Map.new(), size: 0, dir: place.dir, name: place.log, bytes: 0, lines: 0,
    cut: false)
  Books(table: table, board: board(), next_id: 1, reserved: 1, torn: false)
end

# The books the place's logs replay to on the deadline: every record a job, the next id above
# every id the log holds and every id it reserved, and a log whose last line was cut short
# rewritten at the first change.
fn opened(fs: Fs, place: Place, by: Deadline) : Result(Books, String)
  first = try table_of(opened_by(fs, place.dir, by))
  table = if place.log == "jobq.log"
    first
  else
    try table_of(continued(fs, first, place.log, by))
  end
  names = keys(table, "j_")
  jobs = names.flat_map(fn(key) record_at(table, key) end)
  if jobs.size != names.size
    return Error("holds a jobq.log with a record that is not a job")
  end
  held_jobs = jobs.reduce(board(), fn(b, job) placed(b, job) end)
  ids = (get(table, "ids") or "0").to_u64 or 0
  next = max_of(max_of(highest(held_jobs) + 1, ids), 1)
  Ok(Books(table: table, board: held_jobs, next_id: next, reserved: next, torn: cut_short?(table)))
end

fn record_at(table: Table, key: String) : List(Job)
  case job_of(get(table, key) or "")
    Some(job): [job].filter(fn(j) id_of(j.number) == key end)
    None: []
  end
end

fn table_of(opened_table: Result(Table, StoreError)) : Result(Table, String)
  case opened_table
    Ok(table): Ok(table)
    Error(NoFolder): Error("is not a folder jobq can read")
    Error(Unreadable): Error("holds a jobq log jobq cannot read")
    Error(Slow): Error("took longer to read than its opening was given")
    Error(BadLine(number)): Error("holds a jobq log whose line #{number} is not a SET or a DEL")
    Error(Unwritten) | Error(Torn): Error("holds a jobq log jobq could not write")
  end
end

fn health_of(books: Books, uptime_ms: Int64) : Health
  counts = books.board.counts
  Health(queued: counts.queued, leased: counts.leased, done: counts.done, dead: counts.dead,
    uptime_ms: uptime_ms)
end

test "a log with a record that is not a job does not open, and one cut short opens torn"
  fs = Fs.fixture()
  at = Time.fixture()
  place = Place(dir: "d", log: "jobq.log")
  assert fs.write("d/jobq.log", "SET j_1 not json\n", within: 1.minute) is Ok(_)
  assert opened(fs, place,
    Deadline.fixture(1.minute)) == Error("holds a jobq.log with a record that is not a job")
  assert fs.write("d/jobq.log", "SET j_1 #{shown(job(2, "q", "p", 1, at))}\n",
    within: 1.minute) is Ok(_)
  assert opened(fs, place, Deadline.fixture(1.minute)) is Error(_)
  text = "SET ids 50\nSET j_2 #{shown(job(2, "q", "p", 1, at))}\nSET j_3 {"
  assert fs.write("d/jobq.log", text, within: 1.minute) is Ok(_)
  assert opened(fs, place, Deadline.fixture(1.minute)) is Ok(books)
  assert books.torn and books.next_id == 50 and books.board.size == 1
  assert health_of(books, 7) == Health(queued: 1, leased: 0, done: 0, dead: 0, uptime_ms: 7)
end

test "a folder that is not there does not open, as jobq serve refuses it"
  fs = Fs.fixture()
  assert opened(fs, Place(dir: "nowhere", log: "jobq.log"),
    Deadline.fixture(1.minute)) == Error("is not a folder jobq can read")
  assert fs.mkdir("empty", within: 1.minute) is Ok(_)
  assert opened(fs, Place(dir: "empty", log: "jobq.log"), Deadline.fixture(1.minute)) is Ok(books)
  assert books.board.size == 0 and !books.torn
end

test "a check's own log replays over the folder's, and its changes go only to its own"
  fs = Fs.fixture()
  at = Time.fixture()
  made = job(1, "q", "p", 1, at)
  assert fs.write("d/jobq.log", "SET j_1 #{shown(made)}\n", within: 1.minute) is Ok(_)
  place = Place(dir: "d", log: "jobq.check.log")
  assert opened(fs, place, Deadline.fixture(1.minute)) is Ok(books)
  gone = Job(number: 1, queue: "q", status: Dead, payload: "p", attempts: 1, max_attempts: 1,
    created_at: at, updated_at: at, worker: None, lease_until: None, reason: Some("x"))
  done = committed(fs, books, [(Some(made), gone)], 0,
    Moment(now: at, by: Deadline.fixture(1.minute)))
  assert done.ok and done.steps.size == 1
  assert opened(fs, place, Deadline.fixture(1.minute)) is Ok(again)
  assert again.board.counts.dead == 1
  assert fs.read("d/jobq.log", within: 1.minute) == Ok("SET j_1 #{shown(made)}\n")
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
