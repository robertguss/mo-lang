# Mo Lang — Index

> Every wiki page, one line each. Read this after SCHEMA.md to find pages for any question.
> Last updated: 2026-09-12 | Total pages: 113

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
- [[syntax-overview|Syntax: how we got to Ruby's look with Go's discipline]] — AI-first constraint: Mo has zero corpus, so bodies borrow shapes models know cold; novelty is spent only where semantics need it (`intent…

## Deep dives
- [[compilation-target-and-compile-speed|Compilation target and compile speed]] — 1
- [[effects-and-capabilities|Effects and capabilities]] — - Effect: what a function does beyond computing (reads clock, writes ledger, sends to a process, calls network)
- [[errors-and-failure|Errors and failure: rain vs broken roof]] — Rain vs broken roof
- [[fork-in-the-road|The fork in the road: three products called 'a language for AI']] — "A language for AI" means three different products:
- [[id-addressed-editing|ID-addressed editing]] — The problem: agent editing tools today use `str_replace` (fails on non-unique or already-changed text), line ranges (wrong the moment any…
- [[idea-backlog|Idea backlog (Claude's early proposals)]] — - Stable semantic IDs on every declaration so agents edit by ID instead of fragile text diffs
- [[negative-space-programming|Negative space programming]] — Source: [Negative Space Programming](https://double-trouble.dev/post/negativ-space-programming/)
- [[research-summary-2026-09|Research summary, Sep 2026]] — Nobody has built this yet
- [[state-model|State model]] — Not mutation itself
- [[steal-list|Steal list: what to take from other languages]] — Framing: Go ships a scheduler and GC inside every binary and nobody calls it a VM
- [[tiger-style-and-power-of-ten|Tiger Style + Power of 10, rethought AI-first]] — Key move: both documents are style guides enforced socially by review
- [[two-altitudes|Two altitudes in one language]] — - Spec altitude (what humans read): module and function signatures, contracts (`requires` / `ensures`), effect declarations, an `intent` …

## Plans
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

