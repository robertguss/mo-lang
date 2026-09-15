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

  made = Account(number: book.next_account, name: name, currency: currency, overdraft: overdraft,
    created_at: now)
  Opening(book: with_account(book, made), account: made)
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

  source = try found(book, from)
  target = try found(book, to)
  return Error(refused(422, "same_account", "a transfer names #{from} twice", 0)) if from == to
  if source.currency != target.currency
    return Error(refused(422, "currency",
      "#{from} holds #{source.currency} and #{to} holds #{target.currency}", 0))
  end
  try covering(book, source, amount)
  var entry = blank(book.next_entry, Transfer, key, now)
  entry.postings = [Posting(account: from, amount: 0 - amount),
    Posting(account: to, amount: amount)]
  entry.amount = amount
  moved(applied(book, entry), entry, from)
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

  holder = try found(book, account)
  try covering(book, holder, amount)
  var entry = blank(book.next_entry, Hold, key, now)
  entry.account = account
  entry.amount = amount
  entry.expires_at = Some(now + ttl_ms.ms)
  moved(applied(book, entry), entry, account)
end

# Turns a live hold into a transfer of the amount to the currency's clearing account, closing
# the hold whether all of it or part was captured.
fn captured(book: Book, hold: UInt64, amount: Money, key: String, now: Time) : Result(Moved,
  Refusal)
  requires amount?(amount)
  requires key?(key)
  ensures result is Ok(m) implies closer(m.book, hold) == Some(m.entry.number)
  ensures result is Ok(m) implies m.entry.postings.map(fn(p) p.amount end) == [0 - amount, amount]

  live = try live_hold(book, hold, now)
  if amount > live.amount
    return Error(refused(422, "over_hold", "#{entry_id(hold)} holds #{live.amount}",
      amount - live.amount))
  end
  holder = try found(book, live.account)
  var entry = blank(book.next_entry, Capture, key, now)
  entry.account = live.account
  entry.amount = amount
  entry.hold = Some(hold)
  entry.postings = [Posting(account: live.account, amount: 0 - amount),
    Posting(account: clearing_of(holder.currency), amount: amount)]
  closing = Closing(hold: hold, held: live.amount, captured: amount, closed_before: false)
  Ok(closed(moved_ok(applied(book, entry), entry, live.account), closing))
end

# Cancels a live hold: nothing moves, and what it held is available again.
fn released(book: Book, hold: UInt64, reason: String, key: String, now: Time) : Result(Moved,
  Refusal)
  requires reason?(reason)
  requires key?(key)
  ensures result is Ok(m) implies closer(m.book, hold) == Some(m.entry.number)

  live = try live_hold(book, hold, now)
  Ok(release(book, live, reason, key, now))
end

# The release a hold's expiry writes: no key, and the reason expired.
fn expired(book: Book, live: Hold, now: Time) : Moved
  requires live.expires_at <= now
  requires book.holds.get(live.number) == Some(live)
  ensures closer(result.book, live.number) == Some(result.entry.number)

  release(book, live, "expired", "", now)
end

fn moved_nothing(book: Book, live: Hold, now: Time) : Moved
  Moved(book: book, entry: blank(0, Release, "", now), standing: None, closing: None, refund: None)
end

fn release(book: Book, live: Hold, reason: String, key: String, now: Time) : Moved
  var entry = blank(book.next_entry, Release, key, now)
  entry.account = live.account
  entry.amount = live.amount
  entry.hold = Some(live.number)
  entry.reason = Some(reason)
  closing = Closing(hold: live.number, held: live.amount, captured: 0, closed_before: false)
  closed(moved_ok(applied(book, entry), entry, live.account), closing)
end

# Moves up to what remains of a capture back from the clearing account to the account it came
# from.
fn refunded(book: Book, capture: UInt64, amount: Money, key: String, now: Time) : Result(Moved,
  Refusal)
  requires amount?(amount)
  requires key?(key)
  ensures result is Ok(m) implies balance(m.book, m.entry.account) == balance(book,
    m.entry.account) + amount

  made = try capture_found(book, capture)
  remaining = made.amount - made.refunded
  if amount > remaining
    return Error(refused(422, "over_capture",
      "#{entry_id(capture)} has #{remaining} left to refund", amount - remaining))
  end
  var entry = blank(book.next_entry, Refund, key, now)
  entry.account = made.account
  entry.amount = amount
  entry.capture = Some(capture)
  entry.postings = [Posting(account: made.clearing, amount: 0 - amount),
    Posting(account: made.account, amount: amount)]
  record = Refunded(capture: capture, captured: made.amount, refunded: made.refunded + amount)
  var done = moved_ok(applied(book, entry), entry, made.account)
  done.refund = Some(record)
  Ok(done)
end

fn found(book: Book, id: String) : Result(Account, Refusal)
  case account_of_id(book, id)
    Some(account): Ok(account)
    None: Error(refused(404, "no_account", "no account #{id}", 0))
  end
end

# Nothing when the account's available balance less the amount stays at or above minus its
# overdraft; otherwise insufficient, by the shortfall.
fn covering(book: Book, account: Account, amount: Money) : Result(Bool, Refusal)
  id = account_id(account.number)
  room = available(book, id) + account.overdraft - amount
  return Ok(true) if room >= 0
  Error(refused(422, "insufficient",
    "#{id} has #{available(book, id)} available and an overdraft of #{account.overdraft}",
    0 - room))
end

# The hold, while it is live and has not expired; 404 for no hold, 409 once it was captured,
# released, or expired.
fn live_hold(book: Book, number: UInt64, now: Time) : Result(Hold, Refusal)
  no_hold = refused(404, "no_hold", "no hold #{entry_id(number)}", 0)
  return Error(no_hold) if !(entry_at(book, number) is Some(e) and e.kind == Hold)
  if closer(book, number) is Some(by)
    return Error(refused(409, "closed", "#{entry_id(number)} was #{closed_how(book, by)}", 0))
  end
  case book.holds.get(number)
    Some(live):
      return Error(refused(409, "closed", "#{entry_id(number)} expired",
        0)) if live.expires_at <= now
      Ok(live)
    None: Error(refused(409, "closed", "#{entry_id(number)} is not live", 0))
  end
end

fn capture_found(book: Book, capture: UInt64) : Result(Captured, Refusal)
  case capture_at(book, capture)
    Some(c): Ok(c)
    None: Error(refused(404, "no_capture", "no capture #{entry_id(capture)}", 0))
  end
end

fn closed_how(book: Book, by: UInt64) : String
  case entry_at(book, by)
    Some(e):
      return "captured by #{entry_id(by)}" if e.kind == Capture
      return "expired" if e.reason == Some("expired")
      "released by #{entry_id(by)}"
    None: "closed"
  end
end

fn refused(status: UInt16, rule: String, error: String, by: Int64) : Refusal
  Refusal(status: status, rule: rule, error: error, by: by)
end

# A refusal as the API's body: what it says, the rule, and by how much.
fn refusal_body(refusal: Refusal) : String
  "{\"error\": #{Json.encode(refusal.error)}, \"rule\": \"#{refusal.rule}\", \"by\": #{refusal.by}}"
end

fn moved(book: Book, entry: Entry, drawn: String) : Result(Moved, Refusal)
  Ok(moved_ok(book, entry, drawn))
end

fn moved_ok(book: Book, entry: Entry, drawn: String) : Moved
  standing = account_of_id(book, drawn).map(fn(a)
    Standing(account: drawn, balance: balance(book, drawn), held: held_on(book, drawn),
      overdraft: a.overdraft)
  end)
  Moved(book: book, entry: entry, standing: standing, closing: None, refund: None)
end

fn closed(done: Moved, closing: Closing) : Moved
  var after = done
  after.closing = Some(closing)
  after
end

# Whether every balance but the two named is as it was, and no account appeared or went.
fn only_moved?(before: Book, after: Book, a: String, b: String) : Bool
  same = before.balances.entries.all?(fn(e)
    e.0 == a or e.0 == b or after.balances.get(e.0) == Some(e.1)
  end)
  same and before.balances.size == after.balances.size
end

fn t0() : Time
  Time.from_parts(2026, 9, 14, 9, 0, 0)
end

# Ada may go 10,000 below zero; grace may not; eur holds euros.
fn three() : Book
  first = opened(book(), "ada", "USD", 10_000, t0())
  second = opened(first.book, "grace", "USD", 0, t0())
  opened(second.book, "eur", "EUR", 0, t0()).book
end

fn paid(book: Book, from: String, to: String, amount: Money) : Book
  case transferred(book, from, to, amount, "k", t0())
    Ok(done): done.book
    Error(_): book
  end
end

fn hold_of(book: Book, account: String, amount: Money) : Moved
  case held(book, account, amount, 60_000, "h", t0())
    Ok(done): done
    Error(_):
      moved_nothing(book, Hold(number: 0, account: account, amount: amount, expires_at: t0()), t0())
  end
end

fn refusal_of(outcome: Result(Moved, Refusal)) : Refusal
  case outcome
    Ok(_): refused(0, "", "", 0)
    Error(why): why
  end
end

# The planted bug: a transfer written as two records, each half an entry of its own. The
# balances come out as a transfer's would.
fn split_transfer(book: Book, from: String, to: String, amount: Money, now: Time) : Book
  var debit = blank(book.next_entry, Transfer, "k", now)
  debit.postings = [Posting(account: from, amount: 0 - amount)]
  var credit = blank(book.next_entry + 1, Transfer, "k", now)
  credit.postings = [Posting(account: to, amount: amount)]
  applied(applied(book, debit), credit)
end

# The next pseudo-random number of a sequence, for a property that walks many transfers.
fn stirred(n: UInt64) : UInt64
  (n * 1_103_515_245 + 12_345) % 2_147_483_648
end

fn walked(book: Book, seed: UInt64) : Book
  ids = ["a_1", "a_2", "a_3"]
  var at = book
  var n = seed % 2_147_483_648
  for _ in 0..40
    n = stirred(n)
    from = ids.get(n % 3) or "a_1"
    to = ids.get((n / 3) % 3) or "a_2"
    amount = ((n / 9) % 20_000 + 1).to_i64
    if transferred(at, from, to, amount, "k#{n}", t0()) is Ok(done)
      at = done.book
    end
  end
  at
end

# Every balance summed again from the postings of every entry the book holds.
fn summed(book: Book) : Map(String, Int64)
  entries = book.entries.values.flat_map(fn(page) page.values end)
  postings = entries.flat_map(fn(e) e.postings end)
  postings.reduce(Map.new(),
    fn(sums, p) sums.set(p.account, (sums.get(p.account) or 0) + p.amount) end)
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

verified: types, contracts, tests (15), property (200 seeds), sim (not run)
          proven: not run
