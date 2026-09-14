module Notes.Note
expose Note, Command, Call, Outcome, Counts, note, note_of, key_of, owner_of, id_of, counted, id_number, title?, body?

use Notes.Limits{ClientId, token?}

intent "What notes is about: a note and the JSON the store keeps it as, what a client asks of the service once its request is read, what comes of it, and the rules a title, a body, a token, and an id keep."

struct Note
  id: String
  title: String
  body: String
  created_at: Time
  updated_at: Time
end

# What a client asked for, once the route and the JSON are read. Refuse is a request the Api
# found malformed: it still takes a token before it is answered 400.
enum Command
  Create(title: String, body: String)
  Fetch(id: String)
  Listing(prefix: String)
  Update(id: String, title: String, body: String)
  Remove(id: String)
  Refuse(reason: String)
end

struct Call
  owner: ClientId
  command: Command
end

enum Outcome
  Made(note: Note)
  Found(note: Note)
  Listed(notes: List(Note))
  Removed
  Missing
  Refused(reason: String)
  Limited(retry_after_ms: Int64)
  Unavailable(reason: String)
end

struct Counts
  notes: UInt64
  clients: UInt64
  uptime_ms: Int64
end

# A new note, stamped now.
fn note(id: UInt64, title: String, body: String, now: Time) : Note
  requires title?(title)
  requires body?(body)

  Note(id: "n_#{id}", title: title, body: body, created_at: now, updated_at: now)
end

# A note as the store keeps it, read back.
fn note_of(text: String) : Option(Note)
  case Json.decode(text)
    Ok(Object(fields)):
      id = try text_in(fields, "id")
      title = try text_in(fields, "title")
      body = try text_in(fields, "body")
      created = try Time.parse(try text_in(fields, "created_at"))
      updated = try Time.parse(try text_in(fields, "updated_at"))
      Some(Note(id: id, title: title, body: body, created_at: created, updated_at: updated))
    Ok(_): None
    Error(_): None
  end
end

fn text_in(fields: Map(String, Json), name: String) : Option(String)
  case fields.get(name)
    Some(String(text)): Some(text)
    Some(_): None
    None: None
  end
end

# The store key of a client's note: its token, a slash, and the id. No token holds a slash,
# so no client's keys are under another's.
fn key_of(owner: ClientId, id: String) : String
  requires token?(owner)

  "#{owner}/#{id}"
end

# The number in an id: n_ and digits.
fn id_number(id: String) : Option(UInt64)
  return None if !id.starts_with?("n_")
  id.slice(2, id.size).to_u64
end

# A title is 1 to 200 bytes with no control character.
fn title?(text: String) : Bool
  size = text.byte_size
  size >= 1 and size <= 200 and plain?(text, false)
end

# A body is at most 60 KiB with no control character but a newline.
fn body?(text: String) : Bool
  text.byte_size <= 61_440 and plain?(text, true)
end

# No C0 control character (a newline allowed when newlines is true), no DEL, and no C1
# control character (U+0080 to U+009F).
fn plain?(text: String, newlines: Bool) : Bool
  ascii = text.bytes.all?(fn(b) (b >= 32 and b != 127) or (newlines and b == 10) end)
  return ascii if !ascii or text.size == text.byte_size
  !text.chars.any?(fn(c) c1?(c) end)
end

# A C1 control character is two bytes in UTF-8: C2, then 80 to 9F.
fn c1?(c: String) : Bool
  second = c.bytes.get(1) or 0
  c.bytes.first == Some(194) and second >= 128 and second <= 159
end

# The client a store key belongs to, and the note id in it: a key is the client, a slash, and
# the id.
fn owner_of(key: String) : String
  key.slice(0, key.index_of("/") or 0)
end

fn id_of(key: String) : String
  key.slice((key.index_of("/") or 0) + 1, key.size)
end

fn counted(counts: Map(String, UInt64), owner: String) : Map(String, UInt64)
  counts.update(owner, 0, fn(n) n + 1 end)
end

test "a title is 1 to 200 bytes and a body up to 60 KiB, with no control character but a newline in the body"
  assert title?("t")
  assert title?("é".repeat(100))
  assert !title?("é".repeat(101))
  assert !title?("")
  assert !title?("a\nb")
  assert !title?("tab\there")
  assert !title?(String.from_bytes([97, 194, 133]) or "\n")
  assert body?("")
  assert body?("line one\nline two")
  assert body?("x".repeat(61_440))
  assert !body?("x".repeat(61_441))
  assert !body?("a\rb")
  assert !body?(String.from_bytes([127]) or "\r")
end

test "a note keeps its shape through the store's JSON"
  made = note(7, "groceries", "eggs\nmilk \"fresh\"", Time.fixture())
  assert Json.encode(made) == "{\"id\": \"n_7\", \"title\": \"groceries\", \"body\": \"eggs\\nmilk \\\"fresh\\\"\", \"created_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:00:00Z\"}"
  assert note_of(Json.encode(made)) == Some(made)
  assert note_of("{\"id\": \"n_1\"}") is None
  assert note_of("{\"id\": 1, \"title\": \"t\", \"body\": \"\", \"created_at\": \"x\", \"updated_at\": \"x\"}") is None
  assert note_of("[1]") is None
  assert note_of("not json") is None
end

test "an id is n_ and a number, and a key is the token, a slash, and the id"
  assert id_number("n_42") == Some(42)
  assert id_number("n_") is None
  assert id_number("42") is None
  assert id_number("n_4x") is None
  assert key_of("ada", "n_1") == "ada/n_1"
end

test rejects "a key for a token with a slash in it"
  key_of("ada/grace", "n_1")
end

test rejects "a note with an empty title"
  note(1, "", "body", Time.fixture())
end

test rejects "a note with a body over 60 KiB"
  note(1, "title", "x".repeat(61_441), Time.fixture())
end

property "any valid title and body survive the store's JSON"
  for title in any(String), body in any(String) if title?(title) and body?(body)
    made = note(1, title, body, Time.fixture())
    assert note_of(Json.encode(made)) == Some(made)
  end
end

verified: types, contracts, tests (7), property (200 seeds), sim (not run)
          proven: not run
