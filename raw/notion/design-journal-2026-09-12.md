---
source_url: https://app.notion.com/p/3d96bcfa7c75815e9d88f6b686b43c6c
source: Notion (Robert's work workspace, private page, exported before deletion)
exported: 2026-09-12
sha256: 59e3f27a4cd0bf8dbde0f89931dfb571396d469787674d76d74e8c68065d7a4b
---
A running record of the design sessions between Robert and Claude for a new programming language built for the AI era. Updated at checkpoints during discussion. **Mode: exploration.** Nothing is decided yet. We are collecting ideas, doing research, and comparing existing languages first; decisions come later. Ideas Robert has reacted well to are listed under **Directions we like**; open questions sit in **Open questions**.
*Last updated: 12 Sep 2026, \~1am — session 2 in progress, Q1–Q10 answered*
---
## Status at a glance
- **Phase:** Discovery / exploration (no decisions yet, by design). Session 1 complete.
- **Next session starts with:** Robert reviews the [Open Questions & Recommendations](https://app.notion.com/p/3d96bcfa7c7581288f6bfde6a5b81865) page (Q1–Q16 with Claude's picks) and answers in / no / counter for each.
- **Working name:** Mo (folder is `mo-lang`; origin of the name not yet discussed)
- **Current leaning:** A language that AI writes \~100% of, humans read only at the spec altitude, with an agent-capability model baked in
- **Guiding lens:** take old, proven ideas (Tiger Style, NASA Power of 10) and rethink them AI-first instead of human-first
---
## Directions we like (not decisions)
1. **Agents write nearly 100% of the code.** Humans no longer write or closely review code. Mo is designed for that world. This is Robert's founding premise.
2. **Human-readable, but at a higher altitude.** Mo stays readable by humans because it is the shared language of understanding, but humans read intent, contracts, and effects, not bodies.
3. **The source carries its own evidence.** Since review is gone, trust comes from what the compiler can check: contracts, effects, tests bound to requirements, proofs.
4. **Style rules become laws, possibly with no escape hatch.** Everything Tiger Style and Power of 10 enforce socially, Mo's compiler enforces. Robert likes the no-override version; to be weighed later against which programs it rules out.
5. **Old ideas, rethought AI-first.** Much of what works is decades old (Tiger Style, Power of 10, contracts, simulation testing). The job is to translate it for a world where agents write the code.
6. **Never OOP. No classes.** Functional and procedural style. (Robert, strongly held)
7. **Elixir-flavored functional, not Haskell-pure.** Pragmatic functional style.
8. **BEAM qualities without the BEAM.** Compile to a single static binary, memory-efficient like Rust or Go. A small runtime linked into the binary (like Go's scheduler) is acceptable; a separate VM is not.
9. **Primary inspirations: Rust, Go, Elixir/BEAM, Elm**, plus anything else worth stealing.
10. **Immutable data by default.** Gives agents locality of reasoning: to understand a function you need only the function. Perceus-style in-place reuse keeps it fast without a GC.
11. **Statically typed.** Inferred inside bodies, required at every function boundary. The one thing not taken from Elixir. (Claude's stated opinion, not yet debated)
12. **Concurrency at the edges, like Go.** Most code is plain functions on immutable data; isolated processes are a tool for concurrency and fault isolation, not the primary program structure. (Robert)
13. **Local ****`var`**** with mutable value semantics, plus ****`inout`**** parameters.** In. A `var` can never be aliased, never escapes its function, and is semantically just rebinding that reaches inside a value. (Robert, after Claude's unpacking)
14. **Processes are the only identity, and each is an Elm-shaped state machine.** State + message type + pure `update` returning new state and effect commands. No globals, statics, mutexes, or singletons. Shared things (config, caches, pools) are a process or a platform-provided capability. (Robert: "that sits with me")
15. **Effects via capabilities, no effect type system.** A function is pure unless it takes a capability parameter. The signature is the purity proof. (Robert: matches)
16. **Direct-style I/O with runtime interception.** `fs.read(path)` reads like Go and blocks like Erlang, but compiles to "suspend, hand a command to the runtime, resume with result." The runtime is the single interception point for capability checks, replay logging, and fault injection. Green threads, no `async` keyword, no function coloring. (Robert: matches)
17. **Every effectful call carries a mandatory deadline.** Bounded waits, extending Power of Ten's bounded loops. Timeout is an ordinary `Err` variant the exhaustiveness checker forces you to handle. (Robert: matches)
18. **Two kinds of failure, two mechanisms, never crossing.** Expected failure ("rain") is an `Err` value, exhaustive, in the signature, handled by the caller. A bug ("broken roof": contract or invariant violated) crashes the process. **No try-catch anywhere in the language.** A crash can only be restarted by a supervisor, logged, and handed to an agent with seed + message log. Agents can never convert a bug into a handled outcome. (Robert: "definitely in")
19. **Negative space is the human-agent contract.** Humans write nothing, not even the spec. Humans *speak* constraints in conversation ("never double-charge"), agents write them as `never` clauses, humans *read* them. The `never` set is the part of the spec altitude a person can judge instantly. The agent has full freedom inside the shape; the shape is what the human agreed to.
20. **A human is pulled in when the shape changes.** Agents add, rewrite, and refactor freely. The moment a change removes or weakens a `never`, a person sees that diff. That is the precise answer to "when does the human look."
21. **Production crashes are fully autonomous.** A tripped `never` or contract crashes the process, the supervisor restarts it, and the agent takes the crash as a task and fixes it with no human involvement. (Robert) Consequence: the runtime must emit a complete bug report (seed, message log, state snapshot, the violated clause and its contract chain), and a fix is acceptable only if it passes all tests and contracts and weakens no `never`. If the fix requires changing the shape, item 20 applies and a human is pulled in. That closes the loop: the human is involved only when the shape changes, never when it is merely enforced.
22. **Type system: Rust-plus-refinements from day one.** Traits (without the deep solver machinery), enums with data, generics with bounds, exhaustive matching, plus refinement types on primitives (`Money where value >= 0`) discharged statically when provable and at runtime otherwise. This is where `never` clauses can become types. Dependent types rejected: models write them at \~27% success vs \~82% for contract-style. (Robert)
23. **Compile speed is a first-class requirement.** The compile time is the latency of the agent's loop; a slow teacher gets ignored. Rust's slowness is the anti-pattern. (Robert, strongly held)
24. **Compilation target: C via the Zig toolchain for release, own fast backend for the edit loop.** Zig toolchain as the only dependency (Tiger Style), trivial cross-compilation and static linking. LLVM deferred until performance demands it. Compile-to-Rust rejected as a trap (semantics mismatch). WASM deferred. Own VM off the table. (Robert agrees with Claude's recommendation, with the speed requirement added)
25. **Fast path is an interpreter, never shipped.** Build order: (1) bytecode interpreter for the edit loop, also the executable reference semantics and the host for the simulator, replay, fault injection, and crash reports; (2) C via Zig for release, differential-tested against the interpreter; (3) own native backend only if a real program proves the first two insufficient. Precedent: OCaml's `ocamlc` / `ocamlopt` pairing. The interpreter is a dev tool and is never inside the release binary. (Robert: in)
26. **Optimize for developer happiness AND agent happiness.** Robert's favorite language to read and write is Ruby (Matz's "developer happiness"). Mo's syntax must be enjoyable to read. A Rust/Gleam-shaped brace syntax was rejected on sight. Direction: Ruby's look with Go's discipline. Precedents: Crystal (Ruby syntax + static types + native binaries) and Elixir (Ruby's feel on the BEAM). One way to write each thing, resolved by the formatter: Ruby's look, not Ruby's freedom.
27. **Design principle (Robert's words):** the language needs to be as simple as possible and elegant like Ruby and Python. Borrow all the things he likes, keep out the things he doesn't. Every syntax proposal is held to this.
28. **Nothing is final until it is measured.** (Robert, session 2) Every decision here — especially the performance-shaped ones — stands only until a benchmark, eval, or test says otherwise. Compile-time performance is of paramount importance, and runtime speed close behind, but both are *measurable*, so neither is settled by argument. Consequences: the project carries a benchmark suite and an eval suite from early on; every performance claim in this journal is a hypothesis with a named way to check it; a decision that measurement contradicts gets reopened without ceremony. This applies to the overflow-check cost, the interpreter-vs-native split, the incremental-rebuild targets, the C-via-Zig backend choice, and any law number.
29. **Agents edit by declaration ID, not by text position.** (Robert: in, session 2, “fascinating”) Every declaration gets a stable ID in a toolchain-owned `.mo.ids` sidecar; source stays plain text and is the truth. `mo edit <id>`, `mo rename <id>`, `mo insert`, `mo delete`, plus a few named sub-targets. Edits are parsed before applying, carry `--expect hash:` for optimistic concurrency, and share the ID with diagnostics as the join key. Replaces grep-and-replace for essentially all agent edits. See the section below.
30. **Supply-chain security is a first-class design goal.** (Robert, session 2, very important) AI has made package-ecosystem attacks (npm, PyPI, and the rest) massive and unlike anything before. Mo and its ecosystem are designed to mitigate this from the start: a Go-sized-or-larger stdlib so most programs have zero dependencies, and a package system where a dependency can only do what it is handed a capability for. Capabilities become the permission system for packages, visible at install time. No install scripts, macros, or build-time code execution. Full question and sub-questions: Open Questions Q17.
---
## ID-addressed editing (unpacked, session 2)
**The problem:** agent editing tools today use `str_replace` (fails on non-unique or already-changed text), line ranges (wrong the moment anything above moves), or whole-file regeneration (burns context, hides the real diff). Root cause: the edit is addressed by text position, but the agent thinks in declarations.
**The move:** the unit of edit is the unit of meaning. `mo edit m7q2k --with refund.new.mo` replaces one declaration. Sounds coarse, but the 40-line function law makes a declaration always fit one edit and one screen; the laws and the editing model reinforce each other.
**What string editing cannot give:**
- **Atomic and parsed.** The new declaration is parsed before the file is touched; a broken edit is rejected whole. A file is never left half-broken.
- **Optimistic concurrency.** `--expect hash:9f31…` → rejected if another agent changed it since. Parallel agents on one module without locks.
- **Semantic rename.** Definition, every call site, `use` lines, and test references across files in one step. No grep false positives.
- **Same address as diagnostics.** A Q9 `fix` names `id + line`; it lands on the right declaration even after other edits.
**Granularity:** the whole declaration, plus a small fixed set of named sub-targets matching the spec-altitude blocks: `<id>.contracts`, `<id>.state`, `<id>.update`; `insert --after <id>`; `delete <id>` (fails if referenced). Nothing finer — needing a one-line edit means the function is too big.
**What stays text:** the `.mo` file. Humans read text on phones (Unison's store is where people bounce off); git/diff/grep/editors work for free; text editing remains as a never-wrong fallback.
**Costs:** `.mo.ids` is committed and can conflict only when two agents *add* declarations at once (`mo ids rebuild` resolves; existing IDs never move); agents must learn the tool exists (they learn it from diagnostics, since every fix names an ID); whole-declaration edits cost more tokens than a one-line replace, bounded by the 40-line cap.
---
## Open questions (for Robert)
1. ~~Who writes it?~~ **Answered: agents, \~100%.** See Decisions.
1b. ~~Laws with no escape hatch?~~ **Liked, parked.** Revisit once we know the target domain.
1. **First real program?** Web service, CLI, data pipeline, agent harness, game? A language without a target domain dies. *Deferred: Robert wants to explore language attributes first and let the domain fall out.*
2b. ~~Mutability~~ **Answered: immutable data is great** (typo in the original). Immutable by default.
2c. **Processes as Elm-shaped state machines?** Is "a process = state + message type + pure update returning new state and effect commands, and that is the only place state lives" right, or too restrictive? **Liked.** Processes are the only identity. See Directions we like, item 14.
1. **Runtime appetite.** Native via LLVM, WebAssembly, transpile to Rust/Go, or the BEAM (like Gleam)? Transpiling to Rust gets verification tooling and an ecosystem for free.
2. **How radical on syntax?** Familiar Python/TypeScript feel to exploit model priors, or willing to look strange if it buys correctness?
3. **Verification dial.** From "strong types + exhaustive matching" up to "Dafny-style proofs the agent must discharge." Suggested start: runtime-checked contracts with an optional SMT path.
4. **The name.** Is "Mo" decided? What's the story?
5. **Type system spectrum considered:** Go-level (small, boring, repetitive) / Rust-level (traits, generics, enums with data) / refinement types (values in types, SMT-backed) / dependent types (Lean, Idris). **Answered: Rust + refinements.**
---
## The fork in the road
"A language for AI" means three different products:
1. **A language AI writes and humans review.** Optimized for verification and review, not typing. Contracts, effects, exhaustive errors, no hidden control flow, structured compiler diagnostics that act as the agent's teacher. **Claude leans here.**
2. **A language for orchestrating agents.** LLM calls, tool capabilities, budgets, retries, structured concurrency as primitives. Pel lives here. Smaller, DSL-shaped bet.
3. **A spec language where the AI is the compiler.** Humans write intent, model generates a verified implementation, code is an invisible intermediate. Boldest, mostly a research project.
**Recommendation:** option 1, with the capability model from option 2 baked in, since agents will also be the ones running the code.
---
## Two altitudes in one language (proposed, awaiting Robert's reaction)
- **Spec altitude** (what humans read): module and function signatures, contracts (`requires` / `ensures`), effect declarations, an `intent` statement per unit, and a visible verification level (`verified by tests, contracts` vs `proof`). Semantically binding, not comments. Reads like a design doc.
- **Implementation altitude** (what agents write): function bodies, checked against the spec altitude, collapsed by default.
Sketch:
```javascript
module payments.refund

intent "Refund a captured charge, at most once, within 90 days of capture."

fn refund(charge: Charge, amount: Money) -> Result<Refund, RefundError>
  requires amount <= charge.captured_amount
  requires charge.captured_at within 90.days
  ensures  result.ok implies ledger.balance == old(ledger.balance) - amount
  effects  db.write(ledger), net.call(stripe)
  verified by tests, contracts
```
---
## Tiger Style + Power of 10, rethought AI-first
**Key move:** both documents are style guides enforced socially by review. Review is gone. So *every style rule becomes a language rule enforced by the compiler.*
**Become laws of Mo (compiler-enforced):**
- No unbounded loops. No `while true`. Loops iterate finite collections or carry an explicit bound in the signature.
- No general recursion. Only structural recursion the compiler proves terminates. Totality by default.
- Hard function length limit (number TBD). Also a context-window-sized unit of agent work.
- Minimum contract density: a function with no `requires`/`ensures` does not compile.
- No compound asserts. A failure always names one property.
- Exhaustive error handling. Every result consumed. No exceptions.
- No default parameters. All options explicit at call site.
- No warnings, only errors.
- Explicitly sized types only.
- Positive and negative space tests are part of the unit; compiler checks both exist per precondition.
**Die (served human eyes):** column limits, indent width, symmetric name lengths, file order, brace style. Canonical formatter, no choices.
**Promoted into bigger features:**
- "Motivate decisions" → structured provenance field linking to requirement and conversation.
- "Performance sketching" → declared resource budgets in the signature (latency, memory, allocations), checked by compiler/simulator.
- "Paired assertions" → type invariants auto-checked at every boundary (create, serialize, deserialize).
- Deterministic simulation testing → default runtime model. Every program deterministic under a seed. Failing assertion + seed = complete, reproducible bug report for an agent.
- Static allocation after startup → powerful but domain-constraining; parked until first-program decision.
Sources: [Tiger Style](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md), [The Power of Ten](https://spinroot.com/gerard/pdf/P10.pdf)
---
## State model (deep dive, 12 Sep 2026)
### Why state hurts, precisely
Not mutation itself. Three things OOP maximized:
1. **Aliasing plus mutation.** Two names for one memory, one changes it.
2. **Hidden state.** A call changes something invisible from the call site; the signature lies.
3. **Time.** "What is x" has no answer without "when."
For an agent reasoning over a context window, each one means "you must read code that isn't in front of you."
### Options weighed
<table header-row="true">
<tr>
<td>Option</td>
<td>Pros</td>
<td>Cons</td>
</tr>
<tr>
<td>1. Shared mutable (imperative default)</td>
<td>Fast to write, matches machine</td>
<td>All three pains. Off the table.</td>
</tr>
<tr>
<td>2. Pure functional, explicit threading (State monad, Elixir passing)</td>
<td>Total honesty, trivially testable</td>
<td>Monad ceremony, awkward accumulators, humans reject it</td>
</tr>
<tr>
<td>3. Mutable value semantics (Swift, Hylo)</td>
<td>Natural loops, C-level perf, no borrow checker; no aliasing so pains 1 and 3 vanish</td>
<td>Needs a story for large shared structures; less familiar to models</td>
</tr>
<tr>
<td>4. Ownership + borrowing (Rust)</td>
<td>Strongest guarantees, full expressiveness</td>
<td>Lifetimes: the #1 failure for humans and agents. Too expensive given option 3</td>
</tr>
<tr>
<td>5. State only in actors (Erlang, Elm)</td>
<td>Time explicit as message sequence, replay free, isolation free, supervision</td>
<td>Shared things become round-trips; god-process blobs; giant update fns</td>
</tr>
<tr>
<td>6. Value/identity split (Clojure atoms, refs, STM)</td>
<td>Philosophically right</td>
<td>STM hard natively; reintroduces shared mutable identity</td>
</tr>
<tr>
<td>7. State as algebraic effect (Koka)</td>
<td>Signature tells the truth; swap handler for test/replay</td>
<td>Unfamiliar, can get abstract</td>
</tr>
<tr>
<td>8. Event sourcing (state = fold over log)</td>
<td>Log is truth; replay/audit built in; perfect for agent repro</td>
<td>Log growth, snapshots, schema evolution; overkill for a counter</td>
</tr>
<tr>
<td>9. Relational / Datalog (Eve, Rel)</td>
<td>Very verifiable</td>
<td>Too far from what models know. Shelved</td>
</tr>
</table>
### Claude's proposed synthesis (stack 3 + 5 + 7 + 8, one concept per layer)
- **Values are immutable with value semantics.** Inside a function, `var` allows in-place mutation because the compiler guarantees no aliasing. Semantically a chain of rebinding that reaches inside a value (Elixir's `x = x + 1`, one step further).
- **Identity exists in exactly one place: a process.** Anything that changes over time and outlives a call is a process, changed only via pure `update`. No globals, statics, refs, or atoms.
- **State access is visible in the signature** as an effect (Koka). Unifies with capabilities: the effect declaration is also the permission.
- **Process state types carry invariants checked at every transition.** Tiger Style paired assertions promoted into the language; provable in verified mode.
- **Every process is replayable from snapshot + message log.** Event sourcing as a runtime property. Persistence is a platform decision; semantics always present.
**Costs, stated plainly:** shared caches/pools/config live in a process or a platform capability (a round-trip where Go uses a mutex); big process states need nested state machines (function length law forces decomposition); `var` is a second binding form.
**AI-first payoff:** any function is understood from its signature and body alone; any process is tested by feeding messages and checking states; any failure reproduces from seed + log. Nothing ever requires reading code that isn't in front of the agent.
### `var` and `inout`, unpacked (Robert: in)
- `var x` is rebinding that reaches inside a value; identical to `x = x.with(i, v)` observably, in-place on the machine.
- **Rule:** a `var` can never be aliased: no references, cannot be sent to a process, cannot be captured by an escaping closure. Passed to a function it is either copied or declared `inout` (caller's name inaccessible until return; mutation visible in the signature).
- **Unlocks:** loops with accumulators in the form models generate reliably (folds are where off-by-one bugs cluster); in-place algorithms (sort, sieve, DP tables, parser cursors); guaranteed in-place memory rather than hoping Perceus proves uniqueness (Roc's gap); honest mutation via `inout`.
- **Costs:** `let` and `var` are two forms; agents may overuse `var`; `inout` rules must be taught well.
- **Fit:** a `var` lives and dies in one call, never becomes identity. Model unchanged: values immutable and unaliased, processes the only identity.
---
## Effects and capabilities (deep dive, 12 Sep 2026)
### Two ideas kept separate
- **Effect:** what a function does beyond computing (reads clock, writes ledger, sends to a process, calls network).
- **Capability:** the unforgeable permission value you must hold to perform it.
### Three ways to make effects visible
1. **Effect types (Koka).** Signature carries an effect row. Precise, handlers swap real I/O for stubs. Cost: a second type system, least familiar to models.
2. **Effects as returned data (Elm).** Pure functions return commands; runtime performs them; results arrive as messages. Cost: sequential I/O scatters across handlers and continuation-carrying message variants; the exact shape where agents drop error branches. Elm does this because JS is a single-threaded event loop, a platform constraint, not a virtue.
3. **Capabilities as parameters (Austral).** No effect types. Can't touch the filesystem without a `FileSystem` value in hand. Signature reveals effects through parameter types.
**Insight:** 2 + 3 make 1 unnecessary. If the only ways to cause an effect are holding a capability or (under the hood) issuing a command, the signature already tells the whole story with zero new type machinery.
### What command style buys, and how direct style earns it back
Command style gives: purity, interception, no blocking, visibility. **Erlang is direct-style and has all four**, because processes are cheap so blocking is free, and every effect goes through the runtime. TigerBeetle does the same in Zig with a swappable I/O interface for the simulator. Direct style loses nothing if:
- every effect is a call into the runtime, never a raw syscall (single interception point), and
- blocking is free via green threads (Go-style, no `async`, no coloring).
Under the hood `fs.read(path)` compiles to suspend / hand command to runtime / resume. Direct style is sugar over command style, as `await` is over promises, but with no keyword because every effectful call works this way. Koka's algebraic effects, Roc's `!`, Gleam's `use` are the same discovery.
<table header-row="true">
<tr>
<td>Property</td>
<td>How Mo gets it</td>
</tr>
<tr>
<td>Purity</td>
<td>No capability parameter = provably pure. Signature is the proof.</td>
</tr>
<tr>
<td>Interception</td>
<td>Runtime performs every command: capability check, replay log entry, simulator hook in one place.</td>
</tr>
<tr>
<td>No blocking</td>
<td>Green threads. 10k blocked processes cost 10k small stacks.</td>
</tr>
<tr>
<td>Visibility</td>
<td>Replay log = sequence of commands and results per process; spec altitude shows effects via capability params.</td>
</tr>
</table>
### The cost and the law
A blocking call can block forever, breaking bounded-everything. So: **every effectful call carries a deadline**, e.g. `fs.read(path, within: 2.seconds)`. Timeout is an ordinary `Err`. Deadline and capability are the same kind of thing: a limit on authority (the "Lingering Authority" pairing).
### Result
No effect type system. No `async`. No callbacks. A function is pure unless it takes a capability; a capability call reads like Go, blocks like Erlang, records like Elm, and cannot hang.
Example:
```javascript
fn append_log(fs: FileSystem, line: Text) -> Result<Unit, IoError>
  let config = fs.read("app.toml", within: 1.second)?
  let path   = parse_log_path(config)?
  fs.append(path, line, within: 1.second)
```
---
## Errors and failure (12 Sep 2026)
**Rain vs broken roof.** Rain is expected (missing file, slow network, bad input): bring an umbrella, i.e. return `Err`. A broken roof is a bug (negative balance, impossible state): you cannot fix it with an umbrella. Continuing means acting on a world that doesn't exist, and every step spreads damage.
**Try-catch is grabbing a broken-roof problem and treating it as rain.** Agents do it more than humans because their job is to make the red go away. Remove it and the guarantee is structural.
**Erlang's move:** make dying cheap. Small processes + supervisor restart from known-good state = a reset, not a catastrophe.
<table header-row="true">
<tr>
<td></td>
<td>Expected failure</td>
<td>Bug</td>
</tr>
<tr>
<td>Looks like</td>
<td>`Err(FileNotFound)` returned</td>
<td>`requires` / `ensures` / invariant fails</td>
</tr>
<tr>
<td>Who handles</td>
<td>Caller, via exhaustive `match` or `?`</td>
<td>Nobody. Process dies.</td>
</tr>
<tr>
<td>Next</td>
<td>Program continues by design</td>
<td>Supervisor restarts process from clean state</td>
</tr>
<tr>
<td>Who learns</td>
<td>Whoever handled it</td>
<td>An agent: crash + seed + message log = fix task</td>
</tr>
</table>
**Unlocks:** every crash is a real bug and vice versa, so the crash log is a noise-free agent work queue; contracts have teeth (tripwires that can't be disarmed); supervision is the only recovery story, so every program has one and failures stay contained.
**Costs:** design process boundaries with restart in mind (smaller processes, persist as messages arrive); untrusted input is rain and must be `Result`, discipline: "if it comes from outside the program, it's rain"; no log-and-continue for real bugs (restart-and-report beats limp-along-and-hide when agents fix bugs in minutes).
`?` is kept for upward propagation only, never for discarding.
---
## Negative space programming (12 Sep 2026)
Source: [Negative Space Programming](https://double-trouble.dev/post/negativ-space-programming/). Define a program by what it must never do, fail the instant it does. Roots in Power of 10 (two assertions per function) and Tiger Style (Joran Greef: think like a hacker).
**Where negative space lives, weakest to strongest:**
1. Runtime assertions in bodies (what the post describes).
2. Contracts (`requires` / `ensures`) on signatures, visible at spec altitude.
3. Types: make illegal states unrepresentable. Compile-time negative space; best feedback loop for agents.
4. Absent capabilities: no `Network` parameter means no network call. Negative space by construction, free to write.
5. **Explicit ****`never`**** clauses** (proposed addition): module/process-level statements of what must never be true. `never ledger.balance < 0`, `never this process sends email`. Runtime-checked, attacked by the simulator, proven when possible; the verification line says which.
**AI-first reframe:** humans are bad at specifying complete behavior and good at saying what must not happen. So the `never` set is the natural human-facing surface. Initial proposal had humans writing it; Robert corrected: humans write nothing. Revised: humans speak it, agents write it, humans read and approve it.
**Design consequences:**
- `never` clauses must render as plain sentences ("a refund never exceeds its charge") since their purpose is to be read by someone not reading code.
- `intent` and `ensures` are agent-authored too, read for context, not judged. The `never` set is the judged part.
- "Think like a hacker" becomes mechanical: deterministic simulator + property-based generation spend a million runs trying to violate every reachable `never`.
- Per the laws, every precondition needs a rejection test, so negative-space testing is required.
**Costs:** `never` clauses can contradict each other or the positive spec (compiler must detect); over-constraining blocks valid solutions (human decision to relax); runtime cost in hot paths (prove-and-remove path earns its keep).
---
## Compilation target and compile speed (12 Sep 2026)
### Target options weighed
1. **Native via LLVM** (Roc, Rust): full control, best perf; huge dependency, slow, we own the whole runtime.
2. **Compile to C** (Koka): no-GC native binary with any C compiler; Zig `cc` for painless cross-compilation; easy to debug output. Leaky for green threads but Koka and Erlang's runtime prove it works. **Chosen for release.**
3. **Compile to Rust:** tempting for Verus/Aeneas verification, but our semantics (value semantics, Perceus) fight the borrow checker and generated-Rust-that-doesn't-compile is a nightmare. **A trap.**
4. **WebAssembly first:** sandboxing fits capabilities; not yet a home for green threads or native single binaries. Later.
5. **Own bytecode VM:** the BEAM route. Off the table.
Verification path is independent of target: SMT (Z3) talks to the compiler's own IR.
### Why Rust is slow (all design decisions, all avoidable)
Monomorphization per concrete type; trait solver + borrow checker before codegen; proc macros run arbitrary code; crate as compilation unit; LLVM even on debug builds. Rust's 2026 roadmap fights all five for single-digit wins.
### Evidence it can be different
- Roc rewrote 300K lines from Rust to Zig: incremental rebuilds 3.4s → 35ms (\~100x).
- Zig: own x86 backend for debug builds (no LLVM), in-place incremental binary patching, sub-300ms rebuilds with C sources.
- Unison: content-addressed functions compiled once per hash; test results cached by hash, never re-run unless a dependency changed.
### Levers for Mo (most already held)
- **Two backends, one per loop.** Interpreter for the agent's iteration loop; C via Zig for release. **Decided: interpreter** (see below).
### Interpreter vs own native backend (Robert: interpreter)
<table header-row="true">
<tr>
<td></td>
<td>Own machine-code backend (Zig-style)</td>
<td>Interpreter (OCaml-style)</td>
</tr>
<tr>
<td>Build effort</td>
<td>Hardest thing on the project: regalloc, calling conventions, debug info, green-thread stack switching, per architecture. Zig took years.</td>
<td>Weeks. Portable everywhere for free.</td>
</tr>
<tr>
<td>Compile latency</td>
<td>Low</td>
<td>Near zero (no codegen)</td>
</tr>
<tr>
<td>Runtime speed</td>
<td>Near release</td>
<td>10-50x slower</td>
</tr>
<tr>
<td>Simulation / replay / fault injection / crash reports</td>
<td>Must be compiled into machine code</td>
<td>Hooks in the interpreter loop; interpreter-native</td>
</tr>
<tr>
<td>Semantics</td>
<td>One implementation</td>
<td>Two, but the interpreter is the executable spec and the C backend is differential-tested against it</td>
</tr>
<tr>
<td>Ships?</td>
<td>Yes</td>
<td>Never. Release is native via C.</td>
</tr>
</table>
**Why interpreter:** everything distinctive about Mo lives in the agent-compiler loop, and all of it is interpreter-native. The one loss, test runtime, has a second answer: content-addressed compilation makes the cached C build the fast native path (a C compiler at -O0 handles one small function in tens of ms), so a hand-written backend may never be needed.
- **Spec altitude = interface file.** Signature/contract/effects declared up front, so a body edit never recompiles dependents; only signature or contract changes ripple. OCaml `.mli`, free from the two-altitude design.
- **Content-addressed functions.** Semantic IDs become content hashes; compile once per hash; cache shared across all agents, so parallel agents never rebuild each other's work.
- **Tests cached by hash.** Pure-unless-capability + deterministic simulator = test results are a pure function of the code hash. Run only what changed.
- **No macros, no deep trait solving, small grammar.** Rust's three heaviest front-end costs don't exist. Dictionary passing for generics in debug builds to avoid code explosion.
- **Verification never blocks the loop.** Refinements and `never` clauses runtime-checked instantly; SMT proving runs in the background, cached by hash, upgrades the verification level on success. An agent never waits on Z3.
- **Compile-speed law.** Benchmark suite tracks build time per KLOC and incremental latency; a regression fails the build.
**Targets (held loosely):** incremental rebuild \< 50ms; full build of 100K lines in seconds; single-function test loop \< 100ms.
Sources: [Roc Rust-to-Zig rewrite](https://rtfeldman.com/rust-to-zig), [Zig self-hosted x86 backend default in debug](https://ziggit.dev/t/self-hosted-x86-backend-is-now-default-in-debug-mode/10447), [Unison: the big idea](https://www.unison-lang.org/docs/the-big-idea/), [Rust Fast Builds roadmap 2026](https://rust-lang.github.io/rust-project-goals/2026/roadmap-fast-builds.html)
---
## Syntax (12 Sep 2026)
**AI-first constraint:** Mo has zero corpus, so bodies borrow shapes models know cold; novelty is spent only where semantics need it (`intent`, `never`, `requires`, `ensures`, `process`, `within:`, `verified by`).
**Families considered:** Rust-shaped (Gleam), Python-shaped, Elixir-shaped, Go-shaped. Claude first recommended Rust/Gleam-shaped braces and showed a full example. **Robert rejected it:** Ruby is his favorite language to read and write; the code must be enjoyable. Rewritten Ruby/Crystal/Elixir-shaped.
**Syntax choices in the Ruby-shaped draft:**
- `def`/`end`, `case`/`when`, `do |x|` blocks, `unless`, trailing `if`. Keywords, not braces.
- Contracts (`requires`/`ensures`) are the first lines of a method, like Rails validations at the top of a model. Above the body, collapsible.
- Predicate methods end in `?` (Ruby), so Rust's `?` propagation is replaced by Zig's `try` prefix: `charge = try db.find_charge(id, within: 200.ms)`.
- `ok` / `error` are lowercase constructors: `return error AlreadyRefunded(id) if ...`.
- Immutable update via `.with(field: value)`.
- Crystal-style `name : Type`; generics with parens `Result(Charge, RefundError)`.
- `struct` / `enum` / `type X = ... where ...` for refinements.
- `process` block with `state ... end`, `invariant`, `message` declarations, one `def update`.
- `test "..."` and `test rejects "..."` blocks; `verified by ...` line at module end.
**Discipline:** Ruby offers five ways to write everything; Mo offers one. Optional parens, `do`/`end` vs braces, `unless` vs `if !`: all resolved by the formatter so agents never choose.
**Open tension noted:** `log.warn(e)` inside a process should require a `Log` capability. Logging is the effect everyone wants everywhere.
### Syntax picks, piece by piece (Robert chose each)
1. **Blocks: keyword ... ****`end`****.** Robert first rejected `def`/`end`, then braces, then wrote his own version with `fn ... end` and no braces. **Final: every block opens with a keyword and closes with ****`end`****. No braces, no labels on ****`end`****.** Indentation-only rejected.
2. **Definition line:** `fn refund(db: Ledger, clock: Clock) : Result(Refund, RefundError)`. `fn` keyword (not `def`); `name: Type` with no space before the colon (Robert's adjustment); `:` for the return type, not `->`; generics with parens, no angle brackets.
3. **Bindings:** bare `now = clock.now` is an immutable binding, bound exactly once per scope; rebinding is a compile error; `var` is the only way to get a changing name. Unused-binding error catches typos.
4. **Conditionals:** `if` is an expression, no parens around the condition, braces. Trailing `if` allowed only on single-line `return` guards. No `unless`. No ternary.
5. **Pattern matching:** `case value ... end` with arms written `Pattern: expression` (Robert's pick, replacing `->`; `->` is now gone from the language). Multi-line arms run until the next `Pattern:` line or `end`, no per-arm closer, Ruby `when` style. Note: `:` now means both "is a type" and "maps to" by context, a deliberate bend of one-symbol-one-idea since both readings are universal (Ruby, Python, JSON) and never overlap. No `when`. Exhaustive always; no catch-all `_` on closed enums; guards via `if` on an arm; nested destructuring.
6. **Results and propagation:** predicates end in `?` (`charge.refunded?`); propagation is the `try` prefix (`charge = try db.find_charge(id, within: 200.ms)`), never postfix `?`; constructors are the capitalized variants `Ok(...)` / `Error(...)`; **no unwrap, no expect**, `try` is the only propagation and nothing turns an `Error` into a crash.
7. **Types:** `struct Charge ... end` with `id: ChargeId` lines, `enum RefundError ... end` with `WindowExpired(captured_at: Time, now: Time)` variants, refinements `type Money = UInt64 where value <= ...`. Construction is call-style with named fields, `Charge(id: id, ...)`, identical for structs and enum variants; never positional. Every field required unless `Option`. **`.with`**** removed** (Robert). The only way to change a struct anywhere: `var updated = charge` then `updated.refunded = true`.
8. **Contracts:** `requires` / `ensures` lines come directly after the signature line, then a blank line, then the body, all inside the `fn ... end`. Lines above the blank line are spec altitude. `result` names the return value, `old(x)` the entry value, `is` does an inline pattern test (`result is Ok(c) implies c.refunded?`).
9. **Module header and ****`never`****:** `module Payments.Refund` with dot paths (Robert's pick; `::` rejected, one symbol one idea, Elixir made the same call). One module per file. `intent "..."` line. A `never` is a quoted sentence plus a block that evaluates true when the bad thing has happened; both mandatory, so a `never` is never just a comment. The sentence is the human's, the block is the agent's. `flows(CardNumber, into: Log)` expresses information-flow rules checkable statically via capabilities.
10. **Process:** `process Name(db: Ledger, clock: Clock) ... end` with capabilities as process parameters (the process's entire authority on line one). `state ... end` block is the struct in the box. `message Increment` lines, one per message. `fn update(state, message)` is the one function that changes the box; **`state`**** is implicitly mutable inside ****`update`** (`state.count += 1`), no return needed. `invariant "sentence" ... end` in the same shape as `never`, checked after every update. Robert found the first version confusing; the counter example clarified it.
11. **Loops and anonymous functions:** `for x in xs ... end` and `for i in 0..n ... end` are the only loops, bounded by construction; no `while`, no `loop`; `break` allowed within a bounded loop. Anonymous functions reuse the keyword: `fn(r) r.charge == c.id end`, Elixir-style. Ruby trailing `do |x|` blocks rejected as a second way.
12. **Tests:** in the same file as the code, under it. No test directory, no framework, no imports. `test "sentence" ... end` positive-space with one property per `assert`; `test rejects "sentence" ... end` passes only if the body trips a contract (how the compiler proves every `requires` fires); `property "sentence"` with `any(Type)` generators run under many seeds by the simulator. Sentence names, not identifiers. Precedents: Zig's `test "name"` blocks (TigerBeetle is written this way), Pyret's `where:` blocks attached to functions, D `unittest`, Rust `mod tests` + doctests, Elixir doctests, Unison hash-cached tests. Nobody combines same-file + compiler-required + `rejects` + hash caching.
13. **Capabilities and logging:** capabilities are ordinary types obtained only at the program root (`fn main(platform: Platform)`), passed down explicitly, narrowed on the way (`fs.scoped("/var/app").read_only`). No global `File.open`; a signature is the complete list of what a function can touch. **No log statements exist in Mo.** The runtime already traces calls, arguments, results, and messages deterministically for replay, and crashes carry seed + trace; ad-hoc logs are a worse copy of that and the most common secret leak. Domain events go out through a typed `Events` capability (`events.emit(RefundFailed(...))`), so `flows(CardNumber, into: Events)` is checkable.
14. **Modules:** private by default, `pub` to expose (the `pub` lines are the spec altitude's table of contents). One `use` form: `use Payments.Ledger` or `use Payments.Ledger.{Charge, Money}`; no wildcards, no aliases, no relative or file paths. One module per file; file path equals module path (`payments/refund.mo`). No cycles; the compiler names the cycle. Any change to a `pub` signature or contract is a breaking version change, decided by the toolchain. Elixir's four keywords (`alias`/`import`/`require`/`use`) collapsed to one.
15. **Methods without objects, traits, generics:** dot calls are sugar for first-argument functions (`charge.within_window?(now)` is `within_window?(charge, now)`), uniform function call syntax as in Nim and D. No methods, no `self`, no classes. `trait Comparable ... end` lists functions a type promises; `impl Comparable for Money ... end` provides them. No inheritance, no overriding defaults, no trait objects in v1. Generics only via `where`: `fn largest(items: List(T)) : Option(T) where T: Comparable`.
### Current base (Robert's style, 12 Sep 2026)
```ruby
module Payments.Refund

intent "Refund a captured charge, at most once, within 90 days of capture."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured_amount
end

struct Charge
  id: ChargeId
  captured_amount: Money
  captured_at: Time
  refunded: Bool
end

enum RefundError
  AlreadyRefunded(id: ChargeId)
  WindowExpired(captured_at: Time, now: Time)
  Timeout
end

fn apply_refund(charge: Charge, amount: Money) : Result(Charge, RefundError)
  requires amount <= charge.captured_amount

  return Error(AlreadyRefunded(charge.id)) if charge.refunded?

  var updated = charge
  updated.refunded = true
  Ok(updated)
end

fn refund(db: Ledger, clock: Clock, id: ChargeId, amount: Money) : Result(Refund, RefundError)
  requires amount > 0

  now = clock.now
  charge = try db.find_charge(id, within: 200.ms)

  if !within_window?(charge, now)
    return Error(WindowExpired(captured_at: charge.captured_at, now: now))
  end

  updated = try apply_refund(charge, amount)
  try db.save_charge(updated, within: 200.ms)

  Ok(Refund(charge: id, amount: amount, at: now))
end

process Counter
  state
    count: UInt32
  end

  message Increment
  message Reset

  fn update(state, message)
    case message
      Increment: state.count += 1
      Reset: state.count = 0
    end
  end
end

test "second refund is rejected"
  charge = Charge.fixture(refunded: true)
  assert apply_refund(charge, 1_00) == Error(AlreadyRefunded(charge.id))
end
```
*The older Ruby-shaped draft below is superseded by the base above.*
### Draft example (Ruby-shaped)
```ruby
module Payments::Refund
  intent "Refund a captured charge, at most once, within 90 days of capture."

  never refund.amount > charge.captured_amount
  never a charge is refunded twice
  never card.number reaches log

  type Money = UInt64 where value <= 10_000_000_00

  struct Charge
    id              : ChargeId
    captured_amount : Money
    captured_at     : Time
    refunded        : Bool
  end

  enum RefundError
    ChargeNotFound(id : ChargeId)
    AlreadyRefunded(id : ChargeId)
    WindowExpired(captured_at : Time, now : Time)
    Timeout
  end

  def within_window?(charge : Charge, now : Time) : Bool
    requires now >= charge.captured_at

    now - charge.captured_at <= 90.days
  end

  def apply_refund(charge : Charge, amount : Money) : Result(Charge, RefundError)
    requires amount <= charge.captured_amount
    ensures  ok(c) implies c.refunded?

    return error AlreadyRefunded(charge.id) if charge.refunded?

    ok charge.with(refunded: true)
  end

  def refund(db : Ledger, clock : Clock, id : ChargeId, amount : Money) : Result(Refund, RefundError)
    requires amount > 0
    ensures  ok(r) implies r.amount == amount

    now    = clock.now
    charge = try db.find_charge(id, within: 200.ms)

    unless within_window?(charge, now)
      return error WindowExpired(captured_at: charge.captured_at, now: now)
    end

    updated = try apply_refund(charge, amount)
    try db.save_charge(updated, within: 200.ms)

    ok Refund.new(charge: id, amount: amount, at: now)
  end

  process RefundQueue
    state
      pending : List(RefundRequest) where size <= 1_000
      done    : UInt32
    end

    invariant done >= 0

    message Enqueue(request : RefundRequest)
    message Drain

    def update(state, message, db : Ledger, clock : Clock)
      case message
      when Enqueue(request)
        state.with(pending: state.pending.push(request))
      when Drain
        var done = state.done
        state.pending.each do |request|
          case refund(db, clock, request.id, request.amount)
          when Ok(_)     then done += 1
          when Error(e)  then log.warn(e)
          end
        end
        state.with(pending: [], done: done)
      end
    end
  end

  test "refund within window succeeds"
    charge = Charge.fixture(captured_at: t0, captured_amount: 5_00)
    assert apply_refund(charge, 5_00) == ok(charge.with(refunded: true))
  end

  test "second refund is rejected"
    charge = Charge.fixture(refunded: true)
    assert apply_refund(charge, 1_00) == error(AlreadyRefunded(charge.id))
  end

  test rejects "amount above captured violates requires"
    charge = Charge.fixture(captured_amount: 5_00)
    apply_refund(charge, 9_99)
  end

  verified by contracts, tests, simulation(runs: 1_000)
end
```
---
## Steal list: what to take from other languages
**Framing:** Go ships a scheduler and GC inside every binary and nobody calls it a VM. Inko and Pony prove Erlang-style isolated processes and message passing work natively in one binary. Mo can have a small linked-in runtime and still meet the single-binary bar. What we lose without the BEAM: hot code loading and the mature distribution layer. Probably fine.
### From Ruby (and Crystal)
- **Steal:** the reading experience. `def`/`end`, `case`/`when`, blocks with `do |x|`, `unless`, trailing conditionals, predicate methods ending in `?`, keyword arguments, everything is an expression.
- **Steal from Crystal:** proof that Ruby's syntax survives static types and native single binaries. `name : Type` annotations.
- **Leave:** five ways to write everything, optional parens as a choice, monkey patching, metaprogramming, dynamic typing, exceptions.
### From Elixir / BEAM
- **Steal:** processes as the unit of isolation, message passing as the only sharing, supervision trees, let-it-crash. AI-first twist: a crashed process + seed + message log is a contained, reproducible task for an agent. Failure becomes a unit of work.
- **Steal:** pattern matching everywhere, tagged results (`ok` / `error`), the pipe operator.
- **Adapt:** immutable data with structural sharing, implemented via Perceus-style reference counting with in-place reuse rather than per-process GC.
- **Leave:** dynamic typing, hot reload, Erlang term format, the VM.
### From Rust
- **Steal:** enums with data, exhaustive matching, Result/Option, no null, no exceptions, traits not classes, "if it compiles it works."
- **Steal:** compiler-as-teacher diagnostics, then go further: structured, machine-consumable errors with suggested fixes.
- **Adapt:** ownership guarantees (no aliasing+mutation, no data races) without the full borrow checker. Lifetimes are the biggest failure source for humans and agents alike; Hylo/Inko get the safety via value semantics and single ownership.
- **Leave:** lifetimes, macros, async coloring, trait-solver complexity, unsafe.
### From Go
- **Steal:** single static binary, one-flag cross-compilation, fast builds, one formatter with zero options, one build tool, batteries-included stdlib so most programs need no deps.
- **Steal:** small language (\~25 keywords). Simplicity is the AI-first feature.
- **Adapt:** ceiling on abstraction. Go says no by omission; Mo says no by law.
- **Leave:** nil, GC, `if err != nil`, implicit interfaces.
### From Elm
- **Steal:** zero runtime exceptions as a guarantee, not a goal. Proof that no-escape-hatch is achievable in a real language.
- **Steal:** effects as data. Pure functions return effect descriptions (`Cmd`); the runtime performs them. Inspectable, testable without mocks, and the natural hook for capabilities: the runtime refuses commands the process was not granted.
- **Steal:** compiler-as-patient-friend error messages (the origin of Rust's). AI-first version adds a structured form: category, location, likely cause, candidate fix.
- **Steal:** enforced semantic versioning by API diff. Mo can go further: a changed contract forces a version bump, not just a changed signature.
- **Steal:** the discipline of no. No custom operators, no user-level FFI (ports only), unchanged since 2019. A stable target is a feature for a language models must learn.
- **Steal:** replay/time-travel falls out of state + message log. Same destination as deterministic simulation.
- **Leave:** web-only, slow BDFL cadence, no abstraction over types (real boilerplate; Mo needs traits or similar).
**Unification spotted:** The Elm Architecture, an OTP GenServer, and a Redux reducer are the same shape: state + message + pure `update` returning new state and effects. Proposal: Mo has exactly one stateful construct, the process, and it is Elm-shaped. Everything inside is pure. Let-it-crash, replay, and agent testing (feed messages, check states) all fall out.
### From languages nobody is looking at
- **Austral:** capabilities as linear values. No filesystem access without an unforgeable, consumable token. Cleanest foundation for agent permissions. Shares our anti-magic, small-enough-for-one-head philosophy. [austral-lang.org](https://austral-lang.org/)
- **Koka:** effect types with handlers; Perceus compiles to plain C with no GC. Effects in the signature = how the spec altitude declares what a function touches. Possibly the single most AI-first feature. [koka-lang](https://github.com/koka-lang/koka)
- **Pony:** reference capabilities: the type says who may read and who may write, so mutable data moves between actors with no copies and no locks. Six caps is too many; the core idea is gold. [Pony reference capabilities](https://tutorial.ponylang.io/reference-capabilities/reference-capabilities.html)
- **Hylo:** mutable value semantics. Mutate locals in place, but no two names ever alias the same memory. Feels functional, runs like C. Possible resolution of functional-vs-mutable. [hylo-lang.org](https://hylo-lang.org/)
- **Roc:** the platform concept. The language has no I/O; a platform provides it. Same language for embedded, server, or agent sandbox. Unsafe parts live in the platform, not the language, which supports no-escape-hatch laws. [roc-lang.org](https://www.roc-lang.org/)
- **Inko:** existence proof of Erlang-style processes + deterministic memory + single ownership, natively, one binary. [inko-lang.org](https://inko-lang.org/)
---
## Idea backlog (Claude's proposals, awaiting reaction)
- **Stable semantic IDs** on every declaration so agents edit by ID instead of fragile text diffs.
- **Intent blocks** that bind a natural-language requirement to a function and its tests, so provenance is part of the source.
- **Capabilities as values with lifetimes.** A function cannot touch the network unless handed the network. Distinguish "what you may do" from "what you actually did."
- **Structured, fix-suggesting compiler errors** so an agent that starts wrong converges in two or three loops. The compiler is the agent's teacher.
- **One canonical formatting**, no options, ever.
- **Tiny grammar**, surface syntax close to something models already know, so knowledge transfers and the zero-training-data problem is softened.
- **Exhaustive result types**, no exceptions from nowhere, no hidden control flow.
- **Effect tracking** so every function declares what it touches (I/O, mutation, DB, network).
- The language's value lives in **what it checks**, not how it looks.
---
## Research summary (Sep 2026)
### Headline
Nobody has built this yet. Mojo hit 1.0 in Aug 2026 but is "for AI" in the sense of running AI workloads. Pel is a Lisp-ish agent-orchestration language. The closest real design is a blog sketch (PACT-Lang) that stayed a sketch. The space is open.
### Three findings that shape everything
- **Training-data gravity is real.** Dan Luu benchmarked agents building a full zstd decoder and modifying Pandoc across many languages. Obscure languages did badly even when denser. Popularity correlated with correctness. A new language starts with zero corpus: **our single biggest risk.**
- **Strictness helps models converge.** Go-for-agents debate, Dafny vericoding (verification success 68% → 97% in one year), verified Rust via Verus and Aeneas. Agents thrive when the compiler rejects wrong programs loudly and there is one way to do things.
- **The ideal AI language is one humans keep rejecting.** Explicit effects, exhaustive result types, contracts, totality. Friction for a human typist, a gift for an agent that iterates in a loop and never tires of annotations.
### Smaller things worth stealing
- Token efficiency matters less than people think at scale (Dan Luu). Don't contort syntax for it.
- "Lingering Authority" paper: revocable, time-bounded capabilities for coding agents; separate permission from actual effect. Fits an effect system perfectly.
- Research trend toward compilers emitting structured diagnostics (category, cause, suggested fix) for agent feedback loops.
### Sources
- [AkitaOnRails: Best programming language for LLMs](https://akitaonrails.com/en/2026/02/09/ai-agents-best-programming-language-for-llms/)
- [Dan Luu: token efficiency and correctness by language](https://danluu.com/pl-tokens/)
- [Do programming languages still matter to your AI coding agent teammate?](https://arxiv.org/pdf/2606.13763)
- [Lingering Authority: Revocable Resource-and-Effect Capabilities for Coding Agents](https://arxiv.org/pdf/2606.22504)
- [A benchmark for vericoding (POPL 2026)](https://popl26.sigplan.org/details/dafny-2026-papers/13/A-benchmark-for-vericoding-formally-verified-program-synthesis)
- [Pel: A Programming Language for Orchestrating AI Agents](https://arxiv.org/abs/2505.13453)
- [A case for Go as the best language for AI agents (HN)](https://news.ycombinator.com/item?id=47222270)
- [Mojo hits 1.0](https://www.theregister.com/ai-and-ml/2026/08/12/modulars-mojo-programming-language-hits-10-milestone/5286545)
- [Aeneas: Bridging Rust to Lean](https://lean-lang.org/use-cases/aeneas/)
- [Token Sugar (ASE 2025)](https://dl.acm.org/doi/10.1109/ASE63991.2025.00201)
- [AI Coders Are Among Us: Rethinking Grammar](https://arxiv.org/pdf/2404.16333)
---
## Next session
**All remaining questions now live on the **[**Open Questions & Recommendations**](https://app.notion.com/p/3d96bcfa7c7581288f6bfde6a5b81865)** page, each with options, a recommendation, and why, plus the full example regenerated in the current style and the proposed path after alignment.** The list below is kept for reference.
**Remaining syntax pieces (small):**
- Literals, strings, interpolation, comments, numbers with units (`200.ms`, `90.days`, `5_00` money).
- `Option` and the absence of nil; how `Option` is matched and combined.
- The `verified by ...` line: what levels exist and who writes it.
- Regenerate the full example in the final style and read it end to end on the phone.
**Bigger topics still open:**
- The verification dial in practice: what runs at runtime vs what the SMT pass proves, and how the verification level is displayed.
- Compiler diagnostics as the agent's teacher: the structured error format.
- Semantic IDs and how agents edit Mo (by ID vs by text).
- The platform concept (Roc-style): what the standard platform provides, and the standard library policy (batteries-included, zero deps).
- First real program (deferred from Q2; attributes are now mostly known, so the domain can fall out).
- The name: is "Mo" decided, and the story.
- Then: compare the design against existing languages, and decide what to lock.
---
## Session log
- **12 Sep 2026, session 1 (cont).** Negative space programming: Claude laid out five levels and proposed `never` clauses as the human-facing surface. Robert: humans shouldn't write any of it. Revised to speak/write/read split; humans pulled in when the shape changes. Robert: none, the agent takes the crash and fixes it. Type system: Robert chose Rust-plus-refinements from day one. Compilation target: Robert agreed with C-via-Zig then LLVM, and added compile speed as a hard requirement; Claude researched Zig/Roc/Unison and laid out the speed levers. Fast path: interpreter, then C, native backend only if proven necessary. Robert: in. Syntax: Claude proposed Rust/Gleam-shaped and showed an example; Robert rejected it, Ruby is his favorite language and the code must be enjoyable to read. Claude rewrote the example Ruby/Crystal-shaped. Robert: closer, but wants to pick piece by piece. Pieces 14 (modules) and 15 (dot-call sugar, traits, `where` generics) in. Session closed at \~1am Robert's time. Piece 13 (root-only capabilities, no log statements, typed events) in. Pieces 11 (loops, `fn(x) ... end`) and 12 (in-file tests, `rejects`, `property`) in. Robert intrigued by in-file tests; Claude cited Zig, Pyret, D, Rust, Elixir, Unison. Piece 10 (process) confused Robert; clarified with a counter. Robert dropped `.with` for plain `state.count = 0`, then wrote his own version of `apply_refund`: `fn ... end` blocks, no braces, `name: Type`, contracts flowing into the body. That is now the base. Pieces 1-9 originally chosen: braces (not def/end, not indentation), `fn` + Crystal types, bare `=` bindings, `if` rules, `case` with arrows, `try` + predicate `?`, call-style construction + `.with`, contracts above the brace, `module Payments.Refund` dot paths + `never` sentence-and-block.
- **12 Sep 2026, session 1 (cont).** Errors and failure: rain vs broken roof, no try-catch, crash-only bugs with supervisor restart. Robert: definitely in. Robert queued negative space programming for discussion next.
- **12 Sep 2026, session 1 (cont).** Effects and capabilities: Claude laid out effect types vs commands vs capabilities, then the direct-vs-command I/O fork. Conclusion: capabilities as parameters, direct-style I/O with runtime interception, green threads, mandatory deadlines. Robert: matches, capture it.
- **12 Sep 2026, session 1 (cont).** State deep dive: Claude mapped nine state models with pros/cons and proposed a layered synthesis. Robert asked for `var`/`inout` unpacked, then said: in, capture it.
- **12 Sep 2026, session 1 (cont).** Immutability confirmed. Robert: processes at the edges like Go. Robert raised Elm; Claude extracted lessons and proposed the process = Elm-shaped state machine unification. Open: is that too restrictive?
- **12 Sep 2026, session 1 (cont).** Robert switched to exploration mode: no decisions yet. Stated attributes: never OOP, Elixir-style functional, loves the BEAM but wants a single memory-efficient binary. Claude researched Roc, Koka, Hylo, Austral, Pony, Inko and produced the steal list. Open: what "mutable data is great" means.
- **12 Sep 2026, session 1 (cont).** Q1 answered: agents write \~100%, humans read at a high altitude. Claude proposed the two-altitude model. Robert pointed to Tiger Style and NASA's Power of 10 as old ideas to rethink AI-first; Claude mapped them into laws / dead rules / promoted features. Open: laws with no escape hatch?
- **12 Sep 2026, session 1.** Kickoff. Robert: 10+ yrs SWE, first language, motivated by AI. Claude ran a research pass on the 2026 landscape and laid out the three-way fork plus six interview questions. Awaiting answers.