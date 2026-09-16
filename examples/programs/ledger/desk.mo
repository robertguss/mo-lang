module Ledger.Desk
expose Sent, Staged, Desk, Took, Flushed, desk, unopened, staged, with_decision, flushed, collected, closed, waiting?, delay_to

use Ledger.Index{Hold, Book, book}
use Ledger.Records{Place, Opened, opened_book, flushed_to, rewritten_from}
use Ledger.Store{Table, StoreError}
use Ledger.Teller{Command, Call, Answer, Decision, decide}

intent "The journal's desk: the book answers come from with every call in the batch, the book as the log holds it, the batch's records and waiting answers, and the flush that writes the batch in one append and answers every call in it, or answers them all 503 and puts the book back as the log holds it."

never "a response is sent before its entry is durable"
  for s in Sent.all
    s.changed and !s.durable
  end
end

# An answer as it is handed out: whether its call changed the log, and whether that was on disk.
struct Sent
  changed: Bool
  durable: Bool
end

# A call waiting in the batch: its ticket, its answer, and whether it added records.
struct Staged
  ticket: UInt64
  answer: Answer
  wrote: Bool
end

# The book answers come from, with every call in the batch; the book as the log holds it; the log;
# whether it may end in part of a batch; the batch's records, calls, and holds; the answers
# flushed and not yet collected; and the next ticket.
struct Desk
  book: Book
  durable: Book
  table: Table
  torn: Bool
  records: List((String, String))
  staged: List(Staged)
  fresh: List(Hold)
  answers: Map(UInt64, Answer)
  next: UInt64
end

struct Took
  desk: Desk
  ticket: UInt64
end

# A batch written or refused: the desk after it, the holds now durable, whether the log took it,
# and each answer as it is handed out.
struct Flushed
  desk: Desk
  fresh: List(Hold)
  ok: Bool
  sent: List(Sent)
end

fn desk(opened: Opened) : Desk
  Desk(book: opened.book, durable: opened.book, table: opened.table, torn: opened.torn,
    records: [], staged: [], fresh: [], answers: Map.new(), next: 1)
end

# The desk a journal holds before it opens: an empty book over the place's log.
fn unopened(place: Place) : Desk
  empty = Table(buckets: Map.new(), size: 0, dir: place.dir, name: place.log, bytes: 0, lines: 0,
    cut: false)
  Desk(book: book(), durable: book(), table: empty, torn: false, records: [], staged: [],
    fresh: [], answers: Map.new(), next: 1)
end

# The call decided against the book with the batch in it; its answer waits for the flush.
fn staged(desk: Desk, call: Call, now: Time, started: Time) : Took
  done = decide(desk.book, call, now, started)
  ticket = desk.next
  var next = desk
  next.book = done.book
  next.records = desk.records.concat(done.records)
  next.staged = desk.staged.push(Staged(ticket: ticket, answer: done.answer,
    wrote: done.records.size > 0))
  next.fresh = desk.fresh.concat(done.holds)
  next.next = desk.next + 1
  Took(desk: next, ticket: ticket)
end

# A decision's book, records, and holds joined to the batch with no call waiting on it: the
# releases an Expire or an opening stages.
fn with_decision(desk: Desk, done: Decision) : Desk
  var next = desk
  next.book = done.book
  next.records = desk.records.concat(done.records)
  next.fresh = desk.fresh.concat(done.holds)
  next
end

# The batch written: appended in one write, or, when the log may end in part of a batch, the log
# written whole from the book, which holds the batch too. A batch the log did not take answers
# every call in it 503 and puts the book back as the log holds it; when that write may have left
# part of the batch, the log is written whole from that book at once, so the 503 changed nothing.
fn flushed(fs: Fs, desk: Desk, by: Deadline) : Flushed
  ensures result.sent.size == desk.staged.size
  return took(desk, desk.table, false) if desk.records.size == 0 and !desk.torn
  written = if desk.torn
    rewritten_from(fs, desk.table, desk.book, by)
  else
    flushed_to(fs, desk.table, desk.records, by)
  end
  case written
    Ok(table): took(desk, table, true)
    Error(problem): refused(fs, desk, problem, by)
  end
end

# The batch on disk: every staged answer ready, the log as it now is, and nothing torn.
fn took(desk: Desk, table: Table, changed: Bool) : Flushed
  Flushed(desk: answered_all(desk, desk.book, table, false), fresh: desk.fresh, ok: true,
    sent: desk.staged.map(fn(s) Sent(changed: changed and s.wrote, durable: true) end))
end

fn refused(fs: Fs, desk: Desk, problem: StoreError, by: Deadline) : Flushed
  torn = desk.torn or problem == Torn
  var mended = desk.table
  var still = torn
  if torn and rewritten_from(fs, desk.table, desk.durable, by) is Ok(whole)
    mended = whole
    still = false
  end
  var back = desk
  back.staged = desk.staged.map(fn(s)
    unavailable(s, "the ledger could not write the change")
  end)
  Flushed(desk: answered_all(back, desk.durable, mended, still), fresh: [], ok: false,
    sent: desk.staged.map(fn(_) Sent(changed: false, durable: false) end))
end

fn unavailable(waiting: Staged, reason: String) : Staged
  var next = waiting
  next.answer = Answer(status: 503, body: "{\"error\": #{Json.encode(reason)}}")
  next.wrote = false
  next
end

# The desk once the batch is settled: every staged answer ready to collect, the batch empty, and
# the book as the log now holds it.
fn answered_all(desk: Desk, held: Book, table: Table, torn: Bool) : Desk
  var next = desk
  next.book = held
  next.durable = held
  next.table = table
  next.torn = torn
  next.records = []
  next.staged = []
  next.fresh = []
  next.answers = desk.staged.reduce(desk.answers, fn(so_far, s) so_far.set(s.ticket, s.answer) end)
  next
end

# The answer for a ticket, taken off the desk; 503 for a ticket the desk does not hold.
fn collected(desk: Desk, ticket: UInt64) : (Desk, Answer)
  case desk.answers.get(ticket)
    Some(answer):
      var next = desk
      next.answers = desk.answers.remove(ticket)
      (next, answer)
    None:
      (desk, Answer(status: 503,
        body: "{\"error\": \"the ledger has no answer for that request\"}"))
  end
end

# A call a journal that is not open takes: answered 503 at once, with why.
fn closed(desk: Desk, why: String) : Took
  ticket = desk.next
  var next = desk
  next.next = desk.next + 1
  next.answers = desk.answers.set(ticket,
    Answer(status: 503, body: "{\"error\": #{Json.encode(why)}}"))
  Took(desk: next, ticket: ticket)
end

fn waiting?(desk: Desk, ticket: UInt64) : Bool
  desk.staged.any?(fn(s) s.ticket == ticket end)
end

# When an Expire for a hold is due: when it expires, or a second from now for one already past,
# so a release the log did not take is tried again.
fn delay_to(expires_at: Time, now: Time) : Duration
  return 1_000.ms if !(now < expires_at)
  expires_at - now
end

fn t0() : Time
  Time.from_parts(2_026, 9, 14, 10, 0, 0)
end

fn call(command: Command, key: String) : Call
  Call(command: command, key: key, request: key)
end

fn opening(fs: Fs, by: Deadline) : Desk
  place = Place(dir: "d", log: "ledger.log")
  case opened_book(fs, place, by)
    Ok(open): desk(open)
    Error(_): unopened(place)
  end
end

test "calls staged together are answered from one append, in order, once it is on disk"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  first = staged(opening(fs, by),
    call(OpenAccount(name: "ada", currency: "USD", overdraft: 500), "o"), t0(), t0())
  second = staged(first.desk, call(ShowAccount(id: "a_1"), ""), t0(), t0())
  assert collected(second.desk, first.ticket).1.status == 503
  done = flushed(fs, second.desk, by)
  assert done.ok and done.sent == [Sent(changed: true, durable: true),
    Sent(changed: false, durable: true)]
  assert fs.read("d/ledger.log", within: 1.minute) is Ok(text)
  assert text.starts_with?("BEGIN 2\nSET a_1 ") and text.contains?("\nSET i_6f ")
  opened_answer = collected(done.desk, first.ticket)
  assert opened_answer.1.status == 201 and collected(opened_answer.0, first.ticket).1.status == 503
  assert collected(done.desk, second.ticket).1.body.contains?("\"overdraft\": 500")
end

test "a batch the log does not take is answered 503 and the book goes back to what the log holds"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  one = staged(opening(fs, by),
    call(OpenAccount(name: "ada", currency: "USD", overdraft: 500), "o"), t0(), t0())
  kept = flushed(fs, one.desk, by)
  two = staged(kept.desk, call(MoveMoney(from: "a_1", to: "a_1", amount: 5), "t"), t0(), t0())
  three = staged(two.desk, call(OpenAccount(name: "grace", currency: "USD", overdraft: 0), "g"),
    t0(), t0())
  refused_batch = flushed(Fs.fixture(delay: 1.minute), three.desk, Deadline.fixture(10_000.ms))
  assert !refused_batch.ok and refused_batch.desk.book == kept.desk.book
  assert collected(refused_batch.desk, three.ticket).1.status == 503
  assert refused_batch.sent.all?(fn(s) !s.changed end) and refused_batch.desk.torn
  again = staged(refused_batch.desk,
    call(OpenAccount(name: "grace", currency: "USD", overdraft: 0), "g"), t0(), t0())
  mended = flushed(fs, again.desk, by)
  assert mended.ok and !mended.desk.torn
  assert opened_book(fs, Place(dir: "d", log: "ledger.log"), by) is Ok(replayed)
  assert replayed.book.accounts.size == 2 and !replayed.torn
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run
