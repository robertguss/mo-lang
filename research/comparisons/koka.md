---
title: "Mo vs Koka"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, effects, performance]
sources: [raw/articles/koka-book.md, raw/articles/koka-release-v3-2-3.md, raw/papers/perceus-reference-counting-with-reuse.md, raw/papers/fp2-fully-in-place-functional-programming.md, raw/papers/generalized-evidence-passing-effect-handlers.md, raw/papers/effects-as-capabilities-oopsla20.md, raw/papers/effects-capabilities-boxes-oopsla22.md, raw/papers/capabilities-effects-for-free-icfem18.md]
confidence: medium
---

# Mo vs Koka

**One line:** the language behind the memory model Mo wants (Perceus) and the effect system Mo declined ([[d15-effects-via-capabilities|direction 15]]); on the list to hold Mo's capability parameters against effect types and handlers, and to check that choice against the research.

## What it is (status as of Sep 2026)

Koka describes itself as "a strongly typed functional-style language with effect types and handlers".[45] v3.2.3 shipped on 18 March 2026.[46] The book calls Koka v3 "a research language … not ready for production use". The language is stable and the compiler implements the full spec; async libraries and package management are missing.[45] Koka compiles to C11 with no runtime system.[47] The Perceus paper won a distinguished paper award at PLDI'21.[45]

## The ideas, one by one

- **Effect types in every signature.** The effect is part of the function type:[45]
  ```koka
  fun sqr    : (int) -> total int       // pure, terminates
  fun divide : (int,int) -> exn int     // may raise
  fun turing : (tape) -> div int        // may not terminate
  fun print  : (string) -> console ()   // does I/O
  ```
  - *Mo today:* no effect types. A function is pure unless it takes a capability parameter ([[d15-effects-via-capabilities|direction 15]]).
  - *Verdict:* **reject** effect rows, as already decided. **Open:** Koka's `div` makes *non-termination* visible. Mo's loops are bounded ([[p11-loops-and-anonymous-functions|pick 11]]), but nothing yet says whether recursion is bounded.

- **Effect handlers: control flow as a library.** An operation is declared abstractly, and a handler in scope gives it meaning. That makes exceptions, async/await and probabilistic programs user libraries.[45]
  ```koka
  effect fun emit(msg : string) : ()
  fun hello() : emit ()
    emit("hello world!")
  fun hello-console() : console ()
    with handler
      fun emit(msg) println(msg)
    hello()
  ```
  - *Mo today:* no try-catch anywhere ([[d18-two-kinds-of-failure|direction 18]]). The runtime is the single interception point ([[d16-direct-style-io|direction 16]]). Swapping `Mo.Server` for `Mo.Sim` replaces every effect at once ([[q11-platform-and-stdlib|Q11]]).
  - *Verdict:* **reject** user-defined handlers. A handler for `exn` is a catch, and would let code turn a bug into a handled outcome. Mo already has the one handler it needs: the platform, installed at `main`.

- **Capabilities instead of effect types, as research.** In a capability-safe language, an expression's effects are bounded by the authority it holds. Capabilities give effect reasoning "for free".[52] Effekt builds on this. A function that closes over a capability can use its effects "not visible in the type of the function", which simplifies higher-order signatures.[51] The same paper names the cost: "since closure over capabilities is not visible in a function's type, it often hinders reasoning about its purity".[51] The known fix makes capabilities *second-class*: they can be passed, but not returned or stored, which "rules out a large class of programs". Its successor, System C, restores first-class use with "boxes" that record impurity in types.[51]
  - *Mo today:* "the signature is the purity proof" ([[d15-effects-via-capabilities|direction 15]]). Anonymous functions capture locals, as in `fn(r) r.charge == c.id end` ([[p11-loops-and-anonymous-functions|pick 11]]). Capabilities are narrowed and handed back, as in `fs.scoped("/var/app")` ([[p13-capabilities-and-logging|pick 13]]).
  - *Verdict:* **open**, with a ⚠️ below. This is the one place where the research contradicts Mo's wording.

- **Perceus: precise reference counting with reuse.** Perceus inserts reference-count operations so that cycle-free programs are "garbage free", and unique values are reused in place. It needs explicit control flow and no stack unwinding.[47] Koka's immutable inductive data types can't form cycles.[47] In the book's red-black tree benchmark, Koka ran in 0.626s against 0.667s for C++ `std::map`, because Perceus turns the functional rebalancing into mostly in-place updates.[45]
  - *Mo today:* Perceus-style reuse without a GC ([[d10-immutable-by-default|direction 10]]). No exceptions, so control flow is explicit ([[d18-two-kinds-of-failure|direction 18]]).
  - *Verdict:* **already have.** Mo meets Perceus's precondition by construction, except for one exit: the crash.

- **Fully in-place functions (`fip`).** `fip fun` is a static check that a function runs fully in place: no allocation or deallocation, and constant stack space.[48] Splay trees, finger trees, merge sort and quicksort are all expressible.[48]
  ```koka
  fip fun left(t : stree, ctx : szipper) : (stree, szipper)
  ```
  - *Mo today:* nothing like it. The laws are about size and shape ([[q12-law-numbers|Q12]]), not allocation.
  - *Verdict:* **steal**, as a compiler-checked property rather than a keyword. It is Tiger Style's "no allocation on the hot path" turned into a proof.

- **Effect handlers compiled to C.** Koka compiles handlers to C through evidence passing and was benchmarked against multicore OCaml and other native implementations.[49] Segmented stacks, the alternative, "need a dedicated runtime system".[49]
  - *Mo today:* direct-style I/O on green threads ([[d16-direct-style-io|direction 16]]), emitted as C through Zig ([[d24-compile-to-c-via-zig|direction 24]]).
  - *Verdict:* **open.** Mo needs *some* way to suspend and resume in C: stack switching, segmented stacks, or a Koka-style translation. The choice is unmade and belongs in the benchmark suite.

## What it gives up

- **Readable signatures.** The Effekt authors say effect systems "track too much information. Types quickly become verbose, difficult to understand".[51] Mo does not accept this cost, but see the closure gap below.
- **Production readiness.** No async libraries and no package manager.[45]
- **Cyclic data.** Perceus assumes cycles are rare because data is immutable and inductive.[47] Mo makes the same bet.

## Evidence

- **Tree performance:** red-black tree inserts took 0.626s in Koka against 0.667s for C++ `std::map` on the book's machine.[45]
- **FP²:** a proof that `fip` functions need no (de)allocation and constant stack.[48]
- **Handler compilation:** benchmarked against multicore OCaml and others. The numbers are in the paper and were not extracted.[49]
- **Usability of effect types vs capabilities:** the arguments above are from language designers, not user studies. **No user study found.**
- **LLMs and effect-typed code:** no evidence found this pass.

## What Mo should take from this

- ⚠️ **Contradicts the wording of [[d15-effects-via-capabilities|direction 15]] ("the signature is the purity proof").** An anonymous function can capture a capability. So `xs.filter(fn(r) db.exists?(r, within: 50.ms) end)` does I/O, while `filter`'s signature holds no capability.[51] Three known ways out, none resolved here:
  - (a) Capabilities are second-class and can't be captured, stored, or returned.[51] This conflicts with narrowing, `fs.scoped(...)` in [[p13-capabilities-and-logging|pick 13]].
  - (b) A function *type* marks that it captures capabilities, like System C's boxes.[51]
  - (c) Anonymous functions alone may not capture capabilities. This is Mo-specific and untested.
- **Question for Robert:** recursion. Ban it (Power of Ten, rule 1), bound it, or allow it? Koka shows that otherwise non-termination is an effect you can't see.
- **Proposal:** a checkable "allocates nothing, constant stack" property on chosen functions, in the `fip` style,[48] run as a tier-1 check ([[q08-verification-tiers|Q8]]).
- **Proposal (hypothesis):** give each process its own heap region, so a crash frees the region whole. The crash is the one exit Perceus's explicit-control-flow precondition doesn't cover.[47] Measure it under [[d28-nothing-final-until-measured|direction 28]].
- **Proposal:** before committing [[d16-direct-style-io|direction 16]]'s suspension strategy in C, prototype two options (stack switching, and a Koka-style translation)[49] and benchmark them.
- **Confirmed, no change:** no effect handlers in user code. A handler for failure is a catch, and [[d18-two-kinds-of-failure|direction 18]] forbids that.

## Related
- [[language-landscape]]
- [[d15-effects-via-capabilities]]
- [[d16-direct-style-io]]
- [[d10-immutable-by-default]]
- [[d18-two-kinds-of-failure]]
- [[d24-compile-to-c-via-zig]]
- [[p13-capabilities-and-logging]]
- [[roc]]

## Sources

[45] https://koka-lang.github.io/koka/doc/book.html — The Koka Programming Language (book)
[46] https://github.com/koka-lang/koka/releases/tag/v3.2.3 — Koka v3.2.3 release
[47] https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v4.pdf — Perceus: Garbage Free Reference Counting with Reuse (Reinking, Xie, Leijen, Swamy; PLDI 2021)
[48] https://webspace.science.uu.nl/~swier004/publications/2023-icfp.pdf — FP2: Fully in-Place Functional Programming (Lorenzen, Leijen, Swierstra; ICFP 2023)
[49] https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf — Generalized Evidence Passing for Effect Handlers (Xie, Leijen; ICFP 2021)
[51] https://se.informatik.uni-tuebingen.de/publications/brachthaeuser22effects.pdf — Effects, Capabilities, and Boxes (Brachthäuser et al.; OOPSLA 2022)
[52] https://potanin.github.io/files/CraigPotaninGrovesAldrichICFEM2018.pdf — Capabilities: Effects for Free (Craig, Potanin, Groves, Aldrich; ICFEM 2018)
