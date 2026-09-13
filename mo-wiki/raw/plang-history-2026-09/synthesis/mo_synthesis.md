# Mo Synthesis: What History Says to a New AI-Era Language

*A Mo-specific reading of the 145,000-word research bundle. Mo is an in-development programming language ([github.com/robertguss/mo-lang](https://github.com/robertguss/mo-lang)) whose design bet is that AI agents will author most Mo code, so annotation cost paid by an agent is worth much more per keystroke than annotation cost paid by a human. This document maps the historical evidence onto Mo's stated direction and returns opinionated, actionable recommendations — with the tradeoffs made explicit so Robert can accept or reject each one.*

---

## Opening — Mo's opportunity is the shift in annotation economics

Every previous generation of language designers ran into the same wall. A property could be enforced in the type system only if the marginal keystroke cost to a human author was less than the marginal reasoning benefit. Eiffel's design-by-contract, Ada's SPARK subset, Clean's uniqueness types, Coq/Agda dependent types, Liquid Haskell refinements, and Rust's lifetime annotations all crossed that threshold for specific communities and remained off-limits to the mainstream ([Bertrand Meyer on Eiffel](https://en.wikipedia.org/wiki/Bertrand_Meyer); [Liquid Haskell page](https://ucsd-progsys.github.io/liquidhaskell/); [Idris multiplicities docs](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)). Simon Peyton Jones's canonical apologia for Haskell — "Wearing the Hair Shirt" — is a language designer acknowledging that laziness and purity are hair shirts users must be persuaded to wear ([Peyton Jones, "Wearing the Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)). The G11 camp in the design-camps report captures the moment the wall moves ([design_camps_and_tradeoffs.md, G11](../camps/design_camps_and_tradeoffs.md)): when the *agent* is the author, verbose contracts and explicit capabilities are cheap; when the *human reviewer* is downstream, machine-verifiable structure is what makes review tractable.

Verus is the first mainstream statement of this observation. It layers pre/post/invariant annotations onto Rust and dispatches them to Z3, at an annotation density that would be prohibitive for most human teams but is trivial for a machine author ([Verus arxiv paper](https://arxiv.org/abs/2303.05491); [Verus guide](https://verus-lang.github.io/verus/guide/)). Roc's "no side effects except through platforms" and pure-by-default semantics play the same game from a different angle: an agent that emits Roc code is emitting code whose intent the reviewer can trust the type system to summarize ([Roc "Fast"](https://www.roc-lang.org/fast); [Roc FAQ](https://roc-lang.org/faq.html)). Mo's stated direction — agent-authored design, contracts/capabilities/effects/regions, package-supply-chain security as a language concern, machine verification with stronger leverage than novel syntax — is a coherent bet on this inverted economics.

The rest of this document maps the camps against Mo's opportunity, section by section.

---

## Paradigm choice — what Mo should borrow from OO, FP, logic, concatenative

The paradigm camp catalog in the research bundle is deliberately not a "pick one" menu; Peter Van Roy's *Programming Paradigms for Dummies* argues that paradigms differ "only in one or a few concepts" and that a serious designer should choose concepts, not paradigms, and combine them with care ([Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf); [Van Roy & Haridi, CTM](https://webperso.info.ucl.ac.be/~pvr/VanRoyHaridi2003-book.pdf)). Mo should follow Van Roy's methodology and pick concepts.

**From imperative (A1)**: the ability to talk about the machine when the machine matters. Rob Pike's Go retrospective argues that Go was designed for "the software engineering done at Google" — programmers working on multi-million-line systems who need to hold the language in one head ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)); Andrew Kelley's Zig thesis is that a systems programmer needs to know what the machine will do at each source location ([Kelley, "Introduction to Zig"](https://andrewkelley.me/post/intro-to-zig.html)). Mo's active dev repo already runs a VM with region allocation, memoization, and benchmarks; the imperative substrate is present. Mo should keep the "no hidden control flow, no hidden allocations, no preprocessor" discipline that Zig articulates, because that discipline is *precisely* what makes agent-generated code auditable: an agent that emits `alloc region_r { ... }` is emitting a locally-inspectable allocation site rather than an ambient GC call the reviewer must trace to a runtime.

**From class-based OO (A2a)**: encapsulation of data with its permitted operations. What Mo should *not* borrow is inheritance. The historical evidence — Java's `final` misuse, C++'s fragile-base-class problems, Alan Kay's own criticism that class-based OO captured "the least important half" of the original vision ([Kay, "The Early History of Smalltalk," HOPL II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)), and Rich Hickey's argument that classes *complect* state, identity, and behavior ([Hickey, "Simple Made Easy"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)) — is that deep inheritance hierarchies produce brittle designs. Rust's alternative — traits (interfaces) plus structs, with composition and delegation instead of inheritance — has become the modern consensus ([Rust traits announcement](https://blog.rust-lang.org/2015/05/11/traits/)). Mo should adopt structs + traits (or "protocols" or "abilities" — the naming is negotiable) and forbid class-style implementation inheritance from the beginning.

**From CLOS/Julia-style generic functions (A2d)**: multiple dispatch as a first-class alternative to method syntax. Julia's ability to dispatch on the combination of argument types has been decisive for its scientific-computing niche and produces code that is more compositional than either OO or FP dispatch ([Benchung, "The Design and Implementation of a Verifier for Dynamic Types," on Julia's multiple dispatch](https://benchung.github.io/papers/jlov.pdf)). Mo does not need multiple dispatch as the primary dispatch mechanism, but *should* consider it as an available idiom for polymorphic library APIs — the annotation cost is exactly the kind an agent can pay and a human reviewer benefits from.

**From pure functional (A3)**: purity as the default, effects as declared. Roc's discipline — no side effects except through platform-provided abilities — is the clearest existing model of what Mo can borrow ([Roc "Fast"](https://www.roc-lang.org/fast); [Roc FAQ](https://roc-lang.org/faq.html)). Unison's abilities carry the same design in a different notation ([Unison abilities](https://www.unison-lang.org/docs/fundamentals/abilities/)). The historical case for pure-by-default is the "reasoning locality" argument: a function whose type says `Int -> Int` cannot silently mutate state or perform I/O, which makes local reasoning tractable ([Peyton Jones, "Wearing the Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)). The historical case against — humans found the discipline burdensome and worked around it with monad transformers — falls away under agent authorship. Mo should be pure-by-default with declared effects.

**From logic programming (A5)**: pattern-based dispatch and unification as an implementation technique for Mo's type checker, not necessarily as a user-facing feature. Datalog's revival in tools like Souffle and Differential Datalog demonstrates that logic programming has a productive niche in analysis ([Wikipedia: Datalog](https://en.wikipedia.org/wiki/Datalog)); Mo's compiler could use Datalog internally for name resolution and effect inference without exposing Prolog-shaped syntax to Mo users.

**From concatenative (A6)**: nothing directly, but the *idea* that composition can be denoted by juxtaposition rather than by nested application is useful in Mo's pipeline syntax (F#-style `|>`, Elixir's `|>`, Haskell's `&`). This is a small ergonomic point but reliably improves LLM-generated code readability.

**Recommendation.** Mo should be a *pure-by-default, imperative-when-declared, ADT-and-trait-oriented* language with pattern matching as the primary control-flow discipline. It should not be a Lisp (S-expressions preclude the LL(1)/LALR(1) grammar the LLM-friendliness argument favors — see the syntax section), and it should not be an actor language at the paradigm level (actors can be a *library*, as they are in Scala; Erlang bakes them in only because BEAM does). It should look, to a working Rust or TypeScript programmer, like a language they can read on day one.

---

## Type system — Mo's options

The type-system menu ranges from untyped through dependent types. Mo's stated commitments (contracts, machine verification, capabilities, effects) constrain the choice sharply.

### Hindley–Milner and its descendants (B6)

Global HM inference — the ML/OCaml/Haskell/Elm design — gives you type inference so complete that annotations are almost never required ([SPJ, "Haskell: Being Lazy With Class"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)). It has two well-documented downsides. First, error messages get worse as inference gets more global: when the compiler cannot unify two types, the reported error is often the "wrong" one from the human's perspective, because the compiler's search order is not aligned with the reader's mental model. Second, whole-program inference makes small edits ripple in ways that are painful under LLM autofix loops — a single change to a helper function's return type can produce cascading errors elsewhere in the module.

**For Mo**: HM is not the right foundation. Bidirectional type checking — where types propagate top-down at binder sites and are inferred bottom-up at construction sites — gives most of HM's convenience without the global-inference downsides, and is what most modern languages (Rust, Swift, Kotlin) actually use in practice ([implementation_engineering.md, §3.2](../camps/implementation_engineering.md)).

### Dependent types (B7)

Full dependent types (Agda, Idris 2, Coq/Rocq, Lean 4, F\*) let types depend on values, which is powerful enough to express arbitrary specifications ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf); [Idris tutorial conclusions](https://idris2.readthedocs.io/en/latest/tutorial/conclusions.html); [Agda docs](https://agda.readthedocs.io/)). The dependent-types deep dive in this bundle ([deep_dives/15_dependent_types.md](../deep_dives/15_dependent_types.md)) documents the current state: Lean 4's mathlib has crossed one million lines of formal mathematics; F\*'s HACL\* verified crypto library ships in Firefox NSS, the Linux kernel's WireGuard implementation, and Python cryptography ([Lean mathlib community](https://leanprover-community.github.io/); [HACL* GitHub](https://github.com/hacl-star/hacl-star)); Idris 2 has integrated quantitative type theory (QTT) that combines dependent types with linear resource tracking ([Idris multiplicities](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)). But dependent types are still hard: Agda and Coq's non-decidable type checking means writing code sometimes requires manual proof search ([Agda docs](https://agda.readthedocs.io/)), and even Lean and Idris require a level of type-level meta-programming ability that only a small fraction of working programmers have developed.

**For Mo**: full dependent types are not the right choice for a general-purpose language, but Mo should be *dependent-adjacent* — expressive enough that the SMT-backed verifier can prove interesting properties, but decidable enough that ordinary code type-checks without solver interaction. This is F\*'s and Dafny's design point ([Dafny page](https://www.microsoft.com/en-us/research/project/dafny-a-language-and-program-verifier-for-functional-correctness/)).

### Refinement types (B8)

Refinement types are decidable subsets of dependent types where a type can be constrained by a decidable predicate: `type Nat = { x: Int | x >= 0 }`, `type SortedList = { xs: List Int | isSorted(xs) }`. Liquid Haskell for Haskell, F\* natively, and (via extensions) LiquidRust and Prusti for Rust have shown that refinement typing scales to real programs when the underlying language's type system is well-behaved ([Prusti page](https://viperproject.github.io/prusti-dev/user-guide/)). The camps report notes the tradeoff clearly: refinements catch specification-level bugs without requiring humans to write proofs ([design_camps_and_tradeoffs.md, B8](../camps/design_camps_and_tradeoffs.md)).

**For Mo**: refinement types are the sweet spot. Mo should support refinement predicates on all base types and datatypes, dispatched to Z3 or a similar SMT solver, with the annotation cost paid by the agent. Contracts (pre/post/invariant) in Verus/Dafny style are essentially refinement types on function boundaries ([Verus guide](https://verus-lang.github.io/verus/guide/); [Dafny page](https://www.microsoft.com/en-us/research/project/dafny-a-language-and-program-verifier-for-functional-correctness/)); Mo should adopt them directly.

### Linear / affine types and ownership (B9, B13)

Linear types require every value to be used exactly once; affine types require every value to be used at most once. Rust's ownership system is essentially affine types plus lifetimes; Austral uses proper linear types plus capabilities ([Austral spec](https://austral-lang.org/spec/spec.html)); Clean and Linear Haskell integrate linear types into functional languages ([Wikipedia: Clean](https://en.wikipedia.org/wiki/Clean_(programming_language))); Granule adds *graded* modalities that combine linearity with metric-tracked usage.

Rust's borrow checker — the aliasing-XOR-mutability rule — has been the decade's most influential single design idea. It prevents whole classes of concurrency bugs and use-after-free at compile time, without runtime cost. Non-Lexical Lifetimes (2018) made the checker's reasoning control-flow-based rather than scope-based, dramatically reducing false positives ([Rust NLL announcement](https://blog.rust-lang.org/2022/08/05/nll-by-default.html)). Polonius (2022–ongoing) continues to refine the analysis ([Polonius enabling on nightly, 2026](https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly/)). The RustBelt work formalized Rust's memory model in Coq and proved that key standard-library abstractions are safe ([RustBelt paper](https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf)).

The alternatives are illuminating. Vale's *generational references* use a small runtime check (a per-object generation number) that catches use-after-free without a borrow checker's compile-time rigidity ([Vale regions](https://vale.dev/guide/regions); [Vale page](https://vale.dev/)). Hylo's *mutable value semantics* gives every value unique ownership and shares only through projections ([Hylo page](https://www.hylo-lang.org/)). Pony's *reference capabilities* enforce data-race freedom via type-level capabilities per reference ([Pony capabilities paper](https://www.ponylang.io/media/papers/codesigning.pdf)). Roc's *platform* system delegates all effects to a runtime-provided platform, letting the language itself remain pure ([Roc FAQ](https://roc-lang.org/faq.html)).

**For Mo**: adopt Rust-style ownership *plus* explicit regions. Mo's current VM already has region allocation, so the semantics are already in the runtime; making regions a language-level primitive gives the agent an unambiguous way to spell "these values all live and die together" without the lifetime-parameter overhead that a full Rust-style borrow checker imposes. Cyclone was the first serious exploration of region-typed C ([Cyclone regions paper](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-safety.pdf)); MLKit and Vale showed that regions are practical in a modern language. Combine regions with linear/affine typing on external resources (file handles, sockets, capabilities) — this is Austral's design ([Austral capabilities tutorial](https://austral-lang.org/tutorial/capability-based-security)) and is the cleanest published integration of ownership with capabilities.

### Effect types (B11) and capability types (B14)

Effect types (Koka, Eff, Frank, OCaml 5 effect handlers, Unison abilities) track what side effects a computation may perform, in the same way HM tracks what values it may produce ([Koka book](https://koka-lang.github.io/koka/doc/book.html); [OCaml effect handlers](https://ocaml.org/manual/5.3/effects.html); [Multicore OCaml paper](https://kcsrk.info/papers/system_effects_feb_18.pdf)). A function's type in Koka reads `int -> <exn, io> int` — this function returns an int, and may throw an exception and/or perform I/O. Effect rows are inferred, similar to HM, and the compiler enforces that handlers exist for every effect the code raises. Unison abilities work the same way with different terminology and richer semantics for content-addressed code ([Unison abilities](https://www.unison-lang.org/docs/fundamentals/abilities/)).

Capability types make authority explicit: to perform an operation, you must hold a capability (a reference) that grants it. There is no ambient authority — no global filesystem, no global heap, no global network. The design lineage runs from Mark Miller's E language through Joe-E, Monte, Pony, Austral, and now Roc's platforms ([Austral capabilities tutorial](https://austral-lang.org/tutorial/capability-based-security); [Pony capabilities paper](https://www.ponylang.io/media/papers/codesigning.pdf); [Roc "Fast"](https://www.roc-lang.org/fast); [Wyvern language documentation](https://cmu-mars.github.io/wyvern-language/)). The G12 camp in the research bundle documents this history in depth ([design_camps_and_tradeoffs.md, G12](../camps/design_camps_and_tradeoffs.md)).

**For Mo**: adopt both. Effects and capabilities are complementary — effects describe *what a function does*, capabilities describe *what authority a function was given*. Austral's spec is the cleanest published integration; Koka's effect rows are the cleanest published effect syntax. Mo should synthesize them into a single row-type that mixes effects and capabilities on function signatures, e.g. `fn read_config(cap: &FS) -> <read_fs> Config`. The annotation cost is exactly what an agent can pay and a human reviewer benefits from.

### Recommendation summary

Mo should adopt:
- **Bidirectional type checking** over a small core based on System F with the ergonomics of modern Rust/Swift ([implementation_engineering.md, §3.2](../camps/implementation_engineering.md)).
- **Refinement types with SMT dispatch** for functional-correctness contracts (Verus/Dafny-style) ([Verus arxiv](https://arxiv.org/abs/2303.05491)).
- **Region-based memory management with linear/affine handles** for resources; explicit region introduction as first-class syntax ([Tofte & Talpin regions](https://cpsc.yale.edu/sites/default/files/files/tr172.pdf); [Austral spec](https://austral-lang.org/spec/spec.html)).
- **Effect rows plus capability parameters** on function signatures, dispatched via handlers (Koka/OCaml 5 style) with ambient authority forbidden by default ([Koka book](https://koka-lang.github.io/koka/doc/book.html)).
- **Structs + traits** with no implementation inheritance; ADTs with exhaustiveness-checked pattern matching as an error not a warning ([Rust traits](https://blog.rust-lang.org/2015/05/11/traits/)).

The composed system will have a larger apparent surface than most existing languages. But every element is annotation an agent can supply and a reviewer can consume — which is precisely the bet Mo makes.

---

## Memory management — regions, ownership, GC, hybrid

Memory management is the deepest single decision Mo will make, because the standard library, concurrency model, FFI story, and even the syntax will organize around the answer.

### Evidence from the exemplar languages

**Rust** proved that ownership + borrowing scales to production systems ([Rust 1.0 announcement, 2015](https://blog.rust-lang.org/2015/05/15/Rust-1.0/); [Rust nomicon](https://doc.rust-lang.org/nomicon/)). The costs are well documented: a steep learning curve for the borrow checker, occasional false positives that force refactoring, and code that becomes cumbersome when ownership crosses complex data structures ([Rust deep dive](../deep_dives/12_rust.md)). Non-Lexical Lifetimes helped substantially; Polonius will help more. RustBelt formally proved the soundness of the core ([RustBelt POPL 2018](https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf)).

**Vale** replaces the borrow checker with *generational references* — every reference holds a generation number, and every dereference checks that the target's generation still matches. This is a small runtime overhead (one comparison per dereference) but no compile-time reasoning about lifetimes ([Vale regions](https://vale.dev/guide/regions)). Vale is much less mature than Rust but proves the design is buildable.

**Hylo** (formerly Val) commits to mutable value semantics: every value is uniquely owned, and sharing goes through *projections* (borrowing without lifetime tracking) and *subscripts* ([Hylo page](https://www.hylo-lang.org/)). The result is a language where "aliasing" simply does not exist as a category — an important simplification, but one that constrains data structures (no cyclic references without explicit handles).

**Austral** uses proper linear types (each value used exactly once) combined with capability parameters ([Austral spec](https://austral-lang.org/spec/spec.html); [Austral introduction](https://borretti.me/article/introducing-austral)). The design is elegant but the ergonomic cost of full linearity is high — every use of a value must be threaded through the program's control flow.

**Roc** delegates memory management to the *platform*: the pure Roc code has no notion of allocation, and the platform (compiled with Rust or Zig) provides an allocator ([Roc "Fast"](https://www.roc-lang.org/fast)). This is a clean separation of concerns but requires the platform ecosystem to be built out.

**Nim** offers ARC (deterministic reference counting) with ORC (cycle collector) as a hybrid: most allocations are RC-managed, cycles are collected asynchronously ([Nim GC docs](https://nim-lang.org/docs/gc.html)). Nim's design is under-appreciated — it delivers Swift/Objective-C-style deterministic memory management with cycle collection handled automatically.

**Go** and **Java** and **C#** all use tracing GC with concurrent, sub-millisecond-pause collectors ([Go GC low-latency post](https://blog.twitch.tv/en/2016/07/05/gos-march-to-low-latency-gc-a6fa96f06eb7/); [G1 tuning docs](https://docs.oracle.com/en/java/javase/25/gctuning/garbage-first-g1-garbage-collector1.html); [OpenJDK ZGC](https://openjdk.org/projects/zgc/)). The costs — throughput overhead, memory footprint, unpredictable latency in the tail — are well understood.

### What Mo should pick

Mo's active repo already has region allocation, memoization, and a VM. This is a leading indicator of the right choice: **regions as the primary memory-management primitive**, with linear/affine handles for external resources.

**Why regions**. Regions were invented by Tofte and Talpin (1994) as an alternative to GC for functional languages, implemented in the MLKit ([Tofte & Talpin regions](https://cpsc.yale.edu/sites/default/files/files/tr172.pdf); [MLKit report](https://elsman.com/pdf/mlkit-4.6.0.pdf)); Cyclone brought them to a C-family language ([Cyclone safety paper](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-safety.pdf)); Vale integrates them with generational references. The critical properties for Mo:

1. **Regions are locally auditable.** An agent that emits `region r { ... }` is emitting a scope whose allocations all die together at the closing brace. A reviewer can see the allocation strategy without cross-file reasoning.
2. **Regions do not require lifetime parameters.** Rust's `'a` lifetimes are the single hardest thing about the language to learn. If Mo's regions are scope-tied, most everyday code needs no explicit lifetime annotation — the region *is* the lifetime.
3. **Regions compose with linear resources.** External resources (file handles, sockets, capabilities) can be *linear* — used exactly once, statically checked — and yet allocated in a region for their memory lifetime. Austral shows the composition; Mo can inherit it.
4. **Regions are fast.** Region deallocation is O(1) (drop the pointer to the region's arena), which is faster than tracing GC and comparable to manual freeing.

**Why not pure Rust-style borrow checking**. Rust's borrow checker is the industry's most successful memory-safety mechanism. It is also the industry's most-complained-about learning curve. An agent-authored language does not need the check to be inferred from usage — the agent can spell out the region explicitly. Making regions first-class syntax is a *simplification* that only Mo's premise (agent-authored) makes practical.

**Why not GC**. Tracing GC would be easier for a small team to implement and would remove a category of learning curve. But GC forces every effect signature that touches allocation to also implicitly touch a GC pause, which pollutes the effect and capability story Mo wants to build. GC also complicates FFI to systems code and to the WebAssembly Component Model.

**Why not mutable value semantics (Hylo)**. Mutable value semantics is elegant but constrains data structures. Real Mo programs will need shared graphs (parse trees, dependency graphs, IR representations) that MVS makes cumbersome to express without escape hatches.

**Hybrid option worth considering**. If regions prove too rigid in practice, Mo can adopt Nim's ARC/ORC discipline (deterministic RC + cycle collector) as an alternative allocator selectable per-region. This gives users an escape hatch for cyclic data structures without abandoning the region model globally.

---

## Concurrency — actors, CSP, async/await, structured concurrency, effects

The concurrency menu has grown enormously in the 2010s. The camps report enumerates threads-and-locks, CSP with channels (Go's ancestor Newsqueak, Alef, Limbo, Occam) ([Hoare's CSP paper](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf); [Wikipedia: Newsqueak](https://en.wikipedia.org/wiki/Newsqueak)), actors (Erlang, Elixir, Pony, Akka, Orleans) ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)), STM (Clojure, GHC Haskell), async/await (Rust, C#, JavaScript, Python, Swift) ([Aaron Turon on zero-cost futures](https://aturon.github.io/blog/2016/08/11/futures/)), structured concurrency (Trio, Swift concurrency, Kotlin coroutines), data parallel (NESL, Data Parallel Haskell, Futhark), fork-join (Cilk, Java ForkJoinPool), and effect-based concurrency (Koka, OCaml 5 domains).

### The mainstream debate

The two dominant camps in 2026 are **async/await** and **preemptive lightweight processes** (Go's goroutines, Erlang's processes). Async/await gives compile-time control over scheduling and integrates naturally with borrow-checked memory, at the cost of the "colored function" problem — a sync function cannot easily call an async one, so libraries must be written twice ([What Color is Your Function? — Bob Nystrom](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/)). Goroutines/BEAM processes hide the scheduler and let all functions look the same, at the cost of runtime overhead and less predictable latency ([Go GC low-latency post](https://blog.twitch.tv/en/2016/07/05/gos-march-to-low-latency-gc-a6fa96f06eb7/)).

Structured concurrency (Nathaniel Smith's "Notes on structured concurrency, or: Go statement considered harmful" and its adoption in Swift, Kotlin, and JEP 505 for Java) is a discipline layered on top of async/await that forces every concurrent task to have a defined parent-child relationship — no fire-and-forget goroutines, no dangling futures ([JEP 505: Structured Concurrency](https://openjdk.org/jeps/505); [Smith's essay on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)). Structured concurrency is a strict improvement on async/await ergonomics and should be Mo's baseline discipline regardless of the underlying primitive.

Effect-based concurrency (Koka, OCaml 5 domains) unifies effect handling and concurrency: `await` is an effect handler, and the type system can enforce that no effect is unhandled ([OCaml 5 effect handlers](https://ocaml.org/manual/5.3/effects.html); [Multicore OCaml paper](https://kcsrk.info/papers/system_effects_feb_18.pdf)). This is the most theoretically elegant model and integrates cleanly with Mo's declared direction on effects. The cost is that effect handlers are still an unfamiliar programming model for most developers, and the compiler engineering to make them efficient is non-trivial.

### Recommendation for Mo

Mo should adopt **structured concurrency on top of effect handlers**, with a syntax that looks async/await-like from the user's perspective. The type system tracks concurrency as an effect (`<async>`, `<par>`), the runtime uses a work-stealing scheduler with pre-emption at handler boundaries, and every task has a parent scope.

- The user-facing syntax borrows from Swift 6's structured concurrency and Kotlin's coroutines ([Swift 6 concurrency](https://developer.apple.com/documentation/swift/concurrency); [Kotlin coroutines guide](https://kotlinlang.org/docs/coroutines-guide.html)).
- The implementation is effect-handler-based (OCaml 5, Koka) so the language does not need a separate async runtime type.
- Data-race freedom is enforced by the ownership+capability system: sending a value across a task boundary requires a capability, and mutable references cannot be shared without a synchronized wrapper (like Rust's `Send`/`Sync` traits but derived from the capability system rather than named separately).
- Actors are provided as a *library* (like Akka on the JVM), not as a language primitive. Erlang's success argues for baking actors in, but Erlang's success is more about supervision trees and hot code reload than about the actor abstraction itself; Mo can offer supervision as a library pattern.

The primary risk with this recommendation is implementation complexity: effect handlers require careful compiler engineering to keep the "handler stack" from becoming a performance bottleneck, and the interaction with borrow-checked memory needs thought. Koka's papers ([Koka book](https://koka-lang.github.io/koka/doc/book.html)) and the Multicore OCaml team's work ([Multicore OCaml paper](https://kcsrk.info/papers/system_effects_feb_18.pdf)) are the prior art.

If the effect-handler runtime proves too complex to ship early, Mo should fall back to **Rust-style async/await with structured concurrency wrappers** as the interim design, and migrate to effects later. Structured concurrency + async/await is already a strict improvement over what Go or Rust ship today.

---

## Syntax and readability — agent-friendly properties

The syntax families (C-family curly braces, ML expression-oriented, Lisp S-expressions, Python indentation) are stable design points; the choice depends on what property Mo prioritizes.

Under LLM authorship the priorities shift. The AI-era section of the history report documents what actually matters ([history/03_2010_to_2026.md, §4.1](../history/03_2010_to_2026.md)):

1. **LL(1) or LALR(1) parseable grammar.** Grammar-constrained decoding libraries (Outlines, XGrammar, SynCode) work by masking LLM logits to only permit tokens that keep the grammar's parser state valid ([Outlines documentation](https://dottxt-ai.github.io/outlines/); [XGrammar blog](https://blog.mlc.ai/2024/11/22/achieving-flexible-portable-structured-generation-with-xgrammar); [SynCode paper](https://arxiv.org/abs/2403.01632)). A language with an ambiguous grammar (Perl, some C++ constructs) is not compatible with these libraries; a language with a clean grammar is trivially compatible.
2. **Statement terminators over indentation.** Rust, Go, Zig, and TypeScript use semicolons or explicit braces as unambiguous commit signals; Python and Nim use indentation, which is harder for incremental generators to keep valid across edit points.
3. **Small, unambiguous operator-precedence table.** Rust, Go, and Zig have flat precedence hierarchies; Scala and Haskell allow user-defined precedence with symbolic operators, which the LLM must know to parse. Rust and Go generate more consistently.
4. **Single obvious solution.** Python's `with open(...)` block is a canonical idiom the LLM produces reliably; Python's *many* equivalent ways to spell a matrix multiplication produce inconsistent completions ([history/03_2010_to_2026.md, §4.2](../history/03_2010_to_2026.md)).
5. **Deterministic formatting.** `gofmt` and `rustfmt` established that a canonical formatter with no options is a competitive differentiator ([users.rust-lang.org discussion](https://users.rust-lang.org/t/what-do-you-think-about-gofmt-vs-rustfmt/51605)).
6. **Structured JSON diagnostics.** Rust's `--error-format=json` is the modern baseline; LLM autofix loops consume diagnostics programmatically ([Rust NLL announcement](https://blog.rust-lang.org/2022/08/05/nll-by-default.html)).

### Recommendation for Mo

Mo should be a **C-family, statement-terminator, expression-oriented hybrid** — visually similar to Rust or Swift, LL(1)/LALR(1) parseable, with braces for blocks and semicolons or newlines-with-explicit-continuation for statements. Concrete points:

- Adopt Rust-style syntax for functions (`fn name(args) -> ReturnType { body }`) and let-bindings (`let x = expr;`).
- Adopt expression-oriented control flow: `if`, `match`, and blocks are expressions (Rust's discipline).
- Adopt pattern-matching syntax similar to Rust's `match`. Exhaustiveness is an *error*, not a warning.
- Ban user-defined operator precedence entirely; provide a fixed precedence table matching Rust's, with the pipeline operator `|>` (F#-style) as the single exception.
- Ship a canonical formatter (`mofmt`?) with no options, from day one.
- Ship structured JSON diagnostics with a stable schema, from day one.
- Reserve `gen`, `effect`, `region`, `cap`, `contract`, `where` as keywords early to leave room for future features without breaking changes.
- Include statement-level annotations for contracts (`@requires`, `@ensures`, `@invariant`) that dispatch to the SMT verifier when present.

The result should look, on a first-glance viewing, like something between Rust and Swift — familiar to any modern-language programmer, LL(1)-parseable for LLM decoding, and with visible annotation slots for the machine-verifiable properties Mo demands.

---

## Compilation strategy — LLVM vs. MLIR vs. Cranelift vs. custom VM

The compilation-strategy menu, per the implementation report ([implementation_engineering.md, §2, §5](../camps/implementation_engineering.md)), boils down to five choices:

1. **LLVM** as the backend: mature, produces high-quality machine code, portable across every mainstream target, but slow to compile (Rust's compile times are largely LLVM's fault) and complex to integrate. Rust, Swift, Julia, Zig (still), Crystal, Odin, and many others use LLVM.
2. **Cranelift**: a Rust-implemented backend built by Bytecode Alliance for Wasmtime and now available as a Rust library ([Cranelift page](https://cranelift.dev/)). Produces less-optimized code than LLVM but compiles ~10× faster, making it ideal for development-time iteration and JIT scenarios.
3. **MLIR**: LLVM's newer multi-level IR, designed for heterogeneous compute (CPU + GPU + accelerator) and adopted by Mojo, TensorFlow, PyTorch (via Torch-MLIR), and Modular's stack ([MLIR paper](https://arxiv.org/pdf/2002.11054)). MLIR is the near-mandatory choice for AI-adjacent languages; overkill for a general-purpose language.
4. **Custom bytecode VM**: Erlang BEAM's reduction-counted preemption ([BEAM book chapter](https://blog.stenmans.org/theBeamBook/)), Lua's register-based bytecode ([Lua VM design](https://www.lua.org/doc/jucs05.pdf)), Python's stack-based bytecode. Best when the language semantics require unusual runtime behavior (soft-real-time, hot code loading, unique dispatch models).
5. **Compilation to C**: Nim, Chicken Scheme, historically Vala. Very portable, easy to bootstrap, but ties the language to C's ABI and calling conventions.

### Recommendation for Mo

Mo should ship a **staged compilation strategy**:

- **Stage 0 (current): custom VM.** Mo already has a VM with region allocation. Keep it as the development-time runtime and reference semantics. This is the fastest path to language iteration.
- **Stage 1: Cranelift for AOT.** Add a Cranelift backend for AOT compilation to native ([Cranelift page](https://cranelift.dev/)). Cranelift compiles ~10× faster than LLVM and is production-quality for warm-path code. Compile times matter enormously for the LLM autofix loop (edit-compile-diagnostic cycles).
- **Stage 2: LLVM for release.** Add an LLVM backend as a release-mode option once the language is stable. Users pay LLVM's compile cost only when they need peak throughput.
- **Stage 3 (later): WebAssembly.** Mo should target WebAssembly as a first-class output ([WASI 0.2 release](https://bytecodealliance.org/articles/webassembly-the-updated-roadmap-for-developers)), with Component Model interop as the mid-term goal ([Component Model](https://component-model.bytecodealliance.org/)). The Wasm target integrates naturally with capability-based isolation — the Wasm sandbox enforces at runtime the same capability discipline Mo enforces at compile time.

**Why not LLVM from day one**: LLVM is heavyweight, slow to build against, and produces a compiler binary of ~100MB by itself. Cranelift is the modern answer for "I want native codegen without LLVM's bulk," and Wasmtime's use of Cranelift in production ([Wasmtime page](https://wasmtime.dev/)) proves it works. LLVM can come later, when peak throughput starts to matter.

**Why not MLIR**: MLIR is overkill for a general-purpose language. It shines when you need to target GPUs and neural accelerators from one IR (Mojo's use case). Mo does not have that requirement.

**Why not compilation to C**: Nim demonstrates the model works, but the resulting language is tied to C's calling conventions and cannot easily express unwinding, effects, or novel memory models without leaking abstractions.

---

## Package system — hard lessons from npm, PyPI, Cargo, Hex, Go modules, Deno

Package management is where language ecosystems most often collapse under their own weight. The bundle's implementation report devotes an entire section to this ([implementation_engineering.md, §7](../camps/implementation_engineering.md)); the AI-era history report treats supply-chain security at length ([history/03_2010_to_2026.md, §4.4](../history/03_2010_to_2026.md)). Mo has more freedom than any existing language ecosystem to design this correctly from the start.

### What the incumbents got wrong

**npm** — the largest package registry — inherited a design from a moment (2009–2015) when supply-chain attacks were rare and ecosystem growth was the priority. Consequences: unauthenticated publishing (fixed with mandatory 2FA on high-download packages, but by then the ecosystem was enormous); no permission model on installed packages; `postinstall` scripts run arbitrary code (`event-stream` in 2018, `colors`/`faker` in 2022, `ua-parser-js` in 2021 all exploited this); left-pad demonstrated the fragility of hyper-fine-grained dependency graphs.

**PyPI** shares most of npm's issues plus its own: `setup.py` runs arbitrary code at install time (still, in 2026, despite PEP 517/518's build isolation improvements); the `ctx`/`phpass` incidents in 2022 exposed the account-compromise vulnerability. PEP 740 attestations and the trusted-publishers work have started to close the gap ([SLSA blog](https://slsa.dev/blog/2024/08/dep-confusion-and-typosquatting)).

**Cargo** got much of the design right — a canonical manifest+lockfile+registry from day one ([Cargo announcement](https://blog.rust-lang.org/2014/11/20/Cargo/); [Cargo documentation](https://doc.rust-lang.org/cargo/)) — but inherited free-for-all `build.rs` scripts and `proc_macro` execution at compile time. Both are default-on. Both are vectors for supply-chain compromise. Cargo has since added `cargo-audit`, `cargo semver-checks`, and moved toward trusted publishers ([Cargo PubGrub project goal](https://rust-lang.github.io/rust-project-goals/2025h1/pubgrub-in-cargo.html)), but the ambient-authority default remains.

**Hex** (Erlang/Elixir) gets several things right: GPG-signed artifacts, immutable versions, hex-scoped org names as first-class ([hex.pm docs](https://hex.pm/docs/publish)). Hex is a good template.

**Go modules** with MVS ([Russ Cox, "Minimal Version Selection"](https://research.swtch.com/vgo-mvs); [Go modules reference](https://go.dev/ref/mod)) gives deterministic reproducible builds without lockfiles, plus `sum.golang.org` as a transparency log that pins every version hash the ecosystem has ever seen. Go's model is the strongest existing reproducibility story. Weakness: no signing story yet, and vendoring is common but manual.

**Deno** made permission flags a first-class runtime concern: `deno run --allow-net --allow-read=./data script.ts` ([Deno v1 announcement](https://deno.com/blog/v1)). This is the closest existing production model to Mo's declared direction on capabilities. Deno's design has the right shape but is enforced at runtime rather than at the type level — an agent-authored language can move the check earlier.

**Unison** takes content-addressing further than anyone: every function is identified by the hash of its normalized AST ([Unison big idea](https://www.unison-lang.org/learn/the-big-idea/)). There are no filenames, no imports; rename is a metadata change, not a code change. This eliminates typosquatting and dependency-version conflicts entirely — at the cost of unreadable references (mitigated by a codebase index).

**Nix** stores every package under a hash-of-inputs derived path ([Nix content-addressed store](https://nix.dev/manual/nix/2.26/store/store-object/content-address)). Perfect reproducibility, atomic upgrades, parallel version coexistence.

### Design principles for Mo's registry

Combining the lessons above, Mo's package system should adopt the following principles:

1. **Content-addressed identifiers as the ground truth, human names as a convenience.** Every published package artifact is identified by a hash of its contents (like Nix or Unison); the human-readable name (`json_parser@2.1.0`) is a *label* over the hash. Renaming, forking, or transferring ownership is a label change, not a code change. This eliminates typosquatting at the identifier level — you cannot typo a 32-byte hash.
2. **Manifest declares capabilities.** Every package's `mo.toml` (or equivalent) declares the effects and capabilities the package's code uses transitively: `capabilities: [read_fs, http_client]`. Import authority is a subset relationship — if a package declares fewer capabilities than its dependencies, the build fails. This makes the DepSec / Cocoon / npm-permission-manifest research direction into a compiler-enforced discipline ([Cocoon research](https://mickens.seas.harvard.edu/publications), [npm supply-chain research collections such as SLSA blog](https://slsa.dev/blog/2024/08/dep-confusion-and-typosquatting)).
3. **Install scripts, build scripts, procedural macros, native code, FFI are default-off.** Any package that wants to run code at install/build time, or link to native code, must declare the intent in its manifest, and the consuming project must explicitly opt in. Cargo's `build.rs` and npm's `postinstall` are the anti-patterns; Deno's `--allow-*` flags at runtime and Bazel's sandboxed-actions model are the templates ([Deno v1](https://deno.com/blog/v1)).
4. **Publisher identity via OIDC only.** No password-authenticated publishing. The `mo publish` command must be invoked from an OIDC-authenticated context (GitHub Actions, GitLab CI, Google Cloud Build) that produces a signed provenance attestation. This is Cargo's trusted-publishers direction and PyPI's PEP 740 ([Cargo PubGrub goal](https://rust-lang.github.io/rust-project-goals/2025h1/pubgrub-in-cargo.html)).
5. **SLSA v1.0 attestations and Sigstore signing as the minimum bar.** Every artifact ships with an in-toto attestation describing the build environment and inputs, signed by Sigstore's transparency-logged short-lived certificates ([SLSA levels](https://slsa.dev/spec/v1.0/levels); [Sigstore Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)).
6. **Release-age gates.** By default, `mo build` refuses to use any dependency version published in the last N days (7 is a defensible default; configurable per-project). Most supply-chain attacks are caught within a week; this policy nullifies them at negligible cost. `uv`, `pip`, and Cargo proposals have all moved toward this ([uv unified Python packaging](https://astral.sh/blog/uv-unified-python-packaging)).
7. **MVS resolution, PubGrub for error messages.** Adopt Go's MVS as the resolution algorithm for reproducibility ([Russ Cox on MVS](https://research.swtch.com/vgo-mvs)), but borrow PubGrub's incompatibility-tracking for excellent error messages when resolution fails ([pubgrub-rs README](https://github.com/pubgrub-rs/pubgrub)). The two are compatible — the resolution semantics are MVS, the error-reporting infrastructure is PubGrub-style.
8. **Vendor by default.** Unlike npm and Cargo, where vendoring is optional, Mo should encourage vendoring the resolved dependency graph into the project repository (as Go does with `go mod vendor`). Vendoring shifts trust from the registry to the version-control system and lets `mo build` be fully offline-reproducible.
9. **Registry federation.** Do not require a central registry. The default should be `registry.mo-lang.org`, but any HTTPS endpoint that serves the standard metadata + signed artifacts format should work — like Go modules' URL-as-identifier design ([Go modules reference](https://go.dev/ref/mod)). Enterprise mirrors and private registries are then trivial.

The combined design is *stricter* than any existing ecosystem, which is precisely the point: Mo has the freedom to demand annotations no existing ecosystem can retrofit, because Mo's user base is being formed now.

---

## Governance — BDFL, foundation, steering council

The governance camp catalog is short but consequential ([implementation_engineering.md, §11.4, §11.5](../camps/implementation_engineering.md)). The three viable models are:

- **BDFL (Benevolent Dictator For Life)**: single-founder-authoritative. Python (Guido until 2018), Perl (Larry Wall), Ruby (Matz, mostly), Lua (Roberto), Erlang (Joe Armstrong until his death in 2019). Guido's resignation established that BDFL is not sustainable at scale: "you're all responsible for this" ([LWN — Van Rossum's resignation](https://lwn.net/Articles/759654/); [PEP 8016](https://peps.python.org/pep-8016/)).
- **Foundation**: independent nonprofit that owns the trademark, IP, and infrastructure. Rust Foundation (2021), Linux Foundation, Python Software Foundation, .NET Foundation, Node.js Foundation ([Rust Foundation launch](https://blog.rust-lang.org/2021/02/08/Foundation-Launch/); [Rust governance page](https://www.rust-lang.org/governance)). Expensive to set up (~$500K/year minimum for a serious foundation), robust to founder-departure, credible to corporate stakeholders.
- **Steering council + topical teams**: contributors elect a small council (5–7 members), delegated topical teams (compiler team, library team, community team) have decision authority in their area. Python's Steering Council (post-2018), Rust Leadership Council ([RFC 3392](https://rust-lang.github.io/rfcs/3392-leadership-council.html)), Swift Language Steering Group. Scales best to large communities.

### Recommendation for Mo

Mo's realistic path is a **staged governance evolution**:

- **Stage 0 (now, pre-1.0): BDFL.** Robert as designer-author, personally accountable for decisions, with a public RFC process modelled on Python's PEP 1 or Rust's RFC template even at this early stage ([Python PEP 1](https://peps.python.org/pep-0001/); [Rust RFCs process](https://github.com/rust-lang/rfcs)). The RFC process is not for consensus-building at this stage — it is for *documenting* decisions so future contributors can understand the rationale.
- **Stage 1 (post-1.0, once external contributors exist): steering council.** Formalize a small (3-5 member) council with delegated decision authority, ideally including at least one non-founder. Publish a charter.
- **Stage 2 (later, once corporate adoption is real): foundation.** Establish a nonprofit that owns the trademark, hosts the registry, and provides legal cover for contributors. This is the moment Rust reached in 2021 ([Rust Foundation launch](https://blog.rust-lang.org/2021/02/08/Foundation-Launch/)).

**Do not skip Stage 0's RFC discipline.** The single most consistent lesson from mature language communities is that written decision records accumulate value over time — future contributors need to know *why* a design choice was made, not just what it was. Python's PEP archive, Rust's RFC repository, and Java's JEP list are the reference examples.

**Do not appoint a successor BDFL.** Guido's decision to resign without naming a successor was widely admired for a reason: an appointed successor inherits neither the founder's legitimacy nor the founder's context, and the community must build governance capacity itself ([LWN — Van Rossum's resignation](https://lwn.net/Articles/759654/)).

---

## Lessons from failure

Historical failures teach more about launch strategy than historical successes. The bundle documents several instructive collapses.

**Dylan (Apple, 1990s)**: a technically-excellent Lisp-with-syntax that never found a niche because it was designed *for* the Newton PDA project which Apple cancelled ([Wikipedia: Dylan](https://en.wikipedia.org/wiki/Dylan_(programming_language))). Lesson: a language needs a *first workload* that will keep it alive if the sponsor changes strategy.

**Fortress (Sun/Oracle, 2003–2012)**: Guy Steele's design for scientific computing, killed by Sun's acquisition and Oracle's disinterest, but even absent that, Fortress's ambition (a fully mathematical Unicode syntax, sophisticated type system, parallelism throughout) outstripped the team's ability to ship ([Wikipedia: Fortress](https://en.wikipedia.org/wiki/Fortress_(programming_language))). Lesson: the design budget must match the engineering budget.

**Sather (Berkeley, 1990s)**: a research language with excellent ideas (iterators before Rust, contract-like invariants) that never bootstrapped a community outside its academic origin. Lesson: excellent ideas in an inaccessible package will lose to mediocre ideas in an accessible one.

**Alef (Bell Labs)**: Rob Pike's CSP-based systems language for Plan 9. Died with Plan 9. Its ideas resurfaced in Go two decades later ([Rob Pike on Alef and Newsqueak influences](https://swtch.com/~rsc/thread/newsqueak.pdf); [Wikipedia: Newsqueak](https://en.wikipedia.org/wiki/Newsqueak)). Lesson: even good ideas need a durable institutional carrier.

**Perl 6 / Raku (announced 2000, released 2015)**: fifteen years of design and re-implementation destroyed the momentum of Perl 5. Larry Wall's essay "Apocalypse 1" set the scope; the scope became untenable ([Wikipedia: Raku](https://en.wikipedia.org/wiki/Raku_(programming_language))). Lesson: version-2-that-is-not-backward-compatible is a language-community-ending event unless completed rapidly and migrated aggressively.

**Python 2 → Python 3 (2008–2020)**: twelve years of ecosystem pain because 3.0 broke ASCII/unicode-string semantics in a way that could not be automatically migrated ([python.org "sunsetting Python 2"](https://www.python.org/doc/sunset-python-2/)). Lesson: even the world's largest language ecosystem paid an enormous cost for a design decision that seemed correct in isolation. Mo should treat backward-compatibility breaks as a rare-emergency mechanism, not a routine tool.

**Scala 2 → Scala 3 (2020–ongoing)**: technically successful migration but with substantial community friction; Kotlin has grown at Scala's expense during the migration window ([Scala 3 migration guide](https://docs.scala-lang.org/scala3/guides/migration/compatibility-intro.html)). Lesson: even a well-executed major version transition costs users.

**The BDFL model's collapse**: covered above under Governance. Applies to Mo directly.

### What these failures say to Mo

Mo should:

1. **Design an edition/epoch mechanism from day one.** Rust editions (2015, 2018, 2021, 2024) let Rust make small backward-incompatible changes without breaking existing code, because each crate declares its edition and `cargo fix --edition` automates migration ([Rust editions guide](https://doc.rust-lang.org/edition-guide/); [Rust 2024 edition](https://doc.rust-lang.org/edition-guide/rust-2024/)). This is much cheaper to include from release 0.1 than to retrofit later — an `edition = "1"` header in every source file is a small tax that buys huge future flexibility.
2. **Pick a first workload.** Rust had Servo (browser engine components at Mozilla); Elixir had WhatsApp-scale messaging; Julia had scientific computing; Go had Google's server-side services. Mo needs an analogous first workload it can point to as proof. The natural fit for Mo's design is *AI-agent tooling itself* — compilers, static analyzers, IDE support tools — where the annotation-heavy contract style buys the most.
3. **Do not let scope creep destroy launch momentum.** Perl 6 is the cautionary tale. Ship 1.0 with a language surface small enough to hold in one head, and add features via a public proposal process afterward.
4. **Plan the governance transition explicitly.** Do not become the next BDFL who is forced to resign under stress.

---

## Lessons from success

Rust, Go, TypeScript, and Elixir are the four unambiguous success stories of the modern era. What did they get right?

**Rust (2015 1.0)**: shipped Cargo alongside the compiler on day one ([Cargo announcement](https://blog.rust-lang.org/2014/11/20/Cargo/)); invested in error messages as a first-class engineering discipline (colored, span-highlighted, machine-readable via JSON, with `--explain` for every error code) ([Rust NLL by default](https://blog.rust-lang.org/2022/08/05/nll-by-default.html)); published *The Rust Programming Language* book alongside the language ([Rust Book](https://doc.rust-lang.org/book/)); adopted an RFC process early ([Rust RFCs](https://github.com/rust-lang/rfcs)); had a *first workload* (Servo) that produced real production users ([Rust deep dive](../deep_dives/12_rust.md)).

**Go (2012 1.0)**: shipped `gofmt`, `go doc`, `go test`, and the whole toolchain in one binary; enforced a Go 1 compatibility promise ([Go 1 compatibility](https://go.dev/doc/go1compat)); had Google's server infrastructure as a first workload; kept the language small enough that most programmers can hold it in their head ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**TypeScript (2012, mainstream by ~2016)**: gradual adoption path — every JavaScript file is a valid TypeScript file; erased at compile time so no runtime cost; structural typing that lets `.d.ts` files retrofit types onto untyped libraries; Microsoft's institutional weight behind the tooling ([TypeScript handbook](https://www.typescriptlang.org/docs/handbook/)).

**Elixir (2012, 1.0 in 2014)**: leveraged Erlang's BEAM runtime and battle-tested library ecosystem (OTP) so Elixir did not have to reinvent the concurrency/fault-tolerance story ([Serokell: History of Erlang and Elixir](https://serokell.io/blog/history-of-erlang-and-elixir); [Elixir v0.5.0 release](https://elixir-lang.org/blog/2012/05/25/elixir-v0-5-0-released/)); José Valim's *Programming Elixir* book set the learning path; Phoenix framework gave Elixir a killer web-application story ([Phoenix framework](https://phoenixframework.org)); the community norms around documentation and testing were established early ([oss history: Elixir](https://osshistory.org/p/elixir)).

### What Mo should imitate from the successes

1. **Ship the toolchain in one binary.** `mo build`, `mo test`, `mo fmt`, `mo doc`, `mo publish` should all be `mo <verb>` subcommands of the same binary. Go's model.
2. **Structured JSON diagnostics from day one.** LLM autofix loops consume these; without them Mo's design premise is compromised. Rust's model.
3. **A first-class book.** *The Mo Programming Language* should exist by 1.0 and be maintained by the core team.
4. **A first workload.** Pick one and commit to it. AI-agent tooling (the compiler itself, analyzers, MCP servers) is the natural fit.
5. **RFC discipline from pre-1.0.** Every non-trivial design decision goes through a written RFC, even if Robert is currently the only reviewer.
6. **Compatibility promise.** Once 1.0 ships, Mo makes a Go-1-style compatibility promise, backed by the edition mechanism for future evolution.

---

## Concrete anti-patterns Mo should avoid

The bundle catalogs many anti-patterns; the ones most relevant to Mo:

1. **Ambient authority in package code.** Every function in a Python or JavaScript program has the authority of the whole process — `left-pad` could steal SSH keys because the language grants every function filesystem access ([design_camps_and_tradeoffs.md, G12](../camps/design_camps_and_tradeoffs.md)). Mo must not repeat this.
2. **Install-time and build-time arbitrary code execution.** npm's `postinstall`, Python's `setup.py`, Cargo's `build.rs`, and proc-macros are the same anti-pattern: a package can run arbitrary code as soon as it is added to your project, before you have read a line of it. Mo should default all of these off.
3. **Whole-program type inference.** HM inference produces cascading errors from single edits, which is painful under LLM autofix loops. Bidirectional checking is the modern answer.
4. **Indentation-sensitive syntax.** Python's indentation is human-friendly but generation-hostile: an LLM cannot commit to a token stream until it knows the indent level, which the surrounding context implies. Braces or explicit block terminators are strictly better for AI authorship.
5. **User-defined operator precedence.** Scala and Haskell allow it; the cost is that a parser cannot resolve `a ⊕ b ⊗ c` without knowing what `⊕` and `⊗` are. LLMs and other tools benefit from a fixed table.
6. **Multiple ways to spell the same thing.** Ruby's "there's more than one way to do it" and Perl's TIMTOWTDI produced hard-to-review codebases and are especially bad for LLM generation. Python's "one obvious way" is the target; Rust and Go come closer than Python does.
7. **Optional semicolons with implicit inserters.** JavaScript's ASI (Automatic Semicolon Insertion) causes subtle bugs and complicates parsing. Semicolons should be either always-required or forbidden, not conditionally required.
8. **Hidden allocations.** Any language construct that silently allocates on the heap (implicit boxing, closures that capture by value, string concatenation) makes performance reasoning impossible. Zig's discipline (`allocator` parameters explicit) is the model.
9. **Global-state singleton APIs.** Any API that returns a global handle (e.g., "get the default logger", "get the current filesystem") is a hidden capability the compiler cannot see. Mo should not have any.
10. **Backward-incompatible major version releases without an edition mechanism.** Perl 6 and Python 3 are the cautionary tales; Rust editions are the answer.

---

## Five specific, actionable recommendations for the next 6 months

Robert has an active Mo repo, a VM with region allocation, and a design direction. The following recommendations are ordered by leverage over the six-month horizon.

### Recommendation 1 — Publish a formal specification of Mo's syntax and core semantics

Every mature language project has a spec that a compiler-independent implementation could match. Rust took a decade to publish one; Austral had one from day one ([Austral spec](https://austral-lang.org/spec/spec.html)); Ada's LRM is the classic model. A written spec forces the design questions this document surfaces to be answered concretely: what is Mo's grammar in EBNF? what are the exact semantics of a region? what is the effect-row syntax? what is the type-checking algorithm?

The spec does not need to be a formal semantics in the Coq/Isabelle sense (though that is a longer-term goal). It should be a *reference document* in the style of the Rust Reference ([Rust reference](https://doc.rust-lang.org/reference/)) or the Go Programming Language Specification ([Go spec](https://go.dev/ref/spec)). The value is threefold: it forces design decisions to be made explicit; it documents them for future contributors; it makes third-party analysis tools (LSPs, tree-sitters, linters, verifiers) possible.

### Recommendation 2 — Ship an LSP, tree-sitter grammar, formatter, and structured JSON diagnostics *before* adding language features

The tooling checklist from the implementation report ([implementation_engineering.md, §11.9](../camps/implementation_engineering.md)) is not optional. Every modern language that has failed to ship these on day one has paid for the omission. The good news: the tooling is largely mechanical work — LSP is a well-specified protocol, tree-sitter has excellent tutorials, formatters follow known patterns.

The specific deliverables:
- **Tree-sitter grammar** matching the EBNF from the spec ([tree-sitter documentation](https://tree-sitter.github.io/tree-sitter/)).
- **LSP server** with go-to-definition, hover, diagnostics, and rename ([Language Server Protocol spec](https://microsoft.github.io/language-server-protocol/)).
- **`mo fmt`** with no options, canonical output.
- **Structured JSON diagnostics** with a stable schema, matching Rust's model.
- **A playground URL** where visitors can run examples in the browser (compile to Wasm for the client-side runtime, or use a hosted server).

### Recommendation 3 — Design and prototype the package manifest with capability declarations

Before Mo has enough packages for the choice to matter, prototype the manifest format that declares capabilities, effects, and dependencies. Reference designs:
- **Cargo.toml** for the general structure ([Cargo book](https://doc.rust-lang.org/cargo/)).
- **Austral's capability parameters** for the vocabulary ([Austral capabilities](https://austral-lang.org/tutorial/capability-based-security)).
- **Deno's `--allow-*` flags** for the runtime granularity ([Deno v1](https://deno.com/blog/v1)).
- **npm/PyPI permission-manifest research** for the transitive-authority propagation.

The prototype does not need to be a working package registry — it should be a specification (a `mo.toml` schema, a sample repository showing the format, and a document explaining how the compiler checks capability subset relations). Publishing this early lets the design be reviewed by the security and language-design communities before any packages exist.

### Recommendation 4 — Draft the RFC process and publish the first three RFCs

The RFC process itself is a small design task (Python's PEP 1 or Rust's RFC template can be adapted with minimal changes). The first three RFCs to publish:

1. **RFC 001: Language governance charter** — declares Robert as BDFL for the pre-1.0 phase, describes the RFC process, commits to future governance evolution.
2. **RFC 002: Mo syntax and grammar (v0)** — the EBNF and design rationale for the syntactic choices this document argues for.
3. **RFC 003: Effects, capabilities, and regions (v0)** — the core type-system commitment.

Publishing these in the open ([mo-lang GitHub](https://github.com/robertguss/mo-lang)) forces the design to be defensible to external readers and creates the archive that future contributors will need. Rust's RFC 0002 (RFC process) is a small readable model ([Rust RFC 0002](https://rust-lang.github.io/rfcs/0002-rfc-process.html)).

### Recommendation 5 — Ship a supply-chain-secured demo package registry — even at toy scale

The single most differentiated design commitment Mo can make is on supply-chain security. Demonstrate it early with a working prototype:

- A `mo publish` command that requires OIDC authentication (GitHub Actions integration is easiest to prototype).
- A registry that stores content-addressed artifacts + label pointers.
- A `mo build` that enforces capability-subset checking and refuses packages with declared but not-opted-in `install_script` or `native_code` capabilities.
- A default 7-day release-age gate that the user can override per-project.
- Sigstore-signed artifacts using the standard Cosign flow ([Sigstore Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)).
- SLSA v1.0-compliant provenance attestations for every published artifact ([SLSA levels](https://slsa.dev/spec/v1.0/levels)).

The prototype does not need to host thousands of packages; a handful of Mo's own stdlib packages is enough. What it needs to *demonstrate* is that Mo has integrated the modern supply-chain security stack into the language's design, rather than treating it as an afterthought.

Combined, these five recommendations set Mo up to be the first language whose response to the AI era is *coherent across all layers* — grammar, type system, effect discipline, tooling, and supply chain — rather than a retrofit of any one concern onto an existing design. The evidence from 90 years of language design is that coherence is the scarcest resource. Mo has the freedom to have it, and that freedom will not last.

---

## Where to look next in the bundle

- For the paradigm evidence in more depth: `camps/design_camps_and_tradeoffs.md`, Camp A.
- For the type-system menu in more depth: `camps/design_camps_and_tradeoffs.md`, Camp B; `deep_dives/15_dependent_types.md`; `deep_dives/05_haskell.md`; `deep_dives/04_ml.md`.
- For memory-management evidence: `camps/design_camps_and_tradeoffs.md`, Camp C; `camps/implementation_engineering.md`, Section 4; `deep_dives/12_rust.md`; `deep_dives/14_zig.md`.
- For concurrency evidence: `camps/design_camps_and_tradeoffs.md`, Camp D; `camps/implementation_engineering.md`, Section 6; `deep_dives/06_erlang.md`; `deep_dives/13_elixir.md`; `deep_dives/11_go.md`.
- For package-manager evidence: `camps/implementation_engineering.md`, Section 7; `history/03_2010_to_2026.md`, §4.4 and §5.5.
- For governance evidence: `camps/implementation_engineering.md`, Section 11.
- For the AI-era design conversation: `history/03_2010_to_2026.md`, §4 and §6.
