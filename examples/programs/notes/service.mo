module Notes.Service
expose Step, Issued, Edit, Plan, Books, Served, Opening, Service, Services, opening, decide

use Notes.Limits{ClientId, Limiter, limiter, allow?, retry_after}
use Notes.Note{Note, Command, Call, Outcome, Counts, note, note_of, key_of, owner_of, id_of, counted, id_number, title?, body?}
use Notes.Store{Table, StoreError, Reopened, get, count, put, delete, keys, open, compact}

intent "The notes service process: every call is let through or refused by its client's bucket, decided against the store, and a create, update, or delete is appended to the log before it is applied or answered; a change the log did not take is 503 with the store unchanged, and one that may have left part of a line has the log rewritten whole before the next change, so changes are taken again once faults stop."

never "a response is sent before its log line is durable"
  for s in Step.all
    s.after != s.before and !s.logged
  end
end

never "a client reads, changes, or deletes another client's note"
  for s in Step.all
    s.key != "" and !s.key.starts_with?("#{s.owner}/")
  end
end

never "an id is reused, restart or not"
  for i in Issued.all
    i.id < i.floor
  end
end

never "a rate-limited request changes the store"
  for s in Step.all
    s.limited and s.after != s.before
  end
end

# What one call did to the store: the key it touched, or "", its value before and after,
# whether the change reached the log first, and whether the call was rate-limited.
struct Step
  owner: String
  key: String
  before: Option(String)
  after: Option(String)
  logged: Bool
  limited: Bool
end

# An id handed out, beside the lowest id not yet handed out when it was.
struct Issued
  id: UInt64
  floor: UInt64
end

# A change to one key, the answer to give once the log holds it, and whether it hands out the
# next id.
struct Edit
  key: String
  value: Option(String)
  outcome: Outcome
  issues: Bool
end

enum Plan
  Answer(outcome: Outcome)
  Write(edit: Edit)
end

# The notes, the next id, the id below which ids are reserved in the log, and whether an append
# may have left part of a line.
struct Books
  notes: Table
  next_id: UInt64
  reserved: UInt64
  torn: Bool
end

struct Served
  books: Books
  outcome: Outcome
  step: Step
end

# How a service starts: the store its log replayed to, the next id, each client's live
# notes, and when it opened.
struct Opening
  notes: Table
  next_id: UInt64
  owners: Map(String, UInt64)
  at: Time
end

process Service(fs: Fs, clock: Clock, opening: Opening)
  state
    notes: Table = opening.notes
    next_id: UInt64 = opening.next_id
    reserved: UInt64 = opening.next_id
    torn: Bool
    owners: Map(String, UInt64) = opening.owners
    limits: Limiter = limiter(60, 1.minute)
  end

  invariant "the service never holds more than a million notes"
    state.notes.size <= 1_000_000
  end

  invariant "the id counter never goes backwards"
    state.next_id >= old(state.next_id)
  end

  message Serve(call: Call) : Outcome
  message Health : Counts

  fn update(state, message)
    # body gone; regenerate
  end
end

# A service that crashed would come back from the store it opened with and forget every change
# since, so it is not started again; its clients get 503 instead.
supervisor Services(fs: Fs, clock: Clock, opening: Opening)
  child Service(fs, clock, opening), restart: :never
end

# How a service starts over a store just opened: each client's live notes, and a next id above
# every id the log holds and every id it reserved.
fn opening(notes: Table, at: Time) : Opening
  ensures result.next_id >= 1
  # body gone; regenerate
end

# What a call comes to against the store: an answer now, or a change to log first.
fn decide(notes: Table, call: Call, next_id: UInt64, now: Time) : Plan
  # body gone; regenerate
end

# A create that would take the store past a million keys, the reserved ids among them, is
# refused instead.
fn created(notes: Table, owner: ClientId, made: Note) : Plan
  # body gone; regenerate
end

fn found(notes: Table, owner: ClientId, id: String) : Outcome
  # body gone; regenerate
end

fn held(notes: Table, owner: ClientId, id: String) : Option(Note)
  # body gone; regenerate
end

# A client's notes whose titles start with the prefix, by id, the first 100.
fn listed(notes: Table, owner: ClientId, prefix: String) : List(Note)
  # body gone; regenerate
end

fn kept_at(notes: Table, key: String) : List(Note)
  # body gone; regenerate
end

fn updated(notes: Table, owner: ClientId, id: String, title: String, body: String, now: Time) : Plan
  # body gone; regenerate
end

fn removed(notes: Table, owner: ClientId, id: String) : Plan
  # body gone; regenerate
end

fn served(fs: Fs, books: Books, call: Call, now: Time) : Served
  # body gone; regenerate
end

# A read, recorded as a step that touched its note's key and changed nothing.
fn looked(call: Call) : Step
  # body gone; regenerate
end

# The log takes the change first, and an id reservation before it when the change hands out an
# id past the reserved ones; only then is the change applied and answered. A log that may end in
# part of a change is rewritten whole first, as the store recipe says.
fn written(fs: Fs, books: Books, call: Call, edit: Edit) : Served
  # body gone; regenerate
end

fn reserved(fs: Fs, books: Books, edit: Edit) : Result(Books, StoreError)
  # body gone; regenerate
end

fn stored(fs: Fs, notes: Table, edit: Edit) : Result(Table, StoreError)
  # body gone; regenerate
end

# A create's id is spent whether or not its line reaches the log, so no id is handed out twice.
fn issued(books: Books, edit: Edit) : Books
  # body gone; regenerate
end

fn torn_by(books: Books, problem: StoreError) : Books
  # body gone; regenerate
end

fn unwritten(books: Books, call: Call, edit: Edit, before: Option(String)) : Served
  # body gone; regenerate
end

fn limited(books: Books, limits: Limiter, call: Call, now: Time) : Served
  # body gone; regenerate
end

fn owned(owners: Map(String, UInt64), owner: String, outcome: Outcome) : Map(String, UInt64)
  # body gone; regenerate
end

# An empty store over the log d/notes.log, for a test that must not fail before it starts.
fn fresh() : Table
  # body gone; regenerate
end

fn ask(service: Handle(Service), owner: String, command: Command) : Outcome
  # body gone; regenerate
end

fn made_id(outcome: Outcome) : String
  # body gone; regenerate
end

fn titles(outcome: Outcome) : List(String)
  # body gone; regenerate
end

fn live(service: Handle(Service)) : Option(UInt64)
  # body gone; regenerate
end

test "create, read, list, update, and delete answer with the note or 404"
  fs = Fs.fixture()
  service = Service.start(fs, Clock.fixture(), opening(fresh(), Time.fixture()))
  made = ask(service, "ada", Create(title: "groceries", body: "eggs"))
  assert made is Made(_) or made is Unavailable(_)
  id = made_id(made)
  if id != ""
    assert ask(service, "ada", Fetch(id: id)) is Found(kept)
    assert kept.title == "groceries" and kept.body == "eggs"
    changed = ask(service, "ada", Update(id: id, title: "shopping", body: "eggs, milk"))
    assert changed is Found(_) or changed is Unavailable(_)
    assert ask(service, "ada", Fetch(id: "n_999")) == Missing
    assert ask(service, "ada", Fetch(id: "nope")) == Missing
    gone = ask(service, "ada", Remove(id: id))
    assert gone == Removed or gone is Unavailable(_)
    if gone == Removed
      assert ask(service, "ada", Fetch(id: id)) == Missing
      assert ask(service, "ada", Remove(id: id)) == Missing
    end
  end
  assert ask(service, "ada", Refuse(reason: "no title")) == Refused(reason: "no title")
end

test "a client never sees, changes, or deletes another client's note"
  fs = Fs.fixture()
  service = Service.start(fs, Clock.fixture(), opening(fresh(), Time.fixture()))
  id = made_id(ask(service, "ada", Create(title: "mine", body: "")))
  if id != ""
    assert ask(service, "grace", Fetch(id: id)) == Missing
    assert ask(service, "grace", Update(id: id, title: "hers", body: "")) == Missing
    assert ask(service, "grace", Remove(id: id)) == Missing
    assert titles(ask(service, "grace", Listing(prefix: ""))) == []
    assert ask(service, "ada", Fetch(id: id)) is Found(_)
  end
end

test "the sixty-first call in a minute is 429 and changes nothing"
  fs = Fs.fixture()
  service = Service.start(fs, Clock.fixture(), opening(fresh(), Time.fixture()))
  for _ in 0..60
    assert !(ask(service, "ada", Listing(prefix: "")) is Limited(_))
  end
  assert ask(service, "ada", Create(title: "one too many", body: "")) is Limited(wait)
  assert wait > 0 and wait <= 60_000
  assert ask(service, "grace", Listing(prefix: "")) is Listed(_)
  assert live(service) == Some(0) or live(service) is None
end

test "a list is the client's notes whose titles start with the prefix, by id, at most 100"
  fs = Fs.fixture()
  service = Service.start(fs, Clock.fixture(), opening(fresh(), Time.fixture()))
  var made = 0
  for i in 0..12
    title = if i % 2 == 0: "todo #{i}" else: "done #{i}"
    if ask(service, "ada", Create(title: title, body: "")) is Made(_)
      made += 1
    end
  end
  listed_titles = titles(ask(service, "ada", Listing(prefix: "todo")))
  assert listed_titles.all?(fn(t) t.starts_with?("todo") end)
  assert listed_titles.size <= 6
  if made == 12
    assert listed_titles == ["todo 0", "todo 2", "todo 4", "todo 6", "todo 8", "todo 10"]
  end
end

# The replay test: a service writes its log, stops, and a service started again from that log
# lists what the first one wrote, holds as many notes, and hands out no id twice.
test "a service started again from its log lists what the first one wrote, and reuses no id"
  fs = Fs.fixture()
  first = Service.start(fs, Clock.fixture(), opening(fresh(), Time.fixture()))
  var ids = [""].take(0)
  for i in 0..4
    ids = ids.push(made_id(ask(first, "ada", Create(title: "note #{i}", body: "body #{i}"))))
  end
  last = ids.last or ""
  if last != "" and ask(first, "ada", Remove(id: last)) == Removed
    before = ask(first, "ada", Listing(prefix: ""))
    if open(fs, "d") is Ok(replayed)
      again = opening(replayed, Time.fixture())
      record = Reopened(before: (live(first) or 0), after: again.owners.values.sum)
      assert record.after == record.before or live(first) is None
      second = Service.start(fs, Clock.fixture(), again)
      assert ask(second, "ada", Listing(prefix: "")) == before
      spent = ids.map(fn(i) id_number(i) or 0 end).max or 0
      made = ask(second, "ada", Create(title: "after", body: ""))
      record_id = Issued(id: id_number(made_id(made)) or spent + 1, floor: spent + 1)
      assert record_id.id >= record_id.floor
    end
  end
end

test "a log a failed change may have torn is rewritten whole at the next change, which is taken"
  fs = Fs.fixture()
  at = Time.fixture()
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert open(fs, "d") is Ok(notes)
  books = Books(notes: notes, next_id: 1, reserved: 1, torn: false)
  create = Call(owner: "ada", command: Create(title: "one", body: ""))
  torn = served(Fs.fixture(delay: 1.minute), books, create, at)
  assert torn.outcome is Unavailable(_) and torn.books.torn
  again = served(fs, torn.books, create, at)
  assert again.outcome is Made(_) and !again.books.torn
  assert open(fs, "d") is Ok(replayed)
  assert count(replayed) == count(again.books.notes)
end

property "a create then a read gives back any valid title and body"
  for title in any(String), body in any(String) if title?(title) and body?(body)
    fs = Fs.fixture()
    assert fs.mkdir("d", within: 1.minute) is Ok(_)
    assert open(fs, "d") is Ok(empty)
    call = Call(owner: "ada", command: Create(title: title, body: body))
    case decide(empty, call, 1, Time.fixture())
      Write(edit):
        assert put(fs, empty, edit.key, edit.value or "") is Ok(notes)
        fetch = Call(owner: "ada", command: Fetch(id: "n_1"))
        assert decide(notes, fetch, 2, Time.fixture()) is Answer(Found(kept))
        assert kept.title == title and kept.body == body
      Answer(_):
        assert false
    end
  end
end

test rejects "a call from a client whose token holds a slash"
  service = Service.start(Fs.fixture(), Clock.fixture(), opening(fresh(), Time.fixture()))
  call = Call(owner: "ada/grace", command: Fetch(id: "n_1"))
  service.send(Serve(call: call))
end
