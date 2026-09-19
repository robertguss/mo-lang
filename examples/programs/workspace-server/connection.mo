module WorkspaceServer.Connection
expose Connection, Runner, Acceptor, Gate, Token, Identity, Reading, Next, Candidates, Handlers, fresh, took, ended, with_length, status_of

use WorkspaceServer.Admission{Admission, Admitted}
use WorkspaceServer.Envelope{Envelope, Ids, refused, ids_of, text}
use WorkspaceServer.Journal{Journal}
use WorkspaceServer.Schema{Call, call}
use WorkspaceServer.Wire{Head, Refusal, head, head_fits?, response, malformed, too_large}
use WorkspaceServer.Worker{Worker}

intent "Serve candidate connections, one process each from accept to close, so no descriptor is shared or reused while another holds it: read the head and the body a line at a time, refuse what the contract refuses, have the gate compare the token, and hand a whole call to the connection's runner, which asks admission and waits for the worker while the connection goes on reading. A request not whole in two seconds is refused; a peer that ends its side once its body is sent is a legal half-close, not pipelining; a peer that ends during a call is recorded as delivery unknown, never as the owner's failure; a wait past its deadline is 504 with execution unknown."

never "the token reaches a candidate's connection"
  flows(Token, into: Conn)
end

never "the token reaches the journal"
  flows(Token, into: Handle(Journal))
end

never "the token reaches a file"
  flows(Token, into: Fs)
end

# The candidate token: 64 hex characters, held by the gate alone.
type Token = String where value.byte_size == 64

# What every connection knows of the run.
struct Identity
  run_id: String
  workspace_id: String
  port: UInt16
  commands: Bool
end

# The request so far: the head's lines, then, once the head is whole, the body's length and the
# body as its lines came, each with the newline that ended it.
struct Reading
  head: List(String)
  head_bytes: UInt64
  length: UInt64
  body: String
  body_bytes: UInt64
end

enum Next
  Wait
  HeadDone(lines: List(String))
  Whole(body: String)
  Refuse(refusal: Refusal)
end

fn fresh() : Reading
  Reading(head: [], head_bytes: 0, length: 0, body: "", body_bytes: 0)
end

fn with_length(r: Reading, length: UInt64) : Reading
  Reading(head: r.head, head_bytes: r.head_bytes, length: length, body: r.body, body_bytes: r.body_bytes)
end

# One more line. A body is whole when its bytes, newlines counted, reach its length; one byte
# more may be a body with no newline after it, which only the end of the stream settles.
fn took(r: Reading, line: String) : (Reading, Next)
  if r.length == 0
    return (r, HeadDone(lines: r.head)) if line == ""
    grown = Reading(head: r.head.push(line), head_bytes: r.head_bytes + line.byte_size + 2,
      length: 0, body: "", body_bytes: 0)
    return (grown, Refuse(refusal: too_large())) if !head_fits?(grown.head_bytes)
    return (grown, Wait)
  end
  bytes = r.body_bytes + line.byte_size + 1
  grown = Reading(head: r.head, head_bytes: r.head_bytes, length: r.length, body: "#{r.body}#{line}\n",
    body_bytes: bytes)
  return (grown, Whole(body: grown.body)) if bytes == r.length
  return (grown, Refuse(refusal: malformed())) if bytes > r.length + 1
  (grown, Wait)
end

# The stream ended. A body one byte past its length ended with no newline: it is whole.
fn ended(r: Reading) : Next
  if r.length > 0 and r.body_bytes == r.length + 1
    return Whole(body: r.body.slice(0, r.body.size - 1))
  end
  Refuse(refusal: malformed())
end

# The door: at most `limit` live candidate connections, and the one holder of the token, which
# it compares in constant time and never gives out.
process Gate(limit: UInt64, token: Token)
  state
    inside: UInt64
  end

  invariant "no more connections are inside than the limit"
    state.inside <= limit
  end

  message Enter : Bool
  message Leave
  message Count : UInt64
  message Check(offered: String) : Bool

  fn update(state, message)
    case message
      Enter:
        if state.inside < limit
          state.inside += 1
          true
        else
          false
        end
      Leave:
        state.inside = state.inside.saturating_sub(1)
      Count: state.inside
      Check(offered): Hash.equal?(Hash.sha256(offered.bytes), Hash.sha256(token.bytes))
    end
  end
end

# The status and envelope an admitted call's wait came to.
fn status_of(got: Result(Envelope, AskError), call: Call) : (UInt16, Envelope)
  ids = Some(ids_of(call))
  case got
    Ok(envelope): (200, envelope)
    Error(Timeout):
      (504, Envelope(ids: ids, accepted: true, state: "timeout", execution: "unknown",
        error: Some("response_timeout"), result: None))
    Error(Down):
      (200, Envelope(ids: ids, accepted: true, state: "failure", execution: "unknown",
        error: Some("owner_unknown"), result: None))
  end
end

# One connection's calls to admission, the worker and the journal. It asks admission, waits
# for the worker at most the call's wait, journals the reply produced before the connection
# writes it, and then the delivery the connection reports.
process Runner(admission: Handle(Admission), worker: Handle(Worker), journal: Handle(Journal))
  state
    call_id: String
  end

  message Go(back: Handle(Connection), call: Call, payload_sha256: String)
  message Delivery(written: Bool, peer_ended: Bool)

  fn update(state, message)
    case message
      Go(back: back, call: call, payload_sha256: sha):
        state.call_id = call.call_id
        case admission.ask(Admit(call_id: call.call_id, payload_sha256: sha, operation: call.operation), within: 1_000.ms)
          Ok(Yes(core_id: core_id, wait_ms: wait_ms)):
            got = status_of(worker.ask(Do(call: call, core_id: core_id), within: wait_ms.ms), call)
            closes(admission, got.1, got.0)
            reply = "{\"status\": #{got.0}, \"state\": \"#{got.1.state}\", \"execution\": \"#{got.1.execution}\", \"error\": #{Json.encode(got.1.error or "")}}"
            noted = journal.ask(Replied(call_id: call.call_id, reply: reply), within: 1_000.ms) == Ok(true)
            back.send(Reply(status: got.0, envelope: got.1, journaled: noted))
          Ok(No(error)): back.send(Refused(error: error))
          Error(_):
            admission.send(Close(why: "admission_unknown"))
            back.send(Refused(error: "admission_closed"))
        end
      Delivery(written: written, peer_ended: peer_ended):
        if !written
          admission.send(Close(why: "response_write_unknown"))
        end
        if peer_ended
          admission.send(Close(why: "observed_disconnect"))
        end
        delivery = "{\"known\": false, \"written\": #{written}, \"peer_ended_during_call\": #{peer_ended}}"
        noted = journal.ask(Delivered(call_id: state.call_id, delivery: delivery, unknown: !written or peer_ended), within: 1_000.ms)
        state.call_id = if noted == Ok(true): "" else: state.call_id
    end
  end
end

# A reply that is a wait expired, an owner lost, or an unknown execution closes admission.
fn closes(admission: Handle(Admission), envelope: Envelope, status: UInt16)
  if status == 504
    admission.send(Close(why: "response_timeout"))
  else
    if envelope.execution == "unknown"
      admission.send(Close(why: if envelope.error == Some("owner_unknown"): "owner_unknown" else: "unknown_execution"))
    end
  end
end

process Connection(conn: Conn, identity: Identity, gate: Handle(Gate), runner: Handle(Runner))
  state
    me: Option(Handle(Connection))
    reading: Reading = fresh()
    phase: String = "head"
    ids: Option(Ids)
    peer_ended: Bool
  end

  message Begin(me: Handle(Connection))
  message Line(text: String)
  message LineTooLong
  message Closed
  message Idle
  message Expire
  message Reply(status: UInt16, envelope: Envelope, journaled: Bool)
  message Refused(error: String)

  fn update(state, message)
    case message
      Begin(me):
        state.me = Some(me)
      Line(text):
        if reading?(state.phase)
          step = took(state.reading, text)
          state.reading = step.0
          phase = next_phase(conn, identity, gate, runner, state.me, step.1)
          state.phase = if phase == "same": state.phase else: phase
          if state.phase == "body" and state.reading.length == 0
            state.reading = with_length(state.reading, length_of(state.reading.head, identity.port))
          end
          state.ids = if state.phase == "running": ids_in(body_of(step.1), identity) else: state.ids
        end
      LineTooLong:
        if reading?(state.phase)
          state.phase = refuse(conn, gate, too_large())
        end
      Closed:
        if state.phase == "running"
          state.peer_ended = true
        end
        if reading?(state.phase)
          whole = ended(state.reading)
          state.phase = next_phase(conn, identity, gate, runner, state.me, whole)
          state.ids = if state.phase == "running": ids_in(body_of(whole), identity) else: state.ids
        end
      Idle:
        state.peer_ended = state.phase == "running"
      Expire:
        if reading?(state.phase)
          state.phase = refuse(conn, gate, malformed())
        end
      Reply(status: status, envelope: envelope, journaled: _):
        state.phase = answered(conn, gate, status, envelope)
        runner.send(Delivery(written: state.phase == "done", peer_ended: state.peer_ended))
      Refused(error):
        state.phase = answered(conn, gate, 409, refused(state.ids, error))
    end
  end
end

fn reading?(phase: String) : Bool
  phase == "head" or phase == "body"
end

fn body_of(next: Next) : String
  case next
    Whole(body): body
    Wait | HeadDone(_) | Refuse(_): ""
  end
end

fn ids_in(body: String, identity: Identity) : Option(Ids)
  case call(body, identity.run_id, identity.workspace_id)
    Ok(c): Some(ids_of(c))
    Error(_): None
  end
end

fn length_of(lines: List(String), port: UInt16) : UInt64
  case head(lines, port)
    Ok(h): h.length
    Error(_): 0
  end
end

# The phase a step leads to, with its effects: a refusal written, a head checked, or a whole
# request handed to the runner; "same" when the step waits for more.
fn next_phase(conn: Conn, identity: Identity, gate: Handle(Gate), runner: Handle(Runner),
  me: Option(Handle(Connection)), next: Next) : String
  case next
    Wait: "same"
    Refuse(refusal): refuse(conn, gate, refusal)
    HeadDone(lines): head_checked(conn, lines, identity.port, gate)
    Whole(body): dispatched(conn, identity, gate, runner, me, body)
  end
end

# A whole head: its own checks, then the token, before any byte of the body is read.
fn head_checked(conn: Conn, lines: List(String), port: UInt16, gate: Handle(Gate)) : String
  case head(lines, port)
    Ok(h):
      if gate.ask(Check(offered: h.offered), within: 1_000.ms) == Ok(true)
        return "body"
      end
      refuse(conn, gate, Refusal(status: 401, error: "unauthorized"))
    Error(refusal): refuse(conn, gate, refusal)
  end
end

fn dispatched(conn: Conn, identity: Identity, gate: Handle(Gate), runner: Handle(Runner),
  me: Option(Handle(Connection)), body: String) : String
  case call(body, identity.run_id, identity.workspace_id)
    Error(refusal): refuse(conn, gate, refusal)
    Ok(c):
      if c.operation == "command" and !identity.commands
        return answered(conn, gate, 409, refused(Some(ids_of(c)), "request_refused"))
      end
      case me
        Some(back):
          runner.send(Go(back: back, call: c, payload_sha256: Hash.hex(Hash.sha256(body.bytes))))
          "running"
        None: answered(conn, gate, 409, refused(Some(ids_of(c)), "admission_closed"))
      end
  end
end

# A refusal before admission: written, the connection closed, its gate slot given back.
fn refuse(conn: Conn, gate: Handle(Gate), refusal: Refusal) : String
  answered(conn, gate, refusal.status, refused(None, refusal.error))
end

fn answered(conn: Conn, gate: Handle(Gate), status: UInt16, envelope: Envelope) : String
  wrote = conn.write(response(status, text(envelope)), within: 2_000.ms) is Ok(_)
  conn.close
  gate.send(Leave)
  if wrote: "done" else: "unwritten"
end

# Accepts candidate connections: four at most live; each gets a connection process and a
# runner, the runtime reads its lines into it, and it is told when its two seconds end.
process Acceptor(identity: Identity, gate: Handle(Gate), admission: Handle(Admission),
  worker: Handle(Worker), journal: Handle(Journal))
  state
    accepted: UInt64
    turned_away: UInt64
  end

  message Accepted(conn: Conn)
  message Idle

  fn update(state, message)
    case message
      Accepted(conn):
        if gate.ask(Enter, within: 1_000.ms) == Ok(true)
          handler = Connection.start(conn, identity, gate, Runner.start(admission, worker, journal))
          handler.send(Begin(me: handler))
          conn.lines(into: handler, idle: 310_000.ms)
          handler.send(Expire, delay: 2_000.ms)
          state.accepted += 1
        else
          conn.close
          state.turned_away += 1
        end
      Idle:
        state.accepted += 0
    end
  end
end

supervisor Candidates(identity: Identity, token: Token, gate: Handle(Gate),
  admission: Handle(Admission), worker: Handle(Worker), journal: Handle(Journal))
  child Gate(4, token), restart: :never
  child Acceptor(identity, gate, admission, worker, journal), restart: :always
  child Runner(admission, worker, journal), restart: :never
end

supervisor Handlers(conn: Conn, identity: Identity, gate: Handle(Gate), runner: Handle(Runner))
  child Connection(conn, identity, gate, runner), restart: :never
end

test "a head, then a body with no newline after it, is whole only when the stream ends"
  s1 = took(fresh(), "POST /tool HTTP/1.1")
  assert s1.1 == Wait
  s2 = took(s1.0, "")
  assert s2.1 == HeadDone(lines: ["POST /tool HTTP/1.1"])
  s4 = took(with_length(s2.0, 5), "abcde")
  assert s4.1 == Wait
  assert ended(s4.0) == Whole(body: "abcde")
end

test "a body ending in its own newline is whole at once; more bytes than its length are refused"
  assert took(with_length(fresh(), 6), "abcde").1 == Whole(body: "abcde\n")
  two = took(took(with_length(fresh(), 3), "ab").0, "cd")
  assert two.1 == Refuse(refusal: malformed())
  assert ended(took(with_length(fresh(), 10), "ab").0) == Refuse(refusal: malformed())
end

test "a head past 16,384 bytes is too large, and a stream that ends mid-head is malformed"
  assert took(fresh(), "X: #{"x".repeat(16_400)}").1 == Refuse(refusal: too_large())
  assert ended(took(fresh(), "POST /tool HTTP/1.1").0) == Refuse(refusal: malformed())
end

test "the gate lets four in, and compares the token in constant time"
  gate = Gate.start(4, "a".repeat(64))
  assert gate.ask(Check(offered: "a".repeat(64)), within: 1.minute) == Ok(true)
  assert gate.ask(Check(offered: "wrong"), within: 1.minute) == Ok(false)
  assert gate.ask(Enter, within: 1.minute) == Ok(true)
  assert gate.ask(Enter, within: 1.minute) == Ok(true)
  assert gate.ask(Enter, within: 1.minute) == Ok(true)
  assert gate.ask(Enter, within: 1.minute) == Ok(true)
  assert gate.ask(Enter, within: 1.minute) == Ok(false)
  gate.send(Leave)
  assert gate.ask(Count, within: 1.minute) == Ok(3)
end

test "a wait past its deadline is 504 with execution unknown; an owner lost is 200 owner_unknown"
  c = Call(run_id: "r", workspace_id: "w", call_id: "c", operation: "read_file", args: Map.new(),
    timeout_ms: 0)
  late = status_of(Error(Timeout), c)
  assert (late.0, late.1.execution, late.1.error) == (504, "unknown", Some("response_timeout"))
  lost = status_of(Error(Down), c)
  assert (lost.0, lost.1.error) == (200, Some("owner_unknown"))
end
