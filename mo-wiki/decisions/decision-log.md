---
title: "Decision log"
created: 2026-09-12
updated: 2026-09-13
type: decision
tags: [meta, laws]
sources: [spec/grammar.md, plans/model-bakeoff.md]
number: 0
---

# Decision log

Robert (session 5): "keeping a changelog but also a decision log so we can see how things change over time... document choices and decisions you and I make." This page is the decision log: one row per choice, appended in order, never edited except to change `status`. `CHANGELOG.md` at the repo root is the changelog of what shipped. Locked rules get their own `DNN` page at the v0 lock and a row here pointing to it.

Columns: **who** is who made the call (Robert, or Fable deciding on Robert's instruction). **status** is `provisional` until measured, then `locked` or `overturned` with a link to the row that replaced it. **first tested by** names the thing that can prove it wrong.

## Sessions 1–3

Recorded at the time on the pages themselves: the 35 directions (`directions/`), the 17 questions with answers (`questions/`), the 15 syntax picks (`syntax/`), and the session-3 tensions in [[session-03]]. Not repeated here.

## Session 4 (12 Sep 2026)

| decision | who | status | first tested by |
|---|---|---|---|
| No `pub`; one `expose` line under `module` ([[p14-modules]]) | Robert | provisional | the corpus |
| `use A.B{X, Y}`, no dot before the braces | Robert | provisional | the corpus |
| Every `for` closes with `end` | Robert | provisional | the corpus |
| Keep `for` and `map`/`filter`/`reduce`; formatter moves pure bodies to combinators ([[p11-loops-and-anonymous-functions]]) | Robert | provisional | the corpus |
| Chapter 4 shows current syntax; dated notes are the changelog only | Robert | locked | — |

## Session 5 (12 Sep 2026)

| decision | who | status | first tested by |
|---|---|---|---|
| design-v0 chapters 1–8 reviewed, no edits | Robert | — | — |
| Work happens on feature branches, never on `main` | Robert | locked | — |
| Fable delegates all building and writing to a worker model and reviews; Fable chose Opus ([[model-bakeoff]]) | Robert, then Fable | provisional | round 2 of the bake-off |
| No taste review of the corpus now; build, measure, evaluate; Fable may decide alone | Robert | locked for now | — |
| Deadline law amended: only calls that can wait take `within:` | Fable | provisional | `Mo.Sim` |
| `try` across error types: callee variants must exist in the caller's enum by name and fields | Fable | provisional | the checker on the refund module |
| Literals typed from use, else `Int64`; `size` is `UInt64`; no implicit widening | Fable | provisional | the checker on the corpus |
| `a..b` excludes `b` | Fable | provisional | the corpus |
| One-field variants match positionally; more fields by name; construction always by name | Fable | provisional | the parser |
| `state` fields start at the type's zero, else `= expr` | Fable | provisional | the interpreter |
| `Name.start`, `send` statement, `ask` returns `Result(Reply, AskError)`; reply arm evaluates to the reply | Fable | provisional | the interpreter |
| Supervisors take parameters and pass them on `child` lines (the one new syntax) | Fable | provisional | program 1's `main` |
| Platform chosen by the toolchain (`mo test` is `Mo.Sim`), never by a `use` line | Fable | provisional | the interpreter |
| Capability `fixture` constructors in tests; `Time.fixture()` | Fable | provisional | the corpus tests |
| `Self` in trait signatures | Fable | provisional | the checker |
| Refinement failure is a tripped contract; `test rejects` covers it | Fable | provisional | tier 2 |
| `Type.all` only in `never`; tier 2 skips it, tier 3 checks it | Fable | provisional | tier 3 |
| Module segment → lowercase hyphenated file name | Fable | provisional | the corpus |
| `main` is out of the milestone | Fable | provisional | program 1 |
| Grammar fixes: `cmp` with `is`, `assert` in `stmt`, `old` in `invariant`, `never` takes a bare call, `add` left-assoc, `params_untyped`, comprehension body is a block | Fable | provisional | the parser |

| `invariant` block is true when broken, same reading as `never` | Fable | provisional | tier 2 |
| A supervisor passes a sibling's handle as its own parameter; `main` orders the starts | Fable | provisional | program 1 |
| Step 1 accepted: lexer and parser by Opus, all 50 files parse, 23 minutes of worker time | Fable | — | the checker |
| Every phase runs in a fresh worker session and context window | Robert | locked | — |
| Step 2 accepted: tier-1 checker by Opus, 12 `rejects/` fail by code, 38 clean, 48 minutes | Fable | — | the interpreter |
| `FsError` is `Missing(path: String) | Timeout` | Fable, from Opus's default | provisional | the stdlib chapter |
| An undeclared one-letter type name in a signature is a type parameter of that function | Fable, from Opus's default | provisional | the corpus growing; revisit if a real program wants explicit generics |
| An undeclared type in a recipe signature is opaque; field reads on it are unchecked at tier 1 | Fable, from Opus's default | provisional | the three-recipe test in chapter 8 |
| Contract integers are `i128` in the interpreter, a stand-in for unbounded | Fable | provisional | tier-3 proving |
| The `verified:` line is printed by `mo test`, not written to the file, until the sidecar exists | Fable | provisional | step 5 |
| Step 3 runs pure code only; processes, supervisors, `never`, `invariant` are step 4 | Fable | provisional | step 4 |
| `property` runs 200 seeds from a fixed base seed; a failure reports seed and values | Fable | provisional | tier 3 on the corpus |
| `verified:` vocabulary gains `sim (not run)` until the simulator exists | Fable | provisional | step 4 |
| `test rejects` passes only by tripping a `requires` or a refinement; any other crash fails it | Fable | provisional | the corpus tests |
| `mo run` runs a module's tests until `main` exists | Fable | provisional | program 1 |
| Grok's and Codex's corpora stay on their branches as evidence, never merged | Fable | locked | — |
| Step 3 accepted: VM, tier-2 contracts, test runner by Opus; refund module runs its tests; 36 minutes | Fable | — | step 4 |
| Chapter 4's example gains two `rejects` tests: `mo check` found it broke its own law (`MO0311`) | Fable, found by the compiler | locked | — |
| A test is skipped only when it starts or messages a process, not because its file declares one | Fable, from Opus's default | provisional | step 4 removes the skip |
| Recipe tests that call a body-less signature are skipped until an agent implements it | Fable, from Opus's default | provisional | the three-recipe test |
| A failing test shortens the `verified:` line to `verified: types` and `mo test` exits 1 | Fable, from Opus's default | provisional | tier 3 |
| `String.size` counts code points minus combining marks, a stand-in for graphemes | Fable, from Opus's default | provisional | the stdlib chapter |
| `test rejects` also passes on a tripped `invariant` | Fable | provisional | step 4 |
| Default mailbox bound is 1_000 | Fable | provisional | `Mo.Sim` with a slow consumer |
| `ask` on a crashed, unrestarted process returns `Error(Down)` | Fable | provisional | step 4 |
| Step 4 accepted: Mo.Sim scheduler, transactions, invariants, mailbox bounds, supervisors, crash reports by Opus; milestone met; 21 minutes | Fable | — | program 1 |
| Chapter 4 corrected again by the compiler: `result` is a keyword (test binds `outcome`); the property needed `!charge.refunded?`; `RefundQueue` gains `message Done : UInt32` | Fable, found by the compiler | locked | — |
| A test's sends are delivered after each top-level statement; a `for` counts as one statement | Fable, from Opus's default | provisional | program 1's tests |
| Any process crash fails a plain test even if the supervisor restarts it; `rejects` passes on a tripped `requires`, refinement, or `invariant` | Fable, from Opus's default | provisional | program 1 |
| `ask` returns `Down` when its message was lost to a crash; a re-entrant `ask` is `Timeout` | Fable, from Opus's default | provisional | program 1 |
| A restart empties the mailbox and re-runs init; `:on_crash` behaves like `:always` for now | Fable, from Opus's default | provisional | supervisor strategies question (chapter 8) |
| Zero values: `0`, `""`, `[]`, `None`, `false`, zero `Duration`, and structs or tuples of those; `Time`, enums, capabilities, handles have none | Fable, from Opus's default | provisional | the checker should reject a missing initializer (step 5) |
| The simulated clock does not advance in step 4, so restart windows never slide | Fable, from Opus's default | provisional | the simulator step |
| `Ledger.fixture()` finds every id as an unrefunded 10_000 charge and every save succeeds | Fable, from Opus's default | provisional | program 1 |
| Wanted: `for _ in 0..n` for a loop whose index is unused; today the unused-binding law rejects `i` | Fable | provisional | step 5 |
| Formatter rules fixed in `toolchain/FORMAT.md`: 2-space indent, column 100, one blank line between declarations and after `expose`, `use` sorted, tests at the bottom, comments never moved | Fable | provisional | program 1 |
| The loop rule (pure body → combinator) is a diagnostic `MO0501`, not a rewrite; rewriting is `mo fix` | Fable | provisional | program 1 |
| `for _ in 0..n` allowed; `_` as the loop binder | Fable | provisional | the corpus |
| A `state` field with no zero value and no initializer is `MO0319` at check time | Fable | provisional | the corpus |
| `main` is a known shape, `fn main(platform: Platform)`, no return type; minimal `Platform` (args, env, stdout, stderr, fs, clock, exit) (Q18) | Robert | provisional | program 2 |
| The CLI log analyzer (menu program 2) is built before the job queue (amends Q14) | Robert | provisional | program 2 |
| Overnight run: Fable directs, Opus builds, Fable decides alone and records every decision; merge to `main` after each accepted step; whatever it takes on the worker side; Fable stays on briefs, verification, decisions, logs | Robert | locked for this run | the morning review |
| Roadmap rewritten to the 14-step list on [[roadmap]] | Fable | provisional | each step |
| Step 5 accepted: `mo fmt` with idempotence and round-trip tests, `FORMAT.md`, `MO0501` loop rule, `MO0319`, corpus formatted; 35 minutes | Fable | — | program 2 |
| Top-level blank lines are the formatter's; inside blocks the author's blank lines survive as one | Fable, from Opus's default | provisional | program 2 |
| A comment inside a multi-line paren refuses the file (`MO0502`) rather than being moved | Fable, from Opus's default | provisional | program 2 |
| Long lines break only at commas inside parens opened on that line; other long lines stay long | Fable, from Opus's default | provisional | program 2 |
| `MO0501` counts `send`, `ask`, `start`, and any call passing a capability or handle as effectful; a `break`, `return`, or `try` anywhere in the body makes it effectful | Fable, from Opus's default | provisional | program 2 |
| Step 6 accepted: `main`, `Mo.Server`, `mo run`, three programs with expected output; 21 minutes | Fable | — | program 2 |
| `Platform` is confined to `platform.<part>` reads (`MO0407`); the parts (`Out`, `Env`, `Fs`, `Clock`) are ordinary capabilities that can be passed down | Fable, from Opus's default | provisional | program 2 |
| `fn main` at module level is always the `main` production; a second `main` in a program is `MO0320` | Fable, from Opus's default | provisional | program 2 |
| `platform.exit(code)` does not stop `main`; the last code wins on return; a crash exits 70 regardless | Fable, from Opus's default | provisional | program 2 |
| `Out.write` adds no newline; a failed write is dropped | Fable, from Opus's default | provisional | program 2 |
| `fs.scoped(path)` that leaves the current scope yields an `Fs` that reads nothing; containment is checked on resolved and real paths, symlinks out are `Missing` | Fable, from Opus's default | provisional | program 2 |
| Every read failure is `Missing(path)`; over 64 MiB is `Missing`; a read that is both missing and late is `Timeout` | Fable, from Opus's default | provisional | program 2 |
| `Name.start` under `Mo.Server` crashes: no scheduler outside the test runner yet | Fable, from Opus's default | provisional | program 1 |
| Program 2 and the Go and Python control runs run in parallel, three fresh Opus sessions in three worktrees | Fable | — | the morning review |
| Program 2 accepted as an experiment result (correct with the file law lifted); the control run recorded: Mo 25.5 min, Go 12.9, Python 8; all of Mo's loss is toolchain | Fable | — | round 2 after step 8 |
| `use A.B{X, y}` imports functions as well as types; bare `use` is an error; program root is a `mo.root` marker or the main file's directory | Fable | provisional | step 7 |
| Each file keeps the 500-line law; a program is many files | Fable | locked | — |
| The VM tracks unique ownership so `push` on an unaliased `var` list is in place (Perceus-lite, chapter 7) | Fable | provisional | step 7's numbers |
| The stdlib table in `09-stdlib.md` is the worker's one wiki write; `sort_by` takes a key function because function types cannot be named; maps keep insertion order; no map literal yet | Fable | provisional | step 8 |
| Interpreter speed target for a log line: under 50 µs before optimizing further | Fable | provisional | step 7 |
| Step 7 accepted: `use` imports functions, program root, multi-file corpus programs, `push` in place, 39 µs per log line in ReleaseFast; 67 minutes | Fable | — | program 3 |
| `push` grows in place when the list ends where its buffer's last push stopped; older copies keep their length (no unique-owner bit needed under the loop rule) | Fable, from Opus's default | provisional | program 3 |
| Under `mo run`, values live in a region cleaned at safe points (return, loop iteration, combinator step); `mo test` keeps one arena per test | Fable, from Opus's default | provisional | program 3 |
| Under `mo run`, a pure call (no capability, no `inout`) is memoized on equal arguments, cache capped at 16 MiB, contract trips never cached | Fable, from Opus's default | **overturned** in step 12b: the reference interpreter runs every body and every contract every time | — |
| A `# exit:` line after a `# run:` line gives the expected exit code; stderr is not compared | Fable, from Opus's default | provisional | — |
| `MO0311` counts only `rejects` tests in the function's own module | Fable, from Opus's default | provisional | program 3 |
| `zig build` should install `mo` as ReleaseSafe by default: Mo's own overflow checks live in the VM (step 8 item) | Fable | provisional | step 8 |
| Step 8 accepted: the stdlib (numbers, strings, lists, maps, sets, time, files, output, JSON) as `09-stdlib.md` plus built-ins and seven corpus files; logstat 1,174 → 758 lines; 200k lines 60 s → 0.95 s, 440 → 38 MB; ReleaseSafe `mo`; 60 minutes | Fable | — | program 3 |
| Stdlib rules: deterministic, values in and out, rain is a value and a bug is a crash, indices are `UInt64`, slices clamp, one natural order (`<`), maps and sets iterate in insertion order and compare by order | Fable, from the chapter Opus wrote | provisional | program 3 |
| `round` and `to_string` round half away from zero on the shortest decimal spelling | Fable, from Opus's default | provisional | program 3 |
| `String.to_u64` accepts ASCII digits only, no sign, no `_`; `to_upper`/`to_lower` are ASCII-only; a grapheme is a code point plus following combining marks | Fable, from Opus's default | provisional | the stdlib chapter's next pass |
| JSON: a variant encodes as `{"Name": {fields}}`, maps with non-string keys as pairs, NaN as null; decode keeps the last value of a repeated key; depth over 512 is a syntax error | Fable, from Opus's default | provisional | program 3 |
| `Time.parse` accepts full RFC 3339, fractions truncated to ms, leap seconds are `None` | Fable, from Opus's default | provisional | program 3 |
| `Fs.list` returns files and folders sorted byte by byte | Fable, from Opus's default | provisional | program 3 |
| Step 9 accepted: seeded scheduling, fault injection, `never` over `T.all` under sim, `sim (N runs)`; refund holds under 100 seeds; racy.mo fails only under sim with an interleaving and a replay command; 45 minutes | Fable | — | program 3 |
| `--sim N` (default 100) runs after the fixed-order run passes; run i uses seed S+i; `--seed S` replays one; `--faults P` (default 5%); scheduling and faults draw separate streams | Fable, from Opus's default | provisional | program 3 |
| An `ask` times out only when its target spent past the deadline on slow or failed capability calls, never by chance | Fable, from Opus's default | provisional | program 3 |
| "Passes only without faults" counts as a pass, printed with its seed; `never` blocks are checked only at the end of seeded runs | Fable, from Opus's default | **overturned** in step 12b for the second half: every `never` runs on every test | — |
| `T.all` records struct constructions, copies, fixtures, and capability results; enums and primitives are not yet recordable | Fable, from Opus's default | provisional | program 3 |
| Step 10 accepted: `.mo.ids` sidecar and `mo test --write`, `mo fix` (three loop shapes, unused binding, default parameter), `spec/errors.md` generated from the tables (59 codes), README front door; 60 minutes | Fable | — | program 3 |
| Sidecar: one `.mo.ids` per program root, JSON, declaration ids are 12 hex digits of a hash of module and name, declaration hash is SHA-256/64 over tokens; a `verified:` line is stale only when its own file's declarations change | Fable, from Opus's default | provisional | program 3 |
| `mo test --write` writes even on failure (`verified: types`, exit 1) and writes the `proven:` line too | Fable, from Opus's default | provisional | tier 3 |
| `mo fix` rewrites a pure loop only for the map, filter, and reduce shapes over a list with one statement; other pure bodies stay a diagnostic with no fix | Fable, from Opus's default | provisional | program 3 |
| The usage line in `mo` must list `fmt` and `fix` (they work; the text is stale): a step 11 item | Fable | provisional | step 11 |
| Step 11 accepted: processes under `mo run`, `Net` (listen, accept, connect, read_line, write, close), direct style over blocking calls without stopping the scheduler, `Net.fixture`, echo over a real socket; 1,000 round trips in 56 ms; 62 minutes | Fable | — | program 3 |
| `Sup.start(args)` returns its one child's handle or a tuple of them in child order; nothing names the supervisor | Fable, from Opus's default | provisional | program 3 |
| After `main` returns, the run continues until no message waits; the exit code is `main`'s; a supervisor giving up exits 70 | Fable, from Opus's default | provisional | program 3 |
| A program with processes runs without the value region and without memoization (mailboxes hold values the region cannot see) | Fable, from Opus's default | provisional, a cost to measure | program 3 |
| `listen` binds 127.0.0.1 only; port 0 picks a free port and `listener.port` reports it; `SO_REUSEADDR` only | Fable, from Opus's default | provisional | program 3 |
| Deadline outcomes: `accept` keeps listening, `connect` leaves nothing, `read_line` keeps the partial line, `write` closes the connection | Fable, from Opus's default | provisional | program 3 |
| A `Conn` in a process's start arguments closes when that process crashes or its supervisor gives up; listeners stay open | Fable, from Opus's default | provisional | program 3 |
| Program 3 accepted as an experiment: kv answers 15k GETs/s, holds under sim, but cannot persist (no file write) and leaks per request; six toolchain bugs; corpus test red until fixed | Fable | — | step 12 |
| `main` stays green: session-05 is not merged while `zig build test` fails | Fable | locked | — |
| The runtime under real programs (step 12) comes before the C backend (now step 13) | Fable | provisional | step 12's numbers |
| A function may omit its return type when it returns nothing, like `main` | Fable | provisional | step 12, the corpus |
| A negative integer literal is a pattern | Fable | provisional | step 12 |
| `String.byte_size`; `Fs.write`, `append` (fsync), `remove`, `rename`; `Out.flush`; `Out.fixture()` with `out.written` | Fable | provisional | step 12, kv's replay test |
| Maps and sets gain a hash index; insertion-order semantics unchanged | Fable | provisional | step 12's `map-100k` row |
| Memoization and never-only-under-sim to be reversed in step 12b: the reference interpreter runs every body and every contract every time; every `never` runs on every test, and one that cannot be checked is `MO0324` | Fable, after unpacking both for Robert | provisional, overturns two earlier rows when 12b lands | step 12b |
| Robert (session 5, morning): Fable's recommendations are the decisions; do whatever Fable would do, always documented for later review; "we are super early, there are no mistakes, this is uncharted territory and we are learning as we go" | Robert | locked | — |
| Step 12 accepted: program discovery, hashed maps, in-place state writes, per-request freeing, file writes with fsync, optional return type, negative patterns, `byte_size`, `mo fmt` fuzz-clean, four diagnostics reworded; kv durable across restart; 50k SETs leave the server at 19 MB; 80 minutes | Fable | — | step 13 |
| Corpus rules replace counts: every simulated process test outside racy.mo must hold under faults; recipe skips are the only allowed skips | Fable, from Opus's default | provisional | — |
| Map index is open addressing from 8 keys; in-place writes extend to field paths under any `var`; a crashed `update`'s in-place writes are undone; a process whose invariant reads `old(state)` is never written in place | Fable, from Opus's default | provisional | step 13's differential tests |
| Messages, replies, start arguments, and first state are deep-copied between processes; each process reserves up to 16 GiB of address space; the region compacts when it doubles | Fable, from Opus's default | provisional | a day-long kv run |
| `Fs.write` and `append` fsync; a write past its deadline stays written; rename replaces; a read-only `Fs` passed as a parameter is enforced at run time, not check time | Fable, from Opus's default | provisional, the check-time gap is a step 13 item | step 13 |
| `Out.written` is tests-only and `Out.flush` is a no-op in tests | Fable, from Opus's default | provisional | program 4 |
| Step 12b accepted: memoization removed (logstat-4k 12 → 80 ms, accepted), every `never` runs at the end of every test over recorded values, `MO0324` for an uncheckable `never`, a `never` trip satisfies `test rejects`; 25 minutes | Fable | — | step 13 |
| Values are recorded where held (bindings, parameters, binders, constructions, state fields), inside collections; a type the recorder cannot see (a generic `T`) is a gap, not an error | Fable, from Opus's default | provisional | program 4 |
| Control run round 2 recorded: Mo 11.8 min (from 25.5), Go 8.2, Python 7.9; Mo zero loops to green; the rest of the gap is `mo fmt` line breaking and five stdlib rows | Fable | — | round 3 after the formatter fixes |
| Formatter follow-ups (from round 2): break long list literals and calls outside parentheses; keep one-line anonymous functions inside long calls; `sort_by` descending, two-value `min`/`max`, streaming read | Fable | provisional | step 14 |
| Step 13 accepted: C runtime, emitter from the checked tree, `mo build` via `zig cc`, differential tests over the corpus (57 identical, 0 differences), read-only `Fs` refused at check time; logstat native: 200k lines in 0.14 s (interpreter 0.95 s), logstat-4k 6.8 ms vs 44.6 ms; 83 minutes | Fable | — | program 4 |
| Contracts off by default in `mo build` | Opus's default | **overturned** on acceptance: chapter 3 says contracts run in every build; step 14 makes them on by default with `--no-contracts` for measurement | step 14 |
| One 16-byte tagged value in C; `case` as test chains; Mo locals at the top of each C function for the compactor; the interpreter's region model ported as is | Fable, from Opus's default | provisional | program 4 |
| Processes and `Net` are refused by `mo build` in this step, not compiled to crash | Fable, from Opus's default | provisional | step 15: processes in the C backend |
| Linux targets link static musl; macOS links libSystem only; `zig` found next to `mo` then on PATH; nothing cached between builds | Fable, from Opus's default | provisional | program 4 |
| Overflow checks and asserts are always on in every binary | Fable, from Opus's default | locked (chapter 2) | — |
| A read-only `Fs` is its own type unifying with `Fs`; the checker infers which functions write through which `Fs` parameters; not followed through `Process.start` | Fable, from Opus's default | provisional | step 15 |
| Step 14 accepted: contracts on in every build (`--no-contracts` for measurement; logstat-4k-c 8.9 ms with, 6.2 ms without), three interpreter panics reproduced and fixed, the formatter's round-2 shapes, `sort_by_desc`, `min_of`, `max_of`, `Fs.each_line`, housekeeping; 45 minutes | Fable | — | round 3 of the control run |
| Contract cost in native code is measured at about 40 percent on logstat's hot path; recover by contract-proved bound elision later (chapter 7), never by turning contracts off | Fable | provisional | tier 3 proving |

| Step 15 accepted: the scheduler and `Net` in the C runtime, `mo build` compiles every program, the differential test covers every process module and `echo` and `kv`; native echo-1k 33.9 ms (interpreter 52.2), kv-10k-get 345 ms (476), kv after 50k SETs 19.2 MiB (37.4); crash reports, deadline outcomes, and a failing test binary identical to the interpreter on programs the brief did not name; aarch64 Linux static binary; 40 minutes | Fable | — | program 4 |
| Under `main`, each process runs on a thread of its own with a 16 MiB stack and the threads take turns; a call that waits gives up its turn; while `main` waits, one thread per blocked call watches the socket | Fable, from Opus's default | provisional, a cost to measure | a day-long kv run |
| A native socket call tries its socket first and gives up its turn only when it is not ready; the interpreter always gives up the turn; the two must print the same | Fable, from Opus's default | provisional | the differential test under load |
| Undo of a crashed `update` in the C runtime treats as older anything not allocated in the current region since the update began; the interpreter compares addresses | Fable, from Opus's default | provisional | program 4 |
| `mo test --sim` has no compiled form: a `--tests` binary runs the fixed order only, the seeded runs stay the interpreter's | Fable, from Opus's default | provisional | — |
| kv's memory row is 50,000 SETs of distinct keys from one client, each waiting for its OK, on an empty log; `kv-50k-set-rss-kib` holds KiB and its name says so | Fable, from Opus's default | locked as the method | every later kv row |
| Two interpreter behaviours ported as they are: a process started directly with no single matching child line takes the last supervisor with one; a skip inside `update` propagates as a skip | Fable, from Opus's default | provisional; the first is a smell and becomes a check-time diagnostic (one child line per process) in a later step | program 4 |
| Step 16 is HTTP in the stdlib, before round 3 of the control run, so program 4's spec can follow; round 3 runs after step 16 in its own worktrees | Fable | provisional | step 16 |
| HTTP v0: `Http` over `Net`, HTTP/1.1 only, no TLS, one request per connection (`Connection: close`), bodies by `Content-Length` only, `Request` and `Response` as structs, a server that `accept`s exchanges and a client that `send`s requests, `Http.fixture()` in tests, both runtimes, differential | Fable | provisional | step 16, program 4 |

| Step 16 accepted: `Http` over `Net` in the interpreter and the C runtime, `## Http` in the stdlib, `effects/http.mo` and `stdlib/http.mo`, `programs/httpd` identical under both runtimes; native http-1k 58.5 ms (interpreter 98.4), servers at 2.4 and 4.6 MiB after 1,000 requests; fourteen curl and raw-socket cases of Fable's own (chunked, a 2 MiB body, garbage, HTTP/2.0, two content-lengths, a stalled client) identical under both; 65 minutes | Fable | — | program 4 |
| The HTTP wire: HTTP/1.0 requests are read and answered as 1.1, any other version is `Unsupported`; 1 MiB each for the request line, the headers, and the body; any `transfer-encoding` is `Unsupported`; a request with no `content-length` has an empty body and a response with none runs to the end of the stream; repeated headers join with `", "`; query keys decode `+` and `%XX` and the last repeated key wins; strings hold the bytes as they came; `Conn` gains no row, the body is read from the buffer | Fable, from Opus's default | provisional | program 4 |
| A failed `accept` answers the client `400`, `413`, or `501` and closes it; `accept`'s deadline covers the whole request, so one slow client holds the acceptor for its deadline | Fable, from Opus's default | provisional, a known cost: if program 4 needs it, `accept` hands over the connection before the request is read | program 4 under load |
| The prelude structs `Request` and `Response` may be built without their empty fields (`headers`, `query`, a request's `body`); a module's own `Request` or `Response` hides the prelude's in that module and the `Http` rows still use the prelude's | Fable, from Opus's default | provisional, flagged: the first fields with a default outside `state`; the rule stays prelude-only until a question settles struct defaults | program 4 |
| `reply`: a status outside 100 to 599 or a bad header is `Malformed` and writes nothing; a second reply is `Closed`; reading `exchange.request` after the reply is a crash; the runtime writes `content-length` and `connection` itself and drops the program's; reason phrases for the common statuses only | Fable, from Opus's default | provisional | program 4 |
| `send` writes `host` unless given one and percent-encodes the query; in a test, `send` delivers the processes' waiting messages a round at a time until the response is whole, `Timeout` when none waits; under `--sim`, `accept` and `send` time out by the seed and `reply` and `send` find the connection `Closed` by the seed | Fable, from Opus's default | provisional | — |
| A request's bytes are freed at the reply; an exchange never answered keeps them until the run ends | Fable, from Opus's default | provisional, a cost to measure | program 4 |
| The http bench rows: 1,000 `GET /hello` to `httpd serve`, one connection per request, from a Zig client, interpreter and binary; resident memory by `ps` after them, in KiB, both runtimes | Fable, from Opus's default | locked as the method | every later http row |
| Round 3 of the control run starts after step 16: worktrees `control3-mo|go|python` from `session-05`, the round 2 implementations removed, the same briefs, agents `mo-r3-*` | Fable | — | round 3's table |

| Control run round 3 recorded: Mo 9 loops to green (6 of them syntax or law diagnostics, 1 real bug, 2 test mistakes) against Go 2 and Python 1; Mo's checks caught a real bug twice (a test and a `never`), the first time in any round; wall-clock void for Mo and Go, the machine slept mid-run; 851 Mo lines to Go's 1,387 | Fable | — | round 4 after step 17 |
| `any(T)` for a refined `T` generates only values the refinement admits; a refinement that admits none of the candidates is a diagnostic, never a value that breaks it | Fable | locked (chapter 5: a refinement is a contract) | step 17 |
| A `String` is UTF-8: an `Fs` row that reads text returns `NotText` for a file that is not, and a program that wants the bytes asks for them by a row that says so | Fable | provisional | step 17 |
| Step 17, the round 3 follow-ups (`any(T)` under refinements, `NotText`, a fold over lines, `MO0101` and the other five diagnostics the run tripped reworded), comes before program 4; the program 4 spec is written meanwhile | Fable | provisional | program 4 |

| Step 17 accepted: `any(T)` honours refinements in both runtimes with `MO0325` when a `where` admits nothing, `NotText` and `Fs.read_bytes`, `Fs.fold_lines`, six diagnostics say what to write instead; verified on a refined type of Fable's own under both runtimes, an unsatisfiable `where`, a bad-byte file through all three rows under both runtimes, the six sentences tripped by hand; 35 minutes | Fable | — | round 4, program 4 |
| `any(T)` on a refined type tries 100 base values, then 100 from the integer bounds a `where` of `value <op> integer` clauses joined by `and` states, hitting each edge a fifth of the time; `MO0325` after 200 misses | Fable, from Opus's default | provisional | round 4 |
| `NotText` carries no path; fixtures and `Mo.Sim` faults cannot produce it, since `write` takes a `String`; `read_bytes` returns `List(UInt8)` for want of a `Bytes` type; `fold_lines(path, init, fn, within:)` returns `Ok(init)` on an empty file | Fable, from Opus's default | provisional; a `Bytes` type is a later question | program 4 |
| Robert (13 Sep, on the outside review): the laws and the no-`while` rule stay as they are; "we need to test and see what happens and can reevaluate later"; findings and decisions are documented as baselines for later comparison | Robert | locked until re-evaluated against a control run | round 4, program 4 |
| The outside review's no-compat fixes go to step 18 before program 4: `invariant` flipped to "stays true", `Handle(T)` counts as a capability, a capability captured in an anonymous function refused, a stack overflow is a Mo crash report, grouped patterns `A | B: body`, map and set equality by content, the sidecar's cache key over transitive bodies, a discarded pure call value refused, and `--faults` that stop injecting partway so a test can assert progress after faults | Fable | provisional | step 18, program 4 |
| Decision-log rows touching failure, authority, equality, persistence, or scheduling carry the tag `semantic`; a `provisional` row names what first tests it and is re-read at that test; Robert reads the `semantic` rows, not the queue | Fable, after the outside review | locked | every acceptance from step 18 |
| The failure model (what survives a crash, what timeout means, when a reply means durable, poison messages, retry limits, cleanup on crash) is written by Fable as chapter 3's next section before program 4's `--sim` claims are read | Fable | provisional | program 4 |
| Deadlines as budgets (an absolute deadline at the operation boundary that nested `within:` calls inherit and may tighten) is program 4's experiment, not a rule yet | Fable | provisional | program 4 |

| Step 18 accepted: the outside review's no-compat fixes; verified with a natural invariant of Fable's own that trips when false, a handle captured in a closure refused (`MO0409`) beside its dropped `map` value (`MO0310`), 50-million-deep recursion crashing with a Mo report and exit 70 under both runtimes, a grouped arm binding a name under both runtimes and a mismatched binding refused, maps and sets equal across insertion order, a body edit tripping `MO0317`, `--until` turning `sim.mo` from "passes only without faults" to held; 55 minutes | Fable | — | round 4, program 4 |
| `semantic`: an `invariant` holds after every `update` and trips when false; the report says "no longer holds in" | Fable, from the review | locked (chapter 3) | — |
| `semantic`: `Handle(T)` is a capability: holding one makes a function effectful, using one with no capability parameter is `MO0403`, a handle in a struct, state, or message field is refused, a handle may be returned, a recipe's `needs` lists capabilities only, `flows(T, into: Handle(P))` covers sends and asks; an anonymous function that captures a capability or handle is `MO0409`; a dropped value from a pure call, a bare dot call included, is `MO0310` | Fable, from Opus's default | provisional | program 4 |
| `semantic`: calls nest at most 10,000 deep per thread, counted through closures, contracts, invariants, updates, and an `ask` running another process inline; past it a crash report and exit 70; the interpreter runs `main` and each process on 256 MiB of reserved stack | Fable, from Opus's default | provisional, the number to measure | program 4 |
| Grouped patterns are arm-only (`A | B: body`), every alternative binds the same names of the same types or none; `is` takes one pattern; grouped `update` arms replying with different types are `MO0212` | Fable, from Opus's default | provisional | round 4 |
| `semantic`: maps and sets are equal, and hash, by content, not insertion order; iteration order stays insertion order | Fable, from the review | locked (chapter 3) | — |
| The sidecar hashes every used module's declarations minus its tests, so any body change in a used module stales the caller's `verified:` line, even one its tests never reach | Fable, from Opus's default | provisional, coarse by design | program 4 |
| `--until F` is a fraction of the fixture calls that could fail, counted on a faults-off run of the same seed first, so a seeded run costs twice; a `# sim: --faults P --until F` line at the top of a file sets the corpus test's options for that file | Fable, from Opus's default | provisional | program 4 |
| `Fs.each_line`'s callback can reach no capability now that capture is refused, so the row is dead; it is removed, or takes a value, in a housekeeping step; `fold_lines` is the streaming row | Fable | provisional | housekeeping |
| Program 4 (`notes`) starts on the toolchain after step 18; the failure model (chapter 3) is written and is what its `--sim` claims are read against | Fable | — | program 4 |

| Program 4 accepted: `notes` in 55 minutes, eight modules, `--sim 100` green, identical native; native creates 7,621/s and gets 23,692/s with 32 clients, 103 MiB at 100k notes, a 1M-line replay in 6.3 s; the recipes saved a design and cost a conformance gap; two runtime findings and seven gaps go to step 19 | Fable | — | step 19, program 1 |
| `semantic`: a started process is never freed today (a thread and about 30 KiB each, for the program's life), so a process per request is not a shape a program can use; step 19 frees a process that no live process or `main` holds a handle to once its mailbox is empty, handles being values the runtime can count across copies; a process a supervisor names by a `child` line is never freed | Fable, after program 4's bug 1 | provisional, the rule to measure | step 19, program 1 |
| `semantic`: sends from inside `update` are held until the update ends (chapter 3), so an `update` that starts a process and waits for its reply deadlocks; step 19 makes the runtime crash the waiting process with a report naming the held message instead of hanging | Fable, after program 4's bug 2 | provisional | step 19 |
| A recipe may hold `never` blocks; `mo check --recipe Module.Recipe file.mo` checks an implementation's exposed signatures against the recipe and runs the recipe's tests against it, so recipes stop drifting from implementations | Fable, after program 4's gap | provisional | step 19, program 5 |
| `Fs.mkdir`, and `mo run --clock <ISO-8601>` giving `main` a clock that starts there and advances with the wall, so a transcript over real sockets can be replayed | Fable, after program 4's gaps | provisional | step 19 |
| A capability cannot travel in a message; a process gets one only as a start argument (chapter 3); program 4 wanted to hand an `Exchange` to a live worker, and the answer is freeing finished processes, not capabilities in messages | Fable | provisional, re-read after step 19 | program 1 |
| Program-level defaults the worker chose (a refill-all-at-once limiter, ids reserved in blocks of 100, `<token>/n_<id>` store keys, 404 across clients, 503 on a torn log, 30 s from acceptor to service) stand as `notes`'s own; none is a language rule | Fable, from Opus's defaults | provisional | program 1's shape |

| Robert (13 Sep, evening, after Fable unpacked the three answers to the fictional-bound loops): the runtime owns the loop; no `loop` keyword; the laws stay | Robert | locked until round 4 re-evaluates the laws | step 20 |
| `semantic`: `Net.serve(listener, into: handle, idle:)`, `Conn.lines(into: handle, idle:)`, and `Http.serve(listener, into: handle, idle:)` make the runtime accept, read, and deliver: each connection, line, or exchange arrives at the named process as a message (`Accepted`, `Line`, `Closed`, `Idle`); the runtime stops reading a socket while the target mailbox is near its bound, so overload is backpressure, not a crash | Fable, Robert agreed | provisional | step 20, program 1 |
| `semantic`: a message may carry a capability or a handle when its `message` line declares the field, and a sender may put in it only what it holds; the process's protocol shows what authority it receives, so direction 31 holds; step 18's refusal of capability fields in messages is reversed for declared message fields only, struct and state fields stay refused | Fable, Robert agreed | provisional | step 20, program 1 |
| Threads: a process is still an OS thread, so a process per connection holds to a few thousand connections; green threads are the chapter 7 memory step, after step 20 | Fable | provisional, the number to measure | step 20's rows, the memory step |

| Step 19 accepted: a finished process is freed (the reproduction runs 200,000 processes at 21 MB interpreted and 9 MB native, where 20,000 ran out of memory before; a worker per exchange serves 20,000 requests at 18 and 9 MB), the held-send deadlock is a crash report, `mo check --recipe` (a missing signature is `MO0326`, a changed type fails the recipe's own tests), `Fs.mkdir` and `mo run --clock` (the same transcript twice), three diagnostics reworded, `each_line` gone, mutation tests 9 of 10 caught; 75 minutes | Fable | — | step 20, program 1 |
| `semantic`: a process started by a `start` call ends once its mailbox is empty, no `update` of it runs, and no handle to it is reachable from `main`'s frames, a running `update`, a live process's start arguments, a held send, or an untaken reply; a sweep on `main`'s thread every 64 quiet events; a process a `child` line names is never freed; freeing happens under `main` only, not in `mo test`; ids are reused last-ended-first and up to 64 threads are kept; a freed process's connections are not closed | Fable, from Opus's default | provisional; the counting costs under 2 percent on the bench rows | step 20, program 1 |
| `semantic`: the held-send rule: an `update` waiting in `accept` on a listener, or `read_line` on a connection, whose only way to progress is a send this `update` holds, crashes with a report naming the message; an `ask` counts through such a wait; a doomed asker crashes when its `ask` returns | Fable, from Opus's default | provisional | step 20 |
| `semantic`: since step 18 a process with no capability parameter cannot start another (`MO0403`), so starting a process is an effect nothing names; step 20 decides: a process may start any process its own supervisor names as a `child` without a capability, and a function still needs one | Fable, found by a probe | provisional, flagged | step 20 |
| The recipe check compares types by printed name, `requires` as the same set, `ensures` as a superset, keeps the implementation's own `test rejects` and identical `never`s, and finds the recipe module under the root or above it; a `# recipe:` line is honoured by the corpus test but not by a plain `mo check`, which step 20 fixes | Fable, from Opus's default | provisional | step 20 |
| `Fs.mkdir` makes one level and is `Ok` on an existing folder; `MO_CLOCK` gives a built binary the fixed clock `--clock` gives `mo run`; `notes check` keeps masking timestamps since the clock still advances between runs | Fable, from Opus's default | provisional | program 1 |
| Mutation testing found the one contract the corpus cannot catch: an `invariant` that reads `old(state)` with its witness removed passes when every test drives the state forward; rule for step 20: an `invariant` that mentions `old` needs a `test rejects` that trips it, as a `requires` needs one (a new `MO03xx`) | Fable | provisional, a law candidate for round 4's re-evaluation | step 20 |

## Related
- [[session-05]]
- [[model-bakeoff]]
- [[roadmap]]
