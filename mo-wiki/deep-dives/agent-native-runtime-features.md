---
title: "Agent-native runtime features to test"
created: 2026-09-13
updated: 2026-09-13
type: deep-dive
tags: [runtime, agents, tooling, verification]
sources: [spec/design-v0/03-semantics.md, spec/design-v0/05-verification.md, spec/design-v0/07-toolchain.md, spec/design-v0/08-milestone.md]
confidence: medium
---

# Agent-native runtime features to test

Mo's differentiator against other languages is not any single feature — contracts, effects, capabilities, and process isolation all exist elsewhere. It's the composition, and specifically that the composition is designed for agents to write and reason about code. This page is a menu of runtime features that lean into that framing, sorted by how novel and load-bearing each one is.

Three tiers: novel and worth prototyping, proven and worth adopting aggressively, worth building only to learn from. Each item explains what it is, what Mo already has toward it, what it would cost, and what breaks if Mo doesn't have it.

The five directions promoted from this menu are [[d37-runtime-mcp-surface|d37]], [[d38-time-travel-debugging|d38]], [[d39-hot-code-reload|d39]], [[d40-structured-runtime-events|d40]], and structurally [[d36-vm-first-runtime|d36]] which makes them all easier.

## Tier 1 — novel, differentiating, worth prototyping

These are the ones that would make Mo something other languages can't do. Each is a real bet.

### Runtime MCP surface

Every running Mo program exposes an MCP server the agent can call. Tools like `list_processes`, `inspect_process`, `send_message`, `query_message_history`, `pause_process`, `resume_process`, `get_supervisor_tree`, `get_capabilities_in_use`.

What Mo has today: `mo check --json`, `mo test --json`, and the error catalog as the compile-time surface; no MCP command yet. The runtime is opaque beyond the crash report.

What it would give the agent: a real API into the running system. Debugging shifts from grep-the-log to programmatic inspection. Because Mo already has process isolation, capability tracking, and deterministic execution, most of the data is already there — the surface just needs to be exposed.

Cost: modest. A few weeks. Belongs in the VM (see [[vm-first-vs-c-first]]).

Without it: the agent debugs blind or through the crash report only.

### Time-travel debugging

The agent asks the runtime: "what was this process doing 30 seconds ago?" — and gets back the state, the message it was processing, its `update` transaction, its call stack. Then: "step forward one message."

What Mo has today: `Mo.Sim` is deterministic. Fault injection is reproducible from a seed. The failure model (chapter 3) is designed around replay from a snapshot plus message log. This puts Mo further toward time-travel debugging than almost any production language.

Cost: 4–6 weeks in a VM, much harder in C. Needs periodic snapshots and a query interface.

Without it: agent-driven debugging is much weaker than it could be. The building blocks are there; not exposing them is leaving Mo's biggest advantage on the table.

### Structured "why" for every runtime decision

Every scheduler preemption, GC pass, supervisor restart, capability check, mailbox overflow, and timeout emits a structured event the agent can query. Not log messages — structured events with schema, tied to the code location and the reason.

What Mo has today: chapter 5's structured diagnostic format for compile-time errors. The crash report is structured. Runtime events currently go to stdout as prose.

What it would give the agent: instead of "the process timed out," "process #42 was preempted after 4096 reductions while blocked on `Http.get(url)` with 340 ms remaining on a 500 ms deadline, and its mailbox depth is 14 (limit 100)." The agent can reason about performance and reliability the same way it reasons about correctness.

Cost: a few weeks of taxonomy work plus emission code at ~15 sites. This is a design-heavy, code-light feature.

Without it: agents infer from logs, which is exactly the thing Mo's compile-time story rejects for diagnostics.

### `mo prove` counterexamples as fixable tests

When `mo prove` fails on a contract, it emits a Mo test that reproduces the failure — one the agent can immediately add to the corpus, ship as a regression, and iterate against.

What Mo has today: property tests (chapter 5), contracts, tests. `mo prove` is deferred (Q17).

Cost: small once `mo prove` exists. Independent of the SMT-vs-model-checker question.

Without it: `mo prove` returns "invalid" and the agent has to reconstruct the counterexample. With it, `mo prove` produces new tests, which then feed the corpus that trains everything else.

## Tier 2 — proven elsewhere, worth adopting aggressively

Not novel, but each one compounds. These are the "steal from BEAM/Nix/Rust" list.

### Content-addressed everything

Modules, functions, contracts, tests, capabilities, and every artifact addressed by hash. Chapter 8 already sketches `.mo.ids` (a manifest of stable ids for a module's public surface); extend beyond it.

What it would give: perfect caching, perfect incremental builds, a registry where "you have this exact code" is a hash check, and supply-chain guarantees where a compromised package can't produce a byte-identical replacement.

Cost: low. Mo's compiler is fast enough that recomputing hashes on every build is cheap.

### First-class fixtures for every capability

`Mo.Sim` for the scheduler, `Fake.Http` and `Fake.Net` for the network — already exist. Extend to `Fake.Storage`, `Fake.Clock`, `Fake.Random`, `Fake.Process`, `Fake.Supervisor`, `Fake.Env`.

What it would give: every effect a Mo program can perform has a fake the agent can use to write tests without mocking. Testing becomes composition, not ceremony.

Cost: one fake per capability, small each.

### Refusal reasons the agent can act on

Every compiler error and runtime failure comes with a machine-readable "here's what you'd need to change to fix this" hint. Extend chapter 5's error catalog.

What Mo has today: 66 error codes with human-readable messages and location info; steps 17 and 19 reworded nine of them to say what to write instead, and the rest do not all say it.

Cost: audit and augment.

### Property-test generation from contracts

`requires`/`ensures` on a function auto-generate a property test that fuzzes the inputs satisfying `requires` and asserts `ensures`. Free property tests everywhere contracts exist.

What Mo has today: contracts, property tests, the compiler's IR knows both.

Cost: 2 weeks of compiler work.

## Tier 3 — build to learn

Worth prototyping to see what breaks. Not obvious that any of these should ship, but the answers would sharpen Mo's design.

### Bidirectional contracts

Contracts describe the function; tests exercise it; the two update each other. If a property test discovers a case the contract didn't cover, the contract gets a suggested extension. If a contract is loosened, tests get suggested updates.

Prototype value: teaches Mo how much of the contract-writing burden can be moved to the machine.

### Effect-scoped memory quotas

Not just "this function can perform I/O" but "this function can allocate at most 1 MiB." Ties memory into the effect system, so `Mo.Sim` can inject allocation failures.

Prototype value: tests whether effect-scoped quotas add expressive power or just noise.

### Speculative execution with rollback

The `update` transaction extended: multiple candidate `update`s run in parallel, the runtime commits the first one that satisfies invariants. Mo's failure model already makes rollback cheap.

Prototype value: whether speculative execution is a useful primitive at the language level, or belongs in the application layer.

## Recommended build order

If Robert wants to test all of Tier 1, this is the order that maximizes what each step gives the next.

1. **Runtime MCP surface** (~1 week). Small, exposes what already exists. Everything else benefits from it.
2. **Structured runtime events** (~2 weeks). Feeds the MCP surface, feeds the crash report, feeds any future debugger.
3. **Time-travel debugging** (~4–6 weeks). The big one. Requires periodic snapshots and depends on the two above.
4. **Contract-to-property generation** (~2 weeks). Independent, high value.
5. **Refusal reasons audit** (~1 week). Grunt work but compounds.

Total: two months of focused work on one feature at a time gets Mo to a place no other language is.

## Meta-point

Every one of these treats the runtime as an API the agent programs against, not as invisible infrastructure. That is Mo's actual differentiator: not a specific feature, but the stance that the runtime is a first-class surface for the agent. If Mo picks three of these, [[d37-runtime-mcp-surface|MCP surface]], [[d38-time-travel-debugging|time-travel debugging]], and structured runtime events do the most to embody that stance.

## Fable's note on filing (13 Sep, night)

Tier 1 is the part of this page that is Mo-shaped: the runtime as a surface the agent programs against is the founding premise taken to its end, a crash as a task becoming a running process as a task. Two corrections on cost. The MCP surface must be a capability, held by `main`, off by default, narrowed like `Fs`; reading any process's state is the largest authority in the system, and direction 31 breaks the moment it is ambient. And time-travel is mostly built under `mo test`; what is new is recording in production and its cost, which is a measurement, not a design. Of tier 2, property tests from contracts and the fixture per capability are already partly true (`any(T)` under refinements since step 17; `Net.fixture`, `Http.fixture`, `Fs.fixture`, `Out.fixture`, `Time.fixture` exist). Program 1, the job queue, is the testbed for all of tier 1.

## Related

- [[vm-first-vs-c-first]]
- [[d36-vm-first-runtime]]
- [[d37-runtime-mcp-surface]]
- [[d38-time-travel-debugging]]
- [[d39-hot-code-reload]]
- [[d40-structured-runtime-events]]
