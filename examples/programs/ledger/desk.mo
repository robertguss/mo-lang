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
  # body gone; regenerate
end

# The desk a journal holds before it opens: an empty book over the place's log.
fn unopened(place: Place) : Desk
  # body gone; regenerate
end

# The call decided against the book with the batch in it; its answer waits for the flush.
fn staged(desk: Desk, call: Call, now: Time, started: Time) : Took
  # body gone; regenerate
end

# A decision's book, records, and holds joined to the batch with no call waiting on it: the
# releases an Expire or an opening stages.
fn with_decision(desk: Desk, done: Decision) : Desk
  # body gone; regenerate
end

# The batch written: appended in one write, or, when the log may end in part of a batch, the log
# written whole from the book, which holds the batch too. A batch the log did not take answers
# every call in it 503 and puts the book back as the log holds it; when that write may have left
# part of the batch, the log is written whole from that book at once, so the 503 changed nothing.
fn flushed(fs: Fs, desk: Desk, by: Deadline) : Flushed
  ensures result.sent.size == desk.staged.size
  # body gone; regenerate
end

fn refused(fs: Fs, desk: Desk, problem: StoreError, by: Deadline) : Flushed
  # body gone; regenerate
end

fn unavailable(waiting: Staged, reason: String) : Staged
  # body gone; regenerate
end

# The desk once the batch is settled: every staged answer ready to collect, the batch empty, and
# the book as the log now holds it.
fn answered_all(desk: Desk, held: Book, table: Table, torn: Bool) : Desk
  # body gone; regenerate
end

# The answer for a ticket, taken off the desk; 503 for a ticket the desk does not hold.
fn collected(desk: Desk, ticket: UInt64) : (Desk, Answer)
  # body gone; regenerate
end

# A call a journal that is not open takes: answered 503 at once, with why.
fn closed(desk: Desk, why: String) : Took
  # body gone; regenerate
end

fn waiting?(desk: Desk, ticket: UInt64) : Bool
  # body gone; regenerate
end

# When an Expire for a hold is due: when it expires, or a second from now for one already past,
# so a release the log did not take is tried again.
fn delay_to(expires_at: Time, now: Time) : Duration
  # body gone; regenerate
end

fn t0() : Time
  # body gone; regenerate
end

fn call(command: Command, key: String) : Call
  # body gone; regenerate
end

fn opening(fs: Fs, by: Deadline) : Desk
  # body gone; regenerate
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
