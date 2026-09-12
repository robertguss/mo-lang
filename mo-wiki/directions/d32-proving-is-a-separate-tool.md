---
title: "Direction 32: Proving is a separate tool; tier 3 v0 is testing in the interpreter"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [verification, tooling]
sources: [research/comparisons/austral.md, research/comparisons/bosque.md, research/comparisons/spark-ada-and-dafny.md]
number: 32
status: liked
origin: "Claude's decision at Robert's request (session 3)"
confidence: low
---

# Direction 32: Proving is a separate tool; tier 3 v0 is testing in the interpreter

Resolves tension 4 of the [[comparison-synthesis-draft]]: an SMT prover in tier 3 ([[q08-verification-tiers|Q8]]) against "Zig is the only dependency" ([[d24-compile-to-c-via-zig|direction 24]], [[q11-platform-and-stdlib|Q11]]). Z3 is about 300K lines of C++ ([[austral]]).

- **Tier 3 in v0** is property testing under many seeds and simulation with fault injection, executed by the interpreter ([[d25-interpreter-for-the-edit-loop|direction 25]]). Zero dependencies. Contracts are the properties.
- **Proving** lives in `mo prove`, a separate optional binary that vendors a pinned, hashed, statically linked solver. It is never in the build path of a user program and never required for a merge in v0.
- The zero-dependency law covers the core toolchain and every user build. The prover is outside it by declaration, not by accident.
- Bosque-style small-model checking (bounded unrolling, counterexample search) written in Zig is the likely middle step ([[bosque]]).

```ruby
verified: types, contracts run (2 tests, 1 rejects), property 200 seeds, sim 20 faults
          proven: not run          # `mo prove` would upgrade this line
```

First tested by: how far property tests plus simulation get on the example corpus before anyone misses a prover. Reopen if a real program's `never` clauses need proof to be trusted.

## Related
- [[q08-verification-tiers]]
- [[d24-compile-to-c-via-zig]]
- [[austral]]
- [[bosque]]
