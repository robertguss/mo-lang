module Jobq.Queue
expose Opened, Readied, Survived, Service, Services, Racer, Racers, readied

use Jobq.Books{Books, Place, Moment, Health, opened, unopened, health_of}
use Jobq.Job{Job, id_of, shown}
use Jobq.Moves{Call, Command, Outcome, Served, serve, swept}

intent "The queue service process: it opens its store at its first message, after a start or a restart, and from then on serves each call against the jobs with main's clock, so a restart recovers every job the log holds; the listener's Idle becomes a sweep of the leases run out; every message is an ask, and every file call it makes waits on what remains of its asker's deadline."

never "a job is lost across a replay"
  for r in Survived.all
    r.replayed != r.held
  end
end

enum Opened
  Ready(jobs: UInt64, cut: Bool)
  Unready(why: String)
end

# The books a message is served against: the store opened at the first message that could open
# it, or why it could not be.
struct Readied
  books: Books
  opened: Bool
  why: String
end

# A job as a service answered for it, beside the same job as a service started again over the
# same log holds it: both as their JSON, "" for none.
struct Survived
  held: String
  replayed: String
end

# A crash discards the update and its books, and the restart opens the store again at its next
# message, so no change the log took is lost; a change it did not take was answered 503. Each
# arm's file calls run on reply_by: the store opened, replayed, appended to, and rewritten on
# what remains of the ask, so none of them waits past its asker.
process Service(fs: Fs, clock: Clock, place: Place, started: Time) mailbox: 4_096
  state
    books: Books = unopened(place)
    opened: Bool
  end

  message Open : Opened
  message Serve(call: Call) : Outcome
  message Sweep : UInt64
  message Tally : Health

  fn update(state, message)
    # body gone; regenerate
  end
end

supervisor Services(fs: Fs, clock: Clock, place: Place, started: Time)
  child Service(fs, clock, place, started), restart: :always, max_restarts: 5 per 1.minute
end

fn readied(fs: Fs, place: Place, books: Books, already: Bool, by: Deadline) : Readied
  # body gone; regenerate
end

fn opened_answer(ready: Readied) : Opened
  # body gone; regenerate
end

fn served_by(fs: Fs, place: Place, ready: Readied, call: Call, at: Moment) : Served
  # body gone; regenerate
end

# The books after a sweep, and the jobs whose leases it ended; none when the store is not open.
fn swept_by(fs: Fs, ready: Readied, at: Moment) : Served
  # body gone; regenerate
end

# A worker for the race test: it asks for a lease on q when told to, and keeps what it got. The
# lease is an hour, longer than any ask in the test can wait under faults, so a second holder
# would be one at the same time.
process Racer(service: Handle(Service), token: String)
  state
    got: String
  end

  message Go
  message Got : String

  fn update(state, message)
    # body gone; regenerate
  end
end

supervisor Racers(service: Handle(Service), token: String)
  child Racer(service, token), restart: :always
end

# What a lease came to: the job's id, empty, or unavailable.
fn named(outcome: Outcome) : String
  # body gone; regenerate
end

fn place() : Place
  # body gone; regenerate
end

fn ask(service: Handle(Service), worker: String, command: Command) : Outcome
  # body gone; regenerate
end

fn made_id(outcome: Outcome) : String
  # body gone; regenerate
end

fn shown_of(outcome: Outcome) : String
  # body gone; regenerate
end

fn got(racer: Handle(Racer)) : String
  # body gone; regenerate
end

test "two workers race for one job, and exactly one holds it"
  fs = Fs.fixture()
  made = fs.mkdir("d", within: 1.minute) is Ok(_)
  service = Service.start(fs, Clock.fixture(), place(), Time.fixture())
  id = made_id(ask(service, "p", Create(queue: "q", payload: "x", max_attempts: 3)))
  assert made or id == ""
  if id != ""
    ada = Racer.start(service, "ada")
    grace = Racer.start(service, "grace")
    ada.send(Go)
    grace.send(Go)
    got_by = [got(ada), got(grace)]
    assert got_by.count(fn(g) g == id end) <= 1
    if got_by.all?(fn(g) g == id or g == "empty" end)
      assert got_by.count(fn(g) g == id end) == 1
    end
  end
end

test "a service started again over its log holds every job it answered for, and reuses no id"
  fs = Fs.fixture()
  made = fs.mkdir("d", within: 1.minute) is Ok(_)
  first = Service.start(fs, Clock.fixture(), place(), Time.fixture())
  var ids = [""].take(0)
  for i in 0..3
    ids = ids.push(made_id(ask(first, "p", Create(queue: "q", payload: "#{i}", max_attempts: 2))))
  end
  assert made or ids.all?(fn(i) i == "" end)
  leased = ask(first, "ada", Lease(queue: "q", lease_ms: 3_600_000))
  var answered = [""].take(0)
  for id in ids.filter(fn(i) i != "" end)
    answered = answered.push(shown_of(ask(first, "p", Fetch(id: id))))
  end
  second = Service.start(fs, Clock.fixture(), place(), Time.fixture())
  for id in ids.filter(fn(i) i != "" end)
    replayed = shown_of(ask(second, "p", Fetch(id: id)))
    kept = answered.find(fn(text) text.contains?("\"id\": \"#{id}\"") end) or ""
    if kept != "" and replayed != ""
      record = Survived(held: kept, replayed: replayed)
      assert record.replayed == record.held
    end
  end
  if leased is Handed(job)
    acked = ask(second, "ada", Ack(id: id_of(job.number)))
    assert acked is Found(_) or acked is Unavailable(_)
  end
  again = made_id(ask(second, "p", Create(queue: "q", payload: "later", max_attempts: 1)))
  assert again == "" or !ids.contains?(again)
end

test "a service whose folder cannot be read says why at every call"
  service = Service.start(Fs.fixture(delay: 1.minute), Clock.fixture(), place(), Time.fixture())
  assert service.ask(Open, within: 1.minute) is Ok(Unready(_)) or service.ask(Open,
    within: 1.minute) is Error(_)
  assert ask(service, "p", Fetch(id: "j_1")) is Unavailable(_)
end
