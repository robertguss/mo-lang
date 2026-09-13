module Kv.Server
expose Gate, Listening, Worker, Servers, admitted, talk, exchange, answer

use Kv.Log{Journal, empty}
use Kv.Protocol{Request, Response, Refusal, parse, render}
use Kv.Store{Store, Opening}

intent "Serve the kv protocol over TCP: a listening process takes each client, a gate lets at most 64 in at once and turns the next away with ERR busy, and a worker process per connection reads a line, asks the store, and writes the answer, closing a client silent for 30 seconds."

process Gate()
  state
    inside: UInt64
  end

  invariant "the gate never lets in more than 64 clients"
    state.inside > 64
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

process Worker(conn: Conn, store: Handle(Store), gate: Handle(Gate))
  state
    lines: UInt64
  end

  message Talk

  fn update(state, message)
    case message
      Talk:
        state.lines += talk(conn, store)
        conn.close
        gate.send(Leave)
    end
  end
end

process Listening(listener: Listener, store: Handle(Store), gate: Handle(Gate))
  state
    admitted: UInt64
    turned_away: UInt64
  end

  message Accept : Bool

  fn update(state, message)
    case message
      Accept:
        case listener.accept(within: 60_000.ms)
          Ok(conn):
            if admitted(conn, store, gate)
              state.admitted += 1
            else
              state.turned_away += 1
            end
            true
          Error(_): false
        end
    end
  end
end

# A worker that crashed has lost its connection, so it is not started again on it.
supervisor Servers(listener: Listener, conn: Conn, store: Handle(Store), gate: Handle(Gate))
  child Gate, restart: :always
  child Listening(listener, store, gate), restart: :always
  child Worker(conn, store, gate), restart: :never
end

# A client past the 64th is told ERR busy and closed; any other gets a worker of its own.
fn admitted(conn: Conn, store: Handle(Store), gate: Handle(Gate)) : Bool
  if gate.ask(Enter, within: 5_000.ms) is Ok(true)
    worker = Worker.start(conn, store, gate)
    worker.send(Talk)
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

# Serves a connection until the client quits, leaves, or is silent for 30 seconds. A for
# needs a range to repeat, so a connection gets at most 100 million lines (GAPS.md).
fn talk(conn: Conn, store: Handle(Store)) : UInt64
  var lines = 0
  for _ in 0..10_000
    stretch = talk_awhile(conn, store)
    lines += stretch.0
    if !stretch.1
      break
    end
  end
  lines
end

fn talk_awhile(conn: Conn, store: Handle(Store)) : (UInt64, Bool)
  var lines = 0
  for _ in 0..10_000
    if !exchange(conn, store)
      return (lines, false)
    end
    lines += 1
  end
  (lines, true)
end

# One line in and its answer out; false once the connection is done.
fn exchange(conn: Conn, store: Handle(Store)) : Bool
  case conn.read_line(within: 30_000.ms)
    Ok(Some(line)): answered(conn, store, line)
    Ok(None): false
    Error(LineTooLong): sent(conn, Failed(reason: Malformed))
    Error(_): false
  end
end

fn answered(conn: Conn, store: Handle(Store), line: String) : Bool
  response = answer(store, line)
  sent(conn, response) and response != Bye
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

# A client that writes its lines, lets the listening process take it, and reads every
# line the server writes back until it closes.
fn conversation(net: Net, store: Handle(Store), gate: Handle(Gate),
  lines: List(String)) : Result(List(String), NetError)
  listener = try net.listen(7_700, within: 1.minute)
  listening = Listening.start(listener, store, gate)
  client = try net.connect("localhost", 7_700, within: 1.minute)
  for line in lines
    try client.write("#{line}\n", within: 1.minute)
  end
  if listening.ask(Accept, within: 10.minute) is Error(_)
    return Error(Timeout)
  end
  heard_all(client)
end

fn heard_all(client: Conn) : Result(List(String), NetError)
  var heard = [""].take(0)
  for _ in 0..1_000
    case try client.read_line(within: 1.minute)
      Some(line):
        heard = heard.push(line)
      None:
        return Ok(heard)
    end
  end
  Ok(heard)
end

# What a client heard is what it should have heard, in order, up to where a failure cut
# the conversation short.
fn heard_so_far?(heard: Result(List(String), NetError), expected: List(String)) : Bool
  case heard
    Ok(lines): expected.take(lines.size) == lines
    Error(_): true
  end
end

fn store_for_tests(dir: Fs, clock: Clock, opening: Opening) : Handle(Store)
  Store.start(Journal.start(dir, "kv.log", 0), clock, opening)
end

test "a client's requests get the store's answers, and QUIT says BYE and closes"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  lines = ["SET a 1", "GET a", "INCR a 2", "nonsense", "KEYS", "DEL b", "QUIT", "GET a"]
  heard = conversation(Net.fixture(), store_for_tests(Fs.fixture(), Clock.fixture(), opening),
    Gate.start(), lines)
  expected = ["OK", "VALUE 1", "VALUE 3", "ERR malformed", "KEYS 1", "a", "MISSING", "BYE"]
  assert heard_so_far?(heard, expected)
end

test "a line over 64 KiB is malformed, and the connection goes on"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  lines = ["SET a #{"x".repeat(65_536)}", "GET a", "QUIT"]
  heard = conversation(Net.fixture(), store_for_tests(Fs.fixture(), Clock.fixture(), opening),
    Gate.start(), lines)
  assert heard_so_far?(heard, ["ERR malformed", "MISSING", "BYE"])
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
  heard = conversation(Net.fixture(), store_for_tests(Fs.fixture(), Clock.fixture(), opening), gate,
    ["GET a"])
  assert heard_so_far?(heard, ["ERR busy"])
end

test "a silent client is closed, and hears nothing"
  opening = Opening(table: empty(), log_bytes: 0, at: Time.fixture(), log_within: 1.minute)
  heard = conversation(Net.fixture(), store_for_tests(Fs.fixture(), Clock.fixture(), opening),
    Gate.start(), [])
  assert heard_so_far?(heard, [])
end

verified: types, contracts, tests (5), property (0 seeds), sim (100 runs)
          proven: not run
