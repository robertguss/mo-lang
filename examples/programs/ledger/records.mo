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
  Loading(accounts: Map.new(), entries: Map.new(), keys: Map.new(), pending: None, lines: 0,
    bytes: 0, bad: 0, batch: [], expected: 0)
end

# The book the place's logs replay to, on the deadline; a folder with no log opens empty.
fn opened_book(fs: Fs, place: Place, by: Deadline) : Result(Opened, String)
  folder = fs.scoped(place.dir)
  names = try names_of(folder, by)
  first = try replayed(folder, loading(), "ledger.log", names, by)
  own = if place.log == "ledger.log"
    first
  else
    try replayed(folder, fresh_lines(first), place.log, names, by)
  end
  opened = try rebuilt(own.loading)
  bytes = if names.contains?(place.log): own.size else: 0
  table = Table(buckets: Map.new(), size: 0, dir: place.dir, name: place.log, bytes: bytes,
    lines: own.loading.lines, cut: own.cut)
  Ok(Opened(book: opened, table: table, torn: own.cut))
end

struct Replayed
  loading: Loading
  size: UInt64
  cut: Bool
end

fn fresh_lines(done: Replayed) : Loading
  var next = done.loading
  next.pending = None
  next.lines = 0
  next.bytes = 0
  next.batch = []
  next.expected = 0
  next
end

fn replayed(folder: Fs, start: Loading, name: String, names: List(String),
  by: Deadline) : Result(Replayed, String)
  return Ok(Replayed(loading: start, size: 0, cut: false)) if !names.contains?(name)
  size = try size_in(folder, name, by)
  read = try folded(folder, start, name, by)
  whole = read.bytes <= size
  last = if whole and read.pending is Some(line): taken(read, line) else: read
  return Error("holds a #{name} whose line #{last.bad} is not a ledger record") if last.bad > 0
  Ok(Replayed(loading: last, size: size, cut: !whole or last.expected > 0))
end

fn names_of(folder: Fs, by: Deadline) : Result(List(String), String)
  case folder.list(within: by)
    Ok(found): Ok(found)
    Error(Timeout): Error("took longer to list than its opening was given")
    Error(Missing(_)) | Error(NotText): Error("is not a folder the ledger can read")
  end
end

fn size_in(folder: Fs, name: String, by: Deadline) : Result(UInt64, String)
  case folder.size(name, within: by)
    Ok(bytes): Ok(bytes)
    Error(_): Error("holds a #{name} the ledger cannot read")
  end
end

fn folded(folder: Fs, start: Loading, name: String, by: Deadline) : Result(Loading, String)
  case folder.fold_lines(name, start, within: by, fn(l, line) stepped(l, line) end)
    Ok(l): Ok(l)
    Error(Timeout): Error("took longer to replay than its opening was given")
    Error(Missing(_)) | Error(NotText): Error("holds a #{name} the ledger cannot read")
  end
end

# The next line read: the one before it is whole, since another came after it, so it is taken.
fn stepped(l: Loading, line: String) : Loading
  var next = l
  next.bytes = l.bytes + line.byte_size + 1
  next.pending = Some(line)
  return next if l.bad > 0
  case l.pending
    Some(previous): taken(next, previous)
    None: next
  end
end

# A whole line taken, as the store takes one: a BEGIN opens a batch, whose lines are held until
# its last, and any other line is kept at once.
fn taken(l: Loading, line: String) : Loading
  var next = l
  next.lines = l.lines + 1
  if line.starts_with?("BEGIN ")
    next.expected = line.slice(6, line.size).to_u64 or 0
    next.batch = []
    return next
  end
  return kept_all(next, [line]) if l.expected == 0
  next.batch = l.batch.push(line)
  next.expected = l.expected - 1
  return next if next.expected > 0
  kept_all(next, next.batch)
end

fn kept_all(l: Loading, lines: List(String)) : Loading
  var next = l
  next.batch = []
  for line in lines
    next = kept(next, line)
    if next.bad > 0
      break
    end
  end
  next
end

# A SET line kept under its key: an account's record replaces the one before, an entry is read
# as it is kept, and a key's row replaces the one before; anything else is a bad line.
fn kept(l: Loading, line: String) : Loading
  var next = l
  rest = line.slice(4, line.size)
  at = rest.index_of(" ") or rest.size
  name = rest.slice(0, at)
  value = rest.slice(at + 1, rest.size)
  if !line.starts_with?("SET ")
    next.bad = l.lines
    return next
  end
  if name.starts_with?("a_")
    next.accounts = l.accounts.set(name, value)
    return next
  end
  if name.starts_with?("i_")
    page = l.keys.get(page_of(name)) or Map.new()
    next.keys = l.keys.set(page_of(name), page.set(name, value))
    return next
  end
  case entry_of(value)
    Some(entry):
      if name.starts_with?("e_") and entry_id(entry.number) == name
        page = l.entries.get(entry.number / 256) or Map.new()
        next.entries = l.entries.set(entry.number / 256, page.set(entry.number, entry))
        return next
      end
      next.bad = l.lines
    None:
      next.bad = l.lines
  end
  next
end

fn page_of(name: String) : UInt64
  name.bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 256 end)
end

# The book a replay folds to: every account from its last record, with no balance read from it;
# every entry folded in by number, which sums every balance from the postings; and every key's row.
fn rebuilt(l: Loading) : Result(Book, String)
  accounts = l.accounts.values.map(fn(text) account_of(text) end)
  opened = accounts.flat_map(fn(a) listed(a) end).sort_by(fn(a) a.number end)
  if opened.size != accounts.size
    return Error("holds an account record that is not an account")
  end
  with_accounts = opened.reduce(book(), fn(b, a) with_account(b, a) end)
  pages = l.entries.keys.sort.flat_map(fn(p) page_entries(l, p) end)
  with_entries = pages.reduce(with_accounts, fn(b, e) applied(b, e) end)
  rows = l.keys.values.flat_map(fn(page) page.entries end)
  keyed_rows = rows.flat_map(fn(r) row_of(r) end)
  if keyed_rows.size != rows.size
    return Error("holds a key row that is not one")
  end
  Ok(keyed_rows.reduce(with_entries, fn(b, r) with_keyed(b, r.0, r.1) end))
end

fn page_entries(l: Loading, page: UInt64) : List(Entry)
  (l.entries.get(page) or Map.new()).values.sort_by(fn(e) e.number end)
end

fn listed(account: Option(Account)) : List(Account)
  case account
    Some(a): [a]
    None: []
  end
end

fn row_of(named: (String, String)) : List((String, Keyed))
  case (unhex(named.0.slice(2, named.0.size)), keyed_of(named.1))
    (Some(key), Some(row)): [(key, row)]
    _: []
  end
end

# The text a key's store name spells in hex.
fn unhex(text: String) : Option(String)
  bytes = text.bytes
  return None if bytes.size % 2 == 1
  pairs = (0..bytes.size / 2).map(fn(i)
    nibble(bytes.get(i * 2) or 0) * 16 + nibble(bytes.get(i * 2 + 1) or 0)
  end)
  String.from_bytes(pairs.map(fn(n) n.to_u8 end))
end

fn nibble(b: UInt8) : UInt64
  return (b - 48).to_u64 if b >= 48 and b <= 57
  return (b - 87).to_u64 if b >= 97 and b <= 102
  0
end

# The batch appended in one write, on at most 5 seconds of what remains of the deadline so a
# failed append can be looked at again: a log that holds the whole batch took it, one as long as
# before did not, and anything else may end in part of it.
fn flushed_to(fs: Fs, table: Table, pairs: List((String, String)), by: Deadline) : Result(Table,
  StoreError)
  folder = fs.scoped(table.dir)
  text = batch_text(pairs)
  after = table.bytes + text.byte_size
  var grown = table
  grown.bytes = after
  return Ok(grown) if folder.append(table.name, text, within: by.at_most(5_000.ms)) is Ok(_)
  case folder.size(table.name, within: by)
    Ok(size):
      return Ok(grown) if size == after
      return Error(Unwritten) if size == table.bytes
      Error(Torn)
    Error(Missing(_)):
      return Error(Unwritten) if table.bytes == 0
      Error(Torn)
    Error(Timeout) | Error(NotText): Error(Torn)
  end
end

# The log written whole from the book, one SET line per account, entry, and key row, beside the
# log and renamed over it; the rename has what remains after the write.
fn rewritten_from(fs: Fs, table: Table, whole: Book, by: Deadline) : Result(Table, StoreError)
  folder = fs.scoped(table.dir)
  text = String.join(records_of(whole).map(fn(r) set_line(r.0, r.1) end), "")
  fresh = "#{table.name}.new"
  return Error(Unwritten) if folder.write(fresh, text, within: by) is Error(_)
  return Error(Unwritten) if folder.rename(fresh, table.name, within: by) is Error(_)
  var after = table
  after.bytes = text.byte_size
  after.cut = false
  Ok(after)
end

fn records_of(whole: Book) : List((String, String))
  accounts = whole.accounts.values.sort_by(fn(a) a.number end).map(fn(a) account_pair(whole, a) end)
  entries = whole.entries.keys.sort.flat_map(fn(p) (whole.entries.get(p) or Map.new()).values end)
  keys = whole.keys.values.flat_map(fn(page) page.entries end)
  accounts.concat(entries.sort_by(fn(e)
    e.number
  end).map(fn(e)
    (entry_id(e.number), shown_entry(e))
  end)).concat(keys.map(fn(k) (key_name(k.0), keyed_json(k.1)) end))
end

fn account_pair(whole: Book, account: Account) : (String, String)
  id = account_id(account.number)
  (id, shown_account(account, balance(whole, id), available(whole, id)))
end

fn key_name(key: String) : String
  "i_#{String.join(key.bytes.map(fn(b) hex(b) end), "")}"
end

fn hex(b: UInt8) : String
  digits = "0123456789abcdef"
  high = (b / 16).to_u64
  low = (b % 16).to_u64
  "#{digits.slice(high, high + 1)}#{digits.slice(low, low + 1)}"
end

fn t0() : Time
  Time.from_parts(2026, 9, 14, 9, 0, 0)
end

fn here() : Place
  Place(dir: "d", log: "ledger.log")
end

fn call(command: Command, key: String) : Call
  Call(command: command, key: key, request: key)
end

# Ada, grace, 1,500 from ada to grace, a hold on grace of 1,000 captured for 600, and 100 of it
# refunded: each call's records appended as a batch, as a journal writes them.
fn written(fs: Fs, table: Table, by: Deadline) : Book
  calls = [call(OpenAccount(name: "ada", currency: "USD", overdraft: 10_000), "o1"),
    call(OpenAccount(name: "grace", currency: "USD", overdraft: 0), "o2"),
    call(MoveMoney(from: "a_1", to: "a_2", amount: 1_500), "t"),
    call(PlaceHold(account: "a_2", amount: 1_000, ttl_ms: 60_000), "h"),
    call(CaptureHold(hold: "e_2", amount: 600), "c"),
    call(RefundCapture(capture: "e_3", amount: 100), "r")]
  var at = book()
  var log = table
  for c in calls
    done = decide(at, c, t0(), t0())
    at = done.book
    case flushed_to(fs, log, done.records, by)
      Ok(grown):
        log = grown
      Error(_):
        break
    end
  end
  at
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

verified: types, contracts, tests (5), property (0 seeds), sim (not run)
          proven: not run
