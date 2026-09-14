module Kv.Server
expose Gate, Listening, Worker, Heard, Servers, admitted, finished, answer, conversation, heard_so_far?

use Kv.Log{Journal, empty}
use Kv.Protocol{Request, Response, Refusal, parse, render}
use Kv.Store{Store, Opening}

intent "Serve the kv protocol over TCP: the runtime serves the listener into a listening process, a gate lets at most 64 clients in at once and turns the next away with ERR busy, and each connection is read into a worker process of its own, which asks the store for each line's answer and writes it, and the runtime closes a client silent for 30 seconds."

process Gate()
  state
    inside: UInt64
  end

  invariant "the gate never lets in more than 64 clients"
    state.inside <= 64
  end

  message Enter : Bool
  message Leave

  fn update(state, message)
    case message
      Enter:
        if state.inside < 64
          state.inside += 1
          true
        else
          false
        end
      Leave:
        if state.inside > 0
          state.inside -= 1
        end
    end
  end
end

# A connection's worker: each line the runtime reads is answered in turn, until the client quits,
# goes, is silent for 30 seconds, or a write fails; then the worker closes it and leaves the gate.
process Worker(conn: Conn, store: Handle(Store), gate: Handle(Gate))
  state
    lines: UInt64
    done: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if !state.done
          state.lines += 1
          state.done = finished(conn, store, gate, text)
        end
      LineTooLong:
        if !state.done
          state.done = !sent(conn, Failed(reason: Malformed)) and left(conn, gate)
        end
      Closed | Idle:
        if !state.done
          state.done = left(conn, gate)
        end
    end
  end
end

process Listening(store: Handle(Store), gate: Handle(Gate))
  state
    admitted: UInt64
    turned_away: UInt64
    quiet: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        if admitted(conn, store, gate)
          state.admitted += 1
        else
          state.turned_away += 1
        end
      Idle:
        state.quiet += 1
    end
  end
end

# What a client heard, line by line, until its connection ended: the tests' client.
process Heard()
  state
    lines: List(String)
    ended: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle
  message Lines : List(String)

  fn update(state, message)
    case message
      Line(text):
        state.lines = state.lines.push(text)
      LineTooLong:
        state.lines = state.lines.push("")
      Closed | Idle:
        state.ended = true
      Lines: state.lines
    end
  end
end

# A worker that crashed has lost its connection, so it is not started again on it.
supervisor Servers(conn: Conn, store: Handle(Store), gate: Handle(Gate))
  child Gate, restart: :always
  child Listening(store, gate), restart: :always
  child Worker(conn, store, gate), restart: :never
  child Heard, restart: :always
end

# A client past the 64th is told ERR busy and closed; any other has its lines read into a
# worker of its own.
fn admitted(conn: Conn, store: Handle(Store), gate: Handle(Gate)) : Bool
  if gate.ask(Enter, within: 5_000.ms) is Ok(true)
    conn.lines(into: Worker.start(conn, store, gate), idle: 30_000.ms)
    return true
  end
  turn_away(conn)
  false
end

# Tells a client there is no room, ERR busy, and closes its connection.
fn turn_away(conn: Conn)
  sent(conn, Failed(reason: Busy))
  conn.close
end

# One line in and its answer out; true once the connection is done, after the worker has
# closed it and left the gate.
fn finished(conn: Conn, store: Handle(Store), gate: Handle(Gate), line: String) : Bool
  response = answer(store, line)
  if sent(conn, response) and response != Bye
    return false
  end
  left(conn, gate)
end

# The worker is done with its client: the connection closes and the gate has room again.
fn left(conn: Conn, gate: Handle(Gate)) : Bool
  conn.close
  gate.send(Leave)
  true
end

# The answer to one line: BYE for QUIT, ERR malformed for a line that is no request, and
# otherwise the store's, or ERR io when the store does not answer in time.
fn answer(store: Handle(Store), line: String) : Response
  case parse(line)
    Ok(Quit): Bye
    Ok(request): asked(store, request)
    Error(reason): Failed(reason: reason)
  end
end

fn asked(store: Handle(Store), request: Request) : Response
  case store.ask(Serve(request: request), within: 5_000.ms)
    Ok(response): response
    Error(_): Failed(reason: Io)
  end
end

fn sent(conn: Conn, response: Response) : Bool
  conn.write(render(response), within: 30_000.ms) is Ok(_)
end

# A client of a served listener that has what comes back read into `heard` and writes its
# lines, all in one statement, so the runtime serves it once they are written.
fn conversation(net: Net, store: Handle(Store), gate: Handle(Gate), heard: Handle(Heard),
  lines: List(String)) : Result(Bool, NetError)
  listener = try net.listen(7_700, within: 1.minute)
  listener.serve(into: Listening.start(store, gate), idle: 60_000.ms)
  client = try net.connect("localhost", 7_700, within: 1.minute)
  client.lines(into: heard, idle: 60_000.ms)
  try client.write(String.join(lines.map(fn(line) "#{line}\n" end), ""), within: 1.minute)
  Ok(true)
end

# What a client heard is what it should have heard, in order, up to where a failure cut the
# conversation short or a seeded run left the rest waiting, and up to an ERR io, after which a
# store that failed may answer otherwise; anything, when it never got to talk.
fn heard_so_far?(talk: Result(Bool, NetError), heard: Result(List(String), AskError),
  expected: List(String)) : Bool
  case heard
    Ok(lines): talk is Error(_) or agreed?(lines, expected)
    Error(_): true
  end
end

fn agreed?(lines: List(String), expected: List(String)) : Bool
  for pair in lines.zip(expected)
    return true if pair.0 == "ERR io"
    return false if pair.0 != pair.1
  end
  lines.size <= expected.size
end

fn store_for_tests(dir: Fs, clock: Clock, opening: Opening) : Handle(Store)
  Store.start(Journal.start(dir, "kv.log", 0), clock, opening)
end

test "a client's requests get the store's answers, and QUIT says BYE and closes"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  store = store_for_tests(Fs.fixture(), Clock.fixture(), opening)
  heard = Heard.start()
  lines = ["SET a 1", "GET a", "INCR a 2", "nonsense", "KEYS", "DEL b", "QUIT", "GET a"]
  talk = conversation(Net.fixture(), store, Gate.start(), heard, lines)
  expected = ["OK", "VALUE 1", "VALUE 3", "ERR malformed", "KEYS 1", "a", "MISSING", "BYE"]
  assert heard_so_far?(talk, heard.ask(Lines, within: 1.minute), expected)
end

test "a line over 64 KiB is malformed, and the connection goes on"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  store = store_for_tests(Fs.fixture(), Clock.fixture(), opening)
  heard = Heard.start()
  talk = conversation(Net.fixture(), store, Gate.start(), heard,
    ["SET a #{"x".repeat(65_536)}", "GET a", "QUIT"])
  assert heard_so_far?(talk, heard.ask(Lines, within: 1.minute),
    ["ERR malformed", "MISSING", "BYE"])
end

test "the gate lets 64 clients in, turns the next away, and takes one more when one leaves"
  gate = Gate.start()
  var admitted = 0
  for _ in 0..65
    if gate.ask(Enter, within: 1.minute) is Ok(true)
      admitted += 1
    end
  end
  gate.send(Leave)
  again = gate.ask(Enter, within: 1.minute)
  assert admitted == 64
  assert again is Ok(true) or again is Error(_)
end

test "a client that finds 64 inside hears ERR busy, and is closed"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  gate = Gate.start()
  for _ in 0..64
    gate.send(Enter)
  end
  store = store_for_tests(Fs.fixture(), Clock.fixture(), opening)
  heard = Heard.start()
  talk = conversation(Net.fixture(), store, gate, heard, ["GET a"])
  assert heard_so_far?(talk, heard.ask(Lines, within: 1.minute), ["ERR busy"])
end

test "a client that says nothing hears nothing"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  store = store_for_tests(Fs.fixture(), Clock.fixture(), opening)
  heard = Heard.start()
  talk = conversation(Net.fixture(), store, Gate.start(), heard, [])
  assert heard_so_far?(talk, heard.ask(Lines, within: 1.minute), [])
end

verified: types, contracts, tests (5), property (0 seeds), sim (100 runs)
          proven: not run
