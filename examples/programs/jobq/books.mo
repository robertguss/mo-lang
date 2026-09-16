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
  return Committed(books: books, ok: true, steps: []) if changes.size == 0 and ceiling == 0
  var whole = books
  if mended(fs, books, at.by) is Ok(ready)
    whole = ready
  else
    return Committed(books: books, ok: false, steps: stepped(changes, at.now, false))
  end
  written = changes.map(fn(change) (id_of(change.1.number), shown(change.1)) end)
  case put_all(fs, whole.table, reserved(ceiling).concat(written), at.by)
    Ok(after):
      var kept = whole
      kept.table = after
      kept.board = changes.reduce(whole.board, fn(held, change) placed(held, change.1) end)
      kept.reserved = if ceiling > 0: ceiling else: whole.reserved
      Committed(books: kept, ok: true, steps: stepped(changes, at.now, true))
    Error(Torn):
      var hurt = whole
      hurt.torn = true
      Committed(books: hurt, ok: false, steps: stepped(changes, at.now, false))
    Error(_): Committed(books: whole, ok: false, steps: stepped(changes, at.now, false))
  end
end

fn reserved(ceiling: UInt64) : List((String, String))
  return [] if ceiling == 0
  [("ids", "#{ceiling}")]
end

fn stepped(changes: List((Option(Job), Job)), now: Time, logged: Bool) : List(Step)
  changes.map(fn(change)
    Step(before: change.0, after: Some(change.1), now: now, logged: logged, kept: logged)
  end)
end

fn mended(fs: Fs, books: Books, by: Deadline) : Result(Books, StoreError)
  return Ok(books) if !books.torn
  var whole = books
  whole.table = try compacted(fs, books.table, by)
  whole.torn = false
  Ok(whole)
end

fn held_twice?(s: Step) : Bool
  return false if !s.kept
  case s.before
    Some(was):
      case s.after
        Some(held):
          live = was.state == Leased and !run_out?(was, s.now)
          live and held.state == Leased and was.worker != held.worker
        None: false
      end
    None: false
  end
end

fn revived?(s: Step) : Bool
  return false if !s.kept
  case s.before
    Some(was):
      case s.after
        Some(held): held.state == Leased and (was.state == Done or was.state == Dead)
        None: false
      end
    None: false
  end
end

fn blocked?(s: Step) : Bool
  return false if !s.kept
  case s.before
    Some(was):
      case s.after
        Some(held): run_out?(was, s.now) and held.state == Leased and run_out?(held, s.now)
        None: false
      end
    None: false
  end
end

# The books a service starts with before its first message opens the store.
fn unopened(place: Place) : Books
  empty = Table(buckets: Map.new(), size: 0, dir: place.dir, name: place.log, bytes: 0, lines: 0,
    cut: false)
  Books(table: empty, board: board(), next_id: 1, reserved: 0, torn: false)
end

# The books the place's logs replay to on the deadline: every record a job, the next id above
# every id the log holds and every id it reserved, and a log whose last line was cut short
# rewritten at the first change.
fn opened(fs: Fs, place: Place, by: Deadline) : Result(Books, String)
  table = try table_of(opened_by(fs, place.dir, by))
  own = if place.log == "jobq.log": table else: try table_of(continued(fs, table, place.log, by))
  ids = keys(own, "j_")
  jobs = ids.flat_map(fn(key) record_at(own, key) end)
  if jobs.size != ids.size
    return Error("holds a jobq.log with a record that is not a job")
  end
  floor = (get(own, "ids") or "0").to_u64 or 0
  filled = jobs.reduce(board(), fn(held, one) placed(held, one) end)
  Ok(Books(table: own, board: filled, next_id: max_of(floor, highest(filled) + 1), reserved: floor,
    torn: cut_short?(own)))
end

fn record_at(table: Table, key: String) : List(Job)
  case job_of(get(table, key) or "")
    Some(one): if id_of(one.number) == key: [one] else: []
    None: []
  end
end

fn table_of(opened_table: Result(Table, StoreError)) : Result(Table, String)
  case opened_table
    Ok(table): Ok(table)
    Error(NoFolder): Error("is not a folder jobq can read")
    Error(Unreadable): Error("holds a jobq.log jobq cannot read")
    Error(Slow): Error("took too long to read")
    Error(BadLine(number)): Error("holds a jobq.log whose line #{number} is not a change")
    Error(Unwritten) | Error(Torn): Error("holds a jobq.log jobq could not write")
  end
end

fn health_of(books: Books, uptime_ms: Int64) : Health
  Health(queued: books.board.counts.queued, leased: books.board.counts.leased,
    done: books.board.counts.done, dead: books.board.counts.dead, uptime_ms: uptime_ms)
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
  gone = Job(number: 1, queue: "q", state: Dead, payload: "p", attempts: 1, max_attempts: 1,
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
