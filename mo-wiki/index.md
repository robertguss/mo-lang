---
title: "Mo"
type: index
---

# Mo Lang — Index

> **Start here.** [[state-of-the-project|The state of the project]] is the whole picture, rewritten at every pause. The maps of content gather the pages behind it: [[the-thesis-and-its-evidence|the thesis and its evidence]], [[the-rounds|the rounds and the measurements]], [[the-language|the language]], [[the-runtime|the runtime]], [[the-programs|the programs]], [[for-robert|for Robert]], [[how-we-work|how we work]]. The [[roadmap]] table is the authority on order; the [[decision-log]] is what Robert reads.


> Every wiki page, one line each. Read this after SCHEMA.md to find pages for any question.
> Last updated: 2026-09-13 | Total pages: 137
> Last updated: 2026-09-13 | Total pages: 160

## Directions we like
- [[d01-agents-write-the-code|Direction 1: Agents write nearly 100% of the code]] — Humans no longer write or closely review code
- [[d02-spec-altitude|Direction 2: Human-readable, but at a higher altitude]] — Mo stays readable by humans because it is the shared language of understanding, but humans read intent, contracts, and effects, not bodies
- [[d03-source-carries-its-evidence|Direction 3: The source carries its own evidence]] — Since review is gone, trust comes from what the compiler can check: contracts, effects, tests bound to requirements, proofs
- [[d04-style-rules-become-laws|Direction 4: Style rules become laws, possibly with no escape hatch]] — Everything Tiger Style and Power of 10 enforce socially, Mo's compiler enforces
- [[d05-old-ideas-rethought-ai-first|Direction 5: Old ideas, rethought AI-first]] — Much of what works is decades old (Tiger Style, Power of 10, contracts, simulation testing)
- [[d06-never-oop|Direction 6: Never OOP. No classes]] — Functional and procedural style
- [[d07-elixir-flavored-functional|Direction 7: Elixir-flavored functional, not Haskell-pure]] — Pragmatic functional style
- [[d08-beam-qualities-without-the-beam|Direction 8: BEAM qualities without the BEAM]] — Compile to a single static binary, memory-efficient like Rust or Go
- [[d09-primary-inspirations|Direction 9: Primary inspirations: Rust, Go, Elixir/BEAM, Elm]] — , plus anything else worth stealing
- [[d10-immutable-by-default|Direction 10: Immutable data by default]] — Gives agents locality of reasoning: to understand a function you need only the function
- [[d11-statically-typed|Direction 11: Statically typed]] — Inferred inside bodies, required at every function boundary
- [[d12-concurrency-at-the-edges|Direction 12: Concurrency at the edges, like Go]] — Most code is plain functions on immutable data; isolated processes are a tool for concurrency and fault isolation, not the primary progra…
- [[d13-local-var-and-inout|Direction 13: Local `var` with mutable value semantics, plus `inout` parameters]] — In
- [[d14-processes-are-the-only-identity|Direction 14: Processes are the only identity, and each is an Elm-shaped state machine]] — State + message type + pure `update` returning new state and effect commands
- [[d15-effects-via-capabilities|Direction 15: Effects via capabilities, no effect type system]] — A function is pure unless it takes a capability parameter
- [[d16-direct-style-io|Direction 16: Direct-style I/O with runtime interception]] — `fs.read(path)` reads like Go and blocks like Erlang, but compiles to "suspend, hand a command to the runtime, resume with result." The r…
- [[d17-mandatory-deadlines|Direction 17: Every effectful call carries a mandatory deadline]] — Bounded waits, extending Power of Ten's bounded loops
- [[d18-two-kinds-of-failure|Direction 18: Two kinds of failure, two mechanisms, never crossing]] — Expected failure ("rain") is an `Err` value, exhaustive, in the signature, handled by the caller
- [[d19-negative-space-is-the-contract|Direction 19: Negative space is the human-agent contract]] — Humans write nothing, not even the spec
- [[d20-human-pulled-in-when-shape-changes|Direction 20: A human is pulled in when the shape changes]] — Agents add, rewrite, and refactor freely
- [[d21-autonomous-crash-fixing|Direction 21: Production crashes are fully autonomous]] — A tripped `never` or contract crashes the process, the supervisor restarts it, and the agent takes the crash as a task and fixes it with …
- [[d22-rust-plus-refinements-types|Direction 22: Type system: Rust-plus-refinements from day one]] — Traits (without the deep solver machinery), enums with data, generics with bounds, exhaustive matching, plus refinement types on primitiv…
- [[d23-compile-speed-first-class|Direction 23: Compile speed is a first-class requirement]] — The compile time is the latency of the agent's loop; a slow teacher gets ignored
- [[d24-compile-to-c-via-zig|Direction 24: Compilation target: C via the Zig toolchain for release, own fast backend for the edit loop]] — Zig toolchain as the only dependency (Tiger Style), trivial cross-compilation and static linking
- [[d25-interpreter-for-the-edit-loop|Direction 25: Fast path is an interpreter, never shipped]] — Build order: (1) bytecode interpreter for the edit loop, also the executable reference semantics and the host for the simulator, replay, …
- [[d26-developer-and-agent-happiness|Direction 26: Optimize for developer happiness AND agent happiness]] — Robert's favorite language to read and write is Ruby (Matz's "developer happiness")
- [[d27-simple-and-elegant-like-ruby|Direction 27: Design principle (Robert's words)]] — the language needs to be as simple as possible and elegant like Ruby and Python
- [[d28-nothing-final-until-measured|Direction 28: Nothing is final until it is measured]] — (Robert, session 2) Every decision here — especially the performance-shaped ones — stands only until a benchmark, eval, or test says othe…
- [[d29-edit-by-declaration-id|Direction 29: Agents edit by declaration ID, not by text position]] — (Robert: in, session 2, “fascinating”) Every declaration gets a stable ID in a toolchain-owned `.mo.ids` sidecar; source stays plain text…
- [[d30-supply-chain-security|Direction 30: Supply-chain security is a first-class design goal]] — (Robert, session 2, very important) AI has made package-ecosystem attacks (npm, PyPI, and the rest) massive and unlike anything before
- [[d31-effects-never-hide-in-a-value|Direction 31: Effects never hide in a value]] — (session 3, tension 1) anonymous fns are call-arguments only, captures read-only; a captured capability can't outlive the call
- [[d32-proving-is-a-separate-tool|Direction 32: Proving is a separate tool; tier 3 v0 is testing in the interpreter]] — (session 3, tension 4) property tests + simulation in the interpreter; `mo prove` vendors a solver outside the zero-dep law
- [[d33-bounded-mailboxes|Direction 33: Bounded mailboxes; `send` never blocks; overflow is a roof]] — (session 3, tension 5) `mailbox: N` per process, sender crashes on overflow, backpressure via `ask`
- [[d34-packages-are-recipes|Direction 34: Packages are recipes; the spec is shared, the bodies are yours]] — (Robert, session 3, to be proven) stdlib is the bricks, a package is the booklet, the agent builds it in your repo; zero dependencies by construction
- [[d41-small-model-round|Direction 41: The small-model round]] — (Robert, 15 Sep) rerun the control run's reliability and loop measures with smaller models; speed, memory, and dependencies do not move with the model, the two that do are where the checks would first earn their keep
- [[d42-elixir-round|Direction 42: The Elixir round]] — (Robert, 15 Sep) round 10: the BEAM null hypothesis run in a pane, round 7's job queue and round 8's change in Elixir, read on reliability, the loop, dependencies, and the runtime rows
- [[d43-five-measurements|Direction 43: Five measurements]] — (Fable, 15 Sep evening, at Robert's request to drive) bodies as cache, sampling as verification, the erosion round, the incident round, tokens and first-fix rate as columns; the unfamiliarity tax named as the risk against the thesis
- [[d40-structured-runtime-events|Direction 40: Structured runtime events, not log lines]] — (outside session, 13 Sep) every scheduler, supervisor, capability, and mailbox event with a schema; feeds the MCP surface and the crash report
- [[d39-hot-code-reload|Direction 39: Hot code reload]] — (Robert, 13 Sep) swap a module's code under running processes; state migration is the design work
- [[d38-time-travel-debugging|Direction 38: Time-travel debugging for Mo processes]] — (outside session, 13 Sep) snapshots plus the message log as a stepwise query interface; mostly built under mo test
- [[d37-runtime-mcp-surface|Direction 37: Runtime MCP surface — every Mo program is queryable]] — (Robert, 13 Sep, "the ability to debug a process") list, inspect, query, pause a running process; must be a capability
- [[d36-vm-first-runtime|Direction 36: VM-first runtime, C backend as an optimization]] — (Robert, 13 Sep, "you are beginning to persuade me") the VM as the reference, native as ahead-of-time compilation of it; the frame for d37–d40
- [[d35-mo-is-an-ecosystem|Direction 35: Mo is an ecosystem; first-party batteries you own]] — (Robert, session 3) Laravel model for first-party tooling, Phoenix-auth/shadcn model for kits you own; three shelves: bricks, kits, recipes

## Open questions
- [[q01-comments|Q1: Comments]] — ✅ in — Options: `#` (Ruby, Python, Elixir) or `//` (Rust, Go, C)
- [[q02-strings-and-interpolation|Q2: Strings and interpolation]] — ✅ in — Options: Ruby `"Hello #{name}"` / Python `f"Hello {name}"` / Rust `format!("Hello {name}")`
- [[q03-numbers-and-units|Q3: Numbers and units]] — ✅ in — Options: plain numerals only / numerals with unit suffixes as methods (`200.ms`, `90.days`) / a full units system
- [[q04-integer-types-and-overflow|Q4: Integer types and overflow]] — ✅ in — Options: wrap silently (C, Go) / crash on overflow (Rust debug, Zig safe modes) / checked types that return `Option`
- [[q05-option-and-no-nil|Q5: Option and the absence of nil]] — ✅ in — Options: `Option(T)` with `Some`/`None` (Rust) / `Maybe` with `Just`/`Nothing` (Haskell, Elm) / a `T?` shorthand (Swift, Kotlin)
- [[q06-verified-line|Q6: The `verified by` line]] — ✅ in — Options: written by the agent as a claim / computed by the compiler and displayed / both
- [[q07-process-api|Q7: Process API syntax: spawn, send, receive, supervise]] — ✅ in — Recommendation:
- [[q08-verification-tiers|Q8: The verification dial in practice]] — ✅ in — Question: what checks run when, and what does an agent wait for?
- [[q09-compiler-diagnostics|Q9: Compiler diagnostics as the agent's teacher]] — ✅ in — Question: what does an error look like?
- [[q10-semantic-ids-and-editing|Q10: Semantic IDs and how agents edit Mo]] — ✅ in — Question: do agents edit text, or the tree?
- [[q11-platform-and-stdlib|Q11: The platform concept and the standard library]] — ✅ in — Question: where do I/O primitives live, and how batteries-included is Mo?
- [[q12-law-numbers|Q12: Law numbers]] — ↩ counter — Question: the concrete limits behind the laws
- [[q13-implementation-language|Q13: Implementation language for the Mo toolchain]] — ✅ in — Options: Zig / Rust / OCaml / Go
- [[q14-first-real-program|Q14: The first real program]] — ✅ in — Options (from session 1): agent harness / backend service with a DB / infrastructure component (queue, KV store, proxy) / the Mo toolchai…
- [[q15-the-name|Q15: The name]] — ✅ in — Question: is "Mo" it, and what's the story?
- [[q16-escape-hatch|Q16: Escape hatch, revisited]] — ✅ in — Question: parked in session 1: laws with no override, ever?
- [[q17-package-management-and-supply-chain|Q17: Package management and supply-chain security]] — ✅ in (session 3: six-layer design, plus aube additions) — Raised by Robert (session 2), flagged as very important
- [[q18-main-and-the-platform|Q18: The shape of main and the first real platform]] — main as a known shape like update; minimal Platform; CLI log analyzer before the job queue

## Decisions
- [[decision-log|Decision log]] — every choice in order, who made it, status, what first tests it

## Syntax picks and examples
- [[base-example|Current base example (Robert's style)]] — ```ruby
- [[draft-example-ruby-shaped|Draft example, Ruby-shaped (superseded)]] — ```ruby
- [[full-example-q1-q7|Full example with Q1–Q7 applied]] — This is the base with every pick applied, including Q1–Q7 above
- [[p01-blocks-keyword-end|Syntax pick 1: Blocks: keyword ... `end`]] — Robert first rejected `def`/`end`, then braces, then wrote his own version with `fn 
- [[p02-definition-line|Syntax pick 2: Definition line]] — `fn refund(db: Ledger, clock: Clock) : Result(Refund, RefundError)`
- [[p03-bindings|Syntax pick 3: Bindings]] — bare `now = clock.now` is an immutable binding, bound exactly once per scope; rebinding is a compile error; `var` is the only way to get …
- [[p04-conditionals|Syntax pick 4: Conditionals]] — `if` is an expression, no parens around the condition, braces
- [[p05-pattern-matching|Syntax pick 5: Pattern matching]] — `case value 
- [[p06-results-and-propagation|Syntax pick 6: Results and propagation]] — predicates end in `?` (`charge.refunded?`); propagation is the `try` prefix (`charge = try db.find_charge(id, within: 200.ms)`), never po…
- [[p07-types-struct-enum-refinement|Syntax pick 7: Types]] — `struct Charge 
- [[p08-contracts|Syntax pick 8: Contracts]] — `requires` / `ensures` lines come directly after the signature line, then a blank line, then the body, all inside the `fn 
- [[p09-module-header-and-never|Syntax pick 9: Module header and `never`]] — `module Payments.Refund` with dot paths (Robert's pick; `::` rejected, one symbol one idea, Elixir made the same call)
- [[p10-process|Syntax pick 10: Process]] — `process Name(db: Ledger, clock: Clock) 
- [[p11-loops-and-anonymous-functions|Syntax pick 11: Loops and anonymous functions]] — `for x in xs 
- [[p12-tests|Syntax pick 12: Tests]] — in the same file as the code, under it
- [[p13-capabilities-and-logging|Syntax pick 13: Capabilities and logging]] — capabilities are ordinary types obtained only at the program root (`fn main(platform: Platform)`), passed down explicitly, narrowed on th…
- [[p14-modules|Syntax pick 14: Modules]] — private by default, `pub` to expose (the `pub` lines are the spec altitude's table of contents)
- [[p15-methods-traits-generics|Syntax pick 15: Methods without objects, traits, generics]] — dot calls are sugar for first-argument functions (`charge.within_window?(now)` is `within_window?(charge, now)`), uniform function call s…
- [[p16-one-line-if-value|Pick 16: the one-line if as a value]] — Robert, 14 Sep morning: `x = if c: a else: b`, a value only
- [[syntax-overview|Syntax: how we got to Ruby's look with Go's discipline]] — AI-first constraint: Mo has zero corpus, so bodies borrow shapes models know cold; novelty is spent only where semantics need it (`intent…

## Deep dives
- [[compilation-target-and-compile-speed|Compilation target and compile speed]] — 1
- [[effects-and-capabilities|Effects and capabilities]] — - Effect: what a function does beyond computing (reads clock, writes ledger, sends to a process, calls network)
- [[errors-and-failure|Errors and failure: rain vs broken roof]] — Rain vs broken roof
- [[fork-in-the-road|The fork in the road: three products called 'a language for AI']] — "A language for AI" means three different products:
- [[id-addressed-editing|ID-addressed editing]] — The problem: agent editing tools today use `str_replace` (fails on non-unique or already-changed text), line ranges (wrong the moment any…
- [[idea-backlog|Idea backlog (Claude's early proposals)]] — - Stable semantic IDs on every declaration so agents edit by ID instead of fragile text diffs
- [[agent-native-runtime-features|Agent-native runtime features to test]] — a menu in three tiers: MCP surface, time travel, structured events, counterexamples as tests; the build order
- [[vm-first-vs-c-first|VM-first vs C-first for the Mo runtime]] — what a VM owns that C cannot, where Mo sits, stay on C-first and design the VM as the eventual primary
- [[reading-pack-2026-09|Reading pack for an outside reviewer]] — seven things to read in order, what we want from an OTP and a capability-systems reader, and the tried-and-rejected appendix
- [[closure-audit-2026-09-14|The closure audit]] — direction 31 cost round 7's jobq 12 lines of 2,843; the finding is a spec contradiction: chapter 3 says named functions are values, the stdlib chapter says no signature can name one
- [[outside-review-2026-09-14|Outside review, 14 Sep 2026]] — a deep review after round 6: protect capabilities, the failure model, the runtime surface; the shape laws and keywords are the weakest part; test Mo on the programs that exercise it
- [[outside-review-2026-09-14-response|Outside review, 14 Sep 2026: Fable's response]] — what was already done, what is wrong on facts, seven things to act on, the fork put to Robert
- [[outside-review-2026-09-13-response|Outside review, 13 Sep 2026: Fable's response and the baselines]] — the calls per item, Robert's decision, the numbers to compare against
- [[research-agenda-2026-09-response|Research agenda, Sep 2026: Fable's response to the contradictions]] — seventeen "contradicts Mo" items called (agree, disagree, test); chapter 2's recursion law corrected; reproducible builds measured
- [[outside-review-2026-09-13|Outside review, 13 Sep 2026: what to keep, revise, drop]] — Amp + oracle + librarian; verdict, ranked disagreements, keep/revise/drop table, next five moves
- [[outside-review-2026-09-13-evidence|Outside review, 13 Sep 2026: evidence]] — thirteen probes against the day-two toolchain and kv corpus, with file and line references
- [[negative-space-programming|Negative space programming]] — Source: [Negative Space Programming](https://double-trouble.dev/post/negativ-space-programming/)
- [[research-summary-2026-09|Research summary, Sep 2026]] — Nobody has built this yet
- [[plang-history-2026-09-index|PL history research, Sep 2026: bundle index]] — entry point for the 168k-word bundle: history eras, camps, deep dives, Mo synthesis, decision matrix
- [[plang-history-lambda-to-1970s|PL history: lambda calculus through the 1970s]] — Church/Turing, Fortran, Lisp, ALGOL, Simula, C, Smalltalk, ML, Prolog, Scheme, Forth; lessons for Mo
- [[plang-history-1980s-to-2000s|PL history: 1980s through 2000s]] — C++, Ada, Eiffel, Haskell, Erlang, Self, Python, Ruby, Java, JS, C#, Scala, Clojure, Coq/Agda/Idris; lessons for Mo
- [[plang-history-2010-to-2026|PL history: 2010 to 2026, the modern era]] — Go, Rust, Swift, Kotlin, Elixir, Julia, TS, Zig, Koka, Unison, Roc, Austral, Vale, Hylo, Carbon, Mojo, Lean 4, AI era
- [[plang-design-camps|The eight camps of language design]] — paradigm, types, memory, concurrency, syntax, compilation, philosophy, ecosystem — Mo's stance on each
- [[plang-implementation-menu|Implementation menu: what a language builder chooses]] — parsers, IRs, type-check algorithms, GC, VMs/JITs, package managers, verification, bootstrapping
- [[plang-mo-synthesis|Mo synthesis: what history says to Mo]] — camp-by-camp mapping to Mo's directions with reasoning
- [[plang-decision-matrix|PL design decision matrix for Mo]] — 18 design axes as a compact table: Options | Mo direction | Rationale
- [[state-model|State model]] — Not mutation itself
- [[steal-list|Steal list: what to take from other languages]] — Framing: Go ships a scheduler and GC inside every binary and nobody calls it a VM
- [[tiger-style-and-power-of-ten|Tiger Style + Power of 10, rethought AI-first]] — Key move: both documents are style guides enforced socially by review
- [[two-altitudes|Two altitudes in one language]] — - Spec altitude (what humans read): module and function signatures, contracts (`requires` / `ensures`), effect declarations, an `intent` …

## Plans
- [[interpreter-step-30|Step 30: processes on every core]] — a scheduler per core, messages across threads, fsync off the scheduler; a sketch until step 29 lands
- [[interpreter-step-31|Step 31: a deferred reply, brief for the worker]] — chapter 10 §1: `reply_to` kept in state and answered later, the asker keeps its deadline and sees `Down` on a crash; the batching queue's fix for round 8's outage
- [[interpreter-step-32|Step 32: crash reports apart from the ring, and the reopening store]] — what P6 on Mo found: `/crashes` empty under load, and the restart pattern no corpus file shows
- [[interpreter-step-29b|Step 29b: replay memory on a real log]] — Fable's 1M probe on an HTTP-written log passed 8 GB after the fold; the rule bounded-by-what-the-update-reaches made to hold in every loop shape
- [[interpreter-step-29|Step 29: the runtime honest]] — `restart: :never` honoured, `platform.exit` with a pending delayed send, replay streamed, simulated time only when a test waits, invariants counted
- [[program-6|Program 6: ledger in Mo]] — the brief for the payments ledger whose invariants are the point; after step 28
- [[interpreter-step-28|Step 28: what round 7 found in the runtime]] — a map written in place, the tuple `reduce`, resident memory, replay, the `never` rule's `if` gap, six gaps
- [[control-run-7|The control run, round 7]] — pre-registered on Robert's measure: the hidden defect suite, native speed and memory, the feedback loop, dependencies
- [[sampling-as-verification|Sampling as verification]] — measurement 2 of direction 43: five regenerations of the queue's board, a random driver, disagreements against the hidden suite
- [[mac-scaling-run|The Mac scaling run]] — step 30's rows at 1, 4, 10, and 14 cores on the M3 Max, one script
- [[bodies-as-cache|Bodies as cache]] — measurement 1 of direction 43: every program regenerated from its stripped spec, twice; completeness per program
- [[control-run-10|The control run, round 10, the Elixir round]] — pre-registered: the BEAM null hypothesis in a pane, round 7's queue and round 8's change in Elixir under the same suites
- [[mac-scaling-run|The Mac scaling run]] — the one script for step 30 at 1, 4, 10, 14 cores on the M3 Max, and what to read from it
- [[erosion-round|The erosion round, generation two]] — pre-registered: change 2 to the Mo, Go, Python, and Elixir queues by fresh maintainers, the third hidden suite, P6 on the Mo change
- [[control-run-9|The control run, round 9, the small-model round]] — pre-registered: round 8's change by five smaller models in the Pi harness, reliability and loops as the columns that move
- [[control-run-8|The control run, round 8, the maintenance round]] — pre-registered: the finished queues handed to fresh agents with a changed spec, regressions and defects, read on reliability and dependencies together
- [[interpreter-step-27|Step 27: what round 6 found]] — the file law gone, `state`/`result`/`old` as names, a `never` reads values at rest, the escape, `fold_lines`
- [[control-run-6|The control run, round 6]] — pre-registered: logstat and jobq, the baselines with their checks bolted on, the null hypothesis stated as P3
- [[interpreter-step-26|Step 26: the one-line if in tail position]] — what step 25's acceptance found: tail position is a value, two keyword diagnostics; before round 6
- [[interpreter-step-25|Step 25: the one-line if and keyword field names]] — Robert's two calls of 14 Sep morning; the production, the formatter rule, the fix reversed, `state` after a dot
- [[interpreter-step-24|Step 24: what program 5 found]] — the authority hole, a handle in a state field, a delayed send, `Deadline.remaining`, four gaps, the simulator's ask
- [[interpreter-step-23|Step 23: the runtime surface]] — `platform.runtime`, the event ring, `mo run --surface PORT`; directions 37 and 40 against program 1's nine questions
- [[interpreter-step-22|Step 22: what program 1 and round 5 found]] — the `--recipe` line count, the fixture's missing folder, a JSON integer, the derived deadline (`reply_by`), the recipe's rewrite rule, two diagnostics
- [[interpreter-step-21|Step 21: memory and green threads]] — a process is not an OS thread; chapter 7's bets measured; `Fs.fixture()` refuses `..`; three diagnostics, no syntax
- [[interpreter-step-20|Step 20: the runtime owns the loop, brief for the worker]] — serve and lines rows, capabilities in declared message fields, the four servers rewritten
- [[interpreter-step-19|Step 19: what program 4 found, brief for the worker]] — freeing finished processes, the held-send deadlock, recipe conformance, mkdir, a fixed clock, diagnostics, each_line, mutation tests
- [[interpreter-step-18|Step 18: the outside review's no-compat fixes, brief for the worker]] — invariant polarity, handles as authority, capture, recursion, grouped patterns, equality, cache key, faults that stop
- [[interpreter-step-17|Step 17: the round 3 follow-ups, brief for the worker]] — `any(T)` under refinements, `NotText`, a fold over lines, six diagnostics reworded
- [[interpreter-step-16|Step 16: HTTP in the stdlib, brief for the worker]] — `Http` over `Net`, server and client, fixture, both runtimes, differential
- [[interpreter-step-15|Step 15: processes and Net in the C backend, brief for the worker]] — the scheduler and sockets in C, kv and echo native, differential
- [[interpreter-step-14|Step 14: the follow-ups from round 2 and the C backend, brief for the worker]] — contracts on in every build, three suspected panics, formatter shapes, four stdlib rows, housekeeping
- [[interpreter-step-13|Step 13: the C backend, brief for the worker]] — C runtime, emitter, mo build, differential tests against the interpreter
- [[interpreter-step-12b|Step 12b: two ratified defaults, undone, brief for the worker]] — memoization out of the reference interpreter; every never runs on every test
- [[interpreter-step-12|Step 12: the runtime under real programs, brief for the worker]] — program discovery, hashed maps, in-place state, per-request freeing, file writes, three language decisions, fmt fuzz
- [[program-5|Program 5: agent in Mo, brief for the worker]] — the agent harness: permissions as narrowed capabilities, a run's budget as one `Deadline`, retries, a scripted mock model, the surface as the operator's view
- [[program-1|Program 1: jobq in Mo, brief for the worker]] — the founding premise's first real test: a durable lease-based job queue over HTTP on the store recipe
- [[program-4|Program 4: notes in Mo, brief for the worker]] — the first program over HTTP, built from two recipes
- [[program-3|Program 3: kv in Mo, brief for the worker]] — the second real program, a TCP key-value store
- [[interpreter-step-11|Step 11: Net, a TCP capability, brief for the worker]] — processes under mo run, sockets, direct style over blocking calls, Net.fixture
- [[interpreter-step-10|Step 10: the verified sidecar, mo fix, the error catalog, the README, brief for the worker]] — four tooling promises from chapters 5 and 7
- [[interpreter-step-9|Step 9: Mo.Sim with seeds and fault injection, brief for the worker]] — seeded scheduling, injected failures, never over Type.all, sim (N runs)
- [[interpreter-step-8|Step 8: the stdlib, brief for the worker]] — strings, lists, maps, sets, time, fs listing, JSON; 09-stdlib.md; logstat rewritten
- [[interpreter-step-7|Step 7: programs of many modules, brief for the worker]] — use imports functions, program root, multi-file corpus programs, push in place, interpreter speed
- [[control-run-4|The control run, round 4: logstat after steps 17–20, the timing round]] — same spec, same model, fresh sessions; the laws re-evaluated against it
- [[control-run-3|The control run, round 3: logstat after the formatter fixes and HTTP]] — same spec, same model, fresh sessions, after steps 14–16
- [[control-run-5|The control run, round 5: pre-registered]] — three predictions written before the run; loops by cause; wrote-the-language-directly
- [[control-run-2|The control run, round 2: logstat again on today's toolchain]] — same spec, same model, fresh sessions, after steps 7–12b
- [[control-run|The control run: logstat in Go and Python, brief for the worker]] — same spec, same model, chapter 8's null hypothesis
- [[program-2|Program 2: logstat in Mo, brief for the worker]] — the first real program, written from a spec, the founding-premise experiment
- [[interpreter-step-6|Step 6: main and Mo.Server, brief for the worker]] — main in the language, the real platform over std.Io, mo run, three programs with expected output
- [[interpreter-step-5|Step 5: the formatter, brief for the worker]] — FORMAT.md rules, mo fmt, the loop rule as MO0501, for _, MO0319, corpus formatted
- [[interpreter-step-4|Interpreter step 4: processes and supervisors, brief for the worker]] — Mo.Sim scheduler, update as a transaction, invariants, mailbox bounds, supervisors, the refund queue test
- [[interpreter-step-3|Interpreter step 3: run the tests, brief for the worker]] — refund module joins the corpus, bytecode, VM, tier-2 contracts, test runner, verified line
- [[interpreter-step-2|Interpreter step 2: the tier-1 checker, brief for the worker]] — prelude, names and types, the laws, capabilities, rejects/ fails by code
- [[interpreter-step-1|Interpreter step 1: lexer and parser, brief for the worker]] — corpus catches up with the Session 5 decisions, then lexer, parser, corpus test, bench rows
- [[model-bakeoff|Model bake-off: Opus vs Grok vs Codex as workers]] — same corpus brief to three models, one rubric, Robert picks
- [[corpus|Corpus: brief for the worker session]] — 50 tiny programs in examples/, one construct each, plus rejects/ that must not compile
- [[comparison-pass|Comparison pass: brief for the worker session]] — template, tools, and the 13 briefs for the Opus worker
- [[program-menu|Program menu: what we build to put Mo through its paces]] — seven programs of different kinds, and what each measures
- [[roadmap|Roadmap: the path after alignment]] — Once you've gone through Q1–Q16, here is the path I'd propose

## Sessions
- [[session-06|Session 6 — 13 Sep 2026 (evening, ingestion)]] — six deep-research runs and three adjacent runs ingested into raw/; new prompts-mo-parallel-tracks page; no decisions changed
- [[session-05|Session 5 — 12 Sep 2026]] — review closed, corpus and toolchain begun, bake-off, build-first process, gap decisions
- [[session-01|Session 1 — 12 Sep 2026 (night)]] — - 12 Sep 2026, session 1 (cont)
- [[session-02|Session 2 — 12 Sep 2026]] — - Walked the Open Questions page one at a time
- [[session-03|Session 3 — 12 Sep 2026]] — tensions 1–7, Q17, aube, recipes and the ecosystem (d31–d35), design-v0 folder
- [[session-04|Session 4 — 12 Sep 2026]] — expose line replaces pub, use A.B{X}, every for closes with end, loops vs combinators rule

## Research
- [[elixir|Mo vs Elixir]] — comparison: inference-first gradual types, OTP supervision shapes vs Q7, typed processes
- [[go|Mo vs Go]] — comparison: simplicity by tooling, error-syntax post-mortem, goroutine bugs, module supply chain
- [[rust|Mo vs Rust]] — comparison: what Mo keeps (enums, matching, small traits) and drops (lifetimes); compile-time and LLM evidence
- [[roc|Mo vs Roc]] — comparison: how a platform is built, purity by arrow, static dispatch, Perceus, the Zig rewrite numbers
- [[koka|Mo vs Koka]] — comparison: effect types and handlers vs capabilities, the closure-capture gap in d15, Perceus, fip
- [[austral|Mo vs Austral]] — comparison: linear capabilities from a root, unsafe modules, crash-on-contract-violation, what linearity would buy Mo
- [[hylo|Mo vs Hylo]] — comparison: mutable value semantics precisely, parameter conventions, projections, a coherence rule, colorless concurrency
- [[unison|Mo vs Unison]] — comparison: hash-identified definitions, never-invalidated caches, no dependency conflicts, the cost of dropping text
- [[moonbit|Mo vs MoonBit]] — comparison: the shipping AI-native toolchain (Pilot, sampler, SeekMoon), its language, and the no-resource LLM evidence
- [[bosque|Mo vs Bosque]] — comparison: design by removal, no loops, escape-free lambdas, validation levels, small-model verification, why it slowed
- [[spark-ada-and-dafny|Mo vs SPARK Ada and Dafny]] — comparison: contracts that run and prove, assurance levels, contract shapes LLMs discharge, loop invariants
- [[agent-native-cluster|Mo vs the agent-native cluster]] — comparison: 13 agent-first languages in short entries, and what 42 catalogued attempts converged on
- [[aube|Mo vs aube]] — comparison: the Node package manager's security defaults (trust no-downgrade, age gates, reputation signals, jail) and the seven things Mo takes
- [[verse|Mo vs Verse]] — comparison: failure as control flow, transactional rollback, structured concurrency; transactions vs crash-and-restart
- [[comparison-synthesis-draft|Comparison synthesis (draft)]] — ⚠️ tensions across the 13 comparisons, top ten steals, open questions for Robert; draft for Fable
- [[supply-chain-defenses|Supply-chain defenses]] — Q17 input: defenses that exist, the 2024–26 incident record (20 of 47) with impact/trend ranking, Mo mapped against it, six package-system design options (no recommendation)
- [[landscape-second-lane|Landscape, second lane]] — what Robert's three landscape research runs add or dispute vs Claude's survey; shortlist arguments
- [[motoko|Mo vs Motoko]] — comparison: actor isolation, trap-reverts-to-commit-point, upgrade-safe persistence, the 'designed for AI agents' claim (Caffeine)
- [[case-against-new-languages|The case against new languages]] — the null hypothesis the v0 design doc must answer: Quasar, CodeAct, SynCode, token sugar, cold start, ilo, Aether, BHC/hx
- [[capability-module-lineage|Capability module lineage]] — Newspeak, Joe-E, Wyvern, Limbo, E's confused deputy, each mapped to pick 13 / Q16 / Q17
- [[language-landscape|Language landscape: which languages deserve a deep comparison]] — 40+ languages in seven groups with the idea to steal from each, plus a 13-entry shortlist for the comparison pass
- [[prompts-language-landscape|Research prompts: the language landscape]] — three prompts for Robert's deep-research tools
- [[prompts-q17-supply-chain|Research prompts: Q17 supply-chain security and package management]] — three prompts for Robert's deep-research tools
- [[prompts-mo-parallel-tracks|Research prompts: Mo's three parallel research tracks]] — empirical validation, ecosystem depth, agent-authoring frontier; each brief paired with its Perplexity deep run
- [[plang-landscape-2026|The PL landscape circa 2026]] — what's alive, growing, fading, and where the interesting design work is happening; extends [[language-landscape]]

### Language surveys (history + design + Mo lesson)
- [[c|C]] — Ritchie 1972, Unix's portable assembler, why it won and what it cost; what Mo takes and rejects
- [[lisp|Lisp / Scheme / Common Lisp]] — McCarthy 1958, homoiconicity, macros, why it never dominated; what Mo takes
- [[smalltalk|Smalltalk]] — Kay/Ingalls/Goldberg, pure message-passing OO, image-based dev; why Mo is [[d06-never-oop]] but respects the insight
- [[ml|ML / Standard ML / OCaml]] — Milner 1973, Hindley-Milner, ADTs, functors; what Mo takes
- [[haskell|Haskell]] — 1990 committee, laziness, monads, type classes; why Mo is [[d07-elixir-flavored-functional]] not Haskell-pure
- [[erlang|Erlang / BEAM]] — Armstrong 1986, actor model, let-it-crash; the model behind [[d08-beam-qualities-without-the-beam]]
- [[cpp|C++]] — Stroustrup 1985, RAII and templates, the complexity lesson Mo rejects
- [[java|Java]] — Gosling 1995, JVM, generics-via-erasure, the ecosystem-wins lesson
- [[python|Python]] — van Rossum 1991, indentation, Python 2→3 and PyPI supply-chain lessons
- [[javascript|JavaScript / TypeScript]] — Eich's 10 days, gradual typing win, npm as the negative example for [[d30-supply-chain-security]]
- [[go-history|Go (survey)]] — Pike/Thompson/Griesemer, simplicity discipline, gofmt culture, MVS, mandatory checksums (see also [[go|Mo vs Go]])
- [[zig|Zig]] — Kelley 2016, comptime, no hidden control flow, the raw-C-hazard lesson; toolchain choice for [[d24-compile-to-c-via-zig]]
- [[dependent-types|Dependent types: Lean 4, Idris 2, Agda]] — the case for and against dependent types in general-purpose languages; where Mo's [[q08-verification-tiers]] fits
- [[prompts-research-agenda-2026-09|Research agenda 2026-09: papers, authors, manifestos]] — six runs (R1–R6) with prompts; R1, R3, R6 executed 2026-09-13 via Perplexity Computer, R2/R4/R5 ready to run
- [[empirical-validation-plan|Empirical validation plan: how Mo gets judged]] — the seven experiments against the control runs; round 5 pre-registered, tokens counted, baselines with checks
- [[ecosystem-strategy|Ecosystem strategy: the stdlib, kits, and the registry]] — Q11 answered against the day-one list; TLS and crypto as the gating bricks; recipes as kits
- [[agents-and-verification-2026|Agents and verification: the 2025–2026 evidence]] — R1: verifier automation beats model choice (82/44/27%), specs not proofs are the bottleneck, 0% contract satisfaction at 75–82% pass@1, composition frontier, diagnostics exchange rate for agents
- [[language-design-for-llms-evidence|Language design for LLMs: what the evidence says]] — R1: what measured results say about strictness, shape laws, low-resource syntax, structured edits, and error messages; where Mo's laws have evidence for and against
- [[author-ken-thompson|Author: Ken Thompson (Unix, C, Go)]] — R3: Trusting Trust vs source-first supply chain; taste, deletion, and what he refused to add
- [[author-dennis-ritchie|Author: Dennis Ritchie (C)]] — R3: C as a portable assembler by intent; what he called mistakes; the cost of trusting the programmer
- [[author-brian-kernighan|Author: Brian Kernighan (Unix, AWK, style)]] — R3: Elements of Programming Style and the Practice of Programming as the human ancestor of Mo's laws
- [[author-rob-pike|Author: Rob Pike (Plan 9, Go)]] — R3: simplicity as a tooling and social property, gofmt, less is exponentially more, Go's error and generics decisions
- [[author-tony-hoare|Author: Tony Hoare (CSP, axiomatic semantics)]] — R3: axiomatic contracts, null as the billion-dollar mistake, the Turing lecture on simplicity
- [[author-edsger-dijkstra|Author: Edsger Dijkstra (structured programming)]] — R3: goto, testing shows presence not absence, against mechanical translation of bans, simplicity is not systematic
- [[author-niklaus-wirth|Author: Niklaus Wirth (Pascal, Modula, Oberon)]] — R3: a feature's cost must be known before release, compiler self-hosting speed rule, design by removal
- [[author-joe-armstrong|Author: Joe Armstrong (Erlang)]] — R3: the six requirements R1–R6, let it crash, restart is not storage, failed type retrofits, do away with modules
- [[safety-critical-coding-standards|Safety-critical coding standards]] — R6: Power of 10, JPL C, MISRA, CERT, DO-178C, Ravenscar, SPARK and others compared; three rule categories, deviation records, the loop-annotation convergence
- [[reliability-and-testing-philosophies|Reliability and testing philosophies]] — R6: FoundationDB, Antithesis sometimes-assertions, Jepsen, SQLite coverage, let-it-crash restart intensity, QuickCheck shrinking, SRE error budgets, mutation testing

