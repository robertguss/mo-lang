---
title: "Mo vs Bend2: borrow the proof workflow, not the whole calculus"
created: 2026-09-19
updated: 2026-09-19
type: comparison
tags: [research, languages, verification, compiler, agents, runtime]
sources: [raw/articles/bend2-guide-2026-09-19.md, raw/articles/bend2-source-inspection-2026-09-19.md, raw/articles/bend2-local-checks-2026-09-19.md, raw/articles/bend2-mutation-control-2026-09-19.md]
confidence: medium
---

# Mo vs Bend2: borrow the proof workflow, not the whole calculus

**Hermes research, requested by Robert.** Recommendation: borrow protected obligations, version-matched learning, goal-shaped feedback and transparent verification status first. Study selective ownership/reuse later. Do not redirect Mo into a GPU-first dependent-type language. These are proposals, not language decisions or implementation authorization.

**Revisions:** Bend `15ae0c86f3193b8f645b4bedbc438655b648d0da`, reporting `2.0.16`; Mo `4f2e4154f00f395f88de049287daac6665474d91`. Separate source checkout; no Bend or Mo implementation changes. This is research informed by Mo's current handoff/decisions and prior audit exposure, **not a cold audit**. Mo's current priority is the agent feedback loop and the in-progress harness/Exec work, not the suspended program-7 superiority experiment. Named worker branches in the handoff were not inspected; recommendations refer to accepted main.

## What Bend2 actually is

The old landscape entry about Bend/HVM is stale for this repository. Bend2 is a new affine, dependently typed language with ordinary definitions as proofs, C/JavaScript compilation, and CPU/GPU machinery. Its README explicitly says Bend1 programs and HVM do not carry over; the runtime paper says there are no interaction nets here.[1][2][12] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

*Dependent types* let a type express a proposition about values. A proof is a program inhabiting that proposition. *Affine* means an owned value may be consumed at most once; Bend permits explicit reuse for eligible `Data`. Neither concept alone means all application behavior is correct.[2][11] ^[raw/articles/bend2-guide-2026-09-19.md]

Its most relevant overlap with Mo is not parallel compute: it explicitly targets AI-authored code constrained by mechanically checked requirements. That makes it a useful comparator for [[01-premise]], even though its proof-oriented language and Mo's capabilities/process/runtime-contract architecture differ substantially.[1][14] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

## Ranked ideas to borrow

### 1. Protected requirements plus mandatory evidence closure — highest value

Bend keeps owner-written `LAWS.bend` separate from agent-written `PROOF.bend` and program code. The CLI requires a sibling laws file to be imported and rejects remaining TODOs/open claims (`main.ts:522–540`). The separation is more concrete than “ask the agent to obey the spec.” However, file ownership is a workflow convention, not an access-control guarantee enforced by this import check.[2][3] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

The sort demo states **both** sortedness and preservation of every element's occurrence count (`LAWS.bend:7–17`). Merely requiring sorted output would allow an implementation that discards everything. This is an excellent example of reviewing specification adequacy, not just trusting a green checker.[7] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

**Mo adaptation:** reuse the existing protected-verifier direction rather than inventing a new `law` keyword. Each task should bind an owner-approved requirements bundle to its exact hash and list every required obligation. Agent edits change bodies and candidate evidence, not the goalposts. Omitted, changed, failed or unexecuted obligations must prevent acceptance. Evidence kinds can initially be tests, simulation and runtime-contract checks; none should be labelled universal proof.

This strengthens an existing Mo rule: verification chapter 5 already separates evidence tiers and prohibits an agent from weakening contracts/tests while changing the body. The work is enforcing and reporting that distinction end to end, not claiming Bend invented a missing Mo principle.[14]

**Proposed first test:** one normal maintenance task, with deliberate omitted-test and changed-contract controls. Measure independently accepted behavior, rejected invalid submissions, repair turns and total cost. Do not begin a new experiment merely because this recommendation exists.

### 2. Ship a small, queryable language manual with the executable

`bend guide`, `bend base --types`, and `bend base Map` expose the installed language's own guide and library surface (`main.ts:112–119,367–393`). The last command actually worked in the local check; it prints the named declaration family, including helper definitions, so it is not yet an ideal minimal public API answer.[2][3] ^[raw/articles/bend2-guide-2026-09-19.md]

**Mo adaptation:** prioritize the already specified version-pinned guidance: concise `mo guide`, symbol documentation and code-specific diagnostic explanations, generated from the same release as the checker. These names are illustrative proposals, **not existing commands**. The inspected CLI lists `check/test/run/build/fmt/fix`, not these discovery commands. Keep JSON as well as readable prose.[15][16]

The measurable benefit is less agent guessing about syntax, stdlib and failure semantics. Compare cold discovery with a short release-matched guide; count invalid API attempts and tokens to the first valid edit. Avoid requiring the agent to read the entire wiki or compiler.

### 3. Return the unmet goal and the trust status, not just “failed” or “verified”

Bend's equality checker compares both endpoints; named holes show the required goal, while `?TODO` can exist during construction but prevents a successful CLI proof verdict. Diagnostics display expected/observed terms and local context. Separately, the CLI can succeed with `All terms check, with N unsafe annotations` (`bend.ts:3622–3639`; `main.ts:490–500,534–538`).[3][4] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

**Mo adaptation:** build on its existing structured diagnostic vocabulary and toolchain-computed `verified:` line. Return obligation ID, expected condition, observed result, local assumptions, source/compiler/requirement hashes, exercised coverage, and an explicit status such as `tested`, `proven`, `not_run`, `timed_out`, or `requires_trusted_adapter`. Give the agent the smallest actionable next obligation. A timeout is inconclusive, not proof that a proposition is false.[14]

Do not copy a single broad unsafe indicator. Bend's unsafe mode relaxes termination and reusable-binder kind restrictions; its theoretical guarantees also depend on compiler, base-library and effect boundaries. Mo should distinguish those categories and independently decide which are allowed for a task.[4][6][11] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

### 4. Make cross-backend correctness and feedback latency a visible gate

Bend's test files embed expected output as `#|` lines. The gate chooses checking/evaluation/C/JS probes and compares results; backend eligibility varies with Base imports, foreign implementations and printable output (`gates/test.ts:48–95`). This is useful, but “one test passed” does not mean all backends executed.[8] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

**Mo adaptation:** keep its existing interpreter-versus-C differential testing; add a visible per-case execution matrix, exact failure statuses and a small fast gate separate from long stress/simulation work. Track edit/check latency, native compilation, execution and memory separately. This is a strengthening of Mo's chosen architecture, not a recommendation to add JavaScript just because Bend has it.[15]

Borrow benchmark version stamps and correctness checks, not the headline speed claims. Bend's performance gate compares the last nonempty output line against a pin, and its source uses explicit threshold/timing rules; those are not equivalent to complete behavioral equivalence or a confidence interval (`gates/perf.ts:264–280,351–377`).[9] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

### 5. Use ownership facts selectively; study allocation reuse rather than importing global affinity

Bend carries a small use-count algebra: sequential uses add, mutually exclusive branches join, and excessive consumption is rejected (`bend.ts:584–618`). Its C emitter can reuse storage from a consumed constructor of a compatible allocation class (`comp.ts:1056–1076`). These are concrete implementation ideas, not merely functional-language branding.[4][5] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

**Mo adaptation:** inspect whether the existing moves/uniqueness analysis and planned parcel/value distinction can express the needed ownership facts more explicitly. Mo already has last-use analysis and in-place updates, so “add ownership optimization” would be an inaccurate recommendation. A focused experiment could compare current allocation behavior with constructor-spare reuse on one AST/tree transformation, with shared-subtree and failure controls.[15][19]

For capabilities, affine use is not authorization, guaranteed cleanup, or distributed exactly-once execution. Bend's channel rows also use generations to recognize stale handles (`comp.ts:5789–5832`), and its file-read ABI returns the handle alongside success/failure. These are useful boundary patterns to compare with Mo's existing handles, not proof that its supervision/runtime should be replaced.[5][18] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

### 6. Explore proofs for a small pure core, not all of Mo

Bend's source-order/decreasing-self-call discipline and ordinary typed proof definitions make a small formal core plausible. But the paper says conversion is a semi-decision procedure: checking can hang, and a hang is inconclusive. Its Lean source explicitly says it does not fully match the implementation; parser/flattening/imports, unsafe and native/foreign boundaries are not comprehensively verified by the calculus model (`bend.lean:1–7,76–110`). No Lean rebuild was performed here.[4][6][11] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

**Mo adaptation, later:** choose a pure state transition, parser invariant or capability-related IR invariant and compare bounded checking/property tests with optional proof evidence. Keep the proof tool outside the normal build path until its benefit is measured, consistent with [[d32-proving-is-a-separate-tool]]. A proved model also needs an explicit connection to the code that actually runs. Do not call a pure response-function proof a verified HTTP server.[14]

Proof-generation effort, additional annotations and unfamiliar syntax are real costs. Bend lacks tactics/proof search and constrains closures and computed matches; those restrictions are a poor default import into Mo's simple application language.[1][2] ^[raw/articles/bend2-guide-2026-09-19.md]

## What not to copy now

- **The GPU/cube scheduler as Mo's main runtime.** Bend's model favors explicitly balanced pure fork/join work; the runtime paper says it does not repair unequal splits by work stealing, CPU/GPU do not compute concurrently, CUDA was not measured in that paper, and the C runtime is unverified. This is not an actor supervision or irregular agent-I/O scheduler.[12] ^[raw/articles/bend2-source-inspection-2026-09-19.md]
- **“Proofs mean bug-free apps.”** Proofs address the formalized properties under their assumptions. Inadequate requirements, compiler/runtime errors and environmental effects remain. Bend's own README discloses compiler immaturity and a Lean/implementation mismatch.[1][6] ^[raw/articles/bend2-source-inspection-2026-09-19.md]
- **Global no-inference/affine restrictions, tiny numeric palette or linked-list strings.** Bend explicitly lists these tradeoffs, including Nat/U32/F32 only and slow text processing. They do not automatically fit Mo's service/harness workloads.[1] ^[raw/articles/bend2-source-inspection-2026-09-19.md]
- **Arbitrary token limits as correctness laws.** Its repository gate caps source tokens and allowed paths. Use this as inspiration for bounded agent learning/context packs, not a mandate to compress readable code or delete expensive tests.[13] ^[raw/articles/bend2-source-inspection-2026-09-19.md]
- **A new package ecosystem.** Content-hash imports are useful identity mechanisms, but a hash does not establish safety or correctness. Mo already has its own recipes and provenance direction; no ecosystem switch is justified by this inspection.[2] ^[raw/articles/bend2-guide-2026-09-19.md]

## What was actually exercised

Linux x86_64, Bun 1.4.2, Bend 2.0.16 at the pinned source. Telemetry was disabled. The original insertion-sort proof returned `All terms check.`; pure evaluation, emitted JS on Node and emitted C compiled through Zig 0.16.0 `cc` all printed `[1n, 2n, 3n]`. The C route was a backend smoke check, not Bend's normal Clang-discovery build. ^[raw/articles/bend2-local-checks-2026-09-19.md]

The copied project with an empty proof rejected two open claims. A proof omitting sibling laws was refused. A syntactically valid attempt to prove `0n == 1n` failed with expected/observed endpoints; an earlier typo had only produced a parse error and is preserved separately. The corrected main run records 13 commands; this is not a full test-suite pass count. ^[raw/articles/bend2-local-checks-2026-09-19.md]

A supplementary scratch-copy edit made sorting return an empty list. Its unchanged proof failed first at `LAWS.sort_sorted` because that proof no longer matched the new implementation. This demonstrates old-proof invalidation for that edit; it is **not** an observed rejection specifically at the permutation law or an audit of logical soundness. ^[raw/articles/bend2-mutation-control-2026-09-19.md]

No GPU runs, cluster gates, live networking, Lean build, or comparative performance replication were performed. The repository's current M4 Max pin, for example, records hashmap sequential Bend at 2.741s versus C at 0.622s, and queens GPU at 0.933s versus parallel CPU at 0.455s. These author-recorded rows make the tradeoffs clearer than a universal “as fast as C/faster on GPU” summary; they are not measurements made here.[17] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

## Recommendation for Mo's current work

After the already queued correctness and runtime work, prioritize **version-matched discovery and obligation-level acceptance receipts** in the existing harness. These offer the most plausible improvement to the agent's learn/edit/check/repair loop without new language theory. Treat optional proof islands and additional allocation reuse as bounded later research. Retain the existing runtime, capability and independent-verification strategy until a matched experiment supports changing it.

Bend is Apache-2.0. Borrow ideas freely; any source reuse should retain the required license/notices and mark modifications. No Bend implementation was copied into Mo's compiler or runtime; the raw research bundle contains attributed inspection excerpts and the license.[10] ^[raw/articles/bend2-source-inspection-2026-09-19.md]

## Activity and validation

Robert's manually requested research; isolated `research/bend2-20260919` branch. Initial wiki lint: 281 pages, 26 inherited notices (15 review, 11 size). Final lint: 282 pages, the same 26 notices, no new issues. Citation ledger validation passed. Authored prose passes the staged whitespace check; two trailing-space notices in verbatim Lean-source excerpts are intentionally preserved, not normalized. Source snapshots carry body hashes; local checks and caveats are retained. No changes to specs, decisions, roadmap, log, audit readings or implementation. Final validation/publication is recorded in the PR; no automatic merge or audit intake.

## Related

- [[language-landscape]]
- [[agent-native-research-synthesis]]
- [[d32-proving-is-a-separate-tool]]
- [[05-verification]]
- [[07-toolchain]]
- [[roadmap]]

## Sources

[1] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/README.md
[2] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/guide/GUIDE.md
[3] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/main.ts
[4] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/bend.ts
[5] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/comp.ts
[6] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/bend.lean
[7] https://github.com/bendlang/bend/tree/15ae0c86f3193b8f645b4bedbc438655b648d0da/demos/proof_insertion_sort
[8] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/test.ts
[9] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/perf.ts
[10] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/LICENSE
[11] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/docs/BendTT/main.typ
[12] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/docs/BendRT/main.typ
[13] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/repo.ts
[14] https://github.com/robertguss/mo-lang/blob/4f2e4154f00f395f88de049287daac6665474d91/mo-wiki/spec/design-v0/05-verification.md
[15] https://github.com/robertguss/mo-lang/blob/4f2e4154f00f395f88de049287daac6665474d91/mo-wiki/spec/design-v0/07-toolchain.md
[16] https://github.com/robertguss/mo-lang/blob/4f2e4154f00f395f88de049287daac6665474d91/toolchain/src/main.zig
[17] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bench/runtime/_pin_/apple_m4_max.txt
[18] https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/effs/file_read.c
[19] https://github.com/robertguss/mo-lang/blob/4f2e4154f00f395f88de049287daac6665474d91/toolchain/src/moves.zig
