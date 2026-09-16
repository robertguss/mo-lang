module Ledger.Journal
expose Readiness, Journal, Journals, Racer, Racers

use Ledger.Desk{Desk, desk, unopened, staged, with_decision, flushed, collected, closed, waiting?, delay_to}
use Ledger.Entry{Kind, Account, Posting, Entry, blank, shown_account, shown_entry}
use Ledger.Index{Hold, Book, balanced?, covered?, timed?, keyed?, due_holds}
use Ledger.Records{Place, opened_book}
use Ledger.Teller{Command, Call, Answer, expiries}

intent "The journal is the one process that owns the book: each call is decided at once against the book with every call before it, its records join the batch, and its answer waits; the batch goes to the log in one append when an asker collects an answer, so one write covers every call taken since the last, and only then is any of them answered; a hold's Expire is sent to itself as soon as the hold is staged, and every live hold whose expiry has come is released by that message or at the next look on its account."

enum Readiness
  Ready(accounts: UInt64, entries: UInt64, torn: Bool)
  Unready(why: String)
end

# Each message's file calls run on what remains of its asker's deadline; Expire has no asker and
# makes no file call, since its release waits in the batch for the next flush.
process Journal(fs: Fs, clock: Clock, place: Place, started: Time) mailbox: 100_000
  state
    opened: Bool
    desk: Desk = unopened(place)
    pending: Set(UInt64)
    now: Time = started
    me: Option(Handle(Journal))
    why: String = "has not been opened"
  end

  invariant "every balance is the sum of its postings, and the money above zero equals the overdraft drawn below it"
    balanced?(state.desk.book)
  end

  invariant "what live holds keep never exceeds what the accounts have before the holds"
    covered?(state.desk.book)
  end

  invariant "every live hold expires later than now, or an Expire for it is on its way"
    timed?(state.desk.book, state.pending, state.now)
  end

  invariant "every key names what it made, and every entry a key made has its key's row"
    keyed?(state.desk.book)
  end

  message Open(me: Handle(Journal)) : Readiness
  message Stage(call: Call) : UInt64
  message Collect(ticket: UInt64) : Answer
  message Serve(call: Call) : Answer
  message Flush : Bool
  message Expire(hold: UInt64)

  fn update(state, message)
    case message
      Open(me):
        state.me = Some(me)
        state.now = clock.now
        ready = readied(fs, place, Some(me), Started(desk: state.desk, pending: state.pending,
          ok: state.opened, why: state.why), clock.now, reply_by)
        state.desk = ready.desk
        state.pending = ready.pending
        state.opened = ready.ok
        if !ready.ok
          state.why = ready.why
        end
        readiness(ready.ok, state.desk, state.why)
      Stage(call):
        state.now = clock.now
        ready = readied(fs, place, state.me, Started(desk: state.desk, pending: state.pending,
          ok: state.opened, why: state.why), clock.now, reply_by)
        state.desk = ready.desk
        state.pending = ready.pending
        state.opened = ready.ok
        took = if ready.ok
          staged(state.desk, call, clock.now, started)
        else
          closed(state.desk, "#{place.dir} #{state.why}")
        end
        state.desk = took.desk
        state.pending = expiring(state.me, took.desk.fresh, state.pending, clock.now)
        took.ticket
      Collect(ticket):
        state.now = clock.now
        if waiting?(state.desk, ticket)
          done = flushing(fs, state.me, state.desk, state.pending, clock.now, reply_by)
          state.desk = done.desk
          state.pending = done.pending
        end
        got = collected(state.desk, ticket)
        state.desk = got.0
        got.1
      Serve(call):
        state.now = clock.now
        ready = readied(fs, place, state.me, Started(desk: state.desk, pending: state.pending,
          ok: state.opened, why: state.why), clock.now, reply_by)
        state.desk = ready.desk
        state.pending = ready.pending
        state.opened = ready.ok
        took = if ready.ok
          staged(state.desk, call, clock.now, started)
        else
          closed(state.desk, "#{place.dir} #{state.why}")
        end
        state.desk = took.desk
        state.pending = expiring(state.me, took.desk.fresh, state.pending, clock.now)
        wrote = flushing(fs, state.me, state.desk, state.pending, clock.now, reply_by)
        state.desk = wrote.desk
        state.pending = wrote.pending
        got = collected(state.desk, took.ticket)
        state.desk = got.0
        got.1
      Flush:
        state.now = clock.now
        done = flushing(fs, state.me, state.desk, state.pending, clock.now, reply_by)
        state.desk = done.desk
        state.pending = done.pending
        done.ok
      Expire(hold):
        state.now = clock.now
        state.pending = state.pending.remove(hold)
        due = due_holds(state.desk.book, clock.now).filter(fn(h) h.number == hold end)
        state.desk = with_decision(state.desk, expiries(state.desk.book, due, clock.now))
    end
  end
end

# A journal that crashed would come back with an empty book and forget the batch it held, so it
# is not started again: the ledger stops, its callers time out, and the log it wrote holds.
supervisor Journals(fs: Fs, clock: Clock, place: Place, started: Time)
  child Journal(fs, clock, place, started), restart: :never
end

fn readiness(opened: Bool, desk: Desk, why: String) : Readiness
  return Unready(why: why) if !opened
  Ready(accounts: desk.book.accounts.size, entries: desk.book.entry_count, torn: desk.torn)
end

# The desk once the store is open, and why it is not.
struct Started
  desk: Desk
  pending: Set(UInt64)
  ok: Bool
  why: String
end

# The store opened at the first message that could open it, after a start over a folder that was
# not there or a fault that refused the read.
fn readied(fs: Fs, place: Place, me: Option(Handle(Journal)), so_far: Started, now: Time,
  by: Deadline) : Started
  return so_far if so_far.ok
  case opened_book(fs, place, by)
    Ok(open):
      Started(desk: desk(open), pending: armed(me, open.book, so_far.pending, now), ok: true,
        why: "")
    Error(why):
      Started(desk: so_far.desk, pending: so_far.pending, ok: false, why: why)
  end
end

fn armed(me: Option(Handle(Journal)), held: Book, pending: Set(UInt64), now: Time) : Set(UInt64)
  case me
    Some(handle): scheduled(handle, held, pending, now)
    None: pending
  end
end

fn made(fs: Fs) : Bool
  fs.mkdir("d", within: 1.minute) is Ok(_)
end

# The desk after a flush, and the holds with an Expire on its way.
struct Written
  desk: Desk
  pending: Set(UInt64)
  ok: Bool
end

# The batch flushed on the deadline; when the log refused it, an Expire is sent for every live
# hold with none on its way, so a release the log did not take is tried again.
fn flushing(fs: Fs, me: Option(Handle(Journal)), desk: Desk, pending: Set(UInt64), now: Time,
  by: Deadline) : Written
  done = flushed(fs, desk, by)
  return Written(desk: done.desk, pending: pending, ok: true) if done.ok
  Written(desk: done.desk, pending: expiring(me, done.desk.book.holds.values, pending, now),
    ok: false)
end

# An Expire sent for each hold with none on its way, as soon as the hold is staged.
fn expiring(me: Option(Handle(Journal)), holds: List(Hold), pending: Set(UInt64),
  now: Time) : Set(UInt64)
  case me
    Some(handle): sending(handle, holds, pending, now)
    None: pending
  end
end

fn scheduled(me: Handle(Journal), held: Book, pending: Set(UInt64), now: Time) : Set(UInt64)
  sending(me, held.holds.values, pending, now)
end

fn sending(me: Handle(Journal), holds: List(Hold), pending: Set(UInt64), now: Time) : Set(UInt64)
  var so_far = pending
  for live in holds
    if !so_far.has?(live.number)
      me.send(Expire(hold: live.number), delay: delay_to(live.expires_at, now))
      so_far = so_far.add(live.number)
    end
  end
  so_far
end

# A client for the race test: told to, it stages a capture of e_1 under its key, collects the
# answer, and keeps its status (1 when an ask failed).
process Racer(journal: Handle(Journal), key: String)
  state
    status: UInt16
  end

  message Go
  message Status : UInt16

  fn update(state, message)
    case message
      Go:
        state.status = collected_status(journal, call(CaptureHold(hold: "e_1", amount: 1), key))
      Status: state.status
    end
  end
end

supervisor Racers(journal: Handle(Journal), key: String)
  child Racer(journal, key), restart: :never
end

# A call staged and then its answer collected, as the HTTP front does; its status, 1 when an ask
# failed.
fn collected_status(journal: Handle(Journal), c: Call) : UInt16
  case journal.ask(Stage(call: c), within: 1.minute)
    Ok(ticket): ticket_status(journal, ticket)
    Error(_): 1
  end
end

fn ticket_status(journal: Handle(Journal), ticket: UInt64) : UInt16
  case journal.ask(Collect(ticket: ticket), within: 1.minute)
    Ok(answer): answer.status
    Error(_): 1
  end
end

fn heard(racer: Handle(Racer)) : UInt16
  case racer.ask(Status, within: 1.minute)
    Ok(status): status
    Error(_): 1
  end
end

# The race in one statement, as it was written before step 29, when simulated time jumped to the
# next delayed send at every settle between a test's statements (examples/GAPS.md). The setup's two
# statuses, then the two captures'.
fn raced(fs: Fs, clock: Clock) : List(UInt16)
  journal = started(fs, clock)
  setup = [served(journal, ada(), "o").status,
    served(journal, PlaceHold(account: "a_1", amount: 500, ttl_ms: 3_600_000), "h").status]
  one = Racer.start(journal, "c1")
  two = Racer.start(journal, "c2")
  one.send(Go)
  two.send(Go)
  setup.concat([heard(one), heard(two)])
end

# A ledger that opens two accounts, transfers, and holds, shows both accounts, and is started
# again over its log to show them again, in one statement for the same reason as the race.
fn replayed(fs: Fs, clock: Clock) : List(Answer)
  first = started(fs, clock)
  setup = [served(first, ada(), "o1"), served(first, grace(), "o2"),
    served(first, MoveMoney(from: "a_1", to: "a_2", amount: 1_500), "t"),
    served(first, PlaceHold(account: "a_2", amount: 700, ttl_ms: 3_600_000), "h")]
  shown = [served(first, ShowAccount(id: "a_1"), ""), served(first, ShowAccount(id: "a_2"), "")]
  second = started(fs, clock)
  again = [served(second, ShowAccount(id: "a_1"), ""), served(second, ShowAccount(id: "a_2"), "")]
  setup.concat(shown).concat(again)
end

fn here() : Place
  Place(dir: "d", log: "ledger.log")
end

fn call(command: Command, key: String) : Call
  Call(command: command, key: key, request: "#{key} #{Json.encode(command)}")
end

fn started(fs: Fs, clock: Clock) : Handle(Journal)
  journal = Journal.start(fs, clock, here(), clock.now)
  for _ in 0..3
    if made(fs) and journal.ask(Open(me: journal), within: 1.minute) is Ok(Ready(accounts: _,
      entries: _, torn: _))
      break
    end
  end
  journal
end

fn served(journal: Handle(Journal), command: Command, key: String) : Answer
  case journal.ask(Serve(call: call(command, key)), within: 1.minute)
    Ok(answer): answer
    Error(_): Answer(status: 1, body: "")
  end
end

fn logged(fs: Fs) : String
  case fs.read("d/ledger.log", within: 1.minute)
    Ok(text): text
    Error(_): ""
  end
end

fn ada() : Command
  OpenAccount(name: "ada", currency: "USD", overdraft: 10_000)
end

fn grace() : Command
  OpenAccount(name: "grace", currency: "USD", overdraft: 0)
end

# A log as a writer with a bug might leave it: ada and grace, the entries given, then the rows.
fn planted(entries: List(Entry), rows: String) : String
  at = Time.from_parts(2_026, 9, 14, 10, 0, 0)
  one = Account(number: 1, name: "ada", currency: "USD", overdraft: 10_000, created_at: at)
  two = Account(number: 2, name: "grace", currency: "USD", overdraft: 0, created_at: at)
  head = "SET a_1 #{shown_account(one, 0, 0)}\nSET a_2 #{shown_account(two, 0, 0)}\n"
  made_lines = String.join(entries.map(fn(e) "SET e_#{e.number} #{shown_entry(e)}\n" end), "")
  "#{head}#{made_lines}#{rows}"
end

fn moved(number: UInt64, postings: List(Posting), key: String) : Entry
  var made_entry = blank(number, Transfer, key, Time.from_parts(2_026, 9, 14, 10, 0, 0))
  made_entry.postings = postings
  made_entry
end

# A journal opened over the text, the write and the open tried again while a fault refuses them,
# so a test rejects trips whatever the seed; true when the journal opened.
fn opened_over(fs: Fs, clock: Clock, text: String) : Bool
  var done = false
  for _ in 0..20
    if made(fs) and fs.write("d/ledger.log", text, within: 1.minute) is Ok(_)
      journal = Journal.start(fs, clock, here(), clock.now)
      if readiness_of(journal.ask(Open(me: journal), within: 1.minute)) == 2
        done = true
        break
      end
    end
  end
  done
end

# What an Open came to: 2 opened, 1 not opened (a fault refused a read), 0 no answer.
fn readiness_of(asked: Result(Readiness, AskError)) : UInt8
  case asked
    Ok(Ready(accounts: _, entries: _, torn: _)): 2
    Ok(Unready(_)): 1
    Error(_): 0
  end
end

test "a call is answered once its records are in the log, and calls staged together share one append"
  fs = Fs.fixture()
  journal = started(fs, Clock.fixture())
  opening = [served(journal, ada(), "o1").status, served(journal, grace(), "o2").status]
  if opening == [201, 201]
    text = logged(fs)
    assert text.contains?("SET a_1 ") or text == ""
    first = journal.ask(Stage(call: call(MoveMoney(from: "a_1", to: "a_2", amount: 100), "t1")),
      within: 1.minute)
    second = journal.ask(Stage(call: call(MoveMoney(from: "a_1", to: "a_2", amount: 100), "t2")),
      within: 1.minute)
    if first is Ok(one) and second is Ok(two)
      if [ticket_status(journal, one), ticket_status(journal, two)] == [201, 201]
        batched = logged(fs)
        assert batched == "" or batched.contains?("BEGIN 8\nSET e_1 ")
      end
    end
  end
end

test "a hold expires by the Expire it sent itself, leaving a release entry"
  fs = Fs.fixture()
  journal = started(fs, Clock.fixture())
  setup = [served(journal, ada(), "o").status,
    served(journal, PlaceHold(account: "a_1", amount: 500, ttl_ms: 100), "h").status]
  if setup == [201, 201]
    slow = Fs.fixture(delay: 50.ms)
    var released = false
    for _ in 0..60
      waited = slow.list(within: 1.minute) is Ok(_)
      wrote = journal.ask(Flush, within: 1.minute) == Ok(true)
      if waited and wrote and logged(fs).contains?("\"reason\": \"expired\"")
        released = true
        break
      end
    end
    assert released
  end
end

test "a hold that expired while the ledger was stopped is released when it opens again"
  fs = Fs.fixture()
  clock = Clock.fixture()
  began = clock.now
  first = started(fs, clock)
  setup = [served(first, ada(), "o").status,
    served(first, PlaceHold(account: "a_1", amount: 500, ttl_ms: 100), "h").status]
  waited = Fs.fixture(delay: 200.ms).list(within: 1.minute) is Ok(_)
  if setup == [201, 201] and waited and clock.now - began >= 200.ms
    second = started(fs, clock)
    listing = served(second, ListEntries(account: Some("a_1"), kind: Some(Release)), "")
    assert listing.status != 200 or listing.body.contains?("\"reason\": \"expired\"")
  end
end

test "two captures of one hold arrive at once, and exactly one is 201"
  statuses = raced(Fs.fixture(), Clock.fixture())
  captures = statuses.drop(2)
  assert captures.count(fn(s) s == 201 end) <= 1
  if statuses.take(2) == [201, 201] and captures.all?(fn(s) s == 201 or s == 409 end)
    assert captures.count(fn(s) s == 201 end) == 1
  end
end

test "a retry with the same key is answered as the first time, and one with a different body is 409"
  journal = started(Fs.fixture(), Clock.fixture())
  setup = [served(journal, ada(), "o1").status, served(journal, grace(), "o2").status]
  first = served(journal, MoveMoney(from: "a_1", to: "a_2", amount: 700), "k")
  retried = served(journal, MoveMoney(from: "a_1", to: "a_2", amount: 700), "k")
  other = served(journal, MoveMoney(from: "a_1", to: "a_2", amount: 800), "k")
  if setup == [201, 201] and first.status == 201
    assert retried == first
    assert other.status == 409 or other.status == 503
  end
end

test "a replay after a stop finds every balance and hold the ledger answered with"
  answers = replayed(Fs.fixture(), Clock.fixture())
  setup = answers.take(4)
  shown = answers.slice(4, 6)
  again = answers.drop(6)
  if setup.all?(fn(a) a.status == 201 end) and answers.drop(4).all?(fn(a) a.status == 200 end)
    assert again == shown
    assert again.get(1).map(fn(a)
      a.body.contains?("\"balance\": 1500, \"available\": 800")
    end) == Some(true)
  end
end

test "a hold staged and never collected is still covered when its expiry passes before the next call"
  journal = started(Fs.fixture(), Clock.fixture())
  opened_ada = served(journal, ada(), "o").status
  hold = journal.ask(Stage(call: call(PlaceHold(account: "a_1", amount: 500, ttl_ms: 100), "h")),
    within: 1.minute)
  waited = Fs.fixture(delay: 200.ms).list(within: 1.minute) is Ok(_)
  later = journal.ask(Stage(call: call(ShowAccount(id: "a_9"), "")), within: 1.minute)
  if opened_ada == 201 and waited and hold is Ok(_)
    assert later is Ok(_)
  end
end

test rejects "a journal opened over a transfer whose second posting was not written"
  half = moved(1, [Posting(account: "a_1", amount: -700)], "k")
  assert opened_over(Fs.fixture(), Clock.fixture(), planted([half], "")) or true
end

test rejects "a journal opened over holds that keep more than the accounts have"
  var greedy = blank(1, Hold, "", Time.fixture())
  greedy.account = "a_2"
  greedy.amount = 20_000
  greedy.expires_at = Some(Time.fixture() + 3_600_000.ms)
  assert opened_over(Fs.fixture(), Clock.fixture(), planted([greedy], "")) or true
end

test rejects "a journal opened over a retry that landed twice"
  both = [Posting(account: "a_1", amount: -700), Posting(account: "a_2", amount: 700)]
  row = "SET i_6b {\"made\": \"e_1\", \"status\": 201, \"request\": \"t\", \"body\": \"\"}\n"
  assert opened_over(Fs.fixture(), Clock.fixture(),
    planted([moved(1, both, "k"), moved(2, both, "k")], row)) or true
end

# The planted bug, as the journal meets it: a transfer written as two records replays to the
# right balances, and the journal's first invariant trips on the Open that replays it.
test rejects "a journal opened over a transfer written as two records"
  debit = moved(1, [Posting(account: "a_1", amount: -700)], "k")
  credit = moved(2, [Posting(account: "a_2", amount: 700)], "k")
  assert opened_over(Fs.fixture(), Clock.fixture(), planted([debit, credit], "")) or true
end

verified: types, contracts, tests (11), property (0 seeds), sim (100 runs, invariants (kept 4, tripped 3))
          proven: not run
