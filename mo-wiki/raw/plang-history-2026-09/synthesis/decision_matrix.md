# Mo Design Decision Matrix

*A living menu of concrete design choices for Mo. Each design axis lists the mainstream options, what each is, exemplar languages, pros and cons in Mo's specific context, implementation cost, how reversible the choice is, and whether it is recommended.*

---

## How to use this document

This document is a **decision menu**, not a set of pronouncements. Each row in each table maps an option to the strongest case for choosing it — Robert's stated preference is comparisons that surface tradeoffs rather than crowning universal winners. The **Recommended for Mo?** column reflects the analysis in `mo_synthesis.md` and is meant as a defensible default, not a verdict; each recommendation carries a brief rationale so Robert (or a future Mo contributor) can weigh a divergent choice with the reasoning in hand.

Two conventions:
- **Implementation cost** is a rough estimate of engineering effort to ship a production-quality implementation, rated Low / Medium / High. It assumes a small team and an existing VM baseline (Mo's current state).
- **Reversibility** rates how hard the choice is to change *after* Mo has real users. Easy = one edition/deprecation cycle. Medium = several years of migration. Hard = essentially a new language.

The document is designed to be updated in place as decisions solidify. When a choice is locked in, mark the row **Chosen** and record the RFC number.

The final two sections — the **Recommended starting stack for Mo** and **Provocative alternatives** — pick coherent combinations from the tables and describe what a Mo built on that combination would feel like.

---

## 1. Core paradigm blend

Every language commits to a paradigm mix, even when it claims to be "multi-paradigm." Van Roy's argument that paradigms differ "only in a few concepts" ([Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)) means the choice is about which concepts to make cheap and which to make expensive. Mo's stated direction — pure by default, imperative when declared, structs+traits, ADTs+pattern matching — is a specific mix of five paradigmatic concepts.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Imperative-first | Program is a sequence of state mutations on the machine | C, Zig, Odin, Jai ([Kelley on Zig](https://andrewkelley.me/post/intro-to-zig.html)) | Matches Mo's existing VM; agent can inspect allocation sites; predictable performance | Fights the pure-by-default direction; forces effects everywhere | Low | Hard | **No** — imperative *available*, not primary |
| Functional-first (pure) | Program is a composition of pure functions; effects declared | Haskell, Elm, Roc, PureScript ([Peyton Jones "Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/); [Roc "Fast"](https://www.roc-lang.org/fast)) | Purity enables local reasoning; effect discipline emerges naturally; annotation cost paid by agent | Historical human resistance; need for effect handlers or monads for real code | Medium | Hard | **Yes** — pure-by-default is Mo's central bet |
| Actor-first | Program is a network of isolated processes exchanging messages | Erlang, Elixir, Pony, Akka ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)) | Fault tolerance for free; horizontal scaling story built in | Restrictive for non-distributed code; conflicts with borrow-checked shared memory | High | Hard | **No** — actors as a library, not a language primitive |
| OO-first (class-based) | Program is a hierarchy of classes with inheritance | Java, C#, Simula, Smalltalk ([Stroustrup HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)) | Familiar to enterprise programmers; large training corpus for LLMs | Fragile base class; complects state/identity/behavior ([Hickey "Simple Made Easy"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)); Alan Kay called it "the least important half" ([Kay HOPL II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)) | Medium | Hard | **No** — structs + traits + composition instead |
| Concatenative | Program is a composition of stack effects | Forth, Factor, Joy | Concise; naturally serializable | Alien to modern programmers; hard for LLMs (no positional argument naming) | Medium | Hard | **No** — reject as primary; borrow only the `\|>` pipeline idiom |
| Logic programming | Program is a set of clauses solved by unification | Prolog, Datalog, miniKanren | Excellent for constraint problems and analysis | Non-decidable in general; hard to give predictable performance | High | Hard | **No** as user-facing paradigm; **yes** internally for compiler analysis (Datalog is used by rust-analyzer, Polonius) |
| Hybrid (Mo's direction) | Pure-by-default expressions, imperative when declared, structs+traits, ADTs+pattern matching, first-class effects | Rust (approximate), Swift, Roc + Austral inspiration | Coherent with Mo's stated direction; each paradigm's concept is deployed for what it does best | Larger surface than any single paradigm; requires deliberate integration | Medium | Hard | **Yes** — this is the recommendation |

**Rationale for the recommendation.** Van Roy's methodology says pick *concepts* not paradigms. Mo's needed concepts — purity for reasoning, imperative regions for control, ADTs for data, effect rows for authority, traits for polymorphism — cross paradigm boundaries. The exemplar that most closely matches is Rust with Roc/Austral influence on the effect/capability side.

---

## 2. Type system foundation

The type-system menu (Camp B in the research bundle) is the deepest single design axis Mo will decide. Mo's commitments (contracts, machine verification, capabilities, effects) rule out several options immediately.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Dynamic (no static types) | Types checked at runtime only | Python, Ruby, JavaScript, Lua, Clojure | Fastest exploration; least friction | Incompatible with contracts and machine verification; ecosystem-quality problems ([Harper](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/)) | Low | Hard | **No** — incompatible with Mo's premise |
| Gradual | Static and dynamic coexist per-file; `any` opts out | TypeScript, Sorbet, mypy, Elixir ([TS handbook](https://www.typescriptlang.org/docs/handbook/); [Elixir gradual types](https://hexdocs.pm/elixir/gradual-set-theoretic-types.html)) | Migration path from dynamic; low friction | Encourages leaving code untyped; complicates verification | Medium | Medium | **No** as foundation; consider a well-defined `dynamic` escape hatch |
| Hindley–Milner (global) | Whole-program type inference; annotations rare | ML, OCaml, Haskell, Elm ([SPJ Haskell paper](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)) | Almost no annotation burden | Poor error messages; global-inference cascade under LLM edits; hard to extend to effects | High | Hard | **No** — bidirectional is strictly better in modern context |
| System F (bidirectional) | Types propagate at binders, inferred at constructors | Rust, Swift, Kotlin (in practice) ([impl. report §3.2](../camps/implementation_engineering.md)) | Excellent errors; local inference; extends naturally to effects/refinements; agent can supply annotations at binders | More annotations than HM (mostly at function signatures) | Medium | Medium | **Yes** — the mainstream modern answer |
| Dependent types | Types can depend on values; arbitrary specification | Agda, Idris, Coq/Rocq, Lean 4, F\*, ATS ([Lean 4 paper](https://lean-lang.org/papers/lean4.pdf); [Idris tutorial](https://idris2.readthedocs.io/en/latest/tutorial/conclusions.html)) | Maximum expressive power for specifications | Non-decidable type checking; requires proof search; steep learning curve even with LLM assist | Very High | Hard | **No** — too far from mainstream; use refinement types instead |
| Refinement types | Types constrained by decidable predicates; SMT-dispatched | Liquid Haskell, F\*, Verus, Prusti ([Verus](https://arxiv.org/abs/2303.05491); [Dafny](https://www.microsoft.com/en-us/research/project/dafny-a-language-and-program-verifier-for-functional-correctness/)) | Decidable; contracts naturally expressible; annotation cost paid by agent | Requires SMT solver in build pipeline; error messages need investment | High | Medium | **Yes** — the machine-verification story lives here |
| Effect-typed | Function signatures track effects (I/O, exceptions, allocation) | Koka, Eff, Frank, OCaml 5, Unison ([Koka book](https://koka-lang.github.io/koka/doc/book.html); [OCaml effects](https://ocaml.org/manual/5.3/effects.html); [Unison abilities](https://www.unison-lang.org/docs/fundamentals/abilities/)) | Effect discipline enforced by compiler; capabilities integrate naturally | Row inference is compiler engineering; syntax debate open | High | Medium | **Yes** — combined with capabilities |
| Linear/affine types | Every value used exactly (or at most) once | Clean, Linear Haskell, Austral, Rust ownership ([Austral spec](https://austral-lang.org/spec/spec.html); [Idris multiplicities](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)) | Precise resource tracking; combines with capabilities for authority | Programmer must thread values manually if fully linear | High | Hard | **Yes** as an *addition* — affine on resources, not general values |
| Capability types | Authority is a type carried on references | Pony, Wyvern, Austral, E ([Pony capabilities paper](https://www.ponylang.io/media/papers/codesigning.pdf); [Austral capabilities](https://austral-lang.org/tutorial/capability-based-security)) | No ambient authority; supply-chain safety enforced by type system | Verbose without careful syntax design; ecosystem must be built | High | Hard | **Yes** — combined with effects |

**Recommendation.** Mo's type system foundation is **bidirectional System F + row-typed effects + refinement types + affine handles on resources + capability parameters on effects**. The combined system is larger than any single existing language, but it is the sum of concepts that each independently has decade-plus track records. Austral is the closest existing prior art; Verus + Koka + Rust together sketch the rest.

---

## 3. Memory model

Memory management is the deepest engineering decision. Once made, the standard library, concurrency runtime, and even the FFI story organize around it.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Manual | Programmer calls alloc/free explicitly | C, Zig ([Zig intro](https://andrewkelley.me/post/intro-to-zig.html)) | Maximum control; predictable | Use-after-free is a real bug class; painful for high-level code | Low | Hard | **No** — even Zig is fighting this |
| Reference counting | Every value has a refcount; freed at zero | Objective-C ARC, Swift, CPython, Perl | Deterministic; low pause; simple mental model | Cycle leaks; atomic RC contention; Swift's ARC limits on concurrency | Medium | Medium | **No** — but ORC-style RC+cycle collector is a viable hybrid escape hatch |
| Tracing GC | Runtime traces roots and collects unreachable memory | Java, Go, Haskell, C#, JavaScript ([Go GC latency](https://blog.twitch.tv/en/2016/07/05/gos-march-to-low-latency-gc-a6fa96f06eb7/); [G1 tuning](https://docs.oracle.com/en/java/javase/25/gctuning/garbage-first-g1-garbage-collector1.html)) | Zero programmer burden; sophisticated in production | GC pauses (even sub-ms is nonzero); memory overhead; complicates effect signatures | High | Hard | **No** — GC pollutes the effect story |
| Ownership + borrowing | Aliasing XOR mutability; compile-time checked | Rust, Vale ([Rust NLL](https://blog.rust-lang.org/2022/08/05/nll-by-default.html); [RustBelt](https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf)) | Compile-time memory safety with no runtime cost; industry-proven | Steep learning curve; lifetime-parameter syntax is famously hard | High | Hard | **Partial** — inspire the safety, drop the lifetime parameters |
| Region-based | Values allocated in a region; freed at scope end | Cyclone, MLKit, Vale ([Tofte & Talpin](https://cpsc.yale.edu/sites/default/files/files/tr172.pdf); [Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-safety.pdf); [Vale regions](https://vale.dev/guide/regions)) | Locally auditable; O(1) deallocation; no lifetime params; matches Mo's existing VM | Restrictive for cyclic or long-lived shared data; region-inference is nontrivial | Medium | Medium | **Yes** — the recommended primary model |
| Linear / uniqueness | Each value used exactly once; enforces move semantics | Clean, Linear Haskell, Austral ([Austral spec](https://austral-lang.org/spec/spec.html)) | Precise resource control; combines with capabilities | Ergonomic burden if applied to all values | High | Hard | **Yes** on external resources (file handles, sockets), not on ordinary values |
| Generational references | RC-free non-owning references with generation-tag runtime check | Vale ([Vale page](https://vale.dev/)) | Catches use-after-free without borrow checker; friendly ergonomics | Small runtime overhead per dereference; young technology | High | Medium | **Consider** as complement to regions for cross-region references |
| Mutable value semantics | All values uniquely owned; sharing via projections only | Hylo ([Hylo page](https://www.hylo-lang.org/)) | No aliasing category; simplifies reasoning | Constrains data structures (no easy cyclic graphs); young | High | Hard | **No** — too restrictive for Mo's expected workloads |
| Hybrid (ARC + cycle collector) | Deterministic RC + async cycle detection | Nim ARC/ORC ([Nim GC docs](https://nim-lang.org/docs/gc.html)) | Deterministic; handles cycles; underrated in the field | RC atomicity cost; still has some runtime cost | Medium | Medium | **Consider** as fallback for cyclic-graph regions |
| Platform-provided | Language pure; memory strategy delegated to a runtime "platform" | Roc ([Roc "Fast"](https://www.roc-lang.org/fast); [Roc FAQ](https://roc-lang.org/faq.html)) | Clean separation; language stays small | Requires platform ecosystem; complicates FFI | Medium | Medium | **No** — Mo's users need direct control |

**Recommendation.** **Regions as primary, linear/affine on external resources, ORC hybrid as an escape hatch for cyclic data structures.** This combination is closest to what Austral proposes conceptually and what Vale is exploring practically. Rust's borrow-checker discipline informs the safety story, but Mo's regions are explicit syntax rather than inferred lifetimes, which sidesteps Rust's most-complained-about learning barrier.

---

## 4. Effect handling

Effect handling determines how side effects show up in types and how programs can intercept/redirect them. This axis is tightly coupled to the type-system foundation.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Implicit (ambient) | Effects invisible in types | Python, Ruby, JS, C, Go, Java | Zero annotation burden | Any function can do anything; incompatible with Mo's capability story | Low | Easy | **No** — undermines Mo's design |
| Monadic | Effects encoded in return types via monads | Haskell (IO, State, Reader) ([Peyton Jones "Hair Shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)) | Complete effect tracking; well-understood theory | Monad transformer stacks are notoriously painful; poor composition | Medium | Medium | **No** — algebraic effects strictly better in modern design |
| Algebraic effects with handlers | Effects declared, handlers give semantics; can resume | Koka, Eff, Frank, OCaml 5, Unison ([Koka book](https://koka-lang.github.io/koka/doc/book.html); [OCaml 5 effects](https://ocaml.org/manual/5.3/effects.html); [Multicore OCaml paper](https://kcsrk.info/papers/system_effects_feb_18.pdf); [Unison abilities](https://www.unison-lang.org/docs/fundamentals/abilities/)) | Composable; unifies exceptions, async, generators, coroutines; row inference is tractable | Compiler engineering intensive; handler stack performance requires work | High | Medium | **Yes** — this is Mo's recommended model |
| Capabilities (object) | Authority is an unforgeable reference; no ambient access | Pony, Austral, E, Wyvern, Roc platforms ([Austral capabilities](https://austral-lang.org/tutorial/capability-based-security); [Pony](https://www.ponylang.io/media/papers/codesigning.pdf)) | Compile-time authority tracking; supply-chain safety | Verbose without careful syntax; must design capabilities into every API | High | Hard | **Yes** — combined with effects |
| None | No effect tracking at all | C, Zig (mostly), Go | Simplest possible model | Incompatible with Mo's premises | Low | Easy | **No** |

**Recommendation.** **Algebraic effect handlers combined with capability parameters** — the recommended design is an effect row that includes both effect names (`<read_fs, http, exn>`) and capability parameters (`fn foo(cap: &FS) -> <read_fs> Config`). Koka's syntax is the closest published model; Austral's design is the closest published integration with capabilities.

---

## 5. Concurrency model

Concurrency choice determines the shape of the runtime and the standard library. It is hard to reverse after 1.0.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Threads and locks | OS threads with shared memory + mutexes | Java, C++, C#, POSIX threads | Universal; well-understood | Data races and deadlocks; hardest concurrency model to get right | Low | Medium | **No** — not the primary model |
| CSP with channels | Independent processes communicating over typed channels | Go, Newsqueak, Alef, Limbo, Occam ([Hoare CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf); [Wikipedia: Newsqueak](https://en.wikipedia.org/wiki/Newsqueak)) | Simple mental model; goroutines are cheap | "Colored" — hard to make sync code from channel code; channel semantics have sharp edges | Medium | Medium | **Consider** as an alternative if effect handlers prove too complex |
| Actors | Isolated processes with mailboxes; supervision trees | Erlang, Elixir, Pony, Akka ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)) | Fault tolerance; horizontal scaling; production-proven | Restrictive for non-distributed code; conflicts with borrow-checked shared memory | High | Hard | **No** as primary; provide as library |
| Async/await | Cooperative scheduling; futures typed | Rust, C#, JavaScript, Python, Swift ([Aaron Turon on futures](https://aturon.github.io/blog/2016/08/11/futures/)) | Compile-time control; integrates with types | Colored functions problem; ecosystem must be async-aware | Medium | Hard | **Yes** as user-facing syntax over effect handlers |
| Structured concurrency | Task hierarchies; parent scopes await children | Trio, Swift concurrency, Kotlin coroutines, JEP 505 ([JEP 505](https://openjdk.org/jeps/505); [Smith on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)) | Prevents dangling tasks; propagates errors and cancellation | Requires ecosystem discipline | Medium | Easy | **Yes** — layer on top of async/await |
| Software transactional memory | Transactions over shared refs; retry on conflict | Clojure, GHC Haskell | No manual locking; composable | Performance cost; interacts badly with I/O | High | Medium | **No** — provide as library if at all |
| Effect-based | Concurrency modeled as an effect handler | Koka, OCaml 5 domains ([OCaml 5 effects](https://ocaml.org/manual/5.3/effects.html)) | Unified with other effect handling; composable with cancellation and retry | Very novel; performance engineering nontrivial | High | Medium | **Yes** as the underlying implementation |
| None yet | Ship without concurrency; add later | Original Lua, early Ruby | Simpler initial scope | Retrofit is expensive; concurrency-shape decisions leak into APIs | — | Very Hard | **No** — pick early even if the initial implementation is minimal |

**Recommendation.** **Structured concurrency at the surface, implemented via algebraic effect handlers underneath.** Users see async/await-like syntax with parent-child task scopes; the compiler translates to effect handler code. Data-race freedom is enforced by the ownership+capability system rather than by `Send`/`Sync` traits. If the effect-handler runtime proves too ambitious for 1.0, ship Rust-style async/await with structured concurrency wrappers as an interim design and migrate to effects later.

---

## 6. Error handling

Error handling is the surface every function in the language touches. Choices ripple into the type system, the standard library, and even the syntax.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Exceptions | Errors unwind the stack; caught by handlers | Java, C#, Python, C++, Ruby | Familiar; low syntactic cost at call site | Errors invisible in signatures; interacts badly with concurrency and borrowing | Medium | Hard | **No** — invisible errors defeat effect discipline |
| Result / Either | Errors are values of type `Result<T, E>` | Rust, Haskell, Swift (Result), Roc ([Rust book on `?`](https://doc.rust-lang.org/book/ch09-02-recoverable-errors-with-result.html)) | Errors visible in types; composable; interacts well with pattern matching | Some syntactic overhead (mitigated by `?`) | Low | Medium | **Yes** — the modern mainstream answer |
| Error unions | Similar to Result, but built into the language | Zig ([Zig errors docs](https://ziglang.org/documentation/master/#Errors)) | Ergonomic; low syntactic cost; error sets are inferrable | Requires language-level design | Medium | Medium | **Consider** — a variation of Result worth studying |
| Condition system | Errors are conditions; restarts can resume computation | Common Lisp | Powerful; can express recovery patterns not otherwise available | Alien to most programmers; large runtime | High | Hard | **No** — too idiosyncratic |
| Effect-based | Errors are algebraic effects handled by effect handlers | Koka, OCaml 5, Unison ([Koka book](https://koka-lang.github.io/koka/doc/book.html)) | Unifies error handling with other effects; supports "resume after handling" | Requires effect infrastructure; syntax debate open | High | Medium | **Yes** — the effect handler is the primitive; Result is sugar |
| Panic-only | Fatal errors abort; no user-catchable exceptions | Early Zig (with `unreachable`); Erlang (let it crash) | Simple; enforces recovery via supervision | Cannot express recoverable errors ergonomically | Low | Medium | **No** as sole model; provide `panic`/`abort` for truly fatal cases |

**Recommendation.** **Effect-based errors surfaced as `Result<T, E>` sugar.** Under the hood, `throw` and `try` desugar to raising and handling an `<exn>` effect. `Result<T, E>` is the ergonomic form for functions that expose errors as values (with `?` for propagation, à la Rust). This unifies the design with effect handling and lets users choose their preferred style.

---

## 7. Metaprogramming

Metaprogramming is the extension mechanism for a language. Guy Steele's *Growing a Language* argues that the extension mechanism is more important than the initial feature set ([Steele, "Growing a Language"](https://www.cs.virginia.edu/~evans/cs655/readings/steele.pdf)).

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| None | No user-defined syntactic extension | Go, Zig (mostly) | Simplest to implement; guarantees stable parsing | Users cannot build DSLs; boilerplate must be language-level | Low | Easy | **Consider** as the starting point |
| Text macros | Preprocessor-style substitution | C, C++ | Well-understood; low cost | Notoriously hazardous; no hygiene; hostile to LLMs and tools | Low | Easy | **No** — universally regretted |
| Hygienic macros | Syntax rewrite with lexical hygiene | Scheme (`syntax-rules`), Rust `macro_rules!` ([Rust reference on macros](https://doc.rust-lang.org/reference/macros.html)) | Ergonomic for common patterns (deriving, DSLs); safe | Extends the language grammar in surprising ways | Medium | Medium | **Maybe** — small hygienic macros only; ban unbounded rewriting |
| Procedural macros | User code runs at compile time to generate code | Rust proc-macros, Scala macros, Lisp macros ([Rust proc-macro reference](https://doc.rust-lang.org/reference/procedural-macros.html)) | Extremely powerful; enables `derive` and framework DSLs | Arbitrary code execution at build time = supply-chain vector; slow builds; hostile to LSPs | High | Medium | **No** by default; treat as a capability that must be explicitly enabled |
| Staged compilation | Compile-time-first language with typed splicing | Zig comptime, MetaML, Terra | Type-safe metaprogramming; compile-time execution well-scoped | Requires substantial compiler machinery | High | Medium | **Consider** — Zig's model is very promising for a language of Mo's shape |
| Reflection | Runtime type introspection | Java, C#, Ruby | Very flexible for frameworks | Undermines type reasoning; runtime overhead; hostile to whole-program optimization | Medium | Medium | **No** — provides no benefit under Mo's static discipline |
| Compile-time evaluation | Pure functions can run at compile time | D (CTFE), C++ constexpr, Zig comptime, Nim ([Zig comptime docs](https://ziglang.org/documentation/master/#comptime)) | Very useful for constants, table generation, size-parameterized types | Requires effectful/pure distinction to be enforceable | Medium | Easy | **Yes** — Mo's pure functions should be evaluable at compile time |

**Recommendation.** **Compile-time evaluation of pure functions (Zig/Nim style), small `derive`-only hygienic macros for common patterns, and procedural macros as an opt-in capability that must be declared in the package manifest and enabled by the consumer.** Full proc-macros are the single largest supply-chain-security hole in the Rust ecosystem and default-off is the correct posture.

---

## 8. Module system

Module systems determine how code is organized, how dependencies are declared, and how names are shared across compilation units.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Namespace / package | Modules are grouping constructs with visibility rules | Java packages, Python modules, Go packages, Rust modules ([Rust book on modules](https://doc.rust-lang.org/book/ch07-00-managing-growing-projects-with-packages-crates-and-modules.html)) | Familiar; simple; predictable | Cannot parametrize modules directly | Low | Medium | **Yes** — the mainstream choice |
| First-class modules | Modules are values that can be passed to functions | OCaml, 1ML, Scala objects | Very flexible; unifies module and object systems | Complex type theory; poor error messages historically | High | Hard | **No** — overkill for Mo |
| ML functors | Modules can be parameterized by other modules | Standard ML, OCaml, Coq | Great for generic abstract-data-type-style libraries | Verbose; foreign to modern programmers | High | Hard | **No** — traits + generics cover the common cases |
| ML-style modules with signatures | Modules have explicit interfaces (signatures) | SML, OCaml | Excellent encapsulation and abstraction | Signature/structure split is a learning barrier | High | Hard | **Partial** — Mo should support explicit interface declarations on modules |
| Content-addressed modules | Modules identified by hash of contents, not name | Unison ([Unison big idea](https://www.unison-lang.org/learn/the-big-idea/)) | Immune to name conflicts and typosquatting; rename is free | Human-readable references require an index; unfamiliar | High | Hard | **Yes** — as the identity layer under the package system |

**Recommendation.** **Namespace/package modules with explicit interface declarations, content-addressed identity in the package manager.** The user-facing model is Rust-like (crates + modules); the identity layer under the package registry is content-addressed (Unison/Nix influence).

---

## 9. Compilation target

Compilation choice determines developer-time iteration speed, runtime performance, and deployment options.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| LLVM | Mature IR + backend for native codegen | Rust, Swift, Julia, Zig, Crystal, Odin | Highest-quality native code; supports every target | Very slow compile times; ~100MB compiler binary; complex to integrate | High | Easy | **Yes** as release-mode option, later |
| Cranelift | Rust-implemented fast backend (Wasmtime's) | Wasmtime, Rust JIT experiments ([Cranelift page](https://cranelift.dev/)) | ~10× faster compile than LLVM; production-quality for warm paths | Less-optimized code than LLVM; fewer target triples | Medium | Easy | **Yes** as primary AOT backend |
| MLIR | LLVM's newer multi-level IR for heterogeneous compute | Mojo, TensorFlow, Torch-MLIR ([MLIR paper](https://arxiv.org/pdf/2002.11054)) | Ideal for GPU/accelerator targets | Very heavy; overkill without accelerator use case | Very High | Medium | **No** — Mo isn't AI-accelerator-shaped |
| Custom VM | Own bytecode + interpreter/JIT | Erlang BEAM, Python CPython, Lua ([BEAM book](https://blog.stenmans.org/theBeamBook/); [Lua VM](https://www.lua.org/doc/jucs05.pdf)) | Complete control; fast iteration during design | No ecosystem; slower than native | Medium | Easy | **Yes** as development-time reference |
| Transpile to C | Emit C, use system C compiler | Nim, Chicken Scheme, Vala | Portable; leverages C toolchain | Ties Mo to C ABI; complicates novel effects/regions | Medium | Medium | **No** — leaks C's abstractions |
| WebAssembly-first | Wasm as the primary target | Grain, Roc (partial), Component Model languages ([WASI 0.2](https://bytecodealliance.org/articles/webassembly-the-updated-roadmap-for-developers)) | Sandboxed by construction; portable; capability-aligned | Immature compared to native; performance still catching up | Medium | Easy | **Yes** as additional target once stable |

**Recommendation.** **Staged: custom VM for dev iteration → Cranelift AOT for production → LLVM as an optional release-mode backend → Wasm/WASI/Component Model target for portable deployment.** Each stage is a reversible engineering choice; the sequencing minimizes wasted effort.

---

## 10. Bootstrapping strategy

Bootstrapping is how Mo's compiler eventually gets written in Mo. Ken Thompson's "Reflections on Trusting Trust" ([Thompson, 1984 Turing lecture](https://www.cs.cmu.edu/~rdriley/487/papers/Thompson_1984_ReflectionsonTrustingTrust.pdf)) established the ceremony matters.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Never self-host | Compiler stays in another language forever | TypeScript (was in TS, now in Go 2025) | Simplest; least ceremony | Signals immaturity; no dogfooding of Mo | Low | Easy | **No** — self-hosting is a milestone worth reaching |
| Implement in existing language then self-host | Bootstrap compiler in Rust/Go/etc.; migrate to Mo when Mo is capable | Rust (was in OCaml, then Rust), Swift, Julia | Standard path; low risk | Delayed self-hosting means Mo's early years are spent optimizing an ecosystem it doesn't use | Medium | Easy | **Yes** — Mo's current VM path fits this |
| Self-host from day one | Write compiler in Mo, bootstrap from a stripped subset | PyPy (partially), some hobby languages | Immediate dogfooding | Very slow initial progress; chicken-and-egg problem | Very High | Hard | **No** — premature optimization |
| Dual-track | Maintain both original-language and self-hosted implementations in parallel | Zig (currently maintaining Zig-in-C++ and Zig-in-Zig backends) | Redundancy; can validate one against the other | Double the maintenance | High | Easy | **Consider** — Zig's transition suggests it works |
| Bootstrappable Builds discipline | Trace the compiler's provenance back to a small trusted seed | GNU Mes, Bootstrappable Builds project ([bootstrappable.org](https://bootstrappable.org/)) | Answers Thompson's trusting-trust concern | Substantial extra work; only matters for high-assurance users | High | Easy | **Consider** — deferred, but plan for it |

**Recommendation.** **Implement Mo's compiler in Rust (matching the current dev repo), self-host once the language is capable, publish a stage-0 seed for bootstrappability once the language is mature.** The transition timing depends on when Mo's type system and effect system are stable — attempting self-hosting before those are settled means rewriting the compiler repeatedly.

---

## 11. Package registry design

Package registries have converged on a common shape, but the details differ enough that the choice matters.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Central registry | One canonical registry; publishing goes through it | npm, PyPI, crates.io, Hex, Maven Central | Single source of truth; discoverability; enforce norms uniformly | Single point of failure/censorship; ecosystem lock-in | Medium | Hard | **Yes** as default, with federation as escape hatch |
| Federated | Multiple registries; clients can use any | Go modules (URL-as-identifier) ([Go modules ref](https://go.dev/ref/mod)) | No single failure point; enterprise-friendly | Fragments discovery; harder to enforce security norms | Medium | Medium | **Yes** as federation layer over central default |
| Content-addressed | Packages identified by hash of contents | Nix, Unison ([Nix content-addressed](https://nix.dev/manual/nix/2.26/store/store-object/content-address); [Unison](https://www.unison-lang.org/learn/the-big-idea/)) | Eliminates typosquatting; perfectly reproducible; no need for lockfiles | Unreadable references without an index | Medium | Medium | **Yes** as the identifier layer |
| Git-based | Dependencies are git repos, no separate registry | Go modules (partly), Zig | Radically simple; no publishing ceremony | Slower resolution; no metadata search; auth issues | Low | Easy | **No** as primary; can support as ad-hoc source |
| No registry | Copy source into your project | Very early C, Unix tradition | Simplest possible | Duplication; no version discovery | Low | Easy | **No** — modern users won't accept this |

**Recommendation.** **Central default registry (`registry.mo-lang.org`) with federation enabled by default (any HTTPS endpoint serving the standard format), content-addressed identifiers under human-readable labels.** This combination is more permissive than crates.io, more secure than npm, and more discoverable than pure Go modules.

---

## 12. Package authority model

This axis is where Mo's design most differs from every existing production language. The default posture for every existing ecosystem is *open trust*; Mo should default to *declared authority*.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Open trust | Any published package can be imported and run with full process authority | npm (mostly), PyPI (mostly), Cargo | Zero friction; fast ecosystem growth | Every supply-chain attack the last decade exploited this | Low | Very Hard | **No** — Mo's rare freedom is to avoid this |
| Signed and verified | Packages must be signed by an authenticated publisher | Hex (GPG), Maven Central (GPG), npm provenance | Attribution; hard to publish anonymously | Signature verifies origin, not intent ([SLSA blog](https://slsa.dev/blog/2024/08/dep-confusion-and-typosquatting)) | Medium | Medium | **Yes** — baseline requirement |
| Capability-declared | Every package's manifest declares the capabilities it uses | Deno (partly), Austral, Roc (via platforms) ([Deno](https://deno.com/blog/v1); [Austral capabilities](https://austral-lang.org/tutorial/capability-based-security)) | Consumer sees authority up front; transitive authority is checkable | Verbose without careful design; ecosystem must be built | High | Hard | **Yes** — the core of Mo's design |
| Sandboxed builds | Build runs in a hermetic sandbox with no network / limited filesystem | Bazel remote execution, Nix ([Nix](https://nix.dev/manual/nix/2.26/store/store-object/content-address)) | Prevents install-time exfiltration; enables perfect reproducibility | Requires containerization infrastructure | High | Medium | **Yes** — should be default for `mo build` |
| Runtime permission flags | Executable requires runtime flags to grant permissions | Deno's `--allow-net`, Wasm sandbox ([Deno v1](https://deno.com/blog/v1)) | Second line of defense after compile-time capability check | Runtime check happens too late in build pipeline | Medium | Easy | **Yes** as complement to compile-time capabilities |

**Recommendation.** **Capability-declared manifests + Sigstore-signed OIDC-authenticated publishing + sandboxed builds + runtime capability flags for compiled binaries.** This composed defense-in-depth is significantly stronger than any existing production ecosystem, and Mo's premise (agent authorship, greenfield ecosystem) is what makes it feasible.

---

## 13. Build script policy

Related to but distinct from package authority: what code is allowed to run *during a build*?

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Arbitrary code | Packages can run any code at install/build time | npm `postinstall`, Python `setup.py`, Cargo `build.rs`, Rust proc-macros | Maximum flexibility for legitimate build tasks | The single largest supply-chain vulnerability class of the last decade | Low | Very Hard | **No** — never enable by default |
| Restricted (sandboxed) | Build code runs in a sandbox with limited permissions | Bazel sandboxed actions, Nix builder | Legitimate build code still works; attacks contained | Sandbox infrastructure is nontrivial | High | Medium | **Yes** — for build code that is opted in |
| Declarative-only | No arbitrary build code; build is a data structure interpreted by the build tool | Bazel BUILD files (partially), CMake target definitions | Reproducible; auditable | Extension mechanism must be more sophisticated | Medium | Hard | **Yes** — the default for Mo builds |
| Disabled entirely | No build hooks; everything must be declared in the manifest | Rare in practice | Simplest security posture | Legitimate needs (code generation, native library detection) require language features | Low | Medium | **No** — too restrictive |

**Recommendation.** **Declarative-only build manifests by default; sandboxed build actions as an opt-in capability declared in the manifest and consented to by the consumer.** Native code compilation is a capability the consumer opts into per-dependency, not a default. This is stricter than Cargo, Deno, and every existing package manager, and is precisely where Mo's greenfield freedom pays off.

---

## 14. Governance model

Governance is a design decision as much as a syntactic one. It scales differently at different sizes.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| BDFL | Single designer-author with final authority | Python (until 2018), Perl, Ruby, Lua | Fast decisions; coherent design | Bus factor 1; burnout risk; illegitimate at scale ([LWN — Guido's resignation](https://lwn.net/Articles/759654/)) | Low | Easy | **Yes** for pre-1.0 only |
| Steering council | Small elected group with delegated topical teams | Python (post-2018), Rust Leadership Council, Swift LSG ([Rust RFC 3392](https://rust-lang.github.io/rfcs/3392-leadership-council.html); [Python PEP 8016](https://peps.python.org/pep-8016/)) | Scalable; resilient; matches large communities | Requires community large enough to elect | Medium | Easy | **Yes** for post-1.0 |
| Foundation | Independent nonprofit owns trademark and infrastructure | Rust Foundation, Python Software Foundation, Node.js Foundation, .NET Foundation ([Rust Foundation launch](https://blog.rust-lang.org/2021/02/08/Foundation-Launch/)) | Legal cover; corporate credibility; long-term stability | Expensive (~$500K+/year); requires board governance | High | Medium | **Yes** eventually, once corporate adoption warrants |
| Corporate | Single company owns and directs the language | Swift (Apple), Kotlin (JetBrains), C# (Microsoft), Go (Google) | Well-funded; coherent | Community concerns about single-vendor lock-in | Medium | Hard | **No** — Mo is not corporate-backed |
| Community RFC | No formal authority; consensus emerges from RFC discussions | Nix (partially), some hobby languages | Democratic feel | Decisions stall; no accountability | Low | Easy | **No** as sole model; RFC process is a *tool*, not a *governance structure* |

**Recommendation.** **Staged: BDFL (Robert) with RFC process for pre-1.0 → steering council (3-5 members with at least one non-founder) post-1.0 → foundation once corporate adoption is real.** Publish the governance charter at 1.0 so the transition is not a surprise.

---

## 15. Standard library scope

Standard library scope determines how much a fresh Mo installation can do without pulling dependencies. Historically this is one of the most-debated ecosystem questions.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Batteries-included | Comprehensive stdlib: HTTP, JSON, cryptography, DB drivers, etc. | Python, Java, .NET, Go | Users can do useful work with no dependencies | Standard library evolves at language speed (slow); breaking changes affect everyone | Very High | Hard | **No** — too expensive for a small team |
| Curated core | Mid-sized stdlib: collections, I/O, common utilities; heavier things in official packages | Rust, Swift, Zig, Elixir | Small stable core; extensions can iterate independently; ecosystem stays healthy | Users must learn what's in core vs. what's external | Medium | Medium | **Yes** — the mainstream modern answer |
| Minimal core | Tiny stdlib: only what the language semantics require | Scheme (minimal), Lua | Very stable; easy to audit | Users must depend on third-party packages for everything | Low | Easy | **No** — too little for productive use |
| Runtime-provided | Language provides no stdlib; runtime/platform does | Roc (via platforms) ([Roc "Fast"](https://www.roc-lang.org/fast)) | Language stays tiny; multiple runtimes possible | Requires platform ecosystem | Medium | Medium | **Consider** — a variation worth studying |

**Recommendation.** **Curated core: collections, I/O with capability requirements, common utilities, contracts/refinements support, effect handler primitives. Everything else in official-but-separate packages.** Rust's model is the reference. Mo's stdlib should be small enough that a single maintainer can review every change.

---

## 16. Backward compatibility policy

Backward-compatibility policy is a promise to users that shapes their willingness to invest in the language.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| Never break | Every version compiles all prior code | Java (mostly), Go 1 compatibility promise ([Go 1 compat](https://go.dev/doc/go1compat)) | Users can upgrade fearlessly | Ossification; cannot fix past design mistakes | — | — | **Consider** — combined with editions |
| Editions / epochs | Small breaking changes allowed per edition; per-crate opt-in; mechanical migration | Rust (2015, 2018, 2021, 2024) ([Rust editions](https://doc.rust-lang.org/edition-guide/)) | Best of both worlds: evolution + stability | Complexity in tooling; edition boundaries require careful design | Medium | Easy (if planned) | **Yes** — the recommended model |
| Semantic versioning strict | Follow semver mechanically; major = breaking | Cargo semver checks, most modern ecosystems | Widely understood | Semver is a promise easily broken in practice ([Reprog critique](https://reprog.wordpress.com/2023/12/27/semantic-versioning-is-a-terrible-mistake/)); Hyrum's law says users depend on all observable behavior | Low | Easy | **Yes** — combined with editions |
| Major version breaks | Break freely at major versions | Python 2→3, Scala 2→3, Perl 6 | Ability to fix past design | Massive user migration cost; often ecosystem-destroying (Perl 6, Python 3 pain) | — | Hard | **No** — the cautionary tales are decisive |
| Rolling deprecation | Feature marked deprecated → warning → removed over N releases | Many languages informally | Predictable; users have time to migrate | Requires disciplined communication | Low | Easy | **Yes** — as the day-to-day process |

**Recommendation.** **Rust-style editions from day one (each source file declares `edition = "1"`), semver for the compiler, rolling deprecations for stdlib, and Go-1-style compatibility promise within an edition.** Make the migration tooling (`mo fix --edition`) a first-class feature.

---

## 17. Syntax family

Syntax family is largely aesthetic but has real ergonomic and technical implications, especially under LLM authorship.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| C-family curly braces | Statements terminated by `;`, blocks delimited by `{}` | C, C++, Java, C#, JavaScript, TypeScript, Rust, Go, Swift, Zig | Familiar to majority of programmers; unambiguous grammar; excellent for LLM incremental generation | Somewhat verbose | Low | Very Hard | **Yes** — the mainstream modern answer |
| ML expression-oriented | Everything is an expression; whitespace-independent | ML, OCaml, F#, Haskell, Elm, Scala | Excellent for functional composition; concise | Fewer syntactic anchors for LLMs; can be terse to the point of unreadable | Low | Very Hard | **Consider** — hybrid works (Rust is expression-oriented within C-family syntax) |
| Lisp S-expressions | Everything is `(head args...)`; homoiconic | Common Lisp, Scheme, Clojure, Racket | Trivially LL(1); enables powerful macros | Alien to most programmers; ambiguous grammar for LLMs (parens are underloaded); no unique anchors | Low | Very Hard | **No** — closes off too much |
| Python-style indentation | Blocks delimited by indentation | Python, Haskell (layout), Nim, F# | Concise; visually clean | Indentation-sensitive lexing is hostile to LLM incremental generation ([history/03_2010_to_2026.md, §4.1](../history/03_2010_to_2026.md)) | Medium | Very Hard | **No** — LLM-hostility is decisive |
| Hybrid (Mo's direction) | C-family curly braces + expression-oriented semantics | Rust, Swift | Best of both; industry-proven | Requires careful spec design | Low | Very Hard | **Yes** — the recommendation |

**Recommendation.** **C-family curly braces with expression-oriented semantics (Rust/Swift model), LL(1) or LALR(1) grammar, mandatory semicolons or newlines with explicit continuation, no user-defined operator precedence, and a canonical formatter (`mo fmt`) with no options.**

---

## 18. Verification integration

Verification integration is where Mo's premise — machine verification has stronger leverage than novel syntax — most directly cashes out.

| Option | What it is | Exemplar languages | Pros for Mo | Cons for Mo | Impl cost | Reversibility | Recommended? |
|---|---|---|---|---|---|---|---|
| None | No compiler-side verification beyond type checking | C, Zig, Go | Simplest; no solver dependency | Undermines Mo's central design bet | Low | Easy | **No** — inconsistent with Mo's premise |
| Refinement (SMT-checked) | Types constrained by decidable predicates; SMT-solved at compile time | Liquid Haskell, F\*, Verus, Prusti ([Verus](https://arxiv.org/abs/2303.05491); [Prusti](https://viperproject.github.io/prusti-dev/user-guide/)) | Contracts naturally expressible; annotations affordable for agents; usually decidable | Requires Z3/CVC5 in build pipeline; error messages need investment | High | Medium | **Yes** — the recommendation |
| Dependent-adjacent | Types can depend on limited values (e.g., array indexing) | Dependent Haskell (partial), F\* | More expressive than pure refinement | Approaches undecidability | High | Hard | **Consider** — a graduation path from refinement |
| Proof-first (dependent) | Full dependent types; user writes proofs | Agda, Idris, Coq/Rocq, Lean 4 ([Lean 4](https://lean-lang.org/papers/lean4.pdf)) | Maximum expressive power | Too heavyweight for a general-purpose language; steep learning curve | Very High | Hard | **No** — but interop with Lean/F\* as an export target is worth considering |
| Hybrid (staged) | Ordinary code type-checks; verified subset uses SMT-backed contracts | F\*, Dafny, Verus | Users pay verification cost only where warranted | Requires two-mode compiler | High | Medium | **Yes** — the practical form |
| Model-checking integration | Bounded model checker as an external tool | Kani for Rust, TLA+ for design ([Kani docs](https://model-checking.github.io/kani/)) | Automatic; no proofs needed | Only sound within bound | High | Easy | **Consider** — a complementary tool |

**Recommendation.** **Hybrid: ordinary Mo code type-checks with bidirectional inference; SMT-backed refinement types and contracts are opt-in via annotations that dispatch to Z3 at compile time. Provide a `--verify` flag that runs the SMT checks (they can be skipped in fast-iteration builds).** This mirrors Verus and Dafny; it is the modern practical form of verification integration.

---

## Recommended starting stack for Mo

The following combination picks one option from each axis to form a coherent starting stack. The choices reinforce each other: the type system supports the effect discipline, the memory model supports the concurrency runtime, the tooling supports the LLM authorship premise, and the package system supports the capability discipline.

| Axis | Choice |
|---|---|
| 1. Paradigm blend | Pure-by-default expressions, imperative regions, structs+traits, ADTs+pattern matching |
| 2. Type system | Bidirectional System F + row-typed effects + refinement types + affine handles + capability parameters |
| 3. Memory model | Regions as primary, affine on external resources, ORC hybrid escape hatch |
| 4. Effect handling | Algebraic effect handlers + capability parameters (Koka + Austral synthesis) |
| 5. Concurrency model | Structured concurrency surface over effect-handler runtime; fall back to async/await if effects too complex for 1.0 |
| 6. Error handling | Effect-based errors, surfaced as `Result<T, E>` sugar |
| 7. Metaprogramming | Compile-time evaluation of pure functions (Zig-style); `derive`-only hygienic macros; proc-macros default-off (opt-in capability) |
| 8. Module system | Namespace/package modules with explicit interfaces; content-addressed identity in the registry |
| 9. Compilation target | Custom VM → Cranelift AOT → LLVM release option → Wasm/WASI/Component Model |
| 10. Bootstrapping | Compiler in Rust; self-host once type/effect system stable; publish stage-0 seed later |
| 11. Package registry | Central default + federation; content-addressed identifiers under human labels |
| 12. Package authority | Capability-declared manifests + Sigstore OIDC signing + sandboxed builds |
| 13. Build script policy | Declarative-only by default; sandboxed opt-in |
| 14. Governance | BDFL (Robert) pre-1.0 → steering council post-1.0 → foundation later |
| 15. Standard library scope | Curated core (like Rust); rest as official packages |
| 16. Backward compatibility | Rust-style editions from day one; semver + rolling deprecations |
| 17. Syntax family | C-family curly braces + expression-oriented semantics; LL(1)/LALR(1); mandatory terminators |
| 18. Verification integration | Hybrid: refinement types and contracts opt-in, SMT-backed via Z3 |

### Why these choices reinforce each other

- **Type system + memory model + effects.** Refinement types can predicate over regions (`region r where all_freed(r)`), affine handles let capabilities be linear-typed resources, and effect rows include capability parameters. The three are one integrated system, not three separate features.
- **Effect handlers + concurrency + error handling.** Async is an effect; errors are an effect; cancellation is an effect. All flow through the same handler mechanism, which reduces the mental model to a single concept.
- **Syntax + compilation + tooling.** LL(1)/LALR(1) grammar makes tree-sitter, LSP, and grammar-constrained LLM decoding trivially implementable. C-family curly braces integrate with the mainstream tooling ecosystem.
- **Package authority + effects + capabilities.** A package's declared capabilities in the manifest correspond directly to the capabilities its code carries in function signatures. The compiler enforces subset consistency: a package cannot use capabilities its manifest does not declare.
- **Bootstrapping + governance + standard library.** A small stdlib is maintainable by a single BDFL; a stdlib written in Mo becomes possible once the language self-hosts; a foundation eventually funds the ongoing maintenance.
- **Verification + agent authorship + backward compatibility.** Editions let the verification vocabulary evolve without breaking existing verified code; agent-supplied annotations amortize the cost of a verifier that would be too expensive for pure human authorship.

The starting stack is opinionated but not narrow — every choice above is defensible with historical evidence, and every choice above admits a fallback (documented in the tables) if the primary design proves too ambitious.

---

## Provocative alternatives

Two coherent alternatives to the starting stack are worth articulating, if only to make the primary choice more considered. A third stack is included as a "what if Mo were much smaller in scope" thought experiment.

### Alternative 1 — The "Rust with better manifest security" stack

This alternative keeps most of Rust's design but focuses innovation entirely on the supply-chain security layer. It would look like:

| Axis | Choice |
|---|---|
| Paradigm | Rust-shaped |
| Type system | Rust's affine+trait system (no refinement types, no full effects) |
| Memory model | Rust ownership + borrowing with lifetime parameters |
| Effect handling | None (implicit like Rust today) |
| Concurrency | Async/await (Rust-shaped) |
| Error handling | `Result<T, E>` + `?` (Rust-shaped) |
| Package registry | Central + federated + **capability-declared manifest** + **default-off build scripts** + **OIDC publisher signing** + **release-age gates** |
| All other axes | Match Rust's current choices |

**Argument for**: minimizes design risk, maximizes the chance of shipping 1.0 quickly, ports the entire Rust ecosystem of tooling knowledge. The differentiator is *only* the package security story.
**Argument against**: gives up Mo's biggest design bet — that agent authorship inverts annotation economics for effects and refinement types. Mo becomes "Rust with a better `cargo`" rather than "the AI-era language."

### Alternative 2 — The "Verus/Dafny-shaped, verify-heavy" stack

This alternative pushes further into verification than the primary recommendation, closer to Dafny or F\* in ambition.

| Axis | Choice |
|---|---|
| Paradigm | Pure functional-first (like Roc or F\*) |
| Type system | Refinement + dependent-adjacent types; SMT-verified by default |
| Memory model | Roc-style platform-provided (language is pure; runtime handles allocation) |
| Effect handling | Effect rows with handlers |
| Concurrency | Effect-based |
| Error handling | Effect-based |
| Metaprogramming | Staged compilation only |
| Standard library | Minimal core, everything else in verified packages |
| Verification | Every function has pre/post/invariant contracts; SMT check is default-on |

**Argument for**: fully realizes the "verification renaissance" bet documented in the AI-era history ([history/03_2010_to_2026.md, §4.5](../history/03_2010_to_2026.md)); Mo would ship as the first language where every stdlib function has a machine-checked contract.
**Argument against**: hugely ambitious; extends the timeline to 1.0 by years; requires Mo to compete with F\* and Dafny on their home turf; may produce a language too specialized for general use.

### Alternative 3 — The "Unison + capabilities, everything content-addressed" stack

The most provocative alternative: bet the entire language on content-addressed code and capabilities, following Unison to its logical conclusion.

| Axis | Choice |
|---|---|
| Module system | Content-addressed everywhere (no filenames, no imports; functions referenced by hash) |
| Package system | No traditional registry — a distributed content-addressed store like IPFS |
| Effect handling | Unison abilities |
| Type system | Bidirectional + refinement + capability + ability rows |
| Metaprogramming | None (pure content-addressed code is metaprogrammable via ordinary function composition) |
| Backward compatibility | Not a concept — every function's hash is stable, so old functions are always callable |

**Argument for**: eliminates entire classes of problems (typosquatting, dependency-version conflicts, name collisions, backward-compatibility breaks) by architectural decision. Uniquely well-suited to a world of AI-authored code where functions might have no natural human name.
**Argument against**: extremely unfamiliar to the target user base; requires Mo to build a content-addressed distribution infrastructure Unison is still working out ([Unison learn](https://www.unison-lang.org/learn/the-big-idea/)); social friction of "no filenames" is real.

---

## Living-document reminders

This matrix is intended to be updated as design decisions solidify. Practical maintenance:

- When a decision is finalized in an RFC, mark the row **Chosen** and add the RFC number in the "Recommended?" column.
- When a design decision is rejected in an RFC, mark the row **Rejected** with the RFC number.
- Add new rows as new options emerge — the field is expanding faster than at any prior point.
- Cross-reference the RFC repo from the matrix so future contributors can trace decisions to their rationales.

The matrix is not a substitute for the deeper analysis in `mo_synthesis.md` and the source reports; it is a **navigation aid** for reasoning about Mo's design as a whole rather than as isolated choices.
