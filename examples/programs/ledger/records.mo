module Ledger.Records
expose Place, Loading, Opened, opened_book, flushed_to, rewritten_from, rebuilt, taken, loading

use Ledger.Entry{Account, Entry, account_of, entry_of, account_id, entry_id, shown_account, shown_entry}
use Ledger.Index{Keyed, Book, book, applied, with_account, with_keyed, balance, available, keyed, entry_at}
use Ledger.Store{Table, StoreError, set_line, batch_text}
use Ledger.Teller{Command, Call, Decision, decide, keyed_of, keyed_json}

intent "The journal's file calls, each on its asker's deadline: open replays ledger.log (and a check's own log after it) into a book, reading each account's last record for its name and overdraft only and summing every balance again from the entries' postings; a batch goes to the log in one append; and a log that may end in part of a batch is written whole from the book, beside it, and renamed over it."

# Where a journal keeps its records: the folder, and the log in it its changes go to, ledger.log
# itself, or ledger.check.log replayed after it.
struct Place
  dir: String
  log: String
end

# A replay so far: each account's last record, the entries by number in pages of 256, each key's
# last row by its store name, the line read but not taken until the next, lines taken, bytes read,
# the first bad line, and a batch still open with how many more lines it said it holds.
struct Loading
  accounts: Map(String, String)
  entries: Map(UInt64, Map(UInt64, Entry))
  keys: Map(UInt64, Map(String, String))
  pending: Option(String)
  lines: UInt64
  bytes: UInt64
  bad: UInt64
  batch: List(String)
  expected: UInt64
end

# What open found: the book, the log the journal appends to as the store knows it, and whether
# that log may end in part of a batch, so the next flush writes it whole.
struct Opened
  book: Book
  table: Table
  torn: Bool
end

fn loading() : Loading
  # body gone; regenerate
end

# The book the place's logs replay to, on the deadline; a folder with no log opens empty.
fn opened_book(fs: Fs, place: Place, by: Deadline) : Result(Opened, String)
  # body gone; regenerate
end

struct Replayed
  loading: Loading
  size: UInt64
  cut: Bool
end

fn fresh_lines(done: Replayed) : Loading
  # body gone; regenerate
end

fn replayed(folder: Fs, start: Loading, name: String, names: List(String),
  by: Deadline) : Result(Replayed, String)
  # body gone; regenerate
end

fn names_of(folder: Fs, by: Deadline) : Result(List(String), String)
  # body gone; regenerate
end

fn size_in(folder: Fs, name: String, by: Deadline) : Result(UInt64, String)
  # body gone; regenerate
end

fn folded(folder: Fs, start: Loading, name: String, by: Deadline) : Result(Loading, String)
  # body gone; regenerate
end

# The next line read: the one before it is whole, since another came after it, so it is taken.
fn stepped(l: Loading, line: String) : Loading
  # body gone; regenerate
end

# A whole line taken, as the store takes one: a BEGIN opens a batch, whose lines are held until
# its last, and any other line is kept at once.
fn taken(l: Loading, line: String) : Loading
  # body gone; regenerate
end

fn kept_all(l: Loading, lines: List(String)) : Loading
  # body gone; regenerate
end

# A SET line kept under its key: an account's record replaces the one before, an entry is read
# as it is kept, and a key's row replaces the one before; anything else is a bad line.
fn kept(l: Loading, line: String) : Loading
  # body gone; regenerate
end

fn page_of(name: String) : UInt64
  # body gone; regenerate
end

# The book a replay folds to: every account from its last record, with no balance read from it;
# every entry folded in by number, which sums every balance from the postings; and every key's row.
fn rebuilt(l: Loading) : Result(Book, String)
  # body gone; regenerate
end

fn page_entries(l: Loading, page: UInt64) : List(Entry)
  # body gone; regenerate
end

fn listed(account: Option(Account)) : List(Account)
  # body gone; regenerate
end

fn row_of(named: (String, String)) : List((String, Keyed))
  # body gone; regenerate
end

# The text a key's store name spells in hex.
fn unhex(text: String) : Option(String)
  # body gone; regenerate
end

fn nibble(b: UInt8) : UInt64
  # body gone; regenerate
end

# The batch appended in one write, on at most 5 seconds of what remains of the deadline so a
# failed append can be looked at again: a log that holds the whole batch took it, one as long as
# before did not, and anything else may end in part of it.
fn flushed_to(fs: Fs, table: Table, pairs: List((String, String)), by: Deadline) : Result(Table,
  # body gone; regenerate
end

# The log written whole from the book, one SET line per account, entry, and key row, beside the
# log and renamed over it; the rename has what remains after the write.
fn rewritten_from(fs: Fs, table: Table, whole: Book, by: Deadline) : Result(Table, StoreError)
  # body gone; regenerate
end

fn records_of(whole: Book) : List((String, String))
  # body gone; regenerate
end

fn account_pair(whole: Book, account: Account) : (String, String)
  # body gone; regenerate
end

fn key_name(key: String) : String
  # body gone; regenerate
end

fn hex(b: UInt8) : String
  # body gone; regenerate
end

fn t0() : Time
  # body gone; regenerate
end

fn here() : Place
  # body gone; regenerate
end

fn call(command: Command, key: String) : Call
  # body gone; regenerate
end

# Ada, grace, 1,500 from ada to grace, a hold on grace of 1,000 captured for 600, and 100 of it
# refunded: each call's records appended as a batch, as a journal writes them.
fn written(fs: Fs, table: Table, by: Deadline) : Book
  # body gone; regenerate
end

test "a log of the teller's batches replays to the same book, every balance summed from the postings"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert opened_book(fs, here(), by) == Error("is not a folder the ledger can read")
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(empty)
  kept_book = written(fs, empty.table, by)
  assert opened_book(fs, here(), by) is Ok(again)
  assert again.book.balances == kept_book.balances and again.book.entry_count == 4
  assert again.book.holds == kept_book.holds and keyed(again.book, "c") == keyed(kept_book, "c")
  assert again.book.captures == kept_book.captures and again.book.keyed_entries == 4
  assert !again.torn and again.table.bytes > 0
end

test "a balance an account's record carries is never trusted over the postings"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(empty)
  kept_book = written(fs, empty.table, by)
  assert fs.read("d/ledger.log", within: 1.minute) is Ok(text)
  assert text.contains?("\"balance\": -1500")
  lied = text.replace("\"balance\": -1500", "\"balance\": 99")
  assert fs.write("d/ledger.log", lied, within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(again)
  assert balance(again.book, "a_1") == -1_500 and again.book.balances == kept_book.balances
end

test "a batch the log ends inside of is left out, and the log is torn until it is written whole"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(empty)
  kept_book = written(fs, empty.table, by)
  assert fs.read("d/ledger.log", within: 1.minute) is Ok(text)
  assert fs.write("d/ledger.log", text.slice(0, text.size - 20), within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(cut)
  assert cut.torn and cut.book.entry_count == 3 and entry_at(cut.book, 4) is None
  assert rewritten_from(fs, cut.table, kept_book, by) is Ok(whole)
  assert !whole.cut
  assert opened_book(fs, here(), by) is Ok(again)
  assert !again.torn and again.book.balances == kept_book.balances and again.book.entry_count == 4
end

test "a check's own log replays over ledger.log, and its batches go only to it"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(empty)
  kept_book = written(fs, empty.table, by)
  assert fs.read("d/ledger.log", within: 1.minute) is Ok(before)
  checking = Place(dir: "d", log: "ledger.check.log")
  assert opened_book(fs, checking, by) is Ok(check)
  assert check.table.name == "ledger.check.log" and check.table.bytes == 0
  more = decide(check.book, call(MoveMoney(from: "a_2", to: "a_1", amount: 5), "back"), t0(), t0())
  assert flushed_to(fs, check.table, more.records, by) is Ok(_)
  assert fs.read("d/ledger.log", within: 1.minute) == Ok(before)
  assert opened_book(fs, checking, by) is Ok(again)
  assert again.book.balances == more.book.balances and again.book.entry_count == kept_book.entry_count + 1
end

test "a batch the log cannot take is Unwritten or Torn, and a log with a line that is no record does not open"
  fs = Fs.fixture()
  by = Deadline.fixture(1.minute)
  assert fs.mkdir("d", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) is Ok(empty)
  pairs = [("e_1", "x")]
  assert flushed_to(Fs.fixture(delay: 1.minute), empty.table, pairs,
    Deadline.fixture(10_000.ms)) is Error(_)
  assert flushed_to(fs, empty.table, pairs, Deadline.fixture(0.ms)) is Error(_)
  assert fs.write("d/ledger.log", "SET e_1 not an entry\n", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(),
    by) == Error("holds a ledger.log whose line 1 is not a ledger record")
  assert fs.write("d/ledger.log", "SET a_1 {}\n", within: 1.minute) is Ok(_)
  assert opened_book(fs, here(), by) == Error("holds an account record that is not an account")
end
