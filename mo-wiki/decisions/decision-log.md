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

## Related
- [[session-05]]
- [[model-bakeoff]]
- [[roadmap]]
