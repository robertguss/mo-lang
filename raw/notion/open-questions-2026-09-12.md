---
source_url: https://app.notion.com/p/3d96bcfa7c7581288f6bfde6a5b81865
source: Notion (Robert's work workspace, private page, exported before deletion)
exported: 2026-09-12
sha256: 8d54c57827ae98d85c352c05709935eabdb88cae3ebc6a71123f47f690f77ff7
---
# How to use this page
Every remaining question from session 1, each with the realistic options, my recommendation, and why. Read it on your phone, and for each one reply with **in**, **no**, or a counter-proposal. Nothing here is decided until you say so. The companion page is the Design Journal, which holds everything already agreed.
Questions are ordered so the small syntax ones come first and the big shape ones last. The very last section is what happens after we're aligned.
*Written 12 Sep 2026 by Claude, after session 1.*
---
## Part A: small syntax pieces
### Q1. Comments
**Options:** `#` (Ruby, Python, Elixir) or `//` (Rust, Go, C).
**Recommendation:** `#`.
**Why:** It's the Ruby and Python convention, it's one character, and `//` looks like division to a reader on a phone. Doc comments are just a `#` block directly above a declaration; no separate `##` or `///` form. One comment syntax.
✅ **Robert: IN** (session 2). Single comment form, no block comments, no doc-comment variant. Accepted cost: no commenting-out of regions; agents delete and let history hold it.
### Q2. Strings and interpolation
**Options:** Ruby `"Hello #{name}"` / Python `f"Hello {name}"` / Rust `format!("Hello {name}")`.
**Recommendation:** Ruby's `"Hello #{name}"`. Double quotes only. Multi-line strings with triple quotes `""" ... """`. No single-quoted strings, no heredocs, no raw-string variants.
**Why:** Ruby's form is the most-read interpolation syntax alive, and Elixir uses it too. Removing single quotes removes a choice agents don't need. Strings are UTF-8 always; `String.length` is grapheme count, `String.bytes` is bytes, so the ambiguity that bites every language is a named choice at the call site.
✅ **Robert: IN** (session 2). Also settled: every string interpolates (no prefix to forget), triple-quoted literals strip common leading indentation, no raw-string form — regex is a compiled Regex value, not a bare string.
### Q3. Numbers and units
**Options:** plain numerals only / numerals with unit suffixes as methods (`200.ms`, `90.days`) / a full units system.
**Recommendation:** unit suffixes as plain functions via dot-call sugar (`200.ms` is `ms(200)` returning a `Duration`), digit separators with `_` (`10_000`), and no implicit numeric conversion anywhere.
**Why:** `within: 200.ms` reads as English, and it's not magic, it's the dot-call sugar we already have. Money should never be a bare number; `5_00` in the examples was a placeholder and should become `Money.cents(500)` or a `Money` literal decided with the standard library.
✅ **Robert: IN** (session 2). Units are ordinary functions reachable by dot-call, so any project can add its own. No literal type suffixes (no 1u64, no 3.14f32); literals are typed by inference at the binding. A full dimensional-analysis units system was considered and rejected as too big for the target domain.
### Q4. Integer types and overflow
**Options:** wrap silently (C, Go) / crash on overflow (Rust debug, Zig safe modes) / checked types that return `Option`.
**Recommendation:** explicitly sized types only (`UInt8` ... `UInt64`, `Int8` ... `Int64`, `Float64`), overflow is a bug and crashes the process, and `checked_add` style functions return `Option` when the caller wants to handle it.
**Why:** Tiger Style: explicitly sized types. Rain-vs-roof: an unexpected overflow is a broken roof. Silent wrap is the classic hidden bug agents cannot see.
✅ **Robert: IN** (session 2). Crash on overflow in **every** build, not only debug — Rust's debug-only check was rejected because the guarantee must hold in the build that matters. Named variants checked_/saturating_/wrapping_ put the intent in the source. Integer divide-by-zero crashes; Float64 follows IEEE. Accepted cost: a few percent on hot integer loops, to be recovered by contract-proved bound elision and the background SMT tier — and, per the measurement rule, to be verified rather than assumed.
### Q5. Option and the absence of nil
**Options:** `Option(T)` with `Some`/`None` (Rust) / `Maybe` with `Just`/`Nothing` (Haskell, Elm) / a `T?` shorthand (Swift, Kotlin).
**Recommendation:** `Option(T)` with `Some(x)` and `None`, matched with `case` like any enum, plus one convenience: `value or default` as the only shorthand.
**Why:** `Option` and `Some` are the names models know best. `or` for defaults reads like English and covers 80% of uses; everything else is an explicit `case`. No `?.` chains, no `!!` unwraps, no implicit nil anywhere.
✅ **Robert: IN** (session 2). Same rule as Result: nothing turns a None into a crash. If absence is a bug at that point, the agent writes `requires x is Some(_)` and the contract crashes it honestly. No `if let`, no `T?` shorthand. Accepted cost: more `case` blocks than Swift/Kotlin; the function-length law pushes those into helpers, which is the intended direction.
### Q6. The `verified by` line
**Options:** written by the agent as a claim / computed by the compiler and displayed / both.
**Recommendation:** computed by the compiler, never written by hand. The toolchain appends and maintains a line per module: `verified: contracts, tests, simulation(1_000 runs), proofs(3 of 5)`. Editing it by hand is a compile error.
**Why:** It exists so a human can see the honest verification level at a glance. A human-writable claim is a comment; a compiler-maintained one is a fact.
✅ **Robert: IN** (session 2). In-file at the bottom (not a sidecar) so it travels with the code and shows on a phone. Fixed vocabulary: `contracts`, `tests`, `simulation(N runs)`, `proofs(k of n)`; `types` is implied. A pub module's line is part of its published interface. `proofs(k of n)` deliberately partial so a human can watch it climb.
### Q7. Process API syntax: spawn, send, receive, supervise
**Recommendation:**
```ruby
queue = RefundQueue.start(db, clock, events)     # returns a typed handle
queue.send(Enqueue(request: r))                  # fire and forget
reply = try queue.ask(Status, within: 50.ms)     # request/response

supervisor Payments
  child RefundQueue, restart: :always, max_restarts: 5 per 1.minute
  child Reconciler,  restart: :on_crash
end
```
`send` never blocks. `ask` blocks with a mandatory deadline. A handle is typed by the process, so sending the wrong message is a compile error. Supervisors are declared, not coded.
**Why:** This is OTP's proven shape with the dynamic typing removed. Declared supervisors mean an agent cannot forget to supervise; a process not under a supervisor does not compile.
✅ **Robert: IN** (session 2). Details settled: `Name.start(caps...)` returns a `Handle(Name)`, so a wrong message is a compile error. Reply types declared on the message line (`message Status : QueueStatus`) so `ask` is typed. `send` never blocks or fails; `ask` requires `within:` and returns Result with Timeout as rain. Supervisor vocabulary: `:always`, `:on_crash`, `:never`, `max_restarts: N per Duration`; `main` is the root supervisor. No links, monitors, `Process.exit`, or `receive` in user code — `update` is the only message handler. Later stdlib sugar, not a primitive: `Task.run(fn ... end, within:)` for one-shot helpers.
---
## Part B: the full example, regenerated in the current style
This is the base with every pick applied, including Q1–Q7 above. Read it top to bottom on the phone and note anything that bothers you.
```ruby
module Payments.Refund

use Payments.Ledger.{Charge, ChargeId, Money}

intent "Refund a captured charge, at most once, within 90 days of capture."

never "a refund exceeds its charge"
  for r in Refund.all, c in Charge.all if r.charge == c.id
    r.amount > c.captured_amount
end

never "a card number reaches an event"
  flows(CardNumber, into: Events)
end

# A refund that has been applied to a charge.
pub struct Refund
  charge: ChargeId
  amount: Money
  at: Time
end

pub enum RefundError
  AlreadyRefunded(id: ChargeId)
  WindowExpired(captured_at: Time, now: Time)
  Timeout
end

fn within_window?(charge: Charge, now: Time) : Bool
  requires now >= charge.captured_at

  now - charge.captured_at <= 90.days
end

pub fn apply_refund(charge: Charge, amount: Money) : Result(Charge, RefundError)
  requires amount <= charge.captured_amount
  ensures  result is Ok(c) implies c.refunded?

  return Error(AlreadyRefunded(id: charge.id)) if charge.refunded?

  var updated = charge
  updated.refunded = true
  Ok(updated)
end

pub fn refund(db: Ledger, clock: Clock, id: ChargeId, amount: Money) : Result(Refund, RefundError)
  requires amount > Money.zero
  ensures  result is Ok(r) implies r.amount == amount

  now = clock.now
  charge = try db.find_charge(id, within: 200.ms)

  if !charge.within_window?(now)
    return Error(WindowExpired(captured_at: charge.captured_at, now: now))
  end

  updated = try charge.apply_refund(amount)
  try db.save_charge(updated, within: 200.ms)

  Ok(Refund(charge: id, amount: amount, at: now))
end

pub process RefundQueue(db: Ledger, clock: Clock, events: Events)
  state
    pending: List(RefundRequest) where size <= 1_000
    done: UInt32
  end

  invariant "done goes backwards"
    state.done < old(state.done)
  end

  message Enqueue(request: RefundRequest)
  message Drain

  fn update(state, message)
    case message
      Enqueue(request):
        state.pending = state.pending.push(request)
      Drain:
        for request in state.pending
          case refund(db, clock, request.id, request.amount)
            Ok(r): events.emit(RefundCompleted(refund: r))
            Error(e): events.emit(RefundFailed(request: request, reason: e))
          end
        end
        state.pending = []
        state.done += 1
    end
  end
end

test "refund within window succeeds"
  charge = Charge.fixture(captured_at: t0, captured_amount: Money.cents(500))
  result = charge.apply_refund(Money.cents(500))
  assert result is Ok(c)
  assert c.refunded?
end

test "second refund is rejected"
  charge = Charge.fixture(refunded: true)
  assert charge.apply_refund(Money.cents(100)) == Error(AlreadyRefunded(id: charge.id))
end

test rejects "amount above captured"
  charge = Charge.fixture(captured_amount: Money.cents(500))
  charge.apply_refund(Money.cents(999))
end

property "any valid refund leaves the charge refunded"
  for charge in any(Charge), amount in any(Money) if amount <= charge.captured_amount
    assert charge.apply_refund(amount) is Ok(c) and c.refunded?
end

verified: contracts, tests, simulation(1_000 runs)
```
---
## Part C: the bigger open questions
### Q8. The verification dial in practice
**Question:** what checks run when, and what does an agent wait for?
**Recommendation:** three tiers, always in this order.
1. **Instant, blocking:** types, exhaustiveness, capabilities, `flows`, contract *presence*, test *presence*. The compile loop. Target under 50ms incremental.
2. **Fast, blocking:** contracts and invariants checked at runtime while running the module's own tests and `rejects` tests. Target under 100ms per changed function.
3. **Slow, background, cached by hash:** property tests under many seeds, simulation with fault injection, and the SMT prover trying to discharge `requires`/`ensures`/`never` statically. Results upgrade the `verified:` line when they land. An agent never waits on tier 3 to see whether its code compiles, but a merge into a supervised deployment requires tier 3 green.
**Why:** It keeps the agent loop fast (direction 23) without lowering the bar. The Dafny numbers say off-the-shelf models discharge contract-style proofs 82% of the time, so tier 3 will succeed often and quietly.
✅ **Robert: IN** (session 2). Also settled: a tier-3 failure on merged code is a bug, not a flag — a failed property is a found counterexample with seed + log, so the agent takes it as a fix task with no human involved (direction 21); a human is pulled in only if the fix changes a `never`. The 50ms / 100ms numbers are hypotheses that go into the benchmark suite on day one (direction 28).
### Q9. Compiler diagnostics as the agent's teacher
**Question:** what does an error look like?
**Recommendation:** every diagnostic is a structured record with a fixed shape, rendered two ways: Elm-style prose for humans, JSON for agents. Fields: `code` (stable ID like `MO0412`), `category` (type / contract / capability / flow / law), `location` (semantic ID + line), `what` (one sentence), `why` (the rule and its rationale, one paragraph max), `fix` (zero or more concrete candidate edits, machine-applicable), `confidence`. Errors only; no warnings exist.
**Why:** An agent that receives a candidate fix converges in one loop instead of three. Stable codes mean the fix for `MO0412` is learnable across the whole corpus. The `why` field is how the language teaches its own philosophy to a model that has never seen it, which is the mitigation for zero training data.
✅ **Robert: IN** (session 2). `why` text is written once per code in the compiler's error catalog, which becomes the long-term home of the design philosophy — the catalog is the teaching material. Every `fix` candidate carries a confidence. Warnings rejected as a social mechanism with no one on the other end.
### Q10. Semantic IDs and how agents edit Mo
**Question:** do agents edit text, or the tree?
**Recommendation:** both, with text as the source of truth. Every declaration gets a stable ID assigned by the toolchain on first appearance and stored in a sidecar the formatter maintains (`.mo.ids`), never in the source. Tools expose `edit(id, new_source)` and `rename(id, name)` so an agent can change a function without a fragile text diff, and the content hash of a declaration (for caching) is separate from its identity (for editing).
**Why:** Text stays the shared language humans and agents read. IDs solve the two agent pain points: edits landing on the wrong line after a concurrent change, and renames breaking references. Keeping IDs out of the source keeps the page clean.
✅ **Robert: IN** (session 2, after a full unpack — see the deep dive "ID-addressed editing"). Settled: the unit of edit is the declaration, which the 40-line law keeps to one screen; a small fixed set of named sub-targets (`.contracts`, `.state`, `.update`) and `insert --after` / `delete`; edits are parsed before applying and rejected whole if broken; optimistic concurrency via `--expect hash:`; `rename` is a semantic operation across files; diagnostics and edits share the ID as join key. Plain-text editing always remains as the never-wrong, more-fragile fallback.
### Q11. The platform concept and the standard library
**Question:** where do I/O primitives live, and how batteries-included is Mo?
**Recommendation:** Roc's split. The **language** has no I/O; it only knows capabilities as types. A **platform** is a package that provides `main`'s `Platform` value and implements the runtime hooks: scheduler, I/O, the simulator. Ship one official platform, `Mo.Server` (files, network, clock, processes, events), and one test platform, `Mo.Sim` (deterministic everything). The **standard library** is Go-sized: collections, strings, JSON, HTTP client and server, time, crypto primitives, and nothing web-framework-shaped. Zero third-party dependencies for the toolchain itself, Tiger Style.
**Why:** Platforms are where the no-escape-hatch law becomes livable: unsafe code exists only in a platform, written and audited once. A batteries-included stdlib is what lets most programs have zero dependencies, which is the single biggest thing Go got right for agents (less choice, less entropy).
**Session 2 additions:** swapping `use Mo.Server.{Platform}` for `use Mo.Sim.{Platform}` in `main` is the whole simulation story, one line. Stdlib list: List, Map, Set, String, Json, Time, Http (client + server), Crypto primitives, Regex. No web framework, ORM, or CLI-args framework. Package ecosystem for domain-shaped things (Postgres, gRPC) is a later question; the stdlib doesn't try to be it.
✍️ **Robert (in / no / counter):** 
### Q12. Law numbers
**Question:** the concrete limits behind the laws.
**Recommendation:** function bodies at most **40 lines** (Tiger Style is 70; agents write tighter, and 40 fits a phone screen and a context window chunk). Files at most **500 lines**. Parameters at most **6** (beyond that, a struct). Nesting depth at most **3**. Process state at most **12 fields** before the compiler demands a nested process. All enforced as errors, all tunable per-project downward only, never upward.
**Why:** Numbers make laws real. Every one of these is a forcing function toward decomposition, which is what keeps units agent-sized.
**Session 2 note:** all five numbers are hypotheses under direction 28 — the corpus (roadmap step 4) is where we measure whether 40 lines is right.
✍️ **Robert (in / no / counter):** 
### Q13. Implementation language for the Mo toolchain
**Options:** Zig / Rust / OCaml / Go.
**Recommendation:** **Zig.**
**Why:** Roc moved its compiler from Rust to Zig and got 100x faster incremental builds. TigerBeetle is Zig, so the culture we're borrowing has its tooling there. Zig's toolchain is also our C compiler and cross-compiler, so the whole build has exactly one dependency. OCaml would be faster to write a compiler in but adds a second toolchain. Rust's compile times are the thing we're escaping. Self-hosting Mo in Mo is a later milestone, not a starting point.
✍️ **Robert (in / no / counter):** 
### Q14. The first real program
**Options** (from session 1): agent harness / backend service with a DB / infrastructure component (queue, KV store, proxy) / the Mo toolchain itself.
**Recommendation:** **a durable job queue with a small HTTP API.** Enqueue jobs, workers pull them, retries with backoff, dead-letter, exactly-once delivery as a `never`.
**Why:** It exercises every distinctive feature at once: processes with real state, supervision, deadlines, capabilities (DB, network, clock), `never` clauses that matter (never lose a job, never run one twice), simulation with fault injection, and events. It's small enough to finish and real enough that people would use it. It's also the backbone of an agent harness, so it leads naturally to option one without betting on it.
✍️ **Robert (in / no / counter):** 
### Q15. The name
**Question:** is "Mo" it, and what's the story?
**Recommendation:** keep **Mo**. Two letters, pronounceable in every language, the file extension `.mo` is free in practice (gettext uses it for binary catalogs, which never collide with source files), and `mo` as a CLI name is short. Story candidates: "Mo" as in *more with less*, or *modus*, or simply a name that isn't an acronym. The only thing to check before committing: existing projects named Mo in the language space (there is a small "Mo" scripting language from years ago, essentially dormant).
**Why:** Names that are words fail search; names that are two syllables and mean nothing (Go, Zig, Roc, Elm) win. Mo is in that family.
✍️ **Robert (in / no / counter, and the story if you have one):** 
### Q16. Escape hatch, revisited
**Question:** parked in session 1: laws with no override, ever?
**Recommendation:** **yes, no override in the language**, and the platform is the escape hatch. If a program genuinely needs something the laws forbid, that thing gets written once in a platform, audited, and exposed as a capability.
**Why:** With the platform split (Q11) this is no longer a hard stance, it's a place. Every "unsafe" thing has a home, and it's never in application code.
✍️ **Robert (in / no / counter):** 
---
## Part C2: added in session 2
### Q17. Package management and supply-chain security
**Raised by Robert (session 2), flagged as very important.** Two linked goals:
1. **A robust standard library that minimizes the need for third-party packages.** Learn from Go: most programs should have zero dependencies.
2. **An ecosystem designed against supply-chain attacks from day one.** npm and the other popular package managers are being hit at a scale AI has made unprecedented (malware, typosquatting, maintainer takeover, install scripts, dependency confusion). Mo and its ecosystem must be designed to mitigate this and keep people and software safe. Robert: "I don't know what this looks like yet, but we need to enforce security somehow."
**What Mo already has that helps (to build on, not yet decided):**
- **Capabilities are the permission system.** A package can only do what it is handed. A JSON library that takes no `Network` parameter provably cannot phone home. This is the property npm fundamentally cannot offer, and it should be visible at install time: "this package needs: nothing" vs "this package needs: Network, FileSystem".
- **No escape hatch in application code (Q16).** Unsafe code lives only in platforms, so a library cannot smuggle in raw syscalls.
- **No install scripts, no macros, no build-time code execution.** The three biggest npm/PyPI attack surfaces do not exist in the language.
- **Content-addressed declarations (Q10).** Every function has a hash; a package is a set of hashes, so "what changed in this version" is exact and "the registry served different bytes" is detectable.
- **`flows(...)` checks.** Information-flow rules can state that no secret reaches a dependency's outputs.
**Open sub-questions for the design pass:** registry model (central vs. vendored vs. Go-style URL modules); immutable versions and a transparency log; signing and who signs; capability manifests as part of a package's published interface, with any widening being a breaking change a human sees (the same rule as `never` clauses); minimum-privilege by default when adding a dep; typosquat resistance (namespacing, name reservation, similarity checks); how the toolchain audits a platform, since platforms are the trusted layer; whether the stdlib ceiling (Q11) should be raised to keep more of the common surface first-party. Needs fresh web research on 2025–2026 supply-chain incidents and on what Go, Deno, and cargo-vet have tried.
✍️ **Robert:** 
---
## Part D: what happens after we're aligned
Once you've gone through Q1–Q16, here is the path I'd propose. Each step produces something you can read or run.
1. **Write the Mo design document, v0.** Not a formal spec: a 15-page narrative that states the philosophy, the laws, the semantics, and the syntax, with the refund example as the running thread. This is the artifact we compare against other languages and show to people. I'd draft it from the journal; you'd edit by taste, the way you did with the syntax.
2. **The comparison pass.** Take the v0 doc and hold it against Elixir, Go, Rust, Gleam, Roc, Koka, Austral, Zig, and Elm, one page each: what Mo does differently, what it gives up, what it should steal that we missed. This is the research you asked for at the start, done against a concrete design instead of in the abstract.
3. **Lock v0.** After the comparison, convert "directions we like" into decisions, in one sitting.
4. **Write the grammar.** A formal grammar for the syntax, small enough to print on two pages, and a corpus of 30–50 tiny Mo programs that exercise every construct. The corpus doubles as the first training material for agents.
5. **Build the interpreter.** In Zig. Lexer, parser, type checker, capability checker, contract runtime, tests runner. Milestone: the refund module runs and its tests pass, `rejects` included. This is where an agent starts writing Mo for real, and where the design meets reality.
6. **Build the first program** (Q14) in Mo, using agents, with you reading at the spec altitude only. This is the test of the founding premise.
7. **Then** the C backend, the simulator, the SMT pass, and the platform split, in whatever order the first program demands.
Steps 1–4 are days. Step 5 is weeks. Step 6 is where we find out if the idea is right.
