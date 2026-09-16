module Kv.Store
expose Store, Stores, Opening, Step, Change, Plan, Served, decide, incremented, number, applied, faithful?

use Kv.Log{Table, Logged, Journal, empty, lookup, put, drop, keys_with, entry, reopen}
use Kv.Protocol{Request, Response, Refusal, Counts, key?}

intent "The store process: each request is decided against the table, a change is appended to the journal before it is applied or answered, and a change the journal did not take in time is ERR io with the table unchanged."

never "a change is answered before its log line is durable"
  for s in Step.all
    s.after != s.before and !s.logged
  end
end

never "the store holds a key that breaks the key rules"
  for s in Step.all
    s.after is Some(_) and !key?(s.key)
  end
end

never "a refused request, INCR among them, changes a value"
  for s in Step.all
    s.response is Failed(_) and s.after != s.before
  end
end

# What the store did with a request that changed a key or was refused: the key's value
# before and after, whether the change reached the journal first, and the answer.
struct Step
  key: String
  before: Option(String)
  after: Option(String)
  logged: Bool
  response: Response
end

# A change to one key, and the answer to give once the journal holds it.
struct Change
  key: String
  value: Option(String)
  response: Response
end

enum Plan
  Answer(response: Response)
  Write(change: Change)
end

# After one request: the table, the answer, and the log's size.
struct Served
  table: Table
  response: Response
  log_bytes: UInt64
end

# How a store starts: the table its log replayed to, that log's size, when it opened, and
# how long it waits for the journal to take a change.
struct Opening
  table: Table
  log_bytes: UInt64
  at: Time
  log_within: Duration
end

process Store(journal: Handle(Journal), clock: Clock, opening: Opening)
  state
    table: Table = opening.table
    log_bytes: UInt64 = opening.log_bytes
    sets: UInt64
    gets: UInt64
  end

  invariant "the store never holds more than a million keys"
    state.table.size <= 1_000_000
  end

  message Serve(request: Request) : Response

  fn update(state, message)
    case message
      Serve(request):
        counts = Counts(keys: state.table.size, sets: state.sets, gets: state.gets,
          log_bytes: state.log_bytes, uptime_ms: (clock.now - opening.at).ms)
        outcome = served(journal, opening.log_within, state.table, counts, request)
        state.table = outcome.table
        state.log_bytes = outcome.log_bytes
        state.sets += sets_in(request, outcome.response)
        state.gets += gets_in(request)
        outcome.response
    end
  end
end

# A store that crashed does not come back from the table it opened with, which would forget
# every change since; its clients get ERR io instead.
supervisor Stores(journal: Handle(Journal), clock: Clock, opening: Opening)
  child Store(journal, clock, opening), restart: :never
end

fn served(journal: Handle(Journal), within: Duration, table: Table, counts: Counts,
  request: Request) : Served
  case decide(table, counts, request)
    Answer(response):
      Served(table: table, response: answered(table, request, response),
        log_bytes: counts.log_bytes)
    Write(change): committed(journal, within, table, counts.log_bytes, change)
  end
end

# What a request comes to against the table: an answer now, or a change to log first.
fn decide(table: Table, counts: Counts, request: Request) : Plan
  case request
    Set(key: key, value: value): written(table, key, Some(value), Done)
    Get(key): Answer(response: found(lookup(table, key)))
    Del(key): deleted(table, key)
    Incr(key: key, by: by): bumped(table, key, by)
    Keys(prefix): Answer(response: Listed(keys: keys_with(table, prefix)))
    Stats: Answer(response: Counted(counts: counts))
    Quit: Answer(response: Bye)
  end
end

fn found(value: Option(String)) : Response
  case value
    Some(text): Found(value: text)
    None: Absent
  end
end

# A change that would add a key to a table of a million is refused instead.
fn written(table: Table, key: String, value: Option(String), response: Response) : Plan
  if table.size >= 1_000_000 and lookup(table, key) is None
    return Answer(response: Failed(reason: Full))
  end
  Write(change: Change(key: key, value: value, response: response))
end

fn deleted(table: Table, key: String) : Plan
  return Answer(response: Absent) if lookup(table, key) is None
  Write(change: Change(key: key, value: None, response: Done))
end

fn bumped(table: Table, key: String, by: Int64) : Plan
  case incremented(lookup(table, key), by)
    Ok(new): written(table, key, Some("#{new}"), Found(value: "#{new}"))
    Error(reason): Answer(response: Failed(reason: reason))
  end
end

# INCR's arithmetic: the value read as a decimal Int64, or 0 for a key with none, plus by.
fn incremented(current: Option(String), by: Int64) : Result(Int64, Refusal)
  ensures result is Ok(new) implies number(current) is Some(before) and new == before + by
  ensures result is Error(reason) implies reason == NotANumber or reason == Overflow

  case number(current)
    Some(before): sum_of(before, by)
    None: Error(NotANumber)
  end
end

fn sum_of(before: Int64, by: Int64) : Result(Int64, Refusal)
  case before.checked_add(by)
    Some(total): Ok(total)
    None: Error(Overflow)
  end
end

# A value as INCR reads it: a decimal Int64, or 0 when there is no value.
fn number(current: Option(String)) : Option(Int64)
  case current
    Some(text): text.to_i64
    None: Some(0)
  end
end

# A refusal is recorded as a step, so the nevers see that it changed nothing.
fn answered(table: Table, request: Request, response: Response) : Response
  key = key_of(request) or ""
  here = lookup(table, key)
  step = Step(key: key, before: here, after: here, logged: false, response: response)
  step.response
end

fn key_of(request: Request) : Option(String)
  case request
    Set(key: key, value: _): Some(key)
    Get(key): Some(key)
    Del(key): Some(key)
    Incr(key: key, by: _): Some(key)
    Keys(_) | Stats | Quit: None
  end
end

# The journal puts the change's line on disk first; only then is the change applied and
# answered. A journal that does not answer in time, or whose append failed, is ERR io, and
# the table stays as it was. A line the journal appends after the store's deadline is still
# in the log, as a write that finished late would be.
fn committed(journal: Handle(Journal), within: Duration, table: Table, log_bytes: UInt64,
  change: Change) : Served
  before = lookup(table, change.key)
  line = entry(change.key, change.value)
  grown = applied(table, change)
  case journal.ask(Append(line: line, keys: grown.size), within: within)
    Ok(Ok(bytes)):
      step = Step(key: change.key, before: before, after: lookup(grown, change.key), logged: true,
        response: change.response)
      Served(table: grown, response: step.response, log_bytes: bytes)
    Ok(Error(_)): unlogged(table, log_bytes, change, before)
    Error(_): unlogged(table, log_bytes, change, before)
  end
end

fn unlogged(table: Table, log_bytes: UInt64, change: Change, before: Option(String)) : Served
  step = Step(key: change.key, before: before, after: before, logged: false,
    response: Failed(reason: Io))
  Served(table: table, response: step.response, log_bytes: log_bytes)
end

fn applied(table: Table, change: Change) : Table
  case change.value
    Some(value): put(table, change.key, value)
    None: drop(table, change.key)
  end
end

fn sets_in(request: Request, response: Response) : UInt64
  case request
    Set(key: _, value: _): if response is Failed(_): 0 else: 1
    Get(_) | Del(_) | Incr(key: _, by: _) | Keys(_) | Stats | Quit: 0
  end
end

fn gets_in(request: Request) : UInt64
  case request
    Get(_): 1
    Set(key: _, value: _) | Del(_) | Incr(key: _, by: _) | Keys(_) | Stats | Quit: 0
  end
end

# Asks the store each request, and checks every answer against a table kept beside it: the
# answer that table gives, with the table changed as the store's must be, or ERR io and no
# change. An ask that gets no answer ends the check, since the store may yet take it.
fn faithful?(store: Handle(Store), requests: List(Request)) : Bool
  var model = empty()
  var held = true
  for request in requests
    pair = expected_of(model, request)
    case store.ask(Serve(request: request), within: 60_000.ms)
      Ok(response):
        held = held and agreed?(response, pair.0)
        model = next_table(model, pair, response)
      Error(_):
        break
    end
  end
  held
end

# An answer holds when it is the one the table gives, or an ERR io, which changed nothing.
fn agreed?(response: Response, want: Response) : Bool
  response == want or response == Failed(reason: Io)
end

# The table moves on only when the store gave the answer the table gives.
fn next_table(model: Table, pair: (Response, Table), response: Response) : Table
  return pair.1 if response == pair.0
  model
end

fn expected_of(model: Table, request: Request) : (Response, Table)
  case decide(model, counted_nothing(), request)
    Answer(response): (response, model)
    Write(change): (change.response, applied(model, change))
  end
end

fn counted_nothing() : Counts
  Counts(keys: 0, sets: 0, gets: 0, log_bytes: 0, uptime_ms: 0)
end

fn script() : List(Request)
  first = [Set(key: "a", value: "1"), Get(key: "a"), Incr(key: "a", by: 2),
    Set(key: "big", value: "x".repeat(1_000)), Del(key: "gone")]
  first.concat([Set(key: "new", value: "two words"), Keys(prefix: ""), Del(key: "a"),
    Get(key: "a"), Incr(key: "new", by: 1), Get(key: "new")])
end

fn opened(table: Table, at: Time, log_within: Duration) : Opening
  Opening(table: table, log_bytes: 0, at: at, log_within: log_within)
end

test "GET, SET, DEL, KEYS, and QUIT come to the answers the protocol names"
  table = put(put(empty(), "b", "2"), "a", "1")
  none = counted_nothing()
  assert decide(table, none, Get(key: "a")) == Answer(response: Found(value: "1"))
  assert decide(table, none, Get(key: "zz")) == Answer(response: Absent)
  set = decide(table, none, Set(key: "c", value: "3"))
  assert set == Write(change: Change(key: "c", value: Some("3"), response: Done))
  assert decide(table, none,
    Del(key: "a")) == Write(change: Change(key: "a", value: None, response: Done))
  assert decide(table, none, Del(key: "zz")) == Answer(response: Absent)
  assert decide(table, none, Keys(prefix: "")) == Answer(response: Listed(keys: ["a", "b"]))
  assert decide(table, none, Quit) == Answer(response: Bye)
end

test "STATS answers the counts the store passes in"
  counts = Counts(keys: 2, sets: 5, gets: 7, log_bytes: 40, uptime_ms: 12)
  assert decide(empty(), counts, Stats) == Answer(response: Counted(counts: counts))
end

test "INCR adds to a decimal value, starts a missing key at 0, and refuses a word or an overflow"
  assert incremented(Some("41"), 1) is Ok(42)
  assert incremented(Some("-7"), 7) is Ok(0)
  assert incremented(Some("-7"), 2) is Ok(-5)
  assert incremented(None, 5) is Ok(5)
  assert incremented(Some("forty"), 1) is Error(NotANumber)
  assert incremented(Some(""), 1) is Error(NotANumber)
  assert incremented(Some("9223372036854775807"), 1) is Error(Overflow)
  table = put(empty(), "n", "9223372036854775807")
  assert decide(table, counted_nothing(),
    Incr(key: "n", by: 1)) == Answer(response: Failed(reason: Overflow))
end

test "a new key is refused when the table holds a million, and an existing key is not"
  full = Table(buckets: put(empty(), "a", "1").buckets, size: 1_000_000)
  assert decide(full, counted_nothing(),
    Set(key: "b", value: "2")) == Answer(response: Failed(reason: Full))
  assert decide(full, counted_nothing(), Set(key: "a", value: "2")) is Write(_)
end

test "every answer is the one the table gives, through the journal"
  journal = Journal.start(Fs.fixture(), "kv.log", 0)
  store = Store.start(journal, Clock.fixture(), opened(empty(), Time.fixture(), 60_000.ms))
  assert faithful?(store, script())
end

test "a store whose journal never answers in time answers each change ERR io, and changes nothing"
  never_in_time = 0.ms - 1.ms
  store = Store.start(Journal.start(Fs.fixture(), "kv.log", 0), Clock.fixture(),
    opened(empty(), Time.fixture(), never_in_time))
  assert faithful?(store, script())
  set = store.ask(Serve(request: Set(key: "a", value: "1")), within: 60_000.ms)
  got = store.ask(Serve(request: Get(key: "a")), within: 60_000.ms)
  assert set is Ok(Failed(Io)) or set is Error(_)
  assert got is Ok(Absent) or got is Error(_)
end

# The replay test: a store writes its log, stops, and a store started again from that log
# reads what the first one wrote. An append a fault failed was answered ERR io and is not in
# the log, so the two stores still agree.
test "a store started again from its log reads what the first one wrote"
  dir = Fs.fixture()
  first = Store.start(Journal.start(dir, "kv.log", 0), Clock.fixture(),
    opened(empty(), Time.fixture(), 60_000.ms))
  assert faithful?(first, script())
  counted = first.ask(Serve(request: Stats), within: 60_000.ms)
  text = dir.read("kv.log", within: 60_000.ms)
  if counted is Ok(Counted(counts))
    if text is Ok(log)
      assert reopen(Logged(text: log, keys: counts.keys)) is Ok(reopened)
      second = Store.start(Journal.start(dir, "kv.log", 0), Clock.fixture(),
        opened(reopened.table, Time.fixture(), 60_000.ms))
      for request in [Get(key: "a"), Get(key: "big"), Get(key: "new"), Keys(prefix: "")]
        one = first.ask(Serve(request: request), within: 60_000.ms)
        two = second.ask(Serve(request: request), within: 60_000.ms)
        assert one == two or one is Error(_) or two is Error(_)
      end
    end
  end
end

property "a SET then a GET gives back any valid key's value"
  for key in any(String), value in any(String) if key?(key)
    none = counted_nothing()
    case decide(empty(), none, Set(key: key, value: value))
      Write(change):
        table = applied(empty(), change)
        assert decide(table, none, Get(key: key)) == Answer(response: Found(value: value))
      Answer(_):
        assert false
    end
  end
end

verified: types, contracts, tests (8), property (200 seeds), sim (100 runs, invariants (kept 1, tripped 0))
          proven: not run
