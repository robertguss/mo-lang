module WorkspaceServer.Server
expose Settings, settings_of, secrets_of, serve_run

use WorkspaceServer.Admission{Admission}
use WorkspaceServer.Connection{Acceptor, Gate, Identity}
use WorkspaceServer.Journal{Journal, binding_text}
use WorkspaceServer.Operator{Desk, Door, OperatorDoor}
use WorkspaceServer.Worker{Worker, Tap, Script, production}

intent "Start one run from its folder: read the operator's config.json and capability.json, start the journal, admission, the worker holding the workspace folder, the gate holding the token and the desk holding the operator's, bind the journal to the hashes of the source and the verifier configuration before anything is served, listen on two loopback ports, open the lease, and publish readiness in ready.json. Each process is handed only what it uses."

struct Settings
  run_id: String
  workspace_id: String
  lease_ms: UInt64
  journal_cap: UInt64
  late_ms: UInt64
  verifier_sha256: String
end

fn text_in(fields: Map(String, Json), key: String) : String
  case fields.get(key)
    Some(String(text)): text
    Some(Object(_)) | Some(Array(_)) | Some(Number(_)) | Some(Bool(_)) | Some(Null) | None: ""
  end
end

fn count_in(fields: Map(String, Json), key: String, default: UInt64, most: UInt64) : UInt64
  case fields.get(key)
    Some(value): min_of((value.to_i64 or default.to_i64).to_u64, most)
    None: default
  end
end

# The operator's settings: identities, the lease (at most 900 s), the journal's bound, the
# double's late replies, and the hash of the verifier configuration as given.
fn settings_of(text: String) : Result(Settings, String)
  case Json.decode(text)
    Ok(Object(fields)):
      run_id = text_in(fields, "run_id")
      workspace_id = text_in(fields, "workspace_id")
      return Error("config.json names no run or workspace") if run_id == "" or workspace_id == ""
      verifier = Json.encode(fields.get("verifier") or Null)
      Ok(Settings(run_id: run_id, workspace_id: workspace_id,
        lease_ms: count_in(fields, "lease_ms", 900_000, 900_000),
        journal_cap: count_in(fields, "journal_cap", 4_194_304, 4_194_304),
        late_ms: count_in(fields, "late_ms", 0, 60_000),
        verifier_sha256: Hash.hex(Hash.sha256(verifier.bytes))))
    Ok(Array(_)) | Ok(String(_)) | Ok(Number(_)) | Ok(Bool(_)) | Ok(Null) | Error(_):
      Error("config.json is not a JSON object")
  end
end

# The candidate token and the operator's: 64 lowercase hex characters each.
fn secrets_of(text: String) : Result((String, String), String)
  case Json.decode(text)
    Ok(Object(fields)):
      token = text_in(fields, "token")
      operator = text_in(fields, "operator_token")
      return Error("capability.json holds no two 64-character tokens") if token.byte_size != 64 or operator.byte_size != 64
      Ok((token, operator))
    Ok(Array(_)) | Ok(String(_)) | Ok(Number(_)) | Ok(Bool(_)) | Ok(Null) | Error(_):
      Error("capability.json is not a JSON object")
  end
end

fn read_in(run: Fs, name: String) : Result(String, String)
  case run.read(name, within: 5_000.ms)
    Ok(text): Ok(text)
    Error(e): Error("#{name}: #{e}")
  end
end

fn hashed(worker: Handle(Worker)) : Result(String, String)
  case worker.ask(Digest, within: 60_000.ms)
    Ok(digest):
      return Error("the source could not be read whole") if digest == "unreadable"
      Ok(digest)
    Error(_): Error("the source could not be hashed")
  end
end

# The candidates' loopback port, served into the acceptor from here on.
fn candidates(net: Net, given: Identity, gate: Handle(Gate), admission: Handle(Admission),
  worker: Handle(Worker), journal: Handle(Journal)) : Result(UInt16, String)
  case net.listen(0, within: 5_000.ms)
    Ok(listener):
      identity = Identity(run_id: given.run_id, workspace_id: given.workspace_id, port: listener.port,
        commands: given.commands)
      listener.serve(into: Acceptor.start(identity, gate, admission, worker, journal), idle: 60_000.ms)
      Ok(listener.port)
    Error(e): Error("candidate port: #{e}")
  end
end

fn operators(net: Net, desk: Handle(Desk)) : Result(UInt16, String)
  case net.listen(0, within: 5_000.ms)
    Ok(listener):
      listener.serve(into: OperatorDoor.start(desk), idle: 60_000.ms)
      Ok(listener.port)
    Error(e): Error("operator port: #{e}")
  end
end

# The whole run, served. The door is let go by the operator's close, or by the desk itself
# a minute after the lease ends.
fn serve_run(run: Fs, net: Net, clock: Clock, random: Random, double: Bool, door: Handle(Door)) : Result(UInt64, String)
  settings = try settings_of(try read_in(run, "config.json"))
  secrets = try secrets_of(try read_in(run, "capability.json"))
  journal = Journal.start(run, settings.journal_cap)
  admission = Admission.start(journal, clock, random, settings.lease_ms)
  script = if double: Script(commands: true, late_ms: settings.late_ms) else: production()
  tap = if double: Some(Tap.start(run.scoped("workspace"))) else: None
  worker = Worker.start(run.scoped("workspace/data"), journal, admission, script, tap)
  worker.send(Know(me: worker))
  source = try hashed(worker)
  binding = binding_text(settings.run_id, settings.workspace_id, source, settings.verifier_sha256)
  return Error("the journal could not be bound") if journal.ask(Bind(binding: binding), within: 5_000.ms) != Ok(true)
  gate = Gate.start(4, secrets.0)
  desk = Desk.start(secrets.1, admission, journal, worker, gate, door)
  identity = Identity(run_id: settings.run_id, workspace_id: settings.workspace_id, port: 0,
    commands: double)
  port = try candidates(net, identity, gate, admission, worker, journal)
  operator_port = try operators(net, desk)
  return Error("the lease did not open") if admission.ask(Open, within: 5_000.ms) != Ok(true)
  desk.send(Expire, delay: (settings.lease_ms + 60_000).ms)
  ready = "{\"port\": #{port}, \"operator_port\": #{operator_port}, \"run_id\": #{Json.encode(settings.run_id)}, \"workspace_id\": \"#{settings.workspace_id}\"}"
  if run.replace("ready.json", ready, within: 5_000.ms) is Error(e)
    return Error("ready.json: #{e}")
  end
  Ok(settings.lease_ms)
end
