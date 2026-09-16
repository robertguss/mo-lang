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
  Book(accounts: Map.new(), balances: Map.new(), held: Map.new(), holds: Map.new(),
    closed: Map.new(), captures: Map.new(), entries: Map.new(), lists: Map.new(), keys: Map.new(),
    settled: Map.new(), next_account: 1, next_entry: 1, entry_count: 0, posted: 0, unbalanced: 0,
    keyed_entries: 0, naming: 0, dangling: 0)
end

fn account_of_id(book: Book, id: String) : Option(Account)
  book.accounts.get(id)
end

fn balance(book: Book, id: String) : Int64
  book.balances.get(id) or 0
end

fn held_on(book: Book, id: String) : Int64
  book.held.get(id) or 0
end

# The balance less what live holds keep.
fn available(book: Book, id: String) : Int64
  balance(book, id) - held_on(book, id)
end

fn entry_at(book: Book, number: UInt64) : Option(Entry)
  (book.entries.get(number / 256) or Map.new()).get(number)
end

# The entry that captured or released a hold, None while it is live or when it is no hold.
fn closer(book: Book, hold: UInt64) : Option(UInt64)
  (book.closed.get(hold / 256) or Map.new()).get(hold)
end

fn capture_at(book: Book, number: UInt64) : Option(Captured)
  (book.captures.get(number / 256) or Map.new()).get(number)
end

fn keyed(book: Book, key: String) : Option(Keyed)
  (book.keys.get(bucket_of(key)) or Map.new()).get(key)
end

fn bucket_of(key: String) : UInt64
  ensures result < 1_024
  key.bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 1_024 end)
end

# The book with one more entry folded in: its postings into the balances, a hold opened or closed,
# a capture recorded or refunded, a day settled, and its number listed under its accounts.
fn applied(book: Book, entry: Entry) : Book
  ensures result.entry_count == book.entry_count + 1
  page = entry.number / 256
  balance_of = posted(entry)
  var after = book
  after.entries = book.entries.set(page,
    (book.entries.get(page) or Map.new()).set(entry.number, entry))
  after.balances = entry.postings.reduce(book.balances, fn(sums, p) with_posting(sums, p) end)
  after.lists = listed_under(book.lists, entry)
  after.posted = book.posted + balance_of
  after.unbalanced = book.unbalanced + if balance_of == 0: 0 else: 1
  after.keyed_entries = book.keyed_entries + if entry.key == "": 0 else: 1
  after.next_entry = max_of(book.next_entry, entry.number + 1)
  after.entry_count = book.entry_count + 1
  case entry.kind
    Transfer: after
    Hold: opened_hold(after, entry)
    Capture: captured_hold(closed_hold(after, entry), entry)
    Release: closed_hold(after, entry)
    Refund: refunded_capture(after, entry)
    Settlement: settled_day(after, entry)
  end
end

fn with_posting(sums: Map(String, Int64), p: Posting) : Map(String, Int64)
  sums.update(p.account, 0, fn(n) n + p.amount end)
end

fn opened_hold(book: Book, entry: Entry) : Book
  until = entry.expires_at or entry.at
  var after = book
  after.holds = book.holds.set(entry.number,
    Hold(number: entry.number, account: entry.account, amount: entry.amount, expires_at: until))
  after.held = book.held.update(entry.account, 0, fn(n) n + entry.amount end)
  after
end

# A capture or a release closes its hold: what it held is no longer held, and the hold is closed
# by this entry.
fn closed_hold(book: Book, entry: Entry) : Book
  number = entry.hold or 0
  page = number / 256
  var after = book
  after.closed = book.closed.set(page,
    (book.closed.get(page) or Map.new()).set(number, entry.number))
  case book.holds.get(number)
    Some(live):
      var freed = after
      freed.holds = book.holds.remove(number)
      freed.held = book.held.update(live.account, 0, fn(n) n - live.amount end)
      freed
    None: after
  end
end

fn captured_hold(book: Book, entry: Entry) : Book
  page = entry.number / 256
  clearing = entry.postings.find(fn(p) clearing?(p.account) end)
  made = Captured(number: entry.number, account: entry.account,
    clearing: clearing.map(fn(p) p.account end) or "", amount: entry.amount, refunded: 0)
  var after = book
  after.captures = book.captures.set(page,
    (book.captures.get(page) or Map.new()).set(entry.number, made))
  after
end

fn refunded_capture(book: Book, entry: Entry) : Book
  number = entry.capture or 0
  page = number / 256
  case capture_at(book, number)
    Some(was):
      var more = was
      more.refunded = was.refunded + entry.amount
      var after = book
      after.captures = book.captures.set(page,
        (book.captures.get(page) or Map.new()).set(number, more))
      after
    None: book
  end
end

fn settled_day(book: Book, entry: Entry) : Book
  case entry.day
    Some(day):
      var after = book
      after.settled = book.settled.set(day, entry.number)
      after
    None: book
  end
end

# The entry's number under each account it concerns, and under its kind, while the list is under
# a hundred: a listing is the first hundred by id.
fn listed_under(lists: Map(String, List(UInt64)), entry: Entry) : Map(String, List(UInt64))
  name = kind_name(entry.kind)
  touched = entry.postings.map(fn(p) p.account end).push(entry.account).unique
  all = pushed(pushed(lists, "/", entry.number), "/#{name}", entry.number)
  touched.filter(fn(a) a != "" end).reduce(all, fn(so_far, a)
    pushed(pushed(so_far, "#{a}/", entry.number), "#{a}/#{name}", entry.number)
  end)
end

fn pushed(lists: Map(String, List(UInt64)), name: String, number: UInt64) : Map(String,
  List(UInt64))
  lists.update(name, [], fn(held) if held.size >= 100: held else: held.push(number) end)
end

# The first hundred entries by id, of an account or of all, of a kind or of all.
fn listed(book: Book, account: Option(String), kind: Option(Kind)) : List(Entry)
  ensures result.size <= 100
  name = "#{account or ""}/#{kind.map(fn(k) kind_name(k) end) or ""}"
  (book.lists.get(name) or []).flat_map(fn(number) found(book, number) end)
end

fn found(book: Book, number: UInt64) : List(Entry)
  case entry_at(book, number)
    Some(entry): [entry]
    None: []
  end
end

fn with_account(book: Book, account: Account) : Book
  var after = book
  after.accounts = book.accounts.set(account_id(account.number), account)
  after.next_account = max_of(book.next_account, account.number + 1)
  after
end

# The book with the key's row, counted by what it names.
fn with_keyed(book: Book, key: String, row: Keyed) : Book
  at = bucket_of(key)
  counted = uncounted(book, keyed(book, key))
  named = if row.made.starts_with?("e_"): 1 else: 0
  lost = if names_nothing?(book, row.made): 1 else: 0
  var after = counted
  after.keys = book.keys.set(at, (book.keys.get(at) or Map.new()).set(key, row))
  after.naming = counted.naming + named
  after.dangling = counted.dangling + lost
  after
end

fn uncounted(book: Book, row: Option(Keyed)) : Book
  case row
    Some(was):
      named = if was.made.starts_with?("e_"): 1 else: 0
      lost = if names_nothing?(book, was.made): 1 else: 0
      var after = book
      after.naming = book.naming - min_of(book.naming, named)
      after.dangling = book.dangling - min_of(book.dangling, lost)
      after
    None: book
  end
end

fn names_nothing?(book: Book, made: String) : Bool
  return false if made == ""
  case number_in("e_", made)
    Some(number): entry_at(book, number).map(fn(e) entry_id(e.number) end) != Some(made)
    None:
      case number_in("a_", made)
        Some(_): account_of_id(book, made) is None
        None: true
      end
  end
end

# Every live hold whose expiry has come, oldest first.
fn due_holds(book: Book, now: Time) : List(Hold)
  book.holds.values.filter(fn(h) !(now < h.expires_at) end).sort_by(fn(h) h.number end)
end

# The account's live holds whose expiry has come, oldest first.
fn due_on(book: Book, account: String, now: Time) : List(Hold)
  due_holds(book, now).filter(fn(h) h.account == account end)
end

fn held_total(book: Book) : Int64
  book.holds.values.reduce(0, fn(total, h) total + h.amount end)
end

# The sum of every positive balance equals the overdraft drawn by every negative one, every
# balance together equals the sum of the journal's postings, and no entry's postings are
# unbalanced.
fn balanced?(book: Book) : Bool
  book.unbalanced == 0 and book.balances.values.reduce(0, fn(t, v) t + v end) == book.posted
end

# What the live holds keep, summed from the holds themselves, is at most what the accounts have
# before the holds: every balance plus its overdraft.
fn covered?(book: Book) : Bool
  room = book.accounts.values.reduce(0, fn(total, a)
    total + balance(book, account_id(a.number)) + a.overdraft
  end)
  held_total(book) <= room
end

# Every live hold expires later than now, or an Expire for it is on its way.
fn timed?(book: Book, pending: Set(UInt64), now: Time) : Bool
  book.holds.values.all?(fn(h) now < h.expires_at or pending.has?(h.number) end)
end

# Every key row names something the book holds, and every entry a client's key made has its row.
fn keyed?(book: Book) : Bool
  book.dangling == 0 and book.naming == book.keyed_entries
end

fn t0() : Time
  Time.from_parts(2_026, 1, 1, 0, 0, 0)
end

fn ada() : Account
  Account(number: 1, name: "ada", currency: "USD", overdraft: 10_000, created_at: t0())
end

fn grace() : Account
  Account(number: 2, name: "grace", currency: "USD", overdraft: 0, created_at: t0())
end

fn moved(number: UInt64, kind: Kind, postings: List(Posting), key: String) : Entry
  var made = blank(number, kind, key, t0())
  made.postings = postings
  made
end

fn opened() : Book
  with_account(with_account(book(), ada()), grace())
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

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
