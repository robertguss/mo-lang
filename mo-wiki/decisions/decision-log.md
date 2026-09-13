---
title: "Decision log"
created: 2026-09-12
updated: 2026-09-12
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
| Under `mo run`, a pure call (no capability, no `inout`) is memoized on equal arguments, cache capped at 16 MiB, contract trips never cached | Fable, from Opus's default | provisional, watch closely | program 3; revisit if any semantic surprise appears |
| A `# exit:` line after a `# run:` line gives the expected exit code; stderr is not compared | Fable, from Opus's default | provisional | — |
| `MO0311` counts only `rejects` tests in the function's own module | Fable, from Opus's default | provisional | program 3 |
| `zig build` should install `mo` as ReleaseSafe by default: Mo's own overflow checks live in the VM (step 8 item) | Fable | provisional | step 8 |

## Related
- [[session-05]]
- [[model-bakeoff]]
- [[roadmap]]
