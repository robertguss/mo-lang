module Ledger.Teller
expose Command, Call, Answer, Decision, Made, decide, expiries, key_record, keyed_of, keyed_json

use Ledger.Book{Refusal, Moved, opened, transferred, held, captured, released, expired, refunded, refusal_body}
use Ledger.Entry{Kind, Account, Entry, account_id, entry_id, number_in, shown_account, shown_entry}
use Ledger.Index{Hold, Keyed, Book, book, keyed, with_keyed, balance, available, account_of_id, entry_at, capture_at, listed, due_holds, due_on, held_total}
use Ledger.Money{Money}
use Ledger.Settle{settled, shown_statement}

intent "The teller takes one call against the book: a key it has seen is answered as the first time, or 409 when the request differs; otherwise every hold whose expiry has come among the accounts the call looks at is released first, then the rule decides, and the answer, the new book, and the records the store must hold before the answer goes out come back together."

never "an idempotency key produces two entries"
  for a in Made.all, b in Made.all if a.key == b.key
    a.entry != b.entry
  end
end

# What a client asks, once its request is read and its fields keep their rules.
enum Command
  OpenAccount(name: String, currency: String, overdraft: Money)
  ShowAccount(id: String)
  MoveMoney(from: String, to: String, amount: Money)
  PlaceHold(account: String, amount: Money, ttl_ms: Int64)
  CaptureHold(hold: String, amount: Money)
  ReleaseHold(hold: String, reason: String)
  RefundCapture(capture: String, amount: Money)
  ListEntries(account: Option(String), kind: Option(Kind))
  SettleDay(day: String)
  CheckHealth
end

# A command with the idempotency key it came with ("" for one that changes nothing) and the
# request a key is compared by: its method, path, and body.
struct Call
  command: Command
  key: String
  request: String
end

struct Answer
  status: UInt16
  body: String
end

# An entry a client's key made.
struct Made
  key: String
  entry: UInt64
end

# A call decided: the book after it, the answer, the store's records in the order they are
# written, the holds it opened (whose Expire goes once they are durable), and the entries keys made.
struct Decision
  book: Book
  answer: Answer
  records: List((String, String))
  holds: List(Hold)
  made: List(Made)
end

# The call decided against the book at `now`; `started` is when the ledger started, for health.
fn decide(book: Book, call: Call, now: Time, started: Time) : Decision
  ensures result.book.entry_count >= book.entry_count
  if call.key != "" and keyed(book, call.key) is Some(row)
    return plain(book, Answer(status: row.status, body: body_of(book, row))) if row.request == call.request
    return plain(book,
      failed(409, "the idempotency key #{call.key} was used with another request"))
  end
  fresh(expiries(book, due_for(book, call.command, now), now), call, now, started)
end

fn plain(book: Book, answer: Answer) : Decision
  Decision(book: book, answer: answer, records: [], holds: [], made: [])
end

fn failed(status: UInt16, error: String) : Answer
  Answer(status: status, body: "{\"error\": #{Json.encode(error)}}")
end

# The body a key's first answer had: a refusal's and a statement's as they were written, an
# account's as it was opened, an entry's as it is.
fn body_of(book: Book, row: Keyed) : String
  return row.body if row.body != ""
  case number_in("e_", row.made)
    Some(number): entry_at(book, number).map(fn(e) shown_entry(e) end) or ""
    None:
      case account_of_id(book, row.made)
        Some(account):
          shown_account(account, balance(book, row.made), available(book, row.made))
        None: ""
      end
  end
end

# The holds whose expiry has come among the accounts the command looks at.
fn due_for(book: Book, command: Command, now: Time) : List(Hold)
  case command
    OpenAccount(name: _, currency: _, overdraft: _): []
    ShowAccount(id): due_on(book, id, now)
    MoveMoney(from: from, to: to, amount: _):
      due_on(book, from, now).concat(due_on(book, to, now))
    PlaceHold(account: account, amount: _, ttl_ms: _): due_on(book, account, now)
    CaptureHold(hold: hold, amount: _): due_on(book, hold_account(book, hold), now)
    ReleaseHold(hold: hold, reason: _): due_on(book, hold_account(book, hold), now)
    RefundCapture(capture: capture, amount: _):
      due_on(book, capture_account(book, capture), now)
    ListEntries(account: account, kind: _): due_on(book, account or "", now)
    SettleDay(_): []
    CheckHealth: due_holds(book, now)
  end
end

fn hold_account(book: Book, hold: String) : String
  book.holds.get(number_in("e_", hold) or 0).map(fn(h) h.account end) or ""
end

fn capture_account(book: Book, capture: String) : String
  capture_at(book, number_in("e_", capture) or 0).map(fn(c) c.account end) or ""
end

# The book with each due hold released as expired, and the records of the releases.
fn expiries(book: Book, due: List(Hold), now: Time) : Decision
  due.reduce(plain(book, Answer(status: 200, body: "")), fn(so_far, live)
    expiry(so_far, live, now)
  end)
end

fn expiry(so_far: Decision, live: Hold, now: Time) : Decision
  return so_far if so_far.book.holds.get(live.number) is None
  done = expired(so_far.book, live, now)
  var next = so_far
  next.book = done.book
  next.records = so_far.records.concat(entry_records(done.book, done.entry))
  next
end

# The call itself, once the looks are folded in.
fn fresh(looked: Decision, call: Call, now: Time, started: Time) : Decision
  case call.command
    OpenAccount(name: name, currency: currency, overdraft: overdraft):
      done = opened(looked.book, name, currency, overdraft, now)
      id = account_id(done.account.number)
      answered(looked, done.book, Answer(status: 201, body: shown_account(done.account, 0, 0)),
        account_record(done.book, id), call, id)
    ShowAccount(id):
      case account_of_id(looked.book, id)
        Some(account):
          shown = shown_account(account, balance(looked.book, id), available(looked.book, id))
          answered(looked, looked.book, Answer(status: 200, body: shown), [], call, "")
        None: answered(looked, looked.book, failed(404, "no account #{id}"), [], call, "")
      end
    MoveMoney(from: from, to: to, amount: amount):
      moved(looked, call, transferred(looked.book, from, to, amount, call.key, now))
    PlaceHold(account: account, amount: amount, ttl_ms: ttl_ms):
      moved(looked, call, held(looked.book, account, amount, ttl_ms, call.key, now))
    CaptureHold(hold: hold, amount: amount):
      moved(looked, call, captured(looked.book, number_in("e_", hold) or 0, amount, call.key, now))
    ReleaseHold(hold: hold, reason: reason):
      moved(looked, call,
        released(looked.book, number_in("e_", hold) or 0, reason, call.key, now))
    RefundCapture(capture: capture, amount: amount):
      moved(looked, call,
        refunded(looked.book, number_in("e_", capture) or 0, amount, call.key, now))
    ListEntries(account: account, kind: kind): listing(looked, call, account, kind)
    SettleDay(day): settling(looked, call, day, now)
    CheckHealth:
      counts = "\"accounts\": #{looked.book.accounts.size}, \"entries\": #{looked.book.entry_count}"
      shown = "{#{counts}, \"held\": #{held_total(looked.book)}, \"uptime_ms\": #{(now - started).ms}}"
      answered(looked, looked.book, Answer(status: 200, body: shown), [], call, "")
  end
end

fn listing(looked: Decision, call: Call, account: Option(String), kind: Option(Kind)) : Decision
  missing = account.map(fn(id) account_of_id(looked.book, id) is None end) or false
  if missing
    return answered(looked, looked.book, failed(404, "no account #{account or ""}"), [], call, "")
  end
  rows = listed(looked.book, account, kind).map(fn(e) shown_entry(e) end)
  shown = "{\"entries\": [#{String.join(rows, ", ")}]}"
  answered(looked, looked.book, Answer(status: 200, body: shown), [], call, "")
end

fn settling(looked: Decision, call: Call, day: String, now: Time) : Decision
  case settled(looked.book, day, call.key, now)
    Ok(done):
      shown = shown_statement(done.statement)
      made = entry_id(done.entry.number)
      wrote = answered(looked, done.book, Answer(status: 201, body: shown),
        entry_records(done.book, done.entry), call, made)
      kept(wrote, call, made, shown)
    Error(refusal): refused(looked, call, refusal)
  end
end

# A settlement's key row keeps the statement it answered with, in the book and in its record,
# since accounts opened later would change a statement shown again.
fn kept(decision: Decision, call: Call, made: String, body: String) : Decision
  return decision if call.key == ""
  row = Keyed(request: call.request, status: 201, body: body, made: made)
  var next = decision
  next.book = with_keyed(decision.book, call.key, row)
  next.records = decision.records.take(decision.records.size - 1).push((key_record(call.key),
    keyed_json(row)))
  next
end

fn moved(looked: Decision, call: Call, outcome: Result(Moved, Refusal)) : Decision
  case outcome
    Ok(done):
      wrote = answered(looked, done.book, Answer(status: 201, body: shown_entry(done.entry)),
        entry_records(done.book, done.entry), call, entry_id(done.entry.number))
      var next = wrote
      next.holds = wrote.holds.concat(listed_hold(done.book.holds.get(done.entry.number)))
      next
    Error(refusal): refused(looked, call, refusal)
  end
end

fn listed_hold(hold: Option(Hold)) : List(Hold)
  case hold
    Some(live): [live]
    None: []
  end
end

fn refused(looked: Decision, call: Call, refusal: Refusal) : Decision
  answered(looked, looked.book, Answer(status: refusal.status, body: refusal_body(refusal)), [],
    call, "")
end

# The decision with its answer, the records the call adds after the looks', and the key's row
# when the call came with a key: the body kept only for a refusal.
fn answered(looked: Decision, book: Book, answer: Answer, records: List((String, String)),
  call: Call, made: String) : Decision
  var next = looked
  next.book = book
  next.answer = answer
  next.records = looked.records.concat(records)
  return next if call.key == ""
  body = if answer.status >= 400: answer.body else: ""
  row = Keyed(request: call.request, status: answer.status, body: body, made: made)
  next.book = with_keyed(book, call.key, row)
  next.records = looked.records.concat(records).push((key_record(call.key), keyed_json(row)))
  next.made = made_under(call.key, made).concat(looked.made)
  next
end

fn made_under(key: String, made: String) : List(Made)
  return [] if !made.starts_with?("e_")
  [Made(key: key, entry: number_in("e_", made) or 0)]
end

# An entry's record, and the record of each account it concerns as the book now has it.
fn entry_records(book: Book, entry: Entry) : List((String, String))
  touched = entry.postings.map(fn(p) p.account end).push(entry.account).unique
  named = touched.filter(fn(id) id != "" end).flat_map(fn(id) account_record(book, id) end)
  [(entry_id(entry.number), shown_entry(entry))].concat(named)
end

fn account_record(book: Book, id: String) : List((String, String))
  case account_of_id(book, id)
    Some(account): [(id, shown_account(account, balance(book, id), available(book, id)))]
    None: []
  end
end

# The store's name for a key's row: i_ and the key's bytes in hex, so any key is a store key.
fn key_record(key: String) : String
  "i_#{String.join(key.bytes.map(fn(b) hex(b) end), "")}"
end

fn hex(b: UInt8) : String
  digits = "0123456789abcdef"
  n = b.to_u64
  "#{digits.slice(n / 16, n / 16 + 1)}#{digits.slice(n % 16, n % 16 + 1)}"
end

# A key row as the store keeps it, `made` first so a replay can read it without decoding.
fn keyed_json(row: Keyed) : String
  made = "{\"made\": #{Json.encode(row.made)}, \"status\": #{row.status}"
  "#{made}, \"request\": #{Json.encode(row.request)}, \"body\": #{Json.encode(row.body)}}"
end

# A key row read back from the store, or None for text that is not one.
fn keyed_of(text: String) : Option(Keyed)
  case Json.decode(text)
    Ok(Object(fields)): keyed_fields(fields)
    Ok(_): None
    Error(_): None
  end
end

fn keyed_fields(fields: Map(String, Json)) : Option(Keyed)
  made = try text_of(try fields.get("made"))
  status = try (try fields.get("status")).to_i64
  return None if status < 0 or status > 65_535
  request = try text_of(try fields.get("request"))
  body = try text_of(try fields.get("body"))
  Some(Keyed(request: request, status: status.to_u16, body: body, made: made))
end

fn text_of(value: Json) : Option(String)
  case value
    String(text): Some(text)
    Object(_): None
    Array(_): None
    Number(_): None
    Bool(_): None
    Null: None
  end
end

fn t0() : Time
  Time.from_parts(2_026, 9, 14, 10, 0, 0)
end

fn asked(command: Command, key: String, request: String) : Call
  Call(command: command, key: key, request: request)
end

# The book after each call in turn at `now`, and the last decision.
fn after_all(book: Book, calls: List(Call), now: Time) : Decision
  calls.reduce(plain(book, Answer(status: 0, body: "")), fn(so_far, call)
    decide(so_far.book, call, now, now)
  end)
end

# Ada, who may go 10,000 below zero, and grace.
fn two() : Book
  first = opened(book(), "ada", "USD", 10_000, t0())
  opened(first.book, "grace", "USD", 0, t0()).book
end

fn names(decision: Decision) : List(String)
  decision.records.map(fn(r) r.0 end)
end

test "an account opens with 201 and reads back with its balance; one that is not there is 404"
  made = decide(two(), asked(OpenAccount(name: "lin", currency: "EUR", overdraft: 0), "o3", "lin"),
    t0(), t0())
  assert made.answer.status == 201 and names(made) == ["a_3", "i_6f33"]
  assert made.answer.body.starts_with?("{\"id\": \"a_3\", \"name\": \"lin\", \"currency\": \"EUR\"")
  shown = decide(made.book, asked(ShowAccount(id: "a_3"), "", ""), t0(), t0())
  assert shown.answer.status == 200 and shown.records == []
  assert decide(two(), asked(ShowAccount(id: "a_9"), "", ""), t0(), t0()).answer.status == 404
end

test "a transfer writes its entry, both accounts, and its key's row, in that order"
  paid = decide(two(), asked(MoveMoney(from: "a_1", to: "a_2", amount: 1_500), "k1", "t1"), t0(),
    t0())
  assert paid.answer.status == 201 and names(paid) == ["e_1", "a_1", "a_2", "i_6b31"]
  assert paid.made == [Made(key: "k1", entry: 1)]
  assert keyed_of(paid.records.last.map(fn(r) r.1 end) or "") == Some(Keyed(request: "t1",
    status: 201, body: "", made: "e_1"))
end

test "a key seen with the same request is answered as the first time and makes nothing; with another it is 409"
  first = decide(two(), asked(MoveMoney(from: "a_1", to: "a_2", amount: 1_500), "k", "t"), t0(),
    t0())
  again = decide(first.book, asked(MoveMoney(from: "a_1", to: "a_2", amount: 1_500), "k", "t"),
    t0(), t0())
  assert again.answer == first.answer and again.records == [] and again.made == []
  assert again.book.entry_count == 1
  other = decide(first.book, asked(MoveMoney(from: "a_1", to: "a_2", amount: 5), "k", "t5"), t0(),
    t0())
  assert other.answer.status == 409 and other.records == [] and other.book.entry_count == 1
end

test "a refusal under a key is answered the same again, even once the funds are there"
  short = decide(two(), asked(MoveMoney(from: "a_2", to: "a_1", amount: 100), "g", "g"), t0(), t0())
  assert short.answer.status == 422 and names(short) == ["i_67"]
  funded = decide(short.book, asked(MoveMoney(from: "a_1", to: "a_2", amount: 500), "f", "f"), t0(),
    t0())
  retried = decide(funded.book, asked(MoveMoney(from: "a_2", to: "a_1", amount: 100), "g", "g"),
    t0(), t0())
  assert retried.answer == short.answer
end

test "a hold past its expiry is released at the next look on its account, before the call decides"
  held_book = decide(two(), asked(PlaceHold(account: "a_1", amount: 5_000, ttl_ms: 100), "h", "h"),
    t0(), t0())
  assert held_book.holds.size == 1 and held_book.answer.status == 201
  later = t0() + 1_000.ms
  late = decide(held_book.book, asked(CaptureHold(hold: "e_1", amount: 10), "c", "c"), later, t0())
  assert late.answer.status == 409 and late.answer.body.contains?("e_1 was expired")
  assert names(late) == ["e_2", "a_1", "i_63"]
  assert late.book.holds.size == 0 and late.book.entry_count == 2
  health = decide(held_book.book, asked(CheckHealth, "", ""), later, t0())
  assert health.answer.body == "{\"accounts\": 2, \"entries\": 2, \"held\": 0, \"uptime_ms\": 1000}"
  assert names(health) == ["e_2", "a_1"]
end

test "a settlement under a key shows the same statement again, though an account opened since"
  settled_book = decide(two(), asked(SettleDay(day: "2026-09-14"), "s", "s"), t0(), t0())
  assert settled_book.answer.status == 201 and settled_book.made == [Made(key: "s", entry: 1)]
  more = decide(settled_book.book,
    asked(OpenAccount(name: "lin", currency: "USD", overdraft: 0), "o", "o"), t0(), t0())
  again = decide(more.book, asked(SettleDay(day: "2026-09-14"), "s", "s"), t0(), t0())
  assert again.answer == settled_book.answer
  twice = decide(more.book, asked(SettleDay(day: "2026-09-14"), "s2", "s2"), t0(), t0())
  assert twice.answer.status == 409
end

test "a listing is by id, of an account and a kind, and an account that is not there is 404"
  calls = [asked(MoveMoney(from: "a_1", to: "a_2", amount: 1), "k1", "1"),
    asked(PlaceHold(account: "a_1", amount: 1, ttl_ms: 60_000), "k2", "2"),
    asked(MoveMoney(from: "a_2", to: "a_1", amount: 1), "k3", "3")]
  busy = after_all(two(), calls, t0()).book
  listing = decide(busy, asked(ListEntries(account: Some("a_2"), kind: Some(Transfer)), "", ""),
    t0(), t0())
  assert listing.answer.status == 200
  assert listing.answer.body.starts_with?("{\"entries\": [{\"id\": \"e_1\"")
  assert listing.answer.body.contains?("\"id\": \"e_3\"") and !listing.answer.body.contains?("e_2")
  missing = decide(busy, asked(ListEntries(account: Some("a_7"), kind: None), "", ""), t0(), t0())
  assert missing.answer.status == 404
end

test "a key's row reads back from the store, and a key of any bytes names a store record"
  row = Keyed(request: "POST /settle\n{\"day\": \"x\"}", status: 409, body: "{\"error\": \"no\"}",
    made: "")
  assert keyed_of(keyed_json(row)) == Some(row)
  assert keyed_of("{\"made\": \"\"}") is None and keyed_of("nope") is None
  assert key_record("a b") == "i_612062" and key_record("é") == "i_c3a9"
end

verified: types, contracts, tests (8), property (0 seeds), sim (not run)
          proven: not run
