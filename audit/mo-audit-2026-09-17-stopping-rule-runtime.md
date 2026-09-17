# Audit deliverable: a stopping rule for the runtime and process model

**Date:** 17 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** as accepted by Robert 17 Sep 2026; the auditor does not design, execute, or accept work, only reads evidence and files readings for the decision log.
**Status:** draft for Robert. Fable's parallel draft, if written, is to be read alongside this one and not before it.
**Purpose:** state, before program 7 runs, what evidence would confirm and what evidence would refute the project's **primary** thesis claim — that Mo's runtime and process model delivers reliability that existing runtimes (specifically the BEAM) cannot be retrofitted to deliver.

---

## Robert's ratifications, 17 Sep 2026

Ratified in-session on 17 Sep 2026, before program 7 exists. Any change to the below is a decision-log row with a stated reason.

- **R1, R2, R3, R5, R7:** as written.
- **R6:** as written, **no token budget.** The rule is now a ceiling-of-capability test (can the runtime surface produce a correct diagnosis given room to reason?), not a production-realism differentiator. Auditor's flag: if R6 clears, we will not know from R6 alone whether Mo's surface is *better* than Elixir's or just *sufficient*; the sharpest differential test moves to program 8 or a follow-up.
- **R4:** as written.
- **Tier-1 clearing threshold:** 4 of 5 reliability rows (R1, R2, R3, R5, R6).
- **RC1, RC2, RC3, RC4:** all as written.
- **Retirement mapping** (severity-graded, committed in advance):

  | Outcome | Retirement |
  |---|---|
  | ≤ 2 reliability rows clear | **S-A** — full retirement |
  | 3 reliability rows clear, OR any cost row red | **S-B** — scoped retirement, name the domain |
  | Exactly 4 reliability rows clear, no cost row red | **S-C** — provisional, program 8 gates |
  | All 5 reliability rows clear, no cost row red | claim vindicated |

- **Workflow requirement:** Fable drafts a parallel independent reading of program 7's numbers against this rule and files it alongside the auditor's before Robert reads either. Disagreements become decision-log rows.
- **Roadmap ordering (auditor's separate finding, M-3 accepted):** the bricks page ships first, then the generation-4 speed-loss probe, then program 7. Program 7 moves from #6 to #3 on the roadmap's "Next, in order."

---

## 0. Why this is the important pre-registration

The pivot of 14 Sep 2026, held across `01-premise.md`, `state-of-the-project.md`, and `10-language-after-the-rounds.md`, ranks the thesis's three layers by how much they carry:

1. **Runtime and process model** — where reliability comes from.
2. **Capabilities and recipes** — where zero dependencies comes from.
3. **The language** — surface for the first two.

This document binds **layer 1**. The `never`/`invariant` rule binds layer 3. The capabilities/recipes rule binds layer 2. Read all three; this one is the load-bearing one.

Chapter 1 already names the null hypothesis for this layer:

> The BEAM with Elixir already gives most of Mo's runtime advantages (isolated processes, supervision, a mailbox per process, hot code loading, a live shell into a running system), and the delta Mo adds (static types at every boundary, capabilities that cannot be forged, a deadline on every wait, one static binary, no package ecosystem to trust, an agent-facing runtime surface) does not justify a new language. This is the objection an OTP reader raises first, and it is the one program 7 must answer.

Program 7 is the pre-registered test. It sits at #6 on the roadmap's "Next, in order" list, behind the change-6 probe, step-34 follow-up, chapter-10 sections, the bricks page, and the compile benchmark. If runtime is the primary claim, program 7's rank on the roadmap is inverted; that is a separate finding for §11 below.

---

## 1. What "the runtime claim" actually is, made specific

Loose statements of "Mo's runtime is better" fail the same two ways the language claim failed: promising too much or nothing. The claim as it must be read is a **conjunction**:

**The Mo runtime and process model deliver, on a program that exercises them (program 7 or a program of similar shape), a measurable advantage over Elixir/OTP on the same program on at least one of the following dimensions, and no measurable deficit on the others, at similar maintainer cost:**

- **R1: Reliability under a hidden adversarial defect suite.** Mo's defect count is at least as low as Elixir's, ideally lower, on a suite of ≥ 50 hidden defects designed to press on failure semantics (crash-consistency, restart, deadlines, mailbox overflow, capability confinement).
- **R2: Recovery under injected faults.** Under `--faults P --until F` at rates that press the supervisor, Mo's mean-time-to-recovery is at least as short as Elixir's, ideally shorter. Measured on a program with a durable state store and a supervised worker tree.
- **R3: Honest supervision.** No Mo program under test can be put into a "wait no law bounds" state (the outage class from round 8). Round 8's defect must not reproduce under Mo's chapter 10 §1 fix on a program shaped like program 7's.
- **R4: Runtime honesty vs. instrumentation.** The `verified:` line and MO0317 track *actual* verification status on program 7; no `verified:` line is stale by more than one build across 100 sequential edits.
- **R5: Bounded replay.** A crashed process replays to the same state on the same seed, byte for byte, in 100/100 replays across program 7's states.
- **R6: The runtime surface (`platform.runtime`) is queryable and load-bearing.** An outside diagnostic session, using only `platform.runtime` and the crash store, can produce a correct root-cause reading for at least 8 of 10 injected faults on program 7. No token budget: the test measures whether the surface *can* produce the correct diagnosis given room to reason, not whether it does so under production time pressure.
- **R7: One static binary.** Program 7 ships as a single native binary of ≤ 50 MB, boots in ≤ 500 ms cold, and needs no runtime installation on a bare Linux image.

**Costs (bounded, not maximized):**

- **RC1: Maintainer time.** Program 7 takes no more than 2× the maintainer minutes to write in Mo as in Elixir, measured in Herdr session time from empty repo to first passing hidden suite.
- **RC2: Speed on the hot path.** Mo's throughput on program 7's core operation is within 0.7× of Elixir's, and Mo's p99 latency is within 1.5× of Elixir's, under the same load rig.
- **RC3: Memory.** Steady-state RSS is within 2× of Elixir's; peak RSS under load is within 3×.
- **RC4: Runtime dependencies.** Zero — a hard row, must be zero third-party runtime packages.

The reliability wins in R1–R7 must be real, and none of RC1–RC4 may fail badly, for the runtime claim to clear.

---

## 2. What the record shows today, 17 Sep 2026

- **R1 (defects on hidden suites).** No program has yet been measured on a runtime-heavy hidden suite of ≥ 50 defects; the current suites are ≤ 30 defects each, and change 2's outage was found by P6, not by a suite. **Status: not yet tested.**
- **R2 (recovery).** Change 3 sealed with the store restarting itself, "the queue killed under load back in 106 ms, the BEAM's row answered" — a positive data point of one, at a smaller scale than program 7 will be. **Status: single data point, positive.**
- **R3 (honest supervision).** Round 8's outage: the deadline law was satisfied but the service was down. Chapter 10 §1 (deferred reply) landed as step 31 and closed the outage on the same change 2 program. **Status: one class of outage found, one class fixed, no independent verification of the fix on a different program.**
- **R4 (runtime honesty).** MO0317 lands at 6/7 first-fix-right on the corpus; the `verified:` line is being checked at build. **Status: strong evidence from the diagnostic side, no long-lived program has yet stressed the drift budget.**
- **R5 (bounded replay).** Chapter 3 says "every process is replayable from a snapshot plus its message log … replay is exact." No adversarial replay suite has been run. **Status: claimed, not tested at N=100.**
- **R6 (runtime surface).** P6's own performance is the test surrogate today. P6 on change 2 read the outage from the surface and named its cause. **Status: n=1, positive, but Fable is running the probe.**
- **R7 (single binary).** Present. The C backend produces static binaries; step 34 measured at 14 cores. **Status: cleared, subject to program 7's specific size and boot numbers.**

The auditor's summary: the runtime claim has **stronger evidence than the language claim** but **less pre-registered evidence than the language claim**. The rounds and erosion generations pressed on language checks; the runtime layer has been pressed only incidentally, by control run 8 and P6.

---

## 3. The proposed stopping rule

The rule below is stated as **the pre-registration for program 7**. It should be filed before program 7's first commit and read against program 7's final state.

### Tier 1 — reliability wins (R1, R2, R3, R5, R6)

**Program 7, once written and hardened, shall clear at least 4 of 5 reliability rows against an Elixir/OTP counterpart written by the same model at similar cost.** Specifically:

- **R1 clear:** Mo's defect count on a hidden suite of ≥ 50 defects is ≤ Elixir's, with a margin of at least 3 defects OR Mo is at parity with a demonstrated advantage class (e.g., Mo catches ≥ 2 defects Elixir cannot state).
- **R2 clear:** Mo's MTTR on `--faults 0.05 --until 0.5` is ≤ 1.2× Elixir's MTTR.
- **R3 clear:** Round 8's outage class does not reproduce in Mo. An adversarial "wait-no-law-bounds" probe (10 shapes: batched reply, chained ask, mutual send/wait, timer-driven wait, etc.) finds ≤ 1 case in Mo where a wait is un-bounded.
- **R5 clear:** 100/100 replays of program 7's state on the same seed produce byte-identical state.
- **R6 clear:** An outside session (no token budget) correctly names the root cause of 8/10 injected faults using only `platform.runtime` output.

**If 3 or fewer rows clear:** the runtime claim fails against the BEAM. This is the project-changing finding chapter 1 flags.
**If exactly 4 clear:** the runtime claim clears with a caveat; the failed row is a pre-registered follow-up.
**If all 5 clear:** the runtime claim is vindicated on program 7. The claim generalizes to other programs only under future evidence.

### Tier 2 — honesty and surface (R4, R6, R7)

**No advantage claimed in Tier 1 shall depend on the maintainer's instrumentation.** Concretely:

- **R4 clear:** the `verified:` line's drift budget (see §4 below) does not blow across 100 edits.
- **R6 clear:** the diagnostic in R6 uses no code the Mo maintainer wrote for the diagnostic — only the platform's surface. If the maintainer wrote custom logging that a diagnostic needs, R6 fails.
- **R7 clear:** the single binary is real (≤ 50 MB, ≤ 500 ms cold boot, no libc surprises).

**If any of R4, R6, R7 fail:** the runtime claim is downgraded from "delivers reliability the BEAM cannot" to "matches the BEAM's reliability with better tooling," which is a different claim.

### Tier 3 — cost bounds (RC1–RC4)

**No cost row shall blow badly.**

- **RC1 clear:** Mo maintainer time on program 7 ≤ 2× Elixir maintainer time. If between 2× and 3×, the rule is amber (see below); if > 3×, the unfamiliarity tax kills the claim regardless of Tier 1's outcome.
- **RC2 clear:** throughput within 0.7×, p99 within 1.5×. If between 0.5× and 0.7× throughput, amber; below 0.5×, red.
- **RC3 clear:** steady-state RSS within 2×, peak within 3×.
- **RC4 clear:** zero third-party runtime packages.

**All-red on any RC:** the runtime claim is retired (see §5). **Amber on any two:** the claim is under review, and the fix must land before generalization.

---

## 4. Definitions the rule depends on

- **"The same model."** The Mo maintainer and the Elixir maintainer are separate Herdr sessions of the same model (probably Sonnet or Opus, whichever is current) with matched context: same problem spec, same hidden suite (post-hoc), same load rig, same fault budget. Cross-model runs (Haiku, GPT, Gemini) are follow-up evidence and do not clear or fail this rule.
- **"The hidden suite."** ≥ 50 defects, written by Fable (or by a session Fable spawns) *before* seeing program 7's implementation, and not shown to the maintainer. Suite composition: 15 crash-consistency, 10 restart semantics, 10 deadline/mailbox edge cases, 10 capability confinement (see the capabilities audit for exactness), 5 replay determinism.
- **"The drift budget."** From build B to build B+1, `verified:` on a declaration shall reflect whether that declaration's verification obligations passed on B+1's toolchain state. Drift means `verified:` says yes when the current build's checker says no (stale-verified). MO0317 is the mechanism that keeps drift ≤ 1 build behind reality.
- **"The load rig."** A single machine (Robert's Mac at 14 cores today; a Linux VM for the reproducibility run), fixed load generator, warm-up window, measurement window, three trials, report median. Same rig for both languages.
- **"The fault rig."** `--faults P --until F` inside Mo's `Mo.Sim`, and an Elixir-side equivalent that injects faults at the same rate on the same actions (process crash, message drop, network partition, disk full).

---

## 5. What "retires" means for the runtime claim

If the rule fires, three options exist; Robert picks one before program 7's numbers are read.

**S-A: The runtime claim retires entirely.** The project's primary thesis fails against the BEAM. Chapter 1 is rewritten to say "the BEAM already delivers most of what Mo aimed for at the runtime layer; Mo's remaining value is the toolchain, the `verified:` discipline, and the zero-dependency stance." The language and the runtime as delivery mechanisms for reliability are no longer defended; the project pivots to being a *supply-chain-hardened Elixir* or is wound down.

**S-B: The runtime claim retires to a scoped domain.** The claim survives for a specific class of program (say, batch replay-oriented state stores) but not the general reliable-service claim. Program 7 becomes a demo of the scoped claim; the general claim is retired.

**S-C: The runtime claim survives with a stronger pre-registration.** If exactly 4 of 5 reliability rows clear, the claim is provisional and a second program (program 8, a different shape) is written under a new pre-registration to see if the win generalizes.

**Auditor's honest reading.** S-A is a real possibility on the current evidence. The BEAM has been in production for 40 years; Mo has been running for 5 days. If program 7 does not show a substantial delta on at least 2 of the 5 reliability rows, the honest response is S-A. Robert should be prepared for this.

---

## 6. What the rule does *not* bind

- **Non-BEAM baselines.** This rule is Mo vs. Elixir/OTP because that is the null hypothesis chapter 1 names. A Mo-vs-Go or Mo-vs-Rust runtime comparison is a separate claim.
- **The IDE, the LSP, or the `mo` CLI.** Toolchain quality is measured elsewhere.
- **The language layer's own catch claim.** That is the `never`/`invariant` rule.
- **The capability/recipe claim.** That is the capabilities rule, and importantly, program 7's zero-dependency achievement is measured *there*, not here.
- **Adoption or ecosystem.** Program 7 is a pilot, not a product.

---

## 7. When the rule is evaluated

- **Before program 7's first commit:** the hidden suite is written and sealed by Fable; the load rig and fault rig are set up on identical footing for both languages; both maintainer sessions are given the same spec.
- **After program 7's final Mo commit:** the hidden suite runs; MTTR, throughput, RSS, and cold-boot are measured; the R6 diagnostic session runs.
- **After Elixir program 7's final commit:** same measurements.
- **The reading:** the auditor produces the ledger for R1–R7 and RC1–RC4, files `audit/mo-audit-YYYY-MM-DD-program-7-reading.md` in this directory, before Fable's reading is filed. Robert reads both and picks S-A, S-B, or S-C if the rule fires.

---

## 8. What clears the rule, made concrete

A clean win looks like:

- Mo catches 48/50 hidden defects; Elixir catches 43/50; Mo catches 3 defects (a torn-line write, a mailbox-overflow-on-batch, a supervisor-restart-with-live-clients timing) that Elixir cannot state without instrumentation. R1 clears with margin.
- MTTR: Mo 850 ms, Elixir 780 ms. R2 clears (1.09×).
- Adversarial wait probe: 0 outages in Mo, 2 in Elixir. R3 clears.
- 100/100 replays byte-identical. R5 clears.
- Diagnostic session: 9/10 root causes correct in Mo, 6/10 in Elixir. R6 clears.
- Maintainer time: Mo 4h 20m, Elixir 2h 40m. RC1 clears (1.6×).
- Throughput: Mo 92% of Elixir; p99 Mo 1.3× Elixir. RC2 clears.
- RSS: Mo 60 MB steady, Elixir 45 MB. RC3 clears.
- Zero deps. RC4 clears.
- Single binary 42 MB, cold boot 380 ms. R7 clears.

Under that outcome, chapter 1's primary claim is vindicated and program 8 becomes the generalization test.

---

## 9. What retires the rule, made concrete

The version where the rule fires:

- Mo catches 42/50 defects; Elixir catches 44/50. R1 fails.
- MTTR: Mo 1.8 s, Elixir 780 ms. R2 fails (2.3×).
- Adversarial wait probe finds 3 outages in Mo. R3 fails.
- Diagnostic session: 5/10 root causes correct in Mo. R6 fails.
- Maintainer time: Mo 8h, Elixir 2h 40m. RC1 red (3×).

Four of five reliability rows fail; the unfamiliarity tax is > 3×; the rule fires and S-A is the honest response.

The auditor thinks (17 Sep 2026, before program 7 exists) that the most likely outcome is *between* these — probably 3/5 reliability rows clear, RC1 lands at 2.5×, R6 is the clearest Mo win because `platform.runtime` really is novel-in-combination. That would be S-C territory: provisional survival, need program 8.

---

## 10. Auditor's honest priors

Recorded 17 Sep 2026, before program 7:

- **~0.30 chance:** clean S-C win (3/5 reliability rows clear, RC1 in 2×–3× range, R6 clearest advantage).
- **~0.25 chance:** clean S-B outcome (Mo wins on replay-heavy programs, ties elsewhere; scoped claim survives).
- **~0.20 chance:** S-A honest retirement (Mo does not out-reliable the BEAM on a service program; the delta chapter 1 names is not there).
- **~0.15 chance:** clean win, all Tier 1 rows clear (chapter 1's optimistic scenario).
- **~0.10 chance:** something the auditor cannot predict, probably tooling-shaped (a Zig-VM behavior program 7 exposes that neither team knew existed).

Sum > 1 by 0.0 (checked). These are non-independent probability estimates over disjoint outcomes.

---

## 11. Auditor's flag on roadmap ordering

Program 7 is currently ranked #6 on the roadmap's "Next" list, behind:
1. Generation-4 speed-loss probe (relevant but scoped)
2. Step-34 placement follow-up (perf, scoped)
3. Chapter 10 §2/§3/§5 as steps (language-layer, less important post-pivot)
4. The bricks page (documentation)
5. Compile benchmark at 5,000 modules (scoped)
6. **Program 7 (the primary claim's pilot)**

**Auditor's reading:** if runtime is the primary claim of the project's restated thesis (14 Sep pivot), and program 7 is the pre-registered test of that claim, ranking it sixth is inconsistent with the thesis restatement. Chapter 1 says "program 7 must answer" the BEAM null hypothesis. Every day program 7 waits, the project is running erosion generations on the language layer whose claim has already been effectively downgraded, while the runtime claim goes untested.

**Auditor's recommendation:** move program 7 to #1 or #2 on the roadmap, before more erosion generations. The current ordering is a legacy of when the language was the thesis; the pivot has not been reflected in what work happens next. This is exactly the drift the auditor role exists to flag.

---

## 12. The rule in three sentences

1. If, after program 7 is written in both Mo and Elixir under matched conditions, at least 4 of 5 reliability rows (R1, R2, R3, R5, R6) clear at their thresholds and no cost row (RC1–RC4) blows red, the runtime claim is vindicated as the project's primary thesis.
2. If 3 or fewer reliability rows clear, or any cost row blows red, the claim retires under S-A, S-B, or S-C at Robert's choice.
3. The pre-registration — the hidden suite, the load rig, the fault rig, the diagnostic protocol — must be sealed by Fable before either program's first commit, and the reading is filed by the auditor before Fable's reading is read.

---

## 13. What the auditor asks of Robert

Four things:

1. **Accept, amend, or reject the rule.** If amended, name the specific numeric changes; a rule with adjectives is not a rule.
2. **Choose whether to move program 7 up the roadmap.** The auditor's flag is a finding, not a decision. Robert's call.
3. **Choose S-A, S-B, or S-C in advance** (or defer explicitly). Deferring is fine, but should be a written decision.
4. **Confirm Fable will draft a parallel reading** of these thresholds independently, filed alongside.

The auditor does not need Fable's answers to any of this before program 7 starts. But the pre-registration must exist before program 7's first commit; that is when the rule binds.

---

## 14. Related pages

- `audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md` — the language-layer rule.
- `audit/mo-audit-2026-09-17-stopping-rule-capabilities.md` — the capabilities/recipes rule.
- `mo-wiki/spec/design-v0/01-premise.md` — the thesis and the BEAM null hypothesis.
- `mo-wiki/spec/design-v0/03-semantics.md` — the runtime and process model.
- `mo-wiki/plans/roadmap.md` — where program 7 currently sits.
- `mo-wiki/plans/program-menu.md` — the current program list including program 7's shape.
