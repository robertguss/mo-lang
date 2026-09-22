module Tests

use Find{matcher_of}
use Model{Mode, Options, Scan, Report, empty_scan}
use Parse{FileFold, start_file, folded_line}
use Search{report}

intent "End-to-end source cases from records to rendered report: identity, phrase versus all-words, warnings versus errors, strict mode, and excerpts."

fn options(query: String, mode: Mode, tools: Bool) : Options
  Options(query: query, dir: "sessions", mode: mode, include_tools: tools, strict: false)
end

fn searched(wanted: Options, lines: List(String)) : Report
  folded = lines.reduce(start_file(empty_scan(), matcher_of(wanted), "synthetic.jsonl"),
    fn(state, line) folded_line(state, line) end)
  report(folded.scan, wanted)
end

test "a phrase stays inside one block while all words may span blocks of one logical message"
  first = "{\"type\":\"assistant\",\"uuid\":\"one\",\"sessionId\":\"s\",\"timestamp\":\"2026-09-21T10:00:00Z\",\"message\":{\"role\":\"assistant\",\"id\":\"m\",\"content\":[{\"type\":\"text\",\"text\":\"connection here\",\"apiBlockIndex\":3}]}}"
  second = "{\"type\":\"assistant\",\"uuid\":\"two\",\"sessionId\":\"s\",\"timestamp\":\"2026-09-21T10:00:01Z\",\"message\":{\"role\":\"assistant\",\"id\":\"m\",\"content\":[{\"type\":\"text\",\"text\":\"refused there\",\"apiBlockIndex\":8}]}}"
  assert searched(options("connection refused", Phrase, false), [first, second]).matches == 0
  all = searched(options("connection refused", AllWords, false), [first, second])
  assert all.matches == 1 and !all.incomplete
  assert all.text.contains?("apiBlockIndex=3") and all.text.contains?("apiBlockIndex=8")
  assert all.text.contains?("sessions/synthetic.jsonl:2")
end

test "tool blocks are opt-in and thinking remains excluded"
  thinking = "{\"type\":\"assistant\",\"uuid\":\"think\",\"sessionId\":\"s\",\"message\":{\"role\":\"assistant\",\"id\":\"think\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"tool-needle\"}]}}"
  tool = "{\"type\":\"assistant\",\"uuid\":\"tool\",\"sessionId\":\"s\",\"message\":{\"role\":\"assistant\",\"id\":\"tool\",\"content\":[{\"type\":\"tool_use\",\"name\":\"demo\",\"input\":{\"query\":\"tool-needle\"}}]}}"
  assert searched(options("tool-needle", Phrase, false), [thinking, tool]).matches == 0
  assert searched(options("tool-needle", Phrase, true), [thinking, tool]).matches == 1
  assert searched(options("demo", Phrase, true), [thinking, tool]).matches == 1
end

test "physical fallback identity cannot collide with a provided physical-looking id"
  missing = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"content\":\"alpha\"}}"
  provided = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"id\":\"physical:1\",\"content\":\"omega\"}}"
  lines = [missing, provided]
  assert searched(options("alpha omega", AllWords, false), lines).matches == 0
  assert searched(options("alpha", Phrase, false), lines).matches == 1
  assert searched(options("omega", Phrase, false), lines).matches == 1
end

test "warnings leave a search complete unless strict, and still report what matched"
  good = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"id\":\"m\",\"content\":\"needle\"}}"
  lines = [good,
    "[]",
    "{\"payload\":{}}",
    "{\"type\":42}",
    "{\"type\":\"future_conversation\",\"message\":{\"role\":\"user\",\"content\":\"needle\"}}"]
  relaxed = searched(options("needle", Phrase, false), lines)
  assert relaxed.matches == 1 and !relaxed.incomplete
  assert relaxed.diagnostics.contains?("moscope: warning: a non-object record was skipped (1; first at sessions/synthetic.jsonl:2)")
  var strict = options("needle", Phrase, false)
  strict.strict = true
  refused = searched(strict, lines)
  assert refused.matches == 1 and refused.incomplete
  assert refused.diagnostics.contains?("--strict treats the warnings above as errors")
end

test "the session heading carries a resume hint and bookkeeping is one summary note"
  record = "{\"type\":\"user\",\"sessionId\":\"abc-1\",\"cwd\":\"/work/my app\",\"timestamp\":\"2026-09-21T12:00:00+02:00\",\"message\":{\"role\":\"user\",\"content\":\"needle\"}}"
  lines = [record, "{\"type\":\"progress\"}", "{\"type\":\"ai-title\"}"]
  shown = searched(options("needle", Phrase, false), lines)
  assert shown.text.starts_with?("Session abc-1 — latest 2026-09-21T10:00:00Z\n  resume: cd '/work/my app' && claude --resume abc-1\n")
  assert shown.diagnostics == "moscope: note: ignored 2 non-conversation records of 2 kinds\n"
  single = searched(options("needle", Phrase, false), [record, "{\"type\":\"progress\"}"])
  assert single.diagnostics == "moscope: note: ignored 1 non-conversation record of 1 kind\n"
  assert single.text.ends_with?("\n1 matching message.\n")
end

test "excerpts centre on the match and keep ordinary Unicode readable"
  long = "#{"é".repeat(300)} — needle — #{"z".repeat(300)}"
  record = "{\"type\":\"user\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"content\":\"#{long}\"}}"
  shown = searched(options("NEEDLE", Phrase, false), [record])
  assert shown.text.contains?("— needle —")
  assert shown.text.contains?("      ...éé")
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
