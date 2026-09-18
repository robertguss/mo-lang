module Jobq.Bench
expose Load, Producer, Producers, Pairer, Pairers, loaded, paired, rate_line, seconds, resident_mib, create_body

intent "The client half of jobq bench: producers that create jobs and workers that lease and ack them, each a process of its own that sends one request per connection to a service on a port, and the lines bench prints, in the shape the round's measure.py prints them: creates a second, lease-and-ack pairs a second at 1 and at N workers, and the resident memory the program's process holds, read from /proc/self/status."

# What a run of the load gave: how many requests did what they were sent to do, how many did not,
# and how long it took.
struct Load
  done: UInt64
  failed: UInt64
  ms: Int64
end

# A producer that makes `count` jobs when told, in four queues by turn, with a payload of 100 bytes.
process Producer(http: Http, port: UInt16, index: UInt64, count: UInt64)
  state
    made: UInt64
    failed: UInt64
  end

  message Go
  message Made : UInt64

  fn update(state, message)
    case message
      Go:
        for k in 0..count
          if status_of(http, port, "p#{index}", "POST", "/jobs", create_body(index + k)) == 201
            state.made += 1
          else
            state.failed += 1
          end
        end
      Made: state.made
    end
  end
end

supervisor Producers(http: Http, port: UInt16, index: UInt64, count: UInt64)
  child Producer(http, port, index, count), restart: :never
end

# A worker that leases a job from its queue and acks it, again and again, until `until` or until
# its queue has nothing left, and counts the pairs whose ack was 200.
process Pairer(http: Http, clock: Clock, port: UInt16, index: UInt64, until: Time)
  state
    pairs: UInt64
    failed: UInt64
  end

  message Go
  message Pairs : UInt64

  fn update(state, message)
    case message
      Go:
        for _ in 0..10_000
          done = rounds(http, clock, port, index, until)
          state.pairs += done.0
          state.failed += done.1
          if done.2
            break
          end
        end
      Pairs: state.pairs
    end
  end
end

supervisor Pairers(http: Http, clock: Clock, port: UInt16, index: UInt64, until: Time)
  child Pairer(http, clock, port, index, until), restart: :never
end

# Up to 1,000 lease-and-ack pairs, a small range each time since a range is built whole before a
# for walks it: the pairs acked, the acks refused, and whether the worker is done, its time up or
# its queue empty.
fn rounds(http: Http, clock: Clock, port: UInt16, index: UInt64, until: Time) : (UInt64, UInt64,
  Bool)
  worker = "w#{index}"
  var pairs = 0
  var failed = 0
  var over = false
  for _ in 0..1_000
    over = clock.now >= until
    lent = if over
      (0, "")
    else
      sent(http, port, worker, "POST", "/queues/q#{index % 4}/lease", "{\"lease_ms\": 60000}")
    end
    over = over or lent.0 != 200
    if over
      break
    end
    if status_of(http, port, worker, "POST", "/jobs/#{id_in(lent.1)}/ack", "") == 200
      pairs += 1
    else
      failed += 1
    end
  end
  (pairs, failed, over)
end

# A create's body: a queue of four by turn, and 100 bytes of payload.
fn create_body(n: UInt64) : String
  "{\"queue\": \"q#{n % 4}\", \"payload\": \"#{"x".repeat(100)}\", \"max_tries\": 3}"
end

# One request's status and body, status 0 when the wire failed.
fn sent(http: Http, port: UInt16, token: String, method: String, path: String,
  body: String) : (UInt16, String)
  request = Request(method: method, path: path,
    headers: Map.new().set("authorization", "Bearer #{token}"), body: body)
  case http.send(request, host: "127.0.0.1", port: port, within: 30_000.ms)
    Ok(response): (response.status, response.body)
    Error(_): (0, "")
  end
end

fn status_of(http: Http, port: UInt16, token: String, method: String, path: String,
  body: String) : UInt16
  sent(http, port, token, method, path, body).0
end

fn id_in(body: String) : String
  case Json.decode(body)
    Ok(Object(fields)):
      case fields.get("id")
        Some(String(id)): id
        Some(_) | None: ""
      end
    Ok(_) | Error(_): ""
  end
end

# `jobs` creates from 8 producers at once, spread evenly; the first ones take any rest.
fn loaded(http: Http, clock: Clock, port: UInt16, jobs: UInt64) : Load
  began = clock.now
  var producers = [Producer.start(http, port, 0, share(jobs, 0))]
  for i in 1..8
    producers = producers.push(Producer.start(http, port, i * 1_000_000, share(jobs, i)))
  end
  for p in producers
    p.send(Go)
  end
  var made = 0
  for p in producers
    made += case p.ask(Made, within: 3_600_000.ms)
      Ok(n): n
      Error(_): 0
    end
  end
  Load(done: made, failed: jobs - made, ms: (clock.now - began).ms)
end

# The jobs the i-th of 8 producers makes: an even share, and one more for the first of any rest.
fn share(jobs: UInt64, i: UInt64) : UInt64
  jobs / 8 + (if i < jobs % 8: 1 else: 0)
end

# Lease-and-ack pairs from `workers` workers at once for `ms` milliseconds.
fn paired(http: Http, clock: Clock, port: UInt16, workers: UInt64, ms: UInt64) : Load
  began = clock.now
  until = began + ms.to_i64.ms
  var pairers = [Pairer.start(http, clock, port, 0, until)]
  for i in 1..workers
    pairers = pairers.push(Pairer.start(http, clock, port, i, until))
  end
  for p in pairers
    p.send(Go)
  end
  var pairs = 0
  for p in pairers
    pairs += case p.ask(Pairs, within: 3_600_000.ms)
      Ok(n): n
      Error(_): 0
    end
  end
  Load(done: pairs, failed: 0, ms: (clock.now - began).ms)
end

# A count over its time, as measure.py prints it: `<label>: <n> in <s> s = <rate>/s`.
fn rate_line(label: String, load: Load) : String
  ms = if load.ms < 1: 1 else: load.ms.to_u64
  errors = if load.failed == 0: "" else: ", #{load.failed} not done"
  "#{label}: #{load.done} in #{seconds(ms)} s = #{load.done * 1_000 / ms}/s#{errors}"
end

# Milliseconds as seconds with two decimals.
fn seconds(ms: UInt64) : String
  hundredths = ms / 10 % 100
  pad = if hundredths < 10: "0" else: ""
  "#{ms / 1_000}.#{pad}#{hundredths}"
end

# The resident memory of this process in MiB with one decimal, from the VmRSS line of
# /proc/self/status, or None where there is no such file.
fn resident_mib(fs: Fs) : Option(String)
  line = case fs.read_only.fold_lines("/proc/self/status", "", within: 5_000.ms,
    fn(found, next) if next.starts_with?("VmRSS:"): next else: found end)
    Ok(found): found
    Error(_): ""
  end
  mib_of(line)
end

# A VmRSS line's kB as MiB with one decimal: "VmRSS:\t    3884 kB" is 3.7.
fn mib_of(line: String) : Option(String)
  words = line.replace("\t", " ").split(" ").filter(fn(w) w != "" and w != "VmRSS:" end)
  kb = try (words.first or "").trim.to_u64
  Some("#{kb / 1_024}.#{kb % 1_024 * 10 / 1_024}")
end

test "a rate line is a count over seconds with two decimals, as measure.py prints it"
  assert rate_line("creates",
    Load(done: 30_000, failed: 0, ms: 18_437)) == "creates: 30000 in 18.43 s = 1627/s"
  assert rate_line("pairs, 32 workers",
    Load(done: 9_449, failed: 2,
    ms: 10_004)) == "pairs, 32 workers: 9449 in 10.00 s = 944/s, 2 not done"
  assert rate_line("x", Load(done: 0, failed: 0, ms: 0)) == "x: 0 in 0.00 s = 0/s"
  assert seconds(1_205) == "1.20" and seconds(90) == "0.09" and seconds(60_000) == "60.00"
end

test "a create's body names one of four queues by turn and carries 100 bytes"
  assert create_body(5).starts_with?("{\"queue\": \"q1\", \"payload\": \"xxxx")
  assert Json.decode(create_body(2)) is Ok(Object(fields))
  assert fields.get("payload") == Some(String(text: "x".repeat(100)))
  assert id_in("{\"id\": \"j_7\", \"queue\": \"q\"}") == "j_7" and id_in("nope") == ""
end

test "the resident memory is read from a status file's VmRSS line, and none where there is none"
  assert resident_mib(Fs.fixture()) is None
  assert mib_of("VmRSS:\t    3884 kB") == Some("3.7") and mib_of("") is None
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run
