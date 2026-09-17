# The audit folder

**What this is.** A separate reviewer role for the Mo project. Fable is the lead — designer, executor, evaluator. The auditor reads the same evidence Fable does, cold, and files an independent reading before Fable's is read. Where the two readings disagree, that disagreement is a decision-log row with equal standing.

**Why it exists.** Pre-registration and hidden suites lose their power when the same agent writes the predictions, runs the rounds, and reads the results. This was the sharpest finding of an outside review of the wiki on 17 Sep 2026 (see `mo-review-2026-09-17.md` in the project files repo, or ask Robert for it). The auditor role is the operational response.

**Who fills the role.** A fresh Perplexity session in the Mo Lang project, invoked by Robert (never by Fable), reading only raw evidence from the repo (never Fable's synthesis). The auditor is model-generated and shares a training distribution with Fable — a stopgap, not a substitute for a human reviewer.

---

## Files in this folder

### The charter

- **[`CHARTER.md`](./CHARTER.md)** — accepted by Robert on 17 Sep 2026. Rules, workflow (Option B: Robert-driven manual), escalation, migration path to a GitHub Actions webhook.

### The three ratified stopping rules

All three ratified in-session by Robert on 17 Sep 2026, before program 7 exists and before generation 6 runs. Each contains a "Robert's ratifications" block at the top.

- **[`mo-audit-2026-09-17-stopping-rule-runtime.md`](./mo-audit-2026-09-17-stopping-rule-runtime.md)** — the primary claim (layer 1: runtime and process model vs. the BEAM null hypothesis). Program 7 is the pre-registered test. Reliability rows R1–R7, cost bounds RC1–RC4, retirement mapping S-A/S-B/S-C.
- **[`mo-audit-2026-09-17-stopping-rule-capabilities.md`](./mo-audit-2026-09-17-stopping-rule-capabilities.md)** — the secondary claim (layer 2: capabilities and recipes, zero third-party runtime dependencies). Program 7 is also the test. Sub-claims P1–P4, retirement mapping T-A/T-B/T-C.
- **[`mo-audit-2026-09-17-stopping-rule-never-invariant.md`](./mo-audit-2026-09-17-stopping-rule-never-invariant.md)** — the residual layer-3 claim (the language's `never`/`invariant` catch a class of bug tests miss). Simplified to single-tier under L-2; R-B fires automatically if the rule fails.

### Standing recommendations (findings from the same session)

- **Roadmap M-3 reordering (auditor's finding, awaiting Fable's response):** the bricks page ships first, then the generation-4 speed-loss probe, then program 7. Program 7 moves from #6 to #3 on `roadmap.md`'s "Next, in order." Chapter 1 names program 7 as the pre-registered test of the primary claim; leaving it at #6 while the runtime claim goes untested is inconsistent with the pivot.
- **Bricks page as prerequisite:** the capabilities rule cannot bind well until chapter 6's shelf boundary is written. Bricks page must ship before program 7's first commit.

---

## How this works, day to day

**Fable's responsibilities under the audit:**

1. For each ratified rule, draft a parallel independent reading of program 7's numbers (runtime, capabilities) and generation 10's ledger (language) — **before** reading the auditor's file for the same subject.
2. File the parallel reading alongside the auditor's, under the same `audit/` folder, with filename `fable-reading-YYYY-MM-DD-<subject>.md`.
3. When Fable's reading disagrees with the auditor's, file a decision-log row citing both files and stating Fable's position. Robert reads both and either amends the rule or lets the disagreement stand as a row.
4. Do not amend a ratified rule silently. Any threshold change is a decision-log row with a stated reason (per the ratification blocks in each rule file).

**When a new audit is needed:**

1. Robert opens a fresh Perplexity session in the Mo Lang project titled `audit: <round-name>`.
2. Robert pastes into that session only raw evidence pointers — pre-registration path, branch names, suite files, defect counts as raw output. **Not Fable's reading.**
3. The audit session reads the repo cold, files `mo-audit-YYYY-MM-DD-<subject>.md` in this folder.
4. Fable's parallel reading is then read alongside, and disagreements become decision-log rows.

**The auditor's outstanding pre-registration work** (must complete before program 7's first commit):

- Runtime hidden defect suite (≥ 50 defects: 15 crash-consistency + 10 restart + 10 deadline/mailbox + 10 capability + 5 replay).
- The wait-probe of 10 shapes for R3.
- The 10-shape capability-abuse suite for P3.
- The 3 drift-bug seeds for P2a.
- The 5 regeneration-drift seeds for P2c.
- The named change-6-style modification for P4.

A fresh audit session will author these when the bricks page lands and program 7 is ready to begin.

---

## For a new session opening this folder

If you are Fable or a fresh Perplexity session and this is your first time reading the audit folder, read in this order:

1. This README.
2. `CHARTER.md` for the role's rules and escalation path.
3. Whichever rule file matches the work you are about to do:
   - Working on program 7's runtime evidence → the runtime rule.
   - Working on program 7's capabilities/recipes evidence → the capabilities rule.
   - Reading the generation 10 ledger → the language-layer rule.
4. If unsure whether your session is authorized to be the auditor: you are not. Only Robert opens audit sessions, and only from a template that gives you raw evidence and no Fable synthesis. Fable's sessions never take the auditor's seat.
