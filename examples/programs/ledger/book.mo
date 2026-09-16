module Ledger.Book
expose Refusal, Moved, Opening, Standing, Closing, Refunded, opened, transferred, held, captured, released, expired, refunded, only_moved?, refusal_body

use Ledger.Entry{Kind, Posting, Account, Entry, blank, account_id, entry_id, clearing_of, posted}
use Ledger.Index{Hold, Captured, Book, book, account_of_id, balance, held_on, available, entry_at, closer, capture_at, applied, with_account, balanced?}
use Ledger.Money{Money, amount?, overdraft?, currency?, name?, reason?, key?, ttl_ms?, card_run?}

intent "The rules: what opening an account, a transfer, a hold, a capture, a release, an expiry, and a refund each do to a book, as a new entry folded in, or the refusal and why; each rule decides against the book it is handed and nothing else, and the nevers hold every decision to what a ledger must never do."

never "money is created or destroyed: an entry's postings do not sum to zero"
  for e in Entry.all
    posted(e) != 0
  end
end

never "a refund exceeds its charge: the refunds of a capture sum past the captured amount"
  for r in Refunded.all
    r.refunded > r.captured
  end
end

never "a capture exceeds its hold, or a hold is captured or released twice"
  for c in Closing.all
    c.captured > c.held or c.closed_before
  end
end

never "an account goes below minus its overdraft, counting live holds against it"
  for s in Standing.all
    s.balance - s.held < 0 - s.overdraft
  end
end

never "a card number reaches an entry"
  for e in Entry.all
    card_run?(e.key) or card_run?(e.reason or "")
  end
end

# Why a rule refused: the status, the rule by name, what it says, and by how much it missed.
struct Refusal
  status: UInt16
  rule: String
  error: String
  by: Int64
end

# A rule's entry folded into the book, beside what the nevers are held to: the standing of the
# account it drew on, the hold it closed, and the capture it refunded.
struct Moved
  book: Book
  entry: Entry
  standing: Option(Standing)
  closing: Option(Closing)
  refund: Option(Refunded)
end

struct Opening
  book: Book
  account: Account
end

# An account after a change, as the overdraft never reads it.
struct Standing
  account: String
  balance: Int64
  held: Int64
  overdraft: Int64
end

# A hold as a capture or a release closed it: what it held, what was captured of it, and whether
# something had closed it before.
struct Closing
  hold: UInt64
  held: Int64
  captured: Int64
  closed_before: Bool
end

# A capture as a refund left it: what was captured and what is refunded in all.
struct Refunded
  capture: UInt64
  captured: Int64
  refunded: Int64
end

fn opened(book: Book, name: String, currency: String, overdraft: Money, now: Time) : Opening
  requires name?(name)
  requires currency?(currency)
  requires overdraft?(overdraft)
  ensures balance(result.book, account_id(result.account.number)) == 0
  # body gone; regenerate
end

# Moves the amount from one account to another of the same currency, when what the first has
# available, with its overdraft, covers it.
fn transferred(book: Book, from: String, to: String, amount: Money, key: String,
  now: Time) : Result(Moved, Refusal)
  requires amount?(amount)
  requires key?(key)
  ensures result is Ok(m) implies balance(m.book, from) == balance(book, from) - amount
  ensures result is Ok(m) implies balance(m.book, to) == balance(book, to) + amount
  ensures result is Ok(m) implies only_moved?(book, m.book, from, to)
  # body gone; regenerate
end

# Keeps the amount of the account's balance for ttl_ms, when its available balance, with its
# overdraft, covers it; no money moves.
fn held(book: Book, account: String, amount: Money, ttl_ms: Int64, key: String,
  now: Time) : Result(Moved, Refusal)
  requires amount?(amount)
  requires ttl_ms?(ttl_ms)
  requires key?(key)
  ensures result is Ok(m) implies available(m.book, account) == available(book, account) - amount
  ensures result is Ok(m) implies only_moved?(book, m.book, account, account)
  # body gone; regenerate
end

# Turns a live hold into a transfer of the amount to the currency's clearing account, closing
# the hold whether all of it or part was captured.
fn captured(book: Book, hold: UInt64, amount: Money, key: String, now: Time) : Result(Moved,
  # body gone; regenerate
end

# Cancels a live hold: nothing moves, and what it held is available again.
fn released(book: Book, hold: UInt64, reason: String, key: String, now: Time) : Result(Moved,
  # body gone; regenerate
end

# The release a hold's expiry writes: no key, and the reason expired.
fn expired(book: Book, live: Hold, now: Time) : Moved
  requires live.expires_at <= now
  requires book.holds.get(live.number) == Some(live)
  ensures closer(result.book, live.number) == Some(result.entry.number)
  # body gone; regenerate
end

fn moved_nothing(book: Book, live: Hold, now: Time) : Moved
  # body gone; regenerate
end

fn release(book: Book, live: Hold, reason: String, key: String, now: Time) : Moved
  # body gone; regenerate
end

# Moves up to what remains of a capture back from the clearing account to the account it came
# from.
fn refunded(book: Book, capture: UInt64, amount: Money, key: String, now: Time) : Result(Moved,
  # body gone; regenerate
end

fn found(book: Book, id: String) : Result(Account, Refusal)
  # body gone; regenerate
end

# Nothing when the account's available balance less the amount stays at or above minus its
# overdraft; otherwise insufficient, by the shortfall.
fn covering(book: Book, account: Account, amount: Money) : Result(Bool, Refusal)
  # body gone; regenerate
end

# The hold, while it is live and has not expired; 404 for no hold, 409 once it was captured,
# released, or expired.
fn live_hold(book: Book, number: UInt64, now: Time) : Result(Hold, Refusal)
  # body gone; regenerate
end

fn capture_found(book: Book, capture: UInt64) : Result(Captured, Refusal)
  # body gone; regenerate
end

fn closed_how(book: Book, by: UInt64) : String
  # body gone; regenerate
end

fn refused(status: UInt16, rule: String, error: String, by: Int64) : Refusal
  # body gone; regenerate
end

# A refusal as the API's body: what it says, the rule, and by how much.
fn refusal_body(refusal: Refusal) : String
  # body gone; regenerate
end

fn moved(book: Book, entry: Entry, drawn: String) : Result(Moved, Refusal)
  # body gone; regenerate
end

fn moved_ok(book: Book, entry: Entry, drawn: String) : Moved
  # body gone; regenerate
end

fn closed(done: Moved, closing: Closing) : Moved
  # body gone; regenerate
end

# Whether every balance but the two named is as it was, and no account appeared or went.
fn only_moved?(before: Book, after: Book, a: String, b: String) : Bool
  # body gone; regenerate
end

fn t0() : Time
  # body gone; regenerate
end

# Ada may go 10,000 below zero; grace may not; eur holds euros.
fn three() : Book
  # body gone; regenerate
end

fn paid(book: Book, from: String, to: String, amount: Money) : Book
  # body gone; regenerate
end

fn hold_of(book: Book, account: String, amount: Money) : Moved
  # body gone; regenerate
end

fn refusal_of(outcome: Result(Moved, Refusal)) : Refusal
  # body gone; regenerate
end

# The planted bug: a transfer written as two records, each half an entry of its own. The
# balances come out as a transfer's would.
fn split_transfer(book: Book, from: String, to: String, amount: Money, now: Time) : Book
  # body gone; regenerate
end

# The next pseudo-random number of a sequence, for a property that walks many transfers.
fn stirred(n: UInt64) : UInt64
  # body gone; regenerate
end

fn walked(book: Book, seed: UInt64) : Book
  # body gone; regenerate
end

# Every balance summed again from the postings of every entry the book holds.
fn summed(book: Book) : Map(String, Int64)
  # body gone; regenerate
end

test "a transfer moves the amount between two accounts and nothing else"
  moved_book = paid(three(), "a_1", "a_2", 1_500)
  assert balance(moved_book, "a_1") == -1_500 and balance(moved_book, "a_2") == 1_500
  assert balance(moved_book, "a_3") == 0 and moved_book.entry_count == 1
  back = transferred(moved_book, "a_2", "a_1", 1_500, "k2", t0())
  assert back is Ok(done)
  assert done.entry.postings == [Posting(account: "a_2", amount: -1_500),
    Posting(account: "a_1", amount: 1_500)]
  assert done.standing == Some(Standing(account: "a_2", balance: 0, held: 0, overdraft: 0))
end

test "a transfer is refused for an account that is not there, the same account, another currency, or too little"
  books = three()
  assert refusal_of(transferred(books, "a_9", "a_2", 1, "k", t0())).status == 404
  assert refusal_of(transferred(books, "a_1", "a_1", 1, "k", t0())).rule == "same_account"
  assert refusal_of(transferred(books, "a_1", "a_3", 1, "k", t0())).rule == "currency"
  short = refusal_of(transferred(books, "a_1", "a_2", 10_500, "k", t0()))
  assert short.status == 422 and short.rule == "insufficient" and short.by == 500
  assert refusal_of(transferred(books, "a_2", "a_1", 1, "k", t0())).by == 1
  assert refusal_body(short) == "{\"error\": \"a_1 has 0 available and an overdraft of 10000\", \"rule\": \"insufficient\", \"by\": 500}"
end

test "a hold keeps funds without moving them, and a transfer cannot spend what it keeps"
  books = paid(three(), "a_1", "a_2", 5_000)
  hold = hold_of(books, "a_2", 4_000)
  assert available(hold.book, "a_2") == 1_000 and balance(hold.book, "a_2") == 5_000
  assert hold.entry.expires_at == Some(t0() + 60_000.ms)
  assert refusal_of(transferred(hold.book, "a_2", "a_1", 1_001, "k", t0())).by == 1
  assert refusal_of(held(hold.book, "a_2", 1_001, 100, "k", t0())).rule == "insufficient"
end

test "a capture closes its hold and credits the clearing account; a second capture or a release is 409"
  books = paid(three(), "a_1", "a_2", 5_000)
  hold = hold_of(books, "a_2", 5_000)
  number = hold.entry.number
  assert refusal_of(captured(hold.book, number, 5_001, "c", t0())).by == 1
  assert captured(hold.book, number, 4_200, "c", t0()) is Ok(done)
  assert balance(done.book, "a_2") == 800 and available(done.book, "a_2") == 800
  assert balance(done.book, "clearing:USD") == 4_200 and balanced?(done.book)
  assert done.closing == Some(Closing(hold: number, held: 5_000, captured: 4_200,
    closed_before: false))
  again = refusal_of(captured(done.book, number, 1, "c2", t0()))
  assert again.status == 409 and again.error == "e_2 was captured by e_3"
  assert refusal_of(released(done.book, number, "no", "r", t0())).status == 409
  assert refusal_of(captured(done.book, 1, 1, "c", t0())).status == 404
  assert refusal_of(captured(done.book, 99, 1, "c", t0())).status == 404
end

test "a release frees a hold, an expired hold is 409 to capture, and its expiry releases it"
  books = paid(three(), "a_1", "a_2", 5_000)
  hold = hold_of(books, "a_2", 5_000)
  number = hold.entry.number
  assert released(hold.book, number, "customer asked", "r", t0()) is Ok(freed)
  assert available(freed.book, "a_2") == 5_000 and freed.entry.reason == Some("customer asked")
  assert refusal_of(captured(freed.book, number, 1, "c", t0())).error == "e_2 was released by e_3"
  later = t0() + 60_000.ms
  assert refusal_of(captured(hold.book, number, 1, "c", later)).error == "e_2 expired"
  live = hold.book.holds.get(number) or Hold(number: 0, account: "", amount: 0, expires_at: later)
  gone = expired(hold.book, live, later)
  assert gone.entry.reason == Some("expired") and gone.entry.key == "" and gone.entry.amount == 5_000
  assert refusal_of(released(gone.book, number, "late", "r", later)).error == "e_2 was expired"
end

test "refunds of a capture go back to the account, up to what was captured in all"
  books = paid(three(), "a_1", "a_2", 5_000)
  hold = hold_of(books, "a_2", 5_000)
  assert captured(hold.book, hold.entry.number, 4_200, "c", t0()) is Ok(capture)
  number = capture.entry.number
  assert refunded(capture.book, number, 1_000, "r1", t0()) is Ok(first)
  assert balance(first.book, "a_2") == 1_800 and balance(first.book, "clearing:USD") == 3_200
  over = refusal_of(refunded(first.book, number, 3_201, "r2", t0()))
  assert over.status == 422 and over.rule == "over_capture" and over.by == 1
  assert refunded(first.book, number, 3_200, "r2", t0()) is Ok(rest)
  assert rest.refund == Some(Refunded(capture: number, captured: 4_200, refunded: 4_200))
  assert refusal_of(refunded(rest.book, number, 1, "r3", t0())).by == 1
  assert refusal_of(refunded(rest.book, 1, 1, "r3", t0())).status == 404
end

test rejects "an account named with a space"
  opened(book(), "a b", "USD", 0, Time.fixture())
end

test rejects "a transfer of nothing"
  transferred(three(), "a_1", "a_2", 0, "k", Time.fixture())
end

test rejects "a hold that lives 99 ms"
  held(three(), "a_1", 1, 99, "k", Time.fixture())
end

test rejects "a capture with an empty key"
  captured(three(), 1, 1, "", Time.fixture())
end

test rejects "a release whose reason holds a card number"
  released(three(), 1, "card 4111111111111111", "k", Time.fixture())
end

test rejects "an expiry of a hold that has not expired"
  hold = hold_of(three(), "a_1", 100)
  live = Hold(number: hold.entry.number, account: "a_1", amount: 100, expires_at: t0() + 60_000.ms)
  expired(hold.book, live, t0())
end

test rejects "a refund of nothing"
  refunded(three(), 1, 0, "k", Time.fixture())
end

# The planted bug: each half is a record of its own, so each entry's postings miss zero, and the
# never that money is never created or destroyed trips at the end of the test, though the
# balances read as a transfer's would.
test rejects "a transfer written as two records"
  after = split_transfer(three(), "a_1", "a_2", 700, Time.fixture())
  assert balance(after, "a_1") == -700 and balance(after, "a_2") == 700
end

property "any sequence of valid transfers keeps every entry's postings at zero and every balance at their sum"
  for seed in any(UInt64)
    walked_book = walked(three(), seed)
    assert balanced?(walked_book)
    sums = summed(walked_book)
    assert walked_book.balances.entries.all?(fn(e) (sums.get(e.0) or 0) == e.1 end)
  end
end
