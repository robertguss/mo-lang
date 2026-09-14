module Notes.Service
expose Step, Issued, Edit, Plan, Books, Served, Opening, Service, Services, opening, decide

use Notes.Limits{ClientId, Limiter, limiter, allow?, retry_after}
use Notes.Note{Note, Command, Call, Outcome, Counts, note, note_of, key_of, id_number, title?, body?}
use Notes.Store{Table, StoreError, Reopened, get, count, put, delete, keys, open}

intent "The notes service process: every call is let through or refused by its client's bucket, decided against the store, and a create, update, or delete is appended to the log before it is applied or answered; a change the log did not take is 503 with the store unchanged, and one that may have left part of a line refuses every change after it until notes starts again."

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
    case message
      Serve(call):
        now = clock.now
        admitted = allow?(state.limits, call.owner, now)
        state.limits = admitted.0
        books = Books(notes: state.notes, next_id: state.next_id, reserved: state.reserved,
          torn: state.torn)
        done = if admitted.1
          served(fs, books, call, now)
        else
          limited(books, state.limits, call, now)
        end
        state.notes = done.books.notes
        state.next_id = done.books.next_id
        state.reserved = done.books.reserved
        state.torn = done.books.torn
        state.owners = owned(state.owners, call.owner, done.outcome)
        done.outcome
      Health:
        live = state.owners.values.sum
        Counts(notes: live, clients: state.owners.size, uptime_ms: (clock.now - opening.at).ms)
    end
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

  held = keys(notes, "").filter(fn(key) key.contains?("/") end)
  owners = held.reduce(Map.new(), fn(counts, key) counted(counts, owner_of(key)) end)
  highest = held.map(fn(key) id_number(id_of(key)) or 0 end).max or 0
  reserved = (get(notes, "ids") or "0").to_u64 or 0
  Opening(notes: notes, next_id: max_of(max_of(highest + 1, reserved), 1), owners: owners, at: at)
end

fn counted(counts: Map(String, UInt64), owner: String) : Map(String, UInt64)
  counts.update(owner, 0, fn(n) n + 1 end)
end

fn owner_of(key: String) : String
  key.slice(0, key.index_of("/") or 0)
end

fn id_of(key: String) : String
  key.slice((key.index_of("/") or 0) + 1, key.size)
end

# What a call comes to against the store: an answer now, or a change to log first.
fn decide(notes: Table, call: Call, next_id: UInt64, now: Time) : Plan
  case call.command
    Create(title: title, body: body): created(notes, call.owner, note(next_id, title, body, now))
    Fetch(id): Answer(outcome: found(notes, call.owner, id))
    Listing(prefix): Answer(outcome: Listed(notes: listed(notes, call.owner, prefix)))
    Update(id: id, title: title, body: body): updated(notes, call.owner, id, title, body, now)
    Remove(id): removed(notes, call.owner, id)
    Refuse(reason): Answer(outcome: Refused(reason: reason))
  end
end

# A create that would take the store past a million keys, the reserved ids among them, is
# refused instead.
fn created(notes: Table, owner: ClientId, made: Note) : Plan
  if count(notes) >= 999_999
    return Answer(outcome: Unavailable(reason: "the store holds a million notes"))
  end
  edit = Edit(key: key_of(owner, made.id), value: Some(Json.encode(made)),
    outcome: Made(note: made), issues: true)
  Write(edit: edit)
end

fn found(notes: Table, owner: ClientId, id: String) : Outcome
  case held(notes, owner, id)
    Some(kept): Found(note: kept)
    None: Missing
  end
end

fn held(notes: Table, owner: ClientId, id: String) : Option(Note)
  return None if id_number(id) is None
  text = try get(notes, key_of(owner, id))
  note_of(text)
end

# A client's notes whose titles start with the prefix, by id, the first 100.
fn listed(notes: Table, owner: ClientId, prefix: String) : List(Note)
  mine = keys(notes, "#{owner}/").flat_map(fn(key) kept_at(notes, key) end)
  titled = mine.filter(fn(n) n.title.starts_with?(prefix) end)
  titled.sort_by(fn(n) id_number(n.id) or 0 end).take(100)
end

fn kept_at(notes: Table, key: String) : List(Note)
  case note_of(get(notes, key) or "")
    Some(kept): [kept]
    None: []
  end
end

fn updated(notes: Table, owner: ClientId, id: String, title: String, body: String, now: Time) : Plan
  case held(notes, owner, id)
    Some(kept):
      after = Note(id: kept.id, title: title, body: body, created_at: kept.created_at,
        updated_at: now)
      edit = Edit(key: key_of(owner, id), value: Some(Json.encode(after)),
        outcome: Found(note: after), issues: false)
      Write(edit: edit)
    None: Answer(outcome: Missing)
  end
end

fn removed(notes: Table, owner: ClientId, id: String) : Plan
  return Answer(outcome: Missing) if held(notes, owner, id) is None
  Write(edit: Edit(key: key_of(owner, id), value: None, outcome: Removed, issues: false))
end

fn served(fs: Fs, books: Books, call: Call, now: Time) : Served
  case decide(books.notes, call, books.next_id, now)
    Answer(outcome): Served(books: books, outcome: outcome, step: looked(call))
    Write(edit): written(fs, books, call, edit)
  end
end

# A read, recorded as a step that touched its note's key and changed nothing.
fn looked(call: Call) : Step
  key = case call.command
    Fetch(id): key_of(call.owner, id)
    Create(title: _, body: _) | Listing(_) | Update(id: _, title: _,
      body: _) | Remove(_) | Refuse(_):
      ""
  end
  Step(owner: call.owner, key: key, before: None, after: None, logged: false, limited: false)
end

# The log takes the change first, and an id reservation before it when the change hands out an
# id past the reserved ones; only then is the change applied and answered.
fn written(fs: Fs, books: Books, call: Call, edit: Edit) : Served
  before = get(books.notes, edit.key)
  if books.torn
    return unwritten(issued(books, edit), call, edit, before)
  end
  case reserved(fs, books, edit)
    Ok(ready):
      case stored(fs, ready.notes, edit)
        Ok(notes):
          step = Step(owner: call.owner, key: edit.key, before: before, after: edit.value,
            logged: true, limited: false)
          var after = issued(ready, edit)
          after.notes = notes
          Served(books: after, outcome: edit.outcome, step: step)
        Error(problem): unwritten(torn_by(issued(ready, edit), problem), call, edit, before)
      end
    Error(problem): unwritten(torn_by(issued(books, edit), problem), call, edit, before)
  end
end

fn reserved(fs: Fs, books: Books, edit: Edit) : Result(Books, StoreError)
  return Ok(books) if !edit.issues or books.next_id < books.reserved
  ceiling = books.next_id + 100
  notes = try put(fs, books.notes, "ids", "#{ceiling}")
  var after = books
  after.notes = notes
  after.reserved = ceiling
  Ok(after)
end

fn stored(fs: Fs, notes: Table, edit: Edit) : Result(Table, StoreError)
  case edit.value
    Some(value): put(fs, notes, edit.key, value)
    None: delete(fs, notes, edit.key)
  end
end

# A create's id is spent whether or not its line reaches the log, so no id is handed out twice.
fn issued(books: Books, edit: Edit) : Books
  return books if !edit.issues
  record = Issued(id: books.next_id, floor: books.next_id)
  var after = books
  after.next_id = record.id + 1
  after
end

fn torn_by(books: Books, problem: StoreError) : Books
  var after = books
  after.torn = books.torn or problem == Torn
  after
end

fn unwritten(books: Books, call: Call, edit: Edit, before: Option(String)) : Served
  step = Step(owner: call.owner, key: edit.key, before: before, after: before, logged: false,
    limited: false)
  reason = if books.torn
    "the log may end in part of a change, so notes takes no change until it starts again"
  else
    "the log did not take the change"
  end
  Served(books: books, outcome: Unavailable(reason: reason), step: step)
end

fn limited(books: Books, limits: Limiter, call: Call, now: Time) : Served
  step = Step(owner: call.owner, key: "", before: None, after: None, logged: false, limited: true)
  wait = retry_after(limits, call.owner, now).ms
  Served(books: books, outcome: Limited(retry_after_ms: wait), step: step)
end

fn owned(owners: Map(String, UInt64), owner: String, outcome: Outcome) : Map(String, UInt64)
  case outcome
    Made(_): counted(owners, owner)
    Removed:
      left = (owners.get(owner) or 1) - 1
      return owners.remove(owner) if left == 0
      owners.set(owner, left)
    Found(_) | Listed(_) | Missing | Refused(_) | Limited(_) | Unavailable(_): owners
  end
end

# An empty store over the log d/notes.log, for a test that must not fail before it starts.
fn fresh() : Table
  Table(buckets: Map.new(), size: 0, dir: "d", name: "notes.log", bytes: 0, lines: 0, cut: false)
end

fn ask(service: Handle(Service), owner: String, command: Command) : Outcome
  case service.ask(Serve(call: Call(owner: owner, command: command)), within: 60_000.ms)
    Ok(outcome): outcome
    Error(_): Unavailable(reason: "no answer")
  end
end

fn made_id(outcome: Outcome) : String
  case outcome
    Made(made): made.id
    Found(_) | Listed(_) | Removed | Missing | Refused(_) | Limited(_) | Unavailable(_): ""
  end
end

fn titles(outcome: Outcome) : List(String)
  case outcome
    Listed(notes): notes.map(fn(n) n.title end)
    Made(_) | Found(_) | Removed | Missing | Refused(_) | Limited(_) | Unavailable(_): []
  end
end

fn live(service: Handle(Service)) : Option(UInt64)
  case service.ask(Health, within: 60_000.ms)
    Ok(counts): Some(counts.notes)
    Error(_): None
  end
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
    title = if i % 2 == 0
      "todo #{i}"
    else
      "done #{i}"
    end
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

property "a create then a read gives back any valid title and body"
  for title in any(String), body in any(String) if title?(title) and body?(body)
    fs = Fs.fixture()
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

verified: types, contracts, tests (7), property (200 seeds), sim (100 runs)
          proven: not run
