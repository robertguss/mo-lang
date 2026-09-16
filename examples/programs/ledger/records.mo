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
  var done = first
  if place.log != "ledger.log"
    done = try replayed(folder, fresh_lines(first), place.log, names, by)
  end
  built = try rebuilt(done.loading)
  table = Table(buckets: Map.new(), size: 0, dir: place.dir, name: place.log, bytes: done.size,
    lines: done.loading.lines, cut: done.cut)
  Ok(Opened(book: built, table: table, torn: done.cut))
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
  return Error("holds a #{name} whose line #{read.bad} is not a ledger record") if read.bad > 0
  whole = read.bytes <= size
  var done = read
  if whole and read.pending is Some(last)
    done = taken(read, last)
  end
  return Error("holds a #{name} whose line #{done.bad} is not a ledger record") if done.bad > 0
  Ok(Replayed(loading: done, size: size, cut: !whole or done.expected > 0))
end

fn names_of(folder: Fs, by: Deadline) : Result(List(String), String)
  case folder.list(within: by.at_most(10_000.ms))
    Ok(names): Ok(names)
    Error(Missing(_)): Error("is not a folder the ledger can read")
    Error(Timeout): Error("is a folder too slow to read")
    Error(NotText): Error("is not a folder the ledger can read")
  end
end

fn size_in(folder: Fs, name: String, by: Deadline) : Result(UInt64, String)
  case folder.size(name, within: by.at_most(10_000.ms))
    Ok(bytes): Ok(bytes)
    Error(Missing(_)): Error("holds a #{name} the ledger cannot read")
    Error(Timeout): Error("is a folder too slow to read")
    Error(NotText): Error("holds a #{name} the ledger cannot read")
  end
end

fn folded(folder: Fs, start: Loading, name: String, by: Deadline) : Result(Loading, String)
  case folder.fold_lines(name, start, within: by.at_most(600_000.ms),
    fn(l, line) stepped(l, line) end)
    Ok(read): Ok(read)
    Error(Missing(_)): Error("holds a #{name} the ledger cannot read")
    Error(Timeout): Error("is a folder too slow to read")
    Error(NotText): Error("holds a #{name} the ledger cannot read")
  end
end

fn taken_pending(l: Loading) : Loading
  case l.pending
    Some(previous): taken(l, previous)
    None: l
  end
end

fn emptied(l: Loading) : Loading
  var next = l
  next.batch = []
  next.expected = 0
  next
end

fn bad_at(l: Loading) : Loading
  var next = l
  next.bad = l.lines
  next
end

fn entry_pairs(whole: Book, page: UInt64) : List((String, String))
  held = (whole.entries.get(page) or Map.new()).entries.sort_by(fn(e) e.0 end)
  held.map(fn(e) (entry_id(e.0), shown_entry(e.1)) end)
end

fn key_pairs(page: Map(String, Keyed)) : List((String, String))
  page.entries.map(fn(row) (key_name(row.0), keyed_json(row.1)) end)
end

# The next line read: the one before it is whole, since another came after it, so it is taken.
fn stepped(l: Loading, line: String) : Loading
  done = if l.bad > 0: l else: taken_pending(l)
  var next = done
  next.pending = Some(line)
  next.bytes = l.bytes + line.byte_size + 1
  next
end

# A whole line taken, as the store takes one: a BEGIN opens a batch, whose lines are held until
# its last, and any other line is kept at once.
fn taken(l: Loading, line: String) : Loading
  var next = l
  next.lines = l.lines + 1
  if l.expected > 0
    held = l.batch.push(line)
    return kept_all(emptied(next), held) if held.size >= l.expected
    next.batch = held
    return next
  end
  if line.starts_with?("BEGIN ")
    count = line.slice(6, line.size).to_u64 or 0
    if count == 0
      next.bad = l.lines + 1
      return next
    end
    next.expected = count
    next.batch = []
    return next
  end
  kept(next, line)
end

fn kept_all(l: Loading, lines: List(String)) : Loading
  lines.reduce(l, fn(so_far, line) kept(so_far, line) end)
end

# A SET line kept under its key: an account's record replaces the one before, an entry is read
# as it is kept, and a key's row replaces the one before; anything else is a bad line.
fn kept(l: Loading, line: String) : Loading
  return bad_at(l) if !line.starts_with?("SET ")
  rest = line.slice(4, line.size)
  at = rest.index_of(" ") or 0
  name = rest.slice(0, at)
  value = rest.slice(at + 1, rest.size)
  var next = l
  if name.starts_with?("a_")
    next.accounts = l.accounts.set(name, value)
    return next
  end
  if name.starts_with?("i_")
    page = page_of(name)
    next.keys = l.keys.set(page, (l.keys.get(page) or Map.new()).set(name, value))
    return next
  end
  number = name.slice(2, name.size).to_u64 or 0
  return bad_at(l) if entry_id(number) != name
  case entry_of(value)
    Some(entry):
      page = number / 256
      next.entries = l.entries.set(page, (l.entries.get(page) or Map.new()).set(number, entry))
      next
    None: bad_at(l)
  end
end

fn page_of(name: String) : UInt64
  name.bytes.reduce(0, fn(hash, b) (hash * 31 + b.to_u64) % 1_024 end)
end

# The book a replay folds to: every account from its last record, with no balance read from it;
# every entry folded in by number, which sums every balance from the postings; and every key's row.
fn rebuilt(l: Loading) : Result(Book, String)
  found = l.accounts.keys.sort.flat_map(fn(name) listed(account_of(l.accounts.get(name) or "")) end)
  return Error("holds an account record that is not an account") if found.size != l.accounts.size
  opened = found.reduce(book(), fn(so_far, account) with_account(so_far, account) end)
  numbered = l.entries.keys.sort.flat_map(fn(page) page_entries(l, page) end)
  folded_in = numbered.reduce(opened, fn(so_far, entry) applied(so_far, entry) end)
  rows = l.keys.values.flat_map(fn(page) page.entries end).flat_map(fn(named) row_of(named) end)
  Ok(rows.reduce(folded_in, fn(so_far, row) with_keyed(so_far, row.0, row.1) end))
end

fn page_entries(l: Loading, page: UInt64) : List(Entry)
  (l.entries.get(page) or Map.new()).entries.sort_by(fn(e) e.0 end).map(fn(e) e.1 end)
end

fn listed(account: Option(Account)) : List(Account)
  case account
    Some(found): [found]
    None: []
  end
end

fn row_of(named: (String, String)) : List((String, Keyed))
  return [] if !named.0.starts_with?("i_")
  case unhex(named.0.slice(2, named.0.size))
    Some(key):
      case keyed_of(named.1)
        Some(row): [(key, row)]
        None: []
      end
    None: []
  end
end

# The text a key's store name spells in hex.
fn unhex(text: String) : Option(String)
  digits = text.bytes.map(fn(b) nibble(b) end)
  return None if digits.size % 2 != 0 or digits.any?(fn(n) n > 15 end)
  made = (0..(digits.size / 2)).map(fn(i)
    ((digits.get(i * 2) or 0) * 16 + (digits.get(i * 2 + 1) or 0)).to_u8
  end)
  String.from_bytes(made)
end

fn nibble(b: UInt8) : UInt64
  return b.to_u64 - 48 if b >= 48 and b <= 57
  return b.to_u64 - 87 if b >= 97 and b <= 102
  99
end

# The batch appended in one write, on at most 5 seconds of what remains of the deadline so a
# failed append can be looked at again: a log that holds the whole batch took it, one as long as
# before did not, and anything else may end in part of it.
fn flushed_to(fs: Fs, table: Table, pairs: List((String, String)), by: Deadline) : Result(Table,
  StoreError)
  return Ok(table) if pairs.size == 0
  folder = fs.scoped(table.dir)
  text = batch_text(pairs)
  after = table.bytes + text.byte_size
  var grown = table
  grown.bytes = after
  return Ok(grown) if folder.append(table.name, text, within: by.at_most(5_000.ms)) is Ok(_)
  case folder.size(table.name, within: by.at_most(5_000.ms))
    Ok(size):
      return Ok(grown) if size == after
      return Error(Unwritten) if size == table.bytes
      Error(Torn)
    Error(Missing(_)):
      return Error(Unwritten) if table.bytes == 0
      Error(Torn)
    Error(Timeout): Error(Torn)
    Error(NotText): Error(Torn)
  end
end

# The log written whole from the book, one SET line per account, entry, and key row, beside the
# log and renamed over it; the rename has what remains after the write.
fn rewritten_from(fs: Fs, table: Table, whole: Book, by: Deadline) : Result(Table, StoreError)
  folder = fs.scoped(table.dir)
  pairs = records_of(whole)
  text = String.join(pairs.map(fn(pair) set_line(pair.0, pair.1) end), "")
  fresh = "#{table.name}.new"
  if folder.write(fresh, text, within: by.at_most(20_000.ms)) is Error(_)
    return Error(Unwritten)
  end
  if folder.rename(fresh, table.name, within: by) is Error(_)
    return Error(Unwritten)
  end
  var after = table
  after.bytes = text.byte_size
  after.lines = pairs.size
  after.cut = false
  Ok(after)
end

fn records_of(whole: Book) : List((String, String))
  accounts = whole.accounts.values.map(fn(account) account_pair(whole, account) end)
  entries = whole.entries.keys.sort.flat_map(fn(page) entry_pairs(whole, page) end)
  rows = whole.keys.values.flat_map(fn(page) key_pairs(page) end)
  accounts.concat(entries).concat(rows)
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
  n = b.to_u64
  "#{digits.slice(n / 16, n / 16 + 1)}#{digits.slice(n % 16, n % 16 + 1)}"
end

fn t0() : Time
  Time.from_parts(2_026, 9, 14, 10, 0, 0)
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
    call(PlaceHold(account: "a_2", amount: 1_000, ttl_ms: 3_600_000), "h"),
    call(CaptureHold(hold: "e_2", amount: 600), "c"),
    call(RefundCapture(capture: "e_3", amount: 100), "r")]
  var made = book()
  var log = table
  for one in calls
    done = decide(made, one, t0(), t0())
    if flushed_to(fs, log, done.records, by) is Ok(after)
      log = after
      made = done.book
    end
  end
  made
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
