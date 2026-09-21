module Moscope.Tests

use Moscope.Model{Mode, Options, Scan, Report, empty_scan}
use Moscope.Parse{FileFold, start_file, folded_line}
use Moscope.Search{report}

intent "Narrow source-level cases for message identity, phrase versus all-words matching, duplicate UUIDs, conflicts, and unsupported conversation shapes."

fn folded(lines: List(String), clock: Clock) : FileFold
  lines.reduce(start_file(empty_scan(), "synthetic.jsonl", 1_000_000, clock, clock.now),
    fn(state, line) folded_line(state, line) end)
end

fn options(query: String, mode: Mode, tools: Bool) : Options
  Options(query: query, dir: ".", mode: mode, include_tools: tools)
end

fn searched(scan: Scan, wanted: Options, clock: Clock) : Report
  report(scan, wanted, clock, clock.now)
end

test "a phrase stays inside one block while all words may span blocks of one logical message"
  clock = Clock.fixture()
  first = "{\"type\":\"assistant\",\"uuid\":\"one\",\"sessionId\":\"s\",\"timestamp\":\"2026-09-21T10:00:00Z\",\"message\":{\"role\":\"assistant\",\"id\":\"m\",\"content\":[{\"type\":\"text\",\"text\":\"connection here\",\"apiBlockIndex\":3}]}}"
  second = "{\"type\":\"assistant\",\"uuid\":\"two\",\"sessionId\":\"s\",\"timestamp\":\"2026-09-21T10:00:01Z\",\"message\":{\"role\":\"assistant\",\"id\":\"m\",\"content\":[{\"type\":\"text\",\"text\":\"refused there\",\"apiBlockIndex\":8}]}}"
  scan = folded([first, second], clock).scan
  assert searched(scan, options("connection refused", Phrase, false), clock).matches == 0
  all = searched(scan, options("connection refused", AllWords, false), clock)
  assert all.matches == 1
  assert all.text.contains?("apiBlockIndex=3") and all.text.contains?("apiBlockIndex=8")
end

test "tool blocks are opt-in and thinking remains excluded"
  clock = Clock.fixture()
  thinking = "{\"type\":\"assistant\",\"uuid\":\"think\",\"sessionId\":\"s\",\"message\":{\"role\":\"assistant\",\"id\":\"think\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"tool-needle\"}]}}"
  tool = "{\"type\":\"assistant\",\"uuid\":\"tool\",\"sessionId\":\"s\",\"message\":{\"role\":\"assistant\",\"id\":\"tool\",\"content\":[{\"type\":\"tool_use\",\"name\":\"demo\",\"input\":{\"query\":\"tool-needle\"}}]}}"
  scan = folded([thinking, tool], clock).scan
  assert searched(scan, options("tool-needle", Phrase, false), clock).matches == 0
  assert searched(scan, options("tool-needle", Phrase, true), clock).matches == 1
  assert searched(scan, options("demo", Phrase, true), clock).matches == 1
end

test "an exact decoded duplicate UUID is removed and a conflicting payload is incomplete"
  clock = Clock.fixture()
  one = "{\"type\":\"user\",\"uuid\":\"same\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"kept\"}}"
  conflict = "{\"type\":\"user\",\"uuid\":\"same\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"changed\"}}"
  duplicate = folded([one, one], clock).scan
  assert duplicate.messages.size == 1 and !duplicate.incomplete
  disagreed = folded([one, conflict], clock).scan
  assert disagreed.messages.size == 1 and disagreed.incomplete
end

test "physical fallback identity cannot collide with a provided physical-looking id"
  clock = Clock.fixture()
  missing = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"content\":\"alpha\"}}"
  provided = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"id\":\"physical:1\",\"content\":\"omega\"}}"
  scan = folded([missing, provided], clock).scan
  assert scan.messages.size == 2
  assert searched(scan, options("alpha omega", AllWords, false), clock).matches == 0
  assert searched(scan, options("alpha", Phrase, false), clock).matches == 1
  assert searched(scan, options("omega", Phrase, false), clock).matches == 1
end

test "invalid top-level classification cases independently make a result incomplete"
  clock = Clock.fixture()
  nonobject = folded(["[]"], clock).scan
  missing = folded(["{\"payload\":{}}"], clock).scan
  nonstring = folded(["{\"type\":42,\"payload\":{}}"], clock).scan
  conversation = folded([
    "{\"type\":\"future_conversation\",\"message\":{\"role\":\"user\",\"content\":\"needle\"}}"
  ], clock).scan
  wanted = options("needle", Phrase, false)
  assert searched(nonobject, wanted, clock).incomplete
  assert searched(missing, wanted, clock).incomplete
  assert searched(nonstring, wanted, clock).incomplete
  assert searched(conversation, wanted, clock).incomplete
end

test "unknown bookkeeping is counted, but unknown conversation shapes are incomplete"
  clock = Clock.fixture()
  bookkeeping = "{\"type\":\"future_bookkeeping\",\"payload\":{}}"
  unknown_conversation = "{\"type\":\"future_conversation\",\"message\":{\"role\":\"user\",\"content\":\"needle\"}}"
  future = "{\"type\":\"assistant\",\"uuid\":\"future\",\"sessionId\":\"s\",\"message\":{\"role\":\"assistant\",\"id\":\"m\",\"content\":[{\"type\":\"future_block\"}]}}"
  known_unknown = folded([bookkeeping], clock).scan
  assert !known_unknown.incomplete
  assert known_unknown.unknown_kinds.get("future_bookkeeping") == Some(1)
  assert folded([unknown_conversation], clock).scan.incomplete
  assert folded([future], clock).scan.incomplete
end
