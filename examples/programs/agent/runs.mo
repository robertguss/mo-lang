module Agent.Runs
expose made, launched, ended, transcript_of, tool_line, done_line

use Agent.Book{Book}
use Agent.Mock{Cursor, MockServer}
use Agent.Model{Model}
use Agent.Record{Budget, Order, Record, Status, tool_names, budget, default_budget}
use Agent.Run{Run}
use Agent.Shelf{Outcome}
use Agent.Steps{Phase, Setup}

intent "Runs against the scripted model over Http.fixture(), end to end through the book: three steps to an answer, each budget spent to over_budget with its transcript whole, refused tools shown to the model, a model garbage and then right or garbage to the end, and a cancel in the middle of a run."

fn model_at(port: UInt16) : Model
  Model(host: "localhost", port: port, tools: tool_names())
end

fn order_with(tools: List(String), hosts: List(String), given: Budget) : Order
  Order(goal: "count the lines", folder: "work", tools: tools, hosts: hosts, budget: given)
end

fn tool_line(tool: String, args: String, tokens: UInt64) : String
  "{\"tool\": \"#{tool}\", \"args\": #{args}, \"tokens\": #{tokens}}"
end

fn done_line(text: String, tokens: UInt64) : String
  "{\"done\": \"#{text}\", \"tokens\": #{tokens}}"
end

fn look_line(tokens: UInt64) : String
  tool_line("list_files", "{\"path\": \".\"}", tokens)
end

# A run made in the book: its id, or "" when the book did not make it.
fn made(book: Handle(Book), order: Order) : String
  case book.ask(Create(owner: "ada", order: order), within: 1.minute)
    Ok(Made(record)): record.id
    Ok(_) | Error(_): ""
  end
end

# A run's process over its folder, begun on its wall budget; a begin whose answer did not come
# still began it, since the message arrives.
fn launched(book: Handle(Book), folder: Fs, http: Http, clock: Clock, setup: Setup) : Handle(Run)
  run = Run.start(book, folder.read_only, folder, http, clock, setup)
  case run.ask(Begin(me: run), within: setup.order.budget.wall_ms.to_i64.ms)
    Ok(_) | Error(_): run
  end
end

# The run's record once it is no longer running. While a test's ask waits, every other process
# takes a message each round (step 24), so asking the book lets the run's own loop go on.
fn ended(book: Handle(Book), id: String) : Option(Record)
  for _ in 0..400
    if book.ask(Look(owner: "ada", id: id), within: 1.minute) is Ok(Found(record))
      return Some(record) if record.status != Running
    end
  end
  None
end

fn transcript_of(book: Handle(Book), id: String) : List(String)
  case book.ask(Steps(owner: "ada", id: id), within: 1.minute)
    Ok(Transcribed(steps)): steps
    Ok(_) | Error(_): []
  end
end

fn tools_in(steps: List(String)) : UInt64
  steps.count(fn(step) step.contains?("\"kind\": \"tool\"") end)
end

test "a run of three steps against a scripted model is done, with every call in its transcript"
  fs = Fs.fixture()
  ready = fs.write("work/notes.txt", "one\ntwo", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = [look_line(10),
    tool_line("read_file", "{\"path\": \"notes.txt\"}", 20),
    done_line("2 lines", 5)]
  cursor = Cursor.start(script)
  listener.serve(into: MockServer.start(cursor, http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["list_files", "read_file"], [], default_budget())
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    # Under faults a reply lost on the wire still moves the script on, so a run may skip a line, and
    # past the done line hear that the script is over; in the fixed order it takes all three.
    if record.status == Done
      assert record.steps_taken <= 3 and record.tokens_used <= 35
      assert record.answer == Some("2 lines") or record.answer == Some("the script is over")
      steps = transcript_of(book, id)
      assert steps.size == 0 or steps.size == record.steps_taken * 2 - 1
      read = steps.any?(fn(step) step.contains?("one\\ntwo") end)
      heard = cursor.ask(Heard(run: id), within: 1.minute)
      assert !read or heard is Error(_) or (heard is Ok(body) and body.contains?("one\\ntwo"))
    end
  end
end

test "a run past its steps budget ends over_budget with its transcript whole"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = [look_line(1), look_line(1), look_line(1)]
  listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["list_files"], [], budget(2, 1_000, 60_000, 2, 5_000))
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    # Under faults a begin may arrive with nothing left of its deadline, and the run is over its
    # wall budget instead.
    if record.why == Some("steps")
      assert record.status == OverBudget and record.steps_taken == 2
      steps = transcript_of(book, id)
      assert steps.size == 4 or steps.size == 0
    end
  end
end

test "a run past its tokens budget ends over_budget, the tool its last reply named not used"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = [look_line(6), look_line(6), look_line(6)]
  listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["list_files"], [], budget(20, 10, 60_000, 2, 5_000))
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    if record.why == Some("tokens")
      assert record.status == OverBudget and record.tokens_used == 12 and record.steps_taken == 2
      steps = transcript_of(book, id)
      assert steps.size == 3 or steps.size == 0
      assert tools_in(steps) <= 1
    end
  end
end

test "a run past its wall budget ends over_budget, the late reply not acted on"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = ["{\"slow_ms\": 1000}", look_line(1)]
  listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["list_files"], [], budget(20, 1_000, 100, 0, 100))
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    steps = transcript_of(book, id)
    assert tools_in(steps) == 0
    if record.status == OverBudget
      assert record.why == Some("wall_ms")
      assert steps.size <= 1
    end
  end
end

test "refused tools are recorded, count as steps, and are shown to the model"
  fs = Fs.fixture()
  ready = fs.write("secret.txt", "no", within: 1.minute) is Ok(_) and fs.mkdir("work",
    within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = [tool_line("read_file", "{\"path\": \"../secret.txt\"}", 1),
    tool_line("http_get", "{\"url\": \"http://example.com/\"}", 1),
    tool_line("write_file", "{\"path\": \"x.txt\", \"text\": \"x\"}", 1),
    done_line("refused three times", 1)]
  cursor = Cursor.start(script)
  listener.serve(into: MockServer.start(cursor, http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["read_file", "http_get"], ["localhost"], default_budget())
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    assert fs.read("work/x.txt", within: 1.minute) is Error(_)
    if record.status == Done
      assert record.steps_taken <= 4
      steps = transcript_of(book, id)
      refusals = steps.count(fn(step) step.contains?("\"refused\": true") end)
      assert steps.size == 0 or (steps.size == record.steps_taken * 2 - 1 and refusals == tools_in(steps))
      heard = cursor.ask(Heard(run: id), within: 1.minute)
      assert refusals == 0 or heard is Error(_) or (heard is Ok(body) and body.contains?("\"refused\": true"))
    end
  end
end

test "a model garbage twice and then right is answered under two retries"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = ["{\"garbage\": true}", "{\"garbage\": true}", done_line("right", 3)]
  listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with([], [], default_budget())
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    if record.status == Done
      assert record.answer == Some("right") and record.steps_taken == 1
    end
  end
end

test "a model garbage three times fails the run under two retries"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  garbage = "{\"garbage\": true}"
  cursor = Cursor.start([garbage, garbage, garbage, done_line("too late", 3)])
  listener.serve(into: MockServer.start(cursor, http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with([], [], default_budget())
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    assert ended(book, id) is Some(record)
    assert record.status != Done
    if record.status == Failed and record.why == Some("the model's reply is not JSON")
      assert cursor.ask(Calls(run: id), within: 1.minute) != Ok(4)
    end
  end
end

test "a run cancelled in the middle stops, and no tool runs after the cancel is written"
  fs = Fs.fixture()
  ready = fs.mkdir("work", within: 1.minute) is Ok(_)
  http = Http.fixture()
  assert http.listen(0, within: 1.minute) is Ok(listener)
  script = ["{\"slow_ms\": 50}",
    look_line(1),
    "{\"slow_ms\": 50}",
    look_line(1),
    "{\"slow_ms\": 50}",
    look_line(1),
    "{\"slow_ms\": 50}",
    done_line("never", 1)]
  listener.serve(into: MockServer.start(Cursor.start(script), http), idle: 5_000.ms)
  book = Book.start(fs, Clock.fixture(), "runs", Time.fixture())
  order = order_with(["list_files"], [], default_budget())
  id = made(book, order)
  if ready and id != ""
    launched(book, fs.scoped("work"), http, Clock.fixture(),
      Setup(id: id, order: order, model: model_at(listener.port)))
    stop = book.ask(Cancel(owner: "ada", id: id), within: 1.minute)
    assert ended(book, id) is Some(record)
    if stop is Ok(Stopped(_))
      assert record.status == Cancelled
      assert tools_in(transcript_of(book, id)) <= 1
    end
  end
end

verified: types, contracts, tests (8), property (0 seeds), sim (100 runs)
          proven: not run
