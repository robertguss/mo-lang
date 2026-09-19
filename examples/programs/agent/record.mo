module Agent.Record
expose fixture_tools, fixture_budget, Status, Budget, Order, Record, Health, tool_names, budget, default_budget, order, record, goal?, folder?, tools?, host?, hosts?, steps?, tokens?, wall_ms?, retries?, tool_ms?, token?, status_name, status_named, final?, shown, health_of, id_of, number_of

intent "What agent is about: a run's order (the goal, the folder, the tools and hosts it grants, and the budget) and the rules each keeps, the run's record and its five states, and the JSON a record is shown as."

enum Status
  Running
  Done
  Failed
  OverBudget
  Cancelled
end

# How far a run may go: model calls, the tokens they spend, its whole time, the retries of each
# model call, and the time of each call.
struct Budget
  steps: UInt64
  tokens: UInt64
  wall_ms: UInt64
  retries: UInt32
  tool_ms: UInt64
end

# What a client asks for: the goal, the folder under the service's folder the run works in, the
# tools and hosts it grants, and the budget.
struct Order
  goal: String
  folder: String
  tools: List(String)
  hosts: List(String)
  budget: Budget
end

# A run as the API shows it. Its state is `status`, its result `answer`, and its error `why`,
# since state and result are keywords.
struct Record
  id: String
  owner: String
  status: Status
  goal: String
  steps_taken: UInt64
  tokens_used: UInt64
  answer: Option(String)
  why: Option(String)
  created_at: Time
  updated_at: Time
end

struct Health
  running: UInt64
  done: UInt64
  failed: UInt64
  over_budget: UInt64
  cancelled: UInt64
  uptime_ms: UInt64
end

# Every tool the harness can run; a run grants some of them.
fn tool_names() : List(String)
  ["list_files", "read_file", "search", "write_file", "http_get", "now"]
end

# Opt-in trusted fixture catalog; legacy tool_names and order validation stay unchanged.
fn fixture_tools() : List(String)
  ["list_files", "read_file", "search", "write_file", "exact_edit", "command"]
end

fn fixture_budget() : Budget
  budget(16, 4_096, 30_000, 0, 2_000)
end

fn steps?(n: UInt64) : Bool
  n >= 1 and n <= 200
end

fn tokens?(n: UInt64) : Bool
  n >= 1 and n <= 10_000_000
end

fn wall_ms?(n: UInt64) : Bool
  n >= 100 and n <= 3_600_000
end

fn retries?(n: UInt32) : Bool
  n <= 10
end

fn tool_ms?(n: UInt64) : Bool
  n >= 100 and n <= 60_000
end

fn budget(steps: UInt64, tokens: UInt64, wall_ms: UInt64, retries: UInt32, tool_ms: UInt64) : Budget
  requires steps?(steps)
  requires tokens?(tokens)
  requires wall_ms?(wall_ms)
  requires retries?(retries)
  requires tool_ms?(tool_ms)

  Budget(steps: steps, tokens: tokens, wall_ms: wall_ms, retries: retries, tool_ms: tool_ms)
end

# The budget a field left out takes.
fn default_budget() : Budget
  budget(20, 100_000, 60_000, 2, 5_000)
end

# A goal is 1 byte to 4 KiB.
fn goal?(text: String) : Bool
  text != "" and text.byte_size <= 4_096
end

# A folder is a path inside the service's folder: 1 to 256 bytes of segments made of letters,
# digits, ., - and _, none of them . or .., and none starting where the service keeps its logs.
fn folder?(path: String) : Bool
  return false if path == "" or path.byte_size > 256
  segments = path.split("/")
  segments.all?(fn(s) segment?(s) end) and !(segments.first or "").starts_with?("runs")
end

fn segment?(text: String) : Bool
  return false if text == "" or text == "." or text == ".."
  text.bytes.all?(fn(b) named?(b) or b == 46 end)
end

fn named?(b: UInt8) : Bool
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45 or b == 95
end

# Tools are named once each, and each is one the harness has.
fn tools?(names: List(String)) : Bool
  names.all?(fn(name) tool_names().contains?(name) end) and names.unique.size == names.size
end

# A host is a name of letters, digits, ., - and _, and a port after a : when it names one.
fn host?(text: String) : Bool
  parts = text.split(":")
  name = parts.first or ""
  return false if parts.size > 2 or name == "" or name.byte_size > 253
  named = name.bytes.all?(fn(b) named?(b) or b == 46 end)
  named and (parts.size == 1 or port?(parts.get(1) or ""))
end

fn port?(text: String) : Bool
  n = text.to_u64 or 0
  n >= 1 and n <= 65_535 and "#{n}" == text
end

# At most 32 hosts, each a host.
fn hosts?(hosts: List(String)) : Bool
  hosts.size <= 32 and hosts.all?(fn(h) host?(h) end)
end

fn order(goal: String, folder: String, tools: List(String), hosts: List(String),
  budget: Budget) : Order
  requires goal?(goal)
  requires folder?(folder)
  requires tools?(tools)
  requires hosts?(hosts)

  Order(goal: goal, folder: folder, tools: tools, hosts: hosts, budget: budget)
end

# A token names the run's owner: 1 to 256 bytes with no space or control character.
fn token?(text: String) : Bool
  size = text.byte_size
  size >= 1 and size <= 256 and text.bytes.all?(fn(b) b > 32 and b != 127 end)
end

# A run just made: running, nothing taken yet.
fn record(id: String, owner: String, goal: String, now: Time) : Record
  ensures result.status == Running and result.steps_taken == 0

  Record(id: id, owner: owner, status: Running, goal: goal, steps_taken: 0, tokens_used: 0,
    answer: None, why: None, created_at: now, updated_at: now)
end

fn final?(status: Status) : Bool
  status != Running
end

fn status_name(status: Status) : String
  case status
    Running: "running"
    Done: "done"
    Failed: "failed"
    OverBudget: "over_budget"
    Cancelled: "cancelled"
  end
end

fn status_named(name: String) : Option(Status)
  case name
    "running": Some(Running)
    "done": Some(Done)
    "failed": Some(Failed)
    "over_budget": Some(OverBudget)
    "cancelled": Some(Cancelled)
    _: None
  end
end

# A record as the API shows it, the spec's fields in its order, written by hand since a struct
# cannot have a field named state or result.
fn shown(record: Record) : String
  head = "{\"id\": #{Json.encode(record.id)}, \"state\": \"#{status_name(record.status)}\", \"goal\": #{Json.encode(record.goal)}"
  counts = "\"steps_taken\": #{record.steps_taken}, \"tokens_used\": #{record.tokens_used}"
  ends = "\"result\": #{Json.encode(record.answer)}, \"error\": #{Json.encode(record.why)}"
  times = "\"created_at\": #{Json.encode(record.created_at)}, \"updated_at\": #{Json.encode(record.updated_at)}"
  "#{head}, #{counts}, #{ends}, #{times}}"
end

fn health_of(records: List(Record), uptime_ms: UInt64) : Health
  Health(running: records.count(fn(r) r.status == Running end),
    done: records.count(fn(r) r.status == Done end),
    failed: records.count(fn(r) r.status == Failed end),
    over_budget: records.count(fn(r) r.status == OverBudget end),
    cancelled: records.count(fn(r) r.status == Cancelled end), uptime_ms: uptime_ms)
end

fn id_of(number: UInt64) : String
  "r_#{number}"
end

# The number in an id, which is r_ and the number as id_of writes it.
fn number_of(id: String) : Option(UInt64)
  return None if !id.starts_with?("r_")
  n = try id.slice(2, id.size).to_u64
  return None if id_of(n) != id
  Some(n)
end

test "each budget field keeps its bounds, and a field left out takes its default"
  assert steps?(1) and steps?(200) and !steps?(0) and !steps?(201)
  assert tokens?(1) and tokens?(10_000_000) and !tokens?(0) and !tokens?(10_000_001)
  assert wall_ms?(100) and wall_ms?(3_600_000) and !wall_ms?(99) and !wall_ms?(3_600_001)
  assert retries?(0) and retries?(10) and !retries?(11)
  assert tool_ms?(100) and tool_ms?(60_000) and !tool_ms?(99) and !tool_ms?(60_001)
  assert default_budget() == Budget(steps: 20, tokens: 100_000, wall_ms: 60_000, retries: 2,
    tool_ms: 5_000)
end

test "a folder stays inside the service's folder and out of its logs"
  assert folder?("work") and folder?("work/notes-1") and folder?("a.b/c_d")
  assert !folder?("") and !folder?(".") and !folder?("..") and !folder?("work/../..")
  assert !folder?("/etc") and !folder?("work//x") and !folder?("runs") and !folder?("runs.check/r_1")
  assert !folder?("a b") and !folder?("x".repeat(257))
end

test "tools are the harness's, each once, and hosts are names with an optional port"
  assert tools?([]) and tools?(["now", "read_file"]) and tools?(tool_names())
  assert !tools?(["rm"]) and !tools?(["now", "now"])
  assert host?("127.0.0.1:7951") and host?("example.com") and host?("localhost:80")
  assert !host?("") and !host?("a b") and !host?("h:0") and !host?("h:65536") and !host?("h:1:2")
  assert !host?("h:08") and !host?(":80")
  assert hosts?([]) and hosts?(["a", "b:1"]) and !hosts?(["ok", "not ok"])
  assert hosts?((0..32).map(fn(i) "h#{i}" end)) and !hosts?((0..33).map(fn(i) "h#{i}" end))
end

test "a record is shown with the spec's fields in order, null for no result or error"
  at = Time.fixture()
  made = record("r_1", "ada", "count \"a\"", at)
  assert shown(made) == "{\"id\": \"r_1\", \"state\": \"running\", \"goal\": \"count \\\"a\\\"\", \"steps_taken\": 0, \"tokens_used\": 0, \"result\": null, \"error\": null, \"created_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:00:00Z\"}"
  var done = made
  done.status = Done
  done.answer = Some("42")
  assert shown(done).contains?("\"state\": \"done\"") and shown(done).contains?("\"result\": \"42\", \"error\": null")
  assert final?(Done) and final?(Cancelled) and !final?(Running)
  names = ["running", "done", "failed", "over_budget", "cancelled"]
  assert names.all?(fn(name) status_name(status_named(name) or Running) == name end)
  assert status_named("lost") is None
end

test "health counts each state, and an id is r_ and the number"
  at = Time.fixture()
  var failed = record("r_2", "ada", "g", at)
  failed.status = Failed
  counts = health_of([record("r_1", "ada", "g", at), failed, failed], 5)
  assert counts == Health(running: 1, done: 0, failed: 2, over_budget: 0, cancelled: 0,
    uptime_ms: 5)
  assert Json.encode(counts) == "{\"running\": 1, \"done\": 0, \"failed\": 2, \"over_budget\": 0, \"cancelled\": 0, \"uptime_ms\": 5}"
  assert id_of(7) == "r_7" and number_of("r_7") == Some(7)
  assert number_of("r_07") is None and number_of("j_7") is None and number_of("r_") is None
  assert token?("ada") and !token?("") and !token?("a b")
end

test rejects "a budget of no steps"
  budget(0, 100_000, 60_000, 2, 5_000)
end

test rejects "a budget of more than ten million tokens"
  budget(20, 10_000_001, 60_000, 2, 5_000)
end

test rejects "a budget of less than 100 ms"
  budget(20, 100_000, 99, 2, 5_000)
end

test rejects "a budget of eleven retries"
  budget(20, 100_000, 60_000, 11, 5_000)
end

test rejects "a budget whose calls may take more than a minute"
  budget(20, 100_000, 60_000, 2, 60_001)
end

test rejects "an order with no goal"
  order("", "work", [], [], default_budget())
end

test rejects "an order for a folder above the service's"
  order("g", "../etc", [], [], default_budget())
end

test rejects "an order for a tool the harness does not have"
  order("g", "work", ["rm"], [], default_budget())
end

test rejects "an order for a host that is not one"
  order("g", "work", [], ["not a host"], default_budget())
end

verified: types, contracts, tests (14), property (0 seeds), sim (not run)
          proven: not run
