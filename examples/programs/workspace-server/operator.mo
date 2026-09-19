module WorkspaceServer.Operator
expose Desk, Door, OperatorDoor, OperatorLine, OperatorToken, Operators, command_of

use WorkspaceServer.Admission{Admission, Standing}
use WorkspaceServer.Connection{Gate}
use WorkspaceServer.Journal{Journal}
use WorkspaceServer.Worker{Worker}

intent "The operator's path, apart from every candidate connection: its own loopback listener, its own token, its own processes. One line in, one JSON line out: status, freeze, verify, or close. Freeze and close close admission first, then wait a bounded time for the call in flight; close journals cleanup, confirmed only when nothing is in flight, and then lets main end the program. A candidate that disconnects, stalls or floods cannot close or starve this path."

never "the operator token reaches a connection"
  flows(OperatorToken, into: Conn)
end

never "the operator token reaches the journal"
  flows(OperatorToken, into: Handle(Journal))
end

type OperatorToken = String where value.byte_size == 64

# The token offered and the command named on one operator line.
fn command_of(line: String) : (String, String)
  space = line.index_of(" ") or line.size
  (line.slice(0, space), line.slice(space + 1, line.size))
end

# What main waits on: the operator's close, or the end of the lease and its grace.
process Door()
  state
    waiting: List(Reply(Bool))
    knocked: Bool
  end

  message Wait : Bool
  message Knock

  fn update(state, message)
    case message
      Wait:
        state.waiting = state.waiting.push(reply_to)
        if state.knocked
          for w in state.waiting
            w.answer(true)
          end
          state.waiting = []
        end
      Knock:
        state.knocked = true
        for w in state.waiting
          w.answer(true)
        end
        state.waiting = []
    end
  end
end

process Desk(token: OperatorToken, admission: Handle(Admission), journal: Handle(Journal),
  worker: Handle(Worker), gate: Handle(Gate), door: Handle(Door))
  state
    closed: Bool
    last: String
  end

  message Command(offered: String, name: String) : String
  message Expire

  fn update(state, message)
    case message
      Command(offered: offered, name: name):
        if !Hash.equal?(Hash.sha256(offered.bytes), Hash.sha256(token.bytes))
          "{\"error\": \"unauthorized\"}"
        else
          case name
            "status": status(admission, gate)
            "freeze": frozen(admission, journal, worker)
            "verify": "{\"verified\": null, \"why\": \"the protected verifier is part B's\"}"
            "close":
              state.closed = true
              state.last = closed(admission, journal, door)
              state.last
            _: "{\"error\": \"unknown_command\"}"
          end
        end
      Expire:
        if !state.closed
          state.closed = true
          state.last = closed(admission, journal, door)
        end
    end
  end
end

fn status(admission: Handle(Admission), gate: Handle(Gate)) : String
  inside = case gate.ask(Count, within: 1_000.ms)
    Ok(n): "#{n}"
    Error(_): "null"
  end
  case admission.ask(Status, within: 1_000.ms)
    Ok(s):
      "{\"admission\": \"#{if s.open: "open" else: "closed"}\", \"active\": #{s.active}, \"calls\": #{s.calls}, \"why\": #{Json.encode(s.why)}, \"connections\": #{inside}}"
    Error(_): "{\"admission\": \"unknown\", \"connections\": #{inside}}"
  end
end

# Admission closes first; the call in flight, if any, has five seconds to end.
fn drained(admission: Handle(Admission), why: String) : Bool
  admission.send(Close(why: why))
  admission.ask(Drained, within: 5_000.ms) == Ok(true)
end

fn frozen(admission: Handle(Admission), journal: Handle(Journal), worker: Handle(Worker)) : String
  still = drained(admission, "operator_freeze")
  digest = case worker.ask(Digest, within: 30_000.ms)
    Ok(d): d
    Error(_): "unknown"
  end
  record = "{\"drained\": #{still}, \"sha256\": \"#{digest}\"}"
  noted = journal.ask(Froze(frozen: record), within: 5_000.ms) == Ok(true)
  "{\"frozen\": true, \"drained\": #{still}, \"snapshot\": \"#{digest}\", \"journaled\": #{noted}}"
end

# Cleanup is confirmed when admission is closed and no call is in flight; the workspace folder
# is the operator's and stays. Main is let go either way.
fn closed(admission: Handle(Admission), journal: Handle(Journal), door: Handle(Door)) : String
  still = drained(admission, "operator_close")
  verdict = if still: "confirmed" else: "unresolved"
  record = "{\"cleanup\": \"#{verdict}\", \"execution\": \"unknown\", \"method\": \"admission closed, no call in flight\"}"
  noted = journal.ask(Cleaned(cleanup: record), within: 5_000.ms) == Ok(true)
  door.send(Knock)
  "{\"closed\": true, \"cleanup\": \"#{verdict}\", \"journaled\": #{noted}}"
end

# One operator connection: one line, one answer, then closed.
process OperatorLine(conn: Conn, desk: Handle(Desk))
  state
    answered: Bool
  end

  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle

  fn update(state, message)
    case message
      Line(text):
        if !state.answered
          state.answered = true
          asked = command_of(text)
          answer = case desk.ask(Command(offered: asked.0, name: asked.1), within: 70_000.ms)
            Ok(a): a
            Error(_): "{\"error\": \"desk\"}"
          end
          if conn.write("#{answer}\n", within: 2_000.ms) is Error(_)
            state.answered = true
          end
          conn.close
        end
      LineTooLong | Closed | Idle:
        conn.close
    end
  end
end

process OperatorDoor(desk: Handle(Desk))
  state
    served: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        conn.lines(into: OperatorLine.start(conn, desk), idle: 10_000.ms)
        state.served += 1
      Idle:
        state.served += 0
    end
  end
end

supervisor Operators(token: OperatorToken, admission: Handle(Admission), journal: Handle(Journal),
  worker: Handle(Worker), gate: Handle(Gate), door: Handle(Door))
  child Door, restart: :never
  child Desk(token, admission, journal, worker, gate, door), restart: :always
end

supervisor OperatorLines(conn: Conn, desk: Handle(Desk))
  child OperatorDoor(desk), restart: :always
  child OperatorLine(conn, desk), restart: :never
end

test "an operator line is its token, a space, and its command"
  assert command_of("abc status") == ("abc", "status")
  assert command_of("abc") == ("abc", "")
end

test "the door lets main go once, whenever it is asked"
  door = Door.start()
  door.send(Knock)
  assert door.ask(Wait, within: 1.minute) == Ok(true)
end
