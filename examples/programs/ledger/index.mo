module Ledger.Index
expose Hold, Captured, Keyed, Book, book, account_of_id, balance, held_on, available, entry_at, closer, capture_at, keyed, applied, with_account, with_keyed, listed, due_holds, due_on, held_total, balanced?, covered?, timed?, keyed?

use Ledger.Entry{Kind, Posting, Account, Entry, blank, account_id, entry_id, number_in, clearing?, posted, kind_name}
use Ledger.Money{Money}

intent "The book a journal answers from: the accounts, and every entry by number, folded into the balances, the live holds, the captures and what was refunded of each, the first hundred entries per account and kind, the settled days, and the idempotency table; nothing here decides whether an entry is allowed, it only folds one in, and the four checks the journal's invariants run read the fold."

# A hold still live: its entry, the account, the amount held, and when it expires.
struct Hold
  number: UInt64
  account: String
  amount: Money
  expires_at: Time
end

# A capture: the account it debited, the clearing account it credited, how much, and how much of
# it was refunded so far.
struct Captured
  number: UInt64
  account: String
  clearing: String
  amount: Money
  refunded: Money
end

# How a key was answered: the request it came with, the status, the body when it was a refusal
# ("" when the answer is shown again from what it made), and what it made ("e_5", "a_3", or "").
struct Keyed
  request: String
  status: UInt16
  body: String
  made: String
end

# The fold. Maps that grow with the traffic are pages of 256 (entries, closed holds, captures) or
# 1,024 pages by the key's bytes (keys), so a change copies one page. `posted` is the sum of every
# entry's postings, `unbalanced` the entries whose postings do not sum to zero, `keyed_entries`
# the entries a client's key made, `naming` the key rows that name an entry, and `dangling` the
# rows that name something the book does not hold.
struct Book
  accounts: Map(String, Account)
  balances: Map(String, Int64)
  held: Map(String, Int64)
  holds: Map(UInt64, Hold)
  closed: Map(UInt64, Map(UInt64, UInt64))
  captures: Map(UInt64, Map(UInt64, Captured))
  entries: Map(UInt64, Map(UInt64, Entry))
  lists: Map(String, List(UInt64))
  keys: Map(UInt64, Map(String, Keyed))
  settled: Map(String, UInt64)
  next_account: UInt64
  next_entry: UInt64
  entry_count: UInt64
  posted: Int64
  unbalanced: UInt64
  keyed_entries: UInt64
  naming: UInt64
  dangling: UInt64
end

fn book() : Book
  # body gone; regenerate
end

fn account_of_id(book: Book, id: String) : Option(Account)
  # body gone; regenerate
end

fn balance(book: Book, id: String) : Int64
  # body gone; regenerate
end

fn held_on(book: Book, id: String) : Int64
  # body gone; regenerate
end

# The balance less what live holds keep.
fn available(book: Book, id: String) : Int64
  # body gone; regenerate
end

fn entry_at(book: Book, number: UInt64) : Option(Entry)
  # body gone; regenerate
end

# The entry that captured or released a hold, None while it is live or when it is no hold.
fn closer(book: Book, hold: UInt64) : Option(UInt64)
  # body gone; regenerate
end

fn capture_at(book: Book, number: UInt64) : Option(Captured)
  # body gone; regenerate
end

fn keyed(book: Book, key: String) : Option(Keyed)
  # body gone; regenerate
end

fn bucket_of(key: String) : UInt64
  ensures result < 1_024
  # body gone; regenerate
end

# The book with one more entry folded in: its postings into the balances, a hold opened or closed,
# a capture recorded or refunded, a day settled, and its number listed under its accounts.
fn applied(book: Book, entry: Entry) : Book
  ensures result.entry_count == book.entry_count + 1
  # body gone; regenerate
end

fn with_posting(sums: Map(String, Int64), p: Posting) : Map(String, Int64)
  # body gone; regenerate
end

fn opened_hold(book: Book, entry: Entry) : Book
  # body gone; regenerate
end

# A capture or a release closes its hold: what it held is no longer held, and the hold is closed
# by this entry.
fn closed_hold(book: Book, entry: Entry) : Book
  # body gone; regenerate
end

fn captured_hold(book: Book, entry: Entry) : Book
  # body gone; regenerate
end

fn refunded_capture(book: Book, entry: Entry) : Book
  # body gone; regenerate
end

fn settled_day(book: Book, entry: Entry) : Book
  # body gone; regenerate
end

# The entry's number under each account it concerns, and under its kind, while the list is under
# a hundred: a listing is the first hundred by id.
fn listed_under(lists: Map(String, List(UInt64)), entry: Entry) : Map(String, List(UInt64))
  # body gone; regenerate
end

fn pushed(lists: Map(String, List(UInt64)), name: String, number: UInt64) : Map(String,
  # body gone; regenerate
end

# The first hundred entries by id, of an account or of all, of a kind or of all.
fn listed(book: Book, account: Option(String), kind: Option(Kind)) : List(Entry)
  ensures result.size <= 100
  # body gone; regenerate
end

fn found(book: Book, number: UInt64) : List(Entry)
  # body gone; regenerate
end

fn with_account(book: Book, account: Account) : Book
  # body gone; regenerate
end

# The book with the key's row, counted by what it names.
fn with_keyed(book: Book, key: String, row: Keyed) : Book
  # body gone; regenerate
end

fn uncounted(book: Book, row: Option(Keyed)) : Book
  # body gone; regenerate
end

fn names_nothing?(book: Book, made: String) : Bool
  # body gone; regenerate
end

# Every live hold whose expiry has come, oldest first.
fn due_holds(book: Book, now: Time) : List(Hold)
  # body gone; regenerate
end

# The account's live holds whose expiry has come, oldest first.
fn due_on(book: Book, account: String, now: Time) : List(Hold)
  # body gone; regenerate
end

fn held_total(book: Book) : Int64
  # body gone; regenerate
end

# The sum of every positive balance equals the overdraft drawn by every negative one, every
# balance together equals the sum of the journal's postings, and no entry's postings are
# unbalanced.
fn balanced?(book: Book) : Bool
  # body gone; regenerate
end

# What the live holds keep, summed from the holds themselves, is at most what the accounts have
# before the holds: every balance plus its overdraft.
fn covered?(book: Book) : Bool
  # body gone; regenerate
end

# Every live hold expires later than now, or an Expire for it is on its way.
fn timed?(book: Book, pending: Set(UInt64), now: Time) : Bool
  # body gone; regenerate
end

# Every key row names something the book holds, and every entry a client's key made has its row.
fn keyed?(book: Book) : Bool
  # body gone; regenerate
end

fn t0() : Time
  # body gone; regenerate
end

fn ada() : Account
  # body gone; regenerate
end

fn grace() : Account
  # body gone; regenerate
end

fn moved(number: UInt64, kind: Kind, postings: List(Posting), key: String) : Entry
  # body gone; regenerate
end

fn opened() : Book
  # body gone; regenerate
end

test "a transfer moves two balances, lists its number, and keeps the book balanced"
  paid = moved(1, Transfer,
    [Posting(account: "a_1", amount: -700), Posting(account: "a_2", amount: 700)], "k")
  after = applied(opened(), paid)
  assert balance(after, "a_1") == -700 and balance(after, "a_2") == 700
  assert entry_at(after, 1) == Some(paid) and after.next_entry == 2
  assert listed(after, Some("a_1"), None) == [paid] and listed(after, None,
    Some(Transfer)) == [paid]
  assert listed(after, Some("a_2"), Some(Hold)) == []
  assert balanced?(after) and covered?(after) and after.keyed_entries == 1
end

test "a hold keeps part of the balance until a capture or a release closes it"
  at = Time.fixture()
  var hold = moved(1, Hold, [], "h")
  hold.account = "a_1"
  hold.amount = 5_000
  hold.expires_at = Some(at + 1.minute)
  held = applied(opened(), hold)
  assert available(held, "a_1") == -5_000 and held_total(held) == 5_000
  assert due_holds(held, at) == [] and due_on(held, "a_1", at + 1.minute).size == 1
  assert timed?(held, Set.new(), at) and !timed?(held, Set.new(), at + 1.minute)
  assert timed?(held, Set.new().add(1), at + 1.minute)
  capture = moved(2, Capture,
    [Posting(account: "a_1", amount: -4_200), Posting(account: "clearing:USD", amount: 4_200)], "c")
  var closing = capture
  closing.hold = Some(1)
  closing.account = "a_1"
  captured = applied(held, closing)
  assert available(captured, "a_1") == -4_200 and closer(captured, 1) == Some(2)
  assert capture_at(captured, 2) is Some(made)
  assert made.clearing == "clearing:USD" and made.refunded == 0
  assert listed(captured, Some("a_1"), None).size == 2 and balanced?(captured)
end

test "a book that is not balanced, not covered, or not keyed says so"
  half = moved(1, Transfer, [Posting(account: "a_1", amount: -700)], "k")
  assert !balanced?(applied(opened(), half))
  var greedy = moved(1, Hold, [], "h")
  greedy.account = "a_2"
  greedy.amount = 10_001
  assert !covered?(applied(opened(), greedy))
  row = Keyed(request: "POST /transfers\n{}", status: 201, body: "", made: "e_9")
  assert !keyed?(with_keyed(opened(), "k", row))
  paid = moved(1, Transfer,
    [Posting(account: "a_1", amount: -1), Posting(account: "a_2", amount: 1)], "k")
  twice = applied(applied(opened(), paid), moved(2, Transfer, paid.postings, "k"))
  var named = row
  named.made = "e_1"
  assert !keyed?(with_keyed(twice, "k", named))
  assert keyed?(with_keyed(applied(opened(), paid), "k", named))
end

test "a key row replaced is counted once, and a listing stops at a hundred"
  row = Keyed(request: "r", status: 422, body: "{}", made: "")
  var made = row
  made.made = "a_1"
  keys = with_keyed(with_keyed(opened(), "k", row), "k", made)
  assert keyed(keys, "k") == Some(made) and keys.dangling == 0 and keyed?(keys)
  entries = (1..151).map(fn(n)
    moved(n, Transfer, [Posting(account: "a_1", amount: -1), Posting(account: "a_2", amount: 1)],
      "")
  end)
  many = entries.reduce(opened(), fn(b, e) applied(b, e) end)
  assert listed(many, Some("a_2"), None).size == 100 and listed(many, None,
    None).last == entries.get(99)
  assert balance(many, "a_2") == 150 and keyed?(many)
end
