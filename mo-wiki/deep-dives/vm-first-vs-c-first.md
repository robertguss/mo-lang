---
title: "VM-first vs C-first for the Mo runtime"
created: 2026-09-13
updated: 2026-09-17
type: deep-dive
tags: [runtime, compiler, performance, agents]
sources: [spec/design-v0/07-toolchain.md, spec/design-v0/03-semantics.md, toolchain/src/vm.zig, toolchain/runtime/mo_rt.c]
confidence: medium
---

# VM-first vs C-first for the Mo runtime

Chapter 7's build order is explicit: interpreter first, C via Zig for release, "a native backend only if a real program proves the first two insufficient." Mo today sits exactly at that fork. This page names what a VM would own that the C backend cannot, what the C backend owns that a VM cannot, and where the two paths diverge over time.

Written after an outside conversation on 13 Sep 2026 in which Robert reacted well to VM-first, specifically because of hot code reload and agents attaching to running processes for debugging.

## Terms, three lines each

- **Bytecode interpreter.** Reads bytecode instructions and does what they say. Simple. Slow-ish.
- **VM (virtual machine).** Bytecode interpreter plus a designed runtime: scheduler, memory manager, isolation, capability enforcer, hot reload, debugger, and optionally a JIT. "VM" is a container word; what matters is which runtime services it owns.
- **JIT (just-in-time compiler).** The VM compiles hot bytecode into native machine code at runtime, based on observed patterns. V8, modern JVMs, LuaJIT.

## What Mo has today

Mo already has a VM. `toolchain/src/vm.zig` is a stack-based bytecode interpreter. `toolchain/src/bytecode.zig` defines the format. It runs everything the language does: contracts, tests, properties, the `Mo.Sim` scheduler, `Net`, `Http`, processes, supervisors, `update` transactions, `invariant` checks, capability enforcement, fault injection.

Mo also has a native compiler. `toolchain/src/emit_c.zig` emits C11; `toolchain/src/cbuild.zig` drives `zig cc` to a static binary; `toolchain/runtime/mo_rt.{c,h}` is the C runtime shipped inside every native binary. The C runtime has ported the scheduler, `Mo.Sim` turns, mailboxes, `ask` with deadlines, supervisors, `update`, invariants, the crash report, `Net`, and `Http`.

They are differential-tested against each other, zero differences on the corpus.

So the question is not "should Mo have a VM" — it does. The question is which of the two is the primary target, and which is the secondary.

## The two paths

### Path A — VM-first: C backend is an optimization

The VM owns the runtime. Every Mo program runs on the VM in dev, test, and production. The C backend produces fast binaries for specific deployments (edge, embedded, cold-start-sensitive), and its runtime is a stripped-down port of the VM's.

What you get:

- Uniform semantics: the VM is the reference, everything else conforms.
- Runtime services (hot reload, live introspection, JIT if wanted) are available in production, not just development.
- One debugging story.
- The failure model, capability enforcement, and deterministic replay live in one place.

What you pay:

- The VM has to be production-quality: fast, robust, no latency spikes.
- Native performance ceiling is lower than pure C unless a JIT is added.
- Deployment carries the VM (typically 5–20 MiB), which matters on edge and embedded.

Precedent: BEAM (Erlang/Elixir), the JVM (Java/Kotlin/Scala), .NET. BEAM is the closest match to Mo because it's built around processes and supervision.

### Path B — C-first: VM is a development tool

The C backend is the production target. The VM exists for the edit loop, tests, `Mo.Sim`, and reference semantics. Shipped programs are native binaries. Runtime features that don't port cleanly to C (hot reload, live introspection, JIT) are dev-only or never exist.

What you get:

- Native performance ceiling (2–7× the interpreter on the corpus today).
- Small binaries, fast cold start, trivial deployment.
- One dependency (Zig).
- Chapter 7's build order as written.

What you pay:

- Two runtimes to maintain in lockstep, with the differential test as the safety net.
- Runtime features that don't port cleanly are dev-only or missing.
- Every capability, scheduler, or memory decision gets implemented twice.

Precedent: OCaml (`ocamlc` bytecode, `ocamlopt` native — chapter 7 cites this). Go and Rust are C-primary with no VM at all.

## What a VM would own, feature by feature

Each row: what it is in one line, what it would give Mo, what Mo has toward it today, the cost, and how load-bearing it is for the agent-authored premise.

### Preemptive, reduction-counted scheduling

**What.** The VM counts operations as each process runs; after N reductions it forcibly suspends the process and runs another. BEAM does this to keep one process from starving others without needing cooperative yield points.

**Gives Mo.** Fair scheduling across thousands of processes with no cooperation from user code. A tight loop cannot freeze the system. Combined with bounded mailboxes, this is what makes "let it crash" safe under load.

**Today.** The interpreter and native runtime both have schedulers (`sim.zig`, `turns.zig`, `mo_rt.c`); the CHANGELOG describes them as "processes on threads of their own taking turns," which reads cooperative rather than reduction-counted. Worth verifying against the source.

**Cost.** ~2–5% overhead in a bytecode interpreter. Native code has no natural place to count reductions — you'd inject checks at function calls and loop backedges, which is why Go compiles them in and C-runtime-based languages usually don't.

**For Mo.** This is one of the strongest arguments for VM-primary. Preemptive scheduling is much easier to implement correctly in a VM than in generated C.

### Per-process heap with O(1) crash cleanup

**What.** Each process gets its own private heap; on process death, the whole heap is freed as one operation. BEAM's model. Chapter 7's hypothesis: "each process gets its own heap region so a crash frees it whole."

**Gives Mo.** The failure model (chapter 3) becomes cheap. `update` rollback and post-crash cleanup are O(1) instead of O(live-data). Program 4 showed 200,000 processes at 9 MiB native, so the footprint is already excellent.

**Today.** The interpreter uses a region allocator (`region.zig`), "freed at safe points." Whether each process has its own region is worth verifying.

**Cost.** Each process has a minimum heap size (BEAM defaults to 233 words). Message passing copies between heaps rather than sharing pointers.

**For Mo.** Core to the failure model working at scale. Whether the VM enforces it or the C runtime does, someone has to.

### Load-time bytecode verifier

**What.** Before running a module's bytecode, the VM structurally verifies it, type-verifies it, and effect-verifies it (declared capabilities match induced capabilities). JVM's classfile-verifier model.

**Gives Mo.** Compiled bytecode becomes a distributable, inspectable, verifiable artifact. `mo audit some-package.mobc` becomes a fast deterministic operation. Registry-side capability-widening detection becomes trivial.

**Today.** Chapter 6 says packages are source, never binaries. The bytecode in `bytecode.zig` is in-memory, not a distribution format.

**Cost.** A verifier is a real project, though Mo's bytecode is simpler than JVM's, so this is thousands of lines, not tens of thousands.

**For Mo.** Deferred by design. Only becomes urgent if Mo ever distributes compiled artifacts (confidential source, faster installs, offline).

### Hot code reload

**What.** The VM swaps a module's code while processes are running. BEAM's signature feature. Chapter 8 lists it as an open question.

**Gives Mo.** Dev iteration without process teardown. In production, zero-downtime deploys. In the agent loop, the agent fixes a crashed process and reloads without losing the supervisor tree's accumulated state.

**Today.** Nothing.

**Cost.** One of the hardest features to get right. Needs versioned module tables, state-migration rules (state serialized under v1 has to be readable by v2), and a story for functions in flight when the swap happens. Erlang took years.

**For Mo.** Attractive but not on the critical path. 116 ms incremental rebuild time makes cold restart cheap enough for dev. Production hot reload becomes interesting when Mo has real deployments.

### JIT compiler

**What.** The VM compiles hot bytecode into native machine code at runtime.

**Gives Mo.** Interpreter performance approaches or exceeds native code on hot loops.

**Today.** Straight bytecode interpreter. Native performance comes from the C backend.

**Cost.** A production JIT is multi-person-years. GraalVM/Truffle offers "JIT for free" via partial evaluation but requires implementing the interpreter in a specific style.

**For Mo.** Not on the roadmap and shouldn't be. If Mo ever needs JIT-like specialization, Truffle is the shortest path.

### Deterministic execution and replay

**What.** Same bytecode, same inputs, same seed = identical execution, byte for byte.

**Gives Mo.** Chapter 3's "every process is replayable from a snapshot plus its message log" becomes real. `Mo.Sim` with faults becomes a deterministic bug hunter. Property-test counterexamples reproduce exactly.

**Today.** `Mo.Sim` already does this. `sim.zig` is seeded; the stdlib is deterministic by law.

**Cost.** Every source of nondeterminism has to be paid for or eliminated. Mo's design already does this.

**For Mo.** One of Mo's most load-bearing decisions, already implemented. The VM owning it (rather than each program) is what makes it uniform.

### Live introspection

**What.** The VM exposes a protocol for listing processes, inspecting state, reading message queues, attaching to a running program. BEAM's `observer`, JVMTI, Chrome DevTools Protocol.

**Gives Mo.** The agent can query a running system directly instead of grepping logs or adding print statements. Turns debugging from an archaeology exercise into an API call.

**Today.** Crash reports, structured diagnostics, MCP-over-toolchain for edits. No `mo attach pid 1234`.

17 Sep 2026: built — the runtime surface over HTTP answers exactly these queries (step 23, step 32).

**Cost.** Modest. A few percent overhead when active. Protocol design is straightforward.

**For Mo.** Almost certainly worth building. Belongs in the VM. Covered separately in [[d37-runtime-mcp-surface|d37]].

17 Sep 2026: built, at steps 23 and 32.

## Where Mo actually sits

Currently on **Path B**, and doing it well. The differential-testing discipline makes it safe. Native performance (23,692 gets/s on program 4, 200,000 processes at 9 MiB) validates the choice for what's been built.

Two things about Mo's design pull toward Path A over time:

1. **Live introspection matters more for agents than for humans.** A crash report is a snapshot; live introspection is the film. The agent debugging a bad state benefits enormously from being able to query "what messages did this process receive in the last minute" versus reading a log. This is a VM feature by nature.
2. **Hot reload matters more for agents than for humans.** A human writing a service accepts restart cycles. An agent that just fixed a bug wants to reload the fix without losing the supervisor tree's accumulated state. Even a 116 ms rebuild is orders of magnitude slower than zero.

## Recommendation

Stay on Path B for now, but design the VM as if it will become Path A eventually. Concretely:

- Own the scheduler and process model in the VM first, then port to C carefully. If reduction counting isn't in the VM, add it there.
- Make the VM's introspection surface deliberate — a documented protocol, not ad-hoc. Even if not exposed to users yet, the design shapes everything.
- Don't add hot reload or JIT yet. Expensive and premature. But don't foreclose them.
- Treat the C backend as "the VM's semantics, compiled ahead of time" rather than a separate implementation. The differential tests already enforce this.

The moment to reconsider Path A is when a real Mo program wants something the C backend fundamentally cannot provide. Most likely triggers: hot reload, live agent debugging of production processes, or a workload where JIT-only performance matters.

## Fable's note on filing (13 Sep, night)

Two things the page asked to verify: the schedulers are cooperative at waits, not reduction-counted (a process gives up its turn at a call that waits; step 15's decision rows), and each process does have its own region and address reservation (step 12), so per-process cleanup is already what the failure model's rollback rests on. The recommendation, stay on Path B and design the VM as the eventual primary, is the one Fable holds too: it costs nothing today, and the differential test already treats the C runtime as the VM's semantics compiled ahead of time. The order Fable would build the directions in is d40, d37, d38, d39, because the events feed everything and hot reload needs a state-migration design that program 1 should inform. Filed as drafts from Robert's outside session; nothing here is a decision-log row until Robert locks a direction.

## Related

- [[d36-vm-first-runtime]]
- [[d37-runtime-mcp-surface]]
- [[d38-time-travel-debugging]]
- [[d39-hot-code-reload]]
- [[agent-native-runtime-features]]
