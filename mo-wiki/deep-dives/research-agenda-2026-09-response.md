---
title: "Research agenda, Sep 2026: Fable's response to the contradictions"
created: 2026-09-13
updated: 2026-09-17
type: deep-dive
tags: [meta, laws, research, verification, processes]
sources: [research/prompts/prompts-research-agenda-2026-09.md, research/concepts/agents-and-verification-2026.md, research/concepts/language-design-for-llms-evidence.md, research/concepts/reliability-and-testing-philosophies.md, research/concepts/safety-critical-coding-standards.md, research/concepts/author-joe-armstrong.md, research/concepts/author-edsger-dijkstra.md, decisions/decision-log.md]
confidence: medium
contested: true
contradictions: [language-design-for-llms-evidence, safety-critical-coding-standards]
---

# Research agenda, Sep 2026: Fable's response to the contradictions

Robert merged [[prompts-research-agenda-2026-09|the research agenda]] on 13 Sep with twelve concept pages from its runs R1, R3, and R6: two on the LLM literature, two on the safety and reliability traditions, and eight author profiles. Each page ends with a table marking ideas "contradicts Mo". Fable read all twelve the same night, after round 4 of the control run, and made a call on each contradiction: **agree** (Mo changes, or already did), **disagree** (Mo stands, with the reason), or **test** (a named experiment decides). Rows for anything that changes something are in [[decision-log]] under this date.

Three contradictions were already settled before the pages were written. Step 20 removed the fictional loop bounds Dijkstra warns against ([[interpreter-step-20]]). Chapter 3's failure model answers Armstrong's R6 with the store recipe, though not by that name. Round 4 re-evaluated the shape laws against three rounds of loops ([[control-run-4]]). The pages were written from the vault as it stood at noon; the calls below are against the tree as it stands at midnight.

## The calls

| contradiction | source page | call |
|---|---|---|
| Invariant synthesis is cheap, so verifiability is a weak reason to ban `while` | [[agents-and-verification-2026]] | **agree on the premise.** The ban was never argued from verifiability in chapter 2, and after step 20 the runtime is the loop. The rationale is legibility and the removal of fictional bounds; round 5 tests it. |
| Numeric shape laws as model-performance levers; complexity metrics do not predict LLM performance | [[language-design-for-llms-evidence]] | **agree, no change.** The shape laws were never a model-performance claim. Their justification is human review economics and one declaration per ID edit; rounds 2 to 4 tripped none. Round 5 keeps counting. |
| Shape numbers are "should" rules at JPL; MISRA has deviations | [[safety-critical-coding-standards]] | **disagree.** Robert has twice chosen no override (Q16; 13 Sep). MISRA's tighten-only ratchet is already Mo's. A deviation record is an escape hatch by another name. What Mo takes is a ledger: any program a law blocks, as opposed to a missing row, is recorded as a Q16 event. Zero across four programs and four rounds. |
| A pure, no-`while` shape carries a measured error-rate risk | [[language-design-for-llms-evidence]] | **test.** Round 4's loops (Mo 5, Go 1, Python 0) are consistent with the risk and every one was a grammar first guess. Round 5 counts loops by cause after the ergonomics step. |
| Agents may write a Mo generator instead of Mo | [[language-design-for-llms-evidence]] | **agree.** Round 5 records whether each worker wrote Mo directly. So far every round did; the worktrees hold the evidence. |
| Deadlines should be inherited and tightened, not restated per call | [[reliability-and-testing-philosophies]] | **test.** The law stays: every call that can wait carries `within:`. Program 1 counts the deadlines it writes and how many are derived from an enclosing one. If literals lie, an inherited budget is designed then. |
| Annotated non-terminating loop instead of a ban | [[safety-critical-coding-standards]] | **agree, already in Mo.** Ravenscar's "all tasks are non-terminating" is a Mo process under step 20's runtime: the runtime loops, the process never does. |
| Drop the nine-nines claim | [[reliability-and-testing-philosophies]] | **agree.** [[erlang]] cited it until 17 Sep 2026, when the number was struck there; no other Mo page outside the raw runs does. Rule: Mo's materials cite Erlang's practice and scale, never the number. |
| Bounded loops need a real termination argument; `while` ban satisfied by a fake constant | [[author-edsger-dijkstra]] | **agree, done in step 20** for loops. For recursion chapter 2 still promised "structural only, proved terminating", which the toolchain never did: it bounds depth at 10,000 and crashes. The chapter now says what is true; termination is `mo prove`'s obligation. |
| The `verified:` line implies proof from tests | [[author-edsger-dijkstra]] | **disagree.** The line's vocabulary already names each obligation and prints `proven: not run` beneath it. |
| R6 stable storage is unanswered | [[author-joe-armstrong]] | **agree that it must be named.** Chapter 3 already answers it: restart recovers the service, never the state; a process whose state must outlive a crash writes through a capability and replays on start; the store recipe is the pattern. Chapter 3 now names R6. Program 1 is the test. |
| Message passing is unreliable in Erlang; Mo's sends crash on overflow | [[author-joe-armstrong]] | **disagree.** Inside one program a send is reliable or a bug. Across a socket it is unreliable, and `--faults` injects `Closed`, `Timeout`, and `Idle`. Mo has no distribution ([[d08-beam-qualities-without-the-beam]]). |
| A 500-line file law re-imposes the module placement problem | [[author-joe-armstrong]] | **disagree.** The unit of identity is the declaration ([[d29-edit-by-declaration-id]]); the file is a formatter concern. No round or program moved a function for the law. |
| Source-level scrutiny cannot establish trust; Mo inherits Zig and C | [[author-ken-thompson]] | **agree.** [[d03-source-carries-its-evidence]] is about programs, not the toolchain. Reproducible builds of `mo` and of `mo build`'s binaries become a release requirement, measured tonight (below), before any registry. |
| Large-system help is interfaces and dependency structure, not caps | [[author-dennis-ritchie]] | **agree, already in Mo.** `expose` lines, capability parameters, no import cycles, and recipes are the structure; the caps bound review, not systems. Program 1 is the first service large enough to tell. |
| "There is no escape" | [[author-brian-kernighan]] | **disagree, Robert's call.** The platform is the escape. The Q16 ledger above is what would reopen it. |
| Only the user should introduce inefficiency; intent at every level | [[author-tony-hoare]] | **disagree on the first, Robert's call;** step 21 re-measures the contract cost. On the second, bodies may hold `assert` and every module may hold `never`; the altitude fixes what a human reads, not what an agent may write. |

## What changed tonight

- Chapter 2's recursion line: "structural only, proved terminating" became a depth bound of 10,000 and a crash, with termination named as `mo prove`'s obligation. The toolchain had done this since step 18; the spec was the lie.
- Chapter 3 names Armstrong's R6 beside "What restart means".
- Three rules, each a decision-log row: the Q16 ledger, the nine-nines rule, and reproducible builds as a release requirement.
- Round 5's protocol gains two columns: loops by cause, and whether the worker wrote Mo directly.
- Program 1's brief gains a count: `within:` literals written, and how many derive from an enclosing deadline.

## Reproducible builds, measured

Two builds of `mo` from the same tree with separate Zig caches and global caches, then `kv` built once by each `mo`, compared by SHA-256.

| artifact | result |
|---|---|
| `kv.c`, `mo_rt.c` emitted by the two `mo` binaries | identical |
| the `kv` binary from each | identical |
| the two `mo` binaries | differ in 114 bytes: the Mach-O `LC_UUID` and the ad-hoc code signature it feeds; no path is embedded |

So `mo build` is reproducible today, and `mo` itself is reproducible up to the macOS linker's UUID, which is not the toolchain's doing. A Linux static build is expected to be byte-identical and is measured at the registry step, when reproducibility becomes a release gate.

## What the pages strengthen, taken without a row

The dependency closure of a declaration as the unit of context an agent gets, not the file (the composition frontier at two to five dependent functions is exactly program 1's shape); hand-written diagnostics beating generated ones; the reachability obligation for fault tests, which `MO0327` and `--until` already are; shrinking a failing `--sim` seed as a tier 3 item; the feature-cost ledger Wirth and Hoare both ask for, which the decision log's `semantic` rows are becoming.

## Related
- [[prompts-research-agenda-2026-09]]
- [[outside-review-2026-09-13-response]]
- [[control-run-4]]
- [[empirical-validation-plan]]
- [[decision-log]]
- [[q16-escape-hatch]]
- [[d17-mandatory-deadlines]]
- [[interpreter-step-20]]
