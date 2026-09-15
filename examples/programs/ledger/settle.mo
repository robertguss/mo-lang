module Ledger.Settle
expose Item, Line, Statement, Settled, statement, settled, shown_statement, day_of

use Ledger.Book{Refusal, Moved, opened, transferred, held, captured}
use Ledger.Entry{Kind, Entry, blank, entry_id, clearing?, kind_name}
use Ledger.Index{Book, applied, book}
use Ledger.Money{day?, key?, card_run?}

intent "Settle a day: a settlement entry, and the statement it answers with, per account the opening balance, the day's entries with what each moved on the account, and the closing balance, all over the entries before the settlement, so the same statement is shown again whenever it is asked for; a day is settled once, and never before it has begun."

never "a card number reaches a statement"
  for l in Line.all
    card_run?(l.name)
  end
end

# An entry of the day as a statement shows it on one account.
struct Item
  entry: String
  kind: String
  amount: Int64
end

# One account's day. The closing balance is summed from the postings of every entry up to the
# day's end, apart from the opening and the items, so a statement whose parts do not add up is
# caught by settle's ensures.
struct Line
  account: String
  name: String
  currency: String
  opening: Int64
  items: List(Item)
  closing: Int64
end

struct Statement
  day: String
  settlement: UInt64
  lines: List(Line)
end

struct Settled
  book: Book
  entry: Entry
  statement: Statement
end

# The UTC day a time falls on, as YYYY-MM-DD.
fn day_of(at: Time) : String
  at.to_iso8601.slice(0, 10)
end

# Settles the day with a settlement entry, answering with its statement: 422 for a day that has
# not begun, 409 for a day already settled.
fn settled(book: Book, day: String, key: String, now: Time) : Result(Settled, Refusal)
  requires day?(day)
  requires key?(key)
  ensures result is Ok(s) implies s.statement.lines.all?(fn(l) added_up?(l) end)

  if day > day_of(now)
    return Error(Refusal(status: 422, rule: "future_day", error: "#{day} has not begun", by: 0))
  end
  if book.settled.get(day) is Some(number)
    return Error(Refusal(status: 409, rule: "settled",
      error: "#{day} was settled by #{entry_id(number)}", by: 0))
  end
  var entry = blank(book.next_entry, Settlement, key, now)
  entry.day = Some(day)
  Ok(Settled(book: applied(book, entry), entry: entry,
    statement: statement(book, day, entry.number)))
end

fn added_up?(line: Line) : Bool
  line.opening + line.items.map(fn(i) i.amount end).sum == line.closing
end

# The day's statement over every entry numbered below `before`: every account the book opened,
# and every clearing account that moved, by id.
fn statement(book: Book, day: String, before: UInt64) : Statement
  entries = book.entries.values.flat_map(fn(page)
    page.values
  end).filter(fn(e) e.number < before end)
  earlier = entries.filter(fn(e) day_of(e.at) < day end)
  during = entries.filter(fn(e) day_of(e.at) == day end).sort_by(fn(e) e.number end)
  opening = sums(earlier)
  closing = sums(entries.filter(fn(e) day_of(e.at) <= day end))
  opened = book.accounts.values.map(fn(a) (account_key(a.number), a.name, a.currency) end)
  clearing = opening.keys.concat(closing.keys).unique.filter(fn(id) clearing?(id) end)
  named = opened.concat(clearing.map(fn(id) (id, "", id.slice(9, id.size)) end))
  lines = named.map(fn(n) line_of(n, opening, closing, during) end)
  Statement(day: day, settlement: before, lines: lines.sort_by(fn(l) l.account end))
end

fn account_key(number: UInt64) : String
  "a_#{number}"
end

fn sums(entries: List(Entry)) : Map(String, Int64)
  postings = entries.flat_map(fn(e) e.postings end)
  postings.reduce(Map.new(),
    fn(all, p) all.set(p.account, (all.get(p.account) or 0) + p.amount) end)
end

fn line_of(named: (String, String, String), opening: Map(String, Int64),
  closing: Map(String, Int64), during: List(Entry)) : Line
  id = named.0
  mine = during.filter(fn(e) concerns?(e, id) end)
  items = mine.map(fn(e)
    Item(entry: entry_id(e.number), kind: kind_name(e.kind), amount: e.postings.filter(fn(p)
      p.account == id
    end).map(fn(p) p.amount end).sum)
  end)
  Line(account: id, name: named.1, currency: named.2, opening: opening.get(id) or 0, items: items,
    closing: closing.get(id) or 0)
end

fn concerns?(entry: Entry, id: String) : Bool
  entry.account == id or entry.postings.any?(fn(p) p.account == id end)
end

fn shown_statement(s: Statement) : String
  lines = String.join(s.lines.map(fn(l) shown_line(l) end), ", ")
  "{\"day\": \"#{s.day}\", \"settlement\": \"#{entry_id(s.settlement)}\", \"accounts\": [#{lines}]}"
end

fn shown_line(l: Line) : String
  items = String.join(l.items.map(fn(i)
    "{\"id\": \"#{i.entry}\", \"kind\": \"#{i.kind}\", \"amount\": #{i.amount}}"
  end), ", ")
  head = "{\"id\": #{Json.encode(l.account)}, \"name\": #{Json.encode(l.name)}, \"currency\": \"#{l.currency}\""
  "#{head}, \"opening\": #{l.opening}, \"entries\": [#{items}], \"closing\": #{l.closing}}"
end

fn at(day: UInt64, hour: UInt64) : Time
  Time.from_parts(2026, 9, day, hour, 0, 0)
end

fn after(moved: Result(Moved, Refusal), book: Book) : Book
  case moved
    Ok(done): done.book
    Error(_): book
  end
end

# Ada and grace; 1,000 from ada to grace on the 13th; on the 14th 300 back, and a hold on grace
# of 500 captured for 200.
fn busy() : Book
  first = opened(book(), "ada", "USD", 10_000, at(13, 8))
  both = opened(first.book, "grace", "USD", 0, at(13, 8)).book
  paid = after(transferred(both, "a_1", "a_2", 1_000, "t1", at(13, 9)), both)
  back = after(transferred(paid, "a_2", "a_1", 300, "t2", at(14, 9)), paid)
  hold = after(held(back, "a_2", 500, 60_000, "h", at(14, 10)), back)
  after(captured(hold, 3, 200, "c", at(14, 10)), hold)
end

fn line_for(s: Statement, id: String) : Option(Line)
  s.lines.find(fn(l) l.account == id end)
end

test "a day's statement opens with the balances before it, lists its entries per account, and closes with their sum"
  s = statement(busy(), "2026-09-14", 99)
  assert s.lines.map(fn(l) l.account end) == ["a_1", "a_2", "clearing:USD"]
  assert line_for(s,
    "a_1") == Some(Line(account: "a_1", name: "ada", currency: "USD", opening: -1_000,
    items: [Item(entry: "e_2", kind: "transfer", amount: 300)], closing: -700))
  assert line_for(s, "a_2") is Some(grace)
  assert grace.opening == 1_000 and grace.closing == 500
  assert grace.items.map(fn(i) i.amount end) == [-300, 0, -200]
  assert line_for(s, "clearing:USD") is Some(clearing)
  assert clearing.opening == 0 and clearing.closing == 200 and clearing.currency == "USD"
  assert statement(busy(), "2026-09-13", 99).lines.all?(fn(l) l.opening == 0 end)
end

test "a day is settled once, never before it has begun, and its statement is the same when asked again"
  assert settled(busy(), "2026-09-14", "s", at(14, 23)) is Ok(done)
  assert done.entry.day == Some("2026-09-14") and done.book.settled.get("2026-09-14") == Some(5)
  assert statement(done.book, "2026-09-14", done.entry.number) == done.statement
  again = settled(done.book, "2026-09-14", "s2", at(14, 23))
  assert again is Error(twice)
  assert twice.status == 409 and twice.error == "2026-09-14 was settled by e_5"
  assert settled(busy(), "2026-09-15", "s", at(14, 23)) is Error(early)
  assert early.status == 422 and early.rule == "future_day"
  assert settled(busy(), "2026-09-13", "s", at(14, 9)) is Ok(_)
end

test "a statement is shown as JSON, per account, entries in order"
  s = statement(busy(), "2026-09-13", 3)
  assert shown_statement(s) == "{\"day\": \"2026-09-13\", \"settlement\": \"e_3\", \"accounts\": [{\"id\": \"a_1\", \"name\": \"ada\", \"currency\": \"USD\", \"opening\": 0, \"entries\": [{\"id\": \"e_1\", \"kind\": \"transfer\", \"amount\": -1000}], \"closing\": -1000}, {\"id\": \"a_2\", \"name\": \"grace\", \"currency\": \"USD\", \"opening\": 0, \"entries\": [{\"id\": \"e_1\", \"kind\": \"transfer\", \"amount\": 1000}], \"closing\": 1000}]}"
end

test rejects "a settlement of a day that does not exist"
  settled(busy(), "2026-02-30", "s", Time.fixture())
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
