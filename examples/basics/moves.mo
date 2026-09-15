module Basics.Moves
expose Book, Shelf, Shelves, empty, with, without, written, listed, captured, guarded, removed, tallied

intent "A value handed on by its last read is written in place by whatever takes it (step 28), and no other holder ever sees the write: a copy read before, a list's element, a capture, a message, or the next arm of a case."

struct Book
  entries: Map(String, UInt64)
  count: UInt64
end

fn empty() : Book
  Book(entries: Map.new(), count: 0)
end

fn with(book: Book, key: String, n: UInt64) : Book
  var next = book
  next.entries = next.entries.set(key, n)
  next.count += 1
  next
end

fn without(book: Book, key: String) : Book
  var next = book
  next.entries = next.entries.remove(key)
  next
end

fn written() : (UInt64, UInt64, UInt64)
  book = with(with(empty(), "a", 1), "b", 2)
  before = book
  after = with(book, "a", 10)
  (before.entries.get("a") or 0, after.entries.get("a") or 0, after.count)
end

fn listed() : (UInt64, UInt64)
  books = [with(empty(), "a", 1)]
  later = with(books.first or empty(), "a", 5)
  ((books.first or empty()).entries.get("a") or 0, later.entries.get("a") or 0)
end

fn captured(keys: List(String)) : (UInt64, List(UInt64))
  book = with(empty(), "a", 1)
  sizes = keys.map(fn(key) with(book, key, 7).entries.size end)
  (book.entries.size, sizes)
end

fn guarded(book: Book) : UInt64
  case book
    b if with(b, "x", 1).count > 100: 0
    b: b.entries.size
  end
end

fn removed() : (UInt64, UInt64, List(String), Bool)
  full = (0..20).reduce(empty(), fn(b, i) with(b, "k#{i}", i) end)
  early = full
  book = (0..10).reduce(full, fn(b, i) without(b, "k#{i}") end)
  found = book.entries.get("k15") == Some(15) and book.entries.get("k3") == None and early.entries.has?("k3")
  (early.entries.size, book.entries.size, book.entries.keys.take(2), found)
end

fn tallied(keys: List(String)) : (UInt64, List(String))
  pair = keys.reduce((empty(), [""].take(0)),
    fn(acc, key) (with(acc.0, key, key.size), acc.1.push(key)) end)
  (pair.0.count, pair.1)
end

process Shelf()
  state
    book: Book = Book(entries: Map.new(), count: 0)
  end

  message Put(book: Book)
  message Count : UInt64

  fn update(state, message)
    case message
      Put(book):
        state.book = with(book, "shelved", 1)
      Count: state.book.count
    end
  end
end

supervisor Shelves
  child Shelf, restart: :always
end

test "a copy read before a write in place, and a list's element, keep their own values"
  assert written() == (1, 10, 3)
  assert listed() == (1, 5)
end

test "a capture, and the next arm of a case, see the value whole"
  assert captured(["b", "c"]) == (1, [2, 2])
  assert guarded(with(empty(), "a", 1)) == 1
end

test "a remove in place keeps the order and every lookup, and never reaches a copy"
  assert removed() == (20, 10, ["k10", "k11"], true)
  assert tallied(["ab", "c"]) == (2, ["ab", "c"])
end

test "a message is the process's own"
  book = with(empty(), "a", 1)
  shelf = Shelf.start()
  shelf.send(Put(book: book))
  assert shelf.ask(Count, within: 100.ms) is Ok(2)
  assert book.count == 1 and book.entries.size == 1
end

verified: types, contracts, tests (4), property (0 seeds), sim (100 runs)
          proven: not run
