---
title: "Mo vs Austral"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, security, effects]
sources: [raw/articles/austral-spec.md, raw/articles/austral-spec-error-handling.md, raw/articles/austral-tutorial-capabilities.md, raw/articles/austral-tutorial-linear-types.md, raw/articles/borretti-introducing-austral.md, raw/articles/borretti-how-capabilities-work-austral.md, raw/articles/austral-github-repo.md, raw/papers/bronze-gc-rust-rct-icse22.md, raw/papers/linear-types-large-scale-verification-oopsla22.md]
confidence: medium
---

# Mo vs Austral

**One line:** the clearest existing "capabilities as the permission system" ([[d15-effects-via-capabilities|direction 15]], [[p13-capabilities-and-logging|pick 13]]), built on linear types in a deliberately small language; on the list for how capabilities start at the root and get threaded, and for what linearity would buy Mo.

## What it is (status as of Sep 2026)

Fernando Borretti describes Austral as "Rust: The Good Parts or a modernized, stripped-down Ada", with linear types, capability-based security and strong modularity.[56] Its first design goal is "fits-in-head simplicity", measured by how briefly the language can be described.[53] The bootstrapping compiler, written in OCaml, "implements every feature of the spec" but has no separate compilation. A standard library with capability-based filesystem access "is being designed".[58] The last commit to the compiler repo was on 28 July 2025, so the project has been quiet for more than a year.[61]

## The ideas, one by one

- **Linear types, two universes.** Every type is `Free` (usable any number of times) or `Linear` (used exactly once). The rules are brief enough that "the type system rules fit in a napkin", with no SMT solver.[53] A resource's lifecycle becomes a type rule:[53]
  ```
  type File: Linear
  File openFile(String path)
  File writeString(File file, String content)
  void closeFile(File file)
  ```
  Forgetting `closeFile`, or using `file` after it, is a compile error.
  - *Mo today:* no linear types. Values plus `var` / `inout` ([[d13-local-var-and-inout|direction 13]]). OS resources live in the platform ([[q11-platform-and-stdlib|Q11]]).
  - *Verdict:* **open.** A linear type for *all* memory is what Mo's value semantics already avoids. A narrow linear kind for must-consume values is a different, smaller question (see below).

- **Capabilities from a root, threaded as values.** A capability can be destroyed, surrendered, and never duplicated or "acquired out of thin air".[54] `RootCapability` is the only capability built into the language, and only the entrypoint receives it:[57]
  ```austral
  function main(root: RootCapability): ExitCode is
      let cap: EnvCap := acquire(&root);
      print(get(&cap, "HOME"));
      release(cap);
      surrenderRoot(root);
  ```
  The recommended pattern is for `main` to acquire what it needs, surrender the root, then call into the program with narrow capabilities.[57]
  - *Mo today:* the same shape. `fn main(platform: Platform)`, passed down and narrowed on the way (`fs.scoped("/var/app").read_only`) ([[p13-capabilities-and-logging|pick 13]]).
  - *Verdict:* **already have.** **Steal** the surrender rule: `Platform` itself never leaves `main`.

- **What Austral's capabilities can't do.** They are irrevocable: nothing built in lets a holder revoke a capability it handed out. They can't enforce global uniqueness, such as one terminal writer, without consuming the root.[57]
  - *Mo today:* capabilities are ordinary values ([[p13-capabilities-and-logging|pick 13]]). Nothing says whether they can be copied.
  - *Verdict:* **open.** If Mo's capabilities are copyable, uniqueness is out of reach. If they're linear, every signature pays for it.

- **Unsafe modules, and the admitted gap.** Any module that uses the FFI or raw memory must say `pragma Unsafe_Module;`. Borretti is blunt that "you can still have supply-chain attacks in Austral"; only the scope of auditing shrinks.[57] He sketches two fixes. The build system could make you accept or reject each dependency's unsafe modules in the lockfile. Or an `Unsafe` capability could come from the root.[57]
  - *Mo today:* no unsafe code in application code or libraries; only platforms have it ([[q16-escape-hatch|Q16]]). Auditing a platform is an open Q17 sub-question ([[q17-package-management-and-supply-chain|Q17]]).
  - *Verdict:* **already have**, and stricter. **Steal** the lockfile audit workflow as a Q17 input, applied to platforms.

- **Crash on contract violation, whole program.** Austral separates failure conditions (values) from contract violations (overflow, out-of-bounds, divide by zero). It rejects exceptions, and argues affine types are "strictly worse" than linear ones without them.[53] Between terminating the program and terminating the thread, it picks the program "by a hair". A thread that crashes and gets ignored can leave "leaked memory and hanging file handles", which in a long-running server is a denial-of-service risk. The cost is harder testing of crashing code.[53]
  - *Mo today:* a bug crashes the *process*, and a supervisor restarts it ([[d18-two-kinds-of-failure|direction 18]], [[q07-process-api|Q7]]). `test rejects` requires crashes to be cheap to observe ([[p12-tests|pick 12]]).
  - *Verdict:* **already have** thread-level crashes, the option Austral turned down. Austral's objection is Mo's to-do: a crashed process must leak nothing.

- **Terminating keywords name their construct** (`end if`, `end module`), after Ada.[53]
  - *Mo today:* bare `end`; labels rejected ([[p01-blocks-keyword-end|pick 1]]).
  - *Verdict:* **reject**, as already decided.

## What it gives up

- **Proving contracts statically.** "Z3 is 300,000 lines of C++", so Austral leaves static contract proving to research to stay simple.[53] Mo takes the opposite bet in tier 3 ([[q08-verification-tiers|Q8]]).
- **Terseness.** Linear threading and explicit release are verbose, and Austral accepts that "for simplicity".[53] Mo's value semantics avoid most of it.
- **Momentum.** No commits in over a year, and a standard library still being designed.[58][61] Mo accepts no such cost.

## Evidence

- **Linearity helps provers:** adding linear types to Dafny for a verified key-value store cut proof lines by 28% and total verification time by 30%. Memory errors were reported "at precise lines of code".[60]
- **Aliasing costs humans:** in a randomized trial with 428 students, a task needing complex aliasing took Rust users about 12 hours. With a garbage collector (Bronze) it took about 4 hours.[59]
- **Austral in production:** no adoption data found.
- **LLMs and linear types:** no evidence found this pass.

## What Mo should take from this

- **Proposal:** `Platform` never leaves `main`. `main` narrows and hands out, and the formatter-level signature of every other function lists only narrow capabilities.[57]
- **Question for Robert:** a small linear kind, for example `resource struct Lease`, whose values must be consumed exactly once. A job lease must be acked or failed, and a transaction committed or rolled back. That turns [[q14-first-real-program|Q14]]'s "never run a job twice" from a test into a type error. Linear Dafny suggests it also shrinks tier-3 proofs.[60]
- **Question for Robert:** can capabilities be copied? Copyable is simpler. Non-copyable enables uniqueness (one log writer) and a path to revocation.[57]
- **Proposal:** a crash-cleanup contract. When a process crashes, the runtime reclaims its memory and every platform handle it held. State outside the program (locks, files) is the supervisor's job to reconcile on restart. This answers Austral's reason for rejecting thread-level crashes.[53]
- **Q17 input:** a lockfile-recorded audit of each platform's native code, following Borretti's per-dependency unsafe-module audit.[57]
- ⚠️ **Tension between [[q08-verification-tiers|Q8]] (SMT prover in tier 3) and [[d24-compile-to-c-via-zig|direction 24]] / [[q11-platform-and-stdlib|Q11]] ("Zig toolchain as the only dependency", "zero third-party dependencies").** Austral cites Z3's size as the reason to skip proving.[53] Mo must write a solver, vendor one, or accept a dependency. Not resolved here.

## Related
- [[language-landscape]]
- [[d15-effects-via-capabilities]]
- [[p13-capabilities-and-logging]]
- [[q16-escape-hatch]]
- [[q17-package-management-and-supply-chain]]
- [[d18-two-kinds-of-failure]]
- [[koka]]

## Sources

[53] https://austral-lang.org/spec/spec.html — The Austral Language Specification
[54] https://austral-lang.org/tutorial/capability-based-security — Austral tutorial: Capability-Based Security
[56] https://borretti.me/article/introducing-austral — Introducing Austral (Borretti, 2022)
[57] https://borretti.me/article/how-capabilities-work-austral — How Capabilities Work in Austral (Borretti, 2023)
[58] https://github.com/austral/austral — Austral compiler repository
[59] https://dl.acm.org/doi/10.1145/3510003.3510107 — Garbage Collection Makes Rust Easier to Use: an RCT of the Bronze GC (ICSE 2022)
[60] https://doi.org/10.1145/3527313 — Linear Types for Large-Scale Systems Verification (OOPSLA 2022)
[61] https://github.com/austral/austral/commits/master — Austral commit history (last commit 28 Jul 2025, checked 12 Sep 2026)
